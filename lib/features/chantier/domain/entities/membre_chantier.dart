import 'package:equatable/equatable.dart';

import '../../../../core/config/user_role.dart';

/// Membre affecté à un chantier — ou candidat à l'affectation.
///
/// Miroir de `GET /chantiers/:id/membres` (`ChantierService.listMembresChantier`)
/// et de `GET /chantiers/:id/membres/candidats`. L'email n'est servi qu'aux
/// rôles de gestion. Le rôle SUR LE CHANTIER vient de la table de liaison
/// (`ChantierMembre.roleChantier`), que Sequelize imbrique sous le nom du
/// modèle.
class MembreChantier extends Equatable {
  final String id;
  final String nom;
  final String prenom;
  final String? email;
  final UserRole role;
  final String? fonction;
  final String? roleChantier;

  const MembreChantier({
    required this.id,
    required this.nom,
    required this.prenom,
    this.email,
    required this.role,
    this.fonction,
    this.roleChantier,
  });

  factory MembreChantier.fromJson(Map<String, dynamic> json) {
    final liaison = json['ChantierMembre'] ?? json['chantierMembre'] ?? json['chantier_membre'];
    final brut = liaison is Map ? (liaison['roleChantier'] ?? liaison['role_chantier']) : json['roleChantier'];
    final roleChantier = brut is String && brut.trim().isNotEmpty ? brut.trim() : null;

    return MembreChantier(
      id: json['id'] as String,
      nom: json['nom'] as String? ?? '',
      prenom: json['prenom'] as String? ?? '',
      email: json['email'] as String?,
      role: UserRoleX.fromString(json['role'] as String?),
      fonction: json['fonction'] as String?,
      roleChantier: roleChantier,
    );
  }

  String get nomComplet => '$prenom $nom'.trim();

  String get initiales {
    final p = prenom.isNotEmpty ? prenom[0] : '';
    final n = nom.isNotEmpty ? nom[0] : '';
    final v = '$p$n'.toUpperCase();
    return v.isEmpty ? '?' : v;
  }

  @override
  List<Object?> get props => [id, nom, prenom, email, role, fonction, roleChantier];
}
