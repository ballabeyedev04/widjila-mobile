import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecases/get_dashboard_stats.dart';
import 'dashboard_state.dart';

class DashboardCubit extends Cubit<DashboardState> {
  final GetDashboardStats getDashboardStats;
  DashboardCubit({required this.getDashboardStats}) : super(const DashboardState());

  Future<void> charger() async {
    emit(state.copyWith(status: DashboardStatus.chargement));
    final result = await getDashboardStats();
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(status: DashboardStatus.erreur, erreur: failure.errorMessage)),
      (stats) => emit(state.copyWith(status: DashboardStatus.succes, stats: stats)),
    );
  }
}
