import 'package:equatable/equatable.dart';

import '../../domain/entities/inspection.dart';

enum InspectionDetailStatus { initial, chargement, succes, erreur }

class InspectionDetailState extends Equatable {
  final InspectionDetailStatus status;
  final Inspection? inspection;
  final List<Convocation> convocations;
  final String? erreur;

  /// Lignes dont la bascule est en cours d'envoi. Permet de désactiver
  /// UNIQUEMENT la case concernée : bloquer toute la checklist pendant un
  /// aller-retour réseau casserait le rythme de saisie sur un chantier, où
  /// l'on coche plusieurs points d'affilée.
  final Set<String> lignesEnCours;

  /// Un échec de cochage est signalé sans vider l'écran : la visite reste
  /// lisible, seule la ligne fautive revient à son état précédent.
  final String? erreurAction;

  const InspectionDetailState({
    this.status = InspectionDetailStatus.initial,
    this.inspection,
    this.convocations = const [],
    this.erreur,
    this.lignesEnCours = const {},
    this.erreurAction,
  });

  InspectionDetailState copyWith({
    InspectionDetailStatus? status,
    Inspection? inspection,
    List<Convocation>? convocations,
    String? erreur,
    Set<String>? lignesEnCours,
    String? erreurAction,
    bool effacerErreurAction = false,
  }) {
    return InspectionDetailState(
      status: status ?? this.status,
      inspection: inspection ?? this.inspection,
      convocations: convocations ?? this.convocations,
      erreur: erreur,
      lignesEnCours: lignesEnCours ?? this.lignesEnCours,
      erreurAction: effacerErreurAction ? null : (erreurAction ?? this.erreurAction),
    );
  }

  @override
  List<Object?> get props => [status, inspection, convocations, erreur, lignesEnCours, erreurAction];
}
