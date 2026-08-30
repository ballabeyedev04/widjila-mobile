/// Configuration d'environnement — URL de l'API backend.
///
/// Injectée à la compilation via `--dart-define` (jamais bundlée en dur dans
/// l'APK/IPA, ni committée) :
///
///   flutter run  --dart-define=API_BASE_URL=http://10.0.2.2:3109/api/v1
///   flutter build apk --release \
///       --dart-define=API_BASE_URL=https://api.widjila.com/api/v1
///
/// `10.0.2.2` est l'alias que l'émulateur Android utilise pour joindre le
/// `localhost` de la machine hôte (`127.0.0.1` ne fonctionnerait pas depuis
/// l'intérieur de l'émulateur). Sur un vrai téléphone en dev, utiliser l'IP
/// locale de la machine de dev sur le même réseau Wi-Fi.
class Env {
  Env._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.widjila.com/api/v1',
  );

  /// Chemins d'authentification — utilisés par l'intercepteur Dio pour
  /// distinguer les endpoints publics (ne nécessitent pas de Bearer token,
  /// ne doivent jamais déclencher de tentative de refresh en boucle).
  static const String authLogin = '/auth/login';
  static const String authRegister = '/auth/register';
  static const String authRefresh = '/auth/refresh';
  static const String authLogout = '/auth/logout';
  static const String authMfaVerify = '/auth/mfa-verify';

  /// Pages légales — hébergées par l'admin web (pas de vue native dédiée
  /// côté mobile), ouvertes dans le navigateur externe depuis l'inscription.
  /// Mêmes routes que `admin/src/routes/AppRoutes.jsx`
  /// (`/condition-utilisation`, `/politique-confidentialite`), sur le
  /// domaine app.* — l'API vit sur un domaine séparé (api.*), voir
  /// `backend/deploy/nginx-admin.conf`.
  static const String cguUrl = String.fromEnvironment(
    'CGU_URL',
    defaultValue: 'https://app.widjila.com/condition-utilisation',
  );
  static const String politiqueConfidentialiteUrl = String.fromEnvironment(
    'POLITIQUE_CONFIDENTIALITE_URL',
    defaultValue: 'https://app.widjila.com/politique-confidentialite',
  );

  /// Page d'abonnement de l'admin web, ouverte depuis l'écran Abonnement du
  /// mobile pour le paiement par carte (choix confirmé par le client : pas
  /// d'intégration Stripe native).
  ///
  /// Constante DÉDIÉE, et non déduite d'[apiBaseUrl] : les deux vivent sur des
  /// domaines séparés (`api.*` pour l'API, `app.*` pour l'interface, voir
  /// `backend/deploy/nginx-admin.conf`). Retirer `/api/v1` de l'URL de l'API
  /// donnerait le domaine de l'API, où cette page n'existe pas.
  ///
  /// Même route que `admin/src/routes/AppRoutes.jsx` (`/abonnement`).
  static const String abonnementUrl = String.fromEnvironment(
    'ABONNEMENT_URL',
    defaultValue: 'https://app.widjila.com/abonnement',
  );
}
