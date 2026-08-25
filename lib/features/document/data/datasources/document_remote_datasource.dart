import 'package:dio/dio.dart';
import '../../../../core/network/dio_exception_mapper.dart';
import '../../domain/entities/document.dart';

abstract class DocumentRemoteDataSource {
  Future<List<ChantierDocument>> getDocuments({required String chantierId, String? search, DocumentType? type});

  Future<ChantierDocument> ajouterDocument({
    required String chantierId,
    required String cheminFichier,
    required DocumentType type,
  });
}

class DocumentRemoteDataSourceImpl implements DocumentRemoteDataSource {
  final Dio dio;
  DocumentRemoteDataSourceImpl({required this.dio});

  @override
  Future<List<ChantierDocument>> getDocuments({required String chantierId, String? search, DocumentType? type}) async {
    try {
      final response = await dio.get('/chantiers/$chantierId/documents', queryParameters: {
        if (search != null && search.isNotEmpty) 'search': search,
        if (type != null) 'type': type.raw,
      });
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return (data['documents'] as List).map((e) => ChantierDocument.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<ChantierDocument> ajouterDocument({
    required String chantierId,
    required String cheminFichier,
    required DocumentType type,
  }) async {
    try {
      final formData = FormData.fromMap({
        'type': type.raw,
        'fichier': await MultipartFile.fromFile(cheminFichier),
      });
      final response = await dio.post('/chantiers/$chantierId/documents', data: formData);
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return ChantierDocument.fromJson(data['document'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
