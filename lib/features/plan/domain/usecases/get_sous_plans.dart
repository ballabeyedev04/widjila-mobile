import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/plan.dart';
import '../repositories/plan_repository.dart';

/// Les sous-plans DIRECTS d'un plan — un seul cran plus bas.
///
/// Jamais les sous-plans de ceux-là : la navigation est progressive, et c'est
/// l'appui suivant qui descendra encore d'un cran. Renvoyer l'arborescence
/// entière obligerait l'écran à la filtrer et afficherait des plans que
/// personne ne regarde encore.
class GetSousPlans {
  final PlanRepository repository;
  GetSousPlans(this.repository);

  Future<Either<Failure, List<Plan>>> call(String planId) => repository.getSousPlans(planId);
}
