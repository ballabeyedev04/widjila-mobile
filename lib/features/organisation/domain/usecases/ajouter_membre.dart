import 'package:dartz/dartz.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/errors/failure.dart';
import '../entities/membre.dart';
import '../repositories/organisation_repository.dart';

class AjouterMembre {
  final OrganisationRepository repository;
  AjouterMembre(this.repository);

  Future<Either<Failure, AjouterMembreResult>> call({
    required String nom,
    required String prenom,
    required String email,
    required UserRole role,
    String? telephone,
    String? fonction,
    String? motDePasse,
  }) {
    return repository.ajouterMembre(
      nom: nom,
      prenom: prenom,
      email: email,
      role: role,
      telephone: telephone,
      fonction: fonction,
      motDePasse: motDePasse,
    );
  }
}
