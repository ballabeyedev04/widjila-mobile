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
Failure exceptionToFailure(Object error) {
  if (error is UnauthorizedException) {
    return AuthFailure(errorMessage: error.message);
  }
  if (error is NetworkException) {
    return NetworkFailure(errorMessage: error.message);
  }
  if (error is ServerException) {
    return ServerFailure(errorMessage: error.message, statusCode: error.statusCode);
  }
  if (error is CacheException) {
    return CacheFailure(errorMessage: error.message);
  }
  return ServerFailure(errorMessage: error.toString());
}
