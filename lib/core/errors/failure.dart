import 'package:equatable/equatable.dart';

/// Erreur métier renvoyée par la couche `domain`/`data` vers la présentation
/// (jamais une exception brute — voir [exceptions.dart] pour la couche
/// réseau, convertie en [Failure] dans les repositories).
abstract class Failure extends Equatable {
  final String errorMessage;
  const Failure({required this.errorMessage});

  @override
  List<Object?> get props => [runtimeType, errorMessage];

  @override
  String toString() => '$runtimeType(errorMessage: $errorMessage)';
}

/// Erreur renvoyée par le backend (4xx/5xx avec un message exploitable).
class ServerFailure extends Failure {
  final int? statusCode;
  const ServerFailure({required super.errorMessage, this.statusCode});

  @override
  List<Object?> get props => [runtimeType, errorMessage, statusCode];
}

/// Session expirée / refresh impossible — la présentation doit rediriger
/// vers l'écran de connexion plutôt qu'afficher un message d'erreur générique.
class AuthFailure extends Failure {
  const AuthFailure({super.errorMessage = 'Session expirée, veuillez vous reconnecter.'});
}

/// Pas de connexion réseau / timeout — distinct d'une vraie erreur serveur
/// pour permettre un affichage ("Hors ligne", bouton Réessayer) différent.
class NetworkFailure extends Failure {
  const NetworkFailure({super.errorMessage = 'Erreur réseau, vérifiez votre connexion.'});
}

/// Erreur de lecture/écriture locale (cache, stockage sécurisé).
class CacheFailure extends Failure {
  const CacheFailure({required super.errorMessage});
}

/// Erreur de validation locale (formulaire) — avant tout appel réseau.
class ValidationFailure extends Failure {
  const ValidationFailure({required super.errorMessage});
}
