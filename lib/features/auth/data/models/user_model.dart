import '../../../../core/config/user_role.dart';
import '../../domain/entities/user.dart';

/// Désérialisation de l'objet `utilisateur` — miroir exact de
/// `backend/src/utils/formatUser.js`. Toute nouvelle clé ajoutée côté
/// backend doit être répercutée ici.
class UserModel extends User {
  const UserModel({
    required super.id,
    super.organisationId,
    required super.nom,
    required super.prenom,
    required super.email,
    super.telephone,
    super.photoProfil,
    super.fonction,
    required super.role,
    required super.statut,
    super.permissions,
    super.langue,
    super.dernierConnexion,
    super.emailVerifie,
    super.mdpTemporaire,
    super.mfaActive,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      organisationId: json['organisationId'] as String?,
      nom: json['nom'] as String? ?? '',
      prenom: json['prenom'] as String? ?? '',
      email: json['email'] as String? ?? '',
      telephone: json['telephone'] as String?,
      photoProfil: json['photoProfil'] as String?,
      fonction: json['fonction'] as String?,
      role: UserRoleX.fromString(json['role'] as String?),
      statut: json['statut'] as String? ?? 'actif',
      permissions: (json['permissions'] as List?)?.map((e) => e.toString()).toList(),
      langue: json['langue'] as String?,
      dernierConnexion: json['dernierConnexion'] != null
          ? DateTime.tryParse(json['dernierConnexion'] as String)
          : null,
      emailVerifie: json['email_verifie'] as bool? ?? false,
      mdpTemporaire: json['mdp_temporaire'] as bool? ?? false,
      mfaActive: json['mfaActive'] as bool? ?? false,
    );
  }

  /// Pour le cache local (stockage sécurisé) — utilisé au démarrage avant
  /// que `restaurerSession()` ait pu recontacter le backend.
  Map<String, dynamic> toJson() => {
        'id': id,
        'organisationId': organisationId,
        'nom': nom,
        'prenom': prenom,
        'email': email,
        'telephone': telephone,
        'photoProfil': photoProfil,
        'fonction': fonction,
        'role': role.raw,
        'statut': statut,
        'permissions': permissions,
        'langue': langue,
        'dernierConnexion': dernierConnexion?.toIso8601String(),
        'email_verifie': emailVerifie,
        'mdp_temporaire': mdpTemporaire,
        'mfaActive': mfaActive,
      };
}
