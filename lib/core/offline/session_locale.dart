import 'base_locale.dart';
import 'stockage_medias.dart';

/// Propriété des données locales — garantit qu'un compte ne lit jamais, et ne
/// synchronise jamais, les données hors ligne d'un autre compte sur le même
/// appareil (téléphone de chantier partagé).
///
/// ## Le problème que ce service résout
///
/// Le cache local (`BaseLocale`) et les photos hors ligne (`StockageMedias`)
/// ne portent aucune marque d'appartenance ligne par ligne. Une première
/// version faisait donc le ménage à la DÉCONNEXION, ce qui laissait deux
/// trous béants :
///
///  1. **Déconnexion interrompue** — l'utilisateur tape « Déconnexion » puis
///     balaie l'application ; Android tue le process au milieu des `DELETE`.
///     Les chantiers, réserves ET la file d'attente du compte précédent
///     survivent. Le compte suivant les lit hors ligne, et pire : la
///     synchronisation automatique rejoue les actions en attente SOUS SON
///     IDENTITÉ, attribuant à un utilisateur des constats qu'il n'a pas
///     faits.
///  2. **Session expirée** — un jeton qui expire pendant une journée de
///     travail hors réseau déclenchait la même purge, effaçant sans un mot
///     des heures de relevés que leur auteur venait pourtant récupérer en se
///     reconnectant.
///
/// ## La solution
///
/// Le contrôle est déplacé de la déconnexion vers la CONNEXION, via un
/// identifiant de propriétaire persisté dans `sync_meta` :
///
///  - [adopterUtilisateur] est appelé à chaque authentification réussie
///    (connexion, MFA, restauration de session). Si les données locales
///    appartiennent à quelqu'un d'autre, elles sont purgées AVANT que quoi
///    que ce soit ne soit servi ;
///  - une purge ratée à la déconnexion est donc systématiquement rattrapée au
///    prochain démarrage, quel qu'ait été l'état d'arrêt de l'application ;
///  - une session expirée ne purge plus rien : le même utilisateur retrouve
///    sa file d'attente intacte en se reconnectant, et c'est l'arrivée d'un
///    utilisateur DIFFÉRENT qui déclenche le ménage.
class SessionLocale {
  final BaseLocale _base;
  final StockageMedias _medias;

  SessionLocale({required BaseLocale base, required StockageMedias medias})
      // ignore: prefer_initializing_formals — les champs sont privés, les
      // paramètres nommés publics : `this._base` exposerait `_base` comme nom
      // de paramètre à l'appelant, ce que le conteneur d'injection ne peut pas
      // écrire lisiblement.
      : _base = base,
        _medias = medias;

  /// Déclare [utilisateurId] propriétaire des données locales, en purgeant
  /// d'abord tout ce qui appartenait à un autre compte.
  ///
  /// À appeler à CHAQUE authentification réussie, avant que le moindre écran
  /// ne lise le cache. Ne purge rien si le compte est le même qu'avant (cas
  /// nominal : reconnexion, redémarrage de l'app) — c'est précisément ce qui
  /// préserve le travail hors ligne non encore synchronisé.
  Future<void> adopterUtilisateur(String utilisateurId) async {
    final precedent = await _base.proprietaire();
    if (precedent != null && precedent != utilisateurId) {
      await purger();
    }
    // Écrit APRÈS la purge : `viderTout()` vide aussi `sync_meta`, donc
    // l'ordre inverse effacerait le propriétaire qu'on vient de poser.
    await _base.definirProprietaire(utilisateurId);
  }

  /// Efface toutes les données locales — tables ET photos hors ligne.
  ///
  /// Appelée à la déconnexion VOLONTAIRE (l'utilisateur ne s'attend pas à
  /// retrouver ses données) et par [adopterUtilisateur] au changement de
  /// compte. Jamais sur une simple expiration de session.
  Future<void> purger() async {
    await _base.viderTout();
    await _medias.viderTout();
  }
}
