import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/user_role.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/bloc/auth_state.dart';
import '../../features/auth/presentation/pages/forgot_password_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/mfa_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
import '../config/regles_store.dart';
import '../../features/auth/presentation/pages/reset_password_page.dart';
import '../../features/auth/presentation/pages/bienvenue_page.dart';
import '../../features/auth/presentation/pages/splash_page.dart';
import '../../features/account/presentation/pages/profil_page.dart';
import '../../features/abonnement/presentation/pages/abonnement_page.dart';
import '../../features/account/presentation/pages/settings_page.dart';
import '../../features/chantier/presentation/pages/chantier_detail_page.dart';
import '../../features/chantier/presentation/pages/chantiers_list_page.dart';
import '../../features/dashboard/presentation/pages/dashboard_page.dart';
import '../../features/document/presentation/pages/documents_list_page.dart';
import '../../features/notification/presentation/pages/notifications_page.dart';
import '../../features/organisation/presentation/pages/intervenants_list_page.dart';
import '../../features/organisation/presentation/pages/membres_list_page.dart';
import '../../features/inspection/presentation/pages/inspection_detail_page.dart';
import '../../features/inspection/presentation/pages/inspections_list_page.dart';
import '../../features/rapport/domain/entities/rapport.dart';
import '../../features/rapport/presentation/pages/nouveau_rapport_page.dart';
import '../../features/rapport/presentation/pages/rapport_detail_page.dart';
import '../../features/rapport/presentation/pages/rapports_list_page.dart';
import '../../features/plan/presentation/pages/plan_navigation_page.dart';
import '../../features/plan/presentation/pages/plan_viewer_page.dart';
import '../../features/plan/presentation/pages/plan_explorer_page.dart';
import '../../features/plan/presentation/pages/plans_list_page.dart';
import '../../features/chantier/presentation/pages/demandes_chantier_page.dart';
import '../../features/chantier/presentation/pages/depot_plans_page.dart';
import '../../features/chantier/presentation/pages/membres_chantier_page.dart';
import '../../features/chantier/presentation/pages/structure_chantier_page.dart';
import '../../features/reserve/presentation/pages/chantier_dashboard_page.dart';
import '../../features/reserve/presentation/pages/reserve_detail_page.dart';
import '../../features/reserve/presentation/pages/reserve_wizard_page.dart';
import '../../features/reserve/presentation/pages/reserves_list_page.dart';
import '../../features/reserve/presentation/pages/toutes_reserves_page.dart';
import '../../features/synchronisation/presentation/pages/taches_synchronisation_page.dart';
import '../widgets/app_shell.dart';
import '../widgets/pile_onglets.dart';

class AppRoutes {
  AppRoutes._();

  static const splash = '/';

  /// Écran d'accueil du visiteur non connecté : la marque et les deux portes
  /// d'entrée (connexion, inscription). Toute session absente y aboutit —
  /// voir `redirect` plus bas.
  static const bienvenue = '/bienvenue';
  static const login = '/login';
  static const mfa = '/mfa';
  static const register = '/register';
  static const forgotPassword = '/mot-de-passe-oublie';
  static const resetPassword = '/reinitialiser-mot-de-passe';

  // ── Onglets de la barre de navigation ────────────────────────────────────
  static const dashboard = '/tableau-de-bord';
  static const reserves = '/reserves';
  static const plans = '/plans';
  static const plus = '/plus';

  // ── Écrans secondaires, accessibles depuis « Plus » ──────────────────────
  static const chantiers = '/chantiers';
  static const chantierDetail = '/chantiers/:id';

  /// Suivi des demandes de création de chantier.
  ///
  /// Volontairement HORS de l'espace `/chantiers/` : `chantierDetail`
  /// (`/chantiers/:id`) est déclaré plus haut, à l'intérieur de la coquille,
  /// et go_router résout dans l'ordre de déclaration — `/chantiers/demandes`
  /// aurait été capturé comme un chantier d'identifiant « demandes ».
  ///
  /// Les réordonner marcherait aussi, mais ferait dépendre la justesse de la
  /// position relative de deux blocs éloignés : la prochaine réorganisation du
  /// fichier recréerait le bug en silence. Des chemins distincts, eux, ne
  /// peuvent pas entrer en collision.
  static const demandesChantier = '/demandes-chantier';

