import 'package:equatable/equatable.dart';

import '../../domain/entities/piece_jointe.dart';

enum PiecesJointesStatus { chargement, succes, erreur }

class PiecesJointesState extends Equatable {
  final PiecesJointesStatus status;
  final List<PieceJointe> pieces;
  final String? erreur;
  final bool envoiEnCours;

  /// Part déjà envoyée de la pièce en cours, de 0 à 1.
  final double? progression;

  const PiecesJointesState({
    this.status = PiecesJointesStatus.chargement,
    this.pieces = const [],
    this.erreur,
    this.envoiEnCours = false,
    this.progression,
  });

  PiecesJointesState copyWith({
    PiecesJointesStatus? status,
    List<PieceJointe>? pieces,
    String? erreur,
    bool effacerErreur = false,
    bool? envoiEnCours,
    double? progression,
    bool effacerProgression = false,
  }) {
    return PiecesJointesState(
      status: status ?? this.status,
      pieces: pieces ?? this.pieces,
      erreur: effacerErreur ? null : (erreur ?? this.erreur),
      envoiEnCours: envoiEnCours ?? this.envoiEnCours,
      progression: effacerProgression ? null : (progression ?? this.progression),
    );
  }

  @override
  List<Object?> get props => [status, pieces, erreur, envoiEnCours, progression];
}
