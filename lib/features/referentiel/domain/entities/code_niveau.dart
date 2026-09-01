import 'package:equatable/equatable.dart';

/// Les trois SECTIONS de l'écran de dépôt de plans.
///
/// Miroir de `TYPE_NIVEAU` côté serveur. Ce n'est pas une cote — SS2 et R+2
/// ont des cotes opposées — mais la nature du niveau, et rien dans un entier
/// ne dit qu'un niveau est une toiture.
enum TypeNiveau { sousSol, etage, toiture }

extension TypeNiveauX on TypeNiveau {
  /// Valeur envoyée au serveur et stockée en base.
  String get raw {
    switch (this) {
      case TypeNiveau.sousSol:
        return 'sous_sol';
      case TypeNiveau.etage:
        return 'etage';
      case TypeNiveau.toiture:
        return 'toiture';
    }
  }

  static TypeNiveau fromString(String? brut) {
    switch (brut) {
      case 'sous_sol':
        return TypeNiveau.sousSol;
      case 'toiture':
        return TypeNiveau.toiture;
      // `etage` est le défaut du serveur : un type inconnu s'y range plutôt
      // que d'être écarté, faute de quoi un niveau disparaîtrait de l'écran
      // sans que rien ne le signale.
      default:
        return TypeNiveau.etage;
    }
  }
}

/// Un code de niveau du référentiel — « SS1 », « RDC », « R+1 », « TOIT ».
class CodeNiveau extends Equatable {
  final String id;
  final TypeNiveau typeNiveau;
  final String code;

  /// Libellé lisible. Vide quand l'entreprise a créé le code à la volée : le
  /// code sert alors de libellé.
  final String? nom;

  final int ordre;

  /// `true` quand le code appartient au catalogue standard de la plateforme —
  /// il n'est alors pas modifiable par l'organisation.
  final bool standard;

  const CodeNiveau({
    required this.id,
    required this.typeNiveau,
    required this.code,
    this.nom,
    this.ordre = 0,
    this.standard = false,
  });

  factory CodeNiveau.fromJson(Map<String, dynamic> json) => CodeNiveau(
        id: json['id'] as String,
        typeNiveau: TypeNiveauX.fromString(json['typeNiveau'] as String? ?? json['type_niveau'] as String?),
        code: json['code'] as String? ?? '',
        nom: json['nom'] as String?,
        ordre: (json['ordre'] as num?)?.toInt() ?? 0,
        // `organisationId` nul = catalogue de la plateforme.
        standard: (json['organisationId'] ?? json['organisation_id']) == null,
      );

  /// Ce qu'on affiche dans la liste : le code, et son libellé s'il en a un.
  String get libelle => (nom == null || nom!.isEmpty) ? code : '$code — $nom';

  @override
  List<Object?> get props => [id, typeNiveau, code, nom, ordre, standard];
}
