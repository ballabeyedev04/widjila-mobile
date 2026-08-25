import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/auth_event_bus.dart';
import '../../../../core/services/locale_controller.dart';
import '../../domain/entities/user.dart';
import '../../domain/usecases/forgot_password.dart';
import '../../domain/usecases/login_user.dart';
import '../../domain/usecases/logout_user.dart';
import '../../domain/usecases/register_user.dart';
import '../../domain/usecases/reset_password.dart';
import '../../domain/usecases/restaurer_session.dart';
import '../../domain/usecases/verifier_mfa.dart';
import 'auth_event.dart';
import 'auth_state.dart';

/// BLoC de session — état global d'authentification de l'app entière (pas
/// seulement l'écran de login). Le routeur (`go_router`) écoute ce bloc via
/// `GoRouterRefreshStream` pour rediriger automatiquement selon
/// [AuthState.status] et le rôle de [AuthState.utilisateur].
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final LoginUser loginUser;
  final VerifierMfa verifierMfa;
  final LogoutUser logoutUser;
  final RestaurerSession restaurerSession;
  final RegisterUser registerUser;
  final ForgotPassword forgotPassword;
  final ResetPassword resetPassword;
  final LocaleController localeController;

  StreamSubscription<void>? _forcedLogoutSub;

  AuthBloc({
    required this.loginUser,
    required this.verifierMfa,
    required this.logoutUser,
    required this.restaurerSession,
    required this.registerUser,
    required this.forgotPassword,
    required this.resetPassword,
    required this.localeController,
  }) : super(const AuthState.inconnu()) {
    on<AuthCheckRequested>(_onCheckRequested);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthMfaSubmitted>(_onMfaSubmitted);
    on<AuthMfaCancelled>(_onMfaCancelled);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<AuthSessionExpired>(_onSessionExpired);
    on<AuthUserUpdated>(_onUserUpdated);
    on<AuthRegisterRequested>(_onRegisterRequested);
    on<AuthForgotPasswordRequested>(_onForgotPasswordRequested);
    on<AuthResetPasswordRequested>(_onResetPasswordRequested);

    // Déconnexion forcée déclenchée depuis l'intercepteur Dio (401 après
    // échec du refresh) — hors du cycle normal request/handler du bloc.
    _forcedLogoutSub = AuthEventBus.instance.onForcedLogout.listen((_) {
      add(const AuthSessionExpired());
    });
  }

  /// Durée plancher de l'écran de démarrage — doit couvrir l'animation
  /// d'entrée du logo (`SplashPage`, ~1100 ms). Sans ce plancher, un
  /// utilisateur déconnecté (cas le plus fréquent : pas de session à
  /// restaurer, juste une lecture locale de stockage sécurisé, quasi
  /// instantanée) voit le routeur rediriger vers /login avant même que
  /// l'animation ait eu le temps de se jouer — l'écran de démarrage semble
  /// alors ne jamais s'afficher.
  static const _dureeMinSplash = Duration(milliseconds: 1200);

  Future<void> _onCheckRequested(AuthCheckRequested event, Emitter<AuthState> emit) async {
    // `Future.wait` attend le plus long des deux : une restauration RAPIDE
    // (pas de token) est retenue jusqu'au plancher, une restauration LENTE
    // (appel réseau vers /account/me) n'est jamais ralentie davantage.
    final resultats = await Future.wait([
      restaurerSession(),
      Future.delayed(_dureeMinSplash),
    ]);
    final utilisateur = resultats[0] as User?;

    if (utilisateur == null) {
      emit(state.copyWith(status: AuthStatus.nonAuthentifie, effacerUtilisateur: true));
    } else {
      emit(state.copyWith(status: AuthStatus.authentifie, utilisateur: utilisateur));
      // Reconnexion sur un appareil qui n'a jamais vu ce compte (ou dont la
      // langue locale a divergé) : on s'aligne sur la préférence du compte.
      unawaited(localeController.synchroniserDepuisCompte(utilisateur.langue));
    }
  }

  Future<void> _onLoginRequested(AuthLoginRequested event, Emitter<AuthState> emit) async {
    // Un second envoi pendant qu'un premier est déjà en cours (double-tap,
    // appui rapide avant que le bouton se désactive visuellement) est
    // ignoré plutôt que traité en parallèle — l'entrelacement de deux
    // requêtes concurrentes pouvait produire un état incohérent (erreur ET
    // succès émis coup sur coup pour deux tentatives différentes).
    if (state.enCours) return;
    emit(state.copyWith(enCours: true, effacerErreur: true));
    final result = await loginUser(identifiant: event.identifiant, motDePasse: event.motDePasse);
    result.fold(
      (failure) => emit(state.copyWith(enCours: false, erreur: failure.errorMessage)),
      (loginResult) {
        if (loginResult.mfaRequise) {
          emit(state.copyWith(status: AuthStatus.mfaRequis, enCours: false, utilisateur: loginResult.utilisateur));
        } else {
          emit(state.copyWith(status: AuthStatus.authentifie, enCours: false, utilisateur: loginResult.utilisateur));
          unawaited(localeController.synchroniserDepuisCompte(loginResult.utilisateur.langue));
        }
      },
    );
  }

  Future<void> _onMfaSubmitted(AuthMfaSubmitted event, Emitter<AuthState> emit) async {
    if (state.enCours) return; // voir le commentaire dans _onLoginRequested
    emit(state.copyWith(enCours: true, effacerErreur: true));
    final result = await verifierMfa(code: event.code);
    result.fold(
      (failure) => emit(state.copyWith(enCours: false, erreur: failure.errorMessage)),
      (utilisateur) {
        emit(state.copyWith(status: AuthStatus.authentifie, enCours: false, utilisateur: utilisateur));
        unawaited(localeController.synchroniserDepuisCompte(utilisateur.langue));
      },
    );
  }

  void _onMfaCancelled(AuthMfaCancelled event, Emitter<AuthState> emit) {
    emit(state.copyWith(status: AuthStatus.nonAuthentifie, effacerUtilisateur: true, effacerErreur: true));
  }

  Future<void> _onLogoutRequested(AuthLogoutRequested event, Emitter<AuthState> emit) async {
    await logoutUser();
    emit(state.copyWith(status: AuthStatus.nonAuthentifie, effacerUtilisateur: true, effacerErreur: true));
  }

  void _onSessionExpired(AuthSessionExpired event, Emitter<AuthState> emit) {
    emit(state.copyWith(
      status: AuthStatus.nonAuthentifie,
      effacerUtilisateur: true,
      erreur: 'Votre session a expiré, veuillez vous reconnecter.',
    ));
  }

  void _onUserUpdated(AuthUserUpdated event, Emitter<AuthState> emit) {
    emit(state.copyWith(utilisateur: event.utilisateur));
    unawaited(localeController.synchroniserDepuisCompte(event.utilisateur.langue));
  }

  Future<void> _onRegisterRequested(AuthRegisterRequested event, Emitter<AuthState> emit) async {
    if (state.enCours) return; // voir le commentaire dans _onLoginRequested
    emit(state.copyWith(enCours: true, effacerErreur: true, effacerMessageSucces: true));
    final result = await registerUser(
      nom: event.nom,
      prenom: event.prenom,
      email: event.email,
      motDePasse: event.motDePasse,
      telephone: event.telephone,
      fonction: event.fonction,
      organisationNom: event.organisationNom,
      raisonSociale: event.raisonSociale,
      siret: event.siret,
      rccm: event.rccm,
      ninea: event.ninea,
      organisationTelephone: event.organisationTelephone,
      organisationEmail: event.organisationEmail,
      organisationAdresse: event.organisationAdresse,
      organisationVille: event.organisationVille,
      organisationPays: event.organisationPays,
    );
    result.fold(
      (failure) => emit(state.copyWith(enCours: false, erreur: failure.errorMessage)),
      // L'inscription ne donne plus un compte utilisable : elle dépose une
      // demande qu'un administrateur valide ou rejette (voir
      // `backend/src/modules/auth/service/auth.service.js#register`). Annoncer
      // « Compte créé » ferait attendre à l'utilisateur une connexion qui
      // échouera tant que la demande n'est pas traitée.
      (_) => emit(state.copyWith(
        enCours: false,
        messageSucces: "Demande d'inscription enregistrée. Vérifiez votre email pour "
            "confirmer votre adresse : votre compte sera actif dès qu'un "
            "administrateur aura validé votre demande.",
      )),
    );
  }

  Future<void> _onForgotPasswordRequested(AuthForgotPasswordRequested event, Emitter<AuthState> emit) async {
    if (state.enCours) return; // voir le commentaire dans _onLoginRequested
    emit(state.copyWith(enCours: true, effacerErreur: true, effacerMessageSucces: true));
    final result = await forgotPassword(email: event.email);
    result.fold(
      (failure) => emit(state.copyWith(enCours: false, erreur: failure.errorMessage)),
      // Message du backend, jamais reformulé ici (voir AuthRepository.forgotPassword).
      (message) => emit(state.copyWith(enCours: false, messageSucces: message)),
    );
  }

  Future<void> _onResetPasswordRequested(AuthResetPasswordRequested event, Emitter<AuthState> emit) async {
    if (state.enCours) return; // voir le commentaire dans _onLoginRequested
    emit(state.copyWith(enCours: true, effacerErreur: true, effacerMessageSucces: true));
    final result = await resetPassword(
      email: event.email,
      otp: event.otp,
      nouveauMotDePasse: event.nouveauMotDePasse,
    );
    result.fold(
      (failure) => emit(state.copyWith(enCours: false, erreur: failure.errorMessage)),
      (message) => emit(state.copyWith(enCours: false, messageSucces: message)),
    );
  }

  @override
  Future<void> close() {
    _forcedLogoutSub?.cancel();
    return super.close();
  }
}
