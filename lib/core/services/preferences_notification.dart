import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Familles d'alertes que l'utilisateur peut couper séparément.
///
/// Les valeurs correspondent au PRÉFIXE des types émis par le back
/// (`reserve.affectee`, `reserve.statut`, `chantier.affectation`,
/// `inspection.convocation`) : filtrer sur le préfixe plutôt que sur la liste
/// exacte des types permet au serveur d'en ajouter — `reserve.commentaire`,
/// demain — sans que le mobile les laisse passer par inadvertance.
enum FamilleAlerte {
  reserve('reserve'),
  chantier('chantier'),
  inspection('inspection');

  const FamilleAlerte(this.prefixe);
  final String prefixe;
}

/// Préférences d'affichage des notifications, stockées LOCALEMENT.
///
/// Purement côté appareil, et c'est assumé : le backend n'expose aucune route
/// de préférences (`notification.route.js` ne propose que la lecture). Ce
/// réglage ne demande donc pas au serveur de cesser d'envoyer — il décide de
/// ce que CET appareil affiche.
///
/// Conséquence à connaître : les alertes filtrées restent visibles dans
/// l'écran Notifications, qui lit la liste du serveur. C'est le comportement
/// voulu — couper les interruptions ne doit pas faire disparaître
/// l'information, seulement cesser de la pousser.
class PreferencesNotification extends ChangeNotifier {
  final SharedPreferences _prefs;
  PreferencesNotification({required SharedPreferences prefs}) : _prefs = prefs;

  static const _kCleGlobale = 'notif_actives';
  static String _cleFamille(FamilleAlerte f) => 'notif_famille_${f.prefixe}';

  /// Interrupteur général. Par défaut ACTIF : une application de suivi de
  /// chantier qui n'alerte de rien tant qu'on n'a pas trouvé le réglage
  /// n'aurait pas beaucoup d'intérêt.
  bool get toutesActives => _prefs.getBool(_kCleGlobale) ?? true;

  bool familleActive(FamilleAlerte famille) => _prefs.getBool(_cleFamille(famille)) ?? true;

  Future<void> definirToutesActives(bool valeur) async {
    await _prefs.setBool(_kCleGlobale, valeur);
    notifyListeners();
  }

  Future<void> definirFamille(FamilleAlerte famille, bool valeur) async {
    await _prefs.setBool(_cleFamille(famille), valeur);
    notifyListeners();
  }

  /// Faut-il afficher une alerte de ce type ?
  ///
  /// Un type INCONNU passe : le serveur peut en introduire de nouveaux, et
  /// les taire par défaut priverait silencieusement l'utilisateur d'une
  /// information qu'il n'a jamais refusée.
  bool doitAfficher(String type) {
    if (!toutesActives) return false;

    final normalise = type.trim().toLowerCase();
    for (final famille in FamilleAlerte.values) {
      if (normalise.startsWith(famille.prefixe)) return familleActive(famille);
    }
    return true;
  }
}
