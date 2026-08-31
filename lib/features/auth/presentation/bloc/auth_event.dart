import 'package:equatable/equatable.dart';
import '../../domain/entities/user.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();
  @override
  List<Object?> get props => [];
}

/// Émis une seule fois au démarrage de l'app — tente de restaurer la
/// session (refresh token → /account/me).
class AuthCheckRequested extends AuthEvent {
  const AuthCheckRequested();
}

class AuthLoginRequested extends AuthEvent {
  final String identifiant;
  final String motDePasse;
  const AuthLoginRequested({required this.identifiant, required this.motDePasse});
  @override
  List<Object?> get props => [identifiant, motDePasse];
}

class AuthMfaSubmitted extends AuthEvent {
  final String code;
  const AuthMfaSubmitted({required this.code});
  @override
  List<Object?> get props => [code];
}

/// Retour à l'écran de connexion depuis l'étape MFA (annulation).
class AuthMfaCancelled extends AuthEvent {
  const AuthMfaCancelled();
}

class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

/// Inscription — NE connecte PAS automatiquement (le backend exige une
/// vérification d'email avant login, voir REQUIRE_EMAIL_VERIFICATION côté
/// backend). Le statut de session reste inchangé ; seul [AuthState.erreur]
/// ou un succès (redirection manuelle vers /login) résulte de cet event.
class AuthRegisterRequested extends AuthEvent {
  final String nom;
  final String prenom;
  final String email;
  final String motDePasse;
  final String? telephone;
  final String? fonction;
  final String? organisationNom;
  final String? raisonSociale;
  /// Identifiants d'entreprise, indexés par la clé attendue par le serveur.
  /// Les champs varient selon le pays — voir `config/pays.js` côté backend.
  final Map<String, String> identifiants;
  final String? organisationTelephone;
  final String? organisationEmail;
  final String? organisationAdresse;
  final String? organisationVille;
  final String? organisationPays;

  const AuthRegisterRequested({
    required this.nom,
    required this.prenom,
    required this.email,
    required this.motDePasse,
    this.telephone,
    this.fonction,
    this.organisationNom,
    this.raisonSociale,
    this.identifiants = const {},
    this.organisationTelephone,
    this.organisationEmail,
    this.organisationAdresse,
    this.organisationVille,
    this.organisationPays,
  });

  @override
  List<Object?> get props => [
        nom, prenom, email, motDePasse, telephone, fonction, organisationNom,
        raisonSociale, identifiants, organisationTelephone,
        organisationEmail, organisationAdresse, organisationVille, organisationPays,
      ];
}

/// Émis par l'intercepteur Dio (via [AuthEventBus]) quand un refresh a
/// échoué en tâche de fond — déconnexion immédiate, sans passer par
/// [AuthLogoutRequested] (qui tenterait un appel réseau supplémentaire).
class AuthSessionExpired extends AuthEvent {
  const AuthSessionExpired();
}

class AuthForgotPasswordRequested extends AuthEvent {
  final String email;
  const AuthForgotPasswordRequested({required this.email});
  @override
  List<Object?> get props => [email];
}

class AuthResetPasswordRequested extends AuthEvent {
  final String email;
  final String otp;
  final String nouveauMotDePasse;
  const AuthResetPasswordRequested({required this.email, required this.otp, required this.nouveauMotDePasse});
  @override
  List<Object?> get props => [email, otp, nouveauMotDePasse];
}

/// Le profil a été modifié ailleurs dans l'app (ex: écran Profil) — met à
/// jour l'utilisateur courant sans revalider toute la session.
class AuthUserUpdated extends AuthEvent {
  final User utilisateur;
  const AuthUserUpdated(this.utilisateur);
  @override
  List<Object?> get props => [utilisateur];
}
