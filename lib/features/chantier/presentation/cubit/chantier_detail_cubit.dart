import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecases/get_chantier_detail.dart';
import 'chantier_detail_state.dart';

class ChantierDetailCubit extends Cubit<ChantierDetailState> {
  final GetChantierDetail getChantierDetail;
  final String chantierId;

  ChantierDetailCubit({required this.getChantierDetail, required this.chantierId})
      : super(const ChantierDetailState());

  Future<void> charger() async {
    emit(state.copyWith(status: ChantierDetailStatus.chargement));
    final result = await getChantierDetail(chantierId);
    // Retour en arrière pendant le chargement : émettre sur un cubit fermé
    // lève une `StateError` remontée comme crash fatal (voir main.dart).
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(status: ChantierDetailStatus.erreur, erreur: failure.errorMessage)),
      (chantier) => emit(state.copyWith(status: ChantierDetailStatus.succes, chantier: chantier)),
    );
  }
}
