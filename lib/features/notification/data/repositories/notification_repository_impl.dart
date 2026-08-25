import 'package:dartz/dartz.dart';

import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/repositories/notification_repository.dart';
import '../datasources/notification_remote_datasource.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  final NotificationRemoteDataSource remoteDataSource;
  NotificationRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, PageNotifications>> lister({int page = 1, int limit = 20}) async {
    try {
      return Right(await remoteDataSource.lister(page: page, limit: limit));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, int>> compterNonLues() async {
    try {
      return Right(await remoteDataSource.compterNonLues());
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> marquerLues(List<String> ids) async {
    try {
      return Right(await remoteDataSource.marquerLues(ids));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> enregistrerAppareil(String jeton, String plateforme) async {
    try {
      return Right(await remoteDataSource.enregistrerAppareil(jeton, plateforme));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> oublierAppareil(String jeton) async {
    try {
      return Right(await remoteDataSource.oublierAppareil(jeton));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }
}
