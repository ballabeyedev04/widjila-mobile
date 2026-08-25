import 'package:equatable/equatable.dart';

import '../../domain/entities/connexion_log_entry.dart';
import '../../domain/entities/mfa_provisionnement.dart';
import '../../domain/entities/session_active.dart';

enum SettingsStatus { initial, chargement, succes, erreur }

/// Statut générique d'une action ponctuelle (MFA, session, langue, export,
/// suppression) — chacune a le sien pour qu'une erreur sur l'une n'affecte
/// pas l'affichage des autres sections de l'écran.
enum ActionStatus { inactif, enCours, succes, erreur }

class SettingsState extends Equatable {
  final SettingsStatus status;
  final String? erreur;

  final bool mfaActive;
  final MfaProvisionnement? provisionnement;
  final ActionStatus mfaActionStatus;
  final String? mfaErreur;

  final List<SessionActive> sessions;
  final ActionStatus sessionActionStatus;
  final String? sessionErreur;

  final List<ConnexionLogEntry> connexions;

  final ActionStatus langueActionStatus;

  final ActionStatus exportStatus;
  final Map<String, dynamic>? exportResume;
  final String? exportErreur;

  final ActionStatus suppressionStatus;
  final String? suppressionErreur;

  final ActionStatus motDePasseStatus;
  final String? motDePasseErreur;

  const SettingsState({
    this.status = SettingsStatus.initial,
    this.erreur,
    this.mfaActive = false,
    this.provisionnement,
    this.mfaActionStatus = ActionStatus.inactif,
    this.mfaErreur,
    this.sessions = const [],
    this.sessionActionStatus = ActionStatus.inactif,
    this.sessionErreur,
    this.connexions = const [],
    this.langueActionStatus = ActionStatus.inactif,
    this.exportStatus = ActionStatus.inactif,
    this.exportResume,
    this.exportErreur,
    this.suppressionStatus = ActionStatus.inactif,
    this.suppressionErreur,
    this.motDePasseStatus = ActionStatus.inactif,
    this.motDePasseErreur,
  });

  SettingsState copyWith({
    SettingsStatus? status,
    String? erreur,
    bool? mfaActive,
    MfaProvisionnement? provisionnement,
    bool effacerProvisionnement = false,
    ActionStatus? mfaActionStatus,
    String? mfaErreur,
    bool effacerMfaErreur = false,
    List<SessionActive>? sessions,
    ActionStatus? sessionActionStatus,
    String? sessionErreur,
    bool effacerSessionErreur = false,
    List<ConnexionLogEntry>? connexions,
    ActionStatus? langueActionStatus,
    ActionStatus? exportStatus,
    Map<String, dynamic>? exportResume,
    String? exportErreur,
    bool effacerExportErreur = false,
    ActionStatus? suppressionStatus,
    String? suppressionErreur,
    bool effacerSuppressionErreur = false,
    ActionStatus? motDePasseStatus,
    String? motDePasseErreur,
    bool effacerMotDePasseErreur = false,
  }) {
    return SettingsState(
      status: status ?? this.status,
      erreur: erreur ?? this.erreur,
      mfaActive: mfaActive ?? this.mfaActive,
      provisionnement: effacerProvisionnement ? null : (provisionnement ?? this.provisionnement),
      mfaActionStatus: mfaActionStatus ?? this.mfaActionStatus,
      mfaErreur: effacerMfaErreur ? null : (mfaErreur ?? this.mfaErreur),
      sessions: sessions ?? this.sessions,
      sessionActionStatus: sessionActionStatus ?? this.sessionActionStatus,
      sessionErreur: effacerSessionErreur ? null : (sessionErreur ?? this.sessionErreur),
      connexions: connexions ?? this.connexions,
      langueActionStatus: langueActionStatus ?? this.langueActionStatus,
      exportStatus: exportStatus ?? this.exportStatus,
      exportResume: exportResume ?? this.exportResume,
      exportErreur: effacerExportErreur ? null : (exportErreur ?? this.exportErreur),
      suppressionStatus: suppressionStatus ?? this.suppressionStatus,
      suppressionErreur: effacerSuppressionErreur ? null : (suppressionErreur ?? this.suppressionErreur),
      motDePasseStatus: motDePasseStatus ?? this.motDePasseStatus,
      motDePasseErreur: effacerMotDePasseErreur ? null : (motDePasseErreur ?? this.motDePasseErreur),
    );
  }

  @override
  List<Object?> get props => [
        status,
        erreur,
        mfaActive,
        provisionnement,
        mfaActionStatus,
        mfaErreur,
        sessions,
        sessionActionStatus,
        sessionErreur,
        connexions,
        langueActionStatus,
        exportStatus,
        exportResume,
        exportErreur,
        suppressionStatus,
        suppressionErreur,
        motDePasseStatus,
        motDePasseErreur,
      ];
}
