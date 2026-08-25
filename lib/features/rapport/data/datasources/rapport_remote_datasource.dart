import 'package:dio/dio.dart';

import '../../../../core/network/dio_exception_mapper.dart';
import '../../domain/entities/rapport.dart';

abstract class RapportRemoteDataSource {
  Future<List<Rapport>> getRapports(String chantierId);
  Future<Rapport> genererRapport({
    required String chantierId,
    required RapportType type,
    String? statutReserve,
    String? entrepriseId,
    String? batimentId,
  });
  Future<void> supprimerRapport(String id);
}

class RapportRemoteDataSourceImpl implements RapportRemoteDataSource {
  final Dio dio;
  RapportRemoteDataSourceImpl({required this.dio});

  Map<String, dynamic> _data(Response response) =>
      (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;

  @override
  Future<List<Rapport>> getRapports(String chantierId) async {
    try {
      final response = await dio.get('/chantiers/$chantierId/rapports');
      return (_data(response)['rapports'] as List)
          .map((e) => Rapport.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<Rapport> genererRapport({
    required String chantierId,
    required RapportType type,
    String? statutReserve,
    String? entrepriseId,
    String? batimentId,
  }) async {
    try {
      final response = await dio.post('/chantiers/$chantierId/rapports/generer', data: {
        'chantierId': chantierId,
        'type': type.raw,
        if (statutReserve != null) 'statut': statutReserve,
        if (entrepriseId != null) 'entrepriseId': entrepriseId,
        if (batimentId != null) 'batimentId': batimentId,
      });
      return Rapport.fromJson(_data(response)['rapport'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> supprimerRapport(String id) async {
    try {
      await dio.delete('/rapports/$id');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
