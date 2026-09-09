import 'package:dio/dio.dart';

import '../../../../core/network/dio_exception_mapper.dart';
import '../../domain/entities/plan.dart';

abstract class PlanRemoteDataSource {
  Future<List<Plan>> getTousPlans();
  Future<List<Plan>> getPlansChantier(String chantierId);

  /// Plans GLOBAUX d'un chantier — ceux qui n'ont pas de parent.
  ///
  /// C'est le point d'entrée de la navigation par niveau, et il est distinct
  /// de [getPlansChantier], qui renvoie l'arborescence À PLAT (plans globaux,
  /// plans de bâtiment, plans d'étage et plans de détail mélangés).
  Future<List<Plan>> getPlansRacines(String chantierId);

  /// Sous-plans DIRECTS d'un plan — jamais les sous-plans de ceux-là.
  Future<List<Plan>> getSousPlans(String planId);

  Future<Plan> getPlanDetail(String id);

  /// `DELETE /plans/:id` — retire le plan et ses versions.
  Future<void> supprimerPlan(String id);

  /// `POST /plans/:id/versions` — REMPLACE le document d'un plan.
  ///
  /// Une nouvelle version, pas un nouveau plan : le nom, le rattachement et
  /// les réserves déjà posées sont conservés, et l'historique garde la version
  /// précédente. C'est ce que veut dire « Remplacer » pour l'utilisateur, et
  /// c'est le seul geste qui ne perd rien.
  Future<Plan> remplacerFichier(String id, {required String cheminFichier});

  Future<Plan> uploaderPlan({
    required String chantierId,
    required String cheminFichier,
    required String nom,
    PlanFormat? format,
    /// Niveau décrit par le plan — AU PLUS un des trois. Aucun des trois : le
    /// plan est le plan global du chantier.
    String? batimentId,
    String? etageId,
    String? zoneId,
    String? parentId,
    /// Discipline du plan et date DU PLAN — cahier technique § 4.
    /// Facultatives : un chantier qui n'a qu'un jeu de plans n'a rien à
    /// distinguer, et une date inconnue vaut mieux qu'une date inventée.
    String? typePlan,
    DateTime? datePlan,
  });
}

class PlanRemoteDataSourceImpl implements PlanRemoteDataSource {
  final Dio dio;
  PlanRemoteDataSourceImpl({required this.dio});

  Map<String, dynamic> _data(Response response) =>
      (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;

  List<Plan> _plans(Response response) =>
      (_data(response)['plans'] as List).map((e) => Plan.fromJson(e as Map<String, dynamic>)).toList();

  @override
  Future<List<Plan>> getTousPlans() async {
    try {
      return _plans(await dio.get('/plans'));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<List<Plan>> getPlansChantier(String chantierId) async {
    try {
      return _plans(await dio.get('/chantiers/$chantierId/plans'));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// `GET /chantiers/:chantierId/plans/racines`.
  ///
  /// Le serveur ne renvoie qu'une version par plan (la plus récente) et joint
  /// à chacun ses compteurs — combien de sous-plans, combien de réserves. Ce
  /// sont eux qui disent à la tuile si elle fait descendre d'un cran ou si
  /// elle ouvre la zone de travail.
  @override
  Future<List<Plan>> getPlansRacines(String chantierId) async {
    try {
      return _plans(await dio.get('/chantiers/$chantierId/plans/racines'));
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// `GET /plans/:id/sous-plans` — un seul cran, jamais l'arborescence.
  ///
  /// La réponse porte la liste sous la clé `sousPlans` et non `plans` : c'est
  /// la seule différence de forme avec [getPlansRacines], les objets sont
  /// identiques, compteurs compris.
  @override
  Future<List<Plan>> getSousPlans(String planId) async {
    try {
      final response = await dio.get('/plans/$planId/sous-plans');
      return (_data(response)['sousPlans'] as List)
          .map((e) => Plan.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> supprimerPlan(String id) async {
    try {
      await dio.delete('/plans/$id');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Plan> remplacerFichier(String id, {required String cheminFichier}) async {
    try {
      final formData = FormData.fromMap({
        'fichier': await MultipartFile.fromFile(cheminFichier),
      });
      final response = await dio.post('/plans/$id/versions', data: formData);
      return Plan.fromJson(_data(response)['plan'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Plan> getPlanDetail(String id) async {
    try {
      final response = await dio.get('/plans/$id');
      return Plan.fromJson(_data(response)['plan'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  /// `POST /chantiers/:chantierId/plans` — multipart, champ `fichier`
  /// (voir `backend/src/modules/plan/route/plan.route.js`). Le back vérifie
  /// les magic bytes du fichier : un PDF renommé en .png est rejeté.
  @override
  Future<Plan> uploaderPlan({
    required String chantierId,
    required String cheminFichier,
    required String nom,
    PlanFormat? format,
    /// Niveau décrit par le plan — AU PLUS un des trois. Aucun des trois : le
    /// plan est le plan global du chantier.
    String? batimentId,
    String? etageId,
    String? zoneId,
    String? parentId,
    /// Discipline du plan et date DU PLAN — cahier technique § 4.
    /// Facultatives : un chantier qui n'a qu'un jeu de plans n'a rien à
    /// distinguer, et une date inconnue vaut mieux qu'une date inventée.
    String? typePlan,
    DateTime? datePlan,
  }) async {
    try {
      final formData = FormData.fromMap({
        'nom': nom,
        if (format != null) 'format': format.raw,
        // Les rattachements vides sont OMIS : le schéma tolère la chaîne vide,
        // mais l'envoyer ferait échouer la validation UUID côté serveur.
        if (batimentId != null && batimentId.isNotEmpty) 'batimentId': batimentId,
        if (etageId != null && etageId.isNotEmpty) 'etageId': etageId,
        if (zoneId != null && zoneId.isNotEmpty) 'zoneId': zoneId,
        // Le PARENT prime : le serveur ignore alors le rattachement de
        // structure et fait hériter le détail de la place de son parent.
        if (parentId != null && parentId.isNotEmpty) 'parentId': parentId,
        // Discipline et date DU PLAN — cahier technique § 4. Omises quand
        // elles ne sont pas renseignées : le schéma Joi tolère la chaîne vide,
        // mais l'envoyer ferait échouer la validation de date côté serveur.
        if (typePlan != null && typePlan.isNotEmpty) 'type_plan': typePlan,
        if (datePlan != null) 'date_plan': datePlan.toIso8601String().split('T').first,
        'fichier': await MultipartFile.fromFile(cheminFichier),
      });
      final response = await dio.post('/chantiers/$chantierId/plans', data: formData);
      return Plan.fromJson(_data(response)['plan'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
