import 'package:dartz/dartz.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/errors/failure.dart';
import '../entities/membre.dart';
import '../entities/organisation.dart';
import '../entities/partenaire.dart';

abstract class OrganisationRepository {
  /// Organisation de l'utilisateur connecté (`GET /organisation`).
  Future<Either<Failure, Organisation>> getMonOrganisation();

  /// Met à jour l'identité de l'organisation (`PUT /organisation`).
  ///
  /// Réservé aux rôles GESTION côté serveur : la présentation doit masquer
  /// l'action pour les autres, sinon l'utilisateur découvre son absence de
  /// droits par un 403 après avoir rempli le formulaire.
  /// Seuls les champs FOURNIS sont modifiés — passer `null` laisse la valeur
  /// existante intacte.
  Future<Either<Failure, Organisation>> modifierOrganisation({
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
  });

  Future<Either<Failure, List<Membre>>> getMembres();

  /// Partenaires / intervenants de l'organisation
  /// (`GET /organisation/partenaires`).
  Future<Either<Failure, List<Partenaire>>> getPartenaires();

  /// Création d'un partenaire — `POST /organisation/partenaires`, réservé
  /// côté back à ChefProjet / ConducteurTravaux / MaitreOuvrage /
  /// MaitreOeuvre.
  Future<Either<Failure, Partenaire>> creerPartenaire({
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
