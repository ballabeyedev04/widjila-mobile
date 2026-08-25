import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/repositories/account_repository.dart';
import 'settings_state.dart';

/// Cubit unique pour l'écran Paramètres. Appelle directement
/// [AccountRepository] plutôt que de passer par un UseCase par action : les
/// neuf opérations exposées (MFA, sessions, langue, RGPD) sont de simples
/// relais vers le repository, sans logique additionnelle qui justifierait
/// une classe dédiée par action — voir les autres cubits (`MembresCubit`,
/// `PartenairesCubit`) pour le pattern usuel quand une action a réellement
/// une logique propre.
class SettingsCubit extends Cubit<SettingsState> {
  final AccountRepository repository;
  SettingsCubit({required this.repository}) : super(const SettingsState());

  Future<void> charger() async {
    emit(state.copyWith(status: SettingsStatus.chargement));
    final mfaResult = await repository.getStatutMfa();
    final sessionsResult = await repository.getSessions();
    final connexionsResult = await repository.getConnexions();

    String? erreur;
    var mfaActive = false;
    var sessions = state.sessions;
    var connexions = state.connexions;

    mfaResult.fold((f) => erreur = f.errorMessage, (v) => mfaActive = v);
    sessionsResult.fold((f) => erreur ??= f.errorMessage, (v) => sessions = v);
    connexionsResult.fold((f) => erreur ??= f.errorMessage, (v) => connexions = v);

    if (isClosed) return;
    emit(state.copyWith(
      status: erreur == null ? SettingsStatus.succes : SettingsStatus.erreur,
      erreur: erreur,
      mfaActive: mfaActive,
      sessions: sessions,
      connexions: connexions,
    ));
  }

  // -------------------- MOT DE PASSE --------------------

  /// Change le mot de passe. Renvoie `true` si le serveur a accepté ; sinon
  /// le message est dans `state.motDePasseErreur`.
  ///
  /// Verrou de double soumission : deux appuis enverraient deux requêtes, et
  /// la SECONDE échouerait en « mot de passe actuel incorrect » — le premier
  /// appel ayant déjà changé le mot de passe. Un échec parfaitement
  /// incompréhensible pour l'utilisateur, juste après un succès.
  /// Renvoie le nombre d'autres sessions fermées, ou `null` en cas d'échec —
  /// `0` est un SUCCÈS (aucun autre appareil connecté), pas une erreur : les
  /// distinguer par un booléen aurait mélangé les deux.
  Future<int?> changerMotDePasse({
    required String ancienMotDePasse,
    required String nouveauMotDePasse,
  }) async {
    if (state.motDePasseStatus == ActionStatus.enCours) return null;
    emit(state.copyWith(motDePasseStatus: ActionStatus.enCours, effacerMotDePasseErreur: true));

    final result = await repository.changerMotDePasse(
      ancienMotDePasse: ancienMotDePasse,
      nouveauMotDePasse: nouveauMotDePasse,
    );
    if (isClosed) return null;

    return result.fold(
      (failure) {
        emit(state.copyWith(motDePasseStatus: ActionStatus.erreur, motDePasseErreur: failure.errorMessage));
        return null;
      },
      (sessionsRevoquees) {
        emit(state.copyWith(motDePasseStatus: ActionStatus.succes, effacerMotDePasseErreur: true));
        return sessionsRevoquees;
      },
    );
  }

