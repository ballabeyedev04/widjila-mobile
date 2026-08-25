import 'package:dartz/dartz.dart';
import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/dashboard_stats.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../datasources/dashboard_remote_datasource.dart';

class DashboardRepositoryImpl implements DashboardRepository {
  final DashboardRemoteDataSource remoteDataSource;
  DashboardRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, DashboardStats>> getStatsGlobales() async {
    try {
      final stats = await remoteDataSource.getStatsGlobales();
      return Right(stats);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }
}
