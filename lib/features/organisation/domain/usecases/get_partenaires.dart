import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/partenaire.dart';
import '../repositories/organisation_repository.dart';

class GetPartenaires {
  final OrganisationRepository repository;
  GetPartenaires(this.repository);

  Future<Either<Failure, List<Partenaire>>> call() => repository.getPartenaires();
}
