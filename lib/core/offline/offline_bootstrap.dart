import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../injection_container.dart';
import 'bandeau_connexion.dart';
import 'detecteur_connexion.dart';
import 'synchronisation_service.dart';

/// Démarre le mode hors ligne pour toute l'application, et pose le bandeau
/// d'état réseau au-dessus de chaque écran.
///
/// Comme [PushBootstrap] (voir `core/services/push_bootstrap.dart`), placé
/// dans le `builder` de `MaterialApp.router` : le contexte a donc accès à
/// [AuthBloc], nécessaire pour vider les données locales à la déconnexion.
///
/// ## Ce que ce widget garantit
///
///  - la synchronisation démarre au lancement de l'app et repart SEULE à
///    chaque retour de connexion — aucune action de l'utilisateur, nulle
///    part (voir `SynchronisationService`) ;
///  - le bandeau rouge/orange/vert (voir `BandeauConnexion`) est visible sur
///    TOUTE page, y compris les écrans plein écran hors de la coquille de
///    navigation, puisqu'il est posé ICI, au-dessus de tout ;
///  - à la déconnexion du compte, les données hors ligne sont purgées — un
///    appareil de chantier partagé ne doit jamais laisser le compte suivant
///    lire les données du précédent.
class OfflineBootstrap extends StatefulWidget {
  final Widget child;
  const OfflineBootstrap({super.key, required this.child});

  @override
  State<OfflineBootstrap> createState() => _OfflineBootstrapState();
}

class _OfflineBootstrapState extends State<OfflineBootstrap> with WidgetsBindingObserver {
  final DetecteurConnexion _detecteur = sl<DetecteurConnexion>();
  final SynchronisationService _synchro = sl<SynchronisationService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _demarrer();
  }

  Future<void> _demarrer() async {
    // Le détecteur d'abord : `SynchronisationService.demarrer()` lit son état
    // COURANT dès son propre appel (pas seulement les changements à venir) —
    // il doit donc déjà avoir fait sa première vérification.
    await _detecteur.demarrer();
    await _synchro.demarrer();
    // Purge du cache ancien, hors du chemin critique du démarrage : ni
    // attendue, ni capable de retarder le premier écran.
    unawaited(_synchro.entretien());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _synchro.arreter();
    _detecteur.arreter();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // L'utilisateur a pu retrouver du réseau pendant que l'app était en
    // arrière-plan (sortie du sous-sol, écran verrouillé puis rouvert) sans
    // qu'aucun événement système ne le signale pendant que l'app dormait.
    if (state == AppLifecycleState.resumed) {
      _synchro.auRetourAuPremierPlan();
    }
  }

  @override
  Widget build(BuildContext context) {
    // La purge des données locales n'est PLUS déclenchée ici.
    //
    // Elle l'était sur la transition `estAuthentifie` → false, ce qui posait
    // deux problèmes que ce widget ne pouvait pas résoudre :
    //
    //  1. l'appel n'était pas attendu (`_base.viderTout()` sans `await` dans
    //     un listener synchrone) : un process tué juste après la déconnexion
    //     laissait les données du compte précédent intactes ;
    //  2. une simple EXPIRATION de session déclenchait la même purge et
    //     détruisait le travail hors ligne que son auteur venait récupérer.
    //
    // Le ménage vit désormais dans `SessionLocale`, appelé par
    // `AuthRepositoryImpl` : purge attendue à la déconnexion volontaire, et
    // surtout contrôle du propriétaire à CHAQUE connexion — seul point de
    // passage qu'un arrêt brutal ne peut pas contourner.
    return BandeauConnexion(service: _synchro, child: widget.child);
  }
}
