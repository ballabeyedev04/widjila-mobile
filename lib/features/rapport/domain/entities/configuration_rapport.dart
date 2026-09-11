import 'package:equatable/equatable.dart';

import '../../../../l10n/generated/app_localizations.dart';
import 'modele_rapport.dart';

/// Les cinq statuts du rapport — § 4 du cahier des charges.
///
/// Ce ne sont PAS les statuts d'une réserve : le serveur traduit chacun
/// d'eux vers les statuts réels (`À contrôler` couvre « corrigée » et « à
/// vérifier », par exemple). Le mobile n'a donc pas à connaître cette
/// correspondance, et ne risque pas de la faire diverger.
enum StatutReserveRapport { aTraiter, enCours, aControler, levee, cloturee }

extension StatutReserveRapportX on StatutReserveRapport {
  String get raw => switch (this) {
        StatutReserveRapport.aTraiter => 'A_TRAITER',
        StatutReserveRapport.enCours => 'EN_COURS',
        StatutReserveRapport.aControler => 'A_CONTROLER',
        StatutReserveRapport.levee => 'LEVEE',
        StatutReserveRapport.cloturee => 'CLOTUREE',
      };

  static StatutReserveRapport? fromString(String? brut) {
    for (final s in StatutReserveRapport.values) {
      if (s.raw == brut?.toUpperCase()) return s;
    }
    return null;
  }

  String label(AppLocalizations l10n) => switch (this) {
        StatutReserveRapport.aTraiter => l10n.rapportStatutATraiter,
        StatutReserveRapport.enCours => l10n.rapportStatutEnCours,
        StatutReserveRapport.aControler => l10n.rapportStatutAControler,
        StatutReserveRapport.levee => l10n.rapportStatutLevee,
        StatutReserveRapport.cloturee => l10n.rapportStatutCloturee,
      };
}

/// Les trois gravités — § 4.
enum GraviteRapport { critique, majeure, mineure }

extension GraviteRapportX on GraviteRapport {
  String get raw => switch (this) {
        GraviteRapport.critique => 'CRITIQUE',
        GraviteRapport.majeure => 'MAJEURE',
        GraviteRapport.mineure => 'MINEURE',
      };

  static GraviteRapport? fromString(String? brut) {
    for (final g in GraviteRapport.values) {
      if (g.raw == brut?.toUpperCase()) return g;
    }
    return null;
  }

  String label(AppLocalizations l10n) => switch (this) {
        GraviteRapport.critique => l10n.rapportGraviteCritique,
        GraviteRapport.majeure => l10n.rapportGraviteMajeure,
        GraviteRapport.mineure => l10n.rapportGraviteMineure,
      };
}

/// Formats de sortie — § 4 (« PDF / Excel / PDF + Excel »).
enum FormatRapport { pdf, xlsx }

extension FormatRapportX on FormatRapport {
  String get raw => this == FormatRapport.pdf ? 'PDF' : 'XLSX';

  static FormatRapport? fromString(String? brut) {
    final v = brut?.toUpperCase();
    if (v == 'PDF') return FormatRapport.pdf;
    if (v == 'XLSX' || v == 'EXCEL') return FormatRapport.xlsx;
    return null;
  }

  String label(AppLocalizations l10n) =>
      this == FormatRapport.pdf ? l10n.rapportFormatPdf : l10n.rapportFormatExcel;
}

/// Les cinq sections du § 10 — ce que le document contient.
class SectionsRapport extends Equatable {
  final bool summary;
  final bool plans;
  final bool photos;
  final bool location;
  final bool history;

  const SectionsRapport({
    this.summary = true,
    this.plans = true,
    this.photos = true,
    this.location = true,
    this.history = false,
  });

  factory SectionsRapport.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SectionsRapport();
    const defaut = SectionsRapport();
    bool lire(String cle, bool valeur) => json[cle] is bool ? json[cle] as bool : valeur;
    return SectionsRapport(
      summary: lire('summary', defaut.summary),
      plans: lire('plans', defaut.plans),
      photos: lire('photos', defaut.photos),
      location: lire('location', defaut.location),
      history: lire('history', defaut.history),
    );
  }

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'plans': plans,
        'photos': photos,
        'location': location,
        'history': history,
      };

  SectionsRapport copyWith({bool? summary, bool? plans, bool? photos, bool? location, bool? history}) =>
      SectionsRapport(
        summary: summary ?? this.summary,
        plans: plans ?? this.plans,
        photos: photos ?? this.photos,
        location: location ?? this.location,
        history: history ?? this.history,
      );

  @override
  List<Object?> get props => [summary, plans, photos, location, history];
}

/// Les filtres du § 4.
///
/// Chaque liste VIDE signifie « Tous » — c'est la lecture du cahier des
/// charges (« Bâtiment : Tous / A / B / C »). Une liste renseignée est une
/// SÉLECTION : le serveur n'inclut que ces valeurs, et refuse un identifiant
/// qui n'appartient pas au chantier.
class FiltresRapport extends Equatable {
  final List<String> batiments;
  final List<String> etages;
  final List<String> zones;
  final List<String> entreprises;
  final List<String> corpsEtat;
  final List<StatutReserveRapport> statuts;
  final List<GraviteRapport> gravites;
  final DateTime? dateDebut;
  final DateTime? dateFin;

