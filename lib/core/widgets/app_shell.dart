import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../config/user_role.dart';
import '../routes/app_router.dart';
import '../services/verrou_biometrique.dart';
import '../config/breakpoints.dart';
import '../theme/app_colors.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/notification/presentation/cubit/notifications_cubit.dart';
import '../../injection_container.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/l10n_extension.dart';
import 'action_rapide.dart';
import 'chantier_picker_sheet.dart';
import 'menu_plus_sheet.dart';
import 'plan_picker_sheet.dart';

/// Un onglet de la barre. [prefixes] liste TOUTES les routes qui doivent
/// allumer cet onglet — pas seulement sa destination : « Plus » reste
/// surligné quand on est sur Chantiers ou Équipe, qui sont ses sous-écrans.
typedef _Onglet = ({
  String route,
  List<String> prefixes,
  IconData icon,
  IconData iconActif,
  String label,

  /// L'onglet ouvre un MENU au lieu de naviguer. C'est le cas de « Plus » :
  /// son ancienne page n'était qu'une liste de raccourcis, un écran de plus à
  /// traverser pour arriver où l'on voulait aller.
  bool estMenu,
});

const double _hauteurBarre = 64;
const double _diametreFab = 58;

/// Largeur a partir de laquelle la coquille passe de la barre du BAS a une
/// barre LATERALE (tablette).
///
/// 700 dp tranche net entre les deux familles d'appareils :
///  - le telephone le plus large, tourne en paysage, plafonne vers 430 dp : il
///    ne bascule jamais ;
///  - une tablette 7 pouces en paysage fait ~960 dp et une 10 pouces ~1280 dp :
///    elles basculent toujours. Une 7 pouces en PORTRAIT (~600 dp) garde la
///    barre du bas : a cette largeur un rail de 200 dp mangerait un tiers de
///    l'ecran.

const double _largeurRail = 200;

/// Coquille applicative — barre de navigation basse et bouton d'action
/// central, conformément à la maquette Widjila (proposition 4).
///
/// La barre n'utilise pas `NavigationBar` de Material : la maquette impose un
/// bouton flottant AU MILIEU de la barre, qui déborde vers le haut. Aucun
/// composant Material ne fait ça — d'où une barre dessinée à la main, qui
/// garde en revanche les mêmes règles de rôle que le reste de l'app (voir
/// [_AppShellState._entreesPlus]).
class AppShell extends StatefulWidget {
  /// Coquille à branches fournie par `StatefulShellRoute`.
  ///
  /// Porte l'onglet courant (`currentIndex`), le contenu déjà empilé de chaque
  /// branche, et `goBranch` pour passer de l'une à l'autre en RESTAURANT son
  /// état plutôt qu'en la reconstruisant.
  final StatefulNavigationShell navigationShell;

  const AppShell({super.key, required this.navigationShell});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// Empêche de relancer la proposition de verrou si la coquille se
  /// reconstruit (changement d'onglet, rotation) avant la fin du premier
  /// passage — `propositionFaite` n'est écrit qu'À LA FIN du dialogue.
  bool _propositionEnCours = false;

  @override
  void initState() {
    super.initState();
    // Après la première image : `showDialog` a besoin d'un arbre monté, et
    // `disponible` interroge le système d'authentification de l'appareil.
    WidgetsBinding.instance.addPostFrameCallback((_) => _proposerVerrouSiPertinent());
  }

