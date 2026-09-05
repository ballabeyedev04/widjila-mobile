import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/chantier.dart';
import '../cubit/chantiers_list_cubit.dart';
import '../cubit/chantiers_list_state.dart';
import '../widgets/chantier_statut_badge.dart';
import '../../../../core/network/forcer_reseau.dart';

/// Liste des chantiers — même armature que les onglets Réserves et Plans :
/// en-tête de la maquette, barre de recherche arrondie, puces de filtre à
/// compteurs, état vide illustré, cartes blanches sur le gris de fond.
class ChantiersListPage extends StatelessWidget {
  const ChantiersListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      // `chargerCompteurs()` en plus de `charger()` : la liste vient de
      // `GET /chantiers` (paginée), les compteurs des puces de
      // `GET /dashboard`. Deux sources, lancées ensemble.
      create: (_) => sl<ChantiersListCubit>()
        ..charger()
        ..chargerCompteurs(),
      child: const _ChantiersListView(),
    );
  }
}

class _ChantiersListView extends StatefulWidget {
  const _ChantiersListView();

  @override
  State<_ChantiersListView> createState() => _ChantiersListViewState();
}

class _ChantiersListViewState extends State<_ChantiersListView> {
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

  /// Pagination à l'approche du bas — 300 px d'avance, comme Réserves.
  void _surScroll() {
    if (!_scrollCtrl.hasClients) return;
    final position = _scrollCtrl.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      context.read<ChantiersListCubit>().chargerPageSuivante();
    }
  }

  @override
  Widget build(BuildContext context) {
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
            // Écran de la coquille : la barre du bas assure le retour, et le
            // NotificationsCubit de la coquille alimente bien la cloche.
            ContenuCentre(child: EnTeteListe(titre: l10n.actionChantiers)),
            const _BarreRecherche(),
            const _RangeeFiltres(),
            Expanded(
              child: BlocBuilder<ChantiersListCubit, ChantiersListState>(
                builder: (context, state) {
                  switch (state.status) {
                    case ChantiersListStatus.initial:
                    case ChantiersListStatus.chargement:
                      return const LoadingList(itemHeight: 104);
                    case ChantiersListStatus.erreur:
                      return ErrorView(
                        message: state.erreur ?? l10n.commonErrorUnknown,
                        onRetry: () => context.read<ChantiersListCubit>().charger(),
                      );
                    case ChantiersListStatus.succes:
                      if (state.items.isEmpty) {
                        // Distinguer « aucun chantier » de « aucun résultat » :
                        // le premier renvoie vers l'administration, le second
                        // demande simplement d'élargir la recherche.
                        return EtatVideIllustre(
                          motif: state.filtreEnPlace ? MotifVide.recherche : MotifVide.chantier,
                          titre: state.filtreEnPlace ? l10n.commonNoResults : l10n.chantierAucun,
                          description: state.filtreEnPlace
                              ? l10n.chantierAucunRecherche
                              : l10n.chantierAucunSousTitre,
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

/// Barre de recherche arrondie + bouton « Filtrer » — même dessin que celle
/// des réserves et des plans.
class _BarreRecherche extends StatefulWidget {
  const _BarreRecherche();

  @override
  State<_BarreRecherche> createState() => _BarreRechercheState();
}

class _BarreRechercheState extends State<_BarreRecherche> {
  final _controleur = TextEditingController();

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ContenuCentre(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controleur,
                textInputAction: TextInputAction.search,
                onChanged: (v) => context.read<ChantiersListCubit>().rechercher(v),
                decoration: InputDecoration(
                  hintText: l10n.chantierPickerRechercheHint,
                  prefixIcon: const Icon(Icons.search_rounded, size: 21, color: AppColors.textMuted),
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controleur,
                    builder: (context, valeur, _) {
                      if (valeur.text.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                        tooltip: l10n.chantierPickerEffacer,
                        onPressed: () {
                          _controleur.clear();
                          context.read<ChantiersListCubit>().rechercher('');
                        },
                      );
                    },
                  ),
                  filled: true,
                  fillColor: AppColors.background,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const _BoutonFiltrer(),
          ],
        ),
      ),
    );
  }
}

/// Bouton « Filtrer » — ouvre la liste COMPLÈTE des statuts.
///
/// Il ne remplace pas la rangée de puces : celles-ci donnent l'accès direct
/// aux statuts réellement présents, ce bouton permet d'en viser un qui ne
/// figure pas encore dans l'organisation.
class _BoutonFiltrer extends StatelessWidget {
  const _BoutonFiltrer();

  Future<void> _ouvrir(BuildContext context) async {
    final l10n = context.l10n;
    final cubit = context.read<ChantiersListCubit>();
    final courant = cubit.state.filtreStatut;

    // Sentinelle : `null` ne doit signifier QUE « feuille abandonnée ». Sans
    // elle, choisir « Tous » et fermer d'un glissement produiraient la même
    // valeur, et l'abandon réinitialiserait le filtre par surprise.
    const sentinelleTous = '__tous__';

    final choix = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 14),
              ListTile(
                title: Text(l10n.equipeFiltreTous),
                trailing: courant == null ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                onTap: () => Navigator.of(sheetContext).pop(sentinelleTous),
              ),
              // Sans les statuts du circuit : les demandes ont leur propre
              // écran (« Suivi des demandes »), et le serveur les écarte de
              // cette liste — le filtre ne ramènerait rien.
              for (final s in ChantierStatut.values.where((s) => !s.estUneDemande))
                ListTile(
                  leading: Icon(iconeStatutChantier(s), size: 20, color: toneStatutChantier(s).fg),
                  title: Text(s.label(l10n)),
                  trailing: courant == s ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                  onTap: () => Navigator.of(sheetContext).pop(s.raw),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    if (choix == null || !context.mounted) return;
    cubit.filtrerParStatut(choix == sentinelleTous ? null : ChantierStatutX.fromString(choix));
  }

  @override
  Widget build(BuildContext context) {
    final actif = context.select((ChantiersListCubit c) => c.state.filtreStatut) != null;

    return Material(
      color: actif ? AppColors.primary.withValues(alpha: 0.12) : AppColors.background,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: () => _ouvrir(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, size: 19, color: actif ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 7),
              Text(
                context.l10n.reserveFiltrer,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: actif ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rangée de puces de statut, chacune avec SON compteur — pendant exact de
/// celle des réserves et des plans.
class _RangeeFiltres extends StatelessWidget {
  const _RangeeFiltres();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<ChantiersListCubit, ChantiersListState>(
      buildWhen: (a, b) =>
          a.filtreStatut != b.filtreStatut || a.compteursParStatut != b.compteursParStatut,
      builder: (context, state) {
        final statuts = state.statutsPresents;
        // Compteurs pas encore arrivés, ou une seule catégorie : la rangée
        // n'offrirait aucun choix utile.
        if (statuts.length < 2) return const SizedBox.shrink();

        final cubit = context.read<ChantiersListCubit>();
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: ContenuCentre(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  ChipFiltre(
                    icon: Icons.grid_view_rounded,
                    label: '${l10n.equipeFiltreTous} (${state.comptePourStatut(null)})',
                    actif: state.filtreStatut == null,
                    onTap: () => cubit.filtrerParStatut(null),
                  ),
                  for (final s in statuts) ...[
                    const SizedBox(width: 9),
                    ChipFiltre(
                      icon: iconeStatutChantier(s),
                      label: '${s.label(l10n)} (${state.comptePourStatut(s)})',
                      actif: state.filtreStatut == s,
                      onTap: () => cubit.filtrerParStatut(s),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Liste extends StatelessWidget {
  final ChantiersListState state;
  final ScrollController controller;

  const _Liste({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: forcerReseau(() => context.read<ChantiersListCubit>().charger()),
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
                return _CarteChantier(chantier: state.items[i]);
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

/// Carte d'un chantier — reprend le dessin des cartes du sélecteur de
/// chantier : liseré coloré au statut, tuile d'icône, code, adresse,
/// responsable et jauge d'avancement des réserves.
class _CarteChantier extends StatelessWidget {
  final Chantier chantier;
  const _CarteChantier({required this.chantier});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tone = toneStatutChantier(chantier.statut);
    final couleur = tone.fg;
    final total = chantier.reservesTotal;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/chantiers/${chantier.id}'),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border(left: BorderSide(color: couleur, width: 4)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(13, 13, 12, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [couleur.withValues(alpha: 0.18), couleur.withValues(alpha: 0.07)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(iconeStatutChantier(chantier.statut), color: couleur, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      chantier.nom,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ChantierStatutBadge(statut: chantier.statut),
                        if (chantier.code != null && chantier.code!.isNotEmpty)
                          _PastilleCode(code: chantier.code!),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _LigneInfo(
                      icone: Icons.location_on_outlined,
                      texte: (chantier.adresse != null && chantier.adresse!.isNotEmpty)
                          ? chantier.adresse!
                          : l10n.chantierPickerSansAdresse,
                      attenue: chantier.adresse == null || chantier.adresse!.isEmpty,
                    ),
                    if (chantier.responsable != null) ...[
                      const SizedBox(height: 4),
                      _LigneInfo(
                        icone: Icons.person_outline_rounded,
                        texte: l10n.chantierPickerResponsable(chantier.responsable!.nomComplet),
                      ),
                    ],
                    if (total != null) ...[
                      const SizedBox(height: 10),
                      _JaugeReserves(total: total, ouvertes: chantier.reservesOuvertes ?? 0),
                    ],
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 12, left: 2),
                child: Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PastilleCode extends StatelessWidget {
  final String code;
  const _PastilleCode({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.neutralBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        code,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _LigneInfo extends StatelessWidget {
  final IconData icone;
  final String texte;
  final bool attenue;

  const _LigneInfo({required this.icone, required this.texte, this.attenue = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 13.5, color: AppColors.textMuted),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            texte,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: attenue ? AppColors.textMuted : AppColors.textSecondary,
              fontStyle: attenue ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        ),
      ],
    );
  }
}

/// Avancement des réserves — barre de progression + libellés, identique à
/// celle du sélecteur de chantier.
class _JaugeReserves extends StatelessWidget {
  final int total;
  final int ouvertes;

  const _JaugeReserves({required this.total, required this.ouvertes});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (total == 0) {
      return Row(
        children: [
          const Icon(Icons.check_circle_outline_rounded, size: 13.5, color: AppColors.textMuted),
          const SizedBox(width: 5),
          Text(
            l10n.chantierPickerAucuneReserve,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
      );
    }

    final levees = (total - ouvertes).clamp(0, total);
    final ratio = levees / total;
    final pourcent = (ratio * 100).round();
    // Vert quand tout est levé, orange tant qu'il reste des réserves
    // ouvertes : la couleur dit « fini / pas fini » sans lire le chiffre.
    final couleur = ouvertes == 0 ? AppColors.success : AppColors.warning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.report_gmailerrorred_outlined, size: 13.5, color: couleur),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                l10n.chantierReservesOuvertesSur(ouvertes, total),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.chantierPickerAvancement(pourcent),
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: couleur),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: ratio),
            duration: const Duration(milliseconds: 520),
            curve: Curves.easeOutCubic,
            builder: (context, valeur, _) => LinearProgressIndicator(
              value: valeur,
              minHeight: 5,
              backgroundColor: AppColors.border,
              color: couleur,
            ),
          ),
        ),
      ],
    );
  }
}

/// Pied de liste — rappelle combien de chantiers sont affichés sur le total.
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
          Icon(Icons.construction_rounded, size: 16, color: AppColors.textMuted.withValues(alpha: 0.8)),
          const SizedBox(width: 8),
          // `Flexible` et non un `Text` nu : la phrase traduite débordait de
          // 49 px dès 390 dp — largeur d'un téléphone courant. Un `Row` dont
          // un enfant n'a pas l'autorisation de rétrécir échoue à la mise en
          // page, et Flutter lève À CHAQUE IMAGE. `Flexible` préserve le
          // centrage tant que la place suffit, et cède quand elle manque.
          Flexible(
            child: Text(
              context.l10n.chantierAffichageSur(affiches, total),
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
