import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decode/jwt_decode.dart';

/// Service de gestion du JWT (access token) et du refresh token.
///
/// Vérifie l'expiration côté client (évite d'envoyer une requête vouée à
/// échouer en 401) et ne stocke jamais le mot de passe. Les deux tokens
/// vivent dans le stockage sécurisé (Keychain iOS / EncryptedSharedPreferences
/// Android), jamais en SharedPreferences en clair.
class TokenService {
  final FlutterSecureStorage secureStorage;
  final StreamController<bool> _authController = StreamController<bool>.broadcast();

  TokenService({required this.secureStorage});

  static const _kAccessTokenKey = 'sc_jwt_token';
  static const _kRefreshTokenKey = 'sc_refresh_token';

  /// Émet `true`/`false` à chaque changement d'état d'authentification —
  /// consommé par le routeur pour rediriger automatiquement vers /login.
  Stream<bool> get authChanges => _authController.stream;

  /// Vérifie qu'un token existe ET qu'il n'est pas expiré.
  Future<bool> get isAuthenticated async {
    final token = await getToken();
    if (token == null || token.isEmpty) return false;
    return !_isTokenExpired(token);
  }

  Future<String?> getToken() => secureStorage.read(key: _kAccessTokenKey);

  /// Identifiant de l'utilisateur connecté, extrait du JWT (`{ id, role }`).
  /// Source fiable, disponible tant qu'un token valide existe — contrairement
  /// à un `User` parfois absent des arguments de navigation.
  Future<String?> getUserId() async {
    final token = await getValidToken();
    if (token == null) return null;
    try {
      final payload = Jwt.parseJwt(token);
      return payload['id']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Retourne le token s'il est exploitable.
  ///
  /// ## Pourquoi on n'EFFACE plus le jeton jugé expiré
  ///
  /// L'expiration est évaluée avec [DateTime.now], donc avec l'HORLOGE DE
  /// L'APPAREIL. Un téléphone dont la mise à jour automatique de l'heure est
  /// désactivée — cas courant — peut avancer de plusieurs heures : tout jeton
  /// paraissait alors expiré, était effacé, et l'utilisateur se retrouvait
  /// déconnecté en boucle sans message compréhensible, alors que le SERVEUR
  /// aurait parfaitement accepté ce jeton.
  ///
  /// Désormais l'horloge locale ne sert plus qu'à ÉVITER un aller-retour
  /// réseau manifestement inutile : on renvoie `null` (l'intercepteur tentera
  /// un refresh) mais on ne détruit rien. Seul un vrai 401 du serveur, après
  /// échec du refresh, provoque l'effacement — voir `dio_client_factory.dart`.
  Future<String?> getValidToken() async {
    final token = await getToken();
    if (token == null || token.isEmpty) return null;
    if (_isTokenExpired(token)) return null;
    return token;
  }

  Future<void> setToken(String? token) async {
    if (token == null || token.isEmpty) {
      await secureStorage.delete(key: _kAccessTokenKey);
    } else {
      await secureStorage.write(key: _kAccessTokenKey, value: token);
    }
    _authController.add(await isAuthenticated);
  }

  Future<void> clearToken() async {
    await secureStorage.delete(key: _kAccessTokenKey);
    await secureStorage.delete(key: _kRefreshTokenKey);
    _authController.add(false);
  }

  Future<String?> getRefreshToken() => secureStorage.read(key: _kRefreshTokenKey);

  Future<void> setRefreshToken(String? token) async {
    if (token == null || token.isEmpty) {
      await secureStorage.delete(key: _kRefreshTokenKey);
    } else {
      await secureStorage.write(key: _kRefreshTokenKey, value: token);
    }
  }

  /// Vérifie l'expiration du JWT côté client, avec une marge de 30 secondes
  /// (latence réseau) avant l'expiration réelle annoncée par le token.
  bool _isTokenExpired(String token) {
    try {
      final payload = Jwt.parseJwt(token);
      final exp = payload['exp'];
      if (exp == null) return false; // Pas d'expiry — on fait confiance au backend
      final expiryDate = DateTime.fromMillisecondsSinceEpoch((exp as int) * 1000);
      return DateTime.now().isAfter(expiryDate.subtract(const Duration(seconds: 30)));
    } catch (_) {
      return true; // Token illisible = invalide
    }
  }

  void dispose() => _authController.close();
}
