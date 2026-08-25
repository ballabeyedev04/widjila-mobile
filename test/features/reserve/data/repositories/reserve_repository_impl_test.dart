import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/offline/base_locale.dart';
import 'package:suivie_chantier_mobile/core/offline/cache_reserves.dart';
import 'package:suivie_chantier_mobile/core/offline/detecteur_connexion.dart';
import 'package:suivie_chantier_mobile/core/offline/file_attente.dart';
import 'package:suivie_chantier_mobile/core/offline/stockage_medias.dart';
import 'package:suivie_chantier_mobile/features/reserve/data/datasources/reserve_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/reserve/data/repositories/reserve_repository_impl.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/repositories/reserve_repository.dart';

import '../../../../core/offline/detecteur_simule.dart';

class MockReserveRemoteDataSource extends Mock implements ReserveRemoteDataSource {}

Reserve _reserveServeur({String id = 'srv-1', String chantierId = 'c1', String titre = 'Fissure'}) => Reserve(
      id: id,
      numero: 'R-0001',
      chantierId: chantierId,
      titre: titre,
      statut: ReserveStatut.creee,
    );

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Fallback nécessaire pour `any(named: ...)` sur des types non
    // primitifs — mocktail l'exige avant tout `when()` qui s'en sert.
    registerFallbackValue(ReserveSeverite.moyenne);
    registerFallbackValue(ReserveCategorie.autre);
    registerFallbackValue(ReserveStatut.creee);
  });

  late BaseLocale base;
  late CacheReserves cache;
  late FileAttente file;
  late StockageMedias medias;
  late MockReserveRemoteDataSource remote;

  ReserveRepositoryImpl repository(DetecteurSimule detecteur) => ReserveRepositoryImpl(
        remote,
        detecteur: detecteur,
        fileAttente: file,
        cache: cache,
        medias: medias,
      );

  setUp(() async {
    base = BaseLocale.instance;
    // Même précaution que `synchronisation_service_test.dart` : base fermée
    // puis rouverte à chaque test, pour que leur ordre d'exécution
    // n'influence jamais leur résultat.
    await base.fermer();
    await base.viderTout();
    cache = CacheReserves(base);
    file = FileAttente(base);
    medias = StockageMedias();
    remote = MockReserveRemoteDataSource();
  });

  tearDown(() async {
    await base.viderTout();
    await base.fermer();
  });

  group('Lecture — cache en repli', () {
    test('en ligne : la réponse serveur est mise en cache', () async {
      final page = ReservePage(items: [_reserveServeur()], total: 1);
      when(() => remote.getToutesReserves(page: any(named: 'page'), limit: any(named: 'limit')))
          .thenAnswer((_) async => page);

      final resultat = await repository(DetecteurSimule(EtatReseau.enLigne)).getToutesReserves();

      expect(resultat.isRight(), isTrue);
      expect(await cache.lire('srv-1'), isNotNull, reason: 'la réponse doit être écrite en cache');
    });

    test('coupure réseau : sert le cache plutôt que d’échouer', () async {
      await cache.enregistrer(_reserveServeur(id: 'en-cache'));
      when(() => remote.getToutesReserves(page: any(named: 'page'), limit: any(named: 'limit')))
          .thenThrow(const NetworkException());

      final resultat = await repository(DetecteurSimule(EtatReseau.enLigne)).getToutesReserves();

      expect(resultat.isRight(), isTrue);
      resultat.fold((_) => fail('doit réussir depuis le cache'), (page) {
        expect(page.items.single.id, 'en-cache');
      });
    });

    test('refus applicatif (403) : ne retombe PAS sur le cache, remonte l’erreur', () async {
      await cache.enregistrer(_reserveServeur(id: 'en-cache'));
      when(() => remote.getToutesReserves(page: any(named: 'page'), limit: any(named: 'limit')))
          .thenThrow(const ServerException(message: 'Accès refusé', statusCode: 403));

      final resultat = await repository(DetecteurSimule(EtatReseau.enLigne)).getToutesReserves();

      // Servir une vieille donnée derrière un refus d'accès serait trompeur :
      // l'utilisateur croirait avoir le droit de consulter, il ne l'a pas.
      expect(resultat.isLeft(), isTrue);
    });

    test('détail : coupure réseau sert la fiche en cache', () async {
      await cache.enregistrer(_reserveServeur(id: 'r-detail', titre: 'Titre en cache'));
      when(() => remote.getReserveDetail('r-detail')).thenThrow(const NetworkException());

      final resultat = await repository(DetecteurSimule(EtatReseau.enLigne)).getReserveDetail('r-detail');

      expect(resultat.isRight(), isTrue);
      resultat.fold((_) => fail('doit réussir'), (r) => expect(r.titre, 'Titre en cache'));
    });
  });

  group('creerReserve — hors ligne', () {
    test('l’appareil se sait hors ligne : aucun appel réseau, action mise en file', () async {
      final resultat = await repository(DetecteurSimule(EtatReseau.horsLigne)).creerReserve(
        chantierId: 'c1',
        titre: 'Fissure sous-sol',
        priorite: ReserveSeverite.haute,
        categorie: ReserveCategorie.grosOeuvre,
      );

      verifyNever(() => remote.creerReserve(
            chantierId: any(named: 'chantierId'),
            titre: any(named: 'titre'),
            priorite: any(named: 'priorite'),
            categorie: any(named: 'categorie'),
          ));

      expect(resultat.isRight(), isTrue);
      final reserve = resultat.fold((_) => throw StateError('inattendu'), (r) => r);
      expect(reserve.titre, 'Fissure sous-sol');
      expect(reserve.id, isNotEmpty);

      expect(await file.nombreEnAttente(), 1);
      final actions = await file.aTraiter();
      expect(actions.single.type, TypeAction.creerReserve);
      expect(actions.single.charge['id'], reserve.id, reason: 'même id des deux côtés — idempotence serveur');
      expect(actions.single.charge['chantierId'], 'c1');

      expect(await cache.estEnAttente(reserve.id), isTrue);
    });

    test('en ligne mais coupure PENDANT l’appel : bascule quand même en file', () async {
      when(() => remote.creerReserve(
            // [C4] — l'id client accompagne désormais TOUTE tentative en
            // ligne (idempotence du rejeu en cas de timeout après succès
            // serveur) : le stub doit matcher ce paramètre, sinon mocktail
            // ne reconnaît pas l'appel réel et l'invocation retombe sur un
            // comportement par défaut au lieu de la réponse programmée.
            id: any(named: 'id'),
            chantierId: any(named: 'chantierId'),
            titre: any(named: 'titre'),
            description: any(named: 'description'),
            priorite: any(named: 'priorite'),
            categorie: any(named: 'categorie'),
            batimentId: any(named: 'batimentId'),
            etageId: any(named: 'etageId'),
            zoneId: any(named: 'zoneId'),
            lotId: any(named: 'lotId'),
            dateLimite: any(named: 'dateLimite'),
          )).thenThrow(const NetworkException());

      final resultat = await repository(DetecteurSimule(EtatReseau.enLigne)).creerReserve(
        chantierId: 'c1',
        titre: 'Signal perdu en cours d’envoi',
        priorite: ReserveSeverite.moyenne,
        categorie: ReserveCategorie.autre,
      );

      // Ne doit JAMAIS remonter une erreur à l'écran dans ce cas : le travail
      // de l'utilisateur ne doit pas se perdre sur un aléa de couverture
      // réseau au moment précis de l'envoi.
      expect(resultat.isRight(), isTrue);
      expect(await file.nombreEnAttente(), 1);
    });

    test('en ligne, succès : appelle le réseau et NE dépose AUCUNE action', () async {
      when(() => remote.creerReserve(
            // [C4] — l'id client accompagne désormais TOUTE tentative en
            // ligne (idempotence du rejeu en cas de timeout après succès
            // serveur) : le stub doit matcher ce paramètre, sinon mocktail
            // ne reconnaît pas l'appel réel et l'invocation retombe sur un
            // comportement par défaut au lieu de la réponse programmée.
            id: any(named: 'id'),
            chantierId: any(named: 'chantierId'),
            titre: any(named: 'titre'),
            description: any(named: 'description'),
            priorite: any(named: 'priorite'),
            categorie: any(named: 'categorie'),
            batimentId: any(named: 'batimentId'),
            etageId: any(named: 'etageId'),
            zoneId: any(named: 'zoneId'),
            lotId: any(named: 'lotId'),
            dateLimite: any(named: 'dateLimite'),
          )).thenAnswer((_) async => _reserveServeur(id: 'srv-generee'));

      final resultat = await repository(DetecteurSimule(EtatReseau.enLigne)).creerReserve(
        chantierId: 'c1',
        titre: 'Réserve normale',
        priorite: ReserveSeverite.faible,
        categorie: ReserveCategorie.peinture,
      );

      expect(resultat.isRight(), isTrue);
      expect(await file.nombreEnAttente(), 0);
      expect(await cache.estEnAttente('srv-generee'), isFalse);
    });

    // Non-régression [C4] — LE bug de duplication.
    //
    // Sur un réseau de chantier, une création peut aboutir côté serveur alors
    // que la réponse se perd (`receiveTimeout` à 30 s). L'app bascule alors en
    // file d'attente et rejouera l'action au retour du réseau. Pour que ce
    // rejeu soit INOFFENSIF, l'id envoyé lors de la tentative en ligne doit
    // être EXACTEMENT celui mis en file : `ReserveService.creerReserve`
    // (backend) reconnaît alors l'id déjà enregistré et renvoie la réserve
    // existante au lieu d'en créer une seconde.
    //
    // La version précédente ne générait l'id qu'au moment du repli — donc un
    // id différent de celui déjà connu du serveur — et produisait un doublon
    // à chaque timeout sur une création pourtant réussie.
    test('timeout après envoi : l\'action en file rejoue le MÊME id qu\'en ligne', () async {
      String? idEnvoyeAuServeur;
      when(() => remote.creerReserve(
            id: any(named: 'id'),
            chantierId: any(named: 'chantierId'),
            titre: any(named: 'titre'),
            description: any(named: 'description'),
            priorite: any(named: 'priorite'),
            categorie: any(named: 'categorie'),
            batimentId: any(named: 'batimentId'),
            etageId: any(named: 'etageId'),
            zoneId: any(named: 'zoneId'),
            lotId: any(named: 'lotId'),
            dateLimite: any(named: 'dateLimite'),
          )).thenAnswer((invocation) async {
        idEnvoyeAuServeur = invocation.namedArguments[#id] as String?;
        // Le serveur a reçu et créé — mais la réponse n'arrivera jamais.
        throw const NetworkException();
      });

      await repository(DetecteurSimule(EtatReseau.enLigne)).creerReserve(
        chantierId: 'c1',
        titre: 'Fissure au sous-sol',
        priorite: ReserveSeverite.haute,
        categorie: ReserveCategorie.autre,
      );

      expect(idEnvoyeAuServeur, isNotNull,
          reason: 'un id client doit accompagner la tentative EN LIGNE, sinon '
              'le serveur ne peut pas dédupliquer le rejeu');

      final taches = await file.toutesLesTaches();
      expect(taches, hasLength(1));
      expect(
        taches.single.charge['id'],
        idEnvoyeAuServeur,
        reason: 'un id différent recréerait une seconde réserve à la synchronisation',
      );
    });
  });

  group('changerStatut — hors ligne', () {
    test('la réserve existe en cache : mise à jour optimiste + action en file', () async {
      await cache.enregistrer(_reserveServeur(id: 'r1'));

      final resultat = await repository(DetecteurSimule(EtatReseau.horsLigne))
          .changerStatut(reserveId: 'r1', statut: ReserveStatut.enCours);

      expect(resultat.isRight(), isTrue);
      resultat.fold((_) => fail('doit réussir'), (r) => expect(r.statut, ReserveStatut.enCours));

      final relue = await cache.lire('r1');
      expect(relue?.statut, ReserveStatut.enCours, reason: 'la mise à jour optimiste doit persister');
      expect(await cache.estEnAttente('r1'), isTrue);
      expect(await file.nombreEnAttente(), 1);
    });

    test('la réserve est INCONNUE en local : échoue proprement, ne dépose rien', () async {
      final resultat = await repository(DetecteurSimule(EtatReseau.horsLigne))
          .changerStatut(reserveId: 'introuvable', statut: ReserveStatut.enCours);

      expect(resultat.isLeft(), isTrue);
      resultat.fold((f) => expect(f, isA<NetworkFailure>()), (_) => fail('doit échouer'));
      expect(await file.nombreEnAttente(), 0);
    });
  });

  group('ajouterMedia — hors ligne', () {
    test('copie le fichier hors du cache temporaire et met l’action en file', () async {
      // Simule le fichier rendu par `image_picker` : un fichier TEMPORAIRE,
      // hors du dossier propre à l'application.
      final dossierTemp = await Directory.systemTemp.createTemp('photo_source');
      final source = File(p.join(dossierTemp.path, 'cliche.jpg'));
      await source.writeAsBytes([1, 2, 3, 4]);
      addTearDown(() => dossierTemp.delete(recursive: true));

      final resultat = await repository(DetecteurSimule(EtatReseau.horsLigne)).ajouterMedia(
        reserveId: 'r1',
        cheminFichier: source.path,
      );

      expect(resultat.isRight(), isTrue);
      final media = resultat.fold((_) => throw StateError('inattendu'), (m) => m);

      // Le chemin renvoyé n'est PAS celui d'origine : c'est la copie durable.
      expect(media.url, isNot(source.path));
      expect(await File(media.url).exists(), isTrue);
      expect(await File(media.url).readAsBytes(), [1, 2, 3, 4]);

      final actions = await file.aTraiter();
      expect(actions.single.type, TypeAction.ajouterPhotoReserve);
      expect(actions.single.charge['reserveId'], 'r1');
      expect(actions.single.cheminFichier, media.url);
    });
  });
}
