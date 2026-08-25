import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/plan.dart';
import '../repositories/plan_repository.dart';

class GetTousPlans {
  final PlanRepository repository;
  GetTousPlans(this.repository);

  Future<Either<Failure, List<Plan>>> call() => repository.getTousPlans();
}