  /// Dépôt des plans d'un chantier — plan global, bâtiments, niveaux.
  static const depotPlans = '/depot-plans/:chantierId';

  /// Dépôt SANS chantier : l'entreprise dépose d'abord ses plans, le
  /// formulaire de demande vient ensuite (voir DepotPlansCubit, mode
  /// brouillon). Chemin distinct plutôt qu'un paramètre facultatif, que
  /// go_router ne sait pas exprimer.
  static const depotPlansNouveau = '/depot-plans';
  static const equipe = '/equipe';
  static const intervenants = '/intervenants';
  static const profil = '/profil';
  static const parametres = '/parametres';
  static const notifications = '/notifications';

  // Abonnement — dans la coquille, comme Paramètres : c'est un écran de
  // compte, consulté puis quitté, pas un niveau de profondeur d'un chantier.
  static const abonnement = '/abonnement';

  // Synchronisation hors ligne — écran « Voir toutes les tâches », ouvert
  // depuis le bandeau rouge sur une tâche en échec. Hors coquille : c'est un
  // écran de reprise ponctuel, pas un onglet de navigation courante.
  static const tachesSynchronisation = '/synchronisation/taches';

  // Réserves — routes en dehors de la coquille (drill-down depuis un
  // chantier) : écrans dédiés avec leur propre AppBar/retour, pas de barre
  // de navigation globale à ce niveau de profondeur.
  static const reservesListe = '/chantiers/:chantierId/reserves';
  static const reserveNouvelle = '/chantiers/:chantierId/reserves/nouvelle';
  static const reserveDetail = '/reserves/:id';
  static const chantierDashboard = '/chantiers/:chantierId/tableau-de-bord';
  static const documents = '/chantiers/:chantierId/documents';
  static const chantierPlans = '/chantiers/:chantierId/plans';
  // Parcours du guide client : plan global → bâtiment → étage → appartement.
  // Distinct de `chantierPlans`, qui reste la LISTE à plat des documents
  // (import, versions) — les deux répondent à deux besoins différents.
  static const chantierPlansParcours = '/chantiers/:chantierId/plans/parcourir';

  /// Parcours des plans PAR NIVEAU — plans globaux, puis sous-plans directs.
  ///
  /// Distinct de `chantierPlansParcours`, qui descend la STRUCTURE du chantier
  /// (bâtiment → étage → appartement). Celui-ci descend l'arborescence des
  /// PLANS eux-mêmes (`plans.parent_id`), et c'est le parcours du relevé d'une
  /// réserve : on choisit un chantier, on voit ses plans globaux, on descend
  /// jusqu'au plan concerné, et on appuie dessus à l'endroit du défaut.
  static const chantierPlansExplorer = '/chantiers/:chantierId/plans/explorer';
  static const planDetail = '/plans/:id';

  // Inspections et rapports — mêmes règles que les réserves : drill-down
  // depuis un chantier, écrans pleins hors coquille.
  static const inspections = '/chantiers/:chantierId/inspections';
  static const inspectionDetail = '/inspections/:id';
  static const rapports = '/chantiers/:chantierId/rapports';

  // Module Rapports du cahier des charges : l'assistant « + Nouveau
  // rapport » (§ 3), depuis un chantier ou depuis nulle part — l'étape
  // « Choisir le projet » s'ajoute alors —, et le détail d'un rapport.
  static const rapportNouveau = '/chantiers/:chantierId/rapports/nouveau';
  static const rapportDetail = '/chantiers/:chantierId/rapports/:rapportId';
  static const rapportNouveauGlobal = '/rapports/nouveau';

  // Structure et membres d'un chantier — mêmes règles : écrans pleins.
  static const chantierStructure = '/chantiers/:chantierId/structure';
  static const chantierMembres = '/chantiers/:chantierId/membres';
}

