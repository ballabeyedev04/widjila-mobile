import 'package:equatable/equatable.dart';

/// Structure d'un chantier (bâtiments → étages → zones, + lots) — utilisée
/// uniquement pour peupler les sélecteurs de localisation de l'assistant de
/// création de réserve. Miroir partiel de la réponse de
/// `GET /chantiers/:id` (`ChantierService.getChantier`, qui inclut déjà
/// `batiments.etages.zones` et `lots`) : pas de nouvel endpoint nécessaire.
class StructureRef extends Equatable {
  final String id;
  final String nom;
  const StructureRef({required this.id, required this.nom});

  factory StructureRef.fromJson(Map<String, dynamic> json) =>
      StructureRef(id: json['id'] as String, nom: json['nom'] as String? ?? '');

  @override
  List<Object?> get props => [id, nom];
}

class ZoneStructure extends StructureRef {
  const ZoneStructure({required super.id, required super.nom});
  factory ZoneStructure.fromJson(Map<String, dynamic> json) =>
      ZoneStructure(id: json['id'] as String, nom: json['nom'] as String? ?? '');
}

class EtageStructure extends StructureRef {
  final List<ZoneStructure> zones;

  /// Cote du niveau : négative pour un sous-sol, 0 pour le rez-de-chaussée.
  /// C'est elle qui permet de présenter les niveaux comme le guide client —
  /// « SOUS-SOLS » d'un côté, « ÉTAGES » de l'autre — au lieu d'une seule
  /// liste où SS2 se retrouve entre R+1 et R+2.
  final int niveau;

  const EtageStructure({required super.id, required super.nom, this.zones = const [], this.niveau = 0});

  factory EtageStructure.fromJson(Map<String, dynamic> json) => EtageStructure(
        id: json['id'] as String,
        nom: json['nom'] as String? ?? '',
        niveau: (json['niveau'] as num?)?.toInt() ?? 0,
        zones: (json['zones'] as List? ?? []).map((e) => ZoneStructure.fromJson(e as Map<String, dynamic>)).toList(),
      );

  @override
  List<Object?> get props => [id, nom, niveau, zones];
}

class BatimentStructure extends StructureRef {
  final List<EtageStructure> etages;
  const BatimentStructure({required super.id, required super.nom, this.etages = const []});

  factory BatimentStructure.fromJson(Map<String, dynamic> json) => BatimentStructure(
        id: json['id'] as String,
        nom: json['nom'] as String? ?? '',
        etages: (json['etages'] as List? ?? []).map((e) => EtageStructure.fromJson(e as Map<String, dynamic>)).toList(),
      );

  @override
  List<Object?> get props => [id, nom, etages];
}

class ChantierStructure {
  final List<BatimentStructure> batiments;
  final List<StructureRef> lots;
  const ChantierStructure({this.batiments = const [], this.lots = const []});

  factory ChantierStructure.fromJson(Map<String, dynamic> json) => ChantierStructure(
        batiments: (json['batiments'] as List? ?? []).map((e) => BatimentStructure.fromJson(e as Map<String, dynamic>)).toList(),
        lots: (json['lots'] as List? ?? []).map((e) => StructureRef.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
