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

  /// PAGE du document sur laquelle le repère est posé — cahier technique § 6
  /// et § 18 (« plan multi-page → bonne page associée à la réserve »).
  ///
  /// Sans elle, les repères d'un PDF de douze pages se dessinaient tous sur la
  /// page affichée : chacun à ses bonnes coordonnées, mais sur la mauvaise
  /// page. Un repère faux envoie quelqu'un constater un défaut là où il n'y en
  /// a pas — c'est pire qu'un repère absent.
  ///
  /// `1` par défaut : le cas d'un plan d'une seule page, et celui de toutes
  /// les réserves posées avant que la page ne soit enregistrée.
  final int page;

  const PlanPosition({required this.x, required this.y, this.zoom = 1, this.page = 1});

  factory PlanPosition.fromJson(Map<String, dynamic> json) => PlanPosition(
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        zoom: (json['zoom'] as num?)?.toDouble() ?? 1,
        page: (json['page'] as num?)?.toInt() ?? 1,
      );

  @override
  List<Object?> get props => [x, y, zoom, page];
}

/// Réserve telle que renvoyée par le détail d'un plan — volontairement
/// allégée (`PlanService.getPlan` ne sélectionne que id/numéro/titre/statut/
/// sévérité + position + une vignette), puisqu'elle ne sert qu'à poser un
/// repère et à alimenter la liste sous le plan.
class PlanReserve extends Equatable {
  final String id;
  final String numero;

  /// Numéro de la réserve SUR CE PLAN (1, 2, 3…), attribué par le serveur.
  /// C'est ce que le repère affiche : « R-0031 » ne dit pas laquelle des
  /// réserves du plan a été relevée en premier, « 3 » oui. Nul tant que le
  /// serveur ne l'a pas attribué (réserve créée hors ligne, pas encore
  /// synchronisée).
  final int? numeroPlan;

  final String titre;

  /// Observation saisie à la création.
  ///
  /// Servie par le détail du plan depuis que la fiche qui s'ouvre au clic sur
  /// un repère doit montrer CE QUI A ÉTÉ SAISI. Sans elle, la fiche n'affichait
  /// qu'un titre et un badge, et lire l'observation obligeait à quitter le
  /// plan.
  final String? description;

  final ReserveStatut statut;
  final ReserveSeverite severite;
  final PlanPosition? position;
  final String? photoApercu;

  /// Dates portées par le modèle : création, dernière modification, échéance
  /// de levée. Toutes facultatives — une réserve sans échéance est le cas
  /// courant, et l'inventer serait pire que de ne rien afficher.
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? dateLimite;

  /// Auteur du constat, tel que joint par le détail du plan. « Qui a relevé
  /// ça ? » est la question qui suit immédiatement « qu'est-ce que c'est ? ».
  final String? createurNom;

  const PlanReserve({
    required this.id,
    required this.numero,
    this.numeroPlan,
    required this.titre,
    this.description,
    required this.statut,
    required this.severite,
    this.position,
    this.photoApercu,
    this.createdAt,
    this.updatedAt,
    this.dateLimite,
    this.createurNom,
  });

  factory PlanReserve.fromJson(Map<String, dynamic> json) => PlanReserve(
        id: json['id'] as String,
        numero: json['numero'] as String? ?? '',
        numeroPlan: (json['numeroPlan'] as num?)?.toInt(),
        titre: json['titre'] as String? ?? '',
        description: json['description'] as String?,
        statut: ReserveStatutX.fromString(json['statut'] as String?),
        severite: ReserveSeveriteX.fromString(json['severite'] as String?),
        position: json['position'] != null
            ? PlanPosition.fromJson(json['position'] as Map<String, dynamic>)
            : null,
        photoApercu: _apercu(json['medias']),
        createdAt: _date(json['createdAt']),
        updatedAt: _date(json['updatedAt']),
        dateLimite: _date(json['date_limite']),
        createurNom: _nomComplet(json['createur']),
      );

  @override
  List<Object?> get props => [
        id, numero, numeroPlan, titre, description, statut, severite, position, photoApercu,
        createdAt, updatedAt, dateLimite, createurNom,
      ];
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

  /// Plan dont celui-ci est le DÉTAIL — le plan d'une pièce dans celui d'un
  /// appartement, celui d'une façade dans celui d'un bâtiment.
  ///
  /// Nul pour l'immense majorité des plans : leur place vient alors de leurs
  /// rattachements de structure ([batiment], [etage], [zone]), qui restent la
  /// source de vérité pour « dans quel bâtiment, à quel étage ». Renseigné, il
  /// ouvre une profondeur quelconque SOUS le dernier niveau de structure — et
  /// le plan de détail hérite de la place de son parent, posée par le serveur.
  ///
  /// Miroir de `plans.parent_id` (migration 20260907000001).
  final String? parentId;

  /// Discipline du plan — « Architecture », « Électricité », « Plomberie »…
  /// (cahier technique § 4, champ « Type »).
  ///
  /// À ne pas confondre avec [format], qui décrit le FICHIER (pdf, dwg, ifc)
  /// et non son contenu.
  final String? typePlan;

