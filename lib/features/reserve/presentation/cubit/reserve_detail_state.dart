import 'package:equatable/equatable.dart';
import '../../domain/entities/reserve.dart';
import '../../domain/entities/reserve_collaboration.dart';

enum ReserveDetailStatus { chargement, succes, erreur }

/// Statut d'une action ponctuelle (commentaire, affectation, suppression) —
/// séparé de [ReserveDetailStatus] pour qu'un envoi de commentaire en échec
/// ne remplace pas la fiche entière par un écran d'erreur.
enum ActionReserveStatus { inactif, enCours, succes, erreur }

class ReserveDetailState extends Equatable {
  final ReserveDetailStatus status;
  final Reserve? reserve;
  final bool actionEnCours;
  final String? erreur;

  /// Fil de discussion. Chargé APRÈS la fiche, en tâche de fond : il ne doit
  /// pas retarder l'affichage de la réserve elle-même.
  final List<CommentaireReserve> commentaires;
  final bool commentairesCharges;
  final ActionReserveStatus commentaireStatus;

  final List<AffectationReserve> affectations;
  final bool affectationsChargees;
  final ActionReserveStatus affectationStatus;

  /// Passe à `true` quand le serveur a accepté la suppression — l'écran doit
  /// alors se refermer, il n'a plus rien à afficher.
  final bool supprimee;

  const ReserveDetailState({
    this.status = ReserveDetailStatus.chargement,
    this.reserve,
    this.actionEnCours = false,
    this.erreur,
    this.commentaires = const [],
    this.commentairesCharges = false,
    this.commentaireStatus = ActionReserveStatus.inactif,
    this.affectations = const [],
    this.affectationsChargees = false,
    this.affectationStatus = ActionReserveStatus.inactif,
    this.supprimee = false,
  });

  ReserveDetailState copyWith({
    ReserveDetailStatus? status,
    Reserve? reserve,
    bool? actionEnCours,
    String? erreur,
    List<CommentaireReserve>? commentaires,
    bool? commentairesCharges,
    ActionReserveStatus? commentaireStatus,
    List<AffectationReserve>? affectations,
    bool? affectationsChargees,
    ActionReserveStatus? affectationStatus,
    bool? supprimee,
  }) {
    return ReserveDetailState(
      status: status ?? this.status,
      reserve: reserve ?? this.reserve,
      actionEnCours: actionEnCours ?? false,
      erreur: erreur,
      commentaires: commentaires ?? this.commentaires,
      commentairesCharges: commentairesCharges ?? this.commentairesCharges,
      commentaireStatus: commentaireStatus ?? this.commentaireStatus,
      affectations: affectations ?? this.affectations,
      affectationsChargees: affectationsChargees ?? this.affectationsChargees,
      affectationStatus: affectationStatus ?? this.affectationStatus,
      supprimee: supprimee ?? this.supprimee,
    );
  }

  @override
  List<Object?> get props => [
        status,
        reserve,
        actionEnCours,
        erreur,
        commentaires,
        commentairesCharges,
        commentaireStatus,
        affectations,
        affectationsChargees,
        affectationStatus,
        supprimee,
      ];
}
