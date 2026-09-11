import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/exception_to_failure.dart';
import '../domain/suggestions_observation.dart';
import 'datasources/observations_remote_datasource.dart';

/// Source des observations proposées en suggestions — abstraite pour que le
/// champ se teste sans réseau ni stockage.
abstract class SourceObservations {
  /// L'historique, le plus pertinent d'abord.
  Future<List<String>> charger();
}

/// Historique des observations de l'utilisateur : le serveur (ses réserves
/// passées) complété par une copie LOCALE.
///
/// La copie locale sert deux cas que le serveur ne couvre pas :
///   - hors ligne — sous-sol, zone blanche — les suggestions restent là ;
///   - une réserve créée hors ligne n'est pas encore sur le serveur, mais son
///     observation doit déjà être proposée à la suivante.
///
/// Rangée par UTILISATEUR : sur un téléphone partagé, les formulations de l'un
/// ne sont pas proposées à l'autre.
class HistoriqueObservations implements SourceObservations {
  final ObservationsRemoteDataSource distant;
  final SharedPreferences prefs;
  final String? utilisateurId;

  static const int _max = 200;

  HistoriqueObservations({
    required this.distant,
    required this.prefs,
    required this.utilisateurId,
  });

  String get _cle => 'observations_utilisees.${utilisateurId ?? 'anonyme'}';

  List<String> _lireLocal() => prefs.getStringList(_cle) ?? const [];

  /// Copie locale d'abord (les plus récentes, dont celles pas encore
  /// synchronisées), puis ce que le serveur connaît en plus.
  @override
  Future<List<String>> charger() async {
    final local = _lireLocal();
    try {
      final serveur = await distant.observationsUtilisees();
      final vues = <String>{};
      final retenue = <String>[];
      for (final brute in [...local, ...serveur]) {
        final texte = brute.trim();
        if (texte.isEmpty || texte.length > longueurMaxSuggestion) continue;
        if (!vues.add(normaliserObservation(texte))) continue;
        retenue.add(texte);
        if (retenue.length >= _max) break;
      }
      await prefs.setStringList(_cle, retenue);
      return retenue;
    } catch (e, pile) {
      // Hors ligne ou serveur en panne : les suggestions locales suffisent.
      // Une vraie panne (5xx) reste signalée au monitoring par la conversion.
      exceptionToFailure(e, pile);
      return local;
    }
  }

  /// Retient [observation] — à appeler quand la réserve est enregistrée
  /// (en ligne ou mise en file hors ligne).
  Future<void> memoriser(String observation) async {
    await prefs.setStringList(_cle, memoriserObservation(_lireLocal(), observation, max: _max));
  }
}
