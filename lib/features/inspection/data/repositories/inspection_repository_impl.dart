import 'package:dartz/dartz.dart';

import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/inspection.dart';
import '../../domain/repositories/inspection_repository.dart';
import '../datasources/inspection_remote_datasource.dart';

class InspectionRepositoryImpl implements InspectionRepository {
  final InspectionRemoteDataSource remoteDataSource;
  InspectionRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, List<Inspection>>> getInspections({
    required String chantierId,
    InspectionStatut? statut,
  }) async {
    try {
      return Right(await remoteDataSource.getInspections(chantierId: chantierId, statut: statut));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, Inspection>> getInspection(String id) async {
    try {
      return Right(await remoteDataSource.getInspection(id));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, Inspection>> creerInspection({
    required String chantierId,
    /// CODE du type, issu du référentiel administrable
    /// (`/types-inspection/actifs`). Une énumération figée ici
    /// empêcherait d'utiliser un type ajouté par l'administrateur.
    required String typeCode,
    DateTime? dateVisite,
    List<String> libellesChecklist = const [],
  }) async {
    try {
      return Right(await remoteDataSource.creerInspection(
        chantierId: chantierId,
        typeCode: typeCode,
        dateVisite: dateVisite,
        libellesChecklist: libellesChecklist,
      ));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, Inspection>> changerStatut({
    required String id,
    required InspectionStatut statut,
    String? compteRendu,
  }) async {
    try {
      return Right(await remoteDataSource.changerStatut(id: id, statut: statut, compteRendu: compteRendu));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, LigneChecklist>> cocherLigne({
    required String inspectionId,
    required String ligneId,
    required bool coche,
    String? commentaire,
  }) async {
    try {
      return Right(await remoteDataSource.cocherLigne(
        inspectionId: inspectionId,
        ligneId: ligneId,
        coche: coche,
        commentaire: commentaire,
      ));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<Convocation>>> getConvocations(String inspectionId) async {
    try {
      return Right(await remoteDataSource.getConvocations(inspectionId));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> repondreConvocation({
    required String inspectionId,
    required String convocationId,
    required StatutConvocation statut,
  }) async {
    try {
      await remoteDataSource.repondreConvocation(
        inspectionId: inspectionId,
        convocationId: convocationId,
        statut: statut,
      );
      return const Right(null);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }
}
