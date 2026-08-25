/// Exceptions internes à la couche `data` — jamais propagées telles quelles
/// à la présentation (les repositories les attrapent et les convertissent
/// en [Failure], voir failure.dart).
class ServerException implements Exception {
  final String message;
  final int? statusCode;
  const ServerException({required this.message, this.statusCode});
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
