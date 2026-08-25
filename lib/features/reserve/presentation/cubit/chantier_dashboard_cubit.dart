import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecases/get_reserve_evolution.dart';
import '../../domain/usecases/get_reserve_statuts_count.dart';
import 'chantier_dashboard_state.dart';

/// Tableau de bord d'un chantier — donut de répartition + courbe
/// d'évolution. Les deux jeux de données viennent du back
/// (`/dashboard/chantiers/:id` et `/dashboard/chantiers/:id/evolution`) ;
/// ce cubit ne fait qu'orchestrer les deux appels, aucun calcul métier.
class ChantierDashboardCubit extends Cubit<ChantierDashboardState> {
  final GetReserveStatutsCount getReserveStatutsCount;
  final GetReserveEvolution getReserveEvolution;
  final String chantierId;

  ChantierDashboardCubit({
    required this.getReserveStatutsCount,
    required this.getReserveEvolution,
    required this.chantierId,
  }) : super(const ChantierDashboardState());

  Future<void> charger() async {
    emit(state.copyWith(status: ChantierDashboardStatus.chargement));

    final evolutionFuture = getReserveEvolution(chantierId);
    final statutsResult = await getReserveStatutsCount(chantierId);
    final evolutionResult = await evolutionFuture;

    if (isClosed) return;

    if (statutsResult.isLeft()) {
      emit(state.copyWith(
        status: ChantierDashboardStatus.erreur,
        erreur: statutsResult.fold((f) => f.errorMessage, (_) => null),
      ));
      return;
    }

    emit(state.copyWith(
      status: ChantierDashboardStatus.succes,
      statutsCount: statutsResult.fold((_) => state.statutsCount, (v) => v),
      // L'évolution est secondaire : une panne dessus ne bloque pas le
      // reste du tableau de bord, le graphe s'affiche juste vide.
      evolution: evolutionResult.fold((_) => state.evolution, (v) => v),
    ));
  }
}
