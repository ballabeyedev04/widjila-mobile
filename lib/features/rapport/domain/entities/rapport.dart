import 'package:equatable/equatable.dart';

import '../../../../l10n/generated/app_localizations.dart';
import 'configuration_rapport.dart';
import 'etat_rapport.dart';
import 'modele_rapport.dart';

/// Ancien type de rapport — valeurs de `genererRapportSchema`
/// (`backend/src/modules/rapport/validation/rapport.validation.js`).
///
/// Conservé pour les rapports produits avant le module du cahier des
/// charges, et pour l'ancien point d'entrée. Stocké côté serveur en
/// `STRING(50)` : un type inconnu retombe sur [RapportType.reserves] plutôt
/// que de lever — voir [Rapport.typeInconnu].
enum RapportType { reserves, entreprise, batiment, qualite, visite, opr }

extension RapportTypeX on RapportType {
  static RapportType fromString(String? raw) {
    switch (raw) {
      case 'entreprise':
        return RapportType.entreprise;
      case 'batiment':
        return RapportType.batiment;
      case 'qualite':
        return RapportType.qualite;
      case 'visite':
        return RapportType.visite;
      case 'opr':
        return RapportType.opr;
      default:
        return RapportType.reserves;
    }
  }

  String get raw {
    switch (this) {
      case RapportType.reserves:
        return 'reserves';
      case RapportType.entreprise:
        return 'entreprise';
      case RapportType.batiment:
        return 'batiment';
      case RapportType.qualite:
        return 'qualite';
      case RapportType.visite:
        return 'visite';
      case RapportType.opr:
        return 'opr';
    }
  }

  String label(AppLocalizations l10n) {
    switch (this) {
      case RapportType.reserves:
        return l10n.rapportTypeReserves;
      case RapportType.entreprise:
        return l10n.rapportTypeEntreprise;
      case RapportType.batiment:
        return l10n.rapportTypeBatiment;
      case RapportType.qualite:
        return l10n.rapportTypeQualite;
      case RapportType.visite:
        return l10n.rapportTypeVisite;
      case RapportType.opr:
        return l10n.rapportTypeOpr;
    }
  }
}

/// Rapport — miroir de `backend/src/models/rapport.model.js` (table REPORT
/// du § 12 du cahier des charges).
///
/// Un rapport est d'abord une CONFIGURATION (modèle, filtres, sections,
/// formats) ; la génération en tire un fichier FIGÉ, qui reflète l'état des
/// données à cet instant et ne se recalcule pas ensuite. C'est ce qui en fait
/// une pièce opposable — et c'est pourquoi la date de génération et la
/// version sont affichées à côté de chaque ligne.
class Rapport extends Equatable {
  final String id;
  final String chantierId;
  final RapportType type;

  /// Libellé brut de l'ancien type. Conservé tel quel pour pouvoir afficher
  /// un type inconnu sans le travestir en « Réserves ».
  final String typeBrut;

  /// Nom donné au rapport — « Rapport Bâtiment A ».
  final String? nom;

  /// Modèle du § 5 ; `null` pour un modèle que cette version ne connaît pas.
  final ModeleRapport? modele;

  final EtatRapport etat;

  /// Fichier PDF — VIDE tant que le rapport n'est qu'un brouillon.
  final String fichierUrl;
  final String? fichierXlsxUrl;
  final Set<FormatRapport> formats;
  final SectionsRapport sections;
  final FiltresRapport filtres;
  final int version;
  final String? rapportParentId;
  final DateTime? genereLe;
  final int? nbReserves;
  final int? taillePdf;

  /// Motif du dernier échec, quand [etat] vaut [EtatRapport.echec].
  final String? erreur;

  /// Entreprise visée par un rapport « par entreprise » (§ 15).
  final String? partenaireId;
  final String? entrepriseNom;
  final String? lotGenerationId;
  final DateTime? createdAt;

