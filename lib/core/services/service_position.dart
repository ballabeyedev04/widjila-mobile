import 'package:geolocator/geolocator.dart';

/// Pourquoi la position n'a pas pu être obtenue.
///
/// Chaque cas appelle un message DIFFÉRENT : « activez le GPS » et « autorisez
/// l'application » demandent deux gestes opposés, et un message générique
/// laisserait l'utilisateur chercher dans les mauvais réglages.
enum EchecPosition {
  /// Le service de localisation de l'appareil est éteint.
  serviceDesactive,

  /// L'utilisateur a refusé l'autorisation, mais on peut redemander.
  refusee,

  /// Refus DÉFINITIF : plus aucune demande n'est possible, il faut passer par
  /// les réglages du système.
  refuseeDefinitivement,

  /// Le calcul a échoué ou expiré — sous-sol, parking couvert, ciel bouché.
  indisponible,
}

/// Une position obtenue, ou la raison de son absence.
class ResultatPosition {
  final double? latitude;
  final double? longitude;
  final EchecPosition? echec;

  const ResultatPosition.succes(this.latitude, this.longitude) : echec = null;
  const ResultatPosition.echec(this.echec) : latitude = null, longitude = null;

  bool get reussi => echec == null;
}

/// Accès à la position de l'appareil.
///
/// ── Pourquoi une enveloppe autour du plugin ───────────────────────────────
/// Le formulaire de demande n'a pas à connaître `geolocator`, ses énumérations
/// de permission ni ses exceptions. Il pose une question — « où sommes-nous ? »
/// — et reçoit soit deux nombres, soit une raison exploitable. Le jour où le
/// plugin change, un seul fichier bouge.
///
/// C'est aussi ce qui rend le formulaire testable : on remplace cette classe,
/// pas la pile de géolocalisation.
class ServicePosition {
  const ServicePosition();

  /// Délai au-delà duquel on renonce.
  ///
  /// Un chantier est souvent un endroit où le ciel est bouché — grue, dalle,
  /// sous-sol. Sans plafond, le bouton resterait à tourner indéfiniment ; avec,
  /// l'utilisateur récupère la main et saisit à la main.
  static const _delai = Duration(seconds: 12);

  Future<ResultatPosition> obtenir() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const ResultatPosition.echec(EchecPosition.serviceDesactive);
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return const ResultatPosition.echec(EchecPosition.refuseeDefinitivement);
    }
    if (permission == LocationPermission.denied) {
      return const ResultatPosition.echec(EchecPosition.refusee);
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          // `high` et non `best` : `best` peut attendre plusieurs dizaines de
          // secondes pour gagner quelques mètres, sans intérêt pour situer un
          // chantier.
          accuracy: LocationAccuracy.high,
          timeLimit: _delai,
        ),
      );
      return ResultatPosition.succes(position.latitude, position.longitude);
    } catch (_) {
      // Délai dépassé, capteur indisponible, position nulle : tous ces cas
      // appellent la même réponse — saisir à la main.
      return const ResultatPosition.echec(EchecPosition.indisponible);
    }
  }
}