/// Transition commune à tous les écrans PLEINS (ceux empilés hors de la
/// coquille).
///
/// ## Pourquoi une transition sur mesure
///
/// Par défaut, go_router applique la transition de la plateforme. Sur Android
/// c'est une montée verticale, sur le web un simple remplacement sans
/// animation : d'un appareil à l'autre, l'application ne se déplaçait pas de
/// la même manière, et sur navigateur elle ne se déplaçait pas du tout —
/// l'écran changeait d'une image à la suivante, sans rien dire du fait qu'on
/// venait d'ENTRER quelque part.
///
/// ## Ce qu'elle fait
///
/// La page qui arrive glisse depuis la droite en se révélant ; celle qui reste
/// dessous recule légèrement vers la gauche et s'estompe. Ce sont les deux
/// moitiés d'un même geste : sans le recul de la page du dessous, la nouvelle
/// semble se poser sur une image figée.
///
///  - **300 ms à l'aller, 240 au retour** : revenir doit être un peu plus vif
///    qu'aller — c'est un geste que l'on répète, et qui ne demande pas d'être
///    accompagné aussi longuement ;
///  - **glissement de 6 %** de la largeur : assez pour donner la direction,
///    trop peu pour donner l'impression de faire défiler un carrousel ;
///  - `easeOutCubic` à l'entrée : la page décélère, elle « se pose ».
CustomTransitionPage<void> _pagePleine(GoRouterState state, Widget enfant) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    child: enfant,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final entree = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      final sortie = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic);
      return SlideTransition(
        // Le décalage de la page du DESSOUS quand une autre vient la couvrir.
        position: Tween<Offset>(begin: Offset.zero, end: const Offset(-0.03, 0)).animate(sortie),
        child: FadeTransition(
          opacity: entree,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero).animate(entree),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Transition des ecrans de la COQUILLE — les quatre onglets et les ecrans
/// du menu « Plus ».
///
/// Volontairement differente de [_pagePleine] : entre deux onglets il n'y a ni
/// avant ni apres, et le glissement lateral d'un empilement raconterait une
/// hierarchie qui n'existe pas. Un fondu, avec une montee de 1,5 % pour donner
/// de la matiere, suffit a marquer le changement sans le commenter.
///
/// Plus court aussi (220 ms contre 300) : passer d'un onglet a l'autre est un
/// geste que l'on repete, il ne doit jamais se faire attendre.
CustomTransitionPage<void> _pageOnglet(GoRouterState state, Widget enfant) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 160),
    child: enfant,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final entree = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: entree,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.015), end: Offset.zero).animate(entree),
          child: child,
        ),
      );
    },
  );
}

/// Pont entre un `Stream` (ici, le `Stream<AuthState>` du bloc) et
/// `Listenable`, requis par `GoRouter.refreshListenable` pour redéclencher
/// l'évaluation des redirections à chaque changement d'état d'authentification.
class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

class AppRouter {
  final AuthBloc authBloc;
  AppRouter(this.authBloc);

