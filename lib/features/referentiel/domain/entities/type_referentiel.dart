import 'package:equatable/equatable.dart';

/// Type issu d'un référentiel ADMINISTRABLE — document, intervenant,
/// inspection.
///
/// Ces trois listes étaient des énumérations Dart figées, miroir de colonnes
/// `ENUM` PostgreSQL. Ajouter « PPSPS » ou « pré-réception » demandait une
/// migration ET une livraison sur les trois plateformes. Elles vivent
/// désormais en base et se gèrent depuis l'espace d'administration.
///
/// ── Le CODE est la valeur enregistrée ─────────────────────────────────────
/// C'est lui qui part au serveur et qui est stocké dans la donnée
/// (`documents.type`…). Le [nom] n'est qu'un libellé d'affichage, que
/// l'administrateur peut changer sans rien casser.
class TypeReferentiel extends Equatable {
  final String id;
  final String code;
  final String nom;
  final String? description;
  final int ordre;

  /// `null` = catalogue STANDARD de la plateforme, commun à tous les clients.
  /// Renseigné = type propre à l'organisation.
  final String? organisationId;

  const TypeReferentiel({
    required this.id,
    required this.code,
    required this.nom,
    this.description,
    this.ordre = 0,
    this.organisationId,
  });

  factory TypeReferentiel.fromJson(Map<String, dynamic> json) => TypeReferentiel(
        id: json['id'] as String,
        code: json['code'] as String? ?? '',
        nom: json['nom'] as String? ?? '',
        description: json['description'] as String?,
        ordre: (json['ordre'] as num?)?.toInt() ?? 0,
        organisationId: json['organisationId'] as String?,
      );

  @override
  List<Object?> get props => [id, code, nom, description, ordre, organisationId];
}

/// Les trois référentiels administrables, et leur chemin d'API.
///
/// `typesIntervenant` côté URL, `partenaires` en base : le mot du métier a
/// changé, pas la table.
enum ReferentielType {
  document('/types-document'),
  intervenant('/types-intervenant'),
  inspection('/types-inspection');

  const ReferentielType(this.chemin);

  final String chemin;
}
