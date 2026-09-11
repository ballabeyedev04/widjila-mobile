import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/failure.dart';
import '../../domain/entities/membre_chantier.dart';
import '../../domain/usecases/membres_chantier.dart';
import 'membres_chantier_state.dart';

/// Membres affectés à un chantier — consultation, affectation, retrait.
class MembresChantierCubit extends Cubit<MembresChantierState> {
  final String chantierId;
  final GetMembresChantier getMembres;
  final GetCandidatsMembres getCandidats;
  final AffecterMembres affecterMembresUsecase;
  final RetirerMembreChantier retirerMembreUsecase;

  MembresChantierCubit({
    required this.chantierId,
    required this.getMembres,
    required this.getCandidats,
    required this.affecterMembresUsecase,
    required this.retirerMembreUsecase,
  }) : super(const MembresChantierState());

  Future<void> charger({bool silencieux = false}) async {
    if (!silencieux || state.status != MembresChantierStatus.succes) {
      emit(state.copyWith(status: MembresChantierStatus.chargement, effacerErreur: true));
    }
    final resultat = await getMembres(chantierId);
    if (isClosed) return;
    resultat.fold(
      (failure) {
        if (silencieux && state.status == MembresChantierStatus.succes) return;
        emit(state.copyWith(status: MembresChantierStatus.erreur, erreur: failure.errorMessage));
      },
      (membres) => emit(state.copyWith(status: MembresChantierStatus.succes, membres: membres, effacerErreur: true)),
    );
  }

  /// Membres qu'on peut encore affecter — chargés à l'ouverture de la feuille
  /// d'affectation, jamais avant : la liste n'intéresse que ceux qui affectent.
  Future<Either<Failure, List<MembreChantier>>> candidats() => getCandidats(chantierId);

  /// Renvoie le message d'erreur du serveur, ou `null` si l'affectation a réussi.
  Future<String?> affecter(List<String> membreIds, {String? roleChantier}) async {
    if (state.actionEnCours || membreIds.isEmpty) return null;
    emit(state.copyWith(actionEnCours: true));
    final resultat = await affecterMembresUsecase(chantierId, membreIds: membreIds, roleChantier: roleChantier);
    if (isClosed) return null;
    final erreur = resultat.fold<String?>((failure) => failure.errorMessage, (_) => null);
    if (erreur == null) await charger(silencieux: true);
    if (!isClosed) emit(state.copyWith(actionEnCours: false));
    return erreur;
  }

  /// Renvoie le message d'erreur du serveur, ou `null` si le retrait a réussi.
  Future<String?> retirer(String membreId) async {
    if (state.actionEnCours) return null;
    emit(state.copyWith(actionEnCours: true));
    final resultat = await retirerMembreUsecase(chantierId, membreId);
    if (isClosed) return null;
    return resultat.fold<String?>(
      (failure) {
        emit(state.copyWith(actionEnCours: false));
        return failure.errorMessage;
      },
      (_) {
        emit(state.copyWith(
          actionEnCours: false,
          membres: state.membres.where((m) => m.id != membreId).toList(),
        ));
        return null;
      },
    );
  }
}
