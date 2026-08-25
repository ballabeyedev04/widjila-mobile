/// Marqueurs d'erreur réseau — utilisés par `DioClientFactory` (couche
/// réseau, sans accès à `BuildContext`/`AppLocalizations`) à la place d'un
/// message d'erreur en dur.
///
/// [AppAlert] (`core/widgets/app_alert.dart`) — le seul point d'affichage
/// d'erreur de toute l'app — reconnaît ces marqueurs et les traduit avant
/// affichage ; tout autre message (venant du backend, déjà dans la langue de
/// l'utilisateur — voir `Accept-Language`… — ou déjà traduit ailleurs) passe
/// inchangé. C'est ce qui permet de corriger un trou d'internationalisation
/// dans la couche réseau SANS modifier les dizaines d'écrans qui appellent
/// déjà `AppAlert.error(context, message: ...)`.
class ErrCodes {
  ErrCodes._();

  static const forbidden = '__ERR_FORBIDDEN__';
  static const rateLimit = '__ERR_RATE_LIMIT__';
  static const serviceUnavailable = '__ERR_SERVICE_UNAVAILABLE__';
  static const generic = '__ERR_GENERIC__';
}
