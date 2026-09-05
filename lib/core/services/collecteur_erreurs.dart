import 'package:flutter/foundation.dart';

/// Destination finale d'une erreur — Crashlytics en production.
///
/// Une interface, et non un appel direct à `FirebaseCrashlytics.instance` :
/// c'est ce qui rend [CollecteurErreurs] vérifiable sans Firebase, et ce qui
/// permet de RETARDER l'envoi sans rien changer aux appelants.
abstract class PuitsErreurs {
  /// Erreur du framework Flutter — construction, mise en page, rendu.
  ///
  /// Distincte de [erreur] : Crashlytics en tire un rapport plus riche
  /// (bibliothèque fautive, contexte de la construction, arbre de widgets).
  void erreurFlutter(FlutterErrorDetails details);

  /// Erreur Dart hors framework : `Future` orpheline, rappel de `Timer`,
  /// erreur de plateforme.
  void erreur(Object erreur, StackTrace? pile);
}

/// Retient les erreurs survenues AVANT que Crashlytics soit prêt, puis les lui
/// remet.
///
/// ## Le problème
///
/// `Firebase.initializeApp()` était attendu avant `runApp` : l'écran restait
/// noir le temps de l'initialisation, à chaque démarrage, pour tous les
/// utilisateurs — afin de couvrir une fenêtre de quelques centaines de
/// millisecondes pendant laquelle il ne se passe presque rien.
///
/// L'alternative évidente — initialiser après `runApp` — échange ce délai
/// contre un angle mort : les erreurs de cette même fenêtre partiraient nulle
/// part. Or c'est précisément la fenêtre où une configuration absente, une
/// migration de base ratée ou un jeton illisible se manifestent. Perdre CES
/// crashs-là serait perdre les plus utiles.
///
/// ## Ce que fait ce collecteur
///
/// Il supprime le choix. Les gestionnaires d'erreurs sont posés
/// SYNCHRONEMENT, avant la première image ; ils écrivent ici. Firebase
/// s'initialise pendant que l'application s'affiche, et [brancher] rejoue
/// alors tout ce qui a été retenu, dans l'ordre.
///
/// Le démarrage ne coûte plus l'initialisation de Firebase, et aucun crash
/// n'est perdu.
class CollecteurErreurs {
  /// Plafond du tampon.
  ///
  /// Une erreur de construction se répète à chaque image : sans plafond, un
  /// écran cassé au démarrage remplirait la mémoire en quelques secondes —
  /// on transformerait un bug d'affichage en panne sèche. Vingt suffisent
  /// largement à comprendre ce qui s'est passé ; au-delà, ce sont les mêmes.
  final int tamponMax;

  CollecteurErreurs({this.tamponMax = 20});

  final List<void Function(PuitsErreurs)> _tampon = [];
  PuitsErreurs? _puits;
  bool _abandonne = false;

  /// Nombre d'erreurs en attente — pour les tests et le diagnostic.
  @visibleForTesting
  int get enAttente => _tampon.length;

  bool get estBranche => _puits != null;

  /// Envoie maintenant si la destination est prête, retient sinon.
  void differer(void Function(PuitsErreurs) envoi) {
    if (_abandonne) return;

    final puits = _puits;
    if (puits != null) {
      envoi(puits);
      return;
    }

    if (_tampon.length < tamponMax) _tampon.add(envoi);
  }

  /// Branche la destination et rejoue l'arriéré, dans l'ordre d'arrivée.
  void brancher(PuitsErreurs puits) {
    if (_abandonne) return;
    _puits = puits;
    for (final envoi in _tampon) {
      envoi(puits);
    }
    _tampon.clear();
  }

  /// Renonce définitivement : Firebase n'est pas configuré sur cette
  /// installation.
  ///
  /// Le tampon est vidé — le garder ne ferait que retenir de la mémoire pour
  /// des erreurs qui ne partiront jamais. Les erreurs suivantes sont ignorées
  /// ici ; elles restent affichées en console par `FlutterError.presentError`,
  /// posé en amont.
  void abandonner() {
    _abandonne = true;
    _tampon.clear();
  }
}
