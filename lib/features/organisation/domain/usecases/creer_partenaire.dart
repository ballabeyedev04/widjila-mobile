import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/partenaire.dart';
import '../repositories/organisation_repository.dart';

class CreerPartenaire {
  final OrganisationRepository repository;
  CreerPartenaire(this.repository);

  Future<Either<Failure, Partenaire>> call({
    required String nom,
    required PartenaireType type,
    String? email,
    String? telephone,
    String? contact,
    String? adresse,
    String? notes,
  }) {
    return repository.creerPartenaire(
      nom: nom,
      type: type,
      email: email,
      telephone: telephone,
      contact: contact,
      adresse: adresse,
      notes: notes,
    );
  }
}
