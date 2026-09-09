import 'package:equatable/equatable.dart';

/// Un code d'appartement du référentiel — « A001 », « A002 », « B12 ».
///
/// Miroir de `CodeAppartement` côté serveur. Le catalogue standard va de A001
/// à A015 ; une organisation y ajoute ses propres codes depuis le « + » de la
/// feuille de niveau, et ils deviennent alors visibles de tous ses collègues.
///
/// Le code d'appartement était auparavant un CHAMP LIBRE : deux utilisateurs
/// saisissaient « A001 » et « A-001 » pour le même logement, sans qu'aucune
/// liste ne puisse plus les rapprocher.
class CodeAppartement extends Equatable {
  final String id;
  final String code;

  /// Libellé lisible. Nul quand l'entreprise a créé le code à la volée : le
  /// code sert alors de libellé.
  final String? nom;

  final int ordre;

  /// `true` quand le code appartient au catalogue standard de la plateforme —
  /// il n'est alors pas retirable par l'organisation.
  final bool standard;

  const CodeAppartement({
    required this.id,
    required this.code,
    this.nom,
    this.ordre = 0,
    this.standard = false,
  });

  /// Ce que l'écran affiche : « A001 — Appartement 001 », ou le seul code
  /// quand il n'y a pas de libellé.
  String get libelle => (nom == null || nom!.isEmpty) ? code : '$code — $nom';

  factory CodeAppartement.fromJson(Map<String, dynamic> json) => CodeAppartement(
        id: json['id'] as String,
        code: json['code'] as String? ?? '',
        nom: json['nom'] as String?,
        ordre: (json['ordre'] as num?)?.toInt() ?? 0,
        // `organisationId` nul = catalogue de la plateforme.
        standard: json['organisationId'] == null,
      );

  @override
  List<Object?> get props => [id, code, nom, ordre, standard];
}