  late final GoRouter router = GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: GoRouterRefreshStream(authBloc.stream),
    redirect: (context, state) {
      final authState = authBloc.state;
      final loc = state.matchedLocation;

      final estSurEcranPublic = loc == AppRoutes.bienvenue ||
          loc == AppRoutes.login ||
          loc == AppRoutes.register ||
          loc == AppRoutes.mfa ||
          loc == AppRoutes.forgotPassword ||
          loc == AppRoutes.resetPassword;

      // Session encore en cours de vérification (démarrage) — rester sur le
      // splash tant que la décision n'est pas prise, pour éviter un flash
      // de l'écran de login avant que la session en cache soit restaurée.
      if (authState.status == AuthStatus.inconnu) {
        return loc == AppRoutes.splash ? null : AppRoutes.splash;
      }

      if (authState.status == AuthStatus.mfaRequis) {
        return loc == AppRoutes.mfa ? null : AppRoutes.mfa;
      }

      // Sans session, on arrive sur l'ACCUEIL et non sur le formulaire de
      // connexion : un premier visiteur doit pouvoir choisir « créer un
      // compte » sans avoir à repérer un lien sous un champ email. Les écrans
      // publics (dont login et register) restent atteignables depuis là.
      if (authState.status == AuthStatus.nonAuthentifie) {
        return estSurEcranPublic ? null : AppRoutes.bienvenue;
      }

      // Authentifié : ne jamais rester sur un écran public / splash.
      if (authState.status == AuthStatus.authentifie) {
        if (loc == AppRoutes.splash || estSurEcranPublic) {
          // Le sous-traitant n'a rien à faire d'un tableau de bord chantier :
          // son travail, ce sont les réserves qui lui sont assignées. Tous
          // les autres rôles gardent le même accueil qu'avant (Dashboard).
          if (authState.utilisateur?.role == UserRole.sousTraitant) return AppRoutes.reserves;
          return AppRoutes.dashboard;
        }

        // Garde de route par rôle — défense en profondeur. Le back refuse
        // déjà `/organisation/membres` aux rôles hors GESTION_MEMBRES ; ceci évite
        // seulement d'ouvrir un écran voué à afficher une erreur, y compris
        // par lien profond où la barre de navigation n'a rien masqué.
        final role = authState.utilisateur?.role;
        if (loc.startsWith(AppRoutes.equipe) && !(role?.peutGererMembres ?? false)) {
          return AppRoutes.dashboard;
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashPage()),
      GoRoute(path: AppRoutes.bienvenue, builder: (_, _) => const BienvenuePage()),
      GoRoute(path: AppRoutes.login, builder: (_, _) => const LoginPage()),
      GoRoute(path: AppRoutes.mfa, builder: (_, _) => const MfaPage()),
      // Inscription : retirée sur iOS (Apple y voit un canal d'achat
      // externe — voir `ReglesStore`). La route reste déclarée pour qu'un
      // lien résiduel ou un lien profond ne provoque pas d'erreur : il
      // ramène à la connexion.
      GoRoute(
        path: AppRoutes.register,
        redirect: (_, _) => ReglesStore.inscriptionAutorisee ? null : AppRoutes.login,
        builder: (_, _) => const RegisterPage(),
      ),
      GoRoute(path: AppRoutes.forgotPassword, builder: (_, _) => const ForgotPasswordPage()),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (_, state) => ResetPasswordPage(emailPrerempli: state.extra as String?),
      ),

      // ── Coquille applicative (barre de navigation adaptée au rôle) ────────
      StatefulShellRoute(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),

        // Conteneur MAISON plutôt que `StatefulShellRoute.indexedStack` : ce
        // dernier conserve l'état mais bascule sans transition, ce qui aurait
        // coûté le fondu marquant le changement d'onglet. `PileOnglets` fait
        // les deux — voir son en-tête.
        navigatorContainerBuilder: (context, navigationShell, children) =>
            PileOnglets(index: navigationShell.currentIndex, enfants: children),

        // UNE BRANCHE PAR ONGLET. Chacune a son propre navigateur, et garde
        // donc son état : listes chargées, filtres saisis, position de
        // défilement. Avant, tout cela repartait de zéro — et le cubit de
        // l'écran rappelait le serveur — à chaque retour sur l'onglet.
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.dashboard,
              pageBuilder: (_, state) => _pageOnglet(state, const DashboardPage()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.reserves,
              pageBuilder: (_, state) => _pageOnglet(state, const ToutesReservesPage()),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.plans,
              pageBuilder: (_, state) => _pageOnglet(state, const PlansListPage()),
            ),
          ]),

          // Quatrième branche : TOUT ce que dessert le menu « Plus ». L'onglet
          // n'y conduit pas directement (il ouvre un éventail), mais il reste
          // allumé pendant qu'on navigue dedans — c'est cette branche qui le
          // dit désormais, au lieu d'une liste de préfixes à tenir à jour.
          //
          // `initialLocation` est nécessaire : sans elle, go_router prendrait
          // la première route de la branche, et `/chantiers` s'ouvrirait tout
          // seul au premier affichage de la coquille.
          StatefulShellBranch(
            initialLocation: AppRoutes.chantiers,
            routes: [
              GoRoute(
                path: AppRoutes.chantiers,
                pageBuilder: (_, state) => _pageOnglet(state, const ChantiersListPage()),
              ),
              GoRoute(
                path: AppRoutes.chantierDetail,
                pageBuilder: (_, state) =>
                    _pageOnglet(state, ChantierDetailPage(chantierId: state.pathParameters['id']!)),
              ),
              GoRoute(
                path: AppRoutes.equipe,
                pageBuilder: (_, state) => _pageOnglet(state, const MembresListPage()),
              ),
              GoRoute(
                path: AppRoutes.intervenants,
                pageBuilder: (_, state) => _pageOnglet(state, const IntervenantsListPage()),
              ),
              GoRoute(
                path: AppRoutes.profil,
                pageBuilder: (_, state) => _pageOnglet(state, const ProfilPage()),
              ),
              GoRoute(
                path: AppRoutes.parametres,
                pageBuilder: (_, state) => _pageOnglet(state, const SettingsPage()),
              ),
              // Abonnement : écran de vente, donc absent sur iOS (voir
              // `ReglesStore`). Redirigé vers l'accueil plutôt que supprimé,
              // pour qu'aucun chemin résiduel ne tombe sur une erreur.
              GoRoute(
                path: AppRoutes.abonnement,
                redirect: (_, _) => ReglesStore.commerceAutorise ? null : AppRoutes.dashboard,
                pageBuilder: (_, state) => _pageOnglet(state, const AbonnementPage()),
              ),
              // Dans la coquille : l'écran garde la barre du bas, comme
              // Réserves et Plans dont il partage l'armature.
              GoRoute(
                path: AppRoutes.notifications,
                pageBuilder: (_, state) => _pageOnglet(state, const NotificationsPage()),
              ),
            ],
          ),
        ],
      ),

      // ── Réserves — écrans pleins, hors coquille ───────────────────────────
      GoRoute(
        path: AppRoutes.reservesListe,
        pageBuilder: (_, state) => _pagePleine(state, ReservesListPage(chantierId: state.pathParameters['chantierId']!)),
      ),
      GoRoute(
        path: AppRoutes.reserveNouvelle,
        pageBuilder: (_, state) => _pagePleine(
          state,
          ReserveWizardPage(
            chantierId: state.pathParameters['chantierId']!,
            // Le plan arrive en query et non en segment de chemin : il est
            // FACULTATIF. On atteint aussi l'assistant depuis la liste des
            // réserves d'un chantier, sans plan désigné — un segment aurait
            // exigé une seconde route pour dire la même chose.
            planId: state.uri.queryParameters['planId'],
            planNom: state.uri.queryParameters['planNom'],
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.reserveDetail,
        pageBuilder: (_, state) => _pagePleine(state, ReserveDetailPage(reserveId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: AppRoutes.chantierDashboard,
        pageBuilder: (_, state) => _pagePleine(state, ChantierDashboardPage(chantierId: state.pathParameters['chantierId']!)),
      ),
      GoRoute(
        path: AppRoutes.documents,
        pageBuilder: (_, state) => _pagePleine(state, DocumentsListPage(chantierId: state.pathParameters['chantierId']!)),
      ),

      // ── Synchronisation — écran plein, hors coquille ──────────────────────
      GoRoute(
        path: AppRoutes.tachesSynchronisation,
        pageBuilder: (_, state) => _pagePleine(state, const TachesSynchronisationPage()),
      ),

      // ── Plans — écrans pleins, hors coquille ──────────────────────────────
      // ── Demandes de chantier — écrans pleins, hors coquille ─────────────
      //
      // Leurs chemins sont hors de `/chantiers/` : voir la note sur
      // `AppRoutes.demandesChantier`.
      GoRoute(
        path: AppRoutes.demandesChantier,
        pageBuilder: (_, state) => _pagePleine(state, const DemandesChantierPage()),
      ),
      // Déclarée AVANT `depotPlans` : les deux motifs ne se recouvrent pas,
      // mais la lecture suit ainsi l'ordre du parcours — on dépose d'abord,
      // on revient compléter ensuite.
      GoRoute(
        path: AppRoutes.depotPlansNouveau,
        pageBuilder: (_, state) => _pagePleine(state, const DepotPlansPage()),
      ),
      GoRoute(
        path: AppRoutes.depotPlans,
        pageBuilder: (_, state) => _pagePleine(state, DepotPlansPage(
          chantierId: state.pathParameters['chantierId']!,
          // Le nom passe en query : l'écran n'a pas le chantier chargé, et un
          // titre sec ferait perdre le contexte après le sélecteur.
          chantierNom: state.uri.queryParameters['nom'],
        )),
      ),
      GoRoute(
        path: AppRoutes.chantierPlans,
        pageBuilder: (_, state) => _pagePleine(state, PlansListPage(chantierId: state.pathParameters['chantierId']!)),
      ),
      // Déclarée AVANT `planDetail` sans ambiguïté : les deux motifs ne se
      // recouvrent pas. En revanche l'ordre compte face à `chantierPlans`,
      // que `/plans/parcourir` ne doit pas capturer — go_router préfère la
      // route la plus spécifique, mais on la déclare juste après pour que la
      // lecture du fichier suive la hiérarchie réelle.
      // Déclarée avant `chantierPlansParcours` : les deux sous-chemins sont
      // statiques et distincts, l'ordre n'a donc aucune incidence sur le
      // routage — il suit la fréquence d'usage, l'explorateur étant le
      // parcours du relevé quotidien.
      GoRoute(
        path: AppRoutes.chantierPlansExplorer,
        pageBuilder: (_, state) => _pagePleine(state, PlanExplorerPage(
          chantierId: state.pathParameters['chantierId']!,
          chantierNom: state.uri.queryParameters['nom'],
          // Facultatif : ouvre l'explorateur DIRECTEMENT sur ce plan au lieu
          // de partir des plans globaux. Utilisé par la bande « Derniers
          // plans » de l'accueil, où l'on appuie sur un plan précis.
          planIdInitial: state.uri.queryParameters['planId'],
        )),
      ),
      GoRoute(
        path: AppRoutes.chantierPlansParcours,
        pageBuilder: (_, state) => _pagePleine(state, PlanNavigationPage(
          chantierId: state.pathParameters['chantierId']!,
          chantierNom: state.uri.queryParameters['nom'],
        )),
      ),
      GoRoute(
        path: AppRoutes.planDetail,
        pageBuilder: (_, state) => _pagePleine(state, PlanViewerPage(planId: state.pathParameters['id']!)),
      ),

      // ── Inspections — écrans pleins, hors coquille ────────────────────────
      GoRoute(
        path: AppRoutes.inspections,
        pageBuilder: (_, state) => _pagePleine(state, InspectionsListPage(
          chantierId: state.pathParameters['chantierId']!,
          chantierNom: state.uri.queryParameters['nom'],
        )),
      ),
      GoRoute(
        path: AppRoutes.inspectionDetail,
        pageBuilder: (_, state) => _pagePleine(state, InspectionDetailPage(inspectionId: state.pathParameters['id']!)),
      ),

      // ── Rapports — écran plein, hors coquille ─────────────────────────────
      GoRoute(
        path: AppRoutes.rapports,
        pageBuilder: (_, state) => _pagePleine(state, RapportsListPage(
          chantierId: state.pathParameters['chantierId']!,
          chantierNom: state.uri.queryParameters['nom'],
        )),
      ),
      // « nouveau » AVANT « :rapportId » : sinon le mot serait pris pour un
      // identifiant de rapport.
      GoRoute(
        path: AppRoutes.rapportNouveau,
        pageBuilder: (_, state) => _pagePleine(state, NouveauRapportPage(
          chantierId: state.pathParameters['chantierId']!,
          chantierNom: state.uri.queryParameters['nom'],
          // Rapport à modifier (§ 20) ou copie à retoucher.
          existant: state.extra is Rapport ? state.extra as Rapport : null,
        )),
      ),
      GoRoute(
        path: AppRoutes.rapportDetail,
        pageBuilder: (_, state) => _pagePleine(state, RapportDetailPage(
          rapportId: state.pathParameters['rapportId']!,
          chantierNom: state.uri.queryParameters['nom'],
        )),
      ),
      GoRoute(
        path: AppRoutes.rapportNouveauGlobal,
        pageBuilder: (_, state) => _pagePleine(state, const NouveauRapportPage()),
      ),

      // ── Structure et membres d'un chantier — écrans pleins ────────────────
      GoRoute(
        path: AppRoutes.chantierStructure,
        pageBuilder: (_, state) => _pagePleine(
          state,
          StructureChantierPage(chantierId: state.pathParameters['chantierId']!),
        ),
      ),
      GoRoute(
        path: AppRoutes.chantierMembres,
        pageBuilder: (_, state) => _pagePleine(
          state,
          MembresChantierPage(chantierId: state.pathParameters['chantierId']!),
        ),
      ),
    ],
  );

}
