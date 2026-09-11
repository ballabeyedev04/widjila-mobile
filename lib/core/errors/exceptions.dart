/// Exceptions internes à la couche `data` — jamais propagées telles quelles
/// à la présentation (les repositories les attrapent et les convertissent
/// en [Failure], voir failure.dart).
class ServerException implements Exception {
  final String message;
  final int? statusCode;

  /// Code STABLE renvoyé par le serveur (`{ code }` du corps d'erreur), ex.
  /// `ENVOI_EN_COURS`, `SUBSCRIPTION_REQUIRED`. `null` quand le serveur n'en
  /// donne pas. La synchronisation s'en sert pour distinguer un refus
  /// définitif d'un « réessayez plus tard » portant le même statut HTTP.
  final String? code;

  /// Code UNIFORME du serveur (`error.code` : BASE_INDISPONIBLE,
  /// RESSOURCE_INTROUVABLE…) — toujours renseigné quand le serveur répond au
  /// nouveau format. Distinct de [code], qui reste réservé aux codes métier
  /// explicites sur lesquels la synchronisation classe ses reprises.
  final String? codeErreur;

  /// Identifiant de la requête (`requestId` du corps, ou en-tête
  /// `X-Request-Id`) : c'est lui qui retrouve la ligne du journal serveur.
  final String? requestId;

  const ServerException({
    required this.message,
    this.statusCode,
    this.code,
    this.codeErreur,
    this.requestId,
  });

  @override
  String toString() => 'ServerException($statusCode${code != null ? ', $code' : ''}'
      '${requestId != null ? ', requestId=$requestId' : ''}): $message';
}

class CacheException implements Exception {
  final String message;
  const CacheException({required this.message});
}

class NetworkException implements Exception {
  final String message;
  const NetworkException({this.message = 'Erreur réseau, vérifiez votre connexion.'});
}

/// 401 après échec du refresh silencieux — distinct de [ServerException] pour
/// que le repository sache convertir en [AuthFailure] (déclenche la
/// déconnexion) plutôt qu'un message d'erreur générique affiché à l'écran.
class UnauthorizedException implements Exception {
  final String message;
  const UnauthorizedException({this.message = 'Session expirée, veuillez vous reconnecter.'});
}
