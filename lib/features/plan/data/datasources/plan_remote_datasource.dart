import 'package:dio/dio.dart';

import '../../../../core/network/dio_exception_mapper.dart';
import '../../domain/entities/plan.dart';

abstract class PlanRemoteDataSource {
  Future<List<Plan>> getTousPlans();
  Future<List<Plan>> getPlansChantier(String chantierId);
  Future<Plan> getPlanDetail(String id);

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
        'fichier': await MultipartFile.fromFile(cheminFichier),
      });
      final response = await dio.post('/chantiers/$chantierId/plans', data: formData);
      return Plan.fromJson(_data(response)['plan'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
