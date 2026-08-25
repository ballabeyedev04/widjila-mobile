import 'package:equatable/equatable.dart';
import 'user.dart';

/// Résultat d'un login — reflète la réponse backend qui peut soit
/// authentifier directement, soit exiger un second facteur (MFA).
/// Voir `backend/src/modules/auth/controller/auth.controller.js#login`.
class LoginResult extends Equatable {
  final bool mfaRequise;
  final User utilisateur;

  const LoginResult({required this.mfaRequise, required this.utilisateur});

  @override
  List<Object?> get props => [mfaRequise, utilisateur];
}
