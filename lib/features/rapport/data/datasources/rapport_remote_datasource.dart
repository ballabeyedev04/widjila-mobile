import 'package:dio/dio.dart';

import '../../../../core/network/dio_exception_mapper.dart';
import '../../domain/entities/envoi_rapport.dart';
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

  /// Compose l'e-mail SANS l'envoyer — l'écran de vérification.
  Future<EnvoiRapport> preparerEnvoi(String rapportId);

  /// Envoie réellement, sur confirmation. [exclure] ne porte que des
  /// RETRAITS : le serveur recalcule les destinataires et refuse toute
  /// adresse ajoutée par le client.
  Future<String> envoyerRapport(String rapportId, {List<String> exclure});
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

  @override
  Future<EnvoiRapport> preparerEnvoi(String rapportId) async {
    try {
      final response = await dio.get('/rapports/$rapportId/envoi');
      return EnvoiRapport.fromJson(_data(response)['envoi'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  @override
  Future<String> envoyerRapport(String rapportId, {List<String> exclure = const []}) async {
    try {
      final response = await dio.post('/rapports/$rapportId/envoi', data: {'exclure': exclure});
      // Le message du serveur dit qui a reçu quoi — le reprendre tel quel
      // vaut mieux qu'un « Envoyé » qui n'apprend rien.
      return (response.data as Map<String, dynamic>)['message']?.toString() ?? '';
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }
}
