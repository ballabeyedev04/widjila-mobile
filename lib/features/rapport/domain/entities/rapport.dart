import 'package:equatable/equatable.dart';

import '../../../../l10n/generated/app_localizations.dart';

/// Type de rapport — valeurs acceptées par `genererRapportSchema`
/// (`backend/src/modules/rapport/validation/rapport.validation.js`).
///
/// Stocké côté serveur en `STRING(50)` et non en ENUM : un type inconnu peut
/// donc revenir d'un rapport plus ancien ou généré depuis le web. D'où
/// [RapportTypeX.fromString] qui retombe sur [RapportType.reserves] plutôt que
/// de lever.
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

/// Rapport PDF — miroir de `backend/src/models/rapport.model.js`.
///
/// Le fichier est FIGÉ à la génération : il reflète l'état des données à cet
/// instant et ne se recalcule pas ensuite. C'est ce qui en fait une pièce
/// opposable, et c'est aussi pourquoi la date de génération est affichée à
/// côté de chaque ligne.
class Rapport extends Equatable {
  final String id;
  final String chantierId;
  final RapportType type;

  /// Libellé brut renvoyé par le serveur. Conservé tel quel pour pouvoir
  /// afficher un type inconnu sans le travestir en « Réserves ».
  final String typeBrut;

  final String fichierUrl;
  final DateTime? createdAt;

  const Rapport({
    required this.id,
    required this.chantierId,
    this.type = RapportType.reserves,
    this.typeBrut = '',
    required this.fichierUrl,
    this.createdAt,
  });

  /// Vrai quand le serveur a renvoyé un type que cette version du mobile ne
  /// connaît pas — l'écran affiche alors [typeBrut] au lieu d'un libellé faux.
  bool get typeInconnu =>
      typeBrut.isNotEmpty && typeBrut != type.raw;

  factory Rapport.fromJson(Map<String, dynamic> json) {
    final brut = json['type'] as String? ?? '';
    return Rapport(
      id: json['id'] as String,
      chantierId: json['chantierId'] as String? ?? json['chantier_id'] as String? ?? '',
      type: RapportTypeX.fromString(brut),
      typeBrut: brut,
      fichierUrl: json['fichier_url'] as String? ?? '',
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
    );
  }

  @override
  List<Object?> get props => [id, chantierId, type, typeBrut, fichierUrl, createdAt];
}
