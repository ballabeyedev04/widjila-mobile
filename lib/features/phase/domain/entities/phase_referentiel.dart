import 'package:equatable/equatable.dart';

/// Phase du référentiel — Pré-cloisons, Cloisons, OPR, Réception, GPA…
///
/// Miroir de `backend/src/models/phase.model.js`, côté RÉFÉRENTIEL
/// (`chantierId` nul). À ne pas confondre avec les phases de PLANNING d'un
/// chantier, qui portent des dates et alimentent le calendrier.
///
/// C'est la liste à laquelle chaque réserve DOIT se rattacher : le serveur
/// refuse une création sans phase (`creerReserveSchema`).
class PhaseReferentiel extends Equatable {
  final String id;
  final String nom;
  final String? description;

  /// Rang d'affichage, fixé par l'administrateur. L'ordre du chantier ne
  /// coïncide pas avec l'ordre alphabétique — « Décennale » ne précède pas
  /// « Pré-cloisons ».
  final int ordre;

  /// Nul pour le référentiel standard de la plateforme ; renseigné pour une
  /// phase propre à l'organisation.
  final String? organisationId;

  const PhaseReferentiel({
    required this.id,
    required this.nom,
    this.description,
    this.ordre = 0,
    this.organisationId,
  });

  factory PhaseReferentiel.fromJson(Map<String, dynamic> json) => PhaseReferentiel(
        id: json['id'] as String,
        nom: json['nom'] as String? ?? '',
        description: json['description'] as String?,
        ordre: (json['ordre'] as num?)?.toInt() ?? 0,
        organisationId: json['organisationId'] as String? ?? json['organisation_id'] as String?,
      );

  @override
  List<Object?> get props => [id, nom, description, ordre, organisationId];
}
