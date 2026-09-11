import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../../../../core/network/dio_exception_mapper.dart';
import '../../../../core/network/options_envoi_fichier.dart';
import '../../domain/entities/document.dart';
import '../../domain/formats_document.dart';

abstract class DocumentRemoteDataSource {
  Future<List<ChantierDocument>> getDocuments({required String chantierId, String? search, DocumentType? type});

  /// [nomFichier] : nom enregistré dans la GED. Par défaut, celui du fichier
  /// sur l'appareil — souvent un nom de cache illisible quand il vient d'un
  /// sélecteur de fichiers, d'où la possibilité de passer le nom d'origine.
  ///
  /// [onProgression] : part du fichier déjà envoyée, de 0 à 1.
  Future<ChantierDocument> ajouterDocument({
    required String chantierId,
    required String cheminFichier,
    required DocumentType type,
    String? nomFichier,
    void Function(double progression)? onProgression,
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
    String? nomFichier,
    void Function(double progression)? onProgression,
  }) async {
    final nom = (nomFichier == null || nomFichier.trim().isEmpty) ? p.basename(cheminFichier) : nomFichier.trim();
    try {
      final formData = FormData.fromMap({
        'type': type.raw,
        // Type MIME posé explicitement : le serveur le confronte au contenu
        // réel, et la déduction automatique de Dio ne connaît pas tous les
        // formats métier (DWG).
        'fichier': await MultipartFile.fromFile(
          cheminFichier,
          filename: nom,
          contentType: DioMediaType.parse(FormatsDocument.typeMime(nom)),
        ),
      });
      final response = await dio.post(
        '/chantiers/$chantierId/documents',
        data: formData,
        // Une vidéo sur la 4G d'un chantier ne tient pas dans les 30 s par
        // défaut du client — voir `optionsEnvoiFichier`.
        options: optionsEnvoiFichier(),
        onSendProgress: onProgression == null
            ? null
            : (envoye, total) {
                if (total > 0) onProgression(envoye / total);
              },
      );
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      return ChantierDocument.fromJson(data['document'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
