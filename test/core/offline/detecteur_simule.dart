import 'dart:async';

import 'package:suivie_chantier_mobile/core/offline/detecteur_connexion.dart';

/// Détecteur simulé, partagé par les tests du socle hors ligne : permet de
/// piloter l'état réseau à la main, sans dépendre d'une vraie connexion ni
/// d'un vrai serveur `/health`.
class DetecteurSimule implements DetecteurConnexion {
  final _controleur = StreamController<EtatReseau>.broadcast();
  EtatReseau _etat;

  DetecteurSimule(this._etat);

  @override
  EtatReseau get etat => _etat;

  @override
  bool get estEnLigne => _etat == EtatReseau.enLigne;

  @override
  Stream<EtatReseau> get flux => _controleur.stream;

  /// Simule un changement d'état réseau, comme le ferait l'OS.
  void basculer(EtatReseau nouveau) {
    _etat = nouveau;
    _controleur.add(nouveau);
  }

  @override
  Future<EtatReseau> verifier() async => _etat;

  @override
  Future<void> demarrer() async {}

  @override
  Future<void> arreter() async => _controleur.close();
}
