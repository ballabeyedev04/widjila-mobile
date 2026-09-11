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
/// toute erreur répond `{ success: false, message, code?, details?,
/// error: { code, message, details? }, requestId }`.
Exception mapDioException(DioException e) {
  if (e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.connectionError) {
    return const NetworkException();
  }

  final statusCode = e.response?.statusCode;
  final data = e.response?.data;
  final corps = data is Map ? data : null;

  // Identifiant de la requête : corps d'erreur, sinon en-tête de réponse,
  // sinon celui qu'on a envoyé (réponse d'un proxy qui ne le renvoie pas).
  final requestId = _texte(corps?['requestId']) ??
      e.response?.headers.value('x-request-id') ??
      _texte(e.requestOptions.headers['X-Request-Id']);
  final erreurUniforme = corps?['error'];
  final codeErreur = erreurUniforme is Map ? _texte(erreurUniforme['code']) : null;

  final baseMessage = _texte(corps?['message']) ?? _messageSansCorps(e, statusCode);

  // `ValidationError` (422, voir validate.middleware.js) renvoie un message
  // générique (« Données invalides ») ACCOMPAGNÉ d'un détail par champ Joi en
  // échec dans `details`. Sans les intégrer, un mot de passe ou un téléphone
  // qui échappe à la validation locale (ex : contournement du clavier natif)
  // affiche un message inexploitable à l'utilisateur alors que le backend a
  // déjà la raison précise sous la main.
  final details = corps != null && corps['details'] is List
      ? (corps['details'] as List).map((d) => d.toString()).where((d) => d.isNotEmpty)
      : const Iterable<String>.empty();
  final message = details.isEmpty ? baseMessage : '$baseMessage\n${details.join('\n')}';

  if (statusCode == 401) {
    return UnauthorizedException(message: message);
  }

  // Refus lié à l'ABONNEMENT — `SUBSCRIPTION_REQUIRED`,
  // `SUBSCRIPTION_FEATURE_UNAVAILABLE`, `SUBSCRIPTION_LIMIT_REACHED`, posés
  // par `requireFonctionnalite.middleware.js` et `checkSubscription`.
  //
  // Le serveur renvoie ce code depuis toujours ; le mobile ne le lisait pas et
  // affichait le message comme n'importe quelle erreur, sans rien proposer.
  // Or c'est le seul refus qu'un utilisateur peut lever lui-même : il mérite
  // une porte de sortie, pas un constat.
  //
  // Un PRÉFIXE plutôt qu'un type d'exception dédié : le message du serveur est
  // conservé intact, et les dizaines d'écrans qui affichent déjà `failure
  // .errorMessage` n'ont pas une ligne à changer.
  final code = corps?['code'];
  if (code is String && code.startsWith('SUBSCRIPTION_')) {
    // Le CODE voyage avec le message : il permet à l'affichage d'adapter son
    // titre (plafond atteint / option absente / aucun abonnement) sans avoir à
    // deviner en relisant le texte.
    return ServerException(
      message: '${ErrCodes.prefixeAbonnement}$code|$message',
      statusCode: statusCode,
      code: code,
      codeErreur: codeErreur,
      requestId: requestId,
    );
  }

  // Le code voyage aussi hors abonnement : `ENVOI_EN_COURS` (409) se lit
  // « réessayer plus tard », là où un autre 409 est un vrai conflit.
  return ServerException(
    message: message,
    statusCode: statusCode,
    code: code is String ? code : null,
    codeErreur: codeErreur,
    requestId: requestId,
  );
}

String? _texte(Object? valeur) => valeur is String && valeur.isNotEmpty ? valeur : null;

/// Message quand le serveur n'en a donné AUCUN.
///
/// CORRECTIF : on retombait sur `e.message`, le texte technique de Dio —
/// « This exception was thrown because the response has a status code of 502
/// and RequestOptions.validateStatus was configured to throw… ». C'est
/// exactement ce qui s'affichait, en anglais, dans l'écran d'erreur quand
/// nginx répondait 502/504 (API arrêtée ou en redémarrage) : la page HTML du
/// proxy n'a pas de `message`. Seuls les marqueurs `ErrCodes` posés par
/// l'intercepteur passent désormais ; tout le reste devient un marqueur
/// traduit par l'affichage.
String _messageSansCorps(DioException e, int? statusCode) {
  final marqueur = e.message;
  if (marqueur != null && marqueur.startsWith('__ERR_')) return marqueur;
  if (statusCode != null && statusCode >= 500) return ErrCodes.serviceUnavailable;
  return ErrCodes.generic;
}
