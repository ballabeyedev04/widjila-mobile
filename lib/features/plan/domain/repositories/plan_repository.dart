import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/plan.dart';

abstract class PlanRepository {
  /// Tous les plans de l'organisation (dernière version de chacun) —
  /// alimente l'onglet « Plans ».
  Future<Either<Failure, List<Plan>>> getTousPlans();

  /// Plans d'un chantier donné — l'arborescence À PLAT, tous niveaux
  /// confondus. Alimente l'écran « tous les documents du chantier ».
  Future<Either<Failure, List<Plan>>> getPlansChantier(String chantierId);

  /// Plans GLOBAUX d'un chantier — le point d'entrée de la navigation par
  /// niveau, où l'on ne voit à chaque étape que les enfants DIRECTS.
  Future<Either<Failure, List<Plan>>> getPlansRacines(String chantierId);

  /// Sous-plans DIRECTS d'un plan — un seul cran plus bas.
  Future<Either<Failure, List<Plan>>> getSousPlans(String planId);

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
    String? parentId,
    /// Discipline du plan et date DU PLAN — cahier technique § 4.
    /// Facultatives : un chantier qui n'a qu'un jeu de plans n'a rien à
    /// distinguer, et une date inconnue vaut mieux qu'une date inventée.
    String? typePlan,
    DateTime? datePlan,
  });
}
