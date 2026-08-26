import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/organisation.dart';
import '../repositories/organisation_repository.dart';

/// Mise à jour de l'identité de l'organisation — réservée aux rôles GESTION
/// côté serveur (voir [OrganisationRepository.modifierOrganisation]).
class ModifierOrganisation {
  final OrganisationRepository repository;
  ModifierOrganisation(this.repository);

  Future<Either<Failure, Organisation>> call({
    String? nom,
    String? raisonSociale,
    String? siret,
    String? numTva,
    String? rccm,
    String? ninea,
    String? telephone,
    String? email,
    String? adresse,
    String? ville,
    String? pays,
  }) =>
      repository.modifierOrganisation(
        nom: nom,
        raisonSociale: raisonSociale,
        siret: siret,
        numTva: numTva,
        rccm: rccm,
        ninea: ninea,
        telephone: telephone,
        email: email,
        adresse: adresse,
        ville: ville,
        pays: pays,
      );
}