  /// Date DU PLAN, distincte de [createdAt] qui est la date de DÉPÔT
  /// (cahier technique § 4).
  final DateTime? datePlan;

  /// Version COURANTE du plan (cahier technique § 10 et § 15).
  ///
  /// Le serveur ne sert que les versions courantes dans les listes ; ce
  /// drapeau permet de le DIRE à l'écran, comme le demande le § 15
  /// (« afficher clairement la version active »).
  final bool estVersionCourante;

  /// Cycle de validation du plan — miroir de `plans.statut`.
  ///
  /// Un plan joint à une DEMANDE de chantier attend la même validation que le
  /// chantier auquel il est joint, et le serveur refuse d'y poser une réserve
  /// (`reserve.service.js#_verifierLocalisation`). Le lire ici permet de le
  /// dire à l'écran plutôt que de laisser l'utilisateur remplir un formulaire
  /// pour rien.
  final String statut;

  /// Combien de sous-plans DIRECTS ce plan possède, et combien de réserves y
  /// sont posées — comptés par le serveur (`plan.service.js#_compterEnfants`).
  ///
  /// Indispensables à la navigation par niveau : le mobile ne charge qu'un
  /// cran d'arborescence à la fois, il ne peut donc pas déduire d'une liste
  /// locale qu'une tuile mène plus bas. Sans eux, il faudrait ouvrir chaque
  /// plan pour l'apprendre.
  ///
  /// Valent 0 sur les routes qui ne les servent pas (liste à plat, détail
  /// d'une version) : une tuile annonce alors « aucun sous-plan », ce qui est
  /// le cas le plus fréquent et jamais bloquant — la descente reste possible.
  final int nombreSousPlans;
  final int nombreReserves;

  /// Parmi [nombreReserves], celles qui restent À TRAITER — tout sauf
  /// validée et clôturée (`plan.service.js#_compterEnfants`).
  ///
  /// NUL, et non 0, quand le serveur ne le sert pas (version antérieure,
  /// détail d'un plan) : un « 0 à traiter » inventé passerait pour une bonne
  /// nouvelle.
  final int? nombreReservesATraiter;

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
    this.parentId,
    this.statut = 'actif',
    this.nombreSousPlans = 0,
    this.nombreReserves = 0,
    this.nombreReservesATraiter,
    this.typePlan,
    this.datePlan,
    this.estVersionCourante = true,
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
      parentId: (json['parentId'] ?? json['parent_id']) as String?,
      statut: json['statut'] as String? ?? 'actif',
      typePlan: json['type_plan'] as String?,
      datePlan: json['date_plan'] != null ? DateTime.tryParse(json['date_plan'] as String) : null,
      // Absent des réponses d'un serveur pas encore migré : on suppose alors
      // que le plan servi EST le courant — c'est ce que faisait le code avant
      // que le drapeau n'existe.
      estVersionCourante: json['is_current'] as bool? ?? true,
      nombreSousPlans: (json['nombre_sous_plans'] as num?)?.toInt() ?? 0,
      nombreReserves: (json['nombre_reserves'] as num?)?.toInt() ?? 0,
      nombreReservesATraiter: (json['nombre_reserves_a_traiter'] as num?)?.toInt(),
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

  /// Ce plan mène-t-il plus bas dans l'arborescence ?
  ///
  /// La navigation est progressive : une tuile qui a des enfants FAIT DESCENDRE
  /// d'un cran, une feuille ouvre directement sa zone de travail. C'est le seul
  /// endroit où cette distinction se décide.
  bool get aDesSousPlans => nombreSousPlans > 0;

  /// Vrai tant que le plan attend la validation de sa demande de chantier :
  /// le serveur y refuse toute réserve.
  bool get enAttenteValidation => statut == 'en_attente_validation';

  @override
  List<Object?> get props => [
        id, chantierId, nom, version, fichierUrl, format, nombrePages, fichierNom, createdAt,
        chantierNom, reserves, batiment, etage, zone, hotspots, parentId, statut,
        nombreSousPlans, nombreReserves, nombreReservesATraiter, typePlan, datePlan,
        estVersionCourante,
      ];
}

/// Une date de l'API, ou `null` — jamais une exception.
///
/// Le serveur sert de l'ISO 8601, mais une valeur absente, nulle ou malformée
/// ne doit pas faire tomber l'écran : une fiche sans date reste lisible.
DateTime? _date(Object? valeur) =>
    valeur is String ? DateTime.tryParse(valeur) : null;

/// « Prénom Nom » d'un utilisateur joint, ou `null` s'il n'y en a pas.
///
/// Les deux champs sont traités comme facultatifs : un compte peut n'avoir que
/// l'un des deux, et « null Diop » serait pire que « Diop ».
String? _nomComplet(Object? utilisateur) {
  if (utilisateur is! Map<String, dynamic>) return null;
  final morceaux = [utilisateur['prenom'], utilisateur['nom']]
      .whereType<String>()
      .map((m) => m.trim())
      .where((m) => m.isNotEmpty);
  final nom = morceaux.join(' ');
  return nom.isEmpty ? null : nom;
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
