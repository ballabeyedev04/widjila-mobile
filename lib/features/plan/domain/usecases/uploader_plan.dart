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
    /// Niveau décrit par le plan — AU PLUS un des trois. Aucun des trois : le
    /// plan est le plan global du chantier.
    String? batimentId,
    String? etageId,
    String? zoneId,

    /// Plan PARENT — celui dont ce plan est le DÉTAIL.
    ///
    /// Prioritaire sur les trois précédents : le serveur ignore alors le
    /// rattachement de structure et fait hériter le détail de la place de son
    /// parent (`plan.service.js#_resoudreRattachement`). Deux places
    /// contradictoires pour un même plan seraient impossibles à arbitrer.
    String? parentId,
    /// Discipline du plan et date DU PLAN — cahier technique § 4.
    /// Facultatives : un chantier qui n'a qu'un jeu de plans n'a rien à
    /// distinguer, et une date inconnue vaut mieux qu'une date inventée.
    String? typePlan,
    DateTime? datePlan,
  }) =>
      repository.uploaderPlan(
        chantierId: chantierId,
        cheminFichier: cheminFichier,
        nom: nom,
        format: format,
        batimentId: batimentId,
        etageId: etageId,
        zoneId: zoneId,
        parentId: parentId,
        typePlan: typePlan,
        datePlan: datePlan,
      );
}
