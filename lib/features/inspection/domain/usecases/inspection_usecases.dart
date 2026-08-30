import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/inspection.dart';
import '../repositories/inspection_repository.dart';

/// Cas d'usage du module Inspections.
///
/// Regroupés dans un seul fichier — contrairement aux modules plus anciens qui
/// ont un fichier par classe : ils partagent la même entité et la même
/// dépendance, et les éparpiller sur sept fichiers d'une dizaine de lignes
/// n'apporterait rien de plus qu'un dossier plus long à parcourir.

class GetInspections {
  final InspectionRepository repository;
  GetInspections(this.repository);

  Future<Either<Failure, List<Inspection>>> call({
    required String chantierId,
    InspectionStatut? statut,
  }) =>
      repository.getInspections(chantierId: chantierId, statut: statut);
}

class GetInspection {
  final InspectionRepository repository;
  GetInspection(this.repository);

  Future<Either<Failure, Inspection>> call(String id) => repository.getInspection(id);
}

class CreerInspection {
  final InspectionRepository repository;
  CreerInspection(this.repository);

  Future<Either<Failure, Inspection>> call({
    required String chantierId,
    /// CODE du type, issu du référentiel administrable
    /// (`/types-inspection/actifs`). Une énumération figée ici
    /// empêcherait d'utiliser un type ajouté par l'administrateur.
    required String typeCode,
    DateTime? dateVisite,
    List<String> libellesChecklist = const [],
  }) =>
      repository.creerInspection(
        chantierId: chantierId,
        typeCode: typeCode,
        dateVisite: dateVisite,
        libellesChecklist: libellesChecklist,
      );
}

class ChangerStatutInspection {
  final InspectionRepository repository;
  ChangerStatutInspection(this.repository);

  Future<Either<Failure, Inspection>> call({
    required String id,
    required InspectionStatut statut,
    String? compteRendu,
  }) =>
      repository.changerStatut(id: id, statut: statut, compteRendu: compteRendu);
}

class CocherLigneChecklist {
  final InspectionRepository repository;
  CocherLigneChecklist(this.repository);

  Future<Either<Failure, LigneChecklist>> call({
    required String inspectionId,
    required String ligneId,
    required bool coche,
    String? commentaire,
  }) =>
      repository.cocherLigne(
        inspectionId: inspectionId,
        ligneId: ligneId,
        coche: coche,
        commentaire: commentaire,
      );
}

class GetConvocations {
  final InspectionRepository repository;
  GetConvocations(this.repository);

  Future<Either<Failure, List<Convocation>>> call(String inspectionId) =>
      repository.getConvocations(inspectionId);
}

class RepondreConvocation {
  final InspectionRepository repository;
  RepondreConvocation(this.repository);

  Future<Either<Failure, void>> call({
    required String inspectionId,
    required String convocationId,
    required StatutConvocation statut,
  }) =>
      repository.repondreConvocation(
        inspectionId: inspectionId,
        convocationId: convocationId,
        statut: statut,
      );
}
