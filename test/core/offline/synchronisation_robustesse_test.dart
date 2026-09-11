import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/core/offline/base_locale.dart';
import 'package:suivie_chantier_mobile/core/offline/detecteur_connexion.dart';
import 'package:suivie_chantier_mobile/core/offline/file_attente.dart';
import 'package:suivie_chantier_mobile/core/offline/synchronisation_service.dart';

import 'detecteur_simule.dart';

/// Audit synchronisation — robustesse du moteur de file d'attente.
///
/// Défauts reproduits AVANT correction (voir le rapport d'audit), chacun
/// verrouillé ici :
///
///  - 429 / 408 / 425 étaient classés en refus MÉTIER : l'action sortait du
///    cycle et `annuler` SUPPRIMAIT la réserve créée hors ligne ;
///  - un abonnement suspendu (403 `SUBSCRIPTION_*`) faisait de même ;
///  - une création en panne n'empêchait pas d'envoyer la photo qui s'y
///    rattache : 404 garanti, photo classée en échec définitif ;
///  - un fichier local disparu était retenté indéfiniment ;
///  - en ligne, un échec passager n'était JAMAIS retenté sans un nouvel
///    événement réseau ;
///  - une action déposée alors qu'on est en ligne ne partait pas d'elle-même.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    BaseLocale.surchargeNomFichier = 'test_sync_robustesse.db';
  });

  late BaseLocale base;
  late FileAttente file;
  final services = <SynchronisationService>[];

  setUp(() async {
    base = BaseLocale.instance;
    await base.fermer();
    await base.viderTout();
    file = FileAttente(base);
  });

  tearDown(() async {
    // Arrêter AVANT de fermer la base : une relance planifiée ne doit pas
    // tomber sur une base fermée.
    for (final s in services) {
      await s.arreter();
    }
    services.clear();
    await base.viderTout();
    await base.fermer();
  });

  SynchronisationService service({
    required Future<void> Function(ActionEnAttente a) executer,
    Future<void> Function(ActionEnAttente a)? annuler,
    Future<void> Function()? tirer,
    DetecteurSimule? detecteur,
    // Par défaut AUCUNE relance : chaque test qui en veut une le dit.
    List<Duration> delais = const [],
  }) {
    final s = SynchronisationService(
      file: file,
      detecteur: detecteur ?? DetecteurSimule(EtatReseau.enLigne),
      base: base,
      executer: executer,
      annuler: annuler,
      tirer: tirer,
      delaisRelance: delais,
      delaiApresDepot: const Duration(milliseconds: 20),
    );
    services.add(s);
    return s;
  }

  // L'ordre de la file repose sur `cree_le` en millisecondes : une courte
  // pause garantit un ordre déterministe entre deux dépôts.
  Future<void> pause() => Future<void>.delayed(const Duration(milliseconds: 5));

  Future<String> creation(String id) async {
    final idAction = await file.deposer(type: TypeAction.creerReserve, charge: {'id': id, 'titre': id});
    await pause();
    return idAction;
  }

  Future<String> photo(String reserveId) async {
    final idAction = await file.deposer(
      type: TypeAction.ajouterPhotoReserve,
      charge: {'reserveId': reserveId, 'type': 'photo'},
      cheminFichier: '/tmp/$reserveId.jpg',
    );
    await pause();
    return idAction;
  }

  String libelle(ActionEnAttente a) => switch (a.type) {
        TypeAction.creerReserve => 'creer:${a.charge['id']}',
        TypeAction.ajouterPhotoReserve => 'photo:${a.charge['reserveId']}',
        TypeAction.changerStatutReserve => 'statut:${a.charge['reserveId']}',
        TypeAction.envoyerRapport => 'rapport:${a.charge['rapportId']}',
      };

  Future<bool> attendreQue(Future<bool> Function() condition, {Duration max = const Duration(seconds: 3)}) async {
    final fin = DateTime.now().add(max);
    while (DateTime.now().isBefore(fin)) {
      if (await condition()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return condition();
  }

  group('Classification des refus', () {
    for (final code in [408, 425]) {
      test('$code : passager — l’action reste en attente, rien n’est défait', () async {
        await creation('res-1');
        final annulees = <String>[];

        await service(
          executer: (a) async => throw ServerException(message: 'Délai', statusCode: code),
          annuler: (a) async => annulees.add(libelle(a)),
        ).synchroniser();

        expect(await file.nombreEnEchec(), 0, reason: '$code est passager, pas un refus');
        expect(await file.nombreEnAttente(), 1);
        expect(annulees, isEmpty, reason: 'la réserve créée hors ligne ne doit pas être effacée');
      });
    }

    test('429 : la passe s’ARRÊTE — insister aggraverait la limite de débit', () async {
      await creation('A');
      await creation('B');
      final tentees = <String>[];
      final annulees = <String>[];

      await service(
        executer: (a) async {
          tentees.add(libelle(a));
          throw const ServerException(message: 'Trop de requêtes', statusCode: 429);
        },
        annuler: (a) async => annulees.add(libelle(a)),
      ).synchroniser();

      expect(tentees, ['creer:A'], reason: 'B recevrait le même 429');
      expect(await file.nombreEnAttente(), 2);
      expect(await file.nombreEnEchec(), 0);
      expect(annulees, isEmpty);
    });

    test('401 (session à renouveler) : la passe s’arrête, tout reste en file', () async {
      await creation('A');
      await creation('B');
      final tentees = <String>[];

      await service(executer: (a) async {
        tentees.add(libelle(a));
        throw const UnauthorizedException();
      }).synchroniser();

      expect(tentees, ['creer:A']);
      expect(await file.nombreEnAttente(), 2);
    });

    test('abonnement suspendu (403 SUBSCRIPTION_*) : le travail de terrain n’est PAS effacé', () async {
      await creation('A');
      await creation('B');
      final annulees = <String>[];

      await service(
        executer: (a) async => throw const ServerException(
          message: 'Abonnement requis',
          statusCode: 403,
          code: 'SUBSCRIPTION_REQUIRED',
        ),
        annuler: (a) async => annulees.add(libelle(a)),
      ).synchroniser();

      expect(await file.nombreEnEchec(), 0);
      expect(await file.nombreEnAttente(), 2, reason: 'il repartira au renouvellement de l’abonnement');
      expect(annulees, isEmpty);
    });

    test('403 SANS code (droits retirés) reste un refus définitif, et défait l’écriture locale', () async {
      await creation('A');
      final annulees = <String>[];

      await service(
        executer: (a) async => throw const ServerException(message: 'Accès refusé', statusCode: 403),
        annuler: (a) async => annulees.add(libelle(a)),
      ).synchroniser();

      expect(await file.nombreEnEchec(), 1);
      expect(annulees, ['creer:A']);
    });

    test('409 ENVOI_EN_COURS est passager ; un 409 sans code est un vrai conflit', () async {
      await file.deposer(type: TypeAction.envoyerRapport, charge: {'rapportId': 'r1', 'demande': {}});
      await pause();
      await file.deposer(type: TypeAction.envoyerRapport, charge: {'rapportId': 'r2', 'demande': {}});

      await service(executer: (a) async {
        if (a.charge['rapportId'] == 'r1') {
          throw const ServerException(message: 'En cours', statusCode: 409, code: 'ENVOI_EN_COURS');
        }
        throw const ServerException(message: 'Conflit', statusCode: 409);
      }).synchroniser();

      final taches = await file.toutesLesTaches();
      final r1 = taches.firstWhere((t) => t.charge['rapportId'] == 'r1');
      final r2 = taches.firstWhere((t) => t.charge['rapportId'] == 'r2');
      expect(r1.estDefinitivementEnEchec, isFalse);
      expect(r2.estDefinitivementEnEchec, isTrue);
    });

    test('un fichier local disparu est un échec définitif, pas une boucle infinie', () async {
      await photo('A');

      await service(
        executer: (a) async => throw const FileSystemException('Fichier introuvable', '/tmp/A.jpg'),
      ).synchroniser();

      expect(await file.nombreEnEchec(), 1);
      final tache = (await file.toutesLesTaches()).single;
      expect(tache.derniereErreur, contains('/tmp/A.jpg'));
    });

    test('une ActionInvalide est un échec définitif', () async {
      await photo('A');

      await service(executer: (a) async => throw ActionInvalide('sans chemin')).synchroniser();

      expect(await file.nombreEnEchec(), 1);
    });

    test('une erreur inattendue reste PASSAGÈRE — elle peut suivre un succès serveur', () async {
      // Ex. : réponse 201 mal relue. La classer définitive ferait effacer une
      // réserve que le serveur a peut-être bien enregistrée.
      await creation('A');
      final annulees = <String>[];

      await service(
        executer: (a) async => throw StateError('réponse illisible'),
        annuler: (a) async => annulees.add(libelle(a)),
      ).synchroniser();

      expect(await file.nombreEnEchec(), 0);
      expect(annulees, isEmpty);
      final tache = (await file.toutesLesTaches()).single;
      expect(tache.tentatives, 1);
      expect(tache.derniereErreur, contains('réponse illisible'));
    });
  });

  group('Dépendances entre actions d’une même réserve', () {
    test('une création en panne bloque la photo qui s’y rattache, pas les autres réserves', () async {
      await creation('A');
      await photo('A');
      await creation('B');
      final tentees = <String>[];

      await service(executer: (a) async {
        tentees.add(libelle(a));
        if (libelle(a) == 'creer:A') throw const ServerException(message: 'Panne', statusCode: 503);
      }).synchroniser();

      expect(tentees, ['creer:A', 'creer:B'], reason: 'la photo de A partirait sur une réserve inexistante');
      expect(await file.nombreEnEchec(), 0, reason: 'la photo ne doit pas être grillée par un 404 évitable');
      expect(await file.nombreEnAttente(), 2, reason: 'création A et photo A restent à faire');
    });

    test('la photo part à la passe suivante, une fois la réserve créée', () async {
      await creation('A');
      await photo('A');
      final tentees = <String>[];
      var panne = true;

      final s = service(executer: (a) async {
        tentees.add(libelle(a));
        if (libelle(a) == 'creer:A' && panne) throw const ServerException(message: 'Panne', statusCode: 503);
      });
      await s.synchroniser();
      panne = false;
      await s.synchroniser();

      expect(tentees, ['creer:A', 'creer:A', 'photo:A']);
      expect(await file.nombreEnAttente(), 0);
    });

    test('synchroniserUne refuse une photo dont la création n’est pas passée', () async {
      await creation('A');
      final idPhoto = await photo('A');
      final tentees = <String>[];

      final ok = await service(executer: (a) async => tentees.add(libelle(a))).synchroniserUne(idPhoto);

      expect(ok, isFalse);
      expect(tentees, isEmpty);
    });
  });

  group('Relance automatique', () {
    test('en ligne, un échec passager est retenté SANS nouvel événement réseau', () async {
      await creation('A');
      var appels = 0;

      final s = service(
        delais: const [Duration(milliseconds: 40)],
        executer: (a) async {
          appels++;
          if (appels == 1) throw const ServerException(message: 'Panne', statusCode: 503);
        },
      );
      await s.synchroniser();
      expect(await file.nombreEnAttente(), 1);
      expect(s.relancePlanifiee, isTrue);

      final vide = await attendreQue(() async => await file.nombreEnAttente() == 0);

      expect(vide, isTrue, reason: 'la file ne doit pas rester bloquée tant que le réseau ne rebascule pas');
      expect(appels, 2);
      expect(s.relancePlanifiee, isFalse, reason: 'tout est passé : plus rien à relancer');
    });

    test('le délai de relance CROÎT tant que l’échec dure (puis plafonne)', () async {
      await creation('A');
      final instants = <DateTime>[];

      service(
        delais: const [Duration(milliseconds: 20), Duration(milliseconds: 150)],
        executer: (a) async {
          instants.add(DateTime.now());
          throw const ServerException(message: 'Panne', statusCode: 503);
        },
      ).synchroniser();

      await attendreQue(() async => instants.length >= 4, max: const Duration(seconds: 3));

      expect(instants.length, greaterThanOrEqualTo(4));
      final troisieme = instants[3].difference(instants[2]);
      expect(troisieme, greaterThanOrEqualTo(const Duration(milliseconds: 140)),
          reason: 'au-delà du dernier palier, le délai reste au plafond');
    });

    test('coupure réseau alors que l’appareil se croit en ligne : relance planifiée', () async {
      // Portail captif, API tombée derrière un Wi-Fi qui marche : aucun
      // événement réseau ne viendra relancer la file.
      await creation('A');

      final s = service(
        delais: const [Duration(seconds: 30)],
        executer: (a) async => throw const NetworkException(),
      );
      await s.synchroniser();

      expect(s.relancePlanifiee, isTrue);
    });

    test('coupure réelle : pas de relance en boucle, c’est le retour du réseau qui relance', () async {
      await creation('A');
      final detecteur = DetecteurSimule(EtatReseau.enLigne);
      var enPanne = true;
      final envoyees = <String>[];

      final s = service(
        detecteur: detecteur,
        delais: const [Duration(milliseconds: 20)],
        executer: (a) async {
          if (enPanne) {
            detecteur.basculer(EtatReseau.horsLigne);
            throw const NetworkException();
          }
          envoyees.add(libelle(a));
        },
      );
      await s.demarrer();
      expect(s.relancePlanifiee, isFalse);

      enPanne = false;
      detecteur.basculer(EtatReseau.enLigne);

      expect(await attendreQue(() async => envoyees.contains('creer:A')), isTrue);
    });

    test('arreter() annule la relance planifiée', () async {
      await creation('A');
      var appels = 0;

      final s = service(
        delais: const [Duration(milliseconds: 30)],
        executer: (a) async {
          appels++;
          throw const ServerException(message: 'Panne', statusCode: 503);
        },
      );
      await s.synchroniser();
      services.remove(s);
      await s.arreter();
      final apresArret = appels;
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(s.relancePlanifiee, isFalse);
      expect(appels, apresArret, reason: 'plus rien ne doit partir après l’arrêt');
    });
  });

  group('Déclencheurs', () {
    test('une action déposée alors qu’on est EN LIGNE part d’elle-même', () async {
      final envoyees = <String>[];
      final s = service(executer: (a) async => envoyees.add(libelle(a)));
      await s.demarrer();

      await creation('X');

      expect(await attendreQue(() async => envoyees.contains('creer:X')), isTrue);
    });

    test('hors ligne, un dépôt attend le retour du réseau', () async {
      final detecteur = DetecteurSimule(EtatReseau.horsLigne);
      final envoyees = <String>[];
      final s = service(detecteur: detecteur, executer: (a) async => envoyees.add(libelle(a)));
      await s.demarrer();

      await creation('X');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(envoyees, isEmpty);

      detecteur.basculer(EtatReseau.enLigne);
      expect(await attendreQue(() async => envoyees.contains('creer:X')), isTrue);
    });

    test('une action déposée PENDANT une passe n’est pas oubliée', () async {
      await creation('A');
      final envoyees = <String>[];
      final s = service(executer: (a) async {
        if (libelle(a) == 'creer:A') {
          // Pendant l'envoi de A, l'utilisateur crée B.
          await creation('B');
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        envoyees.add(libelle(a));
      });
      await s.demarrer();

      expect(await attendreQue(() async => envoyees.contains('creer:B')), isTrue);
      expect(envoyees.where((e) => e == 'creer:A'), hasLength(1));
    });

    test('réseau qui bascule 10 fois : chaque action part UNE seule fois', () async {
      for (final id in ['A', 'B', 'C']) {
        await creation(id);
      }
      final detecteur = DetecteurSimule(EtatReseau.horsLigne);
      final envoyees = <String>[];
      final s = service(
        detecteur: detecteur,
        executer: (a) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          envoyees.add(libelle(a));
        },
      );
      await s.demarrer();

      for (var i = 0; i < 10; i++) {
        detecteur.basculer(i.isEven ? EtatReseau.enLigne : EtatReseau.horsLigne);
        await Future<void>.delayed(const Duration(milliseconds: 3));
      }
      detecteur.basculer(EtatReseau.enLigne);

      expect(await attendreQue(() async => await file.nombreEnAttente() == 0), isTrue);
      expect(envoyees..sort(), ['creer:A', 'creer:B', 'creer:C']);
    });
  });

  group('Tirage des changements serveur', () {
    test('tiré après une passe d’envoi aboutie', () async {
      await creation('A');
      final journal = <String>[];

      await service(
        executer: (a) async => journal.add(libelle(a)),
        tirer: () async => journal.add('tirage'),
      ).synchroniser();

      expect(journal, ['creer:A', 'tirage'], reason: 'on envoie D’ABORD, on tire ENSUITE');
    });

    test('pas de tirage quand le serveur demande d’attendre (429)', () async {
      await creation('A');
      var tirages = 0;

      await service(
        executer: (a) async => throw const ServerException(message: 'Trop', statusCode: 429),
        tirer: () async => tirages++,
      ).synchroniser();

      expect(tirages, 0);
    });

    test('un tirage en échec ne fait pas échouer l’envoi, et reste consigné', () async {
      await creation('A');

      final s = service(
        executer: (a) async {},
        tirer: () async => throw const NetworkException(message: 'tirage coupé'),
      );
      await s.synchroniser();

      expect(await file.nombreEnAttente(), 0, reason: 'l’envoi a bien abouti');
      expect(s.derniereErreurTirage, isNotNull);
    });
  });

  group('Rejeu après une réponse perdue', () {
    test('l’action rejouée est IDENTIQUE (même id, même charge) — la clé d’idempotence tient', () async {
      await creation('res-42');
      final vues = <String>[];
      var perdue = true;

      final s = service(executer: (a) async {
        vues.add('${a.id}|${a.charge['id']}');
        // Le serveur a écrit, la réponse se perd.
        if (perdue) throw const NetworkException();
      });
      await s.synchroniser();
      perdue = false;
      await s.synchroniser();

      expect(vues, hasLength(2));
      expect(vues[0], vues[1]);
      expect(await file.nombreEnAttente(), 0);
    });
  });
}
