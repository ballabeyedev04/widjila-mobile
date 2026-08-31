import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/routes/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/entete_degrade.dart';
import '../../../../core/widgets/liste_chrome.dart' show PastilleCompteur;
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/fichier_image.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/bloc/auth_event.dart';
import '../../../notification/presentation/cubit/notifications_cubit.dart';
import '../../../chantier/domain/entities/chantier.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../chantier/presentation/widgets/chantier_statut_badge.dart';
import '../../../reserve/domain/entities/reserve.dart';
import '../../../reserve/presentation/cubit/reserves_list_state.dart';
import '../../../reserve/presentation/cubit/toutes_reserves_cubit.dart';
import '../../../reserve/presentation/widgets/reserve_card.dart';
import '../../../reserve/presentation/widgets/reserve_statut_donut.dart';
import '../../domain/entities/dashboard_stats.dart';
import '../cubit/dashboard_cubit.dart';
import '../cubit/dashboard_state.dart';
import '../widgets/derniers_plans.dart';

/// Largeur à partir de laquelle le tableau de bord bascule sur une mise en
/// page à deux colonnes (tablette / desktop) plutôt qu'empilée (téléphone).
const _seuilTablette = 700.0;

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => sl<DashboardCubit>()..charger()),
        // Bloc « Réserves récentes » — cinq éléments suffisent pour un
        // aperçu, inutile de rapatrier une page complète.
        BlocProvider(
          create: (_) => ToutesReservesCubit(
            getToutesReserves: sl(),
            getStatutsCountGlobal: sl(),
            limite: 5,
            // Aperçu sans puces de filtre : les compteurs par statut sont
            // déjà lus par le tableau de bord lui-même.
            avecCompteurs: false,
          )..charger(),
        ),
      ],
      child: const _DashboardView(),
    );
  }
}

class _DashboardView extends StatelessWidget {
  const _DashboardView();

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthBloc b) => b.state.utilisateur);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [_EnTeteTableauDeBord(user: user)],
        body: BlocBuilder<DashboardCubit, DashboardState>(
          builder: (context, state) {
            switch (state.status) {
              case DashboardStatus.initial:
              case DashboardStatus.chargement:
                return const Center(child: CircularProgressIndicator(color: AppColors.primary));
              case DashboardStatus.erreur:
                return ErrorView(
                  message: state.erreur ?? context.l10n.commonErrorUnknown,
                  onRetry: () => context.read<DashboardCubit>().charger(),
                );
              case DashboardStatus.succes:
                return _CorpsTableauDeBord(stats: state.stats!);
            }
          },
        ),
      ),
    );
  }
}

/// Hauteurs de l'en-tête : déployé en haut de page, réduit une fois la liste
/// défilée. L'écart entre les deux pilote l'animation de repli.
const double _enTeteDeploye = 218;
const double _enTeteReplie = 74;

/// Arrondi des angles inférieurs, en-tête déployé.
const double _rayonEnTete = 28;

/// En-tête du tableau de bord — identité de l'utilisateur (nom complet,
/// email et RÔLE), notifications et menu de compte. Toujours pas de
/// salutation « Bonjour ».
///
/// `expandedHeight` plutôt qu'une hauteur fixe : l'en-tête se replie
/// progressivement au défilement — la pastille de rôle s'efface, l'avatar se
/// réduit, les angles se redressent — et ne laisse qu'un bandeau compact. Un
/// bandeau figé de cette hauteur mangerait un tiers de l'écran d'un téléphone
/// pour n'afficher que des informations déjà lues.
class _EnTeteTableauDeBord extends StatelessWidget {
  final User? user;
  const _EnTeteTableauDeBord({required this.user});