  // -------------------- MFA --------------------
  Future<void> demarrerProvisionnementMfa() async {
    if (state.mfaActionStatus == ActionStatus.enCours) return;
    emit(state.copyWith(mfaActionStatus: ActionStatus.enCours, effacerMfaErreur: true));
    final result = await repository.provisionnerMfa();
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(mfaActionStatus: ActionStatus.erreur, mfaErreur: failure.errorMessage)),
      (provisionnement) => emit(state.copyWith(
        mfaActionStatus: ActionStatus.inactif,
        provisionnement: provisionnement,
      )),
    );
  }

  Future<void> confirmerActivationMfa(String code) async {
    final secret = state.provisionnement?.secret;
    if (secret == null) return;
    // Verrou : un code TOTP n'est valable que 30 s, deux envois concurrents
    // du même code se voleraient la fenêtre de validité l'un à l'autre.
    if (state.mfaActionStatus == ActionStatus.enCours) return;
    emit(state.copyWith(mfaActionStatus: ActionStatus.enCours, effacerMfaErreur: true));
    final result = await repository.activerMfa(secret: secret, code: code);
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(mfaActionStatus: ActionStatus.erreur, mfaErreur: failure.errorMessage)),
      (_) => emit(state.copyWith(
        mfaActionStatus: ActionStatus.succes,
        mfaActive: true,
        effacerProvisionnement: true,
      )),
    );
  }

  Future<void> desactiverMfa(String code) async {
    if (state.mfaActionStatus == ActionStatus.enCours) return;
    emit(state.copyWith(mfaActionStatus: ActionStatus.enCours, effacerMfaErreur: true));
    final result = await repository.desactiverMfa(code: code);
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(mfaActionStatus: ActionStatus.erreur, mfaErreur: failure.errorMessage)),
      (_) => emit(state.copyWith(mfaActionStatus: ActionStatus.succes, mfaActive: false)),
    );
  }

  void annulerProvisionnementMfa() {
    emit(state.copyWith(effacerProvisionnement: true, mfaActionStatus: ActionStatus.inactif, effacerMfaErreur: true));
  }

  void accuserReceptionMfa() {
    emit(state.copyWith(mfaActionStatus: ActionStatus.inactif, effacerMfaErreur: true));
  }

  // -------------------- SESSIONS --------------------
  Future<void> revoquerSession(String sessionId) async {
    if (state.sessionActionStatus == ActionStatus.enCours) return;
    emit(state.copyWith(sessionActionStatus: ActionStatus.enCours, effacerSessionErreur: true));
    final result = await repository.revokerSession(sessionId);
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(sessionActionStatus: ActionStatus.erreur, sessionErreur: failure.errorMessage)),
      (_) => emit(state.copyWith(
        sessionActionStatus: ActionStatus.succes,
        sessions: state.sessions.where((s) => s.id != sessionId).toList(),
      )),
    );
  }

  /// Révoque toutes les sessions — y compris celle en cours : l'appelant
  /// (page) doit enchaîner sur une déconnexion locale après succès.
  Future<bool> revoquerToutesSessions() async {
    if (state.sessionActionStatus == ActionStatus.enCours) return false;
    emit(state.copyWith(sessionActionStatus: ActionStatus.enCours, effacerSessionErreur: true));
    final result = await repository.revokerToutesSessions();
    if (isClosed) return false;
    return result.fold(
      (failure) {
        emit(state.copyWith(sessionActionStatus: ActionStatus.erreur, sessionErreur: failure.errorMessage));
        return false;
      },
      (_) {
        emit(state.copyWith(sessionActionStatus: ActionStatus.succes, sessions: const []));
        return true;
      },
    );
  }

  // -------------------- LANGUE --------------------
  Future<bool> changerLangue(String code) async {
    if (state.langueActionStatus == ActionStatus.enCours) return false;
    emit(state.copyWith(langueActionStatus: ActionStatus.enCours));
    final result = await repository.changerLangue(code);
    if (isClosed) return false;
    return result.fold(
      (failure) {
        emit(state.copyWith(langueActionStatus: ActionStatus.erreur));
        return false;
      },
      (_) {
        emit(state.copyWith(langueActionStatus: ActionStatus.succes));
        return true;
      },
    );
  }

  // -------------------- RGPD --------------------
  Future<void> exporterDonnees() async {
    if (state.exportStatus == ActionStatus.enCours) return;
    emit(state.copyWith(exportStatus: ActionStatus.enCours, effacerExportErreur: true));
    final result = await repository.exporterDonnees();
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(exportStatus: ActionStatus.erreur, exportErreur: failure.errorMessage)),
      (donnees) => emit(state.copyWith(exportStatus: ActionStatus.succes, exportResume: donnees)),
    );
  }

  /// Renvoie `true` si la suppression a réussi — l'appelant (page) doit
  /// enchaîner sur une déconnexion locale.
  Future<bool> supprimerCompte() async {
    // Verrou CRITIQUE : un second `DELETE /account/delete-account` partirait
    // sur un compte déjà pseudonymisé et supprimé logiquement, produisant une
    // erreur incompréhensible juste après une suppression pourtant réussie.
    if (state.suppressionStatus == ActionStatus.enCours) return false;
    emit(state.copyWith(suppressionStatus: ActionStatus.enCours, effacerSuppressionErreur: true));
    final result = await repository.supprimerCompte();
    if (isClosed) return false;
    return result.fold(
      (failure) {
        emit(state.copyWith(suppressionStatus: ActionStatus.erreur, suppressionErreur: failure.errorMessage));
        return false;
      },
      (_) {
        emit(state.copyWith(suppressionStatus: ActionStatus.succes));
        return true;
      },
    );
  }
}
