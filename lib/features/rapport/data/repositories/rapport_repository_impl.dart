import 'package:dartz/dartz.dart';

import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/rapport.dart';
import '../../domain/repositories/rapport_repository.dart';
import '../datasources/rapport_remote_datasource.dart';

class RapportRepositoryImpl implements RapportRepository {
  final RapportRemoteDataSource remoteDataSource;
  RapportRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, List<Rapport>>> getRapports(String chantierId) async {
    try {
      return Right(await remoteDataSource.getRapports(chantierId));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, Rapport>> genererRapport({
    required String chantierId,
    required RapportType type,
    String? statutReserve,
    String? entrepriseId,
    String? batimentId,
  }) async {
    try {
      return Right(await remoteDataSource.genererRapport(
        chantierId: chantierId,
        type: type,
        statutReserve: statutReserve,
        entrepriseId: entrepriseId,
        batimentId: batimentId,
      ));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, void>> supprimerRapport(String id) async {
    try {
      await remoteDataSource.supprimerRapport(id);
      return const Right(null);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }
}
