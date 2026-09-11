import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
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

/// Deuxième audit — A2-15 : le repli hors ligne ignorait page, filtre et
/// recherche.
///
/// Signalé par l'audit de performance, reproduit ici : chaque page demandée
/// hors ligne renvoyait TOUT le cache. La liste, qui ajoute la page suivante à
/// la précédente, affichait alors les mêmes réserves deux, trois fois — et
/// sur 10 000 réserves en cache, chaque défilement en recopiait 10 000.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    BaseLocale.surchargeNomFichier = 'test_repli_pagination.db';
  });

  late BaseLocale base;
  late CacheReserves cache;
  late _MockRemote remote;

  setUp(() async {
    base = BaseLocale.instance;
    await base.fermer();
    await base.viderTout();
    cache = CacheReserves(base);
    remote = _MockRemote();
    when(() => remote.getToutesReserves(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          search: any(named: 'search'),
          statut: any(named: 'statut'),
        )).thenThrow(const NetworkException());
    for (var i = 1; i <= 5; i++) {
      await cache.enregistrer(Reserve(
        id: 'r$i',
        numero: 'R-000$i',
        chantierId: 'ch-1',
        titre: i.isEven ? 'Fissure $i' : 'Infiltration $i',
        statut: i <= 2 ? ReserveStatut.corrigee : ReserveStatut.creee,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 3));
    }
  });

  tearDown(() async {
    await base.viderTout();
    await base.fermer();
  });

  ReserveRepositoryImpl repo() => ReserveRepositoryImpl(
        remote,
        detecteur: DetecteurSimule(EtatReseau.enLigne),
        fileAttente: FileAttente(base),
        cache: cache,
        medias: StockageMedias(),
      );

  test('deux pages consécutives ne se recouvrent pas', () async {
    final p1 = (await repo().getToutesReserves(page: 1, limit: 2)).getOrElse(() => throw StateError('x'));
    final p2 = (await repo().getToutesReserves(page: 2, limit: 2)).getOrElse(() => throw StateError('x'));
    final p3 = (await repo().getToutesReserves(page: 3, limit: 2)).getOrElse(() => throw StateError('x'));

    expect(p1.items, hasLength(2));
    expect(p2.items, hasLength(2));
    expect(p3.items, hasLength(1));
    final tous = [...p1.items, ...p2.items, ...p3.items].map((r) => r.id).toList();
    expect(tous.toSet(), hasLength(5), reason: 'aucune réserve affichée deux fois');
    expect(p1.total, 5);
  });

  test('le filtre de statut s’applique hors ligne', () async {
    final p = (await repo().getToutesReserves(statut: ReserveStatut.corrigee)).getOrElse(() => throw StateError('x'));

    expect(p.items.map((r) => r.statut).toSet(), {ReserveStatut.corrigee});
    expect(p.total, 2);
  });

  test('la recherche s’applique hors ligne (titre, numéro, sans casse)', () async {
    final p = (await repo().getToutesReserves(search: 'fissure')).getOrElse(() => throw StateError('x'));

    expect(p.items.map((r) => r.id).toSet(), {'r2', 'r4'});
  });
}
