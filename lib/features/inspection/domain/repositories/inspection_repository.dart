import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/inspection.dart';

/// Visites de chantier.
///
/// Les ÉCRITURES sont réservées côté back au groupe `OPERATIONNEL_CONTROLE`
/// (`requireRole` sur la création, la modification et le cochage des points de
/// contrôle). Le mobile masque ces actions pour les autres rôles, mais c'est
/// le serveur qui tranche : une checklist d'OPR falsifiable rendrait le
/// procès-verbal inopposable.
abstract class InspectionRepository {
  Future<Either<Failure, List<Inspection>>> getInspections({
    required String chantierId,
    InspectionStatut? statut,
  });

  Future<Either<Failure, Inspection>> getInspection(String id);

  Future<Either<Failure, Inspection>> creerInspection({
    required String chantierId,
    /// CODE du type, issu du référentiel administrable
    /// (`/types-inspection/actifs`). Une énumération figée ici
    /// empêcherait d'utiliser un type ajouté par l'administrateur.
    required String typeCode,
    DateTime? dateVisite,
    List<String> libellesChecklist,
  });

  Future<Either<Failure, Inspection>> changerStatut({
    required String id,
    required InspectionStatut statut,
    String? compteRendu,
  });

  Future<Either<Failure, LigneChecklist>> cocherLigne({
    required String inspectionId,
    required String ligneId,
    required bool coche,
    String? commentaire,
  });

  Future<Either<Failure, List<Convocation>>> getConvocations(String inspectionId);

  Future<Either<Failure, void>> repondreConvocation({
    required String inspectionId,
    required String convocationId,
    required StatutConvocation statut,
  });
}
