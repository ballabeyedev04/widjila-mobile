import 'package:equatable/equatable.dart';
import '../../../../core/config/user_role.dart';

/// Utilisateur connecté — miroir exact de `formatUser()` côté backend
/// (`backend/src/utils/formatUser.js`). Le mot de passe (haché) n'est
/// JAMAIS exposé par le backend, donc jamais présent ici.
class User extends Equatable {
  final String id;
  final String? organisationId;
  final String nom;
  final String prenom;
  final String email;
  final String? telephone;
  final String? photoProfil;
  final String? fonction;
  final UserRole role;
  final String statut; // 'actif' | 'inactif' | 'en_attente_validation'
  final List<String>? permissions;
  final String? langue;
  final DateTime? dernierConnexion;
  final bool emailVerifie;
  final bool mdpTemporaire;

  const User({
    required this.id,
    this.organisationId,
    required this.nom,
    required this.prenom,
    required this.email,
    this.telephone,
    this.photoProfil,
    this.fonction,
    required this.role,
    required this.statut,
    this.permissions,
    this.langue,
    this.dernierConnexion,
    this.emailVerifie = false,
    this.mdpTemporaire = false,
  });

  String get nomComplet => '$prenom $nom'.trim();

  String get initiales {
    final p = prenom.isNotEmpty ? prenom[0] : '';
    final n = nom.isNotEmpty ? nom[0] : '';
    final v = '$p$n'.toUpperCase();
    return v.isEmpty ? '?' : v;
  }

  bool get estActif => statut == 'actif';

  User copyWith({
    String? nom,
    String? prenom,
    String? email,
    String? telephone,
    String? photoProfil,
    String? fonction,
    String? langue,
  }) {
    return User(
      id: id,
      organisationId: organisationId,
      nom: nom ?? this.nom,
      prenom: prenom ?? this.prenom,
      email: email ?? this.email,
      telephone: telephone ?? this.telephone,
      photoProfil: photoProfil ?? this.photoProfil,
      fonction: fonction ?? this.fonction,
      role: role,
      statut: statut,
      permissions: permissions,
      langue: langue ?? this.langue,
      dernierConnexion: dernierConnexion,
      emailVerifie: emailVerifie,
      mdpTemporaire: mdpTemporaire,
    );
  }

  @override
  List<Object?> get props => [
        id,
        organisationId,
        nom,
        prenom,
        email,
        telephone,
        photoProfil,
        fonction,
        role,
        statut,
        permissions,
        langue,
        dernierConnexion,
        emailVerifie,
        mdpTemporaire,
      ];
}
