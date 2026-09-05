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

  /// PREFIXE — et non un marqueur entier comme ceux du dessus.
  ///
  /// Quand le serveur refuse une action pour une raison d'ABONNEMENT, son
  /// message est déjà le bon : il nomme la formule en cours et le plafond
  /// atteint (« Votre abonnement Essentiel est limité à 2 utilisateurs »).
  /// Le remplacer par un texte générique perdrait précisément ce qui aide.
  ///
  /// On le préfixe donc au lieu de l'écraser. [AppAlert] reconnaît le
  /// préfixe, le retire, et présente une invitation à s'abonner plutôt qu'une
  /// alerte d'erreur — un refus de quota n'est pas une panne, c'est une
  /// limite qu'on peut lever.
  static const prefixeAbonnement = '__ERR_ABONNEMENT__|';
}
