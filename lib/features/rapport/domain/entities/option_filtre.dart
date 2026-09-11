import 'package:equatable/equatable.dart';

/// Une valeur proposée dans un filtre — un projet, une entreprise, un corps
/// d'état. Réduite à ce que l'écran affiche : un identifiant (ce qui part au
/// serveur) et un nom (ce que l'utilisateur lit).
class OptionFiltre extends Equatable {
  final String id;
  final String nom;

  /// Précision affichée sous le nom — le code d'un chantier, par exemple.
  final String? detail;

  const OptionFiltre({required this.id, required this.nom, this.detail});

  factory OptionFiltre.fromJson(Map<String, dynamic> json, {String? cleDetail}) => OptionFiltre(
        id: json['id']?.toString() ?? '',
        nom: json['nom']?.toString() ?? '',
        detail: cleDetail == null ? null : json[cleDetail]?.toString(),
      );

  @override
  List<Object?> get props => [id, nom, detail];
}

/// Les listes des filtres « Entreprise » et « Corps d'état » (§ 4).
class OptionsFiltresRapport extends Equatable {
  final List<OptionFiltre> entreprises;
  final List<OptionFiltre> corpsEtat;

  const OptionsFiltresRapport({this.entreprises = const [], this.corpsEtat = const []});

  @override
  List<Object?> get props => [entreprises, corpsEtat];
}
