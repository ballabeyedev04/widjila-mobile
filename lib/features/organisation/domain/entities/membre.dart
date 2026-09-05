import 'package:equatable/equatable.dart';

import '../../../../core/config/user_role.dart';

/// Membre de l'organisation — miroir de `SAFE_USER_ATTRIBUTES`
/// (`backend/src/utils/formatUser.js`), tel que renvoyé par
/// `GET /organisation/membres` et `POST /organisation/membres`.
class Membre extends Equatable {
  final String id;
  final String nom;
  final String prenom;
  final String email;
  final String? telephone;
  final String? photoProfil;
  final String? fonction;
  final UserRole role;
  final String statut; // 'actif' | 'inactif' | 'en_attente_validation'
  final DateTime? dernierConnexion;

  /// `true` si le mot de passe a été généré automatiquement à la création
  /// (aucun fourni) — le compte doit le changer à la première connexion.
  final bool mdpTemporaire;

  const Membre({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.email,
    this.telephone,
    this.photoProfil,
    this.fonction,
    required this.role,
    this.statut = 'actif',
    this.dernierConnexion,
    this.mdpTemporaire = false,
  });

  factory Membre.fromJson(Map<String, dynamic> json) {
    return Membre(
      id: json['id'] as String,
      nom: json['nom'] as String? ?? '',
      prenom: json['prenom'] as String? ?? '',
      email: json['email'] as String? ?? '',
      telephone: json['telephone'] as String?,
      photoProfil: json['photoProfil'] as String?,
      fonction: json['fonction'] as String?,
      role: UserRoleX.fromString(json['role'] as String?),
      statut: json['statut'] as String? ?? 'actif',
      dernierConnexion: json['dernierConnexion'] != null
          ? DateTime.tryParse(json['dernierConnexion'] as String)
          : null,
      mdpTemporaire: json['mdp_temporaire'] as bool? ?? false,
    );
  }

  String get nomComplet => '$prenom $nom'.trim();

  String get initiales {
    final p = prenom.isNotEmpty ? prenom[0] : '';
    final n = nom.isNotEmpty ? nom[0] : '';
    final v = '$p$n'.toUpperCase();
    return v.isEmpty ? '?' : v;
  }

  bool get estActif => statut == 'actif';
  bool get enAttenteValidation => statut == 'en_attente_validation';

  @override
  List<Object?> get props =>
      [id, nom, prenom, email, telephone, photoProfil, fonction, role, statut, dernierConnexion, mdpTemporaire];
}

/// Résultat de la création d'un membre.
///
/// Le serveur envoie désormais ses identifiants au nouveau membre par
/// courriel, à son adresse. [emailEnvoye] dit si ce message est bien parti.
///
/// [motDePasseTemporaire] reste renvoyé — c'est l'UNIQUE occasion de le lire,
/// le serveur ne le conserve qu'en empreinte. L'écran ne l'affiche que si
/// l'envoi a échoué : le taire alors ferait perdre le compte, l'afficher
/// systématiquement le ferait circuler pour rien.
class AjouterMembreResult extends Equatable {
  final Membre membre;
  final String? motDePasseTemporaire;

  /// `false` aussi quand le serveur n'a pas de fournisseur d'envoi configuré
  /// (développement local) : dans ce cas rien n'est parti, et il faut bien
  /// que quelqu'un transmette le mot de passe.
  final bool emailEnvoye;

  const AjouterMembreResult({
    required this.membre,
    this.motDePasseTemporaire,
    this.emailEnvoye = false,
  });

  @override
  List<Object?> get props => [membre, motDePasseTemporaire, emailEnvoye];
}
