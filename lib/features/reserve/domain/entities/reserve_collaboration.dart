import 'package:equatable/equatable.dart';

/// Auteur d'un commentaire ou destinataire d'une affectation.
///
/// Volontairement PLUS PAUVRE que `User` : le serveur ne renvoie ici que
/// `id, nom, prenom, photoProfil` (voir les `include` de
/// `reserve.service.js#listCommentaires` et
/// `reserveExtra.service.js#listAffectations`). Réutiliser `User` aurait
/// obligé à inventer un rôle, un email et un statut absents de la réponse.
class PersonneReserve extends Equatable {
  final String id;
  final String nom;
  final String prenom;
  final String? photoProfil;

  const PersonneReserve({
    required this.id,
    required this.nom,
    required this.prenom,
    this.photoProfil,
  });

  factory PersonneReserve.fromJson(Map<String, dynamic> json) => PersonneReserve(
        id: json['id'] as String,
        nom: json['nom'] as String? ?? '',
        prenom: json['prenom'] as String? ?? '',
        photoProfil: json['photoProfil'] as String?,
      );

  String get nomComplet => '$prenom $nom'.trim();

  /// Initiales pour la pastille — `?` plutôt qu'une chaîne vide, qui
  /// donnerait un rond blanc inexplicable.
  String get initiales {
    final p = prenom.trim();
    final n = nom.trim();
    if (p.isEmpty && n.isEmpty) return '?';
    if (p.isEmpty) return n.substring(0, 1).toUpperCase();
    if (n.isEmpty) return p.substring(0, 1).toUpperCase();
    return (p.substring(0, 1) + n.substring(0, 1)).toUpperCase();
  }

  @override
  List<Object?> get props => [id, nom, prenom, photoProfil];
}

/// Commentaire sur une réserve — miroir de `models/commentaire.model.js`.
class CommentaireReserve extends Equatable {
  final String id;
  final String message;
  final PersonneReserve? auteur;
  final DateTime? createdAt;

  const CommentaireReserve({
    required this.id,
    required this.message,
    this.auteur,
    this.createdAt,
  });

  factory CommentaireReserve.fromJson(Map<String, dynamic> json) => CommentaireReserve(
        id: json['id'] as String,
        message: json['message'] as String? ?? '',
        auteur: json['auteur'] != null
            ? PersonneReserve.fromJson(json['auteur'] as Map<String, dynamic>)
            : null,
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      );

  @override
  List<Object?> get props => [id, message, auteur, createdAt];
}

/// Affectation d'une réserve — miroir de `models/reserveAffectation.model.js`.
///
/// Le serveur accepte une affectation à un UTILISATEUR ou à une ENTREPRISE
/// (`affecterReserveSchema` exige l'un des deux), d'où les deux champs
/// mutuellement exclusifs plutôt qu'un destinataire unique polymorphe.
class AffectationReserve extends Equatable {
  final String id;
  final PersonneReserve? utilisateur;
  final String? entrepriseId;
  final String? entrepriseNom;
  final DateTime? dateAffectation;

  const AffectationReserve({
    required this.id,
    this.utilisateur,
    this.entrepriseId,
    this.entrepriseNom,
    this.dateAffectation,
  });

  factory AffectationReserve.fromJson(Map<String, dynamic> json) {
    final entreprise = json['entreprise'] as Map<String, dynamic>?;
    return AffectationReserve(
      id: json['id'] as String,
      utilisateur: json['utilisateur'] != null
          ? PersonneReserve.fromJson(json['utilisateur'] as Map<String, dynamic>)
          : null,
      entrepriseId: entreprise?['id'] as String?,
      entrepriseNom: entreprise?['nom'] as String?,
      dateAffectation: json['date_affectation'] != null
          ? DateTime.tryParse(json['date_affectation'] as String)
          : null,
    );
  }

  /// Libellé du destinataire, quelle que soit sa nature.
  String get libelle => utilisateur?.nomComplet ?? entrepriseNom ?? '—';

  bool get estEntreprise => utilisateur == null && entrepriseNom != null;

  @override
  List<Object?> get props => [id, utilisateur, entrepriseId, entrepriseNom, dateAffectation];
}

/// QR code d'une réserve — `GET /reserves/:id/qr`.
///
/// Le serveur renvoie une image PNG déjà encodée en data-URL
/// (`QRCode.toDataURL`) plutôt qu'une URL de fichier : rien n'est stocké côté
/// serveur, le code est régénéré à chaque demande. Le mobile n'a donc qu'à
/// décoder le base64 pour l'afficher.
class QrReserve extends Equatable {
  /// Data-URL complète : `data:image/png;base64,AAAA…`
  final String dataUrl;

  /// Adresse encodée dans le code — affichée sous l'image pour que
  /// l'utilisateur sache CE QUE le scan ouvrira.
  final String url;

  const QrReserve({required this.dataUrl, required this.url});

  factory QrReserve.fromJson(Map<String, dynamic> json) => QrReserve(
        dataUrl: json['qr'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );

  /// Partie base64 seule, prête pour `base64Decode`.
  ///
  /// Renvoie `null` si l'en-tête `data:…;base64,` manque — mieux vaut ne rien
  /// afficher qu'une exception de décodage au milieu d'un `build`.
  String? get base64 {
    const marqueur = 'base64,';
    final i = dataUrl.indexOf(marqueur);
    if (i < 0) return null;
    final donnees = dataUrl.substring(i + marqueur.length);
    return donnees.isEmpty ? null : donnees;
  }

  @override
  List<Object?> get props => [dataUrl, url];
}
