import 'package:dio/dio.dart';

import '../../../../core/network/dio_exception_mapper.dart';

/// Observations déjà saisies par l'utilisateur — `GET /reserves/observations`
/// (backend : `observations.service.js`). Alimente les suggestions du champ
/// « Observation » de la création d'une réserve.
class ObservationsRemoteDataSource {
  final Dio _dio;

  const ObservationsRemoteDataSource(this._dio);

  /// Les [limite] observations les plus employées puis les plus récentes.
  Future<List<String>> observationsUtilisees({int limite = 100}) async {
    try {
      final reponse = await _dio.get<dynamic>('/reserves/observations', queryParameters: {'limit': limite});
      final corps = reponse.data;
      final donnees = corps is Map ? corps['data'] : null;
      final liste = donnees is Map ? donnees['observations'] : null;
      if (liste is! List) return const [];
      return liste.whereType<String>().toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
