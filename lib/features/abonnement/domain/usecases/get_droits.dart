import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/abonnement.dart';
import '../repositories/abonnement_repository.dart';

class GetDroits {
  final AbonnementRepository repository;
  GetDroits(this.repository);

  Future<Either<Failure, DroitsAbonnement>> call() => repository.getDroits();
}
