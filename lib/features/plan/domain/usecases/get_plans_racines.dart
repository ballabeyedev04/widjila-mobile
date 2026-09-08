import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/plan.dart';
import '../repositories/plan_repository.dart';

/// Les plans GLOBAUX d'un chantier — le premier cran de la navigation.
///
/// À ne pas confondre avec `GetPlansChantier`, qui renvoie l'arborescence à
/// plat : ici on n'obtient que les plans SANS parent, ceux par lesquels le
/// parcours commence. La descente se poursuit avec [GetSousPlans].
class GetPlansRacines {
  final PlanRepository repository;
  GetPlansRacines(this.repository);

  Future<Either<Failure, List<Plan>>> call(String chantierId) =>
      repository.getPlansRacines(chantierId);
}
