import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/dashboard_stats.dart';

abstract class DashboardRepository {
  Future<Either<Failure, DashboardStats>> getStatsGlobales();
}
