import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../config/user_role.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/auth/presentation/bloc/auth_state.dart';
import '../../features/auth/presentation/pages/forgot_password_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/mfa_page.dart';
import '../../features/auth/presentation/pages/register_page.dart';
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
import '../../features/rapport/presentation/pages/rapports_list_page.dart';
import '../../features/plan/presentation/pages/plan_navigation_page.dart';
import '../../features/plan/presentation/pages/plan_viewer_page.dart';
import '../../features/plan/presentation/pages/plans_list_page.dart';
import '../../features/chantier/presentation/pages/demandes_chantier_page.dart';
import '../../features/chantier/presentation/pages/depot_plans_page.dart';
import '../../features/reserve/presentation/pages/chantier_dashboard_page.dart';
import '../../features/reserve/presentation/pages/reserve_detail_page.dart';
import '../../features/reserve/presentation/pages/reserve_wizard_page.dart';
import '../../features/reserve/presentation/pages/reserves_list_page.dart';
import '../../features/reserve/presentation/pages/toutes_reserves_page.dart';
import '../../features/synchronisation/presentation/pages/taches_synchronisation_page.dart';
import '../widgets/app_shell.dart';

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
  static const planDetail = '/plans/:id';

  // Inspections et rapports — mêmes règles que les réserves : drill-down
  // depuis un chantier, écrans pleins hors coquille.
  static const inspections = '/chantiers/:chantierId/inspections';
  static const inspectionDetail = '/inspections/:id';
  static const rapports = '/chantiers/:chantierId/rapports';
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
      GoRoute(path: AppRoutes.register, builder: (_, _) => const RegisterPage()),
      GoRoute(path: AppRoutes.forgotPassword, builder: (_, _) => const ForgotPasswordPage()),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (_, state) => ResetPasswordPage(emailPrerempli: state.extra as String?),
      ),

      // ── Coquille applicative (barre de navigation adaptée au rôle) ────────
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          // Les quatre onglets de la barre
          GoRoute(path: AppRoutes.dashboard, builder: (_, _) => const DashboardPage()),
          GoRoute(path: AppRoutes.reserves, builder: (_, _) => const ToutesReservesPage()),
          GoRoute(path: AppRoutes.plans, builder: (_, _) => const PlansListPage()),

          // Écrans secondaires — la barre reste visible, l'onglet « Plus »
          // reste allumé (voir la liste `prefixes` dans AppShell).
          GoRoute(path: AppRoutes.chantiers, builder: (_, _) => const ChantiersListPage()),
          GoRoute(
            path: AppRoutes.chantierDetail,
            builder: (_, state) => ChantierDetailPage(chantierId: state.pathParameters['id']!),
          ),
          GoRoute(path: AppRoutes.equipe, builder: (_, _) => const MembresListPage()),
          GoRoute(path: AppRoutes.intervenants, builder: (_, _) => const IntervenantsListPage()),
          GoRoute(path: AppRoutes.profil, builder: (_, _) => const ProfilPage()),
          GoRoute(path: AppRoutes.parametres, builder: (_, _) => const SettingsPage()),
          GoRoute(path: AppRoutes.abonnement, builder: (_, _) => const AbonnementPage()),
          // Dans la coquille : l'écran garde la barre du bas, comme Réserves
          // et Plans dont il partage l'armature.
          GoRoute(path: AppRoutes.notifications, builder: (_, _) => const NotificationsPage()),
        ],
      ),

      // ── Réserves — écrans pleins, hors coquille ───────────────────────────
      GoRoute(
        path: AppRoutes.reservesListe,
        builder: (_, state) => ReservesListPage(chantierId: state.pathParameters['chantierId']!),
      ),
      GoRoute(
        path: AppRoutes.reserveNouvelle,
        builder: (_, state) => ReserveWizardPage(chantierId: state.pathParameters['chantierId']!),
      ),
      GoRoute(
        path: AppRoutes.reserveDetail,
        builder: (_, state) => ReserveDetailPage(reserveId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.chantierDashboard,
        builder: (_, state) => ChantierDashboardPage(chantierId: state.pathParameters['chantierId']!),
      ),
      GoRoute(
        path: AppRoutes.documents,
        builder: (_, state) => DocumentsListPage(chantierId: state.pathParameters['chantierId']!),
      ),

      // ── Synchronisation — écran plein, hors coquille ──────────────────────
      GoRoute(
        path: AppRoutes.tachesSynchronisation,
        builder: (_, _) => const TachesSynchronisationPage(),
      ),

      // ── Plans — écrans pleins, hors coquille ──────────────────────────────
      // ── Demandes de chantier — écrans pleins, hors coquille ─────────────
      //
      // Leurs chemins sont hors de `/chantiers/` : voir la note sur
      // `AppRoutes.demandesChantier`.
      GoRoute(
        path: AppRoutes.demandesChantier,
        builder: (_, _) => const DemandesChantierPage(),
      ),
      GoRoute(
        path: AppRoutes.depotPlans,
        builder: (_, state) => DepotPlansPage(
          chantierId: state.pathParameters['chantierId']!,
          // Le nom passe en query : l'écran n'a pas le chantier chargé, et un
          // titre sec ferait perdre le contexte après le sélecteur.
          chantierNom: state.uri.queryParameters['nom'],
        ),
      ),
      GoRoute(
        path: AppRoutes.chantierPlans,
        builder: (_, state) => PlansListPage(chantierId: state.pathParameters['chantierId']!),
      ),
      // Déclarée AVANT `planDetail` sans ambiguïté : les deux motifs ne se
      // recouvrent pas. En revanche l'ordre compte face à `chantierPlans`,
      // que `/plans/parcourir` ne doit pas capturer — go_router préfère la
      // route la plus spécifique, mais on la déclare juste après pour que la
      // lecture du fichier suive la hiérarchie réelle.
      GoRoute(
        path: AppRoutes.chantierPlansParcours,
        builder: (_, state) => PlanNavigationPage(
          chantierId: state.pathParameters['chantierId']!,
          chantierNom: state.uri.queryParameters['nom'],
        ),
      ),
      GoRoute(
        path: AppRoutes.planDetail,
        builder: (_, state) => PlanViewerPage(planId: state.pathParameters['id']!),
      ),

      // ── Inspections — écrans pleins, hors coquille ────────────────────────
      GoRoute(
        path: AppRoutes.inspections,
        builder: (_, state) => InspectionsListPage(
          chantierId: state.pathParameters['chantierId']!,
          chantierNom: state.uri.queryParameters['nom'],
        ),
      ),
      GoRoute(
        path: AppRoutes.inspectionDetail,
        builder: (_, state) => InspectionDetailPage(inspectionId: state.pathParameters['id']!),
      ),

      // ── Rapports — écran plein, hors coquille ─────────────────────────────
      GoRoute(
        path: AppRoutes.rapports,
        builder: (_, state) => RapportsListPage(
          chantierId: state.pathParameters['chantierId']!,
          chantierNom: state.uri.queryParameters['nom'],
        ),
      ),
    ],
  );

}

/// Fournit le routeur à `MaterialApp.router` en écoutant le [AuthBloc]
/// existant plutôt que d'en créer une nouvelle instance — le bloc de session
/// doit rester unique dans toute l'app.
GoRouter buildAppRouter(BuildContext context) {
  final authBloc = context.read<AuthBloc>();
  return AppRouter(authBloc).router;
}
