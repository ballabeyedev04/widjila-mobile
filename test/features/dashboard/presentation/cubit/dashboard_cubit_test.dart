import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/dashboard/domain/entities/dashboard_stats.dart';
import 'package:suivie_chantier_mobile/features/dashboard/domain/usecases/get_dashboard_stats.dart';
import 'package:suivie_chantier_mobile/features/dashboard/presentation/cubit/dashboard_cubit.dart';
import 'package:suivie_chantier_mobile/features/dashboard/presentation/cubit/dashboard_state.dart';

class MockGetDashboardStats extends Mock implements GetDashboardStats {}

const tStats = DashboardStats(
  chantiers: 3,
  reserves: ReservesStats(total: 10, ouvertes: 4, validees: 5, refusees: 1, enRetard: 2),
  plans: 7,
  inspections: 12,
  documents: 20,
  utilisateurs: 8,
);

void main() {
  late MockGetDashboardStats getDashboardStats;

  setUp(() => getDashboardStats = MockGetDashboardStats());

  blocTest<DashboardCubit, DashboardState>(
    'émet [chargement, succes] quand la récupération réussit',
    build: () {
      when(() => getDashboardStats()).thenAnswer((_) async => const Right(tStats));
      return DashboardCubit(getDashboardStats: getDashboardStats);
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const DashboardState(status: DashboardStatus.chargement),
      const DashboardState(status: DashboardStatus.succes, stats: tStats),
    ],
  );

  blocTest<DashboardCubit, DashboardState>(
    'émet [chargement, erreur] quand la récupération échoue',
    build: () {
      when(() => getDashboardStats())
          .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Erreur serveur')));
      return DashboardCubit(getDashboardStats: getDashboardStats);
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const DashboardState(status: DashboardStatus.chargement),
      const DashboardState(status: DashboardStatus.erreur, erreur: 'Erreur serveur'),
    ],
  );
}
