import 'package:dio/dio.dart';

import '../../../../core/network/dio_exception_mapper.dart';

/// « Contacter le support » — `POST /support/messages`.
///
/// Le serveur transmet la demande par email à l'adresse du support, avec
/// l'utilisateur en réponse. Aucune adresse n'est connue du mobile : elle ne
/// peut donc ni fuiter ni devenir périmée dans une version installée.
class SupportRemoteDataSource {
  final Dio dio;
  const SupportRemoteDataSource({required this.dio});

  /// Renvoie le message de confirmation du serveur.
  Future<String> envoyerMessage({
    required String sujet,
    required String message,
    Map<String, String>? contexte,
  }) async {
    try {
      final response = await dio.post('/support/messages', data: {
        'sujet': sujet,
        'message': message,
        if (contexte != null && contexte.isNotEmpty) 'contexte': contexte,
      });
      return ((response.data as Map<String, dynamic>)['message'] as String?) ?? '';
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
