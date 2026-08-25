import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../entities/membre.dart';
import '../repositories/organisation_repository.dart';

/// Active ou désactive un membre de l'organisation.
///
/// Un membre `inactif` conserve son compte et son historique — ses réserves,
/// commentaires et signatures restent attribués — mais ne peut plus se
/// connecter (`checkActiveUser.middleware.js` côté back). C'est la sortie
/// prévue pour un collaborateur qui quitte le chantier, là où la SUPPRESSION
/// déclenche une pseudonymisation irréversible.
class ChangerStatutMembre {
  final OrganisationRepository repository;
  ChangerStatutMembre(this.repository);

  /// Valeurs acceptées par `modifierMembreSchema` côté serveur.
  static const String actif = 'actif';
  static const String inactif = 'inactif';

  Future<Either<Failure, Membre>> call({
    required String membreId,
    required String statut,
  }) =>
      repository.changerStatutMembre(membreId: membreId, statut: statut);
}
