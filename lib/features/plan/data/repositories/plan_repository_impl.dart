import 'package:dartz/dartz.dart';

import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/plan.dart';
import '../../domain/repositories/plan_repository.dart';
import '../datasources/plan_remote_datasource.dart';

class PlanRepositoryImpl implements PlanRepository {
  final PlanRemoteDataSource remoteDataSource;
  PlanRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, List<Plan>>> getTousPlans() async {
    try {
      return Right(await remoteDataSource.getTousPlans());
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<Plan>>> getPlansChantier(String chantierId) async {
    try {
      return Right(await remoteDataSource.getPlansChantier(chantierId));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<Plan>>> getPlansRacines(String chantierId) async {
    try {
      return Right(await remoteDataSource.getPlansRacines(chantierId));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<Plan>>> getSousPlans(String planId) async {
    try {
      return Right(await remoteDataSource.getSousPlans(planId));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, Plan>> getPlanDetail(String id) async {
    try {
      return Right(await remoteDataSource.getPlanDetail(id));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, Plan>> uploaderPlan({
    required String chantierId,
    required String cheminFichier,
    required String nom,
    PlanFormat? format,
    String? batimentId,
    String? etageId,
    String? zoneId,
    String? parentId,
    /// Discipline du plan et date DU PLAN — cahier technique § 4.
    /// Facultatives : un chantier qui n'a qu'un jeu de plans n'a rien à
    /// distinguer, et une date inconnue vaut mieux qu'une date inventée.
    String? typePlan,
    DateTime? datePlan,
  }) async {
    try {
      return Right(await remoteDataSource.uploaderPlan(
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
      ));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }
}
