import 'package:dio/dio.dart';

import '../network/dio_exception_mapper.dart';
import '../services/collecteur_erreurs.dart';
import 'error_codes.dart';
import 'exceptions.dart';
import 'failure.dart';

/// Convertit une exception de la couche `data` en [Failure] pour la couche
/// `presentation`. Utilisé par TOUS les repositories (voir le pattern dans
/// `features/*/data/repositories/*_repository_impl.dart`) :
///
/// ```dart
/// try {
///   final result = await remoteDataSource.foo();
///   return Right(result);
/// } catch (e) {
///   return Left(exceptionToFailure(e));
/// }
/// ```
///
/// ## Ce qui ne restait visible QUE de l'utilisateur
///
/// Deux familles d'erreurs devenaient un simple texte à l'écran, sans
/// qu'aucun rapport ne parte :
///   - les erreurs SERVEUR (5xx) : l'utilisateur voyait « Réessayer », l'équipe
///     ne voyait rien — sauf à recevoir un appel ;
///   - les erreurs NON TYPÉES — réponse mal lue, `null` inattendu, cast
///     impossible : un bug du client, affiché en clair (« type 'Null' is not
///     a subtype of type 'String' ») et jamais signalé.
/// Les deux sont désormais signalées à Crashlytics comme erreurs non fatales,
/// avec l'identifiant de requête qui retrouve la ligne du journal serveur.
Failure exceptionToFailure(Object error, [StackTrace? pile]) {
  // Une DioException non convertie par la source de données : on la convertit
  // ici plutôt que de la traiter comme un bug.
  if (error is DioException) return exceptionToFailure(mapDioException(error), pile ?? error.stackTrace);

  if (error is UnauthorizedException) {
    return AuthFailure(errorMessage: error.message);
  }
  if (error is NetworkException) {
    return NetworkFailure(errorMessage: error.message);
  }
  if (error is ServerException) {
    final statut = error.statusCode;
    if (statut == null || statut >= 500) {
      signalerErreurNonFatale(
        error,
        pile ?? StackTrace.current,
        raison: 'Erreur serveur ${statut ?? '(sans statut)'}',
        contexte: {'statut': statut, 'code': error.codeErreur ?? error.code, 'requestId': error.requestId},
      );
    }
    return ServerFailure(errorMessage: error.message, statusCode: statut);
  }
  if (error is CacheException) {
    return CacheFailure(errorMessage: error.message);
  }

  signalerErreurNonFatale(
    error,
    pile ?? StackTrace.current,
    raison: 'Erreur inattendue (${error.runtimeType}) convertie en échec affiché',
  );
  // Le texte technique n'est plus montré : l'affichage traduit ce marqueur.
  return const ServerFailure(errorMessage: ErrCodes.generic);
}
