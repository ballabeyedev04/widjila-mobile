import 'package:equatable/equatable.dart';

/// Forme de l'envoi — § 13 du cahier des charges : le PDF en pièce jointe
/// pour un petit rapport, un lien sécurisé pour un rapport lourd en photos.
enum ModeEnvoiRapport { pieceJointe, lien }

extension ModeEnvoiRapportX on ModeEnvoiRapport {
  String get raw => this == ModeEnvoiRapport.lien ? 'lien' : 'piece_jointe';

  static ModeEnvoiRapport fromString(String? brut) =>
      brut == 'lien' ? ModeEnvoiRapport.lien : ModeEnvoiRapport.pieceJointe;
}

/// Un destinataire proposé par le serveur — entreprise, client ou membre du
/// chantier.
///
/// [email] peut être nul : le partenaire existe dans l'annuaire du chantier
/// mais n'a pas d'adresse. On l'affiche quand même, NOMMÉ, pour que
/// l'utilisateur sache qui ne recevra rien et puisse compléter l'annuaire.
class DestinataireRapport extends Equatable {
  final String id;
  final String nom;
  final String? email;

  /// `partenaire` (annuaire du chantier) ou `membre` (compte de la
  /// plateforme) — renseigné pour les CANDIDATS seulement.
  final String? type;

  const DestinataireRapport({required this.id, required this.nom, this.email, this.type});

