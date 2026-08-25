import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/fiche_chrome.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../cubit/chantier_detail_cubit.dart';
import '../cubit/chantier_detail_state.dart';
import '../widgets/chantier_statut_badge.dart';

class ChantierDetailPage extends StatelessWidget {
  final String chantierId;
  const ChantierDetailPage({super.key, required this.chantierId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ChantierDetailCubit>(param1: chantierId)..charger(),
      child: const _ChantierDetailView(),
    );
  }
}

class _ChantierDetailView extends StatelessWidget {
  const _ChantierDetailView();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      // Blanc, comme les autres écrans. Le CONTENU repose sur le gris de fond :
      // des cartes blanches sur une page blanche perdraient tout relief.
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Écran de la coquille : la cloche y trouve bien son cubit.
            ContenuCentre(child: EnTeteListe(titre: l10n.chantierDetailTitre, avecRetour: true)),
            Expanded(
              child: BlocBuilder<ChantierDetailCubit, ChantierDetailState>(
        builder: (context, state) {
          switch (state.status) {
            case ChantierDetailStatus.chargement:
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            case ChantierDetailStatus.erreur:
              return ErrorView(
                message: state.erreur ?? l10n.commonErrorUnknown,
                onRetry: () => context.read<ChantierDetailCubit>().charger(),
              );
            case ChantierDetailStatus.succes:
              final c = state.chantier!;
              final df = DateFormat('dd/MM/yyyy');
              // `ContenuCentre` : sans lui, les cartes de section s'étirent sur
              // toute la largeur d'une tablette.
              return ColoredBox(
                color: AppColors.background,
                child: ContenuCentre(
                child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.nom,
                          style:
                              const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                        ),
                      ),
                      ChantierStatutBadge(statut: c.statut),
                    ],
                  ),
                  if (c.code != null && c.code!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(l10n.chantierDetailCode(c.code!), style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                  const SizedBox(height: 20),
                  TitreSectionFiche(l10n.chantierDetailInformations, icone: Icons.info_outline_rounded),
                  CarteFiche(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    child: Column(
                      children: [
                        LigneFiche(
                          icone: Icons.location_on_outlined,
                          libelle: l10n.chantierDetailAdresse,
                          valeur: c.adresse,
                          texteSiVide: l10n.membreDetailNonRenseigne,
                        ),
                        LigneFiche(
                          icone: Icons.person_outline_rounded,
                          libelle: l10n.chantierDetailResponsable,
                          valeur: c.responsable?.nomComplet,
                          texteSiVide: l10n.membreDetailNonRenseigne,
                        ),
                        LigneFiche(
                          icone: Icons.calendar_today_outlined,
                          libelle: l10n.chantierDetailDebut,
                          valeur: c.dateDebut != null ? df.format(c.dateDebut!) : null,
                          texteSiVide: l10n.membreDetailNonRenseigne,
                        ),
                        LigneFiche(
                          icone: Icons.event_outlined,
                          libelle: l10n.chantierDetailFinPrevue,
                          valeur: c.dateFin != null ? df.format(c.dateFin!) : null,
                          texteSiVide: l10n.membreDetailNonRenseigne,
                        ),
                      ],
                    ),
                  ),
                  if (c.description != null && c.description!.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    TitreSectionFiche(l10n.commonDescription, icone: Icons.notes_rounded),
                    CarteFiche(
                      child: Text(
                        c.description!,
                        style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  TitreSectionFiche(l10n.chantierDetailSections, icone: Icons.dashboard_outlined),
                  _SectionCard(
                    icon: Icons.report_gmailerrorred_outlined,
                    titre: l10n.navReserves,
                    sousTitre: c.reservesTotal != null
                        ? l10n.chantierDetailReservesSousTitre(c.reservesOuvertes ?? 0, c.reservesTotal!)
                        : l10n.chantierDetailReservesSousTitreDefaut,
                    onTap: () => context.push('/chantiers/${c.id}/reserves'),
                  ),
                  const SizedBox(height: 10),
                  _SectionCard(
                    icon: Icons.bar_chart_outlined,
                    titre: l10n.chantierDetailTableauBord,
                    sousTitre: l10n.chantierDetailTableauBordSousTitre,
                    onTap: () => context.push('/chantiers/${c.id}/tableau-de-bord'),
                  ),
                  const SizedBox(height: 10),
                  _SectionCard(
                    icon: Icons.folder_outlined,
                    titre: l10n.dashboardApercuDocuments,
                    sousTitre: l10n.chantierDetailDocumentsSousTitre,
                    onTap: () => context.push('/chantiers/${c.id}/documents'),
                  ),
                  const SizedBox(height: 10),
                  _SectionCard(
                    icon: Icons.map_outlined,
                    titre: l10n.navPlans,
                    sousTitre: l10n.chantierDetailPlansSousTitre,
                    onTap: () => context.push('/chantiers/${c.id}/plans'),
                  ),
                  const SizedBox(height: 10),
                  _SectionCard(
                    icon: Icons.fact_check_outlined,
                    titre: l10n.dashboardApercuInspections,
                    sousTitre: l10n.chantierDetailInspectionsSousTitre,
                    // Le nom du chantier est passé en query : l'écran plein
                    // n'a pas accès au chantier chargé ici, et un titre
                    // « Inspections » sec ferait perdre le contexte après
                    // deux niveaux de navigation.
                    onTap: () => context.push(
                      '/chantiers/${c.id}/inspections?nom=${Uri.encodeComponent(c.nom)}',
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SectionCard(
                    icon: Icons.description_outlined,
                    titre: l10n.chantierSectionRapports,
                    sousTitre: l10n.chantierDetailRapportsSousTitre,
                    onTap: () => context.push(
                      '/chantiers/${c.id}/rapports?nom=${Uri.encodeComponent(c.nom)}',
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _SectionsAVenir(),
                ],
                ),
                ),
              );
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

/// Bouton d'accès à une section complète du chantier (carte cliquable) —
/// utilisé pour « Réserves » et, au fur et à mesure de leur implémentation,
/// les autres sections actuellement listées dans `_SectionsAVenir`.
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String titre;
  final String sousTitre;
  final VoidCallback onTap;
  const _SectionCard({required this.icon, required this.titre, required this.sousTitre, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.primary100, borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titre, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(sousTitre, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Structure/Plans/Inspections/Rapports/Membres — prévus en phase 2/3 (voir
/// le plan communiqué). Placeholder honnête plutôt qu'un onglet qui semble
/// fonctionnel mais ne l'est pas. « Réserves », « Tableau de bord » et
/// « Documents » sont sortis de cette liste : ce sont désormais de vraies
/// sections (`_SectionCard` ci-dessus).
class _SectionsAVenir extends StatelessWidget {
  const _SectionsAVenir();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sections = [
      (l10n.chantierSectionStructure, Icons.apartment_outlined),
      (l10n.dashboardApercuMembres, Icons.group_outlined),
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppColors.neutralBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.commonProchainement, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              l10n.chantierSectionsAVenirTexte,
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in sections)
                  Chip(avatar: Icon(s.$2, size: 16), label: Text(s.$1), backgroundColor: Colors.white),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
