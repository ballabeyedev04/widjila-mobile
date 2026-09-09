import 'package:equatable/equatable.dart';

/// Un destinataire proposé par le serveur — entreprise ou client du chantier.
///
/// [email] peut être nul : le partenaire existe dans l'annuaire du chantier
/// mais n'a pas d'adresse. On l'affiche quand même, NOMMÉ, pour que
/// l'utilisateur sache qui ne recevra rien et puisse compléter l'annuaire.
class DestinataireRapport extends Equatable {
  final String id;
  final String nom;
  final String? email;

  const DestinataireRapport({required this.id, required this.nom, this.email});

  factory DestinataireRapport.fromJson(Map<String, dynamic> json) {
    final brut = json['email'] as String?;
    return DestinataireRapport(
      id: json['id']?.toString() ?? '',
      nom: json['nom']?.toString() ?? '',
      email: (brut == null || brut.trim().isEmpty) ? null : brut.trim(),
    );
  }

  @override
  List<Object?> get props => [id, nom, email];
}

/// L'e-mail tel qu'il PARTIRAIT — composé par le serveur, pas encore envoyé.
///
/// Deux appels et non un : le client a demandé que rien ne parte « sans
/// validation de l'utilisateur ». Cet objet est ce que l'écran montre avant
/// que l'utilisateur ne confirme.
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

  /// Les partenaires sans adresse e-mail, nommés. À afficher : ils ne
  /// recevront rien, et c'est réparable depuis l'annuaire du chantier.
  final List<String> sansEmail;

  final String pieceJointeNom;

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
    this.nbReserves,
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
      sansEmail: ((json['sansEmail'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      pieceJointeNom: piece?['nom']?.toString() ?? 'rapport.pdf',
    );
  }

  /// Les adresses réellement joignables — les seules qui recevront l'e-mail.
  List<DestinataireRapport> get destinatairesJoignables =>
      destinataires.where((d) => d.email != null).toList();

  List<DestinataireRapport> get copiesJoignables =>
      copies.where((c) => c.email != null).toList();

  @override
  List<Object?> get props => [
        rapportId, chantierNom, objet, message, expediteur, nbReserves,
        destinataires, copies, sansEmail, pieceJointeNom,
      ];
}
