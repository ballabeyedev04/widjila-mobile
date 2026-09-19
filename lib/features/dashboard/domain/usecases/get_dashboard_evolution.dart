import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/dashboard_stats.dart';
import '../repositories/dashboard_repository.dart';

class GetDashboardEvolution {
  final DashboardRepository repository;
  GetDashboardEvolution(this.repository);

  Future<Either<Failure, DashboardEvolution>> call() => repository.getEvolution();
}
