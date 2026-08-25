import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/rapport.dart';

/// Rapports PDF d'un chantier.
///
/// La génération est réservée côté back aux rôles opérationnels ; le mobile
/// masque le bouton pour les autres, mais c'est le serveur qui décide.
abstract class RapportRepository {
  Future<Either<Failure, List<Rapport>>> getRapports(String chantierId);

  Future<Either<Failure, Rapport>> genererRapport({
    required String chantierId,
    required RapportType type,
    String? statutReserve,
    String? entrepriseId,
    String? batimentId,
  });

  Future<Either<Failure, void>> supprimerRapport(String id);
}
