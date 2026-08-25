import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/plan.dart';
import '../repositories/plan_repository.dart';

/// Dépose un plan sur un chantier.
///
/// Le serveur exige le rôle OPERATIONNEL_CONTROLE (voir
/// `backend/src/modules/plan/route/plan.route.js`) : l'appelant doit donc
/// masquer l'action pour les autres rôles plutôt que de laisser partir un
/// appel qui reviendra en 403.
class UploaderPlan {
  final PlanRepository repository;
  UploaderPlan(this.repository);

  Future<Either<Failure, Plan>> call({
    required String chantierId,
    required String cheminFichier,
    required String nom,
    PlanFormat? format,
  }) =>
      repository.uploaderPlan(
        chantierId: chantierId,
        cheminFichier: cheminFichier,
        nom: nom,
        format: format,
      );
}
