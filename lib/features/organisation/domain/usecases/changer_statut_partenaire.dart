import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/partenaire.dart';
import '../repositories/organisation_repository.dart';

/// Active ou archive un intervenant de l'annuaire.
///
/// Pendant exact de [ChangerStatutMembre] pour les partenaires : un
/// intervenant `inactif` reste dans l'annuaire avec tout son historique —
/// on cesse simplement de le proposer comme intervenant courant. C'est la
/// sortie prévue pour une entreprise dont le lot est terminé, là où la
/// SUPPRESSION (réservée au chef de projet) retire la fiche pour de bon.
class ChangerStatutPartenaire {
  final OrganisationRepository repository;
  ChangerStatutPartenaire(this.repository);

  Future<Either<Failure, Partenaire>> call({
    required String partenaireId,
    required bool actif,
  }) =>
      repository.changerStatutPartenaire(partenaireId: partenaireId, actif: actif);
}
