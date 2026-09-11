import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/repositories/pieces_jointes_repository.dart';
import 'pieces_jointes_state.dart';

/// Pièces jointes d'une réserve — liste, ajout, suppression.
class PiecesJointesCubit extends Cubit<PiecesJointesState> {
  final String reserveId;
  final PiecesJointesRepository repository;

  PiecesJointesCubit({required this.reserveId, required this.repository}) : super(const PiecesJointesState());

  Future<void> charger() async {
    emit(state.copyWith(status: PiecesJointesStatus.chargement, effacerErreur: true));
    final resultat = await repository.lister(reserveId);
    if (isClosed) return;
    resultat.fold(
      (failure) => emit(state.copyWith(status: PiecesJointesStatus.erreur, erreur: failure.errorMessage)),
      (pieces) => emit(state.copyWith(status: PiecesJointesStatus.succes, pieces: pieces)),
    );
  }

  /// Renvoie le message d'erreur du serveur, ou `null` si la pièce est jointe.
  Future<String?> ajouter({required String cheminFichier, required String nomFichier}) async {
    if (state.envoiEnCours) return null;
    emit(state.copyWith(envoiEnCours: true, effacerProgression: true));

    // Une émission par point de pourcentage au plus : Dio signale chaque
    // paquet envoyé.
    var dernierPourcent = -1;
    final resultat = await repository.ajouter(
      reserveId,
      cheminFichier: cheminFichier,
      nomFichier: nomFichier,
      onProgression: (progression) {
        final borne = progression.clamp(0.0, 1.0);
        final pourcent = (borne * 100).floor();
        if (isClosed || pourcent == dernierPourcent) return;
        dernierPourcent = pourcent;
        emit(state.copyWith(progression: borne));
      },
    );
    if (isClosed) return null;

    return resultat.fold<String?>(
      (failure) {
        emit(state.copyWith(envoiEnCours: false, effacerProgression: true));
        return failure.errorMessage;
      },
      (piece) {
        emit(state.copyWith(
          envoiEnCours: false,
          effacerProgression: true,
          status: PiecesJointesStatus.succes,
          pieces: [piece, ...state.pieces],
        ));
        return null;
      },
    );
  }

  /// Renvoie le message d'erreur du serveur, ou `null` si la pièce est supprimée.
  Future<String?> supprimer(String pieceId) async {
    final resultat = await repository.supprimer(pieceId);
    if (isClosed) return null;
    return resultat.fold<String?>(
      (failure) => failure.errorMessage,
      (_) {
        emit(state.copyWith(pieces: state.pieces.where((p) => p.id != pieceId).toList()));
        return null;
      },
    );
  }
}
