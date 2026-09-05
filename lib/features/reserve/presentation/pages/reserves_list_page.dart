import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../cubit/reserves_list_cubit.dart';
import '../cubit/reserves_list_state.dart';
import '../widgets/reserve_card.dart';
import '../widgets/reserves_chrome.dart';
import '../../../../core/network/forcer_reseau.dart';

/// Réserves d'UN chantier.
///
/// Même écran que l'onglet transversal « Réserves » à une échelle près : même
/// en-tête, même barre de recherche, mêmes puces de statut avec compteurs,
/// même état vide illustré. Toutes ces pièces viennent de `reserves_chrome`
/// et de `liste_chrome` — la page n'ajoute que ce qui lui est propre : la
/// flèche de retour et le bouton de création, ce dernier n'ayant pas lieu
/// d'être dans l'onglet (où le « + » de la barre du bas s'en charge).
class ReservesListPage extends StatelessWidget {
  final String chantierId;
  const ReservesListPage({super.key, required this.chantierId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ReservesListCubit>(param1: chantierId)..charger(),
      child: _ReservesListView(chantierId: chantierId),
    );
  }
}

class _ReservesListView extends StatefulWidget {
  final String chantierId;
  const _ReservesListView({required this.chantierId});

  @override
  State<_ReservesListView> createState() => _ReservesListViewState();
}

