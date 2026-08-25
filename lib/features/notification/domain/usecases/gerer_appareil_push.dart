import 'dart:io' show Platform;

import 'package:dartz/dartz.dart';

import '../../../../core/errors/failure.dart';
import '../repositories/notification_repository.dart';

/// Déclare ou retire l'appareil courant de la liste des destinataires push.
///
/// Deux moments dans la vie d'une session :
///   - à la connexion et à chaque rotation du jeton par Firebase (qui survient
///     sans action de l'utilisateur) → [enregistrer] ;
///   - à la déconnexion → [oublier], faute de quoi l'appareil continuerait de
///     recevoir les alertes du compte précédent. Sur un téléphone partagé ou
///     revendu, c'est une fuite d'information métier.
class GererAppareilPush {
  final NotificationRepository repository;
  GererAppareilPush(this.repository);

  /// La plateforme est déduite ici plutôt que fournie par l'appelant : elle ne
  /// dépend que de l'appareil, et le serveur ne l'accepte que parmi
  /// `android`, `ios` et `web`.
  static String get _plateforme {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'web';
  }

  Future<Either<Failure, void>> enregistrer(String jeton) =>
      repository.enregistrerAppareil(jeton, _plateforme);

  Future<Either<Failure, void>> oublier(String jeton) => repository.oublierAppareil(jeton);
}
