import 'package:dartz/dartz.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/membre.dart';
import '../../domain/entities/organisation.dart';
import '../../domain/entities/partenaire.dart';
import '../../domain/repositories/organisation_repository.dart';
import '../datasources/organisation_remote_datasource.dart';

class OrganisationRepositoryImpl implements OrganisationRepository {
  final OrganisationRemoteDataSource remoteDataSource;
  OrganisationRepositoryImpl(this.remoteDataSource);

  @override
  Future<Either<Failure, Organisation>> getMonOrganisation() async {
    try {
      return Right(await remoteDataSource.getMonOrganisation());
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
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
  }) async {
    try {
      // Seules les clés RENSEIGNÉES partent : le schéma Joi valide avec
      // `stripUnknown` et traite chaque champ comme optionnel, mais envoyer
      // `null` sur un champ non touché l'effacerait en base.
      final payload = <String, dynamic>{
        'nom': ?nom,
        'raison_sociale': ?raisonSociale,
        'siret': ?siret,
        'num_tva': ?numTva,
        'rccm': ?rccm,
        'ninea': ?ninea,
        'telephone': ?telephone,
        'email': ?email,
        'adresse': ?adresse,
        'ville': ?ville,
        'pays': ?pays,
      };
      return Right(await remoteDataSource.modifierOrganisation(payload));
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<Membre>>> getMembres() async {
    try {
      final membres = await remoteDataSource.getMembres();
      return Right(membres);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, List<Partenaire>>> getPartenaires() async {
    try {
      return Right(await remoteDataSource.getPartenaires());
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
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
  }) async {
    try {
      // Les champs vides sont OMIS plutôt qu'envoyés à `''` :
      // `creerPartenaireSchema` les tolère, mais une chaîne vide en base se
      // relit ensuite comme une valeur renseignée et fait afficher une ligne
      // « Email : » sans email.
      final partenaire = await remoteDataSource.creerPartenaire({
        'nom': nom,
        'type': typeCode,
        if (email != null && email.isNotEmpty) 'email': email,
        if (telephone != null && telephone.isNotEmpty) 'telephone': telephone,
        if (contact != null && contact.isNotEmpty) 'contact': contact,
        if (adresse != null && adresse.isNotEmpty) 'adresse': adresse,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      });
      return Right(partenaire);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, Partenaire>> changerStatutPartenaire({
    required String partenaireId,
    required bool actif,
  }) async {
    try {
      final partenaire = await remoteDataSource.modifierPartenaire(partenaireId, {'actif': actif});
      return Right(partenaire);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, Membre>> changerStatutMembre({
    required String membreId,
    required String statut,
  }) async {
    try {
      final membre = await remoteDataSource.modifierMembre(membreId, {'statut': statut});
      return Right(membre);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }

  @override
  Future<Either<Failure, AjouterMembreResult>> ajouterMembre({
    required String nom,
    required String prenom,
    required String email,
    required UserRole role,
    String? telephone,
    String? fonction,
    String? motDePasse,
  }) async {
    try {
      final resultat = await remoteDataSource.ajouterMembre({
        'nom': nom,
        'prenom': prenom,
        'email': email,
        'role': role.raw,
        if (telephone != null && telephone.isNotEmpty) 'telephone': telephone,
        if (fonction != null && fonction.isNotEmpty) 'fonction': fonction,
        if (motDePasse != null && motDePasse.isNotEmpty) 'mot_de_passe': motDePasse,
      });
      return Right(resultat);
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
  }
}
