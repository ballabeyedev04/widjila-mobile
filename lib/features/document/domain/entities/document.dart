import 'package:equatable/equatable.dart';

import '../../../../l10n/generated/app_localizations.dart';

/// Type de document — miroir de l'ENUM Sequelize
/// (`backend/src/models/document.model.js`).
enum DocumentType { plan, contrat, doe, pv, compteRendu, rapport, notice, photo, autre }

extension DocumentTypeX on DocumentType {
  static DocumentType fromString(String? raw) {
    switch (raw) {
      case 'plan':
        return DocumentType.plan;
      case 'contrat':
        return DocumentType.contrat;
      case 'doe':
        return DocumentType.doe;
      case 'pv':
        return DocumentType.pv;
      case 'compte_rendu':
        return DocumentType.compteRendu;
      case 'rapport':
        return DocumentType.rapport;
      case 'notice':
        return DocumentType.notice;
      case 'photo':
        return DocumentType.photo;
      default:
        return DocumentType.autre;
    }
  }

  String get raw {
    switch (this) {
      case DocumentType.plan:
        return 'plan';
      case DocumentType.contrat:
        return 'contrat';
      case DocumentType.doe:
        return 'doe';
      case DocumentType.pv:
        return 'pv';
      case DocumentType.compteRendu:
        return 'compte_rendu';
      case DocumentType.rapport:
        return 'rapport';
      case DocumentType.notice:
        return 'notice';
      case DocumentType.photo:
        return 'photo';
      case DocumentType.autre:
        return 'autre';
    }
  }

  String label(AppLocalizations l10n) {
    switch (this) {
      case DocumentType.plan:
        return l10n.documentTypePlan;
      case DocumentType.contrat:
        return l10n.documentTypeContrat;
      case DocumentType.doe:
        return l10n.documentTypeDoe;
      case DocumentType.pv:
        return l10n.documentTypePv;
      case DocumentType.compteRendu:
        return l10n.documentTypeCompteRendu;
      case DocumentType.rapport:
        return l10n.documentTypeRapport;
      case DocumentType.notice:
        return l10n.documentTypeNotice;
      case DocumentType.photo:
        return l10n.documentTypePhoto;
      case DocumentType.autre:
        return l10n.documentTypeAutre;
    }
  }
}

/// Document (GED du chantier) — miroir de
/// `backend/src/models/document.model.js`.
class ChantierDocument extends Equatable {
  final String id;
  final String chantierId;
  final DocumentType type;
  final String nomFichier;
  final String fichierUrl;
  final String? mimeType;
  final int? taille;
  final int version;
  final bool archive;
  final DateTime? createdAt;

  const ChantierDocument({
    required this.id,
    required this.chantierId,
    this.type = DocumentType.autre,
    required this.nomFichier,
    required this.fichierUrl,
    this.mimeType,
    this.taille,
    this.version = 1,
    this.archive = false,
    this.createdAt,
  });

  /// Taille lisible (« 2,4 Mo », « 340 Ko ») — `null` si inconnue.
  String? tailleLisible(AppLocalizations l10n) {
    if (taille == null) return null;
    final ko = taille! / 1024;
    if (ko < 1024) return l10n.documentTailleKo(ko.toStringAsFixed(0));
    return l10n.documentTailleMo((ko / 1024).toStringAsFixed(1));
  }

  /// Extension du nom de fichier, en minuscules et sans le point.
  String get extension {
    final i = nomFichier.lastIndexOf('.');
    if (i < 0 || i == nomFichier.length - 1) return '';
    return nomFichier.substring(i + 1).toLowerCase();
  }

  /// Type MIME exploitable, `null` s'il est absent ou générique — l'extension
  /// prend alors le relais (lignes anciennes, dépôts sans type).
  String? get _mimeConnu {
    final mime = mimeType?.trim().toLowerCase();
    if (mime == null || mime.isEmpty || mime == 'application/octet-stream') return null;
    return mime;
  }

  static const _mimesImage = {'image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/gif'};
  static const _extensionsImage = {'jpg', 'jpeg', 'png', 'webp', 'gif'};
  static const _extensionsVideo = {'mp4', 'm4v', '3gp', 'mov', 'webm'};

  /// Photo affichable telle quelle. Seuls les formats MATRICIELS comptent :
  /// un plan DWG servi en `image/vnd.dwg` n'est pas une photo.
  bool get estImage {
    final mime = _mimeConnu;
    return mime != null ? _mimesImage.contains(mime) : _extensionsImage.contains(extension);
  }

  bool get estVideo {
    final mime = _mimeConnu;
    return mime != null ? mime.startsWith('video/') : _extensionsVideo.contains(extension);
  }

  bool get estPdf {
    final mime = _mimeConnu;
    return mime != null ? mime == 'application/pdf' : extension == 'pdf';
  }

  /// L'application sait-elle l'afficher elle-même, sans rien enregistrer sur
  /// le téléphone ? Les autres formats passent par une application tierce.
  bool get apercuIntegre => estPdf || estImage;

  factory ChantierDocument.fromJson(Map<String, dynamic> json) => ChantierDocument(
        id: json['id'] as String,
        chantierId: json['chantierId'] as String? ?? json['chantier_id'] as String? ?? '',
        type: DocumentTypeX.fromString(json['type'] as String?),
        nomFichier: json['nom_fichier'] as String? ?? '',
        fichierUrl: json['fichier_url'] as String? ?? '',
        mimeType: json['mime_type'] as String?,
        taille: json['taille'] as int?,
        version: json['version'] as int? ?? 1,
        archive: (json['statut'] as String?) == 'archive',
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      );

  @override
  List<Object?> get props => [id, chantierId, type, nomFichier, fichierUrl, mimeType, taille, version, archive, createdAt];
}
