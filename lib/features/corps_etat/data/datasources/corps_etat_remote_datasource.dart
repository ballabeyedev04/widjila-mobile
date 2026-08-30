import 'package:dio/dio.dart';

import '../../../../core/network/dio_exception_mapper.dart';
import '../../domain/entities/corps_etat.dart';

abstract class CorpsEtatRemoteDataSource {
  Future<List<CorpsEtat>> getCorpsEtatActifs();
}

class CorpsEtatRemoteDataSourceImpl implements CorpsEtatRemoteDataSource {
  final Dio dio;
  CorpsEtatRemoteDataSourceImpl({required this.dio});

  Map<String, dynamic> _data(Response response) =>
      (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;

  @override
  Future<List<CorpsEtat>> getCorpsEtatActifs() async {
    try {
      // `/actifs` et non `/corps-etat` : cette route renvoie la liste
      // COMPLÈTE des métiers actifs, sans pagination. Une liste déroulante
      // doit pouvoir tout montrer d'un coup, et les métiers désactivés n'ont
      // rien à y faire.
      final response = await dio.get('/corps-etat/actifs');
      return (_data(response)['corpsEtat'] as List)
          .map((e) => CorpsEtat.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
