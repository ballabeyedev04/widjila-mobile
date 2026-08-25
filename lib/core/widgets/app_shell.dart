import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../config/user_role.dart';
import '../routes/app_router.dart';
import '../theme/app_colors.dart';
import '../../features/auth/presentation/bloc/auth_bloc.dart';
import '../../features/notification/presentation/cubit/notifications_cubit.dart';
import '../../injection_container.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/l10n_extension.dart';
import 'chantier_picker_sheet.dart';
import 'eventail_actions.dart';

/// Un onglet de la barre. [prefixes] liste TOUTES les routes qui doivent
/// allumer cet onglet — pas seulement sa destination : « Plus » reste
/// surligné quand on est sur Chantiers ou Équipe, qui sont ses sous-écrans.
typedef _Onglet = ({
  String route,
  List<String> prefixes,
  IconData icon,
  IconData iconActif,
  String label,

  /// L'onglet ouvre un éventail au lieu de naviguer. C'est le cas de
  /// « Plus » : son ancienne page n'était qu'une liste de raccourcis, un
  /// écran de plus à traverser pour arriver où l'on voulait aller.
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
const double _seuilTablette = 700;
const double _largeurRail = 200;

/// Coquille applicative — barre de navigation basse et bouton d'action
/// central, conformément à la maquette Widjila (proposition 4).
///
/// La barre n'utilise pas `NavigationBar` de Material : la maquette impose un
/// bouton flottant AU MILIEU de la barre, qui déborde vers le haut et ouvre un
/// éventail d'actions. Aucun composant Material ne fait ça — d'où une barre
/// dessinée à la main, qui garde en revanche les mêmes règles de rôle que le
/// reste de l'app (voir [_actionsPourRole]).
class AppShell extends StatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _menuOuvert = false;

  /// Posée sur l'onglet « Plus » pour mesurer sa position à l'ouverture du
  /// menu (voir [_ouvrirMenuPlus]).
  final _clePlus = GlobalKey();

  /// Dernier onglet affiché — sert à donner un SENS à la transition entre
  /// pages : aller vers un onglet situé à droite fait glisser la nouvelle
  /// page depuis la droite, et inversement. Sans cette mémoire, toutes les
  /// transitions partiraient du même côté et l'animation ne dirait plus rien
  /// du déplacement réel dans la barre.
  int _indexPrecedent = 0;

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
          prefixes: [AppRoutes.plus, AppRoutes.chantiers, AppRoutes.equipe, AppRoutes.intervenants, AppRoutes.profil],
          icon: Icons.more_horiz_rounded,
          iconActif: Icons.more_horiz_rounded,
          label: l10n.navPlus,
          estMenu: true,
        ),
      ];

  /// Accès rapides du bouton « + », filtrés par rôle — mêmes règles que les
  /// `requireRole` du back, pour ne jamais proposer un raccourci que le
  /// serveur refuserait :
  ///
  ///  - tableau de bord chantier : aucun `requireRole` côté serveur (voir
  ///    `backend/src/modules/dashboard/route/dashboard.route.js`), ouvert à
  ///    tous ;
  ///  - équipe : GESTION, d'où `peutGererOrganisation` — même condition que
  ///    l'entrée « Équipe » du portail « Plus » ;
  ///  - document : OPERATIONNEL_CONTROLE.
  ///
  /// Ni réserve ni plan ici : les deux ont déjà leur onglet dans la barre du
  /// bas, et les voir une seconde fois dans l'éventail donnait l'impression
  /// d'un doublon.
  List<ActionRapide> _actionsPourRole(UserRole? role, AppLocalizations l10n) {
    if (role == null) return const [];
    return [
      (
        icon: Icons.insights_rounded,
        label: l10n.actionTableauBordChantier,
        couleur: AppColors.primary,
        besoinChantier: true,
        dansCoquille: false,
        route: (String? id) => '/chantiers/$id/tableau-de-bord',
      ),
      if (role.peutGererOrganisation)
        (
          icon: Icons.groups_rounded,
          label: l10n.actionEquipe,
          couleur: AppColors.accentDark,
          // Transversale à l'organisation : aucun chantier à choisir.
          besoinChantier: false,
          dansCoquille: true,
          route: (String? _) => AppRoutes.equipe,
        ),
      if (role.estOperationnelOuControle)
        (
          icon: Icons.folder_open_rounded,
          label: l10n.actionDocument,
          couleur: AppColors.success,
          besoinChantier: true,
          dansCoquille: false,
          route: (String? id) => '/chantiers/$id/documents',
        ),
    ];
  }

  /// Entrées de l'onglet « Plus ».
  ///
  /// Deux seulement, et vérifiées contre le reste de la navigation pour
  /// éviter les doublons : « Chantiers » et « Intervenants » n'apparaissent
  /// nulle part ailleurs. « Équipe », qui figurait autrefois à la fois ici et
  /// dans l'éventail du bouton « + », ne reste que dans ce dernier ; « Mon
  /// profil » a rejoint le menu de l'en-tête du tableau de bord.
  ///
  /// Aucun filtre de rôle : les deux écrans sont en lecture, et leurs routes
  /// côté serveur n'exigent aucun rôle particulier.
  List<ActionRapide> _entreesPlus(AppLocalizations l10n) => [
        (
          icon: Icons.construction_rounded,
          label: l10n.actionChantiers,
          couleur: AppColors.primary,
          besoinChantier: false,
          dansCoquille: true,
          route: _versChantiers,
        ),
        (
          icon: Icons.handshake_rounded,
          label: l10n.actionIntervenants,
          couleur: AppColors.info,
          besoinChantier: false,
          dansCoquille: true,
          route: _versIntervenants,
        ),
      ];

  // Fonctions nommées et non lambdas : une liste `const` n'accepte pas de
  // fermeture créée à la volée.
  static String _versChantiers(String? _) => AppRoutes.chantiers;
  static String _versIntervenants(String? _) => AppRoutes.intervenants;

  int _indexActif(String location, List<_Onglet> onglets) {
    for (var i = 0; i < onglets.length; i++) {
      if (onglets[i].prefixes.any(location.startsWith)) return i;
    }
    return 0;
  }

  /// Déploie un éventail et exécute l'action choisie.
  ///
  /// [ancrageX] décale le point de départ par rapport au centre de l'écran :
  /// nul pour le bouton « + », qui est centré, mesuré pour l'onglet « Plus »,
  /// dont l'éventail doit jaillir de sous SON bouton.
  Future<void> _ouvrirEventail(
    List<ActionRapide> actions, {
    double ancrageX = 0,
    List<double>? angles,
  }) async {
    if (actions.isEmpty) return;
    setState(() => _menuOuvert = true);
    final basSecurise = MediaQuery.paddingOf(context).bottom;

    final action = await showGeneralDialog<ActionRapide>(
      context: context,
      barrierDismissible: true,
      barrierLabel: context.l10n.actionsFermerLabel,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
      transitionBuilder: (context, animation, _, _) => EventailActions(
        animation: animation,
        actions: actions,
        distanceBas: basSecurise + _hauteurBarre - 6,
        ancrageX: ancrageX,
        angles: angles,
        onChoix: (choix) => Navigator.of(context).pop(choix),
        onFermeture: () => Navigator.of(context).pop(),
      ),
    );
    if (mounted) setState(() => _menuOuvert = false);
    if (action == null || !mounted) return;

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
    final chantier = await choisirChantier(context, titre: action.label);
    if (chantier == null || !mounted || !context.mounted) return;

    final destination = action.route(chantier.id);
    action.dansCoquille ? context.go(destination) : context.push(destination);
  }

  /// Ouvre le menu de l'onglet « Plus », ancré sous son bouton.
  ///
  /// La position est MESURÉE sur le rendu (`GlobalKey`) plutôt que recalculée
  /// à partir de la largeur d'écran et du nombre d'onglets : la barre change
  /// de répartition selon que le bouton « + » est présent ou non, et une
  /// formule dupliquée ici dériverait au premier ajustement de la barre.
  void _ouvrirMenuPlus() {
    final boite = _clePlus.currentContext?.findRenderObject() as RenderBox?;
    final largeur = MediaQuery.sizeOf(context).width;

    var ancrage = 0.0;
    if (boite != null) {
      final centreOnglet = boite.localToGlobal(Offset.zero).dx + boite.size.width / 2;
      ancrage = centreOnglet - largeur / 2;
    }

    // Sens de deploiement dicte par la position du bouton :
    //  - barre du bas : « Plus » est colle au bord DROIT, arc vers le
    //    haut-gauche, sinon la moitie des pastilles sort de l'ecran ;
    //  - rail lateral : « Plus » est a GAUCHE, arc symetrique vers le
    //    haut-droit, pour la meme raison.
    final surRail = largeur >= _seuilTablette;
    _ouvrirEventail(
      _entreesPlus(context.l10n),
      ancrageX: ancrage,
      angles: surRail ? const [30.0, 80.0] : const [150.0, 100.0],
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = context.select((AuthBloc b) => b.state.utilisateur?.role);
    final l10n = context.l10n;
    final actions = _actionsPourRole(role, l10n);
    final onglets = _onglets(l10n);
    final location = GoRouterState.of(context).matchedLocation;
    final index = _indexActif(location, onglets);

    // Sens du glissement : +1 vers la droite (onglet plus loin dans la barre),
    // -1 vers la gauche. Écrit ici sans `setState` — cette mémoire ne doit
    // JAMAIS déclencher de reconstruction, elle ne fait qu'accompagner celle
    // qui a déjà lieu.
    final sens = index >= _indexPrecedent ? 1.0 : -1.0;
    _indexPrecedent = index;

    // Un SEUL cubit de notifications pour toute la coquille : la cloche de
    // chaque onglet, celle du tableau de bord et l'écran Notifications lisent
    // ainsi le même compteur. Le fournir par écran ferait diverger les
    // pastilles entre onglets après un « tout marquer comme lu ».
    final contenu = _TransitionOnglet(sens: sens, cle: location, child: widget.child);
    void ouvrirOnglet(int i) =>
        onglets[i].estMenu ? _ouvrirMenuPlus() : context.go(onglets[i].route);

    // Le seuil est lu ICI et non dans un widget enfant : la coquille change de
    // structure (Row + rail contre body + barre basse), pas seulement de
    // style. Un LayoutBuilder plus bas ne verrait que la zone deja amputee du
    // rail, et ne pourrait donc plus decider de sa propre existence.
    final estTablette = MediaQuery.sizeOf(context).width >= _seuilTablette;

    return BlocProvider<NotificationsCubit>(
      create: (_) => sl<NotificationsCubit>()..charger(),
      child: estTablette
          ? Scaffold(
              body: Row(
                children: [
                  _BarreLaterale(
                    onglets: onglets,
                    indexActif: index,
                    clePlus: _clePlus,
                    onOnglet: ouvrirOnglet,
                  ),
                  Expanded(child: contenu),
                ],
              ),
              // Sur tablette le « + » quitte la barre (il n'y en a plus) pour
              // le coin bas-droit du contenu.
              floatingActionButton: actions.isEmpty
                  ? null
                  : FloatingActionButton(
                      onPressed: () => _ouvrirEventail(actions),
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 6,
                      child: AnimatedRotation(
                        turns: _menuOuvert ? 0.125 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.add_rounded, size: 28),
                      ),
                    ),
            )
          : Scaffold(
              body: contenu,
              bottomNavigationBar: _BarreNavigation(
                onglets: onglets,
                indexActif: index,
                avecFab: actions.isNotEmpty,
                fabOuvert: _menuOuvert,
                clePlus: _clePlus,
                onOnglet: ouvrirOnglet,
                onFab: () => _ouvrirEventail(actions),
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
  final GlobalKey clePlus;
  final ValueChanged<int> onOnglet;

  const _BarreLaterale({
    required this.onglets,
    required this.indexActif,
    required this.clePlus,
    required this.onOnglet,
  });

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
                  key: onglets[i].estMenu ? clePlus : null,
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
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
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

  const _ItemRail({
    super.key,
    required this.onglet,
    required this.actif,
    required this.onTap,
  });

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
//  TRANSITION ENTRE ONGLETS
// ─────────────────────────────────────────────────────────────────────────────

/// Anime le passage d'un onglet à l'autre : fondu croisé + glissement
/// horizontal dans le SENS du déplacement dans la barre.
///
/// ## Pourquoi ce widget plutôt que les transitions de `go_router`
///
/// Les onglets vivent dans une `ShellRoute` : go_router remplace simplement le
/// `child` de la coquille, sans pousser de nouvelle page — il n'y a donc
/// aucune transition de route à configurer, et le contenu changeait
/// brutalement d'une frame à l'autre.
///
/// ## Réglages
///
///  - **250 ms** : au-delà, une navigation entre onglets — geste répété des
///    dizaines de fois par jour — commence à se faire attendre ;
///  - **glissement de 4 %** de la largeur seulement : l'intention est de
///    suggérer la direction, pas de faire défiler l'écran. Un décalage franc
///    donnerait un carrousel, et rendrait chaque aller-retour fatigant ;
///  - `easeOutCubic` à l'entrée, `easeInCubic` à la sortie : la page qui
///    arrive décélère (elle « se pose »), celle qui part accélère.
class _TransitionOnglet extends StatelessWidget {
  /// +1 : le nouvel onglet est à DROITE du précédent, la page entre par la
  /// droite. -1 : l'inverse.
  final double sens;

  /// Identifie la page courante. Un changement de valeur déclenche
  /// l'animation — d'où la route, et non l'index d'onglet : deux écrans
  /// différents rattachés au MÊME onglet (par exemple la liste des chantiers
  /// et le détail d'un chantier, tous deux sous « Plus ») doivent eux aussi
  /// se succéder avec la transition.
  final String cle;

  final Widget child;

  const _TransitionOnglet({required this.sens, required this.cle, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      // Empilement en `expand` : la disposition par défaut d'AnimatedSwitcher
      // centre ses enfants et les laisse prendre leur taille intrinsèque, ce
      // qui casse la mise en page d'un écran plein (listes, Scaffold internes)
      // pendant toute la durée de l'animation.
      layoutBuilder: (courant, precedents) => Stack(
        fit: StackFit.expand,
        children: [
          ...precedents,
          ?courant,
        ],
      ),
      transitionBuilder: (enfant, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0.04 * sens, 0),
              end: Offset.zero,
            ).animate(animation),
            child: enfant,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey(cle), child: child),
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
  final bool fabOuvert;

  /// Clé posée sur l'onglet « Plus » : elle sert à mesurer sa position pour
  /// y ancrer l'éventail.
  final GlobalKey clePlus;

  final ValueChanged<int> onOnglet;
  final VoidCallback onFab;

  const _BarreNavigation({
    required this.onglets,
    required this.indexActif,
    required this.avecFab,
    required this.fabOuvert,
    required this.clePlus,
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
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, -4)),
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
                      key: onglets[i].estMenu ? clePlus : null,
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
              child: _BoutonPlus(ouvert: fabOuvert, onTap: onFab),
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

  const _ItemOnglet({super.key, required this.onglet, required this.actif, required this.onTap});

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

class _BoutonPlus extends StatelessWidget {
  final bool ouvert;
  final VoidCallback onTap;
  const _BoutonPlus({required this.ouvert, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedRotation(
        // 45° : le « + » devient une croix quand l'éventail est déployé.
        turns: ouvert ? 0.125 : 0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
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
      ),
    );
  }
}
