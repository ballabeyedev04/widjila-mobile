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
  }) async {
    try {
      return Right(await remoteDataSource.uploaderPlan(
        chantierId: chantierId,
        cheminFichier: cheminFichier,
        nom: nom,
        format: format,
      ));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }
}
