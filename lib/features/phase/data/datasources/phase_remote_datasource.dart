import 'package:dio/dio.dart';

import '../../../../core/network/dio_exception_mapper.dart';
import '../../domain/entities/phase_referentiel.dart';

abstract class PhaseRemoteDataSource {
  Future<List<PhaseReferentiel>> getPhasesActives();
}

class PhaseRemoteDataSourceImpl implements PhaseRemoteDataSource {
  final Dio dio;
  PhaseRemoteDataSourceImpl({required this.dio});

  Map<String, dynamic> _data(Response response) =>
      (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;

  @override
  Future<List<PhaseReferentiel>> getPhasesActives() async {
    try {
      // `/phases/actives` — le RÉFÉRENTIEL, à ne pas confondre avec
      // `/chantiers/:id/phases`, qui sert le planning d'un chantier.
      final response = await dio.get('/phases/actives');
      return (_data(response)['phases'] as List)
          .map((e) => PhaseReferentiel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
