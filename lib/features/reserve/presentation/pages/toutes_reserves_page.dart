import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/chantier_picker_sheet.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../cubit/reserves_list_state.dart';
import '../cubit/toutes_reserves_cubit.dart';
import '../widgets/reserve_card.dart';
import '../widgets/reserves_chrome.dart';

/// Écran 2 de la maquette — toutes les réserves de l'organisation.
class ToutesReservesPage extends StatelessWidget {
  const ToutesReservesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ToutesReservesCubit>()..charger(),
      child: const _ToutesReservesView(),
    );
  }
}

class _ToutesReservesView extends StatefulWidget {
  const _ToutesReservesView();

  @override
  State<_ToutesReservesView> createState() => _ToutesReservesViewState();
}

class _ToutesReservesViewState extends State<_ToutesReservesView> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_surScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_surScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// Pagination à l'approche du bas — 300 px d'avance pour que la page
  /// suivante soit déjà là quand l'utilisateur y arrive.
  void _surScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      context.read<ToutesReservesCubit>().chargerPageSuivante();
    }
  }

  /// Une réserve appartient toujours à un chantier : on le demande avant
  /// d'ouvrir le formulaire de création (voir chantier_picker_sheet).
  Future<void> _creerReserve() async {
    final chantier = await choisirChantier(context, titre: context.l10n.syncNomNouvelleReserve);
    if (chantier == null || !mounted) return;
    if (context.mounted) context.push('/chantiers/${chantier.id}/reserves/nouvelle');
  }

  @override
  Widget build(BuildContext context) {
    // Le serveur réserve la création aux rôles RESERVE_INTERVENANTS : proposer
    // le bouton aux autres serait promettre une action qui reviendra en 403.
    final peutCreer = context.select(
      (AuthBloc b) => b.state.utilisateur?.role.peutIntervenirSurReserves ?? false,
    );
    final l10n = context.l10n;

    return Scaffold(
      // Blanc, comme la maquette. La LISTE, elle, repose sur le gris de fond
      // (voir _Liste) : des cartes blanches sur une page blanche perdraient
      // tout relief.
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ContenuCentre(child: EnTeteListe(titre: l10n.navReserves)),
            BarreRechercheReserves(
              onRecherche: (v) => context.read<ToutesReservesCubit>().rechercher(v),
              filtreCourant: context.select((ToutesReservesCubit c) => c.state.filtreStatut),
              onFiltre: (statut) => context.read<ToutesReservesCubit>().filtrerParStatut(statut),
            ),
            const _RangeeFiltres(),
            Expanded(
              child: BlocBuilder<ToutesReservesCubit, ReservesListState>(
                builder: (context, state) {
                  switch (state.status) {
                    case ReservesListStatus.initial:
                    case ReservesListStatus.chargement:
                      return const LoadingList();
                    case ReservesListStatus.erreur:
                      return ErrorView(
                        message: state.erreur ?? l10n.commonErrorUnknown,
                        onRetry: () => context.read<ToutesReservesCubit>().charger(),
                      );
                    case ReservesListStatus.succes:
                      if (state.items.isEmpty) {
                        return _EtatVide(
                          filtreActif: state.recherche.isNotEmpty || state.filtreStatut != null,
                          peutCreer: peutCreer,
                          onCreer: _creerReserve,
                        );
                      }
                      return _Liste(state: state, controller: _scrollController);
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
        description: l10n.reserveEssayerAutreFiltre,
      );
    }

    return EtatVideIllustre(
      motif: MotifVide.reserve,
      titre: l10n.reserveAucune,
      description: l10n.reserveAucuneDescription,
      cta: peutCreer
          ? BoutonAction(
              icon: Icons.add_rounded,
              label: l10n.reserveCreerBouton,
              onTap: onCreer,
            )
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
        onRefresh: () => context.read<ToutesReservesCubit>().charger(),
        child: ContenuCentre(
          child: ListView.separated(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            // +1 pour le pied de page, +1 de plus pendant le chargement d'une
            // page supplémentaire.
            itemCount: state.items.length + 1 + (state.chargementPage ? 1 : 0),
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i < state.items.length) {
                final reserve = state.items[i];
                return ReserveCard(
                  reserve: reserve,
                  avecChantier: true,
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

class _RangeeFiltres extends StatelessWidget {
  const _RangeeFiltres();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ToutesReservesCubit, ReservesListState>(
      buildWhen: (a, b) => a.filtreStatut != b.filtreStatut || a.statutsCount != b.statutsCount,
      builder: (context, state) {
        return RangeeFiltresReserve(
          filtreCourant: state.filtreStatut,
          // Compteurs issus de `GET /dashboard` (répartition par statut sur
          // toute l'organisation), et non du `total` de la page courante :
          // chaque puce annonce ainsi son propre volume.
          statutsCount: state.statutsCount,
          onChoix: (statut) => context.read<ToutesReservesCubit>().filtrerParStatut(statut),
        );
      },
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
          Text(
            context.l10n.reserveAffichageSur(affiches, total),
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
