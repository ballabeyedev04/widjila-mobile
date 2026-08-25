import 'package:dio/dio.dart';
import '../../../../core/network/dio_exception_mapper.dart';
import '../../domain/entities/dashboard_stats.dart';

abstract class DashboardRemoteDataSource {
  Future<DashboardStats> getStatsGlobales();
}

class DashboardRemoteDataSourceImpl implements DashboardRemoteDataSource {
  final Dio dio;
  DashboardRemoteDataSourceImpl({required this.dio});

  @override
  Future<DashboardStats> getStatsGlobales() async {
    try {
      final response = await dio.get('/dashboard');
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return DashboardStats.fromJson(data['stats'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
