import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/plan.dart';
import '../repositories/plan_repository.dart';

class GetPlanDetail {
  final PlanRepository repository;
  GetPlanDetail(this.repository);

  Future<Either<Failure, Plan>> call(String id) => repository.getPlanDetail(id);
}
