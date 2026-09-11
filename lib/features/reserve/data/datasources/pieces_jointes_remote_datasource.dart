import 'package:dio/dio.dart';

import '../../../../core/network/dio_exception_mapper.dart';
import '../../../../core/network/options_envoi_fichier.dart';
import '../../../document/domain/formats_document.dart';
import '../../domain/entities/piece_jointe.dart';

abstract class PiecesJointesRemoteDataSource {
  /// `GET /reserves/:id/pieces`.
  Future<List<PieceJointe>> lister(String reserveId);

  /// `POST /reserves/:id/pieces` — multipart, champ `fichier`.
  Future<PieceJointe> ajouter(
    String reserveId, {
    required String cheminFichier,
    required String nomFichier,
    void Function(double progression)? onProgression,
  });

  /// `DELETE /reserves/pieces/:pieceId`.
  Future<void> supprimer(String pieceId);
}

class PiecesJointesRemoteDataSourceImpl implements PiecesJointesRemoteDataSource {
  final Dio dio;
  PiecesJointesRemoteDataSourceImpl({required this.dio});

  Map<String, dynamic> _data(Response<dynamic> response) =>
      (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;

  @override
  Future<List<PieceJointe>> lister(String reserveId) async {
    try {
      final response = await dio.get('/reserves/$reserveId/pieces');
      return (_data(response)['pieces'] as List? ?? [])
          .map((e) => PieceJointe.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<PieceJointe> ajouter(
    String reserveId, {
    required String cheminFichier,
    required String nomFichier,
    void Function(double progression)? onProgression,
  }) async {
    try {
      final formData = FormData.fromMap({
        // Type MIME explicite : le serveur le confronte au contenu réel, et
        // Dio ne connaît pas tous les formats métier (DWG).
        'fichier': await MultipartFile.fromFile(
          cheminFichier,
          filename: nomFichier,
          contentType: DioMediaType.parse(FormatsDocument.typeMime(nomFichier)),
        ),
      });
      final response = await dio.post(
        '/reserves/$reserveId/pieces',
        data: formData,
        options: optionsEnvoiFichier(),
        onSendProgress: onProgression == null
            ? null
            : (envoye, total) {
                if (total > 0) onProgression(envoye / total);
              },
      );
      return PieceJointe.fromJson(_data(response)['piece'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<void> supprimer(String pieceId) async {
    try {
      await dio.delete('/reserves/pieces/$pieceId');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
