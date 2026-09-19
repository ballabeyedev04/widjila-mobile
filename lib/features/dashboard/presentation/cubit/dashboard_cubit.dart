import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecases/get_dashboard_evolution.dart';
import '../../domain/usecases/get_dashboard_stats.dart';
import 'dashboard_state.dart';

class DashboardCubit extends Cubit<DashboardState> {
  final GetDashboardStats getDashboardStats;
  final GetDashboardEvolution getDashboardEvolution;

  DashboardCubit({required this.getDashboardStats, required this.getDashboardEvolution})
      : super(const DashboardState());

  /// Charge les statistiques ET la courbe d'évolution, en parallèle.
  ///
  /// Les deux requêtes partent ensemble ; l'écran s'affiche dès que les
  /// statistiques arrivent, la courbe se remplit quand elle arrive. Une
  /// courbe en erreur ne fait pas tomber l'écran (voir [DashboardState]).
  Future<void> charger() async {
    emit(state.copyWith(status: DashboardStatus.chargement, evolutionStatus: DashboardStatus.chargement));

    final evolutionFuture = getDashboardEvolution();
    final result = await getDashboardStats();
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(status: DashboardStatus.erreur, erreur: failure.errorMessage)),
      (stats) => emit(state.copyWith(status: DashboardStatus.succes, stats: stats)),
    );

    final evolution = await evolutionFuture;
    if (isClosed) return;
    evolution.fold(
      (_) => emit(state.copyWith(evolutionStatus: DashboardStatus.erreur)),
      (courbe) => emit(state.copyWith(evolutionStatus: DashboardStatus.succes, evolution: courbe)),
    );
  }
}
