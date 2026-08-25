import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/membre.dart';
import '../repositories/organisation_repository.dart';

class GetMembres {
  final OrganisationRepository repository;
  GetMembres(this.repository);

  Future<Either<Failure, List<Membre>>> call() => repository.getMembres();
}
