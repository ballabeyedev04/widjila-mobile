import 'package:dio/dio.dart';
import '../errors/error_codes.dart';
import '../errors/exceptions.dart';

/// Convertit une [DioException] en exception typée du domaine (`data`
/// layer). Centralise ce mapping ici plutôt que de le dupliquer dans chaque
/// `*_remote_datasource.dart` — un seul endroit à corriger si le format
/// d'erreur du backend change, et les repositories n'ont plus besoin de
/// connaître Dio (ils catchent [ServerException]/[NetworkException]/
/// [UnauthorizedException], définies dans `core/errors/exceptions.dart`).
///
/// Contrat backend (voir `backend/src/middlewares/errorHandler.middleware.js`) :
/// toute erreur répond `{ success: false, message, details? }`.
Exception mapDioException(DioException e) {
  if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.connectionError) {
    return const NetworkException();
  }

  final statusCode = e.response?.statusCode;
  final data = e.response?.data;
  // `e.message` peut déjà porter un des marqueurs `ErrCodes` posés par
  // l'intercepteur (`dio_client_factory.dart`) — dans ce cas on le laisse
  // passer tel quel, `AppAlert` le traduira. Le seul cas restant sans AUCUN
  // message exploitable (ni backend, ni marqueur) retombe sur `ErrCodes
  // .generic`, jamais un texte en dur.
  final baseMessage = (data is Map && data['message'] is String)
      ? data['message'] as String
      : (e.message ?? ErrCodes.generic);

  // `ValidationError` (422, voir validate.middleware.js) renvoie un message
  // générique (« Données invalides ») ACCOMPAGNÉ d'un détail par champ Joi en
  // échec dans `details`. Sans les intégrer, un mot de passe ou un téléphone
  // qui échappe à la validation locale (ex : contournement du clavier natif)
  // affiche un message inexploitable à l'utilisateur alors que le backend a
  // déjà la raison précise sous la main.
  final details = data is Map && data['details'] is List
      ? (data['details'] as List).map((d) => d.toString()).where((d) => d.isNotEmpty)
      : const Iterable<String>.empty();
  final message = details.isEmpty ? baseMessage : '$baseMessage\n${details.join('\n')}';

  if (statusCode == 401) {
    return UnauthorizedException(message: message);
  }

  return ServerException(message: message, statusCode: statusCode);
}