  const Rapport({
    required this.id,
    required this.chantierId,
    this.type = RapportType.reserves,
    this.typeBrut = '',
    required this.fichierUrl,
    this.nom,
    this.modele,
    this.etat = EtatRapport.genere,
    this.fichierXlsxUrl,
    this.formats = const {FormatRapport.pdf},
    this.sections = const SectionsRapport(),
    this.filtres = const FiltresRapport(),
    this.version = 1,
    this.rapportParentId,
    this.genereLe,
    this.nbReserves,
    this.taillePdf,
    this.erreur,
    this.partenaireId,
    this.entrepriseNom,
    this.lotGenerationId,
    this.createdAt,
  });

  /// Vrai quand le serveur a renvoyé un ancien type que cette version du
  /// mobile ne connaît pas — l'écran affiche alors [typeBrut].
  bool get typeInconnu => typeBrut.isNotEmpty && typeBrut != type.raw;

  /// Un fichier existe : le rapport peut être ouvert, téléchargé, envoyé.
  bool get estGenere => fichierUrl.isNotEmpty;

  /// Diffusé : le régénérer produira une NOUVELLE VERSION (§ 18).
  bool get estDiffuse => etat == EtatRapport.envoye;

  bool get aExcel => (fichierXlsxUrl ?? '').isNotEmpty;

  /// Titre affiché : le nom donné, sinon le modèle, sinon l'ancien type.
  String titre(AppLocalizations l10n) {
    if (nom != null && nom!.trim().isNotEmpty) return nom!;
    if (modele != null) return modele!.label(l10n);
    return typeInconnu ? typeBrut : type.label(l10n);
  }

  /// La configuration de ce rapport — pour y revenir (§ 20) ou la dupliquer.
  ConfigurationRapport configuration() => ConfigurationRapport(
        chantierId: chantierId,
        nom: nom,
        modele: modele ?? ModeleRapport.global,
        filtres: filtres,
        sections: sections,
        formats: formats,
      );

  factory Rapport.fromJson(Map<String, dynamic> json) {
    final brut = json['type'] as String? ?? '';
    DateTime? date(String cle) => json[cle] is String ? DateTime.tryParse(json[cle] as String) : null;
    final formats = ((json['formats'] as List?) ?? const ['PDF'])
        .map((f) => FormatRapportX.fromString(f?.toString()))
        .whereType<FormatRapport>()
        .toSet();
    final entreprise = (json['entrepriseCible'] as Map?)?.cast<String, dynamic>();

    return Rapport(
      id: json['id'] as String,
      chantierId: json['chantierId'] as String? ?? json['chantier_id'] as String? ?? '',
      type: RapportTypeX.fromString(brut),
      typeBrut: brut,
      nom: json['nom'] as String?,
      modele: ModeleRapportX.fromString(json['modele'] as String?),
      etat: EtatRapportX.fromString(json['statut'] as String?),
      fichierUrl: json['fichier_url'] as String? ?? '',
      fichierXlsxUrl: json['fichier_xlsx_url'] as String?,
      formats: formats.isEmpty ? const {FormatRapport.pdf} : formats,
      sections: SectionsRapport.fromJson((json['sections'] as Map?)?.cast<String, dynamic>()),
      filtres: FiltresRapport.fromJson((json['filtres'] as Map?)?.cast<String, dynamic>()),
      version: (json['version'] as num?)?.toInt() ?? 1,
      rapportParentId: json['rapportParentId'] as String?,
      genereLe: date('genere_le'),
      nbReserves: (json['nb_reserves'] as num?)?.toInt(),
      taillePdf: (json['taille_pdf'] as num?)?.toInt(),
      erreur: json['erreur'] as String?,
      partenaireId: json['partenaireId'] as String?,
      entrepriseNom: entreprise?['nom'] as String?,
      lotGenerationId: json['lotGenerationId'] as String?,
      createdAt: date('createdAt'),
    );
  }

  @override
  List<Object?> get props => [
        id, chantierId, type, typeBrut, nom, modele, etat, fichierUrl, fichierXlsxUrl,
        formats, sections, filtres, version, rapportParentId, genereLe, nbReserves,
        taillePdf, erreur, partenaireId, entrepriseNom, lotGenerationId, createdAt,
      ];
}