  factory DestinataireRapport.fromJson(Map<String, dynamic> json) {
    final brut = json['email'] as String?;
    return DestinataireRapport(
      id: json['id']?.toString() ?? '',
      nom: json['nom']?.toString() ?? '',
      email: (brut == null || brut.trim().isEmpty) ? null : brut.trim(),
      type: json['type'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, nom, email, type];
}

/// L'e-mail tel qu'il PARTIRAIT — composé par le serveur, pas encore envoyé.
///
/// Deux appels et non un : « Widjila PROPOSE les destinataires, l'objet et le
/// message » (§ 13), et rien ne part sans validation de l'utilisateur. Cet
/// objet est ce que l'écran montre avant que l'utilisateur ne confirme.
class EnvoiRapport extends Equatable {
  final String rapportId;
  final String chantierNom;
  final String objet;
  final String message;
  final String expediteur;
  final int? nbReserves;

  /// Les ENTREPRISES concernées — destinataires principaux.
  final List<DestinataireRapport> destinataires;

  /// Les CLIENTS du chantier — en copie.
  final List<DestinataireRapport> copies;

  /// Tout ce que l'utilisateur PEUT ajouter : l'annuaire du chantier et ses
  /// membres. Le serveur refuse toute autre adresse (§ 21).
  final List<DestinataireRapport> candidats;

  /// Les partenaires sans adresse e-mail, nommés.
  final List<String> sansEmail;

  final String pieceJointeNom;

  /// Forme proposée par le serveur, d'après le poids réel du PDF.
  final ModeEnvoiRapport mode;

  /// Poids du PDF, en octets — pour dire POURQUOI le lien est conseillé.
  final int taille;

  /// Faux pour un brouillon : il n'y a encore rien à envoyer.
  final bool genere;

  const EnvoiRapport({
    required this.rapportId,
    required this.chantierNom,
    required this.objet,
    required this.message,
    required this.expediteur,
    required this.destinataires,
    required this.copies,
    required this.sansEmail,
    required this.pieceJointeNom,
    this.candidats = const [],
    this.nbReserves,
    this.mode = ModeEnvoiRapport.pieceJointe,
    this.taille = 0,
    this.genere = true,
  });

  factory EnvoiRapport.fromJson(Map<String, dynamic> json) {
    List<DestinataireRapport> liste(String cle) =>
        ((json[cle] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(DestinataireRapport.fromJson)
            .toList();

    final piece = json['pieceJointe'] as Map<String, dynamic>?;

    return EnvoiRapport(
      rapportId: json['rapportId']?.toString() ?? '',
      chantierNom: json['chantierNom']?.toString() ?? '',
      objet: json['objet']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      expediteur: json['expediteur']?.toString() ?? '',
      nbReserves: json['nbReserves'] is int ? json['nbReserves'] as int : null,
      destinataires: liste('destinataires'),
      copies: liste('copies'),
      candidats: liste('candidats'),
      sansEmail: ((json['sansEmail'] as List?) ?? const []).map((e) => e.toString()).toList(),
      pieceJointeNom: piece?['nom']?.toString() ?? 'rapport.pdf',
      mode: ModeEnvoiRapportX.fromString(json['mode'] as String?),
      taille: (json['taille'] as num?)?.toInt() ?? (piece?['taille'] as num?)?.toInt() ?? 0,
      genere: json['genere'] as bool? ?? true,
    );
  }

  /// Les adresses réellement joignables — les seules qui recevront l'e-mail.
  List<DestinataireRapport> get destinatairesJoignables =>
      destinataires.where((d) => d.email != null).toList();

  List<DestinataireRapport> get copiesJoignables => copies.where((c) => c.email != null).toList();

  /// Candidats qui ne sont PAS déjà proposés — ceux qu'on peut ajouter.
  List<DestinataireRapport> get candidatsSupplementaires {
    final dejaLa = {
      ...destinatairesJoignables.map((d) => d.email!.toLowerCase()),
      ...copiesJoignables.map((c) => c.email!.toLowerCase()),
    };
    return candidats.where((c) => c.email != null && !dejaLa.contains(c.email!.toLowerCase())).toList();
  }

  @override
  List<Object?> get props => [
        rapportId, chantierNom, objet, message, expediteur, nbReserves,
        destinataires, copies, candidats, sansEmail, pieceJointeNom, mode, taille, genere,
      ];
}

/// Ce que l'utilisateur a validé — le corps de `POST /reports/:id/send-email`.
///
/// Sans modification, seule la liste des RETRAITS part : le serveur
/// recalcule alors lui-même les destinataires. Quand l'utilisateur en ajoute
/// ou change l'objet, les listes complètes sont transmises — et le serveur
/// vérifie chaque adresse contre l'annuaire du chantier.
class DemandeEnvoiRapport extends Equatable {
  final List<String> exclure;
  final List<String>? destinataires;
  final List<String>? copies;
  final String? objet;
  final String? message;
  final ModeEnvoiRapport? mode;

  const DemandeEnvoiRapport({
    this.exclure = const [],
    this.destinataires,
    this.copies,
    this.objet,
    this.message,
    this.mode,
  });

  factory DemandeEnvoiRapport.fromJson(Map<String, dynamic> json) {
    List<String>? liste(String cle) =>
        json[cle] is List ? (json[cle] as List).map((e) => e.toString()).toList() : null;
    return DemandeEnvoiRapport(
      exclure: liste('exclure') ?? const [],
      destinataires: liste('destinataires'),
      copies: liste('copies'),
      objet: json['objet'] as String?,
      message: json['message'] as String?,
      mode: json['mode'] is String ? ModeEnvoiRapportX.fromString(json['mode'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'exclure': exclure,
        if (destinataires != null) 'destinataires': destinataires,
        if (copies != null) 'copies': copies,
        if (objet != null) 'objet': objet,
        if (message != null) 'message': message,
        if (mode != null) 'mode': mode!.raw,
      };

  @override
  List<Object?> get props => [exclure, destinataires, copies, objet, message, mode];
}

/// Issue d'un envoi : parti, ou mis en FILE D'ATTENTE faute de réseau (§ 22).
class ResultatEnvoiRapport extends Equatable {
  final String message;
  final bool enFileAttente;

  const ResultatEnvoiRapport({required this.message, this.enFileAttente = false});

  @override
  List<Object?> get props => [message, enFileAttente];
}
