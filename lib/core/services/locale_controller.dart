import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Langue courante de l'application — `ValueNotifier` consommé par
/// `MaterialApp.router` (voir main.dart) pour redessiner TOUTE l'app dès
/// qu'elle change, sans redémarrage.
///
/// Deux sources, dans cet ordre de priorité au démarrage :
///  1. la préférence choisie localement (persistée ici), si elle existe ;
///  2. `fr` par défaut — l'app a toujours été française jusqu'ici.
///
/// La langue du COMPTE (`utilisateur.langue`, renvoyée par `/account/me`)
/// n'écrase la préférence locale qu'à la connexion, via
/// [synchroniserDepuisCompte] — voir `AuthBloc`. Elle ne fait jamais autorité
/// à elle seule : un choix fait sur l'écran Paramètres doit survivre même si
/// le compte n'a pas encore été mis à jour côté serveur (ex: hors ligne).
class LocaleController extends ValueNotifier<Locale> {
  final SharedPreferences _prefs;

  LocaleController({required SharedPreferences prefs})
      : _prefs = prefs,
        super(_lireInitiale(prefs));

  static const _kCleLangue = 'sc_langue';

  /// Codes acceptés par le backend (`ROLE`... non, ici `langue` — voir
  /// `backend/src/modules/account/validation/account.validation.js`) et par
  /// les 4 fichiers ARB (`lib/l10n/app_*.arb`). Toute valeur hors de cette
  /// liste retombe sur le français plutôt que de planter au démarrage.
  static const languesSupportees = ['fr', 'en', 'de', 'es'];

  static Locale _lireInitiale(SharedPreferences prefs) {
    final code = prefs.getString(_kCleLangue);
    return Locale(languesSupportees.contains(code) ? code! : 'fr');
  }

  /// Change la langue IMMÉDIATEMENT (toute l'app se redessine dès ce
  /// `notifyListeners` implicite de `ValueNotifier.value=`) et la persiste
  /// localement. N'appelle PAS le backend — l'écran Paramètres s'en charge en
  /// plus, pour que le choix suive l'utilisateur sur ses autres appareils.
  Future<void> changer(String code) async {
    if (!languesSupportees.contains(code) || code == value.languageCode) return;
    value = Locale(code);
    await _prefs.setString(_kCleLangue, code);
  }

  /// Aligne la langue de l'app sur celle du compte — appelé à la connexion
  /// (voir `AuthBloc`). Un code absent, invalide ou déjà appliqué ne fait
  /// rien : ça évite d'écraser un choix local plus récent que ce que le
  /// serveur a mémorisé (ex : changé hors ligne, pas encore synchronisé).
  Future<void> synchroniserDepuisCompte(String? langueCompte) async {
    if (langueCompte == null || !languesSupportees.contains(langueCompte)) return;
    if (langueCompte == value.languageCode) return;
    await changer(langueCompte);
  }
}
