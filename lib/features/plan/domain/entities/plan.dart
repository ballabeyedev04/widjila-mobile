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
        photoApercu: _apercu(json['medias']),
      );

  @override
  List<Object?> get props => [id, numero, titre, statut, severite, position, photoApercu];
}

/// Référence à un niveau de la structure du chantier, telle que jointe au
/// plan par le backend (`INCLUDE_LOCALISATION` de `plan.service.js`).
class PlanNiveauRef extends Equatable {
  final String id;
  final String nom;

  const PlanNiveauRef({required this.id, required this.nom});

  static PlanNiveauRef? fromJson(Map<String, dynamic>? json) {
    if (json == null || json['id'] == null) return null;
    return PlanNiveauRef(id: json['id'] as String, nom: json['nom'] as String? ?? '');
  }

  @override
  List<Object?> get props => [id, nom];
}

/// Niveau de la structure ciblé par une zone cliquable.
enum PlanCibleType { batiment, etage, zone }

extension PlanCibleTypeX on PlanCibleType {
  static PlanCibleType fromString(String? raw) => switch (raw) {
        'batiment' => PlanCibleType.batiment,
        'etage' => PlanCibleType.etage,
        _ => PlanCibleType.zone,
      };
}

/// Zone cliquable posée sur un plan — miroir de
/// `backend/src/models/planHotspot.model.js`.
///
/// `x`, `y`, `largeur` et `hauteur` sont des POURCENTAGES (0-100) de la page
/// rendue. C'est la même convention que [PlanPosition] : le plan est affiché à
/// une taille qui dépend de l'écran et du zoom, seul un repère relatif reste
/// juste d'un appareil à l'autre.
class PlanHotspot extends Equatable {
  final String id;
  final PlanCibleType cibleType;
  final String cibleId;
  final String? libelle;
  final double x;
  final double y;
  final double largeur;
  final double hauteur;

  const PlanHotspot({
    required this.id,
    required this.cibleType,
    required this.cibleId,
    this.libelle,
    required this.x,
    required this.y,
    this.largeur = 0,
    this.hauteur = 0,
  });

  factory PlanHotspot.fromJson(Map<String, dynamic> json) => PlanHotspot(
        id: json['id'] as String,
        cibleType: PlanCibleTypeX.fromString(json['cible_type'] as String?),
        cibleId: json['cible_id'] as String? ?? '',
        libelle: json['libelle'] as String?,
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        largeur: (json['largeur'] as num?)?.toDouble() ?? 0,
        hauteur: (json['hauteur'] as num?)?.toDouble() ?? 0,
      );

  @override
  List<Object?> get props => [id, cibleType, cibleId, libelle, x, y, largeur, hauteur];
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

  /// Niveau de la structure DÉCRIT par ce plan. Les trois sont nuls pour le
  /// plan global du chantier — le point d'entrée du parcours de consultation.
  final PlanNiveauRef? batiment;
  final PlanNiveauRef? etage;
  final PlanNiveauRef? zone;

  /// Zones cliquables qui font descendre d'un niveau. Vides tant que personne
  /// ne les a dessinées : la navigation reste alors possible par les listes.
  final List<PlanHotspot> hotspots;

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
    this.batiment,
    this.etage,
    this.zone,
    this.hotspots = const [],
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
      // La zone porte sa propre chaîne (zone → étage → bâtiment) : on
      // privilégie les rattachements DIRECTS quand ils existent, et on
      // retombe sur la chaîne remontée depuis la zone sinon.
      batiment: PlanNiveauRef.fromJson(
        (json['batiment'] as Map<String, dynamic>?) ??
            ((json['etage'] as Map<String, dynamic>?)?['batiment'] as Map<String, dynamic>?) ??
            (((json['zone'] as Map<String, dynamic>?)?['etage'] as Map<String, dynamic>?)?['batiment']
                as Map<String, dynamic>?),
      ),
      etage: PlanNiveauRef.fromJson(
        (json['etage'] as Map<String, dynamic>?) ??
            ((json['zone'] as Map<String, dynamic>?)?['etage'] as Map<String, dynamic>?),
      ),
      zone: PlanNiveauRef.fromJson(json['zone'] as Map<String, dynamic>?),
      hotspots: json['hotspots'] is List
          ? (json['hotspots'] as List).map((e) => PlanHotspot.fromJson(e as Map<String, dynamic>)).toList()
          : const [],
    );
  }

  /// Nombre de repères réellement positionnables sur l'image du plan.
  int get nombreReperes => reserves.where((r) => r.position != null).length;

  @override
  List<Object?> get props => [
        id, chantierId, nom, version, fichierUrl, format, nombrePages, fichierNom, createdAt,
        chantierNom, reserves, batiment, etage, zone, hotspots,
      ];
}

/// URL d'aperçu d'une liste de médias — la VIGNETTE d'abord.
///
/// Le serveur sélectionne explicitement `thumbnail_url` pour ces requêtes
/// d'aperçu (voir `reserve.service.js` et `plan.service.js`), et le mobile
/// lisait quand même `url` : il jetait ce qu'on lui envoyait et rapatriait
/// l'original — plusieurs mégaoctets sortis d'un appareil photo — pour une
/// vignette de carte.
///
/// Le repli sur l'original reste indispensable : les médias envoyés AVANT que
/// le serveur ne produise des vignettes n'en ont pas, et n'en auront jamais.
String? _apercu(Object? medias) {
  if (medias is! List || medias.isEmpty) return null;
  final premier = medias.first;
  if (premier is! Map<String, dynamic>) return null;
  final vignette = premier['thumbnail_url'] as String?;
  if (vignette != null && vignette.isNotEmpty) return vignette;
  return premier['url'] as String?;
}
