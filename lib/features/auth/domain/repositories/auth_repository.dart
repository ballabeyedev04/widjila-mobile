import 'package:dartz/dartz.dart';
import '../../../../core/errors/failure.dart';
import '../entities/login_result.dart';
import '../entities/user.dart';

abstract class AuthRepository {
  /// Connexion. Si `mfaRequise` dans le résultat, appeler [verifierMfa]
  /// ensuite avec le code TOTP — aucun token n'est encore stocké à ce stade.
  Future<Either<Failure, LoginResult>> login({
    required String identifiant,
    required String motDePasse,
  });

  /// Valide le code TOTP après un login à deux facteurs. Stocke les tokens
  /// et l'utilisateur si succès (mêmes effets de bord qu'un [login] direct).
  Future<Either<Failure, User>> verifierMfa({required String code});

  Future<Either<Failure, User>> register({
    required String nom,
    required String prenom,
    required String email,
    required String motDePasse,
    String? telephone,
    String? fonction,
    String? organisationNom,
    String? raisonSociale,
    /// Identifiants d'entreprise, indexés par la clé attendue par le serveur
    /// (`siret`, `ninea`, `nif`, `ncc`, `idu`, `rccm`, `num_tva`).
    ///
    /// Une carte plutôt que des paramètres nommés : les champs varient selon
    /// le pays, et les figer ici obligerait à modifier chaque couche à chaque
    /// pays ajouté.
    Map<String, String> identifiants = const {},
    String? organisationTelephone,
    String? organisationEmail,
    String? organisationAdresse,
    String? organisationVille,
    String? organisationPays,
  });

  /// Message de confirmation renvoyé par le backend — jamais reformulé côté
  /// mobile (voir `AuthRemoteDataSource.forgotPassword`).
  Future<Either<Failure, String>> forgotPassword({required String email});

  Future<Either<Failure, String>> resetPassword({
    required String email,
    required String otp,
    required String nouveauMotDePasse,
  });

  /// Déconnexion — révoque le refresh token côté backend (best-effort) et
  /// vide le stockage local dans tous les cas.
  Future<void> logout();

  /// Reconnexion silencieuse au démarrage : si un refresh token valide
  /// existe, l'échange contre un nouvel access token puis récupère le
  /// profil (`GET /account/me`). Renvoie `null` si aucune session n'est
  /// récupérable (l'app retombe normalement sur /login) — jamais une
  /// [Failure], une session absente n'est pas une erreur.
  Future<User?> restaurerSession();
}