  const FiltresRapport({
    this.batiments = const [],
    this.etages = const [],
    this.zones = const [],
    this.entreprises = const [],
    this.corpsEtat = const [],
    this.statuts = const [],
    this.gravites = const [],
    this.dateDebut,
    this.dateFin,
  });

  factory FiltresRapport.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const FiltresRapport();
    List<String> ids(String cle) =>
        ((json[cle] as List?) ?? const []).map((e) => e.toString()).toList();
    DateTime? date(String cle) => json[cle] is String ? DateTime.tryParse(json[cle] as String) : null;

    return FiltresRapport(
      batiments: ids('batiments'),
      etages: ids('etages'),
      zones: ids('zones'),
      entreprises: ids('entreprises'),
      corpsEtat: ids('corpsEtat'),
      statuts: ids('statuts').map(StatutReserveRapportX.fromString).whereType<StatutReserveRapport>().toList(),
      gravites: ids('gravites').map(GraviteRapportX.fromString).whereType<GraviteRapport>().toList(),
      dateDebut: date('dateDebut'),
      dateFin: date('dateFin'),
    );
  }

  /// Les filtres sous les noms que le serveur lit.
  ///
  /// Les listes vides NE SONT PAS envoyées : une liste vide transmise serait
  /// lue comme « aucune valeur », donc comme un filtre qui exclut tout.
  Map<String, dynamic> toJson() {
    String jour(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return {
      if (batiments.isNotEmpty) 'batiments': batiments,
      if (etages.isNotEmpty) 'etages': etages,
      if (zones.isNotEmpty) 'zones': zones,
      if (entreprises.isNotEmpty) 'entreprises': entreprises,
      if (corpsEtat.isNotEmpty) 'corpsEtat': corpsEtat,
      if (statuts.isNotEmpty) 'statuts': statuts.map((s) => s.raw).toList(),
      if (gravites.isNotEmpty) 'gravites': gravites.map((g) => g.raw).toList(),
      if (dateDebut != null) 'dateDebut': jour(dateDebut!),
      if (dateFin != null) 'dateFin': jour(dateFin!),
    };
  }

  /// Vrai si aucun filtre n'est posé — le rapport couvre tout le chantier.
  bool get estVide => toJson().isEmpty;

  FiltresRapport copyWith({
    List<String>? batiments,
    List<String>? etages,
    List<String>? zones,
    List<String>? entreprises,
    List<String>? corpsEtat,
    List<StatutReserveRapport>? statuts,
    List<GraviteRapport>? gravites,
    DateTime? dateDebut,
    DateTime? dateFin,
    bool effacerPeriode = false,
  }) =>
      FiltresRapport(
        batiments: batiments ?? this.batiments,
        etages: etages ?? this.etages,
        zones: zones ?? this.zones,
        entreprises: entreprises ?? this.entreprises,
        corpsEtat: corpsEtat ?? this.corpsEtat,
        statuts: statuts ?? this.statuts,
        gravites: gravites ?? this.gravites,
        dateDebut: effacerPeriode ? null : (dateDebut ?? this.dateDebut),
        dateFin: effacerPeriode ? null : (dateFin ?? this.dateFin),
      );

  /// Ce que le modèle exige et qui MANQUE encore — vide si tout est prêt.
  ///
  /// Le serveur refuserait de toute façon ; le vérifier ici permet de le
  /// dire à l'étape des filtres, là où l'utilisateur peut le corriger, plutôt
  /// qu'après un aller-retour réseau.
  List<FiltreRequis> manquantsPour(ModeleRapport modele) => [
        for (final requis in modele.filtresRequis)
          if (switch (requis) {
            FiltreRequis.batiment => batiments.isEmpty,
            FiltreRequis.etageOuZone => etages.isEmpty && zones.isEmpty,
            FiltreRequis.entreprise => entreprises.isEmpty,
            FiltreRequis.corpsEtat => corpsEtat.isEmpty,
          })
            requis,
      ];

  @override
  List<Object?> get props =>
      [batiments, etages, zones, entreprises, corpsEtat, statuts, gravites, dateDebut, dateFin];
}

/// La configuration complète d'un rapport — l'exemple du § 10.
class ConfigurationRapport extends Equatable {
  final String chantierId;
  final String? nom;
  final ModeleRapport modele;
  final FiltresRapport filtres;
  final SectionsRapport sections;
  final Set<FormatRapport> formats;

  const ConfigurationRapport({
    required this.chantierId,
    required this.modele,
    this.nom,
    this.filtres = const FiltresRapport(),
    this.sections = const SectionsRapport(),
    this.formats = const {FormatRapport.pdf},
  });

  /// Corps de `POST /reports` et `PATCH /reports/:id`.
  Map<String, dynamic> toJson({bool avecChantier = true}) => {
        if (avecChantier) 'chantierId': chantierId,
        if (nom != null && nom!.trim().isNotEmpty) 'nom': nom!.trim(),
        'modele': modele.raw,
        'filtres': filtres.toJson(),
        'sections': sections.toJson(),
        // Ordre stable : PDF d'abord, comme dans le cahier des charges.
        'formats': [
          for (final f in FormatRapport.values)
            if (formats.contains(f)) f.raw,
        ],
      };

  @override
  List<Object?> get props => [chantierId, nom, modele, filtres, sections, formats];
}
