import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/dashboard/domain/entities/dashboard_stats.dart';
import 'package:suivie_chantier_mobile/features/dashboard/domain/usecases/get_dashboard_evolution.dart';
import 'package:suivie_chantier_mobile/features/dashboard/domain/usecases/get_dashboard_stats.dart';
import 'package:suivie_chantier_mobile/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:suivie_chantier_mobile/features/dashboard/presentation/cubit/dashboard_state.dart';

class MockGetDashboardStats extends Mock implements GetDashboardStats {}

class MockGetDashboardEvolution extends Mock implements GetDashboardEvolution {}

const tStats = DashboardStats(
  chantiers: 3,
  reserves: ReservesStats(total: 10, ouvertes: 4, validees: 5, refusees: 1, enRetard: 2),
  plans: 7,
  inspections: 12,
  documents: 20,
  utilisateurs: 8,
);

const tEvolution = DashboardEvolution(series: [
  DashboardEvolutionPoint(mois: '2026-08', creees: 4, traitees: 1, levees: 0),
  DashboardEvolutionPoint(mois: '2026-09', creees: 6, traitees: 3, levees: 2),
]);

void main() {
  late MockGetDashboardStats getDashboardStats;
  late MockGetDashboardEvolution getDashboardEvolution;

  setUp(() {
    getDashboardStats = MockGetDashboardStats();
    getDashboardEvolution = MockGetDashboardEvolution();
  });

  DashboardCubit construire() =>
      DashboardCubit(getDashboardStats: getDashboardStats, getDashboardEvolution: getDashboardEvolution);

  blocTest<DashboardCubit, DashboardState>(
    'émet [chargement, succes, évolution] quand tout réussit',
    build: () {
      when(() => getDashboardStats()).thenAnswer((_) async => const Right(tStats));
      when(() => getDashboardEvolution()).thenAnswer((_) async => const Right(tEvolution));
      return construire();
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const DashboardState(status: DashboardStatus.chargement, evolutionStatus: DashboardStatus.chargement),
      const DashboardState(
        status: DashboardStatus.succes,
        stats: tStats,
        evolutionStatus: DashboardStatus.chargement,
      ),
      const DashboardState(
        status: DashboardStatus.succes,
        stats: tStats,
        evolutionStatus: DashboardStatus.succes,
        evolution: tEvolution,
      ),
    ],
  );

  blocTest<DashboardCubit, DashboardState>(
    'émet [chargement, erreur] quand les statistiques échouent',
    build: () {
      when(() => getDashboardStats())
          .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Erreur serveur')));
      when(() => getDashboardEvolution()).thenAnswer((_) async => const Right(tEvolution));
      return construire();
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const DashboardState(status: DashboardStatus.chargement, evolutionStatus: DashboardStatus.chargement),
      const DashboardState(
        status: DashboardStatus.erreur,
        erreur: 'Erreur serveur',
        evolutionStatus: DashboardStatus.chargement,
      ),
      const DashboardState(
        status: DashboardStatus.erreur,
        evolutionStatus: DashboardStatus.succes,
        evolution: tEvolution,
      ),
    ],
  );

  blocTest<DashboardCubit, DashboardState>(
    "un échec de l'évolution ne fait PAS tomber les statistiques",
    build: () {
      when(() => getDashboardStats()).thenAnswer((_) async => const Right(tStats));
      when(() => getDashboardEvolution())
          .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Courbe indisponible')));
      return construire();
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const DashboardState(status: DashboardStatus.chargement, evolutionStatus: DashboardStatus.chargement),
      const DashboardState(status: DashboardStatus.succes, stats: tStats, evolutionStatus: DashboardStatus.chargement),
      const DashboardState(status: DashboardStatus.succes, stats: tStats, evolutionStatus: DashboardStatus.erreur),
    ],
  );

  test("les statistiques s'affichent SANS attendre la courbe", () async {
    final courbe = Completer<Either<Failure, DashboardEvolution>>();
    when(() => getDashboardStats()).thenAnswer((_) async => const Right(tStats));
    // La courbe ne répond pas tant qu'on ne la libère pas.
    when(() => getDashboardEvolution()).thenAnswer((_) => courbe.future);
    final cubit = construire();
    final etats = <DashboardState>[];
    final abonnement = cubit.stream.listen(etats.add);

    // `charger()` n'est PAS attendu : il ne se termine qu'avec la courbe.
    final chargement = cubit.charger();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(etats.last, const DashboardState(
      status: DashboardStatus.succes,
      stats: tStats,
      evolutionStatus: DashboardStatus.chargement,
    ));

    courbe.complete(const Right(tEvolution));
    await chargement;
    expect(cubit.state.evolution, tEvolution);

    await abonnement.cancel();
    await cubit.close();
  });

  test('les deux requêtes partent ENSEMBLE, pas l’une après l’autre', () async {
    final ordre = <String>[];
    when(() => getDashboardStats()).thenAnswer((_) async {
      ordre.add('stats:debut');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      ordre.add('stats:fin');
      return const Right(tStats);
    });
    when(() => getDashboardEvolution()).thenAnswer((_) async {
      ordre.add('evolution:debut');
      return const Right(tEvolution);
    });

    await construire().charger();

    expect(ordre.indexOf('evolution:debut'), lessThan(ordre.indexOf('stats:fin')));
  });
}
