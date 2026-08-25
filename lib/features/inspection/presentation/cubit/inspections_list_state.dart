import 'package:equatable/equatable.dart';

import '../../domain/entities/inspection.dart';

enum InspectionsListStatus { initial, chargement, succes, erreur }

/// Statut de la CRÉATION, distinct de celui de la liste : un échec de création
/// ne doit pas effacer les visites déjà affichées.
enum CreationInspectionStatus { inactif, enCours, succes, erreur }

class InspectionsListState extends Equatable {
  final InspectionsListStatus status;
  final List<Inspection> items;
  final InspectionStatut? filtreStatut;
  final String? erreur;

  final CreationInspectionStatus creationStatus;
  final String? creationErreur;

  const InspectionsListState({
    this.status = InspectionsListStatus.initial,
    this.items = const [],
    this.filtreStatut,
    this.erreur,
    this.creationStatus = CreationInspectionStatus.inactif,
    this.creationErreur,
  });

  /// Visites encore ouvertes — c'est le travail qui reste à faire.
  List<Inspection> get enCours => items
      .where((i) => i.statut == InspectionStatut.planifiee || i.statut == InspectionStatut.enCours)
      .toList();

  /// Visites planifiées dont la date est passée : elles auraient dû avoir lieu.
  ///
  /// Comparaison sur la DATE seule, pas sur l'instant : une visite prévue
  /// aujourd'hui ne doit pas devenir « en retard » à partir de minuit une.
  List<Inspection> get enRetard {
    final aujourdHui = DateTime.now();
    final debutDuJour = DateTime(aujourdHui.year, aujourdHui.month, aujourdHui.day);
    return items.where((i) {
      if (i.statut != InspectionStatut.planifiee || i.dateVisite == null) return false;
      final d = i.dateVisite!;
      return DateTime(d.year, d.month, d.day).isBefore(debutDuJour);
    }).toList();
  }

  InspectionsListState copyWith({
    InspectionsListStatus? status,
    List<Inspection>? items,
    InspectionStatut? filtreStatut,
    bool effacerFiltreStatut = false,
    String? erreur,
    CreationInspectionStatus? creationStatus,
    String? creationErreur,
    bool effacerCreationErreur = false,
  }) {
    return InspectionsListState(
      status: status ?? this.status,
      items: items ?? this.items,
      filtreStatut: effacerFiltreStatut ? null : (filtreStatut ?? this.filtreStatut),
      erreur: erreur,
      creationStatus: creationStatus ?? this.creationStatus,
      creationErreur: effacerCreationErreur ? null : (creationErreur ?? this.creationErreur),
    );
  }

  @override
  List<Object?> get props => [status, items, filtreStatut, erreur, creationStatus, creationErreur];
}
