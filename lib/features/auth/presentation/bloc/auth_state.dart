import 'package:equatable/equatable.dart';
import '../../domain/entities/user.dart';

enum AuthStatus {
  /// Vérification de session en cours (démarrage de l'app) — écran de
  /// chargement, aucune décision de navigation encore prise.
  inconnu,
  authentifie,
  nonAuthentifie,

  /// Login réussi mais un code TOTP est requis avant d'obtenir les tokens.
  mfaRequis,
}

class AuthState extends Equatable {
  final AuthStatus status;
  final User? utilisateur;

  /// `true` pendant un appel réseau (login, submit MFA...) — la page
  /// affiche un indicateur sur le bouton plutôt que de désactiver tout l'UI.
  final bool enCours;

  /// Message d'erreur de la DERNIÈRE action (login/MFA/register) — `null`
  /// sinon. Transitoire : la page l'affiche puis le bloc le vide au
  /// prochain event.
  final String? erreur;

  /// Message de succès transitoire — utilisé par l'inscription (qui ne
  /// change pas le statut de session, voir [AuthRegisterRequested]).
  final String? messageSucces;

  const AuthState({
    this.status = AuthStatus.inconnu,
    this.utilisateur,
    this.enCours = false,
    this.erreur,
    this.messageSucces,
  });

  const AuthState.inconnu() : this(status: AuthStatus.inconnu);

  AuthState copyWith({
    AuthStatus? status,
    User? utilisateur,
    bool? enCours,
    String? erreur,
    String? messageSucces,
    bool effacerErreur = false,
    bool effacerUtilisateur = false,
    bool effacerMessageSucces = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      utilisateur: effacerUtilisateur ? null : (utilisateur ?? this.utilisateur),
      enCours: enCours ?? false,
      erreur: effacerErreur ? null : (erreur ?? this.erreur),
      messageSucces: effacerMessageSucces ? null : (messageSucces ?? this.messageSucces),
    );
  }

  bool get estAuthentifie => status == AuthStatus.authentifie && utilisateur != null;

  @override
  List<Object?> get props => [status, utilisateur, enCours, erreur, messageSucces];
}
