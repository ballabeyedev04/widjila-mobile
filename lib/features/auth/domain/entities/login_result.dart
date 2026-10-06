import 'package:equatable/equatable.dart';
import 'user.dart';

/// Résultat d'un login — reflète la réponse backend qui peut soit
/// authentifier directement, soit exiger un second facteur (MFA).
/// Voir `backend/src/modules/auth/controller/auth.controller.js#login`.
class LoginResult extends Equatable {
  final bool mfaRequise;
  final User utilisateur;

  /// `true` quand la session a été ouverte SANS serveur, sur la foi du
  /// vérificateur local (voir `VerificateurHorsLigne`) : aucun jeton n'existe,
  /// rien ne peut partir vers le serveur avant une réauthentification en ligne.
  final bool horsLigne;

  const LoginResult({required this.mfaRequise, required this.utilisateur, this.horsLigne = false});

  @override
  List<Object?> get props => [mfaRequise, utilisateur, horsLigne];
}
