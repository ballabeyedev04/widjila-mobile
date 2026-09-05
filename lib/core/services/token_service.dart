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

  // ── Copie en mémoire du jeton ───────────────────────────────────────────
  //
  // ## Pourquoi
  //
  // L'intercepteur Dio appelle [getValidToken] AVANT CHAQUE REQUÊTE. Chaque
  // appel descendait jusqu'au stockage sécurisé : un aller-retour de canal de
  // plateforme, plus un déchiffrement (EncryptedSharedPreferences sur Android,
  // Trousseau sur iOS). C'est de l'ordre de la dizaine de millisecondes, et
  // bien davantage au premier accès après le démarrage, quand le magasin de
  // clés Android doit encore s'initialiser. Un écran qui lance quatre requêtes
  // payait quatre fois ce prix AVANT même que la première parte sur le réseau.
  //
  // S'y ajoutait un décodage du JWT (base64 + JSON) à chaque appel, pour
  // relire une date d'expiration qui ne change jamais.
  //
  // ## Pourquoi c'est sûr
  //
  // Ce service est l'UNIQUE écrivain de ces deux clés dans toute
  // l'application, et il est un singleton : personne ne peut modifier le
  // stockage dans son dos. Toute écriture passe par [setToken] /
  // [setRefreshToken] / [clearToken], qui tiennent la copie à jour.
  //
  // Le stockage sécurisé reste la source de vérité et la seule chose qui
  // survit à la fermeture de l'application ; la mémoire n'est qu'un raccourci
  // de lecture pour la session en cours.
  String? _jetonEnMemoire;
  String? _rafraichissementEnMemoire;

  /// `true` dès qu'on a lu le stockage une fois — distingue « pas encore lu »
  /// de « lu, et il n'y avait rien ». Sans ce drapeau, une session sans jeton
  /// relirait le stockage à chaque requête, exactement ce qu'on veut éviter.
  bool _jetonCharge = false;
  bool _rafraichissementCharge = false;

  /// Expiration déjà extraite de [_jetonEnMemoire] — évite de redécoder le
  /// JWT à chaque requête. `null` quand le jeton n'annonce pas d'expiration.
  DateTime? _expiration;

  /// Émet `true`/`false` à chaque changement d'état d'authentification —
  /// consommé par le routeur pour rediriger automatiquement vers /login.
  Stream<bool> get authChanges => _authController.stream;

  /// Vérifie qu'un token existe ET qu'il n'est pas expiré.
  Future<bool> get isAuthenticated async {
    final token = await getToken();
    if (token == null || token.isEmpty) return false;
    return !_estExpire();
  }

  Future<String?> getToken() async {
    if (_jetonCharge) return _jetonEnMemoire;
    _memoriserJeton(await secureStorage.read(key: _kAccessTokenKey));
    return _jetonEnMemoire;
  }

  /// Met à jour la copie mémoire ET l'expiration décodée, d'un seul geste.
  void _memoriserJeton(String? jeton) {
    _jetonEnMemoire = (jeton == null || jeton.isEmpty) ? null : jeton;
    _jetonCharge = true;
    _expiration = _jetonEnMemoire == null ? null : _lireExpiration(_jetonEnMemoire!);
  }

  /// Date d'expiration annoncée par le JWT, ou `null` s'il n'en annonce pas.
  ///
  /// Lève implicitement le cas du jeton illisible en renvoyant une date déjà
  /// passée : [_estExpire] le traitera comme invalide, ce qui reproduit
  /// exactement l'ancien comportement.
  static DateTime? _lireExpiration(String token) {
    try {
      final exp = Jwt.parseJwt(token)['exp'];
      if (exp == null) return null; // pas d'expiry — on fait confiance au backend
      return DateTime.fromMillisecondsSinceEpoch((exp as int) * 1000);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0); // illisible = invalide
    }
  }

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
    if (_estExpire()) return null;
    return token;
  }

  Future<void> setToken(String? token) async {
    if (token == null || token.isEmpty) {
      await secureStorage.delete(key: _kAccessTokenKey);
    } else {
      await secureStorage.write(key: _kAccessTokenKey, value: token);
    }
    _memoriserJeton(token);
    _authController.add(await isAuthenticated);
  }

  Future<void> clearToken() async {
    await secureStorage.delete(key: _kAccessTokenKey);
    await secureStorage.delete(key: _kRefreshTokenKey);
    _memoriserJeton(null);
    _rafraichissementEnMemoire = null;
    _rafraichissementCharge = true;
    _authController.add(false);
  }

  Future<String?> getRefreshToken() async {
    if (_rafraichissementCharge) return _rafraichissementEnMemoire;
    _rafraichissementEnMemoire = await secureStorage.read(key: _kRefreshTokenKey);
    _rafraichissementCharge = true;
    return _rafraichissementEnMemoire;
  }

  Future<void> setRefreshToken(String? token) async {
    if (token == null || token.isEmpty) {
      await secureStorage.delete(key: _kRefreshTokenKey);
    } else {
      await secureStorage.write(key: _kRefreshTokenKey, value: token);
    }
    _rafraichissementEnMemoire = (token == null || token.isEmpty) ? null : token;
    _rafraichissementCharge = true;
  }

  /// Vérifie l'expiration du jeton COURANT, avec une marge de 30 secondes
  /// (latence réseau) avant l'expiration réelle qu'il annonce.
  ///
  /// Lit [_expiration], décodée une seule fois à la mémorisation du jeton :
  /// l'ancienne version redécodait le JWT à chaque requête pour relire une
  /// date qui, par définition, ne change pas.
  bool _estExpire() {
    final expiration = _expiration;
    if (expiration == null) return false; // pas d'expiry — on fait confiance au backend
    return DateTime.now().isAfter(expiration.subtract(const Duration(seconds: 30)));
  }

  void dispose() => _authController.close();
}
