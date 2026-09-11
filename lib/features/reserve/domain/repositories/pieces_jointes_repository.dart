import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/piece_jointe.dart';

/// Pièces jointes d'une réserve. Ajout réservé côté serveur à
/// RESERVE_INTERVENANTS, suppression à OPERATIONNEL.
abstract class PiecesJointesRepository {
  Future<Either<Failure, List<PieceJointe>>> lister(String reserveId);

  Future<Either<Failure, PieceJointe>> ajouter(
    String reserveId, {
    required String cheminFichier,
    required String nomFichier,
    void Function(double progression)? onProgression,
  });

  Future<Either<Failure, void>> supprimer(String pieceId);
}
