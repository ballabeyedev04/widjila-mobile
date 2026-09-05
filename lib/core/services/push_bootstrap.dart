import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/bloc/auth_state.dart';
import '../../features/notification/domain/usecases/gerer_appareil_push.dart';
import '../../injection_container.dart';
import 'destination_notification.dart';
import 'preferences_notification.dart';
import 'push_service.dart';

/// Branche les notifications push sur l'application.
///
/// Comme [OfflineBootstrap] (voir `core/offline/offline_bootstrap.dart`),
/// placé dans le `builder` de `MaterialApp.router` : c'est le seul point où le
/// contexte a accès À LA FOIS à [AuthBloc] (fourni au-dessus) et au `GoRouter`
/// (fourni par `routerConfig`), les deux dont ce widget a besoin — l'un pour
/// savoir qui est connecté, l'autre pour naviguer au tap d'une alerte.
///
/// ## Ce que ce widget garantit
///
///  - le jeton d'appareil est déclaré au serveur dès qu'un utilisateur
///    authentifié ET un jeton sont tous deux disponibles, DANS N'IMPORTE QUEL
///    ORDRE d'arrivée — Firebase peut répondre avant comme après la connexion ;
///  - il est redéclaré à chaque rotation du jeton par Firebase, qui survient
///    sans action de l'utilisateur ;
///  - il est retiré à la déconnexion : sans cela, l'appareil continuerait de
///    recevoir les alertes du compte précédent. Sur un téléphone de chantier
///    partagé, c'est une fuite d'information métier ;
///  - le tap sur une alerte ouvre l'écran VISÉ (voir
///    [DestinationNotification]), pas une liste où il faudrait le retrouver.
class PushBootstrap extends StatefulWidget {
  final Widget child;
  const PushBootstrap({super.key, required this.child});

  @override
  State<PushBootstrap> createState() => _PushBootstrapState();
}

class _PushBootstrapState extends State<PushBootstrap> {
  final GererAppareilPush _gererAppareil = sl<GererAppareilPush>();

  /// Dernier jeton connu de Firebase. Conservé parce qu'il peut arriver AVANT
  /// que l'utilisateur soit authentifié — il faut alors l'enregistrer plus
  /// tard, à la connexion.
  String? _jeton;

  /// Évite de redéclarer le même jeton à chaque reconstruction du widget.
  bool _enregistre = false;

  /// Écran visé par une alerte touchée avant que la session soit résolue.
  ///
  /// Au lancement DEPUIS une alerte, `getInitialMessage()` répond bien avant
  /// `AuthBloc` : la vérification de session s'impose un plancher de 1200 ms
  /// (`_dureeMinSplash`). Naviguer tout de suite ne mène nulle part — la
  /// redirection du routeur ramène sur `/splash` tant que le statut est
  /// `inconnu`, puis sur le tableau de bord une fois la session restaurée.
  /// La destination est donc mise de côté, et rejouée à l'ouverture de session.
  String? _destinationEnAttente;

  @override
  void initState() {
    super.initState();
    PushService.instance
      ..onJeton = _surJeton
      ..onOuverture = _surOuverture
      // Le filtre est relu à CHAQUE alerte (et non capturé une fois) : un
      // changement de réglage prend effet immédiatement, sans redémarrage.
      ..filtreAffichage = sl<PreferencesNotification>().doitAfficher;
    // Ne bloque jamais le premier rendu : sans Firebase configuré,
    // l'initialisation se termine simplement en no-op (voir push_service.dart).
    PushService.instance.initialiser();
  }

  void _surJeton(String jeton) {
    _jeton = jeton;
    _enregistre = false;
    _synchroniser();
  }

  /// Ouvre l'écran VISÉ par l'alerte plutôt que la liste des notifications.
  ///
  /// Le back joint déjà le contexte (`reserveId`, `chantierId`…) dans le bloc
  /// `data` du message FCM ; il n'était jamais lu, et l'utilisateur devait
  /// retrouver à la main la réserve dont on venait de l'avertir. La résolution
  /// vit dans [DestinationNotification], testable sans Firebase.
  ///
  /// `go` et non `push` : on arrive de l'extérieur de l'application, il n'y a
  /// pas de pile à empiler — et un `push` répété laisserait autant d'écrans
  /// superposés que d'alertes ouvertes.
  void _surOuverture(Map<String, dynamic> donnees) {
    if (!mounted) return;
    final destination = DestinationNotification.resoudre(donnees);

    // Session pas encore établie : la redirection du routeur écraserait cette
    // navigation. On garde la destination pour l'ouverture de session.
    if (!context.read<AuthBloc>().state.estAuthentifie) {
      _destinationEnAttente = destination;
      return;
    }

    GoRouter.of(context).go(destination);
  }

  /// Rejoue la destination mise de côté, une fois la session ouverte.
  ///
  /// Après la frame : la bascule d'authentification déclenche elle-même une
  /// redirection vers le tableau de bord, et naviguer pendant la même frame
  /// nous ferait passer AVANT elle — donc écraser.
  void _consommerDestinationEnAttente() {
    final destination = _destinationEnAttente;
    if (destination == null) return;
    _destinationEnAttente = null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) GoRouter.of(context).go(destination);
    });
  }

  /// Enregistre le jeton dès qu'un utilisateur authentifié ET un jeton sont
  /// tous deux disponibles — dans n'importe quel ordre d'arrivée.
  void _synchroniser() {
    if (_jeton == null || _enregistre) return;
    if (!context.read<AuthBloc>().state.estAuthentifie) return;
    _enregistre = true;
    // Best-effort : une panne réseau au moment de l'enregistrement ne doit
    // pas remonter à l'utilisateur, il n'a rien demandé explicitement.
    unawaited(_gererAppareil.enregistrer(_jeton!));
  }

  /// Retire l'appareil des destinataires à la déconnexion.
  void _oublier() {
    final jeton = _jeton;
    _enregistre = false;
    if (jeton == null) return;
    unawaited(_gererAppareil.oublier(jeton));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      // Seules les BASCULES d'authentification comptent : rejouer l'appel à
      // chaque émission du bloc (chargement, erreur, mise à jour du profil)
      // enverrait une requête d'enregistrement par frappe de l'utilisateur.
      listenWhen: (a, b) => a.estAuthentifie != b.estAuthentifie,
      listener: (context, state) {
        if (state.estAuthentifie) {
          _synchroniser();
          _consommerDestinationEnAttente();
        } else {
          _oublier();
          // Une alerte touchée puis une déconnexion : la destination n'a plus
          // de sens et ne doit pas s'ouvrir à la prochaine connexion, sur un
          // compte éventuellement différent.
          _destinationEnAttente = null;
        }
      },
      child: widget.child,
    );
  }
}