  /// Propose UNE fois le déverrouillage biométrique, à l'arrivée dans
  /// l'application.
  ///
  /// La coquille est le seul point de passage obligé de tous les rôles :
  /// l'accueil diffère (tableau de bord pour les uns, liste des chantiers
  /// pour Entreprise et Client — voir `accueilEstListeChantiers`), mais tout
  /// le monde entre par ici. Poser la question sur chaque écran d'accueil
  /// aurait dupliqué la logique et laissé des rôles de côté.
  ///
  /// Le réglage lui-même existe déjà dans les paramètres ; ce dialogue ne
  /// fait que le rendre découvrable — sans lui, personne ne l'active jamais.
  Future<void> _proposerVerrouSiPertinent() async {
    if (_propositionEnCours) return;
    final verrou = sl<VerrouBiometrique>();
    if (verrou.actif || verrou.propositionFaite) return;
    // Un appareil sans biométrie ENREGISTRÉE ne peut pas honorer le réglage :
    // proposer serait promettre ce qu'on ne peut pas tenir.
    if (!await verrou.disponible) return;
    if (!mounted) return;

    _propositionEnCours = true;
    final l10n = context.l10n;
    final accepte = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.fingerprint_rounded, size: 34, color: AppColors.primary),
        title: Text(l10n.bioProposerTitre),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.bioProposerTexte, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(
              l10n.bioProposerReglages,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.bioProposerPlusTard),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.bioProposerActiver),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (accepte != true) {
      // Refus explicite (ou dialogue fermé) : on ne repose plus la question.
      await verrou.marquerPropositionFaite();
      _propositionEnCours = false;
      return;
    }

    // `definirActif` redemande la biométrie pour confirmer — c'est elle qui
    // fait apparaître la boîte du système (empreinte, visage, ou code de
    // l'appareil en repli).
    final active = await verrou.definirActif(true, motif: l10n.bioInvite);

    // Marqué SEULEMENT si l'activation a abouti : un capteur qui n'a pas lu
    // le doigt du premier coup ne doit pas coûter l'offre définitivement.
    if (active) await verrou.marquerPropositionFaite();
    _propositionEnCours = false;

    if (!mounted || active) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(content: Text(l10n.bioEchec), backgroundColor: AppColors.danger),
    );
  }

  // Non `const` (contrairement à l'ancienne version) : le libellé vient de
  // `AppLocalizations`, qui exige un `BuildContext` — indisponible à
  // l'initialisation d'un champ statique.
  List<_Onglet> _onglets(AppLocalizations l10n) => [
    (
      route: AppRoutes.dashboard,
      prefixes: [AppRoutes.dashboard],
      icon: Icons.home_outlined,
      iconActif: Icons.home_rounded,
      label: l10n.navAccueil,
      estMenu: false,
    ),
    (
      route: AppRoutes.reserves,
      prefixes: [AppRoutes.reserves],
      icon: Icons.assignment_outlined,
      iconActif: Icons.assignment_rounded,
      label: l10n.navReserves,
      estMenu: false,
    ),
    (
      route: AppRoutes.plans,
      prefixes: [AppRoutes.plans],
      icon: Icons.map_outlined,
      iconActif: Icons.map_rounded,
      label: l10n.navPlans,
      estMenu: false,
    ),
    (
      route: AppRoutes.plus,
      // « Plus » est le portail des écrans secondaires : il doit rester
      // allumé quand on navigue dans l'un d'eux.
      prefixes: [
        AppRoutes.plus,
        AppRoutes.chantiers,
        AppRoutes.equipe,
        AppRoutes.intervenants,
        AppRoutes.profil,
      ],
      icon: Icons.more_horiz_rounded,
      iconActif: Icons.more_horiz_rounded,
      label: l10n.navPlus,
      estMenu: true,
    ),
  ];

  /// Entrées du menu « Plus » — TOUT ce qui n'a pas son propre onglet.
  ///
  /// ## Pourquoi elles sont toutes ici
  ///
  /// « Tableau de bord chantier » et « Envoi de plans » vivaient derrière le
  /// bouton « + » de la barre. Ce bouton ne signifie plus qu'une seule chose —
  /// créer une réserve, de loin le geste le plus fréquent sur un chantier — et
  /// les deux entrées ont rejoint le menu.
  ///
  /// Le partage tenait mal de toute façon : un « + » promet de CRÉER quelque
  /// chose, or ouvrir le tableau de bord d'un chantier ne crée rien. On
  /// cherche une destination dans « Plus », pas derrière un bouton de
  /// création.
  ///
  /// ## Filtrage par rôle
  ///
  /// Mêmes règles que les `requireRole` du back, pour ne jamais proposer un
  /// raccourci que le serveur refuserait :
  ///
  ///  - tableau de bord chantier : aucun `requireRole` côté serveur (voir
  ///    `backend/src/modules/dashboard/route/dashboard.route.js`) ;
  ///  - document : OPERATIONNEL_CONTROLE ;
  ///  - équipe : GESTION_MEMBRES (`backend/src/config/roles.js`) ;
  ///  - chantiers, demandes, intervenants : lecture, aucun rôle exigé.
  List<ActionRapide> _entreesPlus(AppLocalizations l10n, UserRole? role) => [
    (
      icon: Icons.insights_rounded,
      label: l10n.actionTableauBordChantier,
      couleur: AppColors.primary,
      besoinChantier: true,
      avecCreation: false,
      dansCoquille: false,
      route: (String? id) => '/chantiers/$id/tableau-de-bord',
    ),
    // « Envoi de plans » passe par le sélecteur comme les autres, mais
    // celui-ci propose de CRÉER un chantier : c'est précisément l'action
    // de qui n'en a pas encore un seul.
    //
    // Réservée à `peutDeposerPlans` (miroir de `DEPOSANT`) : la proposer à
    // un client ou à un sous-traitant l'aurait mené jusqu'au sélecteur de
    // chantier pour finir sur un 403.
    if (role?.peutDeposerPlans ?? false)
      (
        icon: Icons.upload_file_rounded,
        label: l10n.envoiPlanTitre,
        couleur: AppColors.info,
        besoinChantier: true,
        avecCreation: true,
        dansCoquille: false,
        route: _versDepotPlans,
      ),
    if (role?.peutGererMembres ?? false)
      (
        icon: Icons.groups_rounded,
        label: l10n.actionEquipe,
        couleur: AppColors.accentDark,
        // Transversale à l'organisation : aucun chantier à choisir.
        besoinChantier: false,
        avecCreation: false,
        dansCoquille: true,
        route: (String? _) => AppRoutes.equipe,
      ),
    (
      icon: Icons.construction_rounded,
      label: l10n.actionChantiers,
      couleur: AppColors.primary,
      besoinChantier: false,
      avecCreation: false,
      dansCoquille: true,
      route: _versChantiers,
    ),
    if (role?.estOperationnelOuControle ?? false)
      (
        icon: Icons.folder_open_rounded,
        label: l10n.actionDocument,
        couleur: AppColors.success,
        besoinChantier: true,
        avecCreation: false,
        dansCoquille: false,
        route: (String? id) => '/chantiers/$id/documents',
      ),
    (
      icon: Icons.assignment_outlined,
      label: l10n.demandesTitre,
      couleur: AppColors.warning,
      besoinChantier: false,
      avecCreation: false,
      dansCoquille: false,
      route: _versDemandes,
    ),
    // Abonnement : ouvert à TOUS les rôles, sans garde.
    //
    // Chacun a un intérêt légitime à voir la formule en cours et ce qu'il
    // reste de quota — c'est ce qui explique un refus de créer un chantier.
    // Seule la FACTURATION est réservée : la page masque cette section
    // d'elle-même selon le rôle (voir `AbonnementPage`), plutôt que de rendre
    // l'écran entier inaccessible.
    (
      icon: Icons.workspace_premium_rounded,
      label: l10n.abonnementTitre,
      couleur: AppColors.warning,
      besoinChantier: false,
      avecCreation: false,
      dansCoquille: true,
      route: _versAbonnement,
    ),
    (
      icon: Icons.handshake_rounded,
      label: l10n.actionIntervenants,
      couleur: AppColors.info,
      besoinChantier: false,
      avecCreation: false,
      dansCoquille: true,
      route: _versIntervenants,
    ),
  ];

  // Fonctions nommées et non lambdas : une liste `const` n'accepte pas de
  // fermeture créée à la volée.
  static String _versChantiers(String? _) => AppRoutes.chantiers;
  static String _versDemandes(String? _) => AppRoutes.demandesChantier;
  static String _versDepotPlans(String? id) =>
      AppRoutes.depotPlans.replaceFirst(':chantierId', id ?? '');
  static String _versIntervenants(String? _) => AppRoutes.intervenants;
  static String _versAbonnement(String? _) => AppRoutes.abonnement;

  /// Ouvre le menu « Plus » et exécute l'entrée choisie.
  Future<void> _ouvrirMenuPlus() async {
    final role = context.read<AuthBloc>().state.utilisateur?.role;
    final entrees = _entreesPlus(context.l10n, role);
    if (entrees.isEmpty) return;

    final choix = await ouvrirMenuPlus(context, entrees);
    if (choix == null || !mounted) return;
    await _executer(choix);
  }

  /// Conduit à la destination d'une entrée, en intercalant le sélecteur de
  /// chantier quand l'écran visé en exige un.
  Future<void> _executer(ActionRapide action) async {
    // Deux familles d'écrans, deux façons d'y aller :
    //
    //  - hors coquille (tableau de bord chantier, documents) : écrans pleins
    //    empilés par-dessus, avec leur propre flèche de retour → `push` ;
    //  - dans la coquille (équipe) : c'est une destination de la barre du bas,
    //    `push` y empilerait une SECONDE coquille par-dessus la première, avec
    //    deux barres de navigation superposées → `go`.
    if (!action.besoinChantier) {
      if (!context.mounted) return;
      final destination = action.route(null);
      action.dansCoquille ? context.go(destination) : context.push(destination);
      return;
    }

    // Le reste appartient toujours à un chantier : on le demande avant
    // d'ouvrir l'écran (voir chantier_picker_sheet).
    final chantier = await choisirChantier(
      context,
      titre: action.label,
      avecCreation: action.avecCreation,
    );
    if (chantier == null || !mounted || !context.mounted) return;

    // Le nom suit en query : les écrans pleins n'ont pas le chantier chargé,
    // et un titre sec ferait perdre le contexte juste après le sélecteur.
    final destination =
        '${action.route(chantier.id)}'
        '?nom=${Uri.encodeComponent(chantier.nom)}';
    action.dansCoquille ? context.go(destination) : context.push(destination);
  }

  /// Parcours du bouton « + » central : chantier, puis plan, puis le
  /// formulaire de réserve.
  ///
  /// ## Pourquoi ce bouton ne fait plus qu'une chose
  ///
  /// Il ouvrait un éventail de trois raccourcis hétéroclites — tableau de
  /// bord, documents, envoi de plans — dont aucun ne CRÉAIT quoi que ce soit.
  /// Un « + » au centre de la barre, c'est le geste principal de
  /// l'application ; sur un chantier, ce geste est de relever une réserve.
  /// Les trois raccourcis ont rejoint le menu « Plus », où l'on cherche
  /// naturellement une destination.
  ///
  /// ## Pourquoi passer par le plan
  ///
  /// Une réserve se situe : « fissure » sans dire où n'aide personne. Le plan
  /// est le repère commun de tous les intervenants, et le serveur sait le
  /// rattacher (`planId` de `POST /reserves`). Le chantier d'abord, puisqu'un
  /// plan appartient à un chantier.
  ///
  /// Le sélecteur de plan sait aussi répondre « sans plan » : un chantier dont
  /// les plans ne sont pas encore déposés ne doit pas empêcher de relever une
  /// réserve (voir [choisirPlan]).
  Future<void> _nouvelleReserve() async {
    final chantier = await choisirChantier(context, titre: context.l10n.syncNomNouvelleReserve);
    if (chantier == null || !mounted || !context.mounted) return;

    final choix = await choisirPlan(context, chantierId: chantier.id, chantierNom: chantier.nom);
    // Feuille refermée sans rien décider : on s'arrête là. Enchaîner sur le
    // formulaire ignorerait un abandon explicite.
    if (choix == null || !mounted || !context.mounted) return;

    final plan = choix.plan;
    final query = plan == null ? '' : '?planId=${plan.id}&planNom=${Uri.encodeComponent(plan.nom)}';
    context.push('/chantiers/${chantier.id}/reserves/nouvelle$query');
  }

  @override
  Widget build(BuildContext context) {
    final role = context.select((AuthBloc b) => b.state.utilisateur?.role);
    final l10n = context.l10n;
    // Le serveur réserve la création de réserve aux rôles
    // RESERVE_INTERVENANTS : afficher le bouton aux autres serait promettre
    // une action qui reviendrait en 403 après deux sélecteurs.
    final peutCreerReserve = role?.peutIntervenirSurReserves ?? false;
    final onglets = _onglets(l10n);

    // LU, et non déduit de la route. La déduction par préfixes se trompait sur
    // `/parametres`, `/notifications` et `/abonnement` — aucun préfixe ne
    // correspondait, elle retombait sur 0 et allumait l'onglet Accueil.
    final index = widget.navigationShell.currentIndex;

    // Un SEUL cubit de notifications pour toute la coquille : la cloche de
    // chaque onglet, celle du tableau de bord et l'écran Notifications lisent
    // ainsi le même compteur. Le fournir par écran ferait diverger les
    // pastilles entre onglets après un « tout marquer comme lu ».
    //
    // Le contenu est la coquille elle-même : `PileOnglets` (voir
    // `app_router.dart`) garde chaque branche montée et anime celle qui entre.
    final contenu = widget.navigationShell;

    void ouvrirOnglet(int i) {
      // L'onglet « Plus » n'est pas une destination : il ouvre un éventail.
      if (onglets[i].estMenu) {
        _ouvrirMenuPlus();
        return;
      }
      // `goBranch` et non `go` : restaure la branche telle qu'elle avait été
      // laissée. `initialLocation: true` seulement si l'on retape l'onglet
      // DÉJÀ actif — geste qui, partout ailleurs, ramène en haut de la pile.
      widget.navigationShell.goBranch(
        i,
        initialLocation: i == widget.navigationShell.currentIndex,
      );
    }

    // Le seuil est lu ICI et non dans un widget enfant : la coquille change de
    // structure (Row + rail contre body + barre basse), pas seulement de
    // style. Un LayoutBuilder plus bas ne verrait que la zone deja amputee du
    // rail, et ne pourrait donc plus decider de sa propre existence.
    final estTablette = MediaQuery.sizeOf(context).width >= seuilTablette;

    return BlocProvider<NotificationsCubit>(
      create: (_) => sl<NotificationsCubit>()..charger(),
      child: estTablette
          ? Scaffold(
              body: Row(
                children: [
                  _BarreLaterale(onglets: onglets, indexActif: index, onOnglet: ouvrirOnglet),
                  Expanded(child: contenu),
                ],
              ),
              // Sur tablette le « + » quitte la barre (il n'y en a plus) pour
              // le coin bas-droit du contenu.
              floatingActionButton: !peutCreerReserve
                  ? null
                  : FloatingActionButton(
                      onPressed: _nouvelleReserve,
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 6,
                      child: const Icon(Icons.add_rounded, size: 28),
                    ),
            )
          : Scaffold(
              body: contenu,
              bottomNavigationBar: _BarreNavigation(
                onglets: onglets,
                indexActif: index,
                avecFab: peutCreerReserve,
                onOnglet: ouvrirOnglet,
                onFab: _nouvelleReserve,
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
//  BARRE LATERALE (TABLETTE)
// ---------------------------------------------------------------------------

/// Navigation de la coquille en format tablette : logo, onglets, puis
/// l'utilisateur connecte en pied de rail.
///
/// Ce n'est pas un `NavigationRail` de Material : celui-ci impose ses propres
/// gabarits d'indicateur et n'accepte pas de pied de colonne. Le rail reprend
/// en revanche EXACTEMENT le vocabulaire de la barre du bas (memes icones,
/// memes libelles, meme surlignage orange) : un utilisateur doit retrouver la
/// meme application d'un appareil a l'autre.
class _BarreLaterale extends StatelessWidget {
  final List<_Onglet> onglets;
  final int indexActif;
  final ValueChanged<int> onOnglet;

  const _BarreLaterale({required this.onglets, required this.indexActif, required this.onOnglet});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final user = context.select((AuthBloc b) => b.state.utilisateur);

    return Container(
      width: _largeurRail,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Image.asset('assets/images/logo-widjila.png', height: 56),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < onglets.length; i++)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: _ItemRail(
                  onglet: onglets[i],
                  actif: i == indexActif,
                  onTap: () => onOnglet(i),
                ),
              ),
            const Spacer(),
            if (user != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: AppColors.primary,
                      child: Text(
                        user.initiales,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.nomComplet,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            user.role.label(l10n),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.push(AppRoutes.notifications),
                    icon: const Icon(Icons.notifications_none_rounded),
                    color: AppColors.textMuted,
                  ),
                  IconButton(
                    onPressed: () => context.push(AppRoutes.parametres),
                    icon: const Icon(Icons.settings_outlined),
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une ligne du rail : meme grammaire visuelle que l'onglet de la barre du
/// bas, mais disposee horizontalement (icone puis libelle) et surlignee par
/// une pastille pleine plutot que par la seule couleur du texte.
class _ItemRail extends StatelessWidget {
  final _Onglet onglet;
  final bool actif;
  final VoidCallback onTap;

  const _ItemRail({required this.onglet, required this.actif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: actif ? AppColors.primary100 : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Icon(
                actif ? onglet.iconActif : onglet.icon,
                size: 21,
                color: actif ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  onglet.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: actif ? FontWeight.w800 : FontWeight.w600,
                    color: actif ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  BARRE DE NAVIGATION
// ─────────────────────────────────────────────────────────────────────────────

class _BarreNavigation extends StatelessWidget {
  final List<_Onglet> onglets;
  final int indexActif;
  final bool avecFab;

  final ValueChanged<int> onOnglet;
  final VoidCallback onFab;

  const _BarreNavigation({
    required this.onglets,
    required this.indexActif,
    required this.avecFab,
    required this.onOnglet,
    required this.onFab,
  });

  @override
  Widget build(BuildContext context) {
    final basSecurise = MediaQuery.paddingOf(context).bottom;

    // Le bouton déborde de la barre : le Stack ne doit pas le rogner, et sa
    // moitié haute reste cliquable grâce au SizedBox surdimensionné.
    return SizedBox(
      height: _hauteurBarre + basSecurise + _diametreFab / 2,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            height: _hauteurBarre + basSecurise,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            padding: EdgeInsets.only(bottom: basSecurise),
            child: Row(
              children: [
                for (var i = 0; i < onglets.length; i++) ...[
                  // Espace réservé au bouton central, au milieu des onglets.
                  if (avecFab && i == onglets.length ~/ 2) const SizedBox(width: _diametreFab + 22),
                  Expanded(
                    child: _ItemOnglet(
                      onglet: onglets[i],
                      actif: i == indexActif,
                      onTap: () => onOnglet(i),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (avecFab)
            Positioned(
              bottom: basSecurise + _hauteurBarre - _diametreFab / 2 - 6,
              child: _BoutonPlus(onTap: onFab),
            ),
        ],
      ),
    );
  }
}

class _ItemOnglet extends StatelessWidget {
  final _Onglet onglet;
  final bool actif;
  final VoidCallback onTap;

  const _ItemOnglet({required this.onglet, required this.actif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final couleur = actif ? AppColors.primary : AppColors.textMuted;

    return InkResponse(
      onTap: onTap,
      radius: 42,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Barre-témoin au-dessus de l'onglet actif : c'est elle qui répond
          // à « on doit savoir qu'on est au niveau de Accueil ».
          //
          // `easeOutBack` (et non `easeOutCubic`) : la barre dépasse très
          // légèrement sa largeur finale avant de se caler. Ce micro-rebond
          // est ce qui fait lire le changement comme un GESTE plutôt que
          // comme un simple redimensionnement.
          AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            height: 3,
            width: actif ? 22 : 0,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 7),
          // Deux animations superposées sur l'icône :
          //  - un rebond d'échelle (le geste) ;
          //  - un FONDU CROISÉ entre la version contour et la version pleine.
          //    Sans lui, l'icône changeait de forme d'une frame à l'autre au
          //    milieu d'une animation par ailleurs fluide — la rupture la plus
          //    visible de toute la barre.
          AnimatedScale(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutBack,
            scale: actif ? 1.12 : 1.0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (enfant, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: enfant),
              ),
              child: Icon(
                actif ? onglet.iconActif : onglet.icon,
                // La clé porte l'ÉTAT : c'est elle qui dit à l'AnimatedSwitcher
                // qu'il s'agit d'une icône différente à faire transiter.
                key: ValueKey(actif),
                size: 22,
                color: couleur,
              ),
            ),
          ),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              fontSize: 11,
              fontWeight: actif ? FontWeight.w700 : FontWeight.w500,
              color: couleur,
            ),
            child: Text(onglet.label, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// Bouton central de la barre — il ouvre le parcours de création d'une
/// réserve.
///
/// Il tournait de 45° pour devenir une croix : il DÉPLOYAIT alors un éventail,
/// et la croix disait comment le refermer. Il ouvre désormais un sélecteur de
/// chantier par-dessus l'écran ; tourner ne promettrait plus rien — au
/// contraire, cela suggérerait qu'un second appui referme quelque chose, alors
/// que le bouton est déjà caché sous la feuille.
class _BoutonPlus extends StatelessWidget {
  final VoidCallback onTap;
  const _BoutonPlus({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _diametreFab,
        height: _diametreFab,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryLight, AppColors.primary],
          ),
          border: Border.all(color: Colors.white, width: 4),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.45),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
    );
  }
}
