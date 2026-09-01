import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/plan.dart';

abstract class PlanRepository {
  /// Tous les plans de l'organisation (dernière version de chacun) —
  /// alimente l'onglet « Plans ».
  Future<Either<Failure, List<Plan>>> getTousPlans();

  /// Plans d'un chantier donné.
  Future<Either<Failure, List<Plan>>> getPlansChantier(String chantierId);

  /// Détail d'un plan, réserves positionnées incluses.
  Future<Either<Failure, Plan>> getPlanDetail(String id);

  /// Dépose un nouveau plan sur un chantier.
  ///
  /// [format] est facultatif côté back (`uploadPlanSchema`) : il décrit la
  /// nature du document (pdf / dwg / ifc) indépendamment du fichier envoyé.
  /// Réservé aux rôles OPERATIONNEL_CONTROLE côté serveur.
  Future<Either<Failure, Plan>> uploaderPlan({
    required String chantierId,
    required String cheminFichier,
    required String nom,
    PlanFormat? format,
    /// Niveau décrit par le plan — AU PLUS un des trois. Aucun des trois : le
    /// plan est le plan global du chantier.
    String? batimentId,
    String? etageId,
    String? zoneId,
  });
}
