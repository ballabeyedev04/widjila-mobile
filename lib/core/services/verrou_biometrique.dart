import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Déverrouillage biométrique de l'ouverture de l'application.
///
/// Sur un chantier, on ressaisit un mot de passe complexe plusieurs fois par
/// jour, souvent avec des gants — c'est la première raison pour laquelle les
/// utilisateurs finissent par choisir un mot de passe faible.
///
/// Ce verrou protège l'ACCÈS À L'APPLICATION, pas la session : le jeton reste
/// en stockage sécurisé et sa validité ne dépend pas d'ici. Quelqu'un qui
/// extrairait le stockage de l'appareil ne serait pas arrêté par ce réglage —
/// il n'a jamais prétendu à cela. Il empêche un collègue de consulter le
/// téléphone posé sur une table.
class VerrouBiometrique extends ChangeNotifier {
  final SharedPreferences _prefs;
  final LocalAuthentication _auth;

  VerrouBiometrique({required SharedPreferences prefs, LocalAuthentication? auth})
      : _prefs = prefs,
        _auth = auth ?? LocalAuthentication();

  static const _kCle = 'verrou_biometrique_actif';
  static const _kCleProposition = 'verrou_biometrique_propose';

  /// Désactivé par défaut : un verrou qu'on n'a pas demandé et qu'on ne sait
  /// pas retirer transformerait une application de travail en piège.
  bool get actif => _prefs.getBool(_kCle) ?? false;

  /// L'offre d'activation a-t-elle déjà été présentée ?
  ///
  /// Le réglage vit dans les paramètres, où personne ne va le chercher : on
  /// le propose donc une fois, à l'arrivée dans l'application. UNE fois —
  /// reposer la question à chaque ouverture à quelqu'un qui a répondu « plus
  /// tard » transformerait une commodité en harcèlement, et la réponse
  /// deviendrait un réflexe de rejet.
  bool get propositionFaite => _prefs.getBool(_kCleProposition) ?? false;

  Future<void> marquerPropositionFaite() async {
    await _prefs.setBool(_kCleProposition, true);
  }

  /// L'appareil propose-t-il une biométrie ENREGISTRÉE ?
  ///
  /// `canCheckBiometrics` seul ne suffit pas : il répond vrai sur un appareil
  /// doté d'un capteur mais sans empreinte configurée, et le réglage
  /// deviendrait alors impossible à honorer.
  Future<bool> get disponible async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final inscrites = await _auth.getAvailableBiometrics();
      return inscrites.isNotEmpty;
    } catch (_) {
      // Plateforme sans plugin (tests, bureau) : on annonce simplement
      // l'indisponibilité plutôt que de laisser remonter l'exception.
      return false;
    }
  }

  /// Active ou désactive le verrou.
  ///
  /// L'ACTIVATION exige une authentification réussie : sans cela, quelqu'un
  /// qui trouve le téléphone déverrouillé pourrait poser un verrou que le
  /// propriétaire ne saurait pas franchir. La DÉSACTIVATION l'exige aussi,
  /// pour la raison inverse — sinon le verrou se contourne en deux taps.
  Future<bool> definirActif(bool valeur, {required String motif}) async {
    if (valeur == actif) return true;
    final ok = await authentifier(motif: motif);
    if (!ok) return false;

    await _prefs.setBool(_kCle, valeur);
    notifyListeners();
    return true;
  }

  /// Demande la biométrie. Renvoie `false` sur refus, échec ou absence de
  /// capteur — jamais d'exception.
  Future<bool> authentifier({required String motif}) async {
    try {
      return await _auth.authenticate(
        localizedReason: motif,
        options: const AuthenticationOptions(
          // `biometricOnly: false` : le code de déverrouillage de l'appareil
          // reste accepté en repli. L'exiger biométrique enfermerait dehors
          // quiconque a un doigt blessé ou mouillé — courant sur un chantier.
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