  @override
  Widget build(BuildContext context) {
    final hautSecurise = MediaQuery.paddingOf(context).top;
    final hauteurMin = _enTeteReplie + hautSecurise;

    return SliverAppBar(
      pinned: true,
      // Transparent, et non `AppColors.primary` : la couleur de fond de la
      // `SliverAppBar` est peinte sur TOUTE la barre, angles compris, et
      // remplirait d'orange les coins que `EnteteDegrade` vient d'arrondir.
      // L'intégralité du fond est peinte par le `flexibleSpace`.
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      toolbarHeight: _enTeteReplie,
      expandedHeight: _enTeteDeploye,
      // Fond soutenu : les icônes de la barre d'état doivent passer en blanc.
      systemOverlayStyle: SystemUiOverlayStyle.light,
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          // 1 = totalement déployé, 0 = replié. Facteur d'animation commun à
          // l'opacité, à la taille de l'avatar et à l'arrondi des angles.
          final amplitude = (_enTeteDeploye + hautSecurise) - hauteurMin;
          final expansion = amplitude <= 0
              ? 0.0
              : ((constraints.maxHeight - hauteurMin) / amplitude).clamp(0.0, 1.0);
          return _ContenuEnTete(user: user, expansion: expansion);
        },
      ),
    );
  }
}

class _ContenuEnTete extends StatelessWidget {
  final User? user;
  final double expansion;

  const _ContenuEnTete({required this.user, required this.expansion});

  @override
  Widget build(BuildContext context) {
    return EnteteDegrade(
      rayonBas: _rayonEnTete * expansion,
      child: Stack(
        children: [
          // Contenu ancré en BAS : au repli, la ligne d'identité vient
          // naturellement se loger dans la barre compacte.
          //
          // La marge basse suit l'expansion : déployé, elle dégage la VAGUE
          // découpée par `EnteteDegrade` (dont le creux remonte jusqu'à ~26 px
          // du bas) pour que la pastille de rôle ne soit jamais rognée ;
          // replié, la vague est plate et 14 px suffisent.
          Positioned(
            left: 18,
            right: 12,
            bottom: 14 + 20 * expansion,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _Avatar(user: user, taille: 46.0 + 26.0 * expansion),
                SizedBox(width: 12 + 3 * expansion),
                Expanded(child: _BlocIdentite(user: user, expansion: expansion)),
                const SizedBox(width: 8),
                const _ActionsEnTete(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Nom, email, puis pastille de rôle — la pastille se rétracte au repli.
class _BlocIdentite extends StatelessWidget {
  final User? user;
  final double expansion;

  const _BlocIdentite({required this.user, required this.expansion});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          user?.nomComplet ?? '—',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 17.5 + 6 * expansion,
            letterSpacing: -0.5,
            height: 1.1,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(
          user?.email ?? '',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.86),
            fontSize: 12.5 + 1.5 * expansion,
            fontWeight: FontWeight.w400,
            height: 1.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        // `heightFactor` plutôt qu'un `if` : la pastille se rétracte en
        // douceur au lieu de disparaître d'un coup.
        ClipRect(
          child: Align(
            heightFactor: expansion,
            alignment: Alignment.topLeft,
            child: Opacity(
              opacity: expansion,
              child: Padding(
                padding: const EdgeInsets.only(top: 11),
                child: _PastilleRole(role: user?.role, fonction: user?.fonction),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Avatar — photo de profil si elle existe, initiales sinon.
///
/// Anneau blanc franc, comme la maquette : sur un dégradé orange soutenu,
/// c'est lui qui détache la pastille, là où un simple aplat translucide la
/// laissait se fondre dans le fond.
class _Avatar extends StatelessWidget {
  final User? user;
  final double taille;

  const _Avatar({required this.user, required this.taille});

  @override
  Widget build(BuildContext context) {
    final photo = user?.photoProfil;

    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.18),
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDarker.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(
        child: photo == null || photo.isEmpty
            ? Center(
                child: Text(
                  user?.initiales ?? '?',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: taille * 0.34,
                    letterSpacing: 0.5,
                  ),
                ),
              )
            : FichierImage(url: photo, width: taille, height: taille),
      ),
    );
  }
}

/// Pastille de rôle — pilule BLANCHE à texte orange, comme la maquette.
///
/// Le rôle détermine ce que l'utilisateur peut faire dans l'application :
/// l'afficher en permanence évite d'avoir à deviner pourquoi tel écran ou tel
/// bouton n'apparaît pas. La fonction déclarée, quand elle existe, la suit en
/// texte discret — c'est une saisie libre, elle ne mérite pas le même poids.
class _PastilleRole extends StatelessWidget {
  final UserRole? role;
  final String? fonction;

  const _PastilleRole({required this.role, required this.fonction});

  @override
  Widget build(BuildContext context) {
    if (role == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryDarker.withValues(alpha: 0.22),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(role!.icon, color: AppColors.primary, size: 16),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    role!.label(context.l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (fonction != null && fonction!.isNotEmpty) ...[
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              fonction!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Cloche et menu de compte, en pastilles translucides.
class _ActionsEnTete extends StatelessWidget {
  const _ActionsEnTete();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        _BoutonNotifications(),
        SizedBox(width: 8),
        _MenuCompte(),
      ],
    );
  }
}

/// Bouton rond translucide — base commune à la cloche et au menu.
class _BoutonRond extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _BoutonRond({required this.icon, required this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.20),
        shape: CircleBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.30))),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Center(child: Icon(icon, color: Colors.white, size: 21)),
          ),
        ),
      ),
    );
  }
}

/// Cloche de notifications.
///
/// La pastille rouge n'est PAS décorative : elle suit le compteur réel de
/// `GET /notifications/non-lues/count`. Sans notification en attente, aucun
/// point ne s'affiche — annoncer des messages inexistants ferait ouvrir une
/// liste vide.
class _BoutonNotifications extends StatelessWidget {
  const _BoutonNotifications();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NotificationsCubit, NotificationsState>(
      buildWhen: (a, b) => a.nonLues != b.nonLues,
      builder: (context, state) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            _BoutonRond(
              icon: Icons.notifications_none_rounded,
              tooltip: context.l10n.navNotifications,
              onTap: () => context.go(AppRoutes.notifications),
            ),
            if (state.nonLues > 0)
              Positioned(top: -2, right: -2, child: PastilleCompteur(nombre: state.nonLues)),
          ],
        );
      },
    );
  }
}

