import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../../../auth/domain/entities/user.dart';
import '../entities/connexion_log_entry.dart';
import '../entities/mfa_provisionnement.dart';
import '../entities/session_active.dart';

/// Actions du compte regroupées dans l'écran Paramètres — sécurité (MFA,
/// sessions, historique de connexion), langue et RGPD. Miroir de
/// `backend/src/modules/account/route/account.route.js`.
abstract class AccountRepository {
  /// État actuel du MFA (`GET /account/me`, champ `mfaActive`) — l'écran
  /// Paramètres en a besoin pour proposer « Activer » ou « Désactiver », et
  /// aucune route dédiée n'existe pour ce seul indicateur.
  Future<Either<Failure, bool>> getStatutMfa();

  /// Historique des connexions (`GET /account/connexions`) — plafonné côté
  /// back par `paginate()`, une seule page suffit pour cet écran.
  Future<Either<Failure, List<ConnexionLogEntry>>> getConnexions();

  /// Sessions actives (`GET /account/sessions`).
  Future<Either<Failure, List<SessionActive>>> getSessions();

  /// Révoque une session précise — déconnexion à distance d'un appareil.
  Future<Either<Failure, void>> revokerSession(String sessionId);

  /// Révoque toutes les sessions, y compris celle en cours : l'appelant doit
  /// enchaîner sur une déconnexion locale immédiate.
  Future<Either<Failure, void>> revokerToutesSessions();

  /// Génère un secret + QR code TOTP sans encore activer le MFA
  /// (`POST /account/mfa/provision`).
  Future<Either<Failure, MfaProvisionnement>> provisionnerMfa();

  /// Confirme le provisionnement avec un code à 6 chiffres et active le MFA.
  Future<Either<Failure, void>> activerMfa({required String secret, required String code});

  /// Désactive le MFA — requiert un code valide, pas seulement le mot de
  /// passe : évite qu'une session volée désarme la protection à elle seule.
  Future<Either<Failure, void>> desactiverMfa({required String code});

  /// Change la langue enregistrée sur le compte (`PUT /account/profil`) —
  /// distinct de `LocaleController.changer`, qui ne fait que l'effet LOCAL
  /// immédiat ; les deux sont appelés ensemble par l'écran Paramètres.
  Future<Either<Failure, void>> changerLangue(String code);

  /// Modifie les informations personnelles (`PUT /account/profil`) et
  /// renvoie l'utilisateur à jour — l'appelant doit le repousser dans
  /// l'`AuthBloc` (`AuthUserUpdated`), seul détenteur de l'utilisateur courant.
  ///
  /// `null` = champ inchangé, `''` = champ effacé (téléphone et fonction
  /// seulement ; le serveur refuse un nom ou un prénom vide).
  Future<Either<Failure, User>> modifierProfil({
    String? nom,
    String? prenom,
    String? telephone,
    String? fonction,
    String? cheminPhoto,
  });

  /// Change le mot de passe (`PUT /account/change-password`) et renvoie le
  /// nombre d'AUTRES sessions fermées au passage.
  ///
  /// Exige l'ancien mot de passe : une session volée ne suffit donc pas à
  /// verrouiller le compte de son propriétaire. Côté serveur, l'opération
  /// solde également un mot de passe provisoire (`mdp_temporaire`) et révoque
  /// les refresh tokens des autres appareils — sans quoi un jeton dérobé
  /// survivait au changement de mot de passe censé le neutraliser.
  Future<Either<Failure, int>> changerMotDePasse({
    required String ancienMotDePasse,
    required String nouveauMotDePasse,
  });

  /// Export de portabilité (RGPD art. 20) — renvoie les compteurs par
  /// catégorie, pas le fichier complet : voir la note dans `settings_page.dart`
  /// sur l'absence d'écriture de fichier côté mobile.
  Future<Either<Failure, Map<String, dynamic>>> exporterDonnees();

  /// Suppression de compte (RGPD art. 17, art. 20) — pseudonymisation puis
  /// suppression logique côté back ; l'appelant doit enchaîner sur une
  /// déconnexion locale.
  Future<Either<Failure, void>> supprimerCompte();
}
