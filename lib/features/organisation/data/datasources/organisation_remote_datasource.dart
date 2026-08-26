import 'package:dio/dio.dart';

import '../../../../core/network/dio_exception_mapper.dart';
import '../../domain/entities/membre.dart';
import '../../domain/entities/organisation.dart';
import '../../domain/entities/partenaire.dart';

abstract class OrganisationRemoteDataSource {
  /// Organisation de l'utilisateur connecté — `GET /organisation`.
  Future<Organisation> getMonOrganisation();

  /// Mise à jour de l'identité de l'organisation — `PUT /organisation`,
  /// réservé aux rôles GESTION côté serveur.
  Future<Organisation> modifierOrganisation(Map<String, dynamic> payload);

  Future<List<Membre>> getMembres();
  Future<AjouterMembreResult> ajouterMembre(Map<String, dynamic> payload);
  Future<Membre> modifierMembre(String membreId, Map<String, dynamic> payload);
  Future<List<Partenaire>> getPartenaires();
  Future<Partenaire> creerPartenaire(Map<String, dynamic> payload);
  Future<Partenaire> modifierPartenaire(String partenaireId, Map<String, dynamic> payload);
}

class OrganisationRemoteDataSourceImpl implements OrganisationRemoteDataSource {
  final Dio dio;
  OrganisationRemoteDataSourceImpl({required this.dio});

  Map<String, dynamic> _data(Response response) =>
      (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;

  @override
  Future<Organisation> getMonOrganisation() async {
    try {
      final response = await dio.get('/organisation');
      return Organisation.fromJson(_data(response)['organisation'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Organisation> modifierOrganisation(Map<String, dynamic> payload) async {
    try {
      final response = await dio.put('/organisation', data: payload);
      return Organisation.fromJson(_data(response)['organisation'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<Membre>> getMembres() async {
    try {
      // Plafond serveur à 100 (voir pagination.middleware.js) — largement
      // suffisant pour l'effectif d'une organisation ; pas de pagination
      // dédiée côté mobile pour cette première version de l'écran.
      final response = await dio.get('/organisation/membres', queryParameters: {'limit': 100});
      final membres = _data(response)['membres'] as List;
      return membres.map((e) => Membre.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<Partenaire>> getPartenaires() async {
    try {
      final response = await dio.get('/organisation/partenaires');
      final partenaires = _data(response)['partenaires'] as List;
      return partenaires.map((e) => Partenaire.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Partenaire> creerPartenaire(Map<String, dynamic> payload) async {
    try {
      final response = await dio.post('/organisation/partenaires', data: payload);
      return Partenaire.fromJson(_data(response)['partenaire'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// `PUT /partenaires/:id` — accepte nom, type, email, telephone, contact,
  /// adresse, notes et actif (voir `modifierPartenaireSchema` côté back).
  ///
  /// Réservé à ChefProjet / ConducteurTravaux / MaitreOuvrage / MaitreOeuvre :
  /// l'appelant doit masquer l'action pour les autres rôles plutôt que de
  /// laisser découvrir le 403 après coup.
  @override
  Future<Partenaire> modifierPartenaire(String partenaireId, Map<String, dynamic> payload) async {
    try {
      final response = await dio.put('/partenaires/$partenaireId', data: payload);
      return Partenaire.fromJson(_data(response)['partenaire'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// `PUT /organisation/membres/:id` — accepte nom, prenom, telephone,
  /// fonction, role et statut (voir `modifierMembreSchema` côté back).
  ///
  /// Le serveur REFUSE que l'acteur modifie son propre rôle, statut ou
  /// permissions (garde anti auto-promotion dans
  /// `OrganisationService.modifierMembre`) : l'appelant doit donc masquer ces
  /// actions sur sa propre fiche plutôt que de laisser l'utilisateur
  /// découvrir le refus après coup.
  @override
  Future<Membre> modifierMembre(String membreId, Map<String, dynamic> payload) async {
    try {
      final response = await dio.put('/organisation/membres/$membreId', data: payload);
      return Membre.fromJson(_data(response)['utilisateur'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<AjouterMembreResult> ajouterMembre(Map<String, dynamic> payload) async {
    try {
      final response = await dio.post('/organisation/membres', data: payload);
      final data = _data(response);
      return AjouterMembreResult(
        membre: Membre.fromJson(data['utilisateur'] as Map<String, dynamic>),
        motDePasseTemporaire: data['motDePasseTemporaire'] as String?,
      );
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