/// Menu de compte — profil et déconnexion.
///
/// C'est ici qu'a atterri « Mon profil » : l'onglet « Plus » de la barre du
/// bas n'ouvre plus une page mais un éventail à deux entrées (Chantiers,
/// Intervenants), et le profil n'aurait plus été atteignable nulle part.
class _MenuCompte extends StatelessWidget {
  const _MenuCompte();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<String>(
      tooltip: l10n.dashboardMenuTooltip,
      offset: const Offset(0, 50),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      onSelected: (choix) {
        switch (choix) {
          case 'profil':
            context.go(AppRoutes.profil);
          case 'parametres':
            context.go(AppRoutes.parametres);
          case 'deconnexion':
            context.read<AuthBloc>().add(const AuthLogoutRequested());
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'profil',
          child: Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 19, color: AppColors.textSecondary),
              const SizedBox(width: 11),
              Text(l10n.dashboardMonProfil, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'parametres',
          child: Row(
            children: [
              const Icon(Icons.settings_outlined, size: 19, color: AppColors.textSecondary),
              const SizedBox(width: 11),
              Text(l10n.dashboardParametres, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'deconnexion',
          child: Row(
            children: [
              const Icon(Icons.logout_rounded, size: 19, color: AppColors.danger),
              const SizedBox(width: 11),
              Text(
                l10n.profilDeconnexion,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.danger),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
        ),
        child: const Icon(Icons.menu_rounded, color: Colors.white, size: 21),
      ),
    );
  }
}

class _CorpsTableauDeBord extends StatelessWidget {
  final DashboardStats stats;
  const _CorpsTableauDeBord({required this.stats});

  @override
  Widget build(BuildContext context) {
    final role = context.select((AuthBloc b) => b.state.utilisateur?.role);

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => context.read<DashboardCubit>().charger(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final estTablette = constraints.maxWidth >= _seuilTablette;
          final padding = EdgeInsets.all(estTablette ? 24 : 16);

          if (!estTablette) {
            return ListView(
              padding: padding,
              children: [
                const _PhraseIntro(),
                const SizedBox(height: 18),
                _RangeeKpi(stats: stats),
                const SizedBox(height: 18),
                _CarteVueEnsemble(stats: stats),
                const SizedBox(height: 18),
                if (stats.parSeverite.values.any((v) => v > 0)) ...[
                  _CarteSeverite(stats: stats),
                  const SizedBox(height: 18),
                ],
                // Les huit derniers plans, entre la vue d'ensemble et
                // l'apercu general : l'ouverture la plus frequente de
                // l'application, jusqu'ici a deux ecrans de distance.
                const DerniersPlans(),
                _TitreSection(context.l10n.dashboardApercuGeneral),
                const SizedBox(height: 12),
                _GrilleApercu(stats: stats, role: role, colonnes: 2),
                const SizedBox(height: 18),
                const _ReservesRecentes(),
                if (stats.parChantier.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _TitreSection(context.l10n.dashboardVosChantiers),
                  const SizedBox(height: 12),
                  _ListeChantiers(chantiers: stats.parChantier),
                ],
              ],
            );
          }

          // ── Tablette / desktop : deux colonnes côte à côte ────────────────
          return SingleChildScrollView(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _PhraseIntro(),
                const SizedBox(height: 20),
                _RangeeKpi(stats: stats),
                const SizedBox(height: 20),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: _CarteVueEnsemble(stats: stats)),
                      if (stats.parSeverite.values.any((v) => v > 0)) ...[
                        const SizedBox(width: 18),
                        Expanded(flex: 4, child: _CarteSeverite(stats: stats)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const DerniersPlans(margeBas: 24),
                _TitreSection(context.l10n.dashboardApercuGeneral),
                const SizedBox(height: 12),
                _GrilleApercu(stats: stats, role: role, colonnes: 4),
                const SizedBox(height: 24),
                const _ReservesRecentes(),
                if (stats.parChantier.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  _TitreSection(context.l10n.dashboardVosChantiers),
                  const SizedBox(height: 12),
                  _ListeChantiers(chantiers: stats.parChantier, colonnes: 2),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Bloc « Réserves récentes » de la maquette (écran 1) — aperçu des cinq
/// dernières réserves, avec un raccourci vers l'onglet complet.
///
/// Alimenté par son propre [ToutesReservesCubit] : le tableau de bord ne
/// renvoie que des agrégats (compteurs, répartitions), pas la liste des
/// réserves elles-mêmes.
class _ReservesRecentes extends StatelessWidget {
  const _ReservesRecentes();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ToutesReservesCubit, ReservesListState>(
      builder: (context, state) {
        // Chargement/erreur : le bloc s'efface au lieu d'afficher un
        // squelette ou une erreur qui parasiterait le reste de l'accueil —
        // les chiffres du haut, eux, sont déjà là.
        if (state.status != ReservesListStatus.succes || state.items.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _TitreSection(context.l10n.dashboardReservesRecentes)),
                TextButton(
                  onPressed: () => context.go(AppRoutes.reserves),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(context.l10n.commonSeeAll, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final reserve in state.items) ...[
              ReserveCard(
                reserve: reserve,
                avecChantier: true,
                onTap: () => context.push('/reserves/${reserve.id}'),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _PhraseIntro extends StatelessWidget {
  const _PhraseIntro();

  @override
  Widget build(BuildContext context) {
    return Text(
      context.l10n.dashboardPhraseIntro,
      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
    );
  }
}

class _TitreSection extends StatelessWidget {
  final String texte;
  const _TitreSection(this.texte);

  @override
  Widget build(BuildContext context) {
    return Text(texte, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.textPrimary));
  }
}

/// Enveloppe carte commune — coins arrondis, ombre douce, jamais de bordure
/// dure. Un seul endroit à ajuster pour que toutes les cartes du tableau de
/// bord restent visuellement cohérentes entre elles.
class _Carte extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _Carte({required this.child, this.padding = const EdgeInsets.all(18)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.045), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: child,
    );
  }
}

/// Rangée de 4 pastilles KPI (total / ouvertes / levées / en retard) — même
/// info que l'ancienne version, présentation reprise avec badge icône coloré
/// plutôt qu'un simple chiffre nu.
class _RangeeKpi extends StatelessWidget {
  final DashboardStats stats;
  const _RangeeKpi({required this.stats});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = [
      (label: l10n.dashboardKpiTotal, valeur: stats.reserves.total, icone: Icons.inventory_2_outlined, couleur: AppColors.primary),
      (label: l10n.dashboardKpiOuvertes, valeur: stats.reserves.ouvertes, icone: Icons.hourglass_top_rounded, couleur: AppColors.warning),
      (label: l10n.dashboardKpiLevees, valeur: stats.reserves.validees, icone: Icons.check_circle_outline_rounded, couleur: AppColors.success),
      (label: l10n.statutEnRetard, valeur: stats.reserves.enRetard, icone: Icons.error_outline_rounded, couleur: AppColors.danger),
    ];

    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: _CarteKpi(item: items[i])),
        ],
      ],
    );
  }
}

class _CarteKpi extends StatelessWidget {
  final ({String label, int valeur, IconData icone, Color couleur}) item;
  const _CarteKpi({required this.item});

  @override
  Widget build(BuildContext context) {
    return _Carte(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: item.couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
            child: Icon(item.icone, size: 16, color: item.couleur),
          ),
          const SizedBox(height: 10),
          Text('${item.valeur}', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 1),
          Text(item.label, style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _CarteVueEnsemble extends StatelessWidget {
  final DashboardStats stats;
  const _CarteVueEnsemble({required this.stats});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.dashboardVueEnsemble, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
          Text(l10n.dashboardRepartitionParStatut, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 16),
          if (stats.reserves.total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(l10n.dashboardAucuneReserve, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ),
            )
          else
            ReserveStatutDonut(parStatut: stats.parStatut, total: stats.reserves.total),
        ],
      ),
    );
  }
}

// ── Répartition par sévérité — mini-barres horizontales ──────────────────
Color _couleurSeverite(ReserveSeverite s) {
  switch (s) {
    case ReserveSeverite.faible:
      return AppColors.info;
    case ReserveSeverite.moyenne:
      return AppColors.warning;
    case ReserveSeverite.haute:
    case ReserveSeverite.critique:
      return AppColors.danger;
  }
}

class _CarteSeverite extends StatelessWidget {
  final DashboardStats stats;
  const _CarteSeverite({required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = stats.parSeverite.values.fold<int>(0, (a, b) => a + b);
    final entrees = ReserveSeverite.values.map((s) => (s: s, n: stats.parSeverite[s] ?? 0)).toList();

    return _Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.dashboardParSeverite, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
          Text(context.l10n.dashboardToutesReservesConfondues, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 16),
          for (final e in entrees) ...[
            _LigneSeverite(severite: e.s, valeur: e.n, total: total),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _LigneSeverite extends StatelessWidget {
  final ReserveSeverite severite;
  final int valeur;
  final int total;
  const _LigneSeverite({required this.severite, required this.valeur, required this.total});

  @override
  Widget build(BuildContext context) {
    final couleur = _couleurSeverite(severite);
    final ratio = total == 0 ? 0.0 : valeur / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(severite.label(context.l10n), style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            ),
            Text('$valeur', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 7,
            backgroundColor: AppColors.neutralBg,
            valueColor: AlwaysStoppedAnimation(couleur),
          ),
        ),
      ],
    );
  }
}

/// Grille des compteurs secondaires — Chantiers, Inspections, Plans,
/// Documents, Utilisateurs. `colonnes` varie selon la largeur disponible
/// (téléphone : 2, tablette : 4).
class _GrilleApercu extends StatelessWidget {
  final DashboardStats stats;
  final UserRole? role;
  final int colonnes;
  const _GrilleApercu({required this.stats, required this.role, required this.colonnes});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final peutGererEquipe = role?.peutGererMembres ?? false;

    final items = [
      (
        icone: Icons.construction_outlined,
        label: l10n.actionChantiers,
        valeur: stats.chantiers,
        couleur: AppColors.primary,
        onTap: () => context.go(AppRoutes.chantiers),
      ),
      (icone: Icons.fact_check_outlined, label: l10n.dashboardApercuInspections, valeur: stats.inspections, couleur: AppColors.info, onTap: null),
      (icone: Icons.map_outlined, label: l10n.navPlans, valeur: stats.plans, couleur: AppColors.accent, onTap: null),
      (icone: Icons.folder_outlined, label: l10n.dashboardApercuDocuments, valeur: stats.documents, couleur: AppColors.success, onTap: null),
      (
        icone: Icons.groups_outlined,
        label: l10n.dashboardApercuMembres,
        valeur: stats.utilisateurs,
        couleur: AppColors.accentDark,
        onTap: peutGererEquipe ? () => context.go(AppRoutes.equipe) : null,
      ),
    ];

    return GridView.count(
      crossAxisCount: colonnes,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: colonnes >= 4 ? 1.15 : 1.5,
      children: [for (final it in items) _CarteApercu(item: it)],
    );
  }
}

class _CarteApercu extends StatelessWidget {
  final ({IconData icone, String label, int valeur, Color couleur, VoidCallback? onTap}) item;
  const _CarteApercu({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: item.onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.045), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: item.couleur.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
                child: Icon(item.icone, color: item.couleur, size: 19),
              ),
              const Spacer(),
              Text('${item.valeur}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              Text(item.label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aperçu des chantiers de l'organisation — chiffres du back
/// (`stats.parChantier`), barre de progression = réserves levées / total.
class _ListeChantiers extends StatelessWidget {
  final List<DashboardChantierResume> chantiers;
  final int colonnes;
  const _ListeChantiers({required this.chantiers, this.colonnes = 1});

  @override
  Widget build(BuildContext context) {
    final visibles = chantiers.take(6).toList();
    if (colonnes == 1) {
      return Column(
        children: [
          for (final c in visibles) ...[
            _CarteChantier(chantier: c),
            const SizedBox(height: 10),
          ],
        ],
      );
    }
    return GridView.count(
      crossAxisCount: colonnes,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.8,
      children: [for (final c in visibles) _CarteChantier(chantier: c)],
    );
  }
}

/// Couleur du statut — DÉRIVÉE de la table des pastilles.
///
/// Elle était recopiée ici, et avait déjà pris du retard : les deux statuts
/// du circuit de validation y manquaient. Une seule table fait foi.
Color _couleurStatutChantier(ChantierStatut s) => toneStatutChantier(s).fg;

class _CarteChantier extends StatelessWidget {
  final DashboardChantierResume chantier;
  const _CarteChantier({required this.chantier});

  @override
  Widget build(BuildContext context) {
    final couleur = _couleurStatutChantier(chantier.statut);
    final ratio = chantier.reservesTotal == 0
        ? 0.0
        : (chantier.reservesTotal - chantier.reservesOuvertes) / chantier.reservesTotal;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/chantiers/${chantier.id}'),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.045), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: Row(
            children: [
              Container(width: 4, height: 40, decoration: BoxDecoration(color: couleur, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      chantier.nom,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 6,
                        backgroundColor: AppColors.neutralBg,
                        valueColor: AlwaysStoppedAnimation(couleur),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${chantier.reservesOuvertes}/${chantier.reservesTotal}',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
