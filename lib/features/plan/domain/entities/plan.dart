import 'package:equatable/equatable.dart';

import '../../../reserve/domain/entities/reserve.dart';

/// Format d'un plan — miroir de l'ENUM `format`
/// (`backend/src/models/plan.model.js`).
///
/// Seul le PDF est réellement affichable sur mobile aujourd'hui ; DWG et IFC
/// existent côté back (import depuis le web) et doivent donc être représentés
/// ici, ne serait-ce que pour l'annoncer clairement à l'utilisateur au lieu
/// d'échouer silencieusement à l'ouverture.
enum PlanFormat { pdf, dwg, ifc }

extension PlanFormatX on PlanFormat {
  static PlanFormat fromString(String? raw) {
    switch (raw) {
      case 'dwg':
        return PlanFormat.dwg;
      case 'ifc':
        return PlanFormat.ifc;
      default:
        return PlanFormat.pdf;
    }
  }

  String get raw => switch (this) {
        PlanFormat.pdf => 'pdf',
        PlanFormat.dwg => 'dwg',
        PlanFormat.ifc => 'ifc',
      };

  String get label => switch (this) {
        PlanFormat.pdf => 'PDF',
        PlanFormat.dwg => 'DWG',
        PlanFormat.ifc => 'IFC (BIM)',
      };

  /// Vrai si le mobile sait rendre ce format dans la visionneuse.
  bool get affichableSurMobile => this == PlanFormat.pdf;
}

/// Position d'une réserve sur un plan — miroir de
/// `backend/src/models/reservePosition.model.js`. `x`/`y` sont les
/// coordonnées telles qu'enregistrées au moment de la pose du repère.
class PlanPosition extends Equatable {
  final double x;
  final double y;
  final double zoom;

  const PlanPosition({required this.x, required this.y, this.zoom = 1});

  factory PlanPosition.fromJson(Map<String, dynamic> json) => PlanPosition(
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        zoom: (json['zoom'] as num?)?.toDouble() ?? 1,
      );

  @override
  List<Object?> get props => [x, y, zoom];
}

/// Réserve telle que renvoyée par le détail d'un plan — volontairement
/// allégée (`PlanService.getPlan` ne sélectionne que id/numéro/titre/statut/
/// sévérité + position + une vignette), puisqu'elle ne sert qu'à poser un
/// repère et à alimenter la liste sous le plan.
class PlanReserve extends Equatable {
  final String id;
  final String numero;
  final String titre;
  final ReserveStatut statut;
  final ReserveSeverite severite;
  final PlanPosition? position;
  final String? photoApercu;

  const PlanReserve({
    required this.id,
    required this.numero,
    required this.titre,
    required this.statut,
    required this.severite,
    this.position,
    this.photoApercu,
  });

  factory PlanReserve.fromJson(Map<String, dynamic> json) => PlanReserve(
        id: json['id'] as String,
        numero: json['numero'] as String? ?? '',
        titre: json['titre'] as String? ?? '',
        statut: ReserveStatutX.fromString(json['statut'] as String?),
        severite: ReserveSeveriteX.fromString(json['severite'] as String?),
        position: json['position'] != null
            ? PlanPosition.fromJson(json['position'] as Map<String, dynamic>)
            : null,
        photoApercu: (json['medias'] is List && (json['medias'] as List).isNotEmpty)
            ? ((json['medias'] as List).first as Map<String, dynamic>)['url'] as String?
            : null,
      );

  @override
  List<Object?> get props => [id, numero, titre, statut, severite, position, photoApercu];
}

/// Plan numérique — miroir de `backend/src/models/plan.model.js`.
class Plan extends Equatable {
  final String id;
  final String chantierId;
  final String nom;
  final int version;
  final String fichierUrl;
  final PlanFormat format;
  final int? nombrePages;
  final String? fichierNom;
  final DateTime? createdAt;

  /// Nom du chantier — présent sur la liste transversale et le détail.
  final String? chantierNom;

  /// Réserves posées sur ce plan — renseignées par le DÉTAIL uniquement.
  final List<PlanReserve> reserves;

  const Plan({
    required this.id,
    required this.chantierId,
    required this.nom,
    this.version = 1,
    required this.fichierUrl,
    this.format = PlanFormat.pdf,
    this.nombrePages,
    this.fichierNom,
    this.createdAt,
    this.chantierNom,
    this.reserves = const [],
  });

  factory Plan.fromJson(Map<String, dynamic> json) {
    final chantier = json['chantier'] as Map<String, dynamic>?;
    return Plan(
      id: json['id'] as String,
      chantierId: json['chantierId'] as String? ?? json['chantier_id'] as String? ?? '',
      nom: json['nom'] as String? ?? '',
      version: json['version'] as int? ?? 1,
      fichierUrl: json['fichier_url'] as String? ?? '',
      format: PlanFormatX.fromString(json['format'] as String?),
      nombrePages: json['page_count'] as int?,
      fichierNom: json['fichier_nom'] as String?,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      chantierNom: chantier?['nom'] as String?,
      reserves: json['reserves'] is List
          ? (json['reserves'] as List).map((e) => PlanReserve.fromJson(e as Map<String, dynamic>)).toList()
          : const [],
    );
  }

  /// Nombre de repères réellement positionnables sur l'image du plan.
  int get nombreReperes => reserves.where((r) => r.position != null).length;

  @override
  List<Object?> get props =>
      [id, chantierId, nom, version, fichierUrl, format, nombrePages, fichierNom, createdAt, chantierNom, reserves];
}
