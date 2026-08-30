import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/abonnement.dart';
import '../repositories/abonnement_repository.dart';

class GetFormules {
  final AbonnementRepository repository;
  GetFormules(this.repository);

  Future<Either<Failure, List<FormuleAbonnement>>> call() => repository.getFormules();
}
