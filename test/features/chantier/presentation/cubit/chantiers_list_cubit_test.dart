import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/entities/chantier.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/repositories/chantier_repository.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/usecases/get_chantiers.dart';
import 'package:suivie_chantier_mobile/features/dashboard/domain/entities/dashboard_stats.dart';
import 'package:suivie_chantier_mobile/features/dashboard/domain/usecases/get_dashboard_stats.dart';
import 'package:suivie_chantier_mobile/features/chantier/presentation/cubit/chantiers_list_cubit.dart';
import 'package:suivie_chantier_mobile/features/chantier/presentation/cubit/chantiers_list_state.dart';

class MockGetChantiers extends Mock implements GetChantiers {}

class MockGetDashboardStats extends Mock implements GetDashboardStats {}

Chantier _chantier(String id) => Chantier(id: id, nom: 'Chantier $id', statut: ChantierStatut.enCours);

void main() {
  late MockGetChantiers getChantiers;
  late MockGetDashboardStats getDashboardStats;

  setUp(() {
    getChantiers = MockGetChantiers();
    getDashboardStats = MockGetDashboardStats();
    // Les compteurs des puces ne sont chargés que par l'écran Chantiers
    // (`chargerCompteurs()`), jamais par `charger()` : le stub sert
    // seulement à ce que le cubit soit constructible.
    when(() => getDashboardStats()).thenAnswer((_) async => const Right(DashboardStats()));
  });

  blocTest<ChantiersListCubit, ChantiersListState>(
    'charger() remplace la liste et repart toujours de la page 1',
    build: () {
      when(() => getChantiers(page: 1, limit: 20, search: '', statut: null))
          .thenAnswer((_) async => Right(ChantierPage(items: [_chantier('a'), _chantier('b')], total: 2)));
      return ChantiersListCubit(getChantiers: getChantiers, getDashboardStats: getDashboardStats);
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const ChantiersListState(status: ChantiersListStatus.chargement),
      isA<ChantiersListState>()
          .having((s) => s.status, 'status', ChantiersListStatus.succes)
          .having((s) => s.items.length, 'items.length', 2)
          .having((s) => s.total, 'total', 2),
    ],
  );

  blocTest<ChantiersListCubit, ChantiersListState>(
    'chargerPageSuivante() AJOUTE à la liste existante sans la remplacer',
    build: () {
      when(() => getChantiers(page: 2, limit: 20, search: '', statut: null))
          .thenAnswer((_) async => Right(ChantierPage(items: [_chantier('c')], total: 3)));
      return ChantiersListCubit(getChantiers: getChantiers, getDashboardStats: getDashboardStats);
    },
    seed: () => ChantiersListState(
      status: ChantiersListStatus.succes,
      items: [_chantier('a'), _chantier('b')],
      total: 3,
      page: 1,
    ),
    act: (cubit) => cubit.chargerPageSuivante(),
    expect: () => [
      isA<ChantiersListState>().having((s) => s.chargementPage, 'chargementPage', true),
      isA<ChantiersListState>()
          .having((s) => s.items.map((c) => c.id).toList(), 'ids', ['a', 'b', 'c'])
          .having((s) => s.page, 'page', 2),
    ],
  );

  blocTest<ChantiersListCubit, ChantiersListState>(
    'chargerPageSuivante() ne fait rien si aPlusDeResultats est déjà false',
    build: () => ChantiersListCubit(getChantiers: getChantiers, getDashboardStats: getDashboardStats),
    seed: () => ChantiersListState(status: ChantiersListStatus.succes, items: [_chantier('a')], total: 1),
    act: (cubit) => cubit.chargerPageSuivante(),
    expect: () => [],
    verify: (_) => verifyNever(() => getChantiers(page: any(named: 'page'), limit: any(named: 'limit'))),
  );

  blocTest<ChantiersListCubit, ChantiersListState>(
    'émet erreur quand le backend échoue',
    build: () {
      when(() => getChantiers(page: 1, limit: 20, search: '', statut: null))
          .thenAnswer((_) async => const Left(NetworkFailure()));
      return ChantiersListCubit(getChantiers: getChantiers, getDashboardStats: getDashboardStats);
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const ChantiersListState(status: ChantiersListStatus.chargement),
      isA<ChantiersListState>().having((s) => s.status, 'status', ChantiersListStatus.erreur),
    ],
  );
}
