import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/plan.dart';
import '../../domain/usecases/get_plan_detail.dart';

enum PlanDetailStatus { initial, chargement, succes, erreur }

class PlanDetailState extends Equatable {
  final PlanDetailStatus status;
  final Plan? plan;

  /// Réserve dont le repère est sélectionné sur le plan — pilote la carte
  /// de détail affichée en bas de la visionneuse.
  final String? reserveSelectionneeId;

  final String? erreur;

  const PlanDetailState({
    this.status = PlanDetailStatus.initial,
    this.plan,
    this.reserveSelectionneeId,
    this.erreur,
  });

  PlanReserve? get reserveSelectionnee {
    final id = reserveSelectionneeId;
    if (id == null || plan == null) return null;
    for (final r in plan!.reserves) {
      if (r.id == id) return r;
    }
    return null;
  }

  PlanDetailState copyWith({
    PlanDetailStatus? status,
    Plan? plan,
    String? reserveSelectionneeId,
    bool effacerSelection = false,
    String? erreur,
  }) {
    return PlanDetailState(
      status: status ?? this.status,
      plan: plan ?? this.plan,
      reserveSelectionneeId: effacerSelection ? null : (reserveSelectionneeId ?? this.reserveSelectionneeId),
      erreur: erreur,
    );
  }

  @override
  List<Object?> get props => [status, plan, reserveSelectionneeId, erreur];
}

class PlanDetailCubit extends Cubit<PlanDetailState> {
  final GetPlanDetail getPlanDetail;
  PlanDetailCubit({required this.getPlanDetail}) : super(const PlanDetailState());

  Future<void> charger(String planId) async {
    emit(state.copyWith(status: PlanDetailStatus.chargement));
    final result = await getPlanDetail(planId);
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(status: PlanDetailStatus.erreur, erreur: failure.errorMessage)),
      (plan) => emit(state.copyWith(status: PlanDetailStatus.succes, plan: plan)),
    );
  }

  /// Re-toucher le même repère le désélectionne (bascule).
  void selectionner(String reserveId) {
    if (state.reserveSelectionneeId == reserveId) {
      emit(state.copyWith(effacerSelection: true));
    } else {
      emit(state.copyWith(reserveSelectionneeId: reserveId));
    }
  }

  void effacerSelection() => emit(state.copyWith(effacerSelection: true));
}
