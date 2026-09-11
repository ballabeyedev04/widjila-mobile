import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:suivie_chantier_mobile/core/offline/base_locale.dart';
import 'package:suivie_chantier_mobile/core/offline/cache_reserves.dart';
import 'package:suivie_chantier_mobile/core/offline/detecteur_connexion.dart';
import 'package:suivie_chantier_mobile/core/offline/file_attente.dart';
import 'package:suivie_chantier_mobile/core/offline/stockage_medias.dart';
import 'package:suivie_chantier_mobile/features/reserve/data/datasources/reserve_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/reserve/data/repositories/reserve_repository_impl.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';

import '../../../../core/offline/detecteur_simule.dart';

class _MockRemote extends Mock implements ReserveRemoteDataSource {}

/// File dont l'écriture échoue APRÈS l'écriture locale, DANS la vraie
/// transaction — disque plein, base verrouillée, process tué entre deux
/// écritures. C'est exactement la fenêtre du défaut : l'écriture locale a eu
/// lieu, le dépôt de l'action non.
class _FileEnPanne extends FileAttente {
  _FileEnPanne(super.base);

  @override
  Future<String> deposer({
    required TypeAction type,
    required Map<String, dynamic> charge,
    String? cheminFichier,
    String? id,
    Future<void> Function(Transaction txn)? avecEcriture,
  }) =>
      super.deposer(
        type: type,
        charge: charge,
        cheminFichier: cheminFichier,
        id: id,
        avecEcriture: (txn) async {
          if (avecEcriture != null) await avecEcriture(txn);
          throw const FileSystemException('Écriture impossible (disque plein)');
        },
      );
}

/// Audit synchronisation — écriture locale ET dépôt en file : tout ou rien.
///
/// ## Le défaut
///
/// Hors ligne, la réserve était d'abord écrite dans le cache marquée « en
/// attente », PUIS l'action était déposée dans la file — deux écritures
/// SQLite indépendantes. Si la seconde échouait (ou si le système tuait
/// l'application entre les deux), la réserve restait affichée « en attente
/// d'envoi »… pour toujours : aucune action ne l'enverrait jamais, et la
/// protection des lignes en attente empêchait même le serveur de la corriger.
/// Une perte de données silencieuse — l'utilisateur croit son travail en file.
///
/// Et l'exception du dépôt remontait NUE jusqu'au cubit.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    BaseLocale.surchargeNomFichier = 'test_depot_atomique.db';
  });

  late BaseLocale base;
  late CacheReserves cache;

  setUp(() async {
    base = BaseLocale.instance;
    await base.fermer();
    await base.viderTout();
    cache = CacheReserves(base);
  });

  tearDown(() async {
    await base.viderTout();
    await base.fermer();
  });

  ReserveRepositoryImpl repository(FileAttente file) => ReserveRepositoryImpl(
        _MockRemote(),
        detecteur: DetecteurSimule(EtatReseau.horsLigne),
        fileAttente: file,
        cache: cache,
        medias: StockageMedias(),
      );

  group('dépôt en échec', () {
    test('création hors ligne : AUCUNE réserve orpheline, et un échec dit', () async {
      final resultat = await repository(_FileEnPanne(base)).creerReserve(
        chantierId: 'ch-1',
        titre: 'Fissure',
        priorite: ReserveSeverite.moyenne,
        categorie: ReserveCategorie.autre,
        phaseId: 'ph-1',
      );

      expect(resultat.isLeft(), isTrue, reason: 'l’échec doit être dit, pas levé ni maquillé en succès');
      expect(await cache.listerTout(), isEmpty,
          reason: 'une réserve « en attente » sans action en file ne partirait jamais');
      expect(await FileAttente(base).nombreEnAttente(), 0);
    });

    test('statut hors ligne : la réserve reste telle quelle', () async {
      await cache.enregistrer(const Reserve(
        id: 'res-1',
        numero: 'R-0001',
        chantierId: 'ch-1',
        titre: 'Fissure',
        statut: ReserveStatut.affectee,
      ));

      final resultat =
          await repository(_FileEnPanne(base)).changerStatut(reserveId: 'res-1', statut: ReserveStatut.corrigee);

      expect(resultat.isLeft(), isTrue);
      final relue = await cache.lire('res-1');
      expect(relue!.statut, ReserveStatut.affectee, reason: 'aucun statut optimiste sans action pour le porter');
      expect(await cache.estEnAttente('res-1'), isFalse);
    });
  });

  group('dépôt réussi', () {
    test('création hors ligne : la réserve ET son action existent ensemble', () async {
      final file = FileAttente(base);
      final resultat = await repository(file).creerReserve(
        chantierId: 'ch-1',
        titre: 'Fissure',
        priorite: ReserveSeverite.moyenne,
        categorie: ReserveCategorie.autre,
        phaseId: 'ph-1',
      );

      final reserve = resultat.fold((_) => throw StateError('inattendu'), (r) => r);
      expect(await cache.estEnAttente(reserve.id), isTrue);
      final actions = await file.aTraiter();
      expect(actions, hasLength(1));
      expect(actions.single.charge['id'], reserve.id, reason: 'l’action porte l’identifiant de la ligne locale');
    });

    test('statut hors ligne : statut provisoire ET action, ensemble', () async {
      final file = FileAttente(base);
      await cache.enregistrer(const Reserve(
        id: 'res-1',
        numero: 'R-0001',
        chantierId: 'ch-1',
        titre: 'Fissure',
        statut: ReserveStatut.affectee,
      ));

      final resultat = await repository(file).changerStatut(reserveId: 'res-1', statut: ReserveStatut.corrigee);

      expect(resultat.isRight(), isTrue);
      expect((await cache.lire('res-1'))!.statut, ReserveStatut.corrigee);
      expect(await cache.estEnAttente('res-1'), isTrue);
      expect(await file.nombreEnAttente(), 1);
    });
  });

  group('FileAttente.deposer — transaction', () {
    test('une écriture locale qui échoue n’enregistre PAS l’action', () async {
      final file = FileAttente(base);

      await expectLater(
        file.deposer(
          type: TypeAction.creerReserve,
          charge: {'id': 'res-9', 'titre': 'X'},
          avecEcriture: (txn) async => throw const FileSystemException('écriture locale impossible'),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await file.nombreEnAttente(), 0);
    });

    test('un dépôt qui échoue défait l’écriture locale déjà faite', () async {
      await expectLater(
        _FileEnPanne(base).deposer(
          type: TypeAction.creerReserve,
          charge: {'id': 'res-9', 'titre': 'X'},
          avecEcriture: (txn) => cache.enregistrer(
            const Reserve(id: 'res-9', numero: '—', chantierId: 'ch-1', titre: 'X', statut: ReserveStatut.creee),
            enAttente: true,
            executeur: txn,
          ),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await cache.lire('res-9'), isNull, reason: 'la transaction doit tout annuler');
    });

    test('chaque dépôt réussi est signalé sur `depots`', () async {
      final file = FileAttente(base);
      final signaux = <void>[];
      final abonnement = file.depots.listen(signaux.add);

      await file.deposer(type: TypeAction.creerReserve, charge: {'id': 'a', 'titre': 'A'});
      await file.deposer(type: TypeAction.creerReserve, charge: {'id': 'b', 'titre': 'B'});
      await Future<void>.delayed(Duration.zero);

      expect(signaux, hasLength(2));
      await abonnement.cancel();
    });
  });
}