class _ReservesListViewState extends State<_ReservesListView> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_surScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_surScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Pagination à l'approche du bas — 300 px d'avance, comme l'onglet
  /// transversal, pour que la page suivante soit déjà là à l'arrivée.
  void _surScroll() {
    if (!_scrollCtrl.hasClients) return;
    final position = _scrollCtrl.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      context.read<ReservesListCubit>().chargerPageSuivante();
    }
  }

  Future<void> _creerReserve() async {
    final cree = await context.push<bool>('/chantiers/${widget.chantierId}/reserves/nouvelle');
    if (cree == true && mounted && context.mounted) {
      context.read<ReservesListCubit>().charger();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Le serveur réserve la création aux rôles RESERVE_INTERVENANTS : proposer
    // le bouton aux autres serait promettre une action qui reviendra en 403.
    final peutCreer = context.select(
      (AuthBloc b) => b.state.utilisateur?.role.peutIntervenirSurReserves ?? false,
    );

    return Scaffold(
      // Blanc, comme la maquette. La LISTE, elle, repose sur le gris de fond
      // (voir _Liste) : des cartes blanches sur une page blanche perdraient
      // tout relief.
      backgroundColor: AppColors.surface,
      floatingActionButton: peutCreer
          ? FloatingActionButton(
              onPressed: _creerReserve,
              backgroundColor: AppColors.primary,
              elevation: 6,
              shape: const CircleBorder(),
              tooltip: l10n.reserveCreerBouton,
              child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ContenuCentre(
              child: EnTeteListe(
                titre: l10n.navReserves,
                avecRetour: true,
                // Écran plein hors coquille : pas de NotificationsCubit ici.
                avecCloche: false,
              ),
            ),
            BarreRechercheReserves(
              onRecherche: (v) => context.read<ReservesListCubit>().rechercher(v),
              filtreCourant: context.select((ReservesListCubit c) => c.state.filtreStatut),
              onFiltre: (statut) => context.read<ReservesListCubit>().filtrerParStatut(statut),
            ),
            const _RangeeFiltres(),
            Expanded(
              child: BlocBuilder<ReservesListCubit, ReservesListState>(
                builder: (context, state) {
                  switch (state.status) {
                    case ReservesListStatus.initial:
                    case ReservesListStatus.chargement:
                      return const LoadingList();
                    case ReservesListStatus.erreur:
                      return ErrorView(
                        message: state.erreur ?? l10n.commonErrorUnknown,
                        onRetry: () => context.read<ReservesListCubit>().charger(),
                      );
                    case ReservesListStatus.succes:
                      if (state.items.isEmpty) {
                        return _EtatVide(
                          filtreActif: state.recherche.isNotEmpty || state.filtreStatut != null,
                          peutCreer: peutCreer,
                          onCreer: _creerReserve,
                        );
                      }
                      return _Liste(state: state, controller: _scrollCtrl);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeeFiltres extends StatelessWidget {
  const _RangeeFiltres();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReservesListCubit, ReservesListState>(
      buildWhen: (a, b) => a.filtreStatut != b.filtreStatut || a.statutsCount != b.statutsCount,
      builder: (context, state) {
        return RangeeFiltresReserve(
          filtreCourant: state.filtreStatut,
          // Répartition calculée par le back pour CE chantier
          // (`GET /dashboard/chantiers/:id`) : chaque puce annonce son propre
          // volume, là où le `total` de la liste ne décrit que le filtre actif.
          statutsCount: state.statutsCount,
          onChoix: (statut) => context.read<ReservesListCubit>().filtrerParStatut(statut),
        );
      },
    );
  }
}

class _EtatVide extends StatelessWidget {
  final bool filtreActif;
  final bool peutCreer;
  final VoidCallback onCreer;

  const _EtatVide({required this.filtreActif, required this.peutCreer, required this.onCreer});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (filtreActif) {
      // Recherche ou filtre en cours : pas de bouton de création, ce n'est
      // pas ce que l'utilisateur cherche à faire à cet instant.
      return EtatVideIllustre(
        motif: MotifVide.recherche,
        titre: l10n.commonNoResults,
        description: l10n.reserveAucuneCriteres,
      );
    }

    return EtatVideIllustre(
      motif: MotifVide.reserve,
      titre: l10n.reserveAucune,
      description: peutCreer ? l10n.reserveCreerPremiere : l10n.reserveAucuneDescription,
      cta: peutCreer
          ? BoutonAction(icon: Icons.add_rounded, label: l10n.reserveCreerBouton, onTap: onCreer)
          : null,
    );
  }
}

class _Liste extends StatelessWidget {
  final ReservesListState state;
  final ScrollController controller;

  const _Liste({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: forcerReseau(() => context.read<ReservesListCubit>().charger()),
        child: ContenuCentre(
          child: ListView.separated(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
            // +1 pour le pied de page, +1 de plus pendant le chargement d'une
            // page supplémentaire.
            itemCount: state.items.length + 1 + (state.chargementPage ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i < state.items.length) {
                final reserve = state.items[i];
                return ReserveCard(
                  reserve: reserve,
                  onTap: () => context.push('/reserves/${reserve.id}'),
                );
              }
              if (state.chargementPage && i == state.items.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                );
              }
              return _PiedDeListe(affiches: state.items.length, total: state.total);
            },
          ),
        ),
      ),
    );
  }
}

/// Pied de liste — rappelle combien de réserves sont affichées sur le total.
///
/// La liste est paginée : sans ce repère, rien ne distingue « j'ai tout vu »
/// de « il en reste, continuez de faire défiler ».
class _PiedDeListe extends StatelessWidget {
  final int affiches;
  final int total;

  const _PiedDeListe({required this.affiches, required this.total});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_note_rounded, size: 16, color: AppColors.textMuted.withValues(alpha: 0.8)),
          const SizedBox(width: 8),
          // `Flexible` et non un `Text` nu : la phrase traduite débordait de
          // 106 px à 320 dp, 66 px à 360 et 36 px à 390 — c'est-à-dire sur la
          // quasi-totalité du parc. Un `Row` dont un enfant n'a pas
          // l'autorisation de rétrécir échoue à la mise en page, et Flutter
          // lève À CHAQUE IMAGE : la zone se dégrade alors même que les
          // réserves sont bien arrivées du serveur.
          Flexible(
            child: Text(
              context.l10n.reserveAffichageSur(affiches, total),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}
