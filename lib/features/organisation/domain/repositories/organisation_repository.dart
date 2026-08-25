import 'package:dartz/dartz.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/errors/failure.dart';
import '../entities/membre.dart';
import '../entities/partenaire.dart';

abstract class OrganisationRepository {
  Future<Either<Failure, List<Membre>>> getMembres();

  /// Partenaires / intervenants de l'organisation
  /// (`GET /organisation/partenaires`).
  Future<Either<Failure, List<Partenaire>>> getPartenaires();

  /// Création d'un partenaire — `POST /organisation/partenaires`, réservé
  /// côté back à ChefProjet / ConducteurTravaux / MaitreOuvrage /
  /// MaitreOeuvre.
  Future<Either<Failure, Partenaire>> creerPartenaire({
    required String nom,
    required PartenaireType type,
    String? email,
    String? telephone,
    String? contact,
    String? adresse,
    String? notes,
  });

  /// Active ou archive un intervenant — `PUT /partenaires/:id`.
  ///
  /// Réservé côté back à ChefProjet / ConducteurTravaux / MaitreOuvrage /
  /// MaitreOeuvre, comme la création : la présentation doit masquer l'action
  /// pour les autres rôles.
  Future<Either<Failure, Partenaire>> changerStatutPartenaire({
    required String partenaireId,
    required bool actif,
  });

  /// Change le statut d'un membre — `PUT /organisation/membres/:id`.
  ///
  /// [statut] doit valoir `'actif'`, `'inactif'` ou `'en_attente_validation'`
  /// (miroir de `modifierMembreSchema`). Le serveur refuse qu'un utilisateur
  /// modifie SON PROPRE statut : la présentation doit masquer l'action sur sa
  /// propre fiche.
  Future<Either<Failure, Membre>> changerStatutMembre({
    required String membreId,
    required String statut,
  });

  /// Réservé aux rôles GESTION (ChefProjet, MaitreOuvrage) côté backend —
  /// voir `requireRole(...GESTION)` sur `POST /organisation/membres`.
  /// [motDePasse] optionnel : si omis, le backend en génère un et le renvoie
  /// une seule fois dans [AjouterMembreResult.motDePasseTemporaire].
  Future<Either<Failure, AjouterMembreResult>> ajouterMembre({
    required String nom,
    required String prenom,
    required String email,
    required UserRole role,
    String? telephone,
    String? fonction,
    String? motDePasse,
  });
}
