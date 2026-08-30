import 'package:equatable/equatable.dart';

/// Corps d'état — un métier / type de travaux du BTP.
///
/// Miroir de `backend/src/models/corpsEtat.model.js`.
///
/// Remplace l'énumération figée `ReserveCategorie` : celle-ci recopiait dans
/// le code Dart les dix valeurs d'un ENUM PostgreSQL, si bien qu'ajouter
/// « Serrurerie » au catalogue imposait une migration, une livraison web ET
/// une mise à jour du magasin d'applications. Le catalogue est désormais servi
/// par l'API et administrable sans déploiement.
///
/// [organisationId] nul signale une ligne du catalogue STANDARD, commune à
/// toutes les organisations ; renseigné, c'est un métier propre à
/// l'organisation. Le mobile ne fait que consulter : la distinction ne sert
/// ici qu'à l'affichage.
class CorpsEtat extends Equatable {
  final String id;
  final String nom;
  final String? code;
  final String? description;
  final int ordre;
  final String? organisationId;

  const CorpsEtat({
    required this.id,
    required this.nom,
    this.code,
    this.description,
    this.ordre = 0,
    this.organisationId,
  });

  factory CorpsEtat.fromJson(Map<String, dynamic> json) => CorpsEtat(
        id: json['id'] as String,
        nom: json['nom'] as String? ?? '',
        code: json['code'] as String?,
        description: json['description'] as String?,
        ordre: (json['ordre'] as num?)?.toInt() ?? 0,
        organisationId: json['organisationId'] as String? ?? json['organisation_id'] as String?,
      );

  /// Vrai pour une ligne du catalogue fourni par la plateforme.
  bool get estStandard => organisationId == null;

  @override
  List<Object?> get props => [id, nom, code, description, ordre, organisationId];
}
