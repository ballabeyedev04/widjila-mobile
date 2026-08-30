import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/partenaire.dart';
import '../repositories/organisation_repository.dart';

class CreerPartenaire {
  final OrganisationRepository repository;
  CreerPartenaire(this.repository);

  Future<Either<Failure, Partenaire>> call({
    required String nom,
    /// CODE du type, issu du référentiel administrable
    /// (`/types-intervenant/actifs`). Une énumération figée ici
    /// empêcherait d'utiliser un type ajouté par l'administrateur.
    required String typeCode,
    String? email,
    String? telephone,
    String? contact,
    String? adresse,
    String? notes,
  }) {
    return repository.creerPartenaire(
      nom: nom,
      typeCode: typeCode,
      email: email,
      telephone: telephone,
      contact: contact,
      adresse: adresse,
      notes: notes,
    );
  }
}
