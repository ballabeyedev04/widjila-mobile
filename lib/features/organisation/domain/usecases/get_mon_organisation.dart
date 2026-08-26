import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/organisation.dart';
import '../repositories/organisation_repository.dart';

class GetMonOrganisation {
  final OrganisationRepository repository;
  GetMonOrganisation(this.repository);

  Future<Either<Failure, Organisation>> call() => repository.getMonOrganisation();
}
