import 'package:equatable/equatable.dart';

import '../../../document/domain/entities/document.dart';

/// Pièce jointe d'une réserve — miroir de `PieceJointe`
/// (`backend/src/models/pieceJointe.model.js`), servie par
/// `GET /reserves/:id/pieces`.
class PieceJointe extends Equatable {
  final String id;
  final String reserveId;
  final String nomFichier;
  final String fichierUrl;
  final String? mimeType;
  final int? taille;
  final DateTime? createdAt;

  const PieceJointe({
    required this.id,
    required this.reserveId,
    required this.nomFichier,
    required this.fichierUrl,
    this.mimeType,
    this.taille,
    this.createdAt,
  });

  factory PieceJointe.fromJson(Map<String, dynamic> json) => PieceJointe(
        id: json['id'] as String,
        reserveId: (json['reserveId'] ?? json['reserve_id']) as String? ?? '',
        nomFichier: json['nom_fichier'] as String? ?? '',
        fichierUrl: json['fichier_url'] as String? ?? '',
        mimeType: json['mime_type'] as String?,
        taille: (json['taille'] as num?)?.toInt(),
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      );

  /// La même pièce vue comme un document : l'aperçu intégré, le
  /// téléchargement et l'ouverture dans une autre application sont ceux de
  /// la médiathèque (`features/document/presentation/widgets/actions_document.dart`).
  ChantierDocument get commeDocument => ChantierDocument(
        id: id,
        chantierId: '',
        nomFichier: nomFichier,
        fichierUrl: fichierUrl,
        mimeType: mimeType,
        taille: taille,
        createdAt: createdAt,
      );

  @override
  List<Object?> get props => [id, reserveId, nomFichier, fichierUrl, mimeType, taille, createdAt];
}
