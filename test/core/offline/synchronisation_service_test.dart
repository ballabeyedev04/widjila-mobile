import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/core/offline/base_locale.dart';
import 'package:suivie_chantier_mobile/core/offline/detecteur_connexion.dart';
import 'package:suivie_chantier_mobile/core/offline/file_attente.dart';
import 'package:suivie_chantier_mobile/core/offline/synchronisation_service.dart';

import 'detecteur_simule.dart';

/// Attend qu'une condition devienne vraie, sans dependre d'un delai fixe.
///
/// Les enchainements asynchrones (Stream -> synchro -> recompte) prennent un
/// temps variable selon la machine : un `delayed` fixe rendrait le test
/// instable en integration continue.
Future<void> _attendre(
  bool Function() condition, {
  Duration limite = const Duration(seconds: 5),
}) async {
  final fin = DateTime.now().add(limite);
  while (!condition()) {
    if (DateTime.now().isAfter(fin)) {
      throw StateError('Condition non remplie dans le delai imparti');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

DioException _erreurReseau() => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.connectionError,
    );

DioException _erreurHttp(int code) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.badResponse,
      response: Response(requestOptions: RequestOptions(path: '/x'), statusCode: code),
    );

void main() {
  // `sqflite` cible mobile ; en test on passe par l'implémentation FFI, qui
  // exécute un vrai SQLite en mémoire — donc un vrai comportement de base, pas
  // une simulation approximative.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late BaseLocale base;
  late FileAttente file;

  setUp(() async {
    base = BaseLocale.instance;
    // `BaseLocale` est un singleton : un test qui ferme la base laisserait les
    // suivants avec une connexion morte. On repart donc d'une base FERMEE puis
    // reouverte a chaque test, ce qui garantit leur independance quel que soit
    // leur ordre d'execution.
    await base.fermer();
    await base.viderTout();
    file = FileAttente(base);
  });

  tearDown(() async {
    await base.viderTout();
    await base.fermer();
  });

  Future<String> deposerCreation(String titre) => file.deposer(
        type: TypeAction.creerReserve,
        charge: {'titre': titre},
      );

  group('Synchronisation automatique', () {
    test('tout part dès que le réseau revient, sans action manuelle', () async {
      await deposerCreation('A');
      await deposerCreation('B');

      final detecteur = DetecteurSimule(EtatReseau.horsLigne);
      final envoyees = <String>[];

      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async => envoyees.add(a.charge['titre'] as String),
      );
      await service.demarrer();

      // Hors ligne : rien ne doit partir.
      expect(envoyees, isEmpty);
      expect(service.statut.value.enAttente, 2);

      // Le réseau revient — c'est le SEUL déclencheur, aucun appui utilisateur.
      detecteur.basculer(EtatReseau.enLigne);

      // Le declenchement passe par un `Stream`, puis la synchro enchaine
      // plusieurs `await` (lecture de la file, envoi, suppression, recompte).
      // On attend que le compteur retombe plutot que de parier sur un delai
      // fixe, qui rendrait le test instable selon la machine.
      await _attendre(() => service.statut.value.enAttente == 0);

      expect(envoyees, ['A', 'B']);
      expect(service.statut.value.enAttente, 0);
      await service.arreter();
    });

    test('respecte l’ordre de création', () async {
      // Une photo ne peut pas partir avant la réserve à laquelle elle se
      // rattache.
      await deposerCreation('premiere');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await deposerCreation('seconde');

      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      final ordre = <String>[];

      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async => ordre.add(a.charge['titre'] as String),
      );
      await service.demarrer();

      expect(ordre, ['premiere', 'seconde']);
      await service.arreter();
    });

    test('ne lance jamais deux passes simultanées', () async {
      await deposerCreation('A');

      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      var appels = 0;

      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async {
          appels++;
          await Future<void>.delayed(const Duration(milliseconds: 40));
        },
      );

      // Trois déclenchements quasi simultanés — réseau instable qui bascule.
      final futures = [service.synchroniser(), service.synchroniser(), service.synchroniser()];
      await Future.wait(futures);

      // Sans le verrou, la même action serait envoyée plusieurs fois.
      expect(appels, 1);
      await service.arreter();
    });
  });

  group('Gestion des échecs', () {
    test('une coupure en pleine synchro garde le reste pour plus tard', () async {
      await deposerCreation('A');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await deposerCreation('B');

      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      var appels = 0;

      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async {
          appels++;
          throw _erreurReseau();
        },
      );
      await service.synchroniser();

      // On s'arrête à la PREMIÈRE coupure au lieu de faire échouer chaque
      // action une par une.
      expect(appels, 1);
      expect(await file.nombreEnAttente(), 2, reason: 'rien ne doit être perdu');
      await service.arreter();
    });

    test('un refus métier (4xx) sort du cycle et ne bloque pas la file', () async {
      await deposerCreation('refusee');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await deposerCreation('valide');

      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      final envoyees = <String>[];

      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async {
          final titre = a.charge['titre'] as String;
          if (titre == 'refusee') throw _erreurHttp(400);
          envoyees.add(titre);
        },
      );
      await service.synchroniser();

      // La suivante passe quand même : une action morte ne doit pas bloquer
      // tout le travail derrière elle.
      expect(envoyees, ['valide']);
      expect(await file.nombreEnEchec(), 1);
      expect(await file.nombreEnAttente(), 0);
      await service.arreter();
    });

    test('un 401 reste en attente — la session peut être rafraîchie', () async {
      await deposerCreation('A');

      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async => throw _erreurHttp(401),
      );
      await service.synchroniser();

      // Marquer un 401 comme échec définitif ferait perdre le travail alors
      // qu'une simple reconnexion suffirait.
      expect(await file.nombreEnEchec(), 0);
      expect(await file.nombreEnAttente(), 1);
      await service.arreter();
    });

    test('une erreur serveur (5xx) est retentée plus tard', () async {
      await deposerCreation('A');

      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async => throw _erreurHttp(503),
      );
      await service.synchroniser();

      expect(await file.nombreEnEchec(), 0, reason: 'une panne serveur est passagère');
      expect(await file.nombreEnAttente(), 1);
      await service.arreter();
    });
  });

  // RÉGRESSION : `ReserveRemoteDataSourceImpl` (comme tout datasource passant
  // par `mapDioException`) ne laisse JAMAIS fuir une `DioException` brute —
  // il la convertit en `NetworkException`/`ServerException`/
  // `UnauthorizedException` avant qu'elle n'atteigne ce service. Le groupe
  // « Gestion des échecs » ci-dessus prouve le comportement avec des
  // `DioException` brutes (utile pour un `executer` non standard), mais ne
  // couvre PAS le chemin réellement emprunté en production. Sans ces tests-ci,
  // un service qui aurait cessé de reconnaître `NetworkException` (comme ce
  // fut le cas avant ce correctif) continuerait de passer les tests
  // au-dessus tout en étant cassé pour de vrai.
  group('Erreurs réelles (types renvoyés par les datasources)', () {
    test('NetworkException interrompt la passe comme une coupure réseau', () async {
      await deposerCreation('A');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await deposerCreation('B');

      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      var appels = 0;
      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async {
          appels++;
          throw const NetworkException();
        },
      );
      await service.synchroniser();

      expect(appels, 1, reason: 'la panne réseau doit arrêter la passe, pas enchaîner sur B');
      expect(await file.nombreEnAttente(), 2, reason: 'rien ne doit être perdu');
      expect(await file.nombreEnEchec(), 0);
      await service.arreter();
    });

    test('UnauthorizedException reste en attente — jamais un échec définitif', () async {
      await deposerCreation('A');

      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async => throw const UnauthorizedException(),
      );
      await service.synchroniser();

      // Le rafraîchissement silencieux du jeton a déjà échoué à ce stade —
      // seule une reconnexion débloque, l'action doit survivre pour repartir.
      expect(await file.nombreEnEchec(), 0);
      expect(await file.nombreEnAttente(), 1);
      await service.arreter();
    });

    test('ServerException 4xx sort du cycle sans bloquer la file', () async {
      await deposerCreation('refusee');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await deposerCreation('valide');

      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      final envoyees = <String>[];
      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async {
          final titre = a.charge['titre'] as String;
          if (titre == 'refusee') {
            throw const ServerException(message: 'Chantier introuvable', statusCode: 400);
          }
          envoyees.add(titre);
        },
      );
      await service.synchroniser();

      expect(envoyees, ['valide']);
      expect(await file.nombreEnEchec(), 1);
      expect(await file.nombreEnAttente(), 0);
      await service.arreter();
    });

    test('ServerException 5xx (ou sans code) est retentée plus tard', () async {
      await deposerCreation('A');

      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async => throw const ServerException(message: 'Panne serveur', statusCode: 503),
      );
      await service.synchroniser();

      expect(await file.nombreEnEchec(), 0, reason: 'une panne serveur est passagère');
      expect(await file.nombreEnAttente(), 1);
      await service.arreter();
    });
  });

  // Écran « Voir toutes les tâches » — gestes EXPLICITES de l'utilisateur,
  // par opposition à la synchronisation automatique testée plus haut.
  group('Synchronisation manuelle (écran des tâches)', () {
    test('synchroniserUne relance un échec définitif et le retire au succès', () async {
      final id = await deposerCreation('A');
      await file.marquerEchecDefinitif(id, 'Chantier introuvable');
      expect(await file.nombreEnEchec(), 1);

      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async {},
      );

      final succes = await service.synchroniserUne(id);

      expect(succes, isTrue);
      expect(await file.parId(id), isNull, reason: 'envoyée avec succès : retirée de la file');
      expect(await file.nombreEnEchec(), 0);
      await service.arreter();
    });

    test('synchroniserUne : id inconnu renvoie false sans effet', () async {
      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async {},
      );

      expect(await service.synchroniserUne('id-inexistant'), isFalse);
      await service.arreter();
    });

    test('synchroniserUne : un nouvel échec reste visible avec son message', () async {
      final id = await deposerCreation('A');
      await file.marquerEchecDefinitif(id, 'ancien message');

      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async => throw const ServerException(message: 'toujours refusée', statusCode: 400),
      );

      final succes = await service.synchroniserUne(id);

      expect(succes, isFalse);
      final relue = await file.parId(id);
      expect(relue, isNotNull);
      expect(relue!.estDefinitivementEnEchec, isTrue);
      expect(relue.derniereErreur, 'toujours refusée');
      await service.arreter();
    });

    test('synchroniserUne ne se chevauche pas avec une passe globale en cours', () async {
      final idGlobal = await deposerCreation('global');
      final idManuel = await deposerCreation('manuel');

      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async => Future<void>.delayed(const Duration(milliseconds: 60)),
      );

      final passeGlobale = service.synchroniser();
      // Lancée pendant que le verrou de la passe globale est posé : doit
      // renvoyer `false` immédiatement plutôt que d'envoyer la même action
      // deux fois.
      final resultatManuel = await service.synchroniserUne(idManuel);

      expect(resultatManuel, isFalse);
      await passeGlobale;
      expect(idGlobal, isNotEmpty);
      await service.arreter();
    });

    test('synchroniserTout relance aussi les échecs définitifs', () async {
      final idAttente = await deposerCreation('en attente');
      final idEchec = await deposerCreation('en échec');
      await file.marquerEchecDefinitif(idEchec, 'refusée précédemment');

      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      final envoyees = <String>[];
      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async => envoyees.add(a.charge['titre'] as String),
      );

      final tout = await service.synchroniserTout();

      expect(tout, isTrue);
      expect(envoyees, containsAll(['en attente', 'en échec']));
      expect(await file.toutesLesTaches(), isEmpty);
      expect(idAttente, isNotEmpty);
      await service.arreter();
    });

    test('synchroniserTout : succès partiel renvoie false et garde les échecs', () async {
      await deposerCreation('valide');
      final idRefuse = await deposerCreation('refusee');
      await file.marquerEchecDefinitif(idRefuse, 'ancien refus');

      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async {
          final titre = a.charge['titre'] as String;
          if (titre == 'refusee') {
            throw const ServerException(message: 'toujours refusée', statusCode: 400);
          }
        },
      );

      final tout = await service.synchroniserTout();

      expect(tout, isFalse);
      expect(await file.nombreEnEchec(), 1);
      expect(await file.nombreEnAttente(), 0);
      await service.arreter();
    });
  });

  // Spec : « Une fois toutes les données synchronisées avec succès, nettoyer
  // les données locales temporaires... uniquement lorsque toutes les tâches
  // en attente ont été synchronisées avec succès ». Le nettoyage passe par
  // `BaseLocale.purgerCacheAncien`, jamais par la file elle-même.
  group('Nettoyage automatique après succès total', () {
    Future<void> deposerChantierAncien(String id) async {
      final db = await base.base;
      await db.insert(BaseLocale.tableChantiers, {
        'id': id,
        'donnees': '{}',
        'maj_le': DateTime.now().subtract(const Duration(days: 200)).millisecondsSinceEpoch,
      });
    }

    test('une passe entièrement réussie déclenche le nettoyage du cache ancien', () async {
      await deposerChantierAncien('vieux-chantier');
      await deposerCreation('A');

      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async {},
      );
      await service.synchroniser();

      final db = await base.base;
      final restant = await db.query(BaseLocale.tableChantiers, where: 'id = ?', whereArgs: ['vieux-chantier']);
      expect(restant, isEmpty, reason: 'succès total : le cache ancien doit être purgé');
      await service.arreter();
    });

    test('une passe interrompue par le réseau NE déclenche PAS le nettoyage', () async {
      await deposerChantierAncien('vieux-chantier');
      await deposerCreation('A');

      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async => throw const NetworkException(),
      );
      await service.synchroniser();

      final db = await base.base;
      final restant = await db.query(BaseLocale.tableChantiers, where: 'id = ?', whereArgs: ['vieux-chantier']);
      expect(restant, isNotEmpty, reason: 'la passe a échoué : rien ne doit être nettoyé');
      await service.arreter();
    });

    test('des échecs définitifs restants empêchent aussi le nettoyage', () async {
      await deposerChantierAncien('vieux-chantier');
      final id = await deposerCreation('refusee');
      await file.marquerEchecDefinitif(id, 'refus');

      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      final service = SynchronisationService(
        file: file,
        detecteur: detecteur,
        base: base,
        executer: (a) async {},
      );
      // La passe automatique ignore les échecs définitifs : la file est donc
      // "vide" à ses yeux, mais `enEchec` reste > 0.
      await service.synchroniser();

      final db = await base.base;
      final restant = await db.query(BaseLocale.tableChantiers, where: 'id = ?', whereArgs: ['vieux-chantier']);
      expect(restant, isNotEmpty, reason: 'un échec définitif attend encore l’utilisateur : pas de nettoyage');
      await service.arreter();
    });
  });

  group('File d’attente', () {
    test('conserve les actions même après fermeture de la base', () async {
      await deposerCreation('persistante');
      await base.fermer();

      // Rouvre : c'est le scénario « l'utilisateur ferme l'app au sous-sol ».
      final apres = await FileAttente(base).nombreEnAttente();
      expect(apres, 1);
    });

    test('la déconnexion vide tout, file comprise', () async {
      await deposerCreation('A');
      await base.viderTout();
      expect(await file.nombreEnAttente(), 0);
    });
  });
}
