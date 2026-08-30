import 'package:dio/dio.dart';

import '../../../../core/network/dio_exception_mapper.dart';
import '../../domain/entities/type_referentiel.dart';

abstract class ReferentielRemoteDataSource {
  Future<List<TypeReferentiel>> getTypesActifs(ReferentielType referentiel);
}

class ReferentielRemoteDataSourceImpl implements ReferentielRemoteDataSource {
  final Dio dio;
  ReferentielRemoteDataSourceImpl({required this.dio});

  @override
  Future<List<TypeReferentiel>> getTypesActifs(ReferentielType referentiel) async {
    try {
      // `/actifs` et non la liste paginée : un sélecteur doit tout montrer
      // d'un coup, et les types désactivés n'ont rien à y faire.
      final response = await dio.get('${referentiel.chemin}/actifs');
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return (data['types'] as List)
          .map((e) => TypeReferentiel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
