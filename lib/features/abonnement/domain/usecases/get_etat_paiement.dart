import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/abonnement.dart';
import '../repositories/abonnement_repository.dart';

class GetEtatPaiement {
  final AbonnementRepository repository;
  GetEtatPaiement(this.repository);

  Future<Either<Failure, EtatPaiement?>> call() => repository.getEtatPaiement();
}
