import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/plan.dart';
import '../repositories/plan_repository.dart';

class GetPlansChantier {
  final PlanRepository repository;
  GetPlansChantier(this.repository);

  Future<Either<Failure, List<Plan>>> call(String chantierId) => repository.getPlansChantier(chantierId);
}
