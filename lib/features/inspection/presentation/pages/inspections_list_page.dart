import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/inspection.dart';
import '../../domain/usecases/inspection_usecases.dart';
import '../cubit/inspections_list_cubit.dart';
import '../cubit/inspections_list_state.dart';
import '../widgets/planifier_inspection_sheet.dart';
import 'inspection_detail_page.dart';

/// Visites d'un chantier.
///
/// Écran plein, ouvert DEPUIS une fiche chantier : d'où `avecRetour` et
/// `avecCloche: false` — hors de la coquille, le [NotificationsCubit] que la
/// cloche cherche n'existe pas (voir l'en-tête de `EnTeteListe`).
class InspectionsListPage extends StatelessWidget {
  final String chantierId;
  final String? chantierNom;

  const InspectionsListPage({super.key, required this.chantierId, this.chantierNom});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => InspectionsListCubit(
        getInspections: sl<GetInspections>(),
        creerInspection: sl<CreerInspection>(),
        chantierId: chantierId,
      )..charger(),
      child: _Vue(chantierNom: chantierNom),
    );
  }
}

class _Vue extends StatelessWidget {
  final String? chantierNom;
  const _Vue({this.chantierNom});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: BlocConsumer<InspectionsListCubit, InspectionsListState>(
          listenWhen: (a, b) => a.creationStatus != b.creationStatus,
          listener: (context, state) {
            if (state.creationStatus == CreationInspectionStatus.erreur) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.creationErreur ?? l10n.commonError)),
              );
              context.read<InspectionsListCubit>().accuserReceptionCreation();
            } else if (state.creationStatus == CreationInspectionStatus.succes) {
              context.read<InspectionsListCubit>().accuserReceptionCreation();
            }
          },
          builder: (context, state) {
            return Column(
              children: [
                ContenuCentre(
                  child: EnTeteListe(
                    titre: chantierNom ?? l10n.inspectionsTitre,
                    avecRetour: true,
                    avecCloche: false,
                  ),
                ),
                _BarreFiltres(state: state),
                Expanded(child: _Corps(state: state)),
              ],
            );
          },
        ),
      ),
      floatingActionButton: Builder(
        builder: (context) => FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          onPressed: () => _ouvrirPlanification(context),
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.inspectionPlanifier),
        ),
      ),
    );
  }

  Future<void> _ouvrirPlanification(BuildContext context) async {
    final cubit = context.read<InspectionsListCubit>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Le cubit vient du contexte PARENT : la feuille est montée dans un
      // autre sous-arbre et ne le trouverait pas toute seule.
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: const PlanifierInspectionSheet(),
      ),
    );
  }
}

/// Filtre par statut — « Toutes » plus les quatre étapes du cycle de vie.
class _BarreFiltres extends StatelessWidget {
  final InspectionsListState state;
  const _BarreFiltres({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<InspectionsListCubit>();

    return SizedBox(
      height: 44,
      child: ContenuCentre(
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            ChipFiltre(
              icon: Icons.all_inclusive_rounded,
              label: l10n.inspectionsFiltreTous,
              actif: state.filtreStatut == null,
              onTap: () => cubit.filtrerParStatut(null),
            ),
            for (final statut in InspectionStatut.values) ...[
              const SizedBox(width: 8),
              ChipFiltre(
                icon: _icone(statut),
                label: statut.label(l10n),
                actif: state.filtreStatut == statut,
                onTap: () => cubit.filtrerParStatut(statut),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _icone(InspectionStatut statut) => switch (statut) {
        InspectionStatut.planifiee => Icons.event_outlined,
        InspectionStatut.enCours => Icons.pending_actions_rounded,
        InspectionStatut.terminee => Icons.task_alt_rounded,
        InspectionStatut.signee => Icons.verified_rounded,
      };
}

class _Corps extends StatelessWidget {
  final InspectionsListState state;
  const _Corps({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<InspectionsListCubit>();

    if (state.status == InspectionsListStatus.chargement && state.items.isEmpty) {
      return const LoadingList();
    }

    if (state.status == InspectionsListStatus.erreur && state.items.isEmpty) {
      return ErrorView(message: state.erreur ?? l10n.commonError, onRetry: cubit.charger);
    }

    if (state.items.isEmpty) {
      return EtatVideIllustre(
        motif: MotifVide.document,
        titre: l10n.inspectionsAucune,
        description: l10n.inspectionsAucuneMessage,
      );
    }

    // Les visites en retard remontent en tête : c'est ce qui demande une
    // décision, le reste peut attendre le défilement.
    final enRetard = state.enRetard.map((i) => i.id).toSet();
    final ordonnees = [
      ...state.items.where((i) => enRetard.contains(i.id)),
      ...state.items.where((i) => !enRetard.contains(i.id)),
    ];

    return RefreshIndicator(
      onRefresh: cubit.charger,
      child: ContenuCentre(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
          itemCount: ordonnees.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, index) {
            final inspection = ordonnees[index];
            return _CarteInspection(
              inspection: inspection,
              enRetard: enRetard.contains(inspection.id),
              onTap: () => _ouvrirDetail(context, cubit, inspection),
            );
          },
        ),
      ),
    );
  }

  Future<void> _ouvrirDetail(
    BuildContext context,
    InspectionsListCubit cubit,
    Inspection inspection,
  ) async {
    final maj = await Navigator.of(context).push<Inspection>(
      MaterialPageRoute(builder: (_) => InspectionDetailPage(inspectionId: inspection.id)),
    );
    // Le détail renvoie la visite modifiée : on remplace la ligne au lieu de
    // recharger toute la liste au retour.
    if (maj != null) cubit.remplacer(maj);
  }
}

class _CarteInspection extends StatelessWidget {
  final Inspection inspection;
  final bool enRetard;
  final VoidCallback onTap;

  const _CarteInspection({
    required this.inspection,
    required this.enRetard,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final couleur = _couleurStatut(inspection.statut);

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: enRetard ? AppColors.danger.withValues(alpha: 0.45) : AppColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: couleur.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_icone(inspection.type), size: 19, color: couleur),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          inspection.type.label(l10n),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          inspection.dateVisite != null
                              ? _formaterDate(inspection.dateVisite!)
                              : l10n.inspectionSansDate,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: enRetard ? AppColors.danger : AppColors.textSecondary,
                            fontWeight: enRetard ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _Pastille(
                    texte: enRetard ? l10n.inspectionEnRetard : inspection.statut.label(l10n),
                    couleur: enRetard ? AppColors.danger : couleur,
                  ),
                ],
              ),

              if (inspection.nbPoints > 0) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: inspection.avancement,
                          minHeight: 6,
                          backgroundColor: AppColors.neutralBg,
                          valueColor: AlwaysStoppedAnimation(
                            inspection.estComplete ? AppColors.success : AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      l10n.inspectionAvancement(inspection.nbCoches, inspection.nbPoints),
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],

              if (inspection.inspecteur != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.person_outline_rounded, size: 14, color: AppColors.textMuted),
                    const SizedBox(width: 5),
                    Text(
                      inspection.inspecteur!.nomComplet,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static IconData _icone(InspectionType type) => switch (type) {
        InspectionType.inspection => Icons.fact_check_outlined,
        InspectionType.opr => Icons.assignment_turned_in_outlined,
        InspectionType.visiteContradictoire => Icons.groups_2_outlined,
      };

  static Color _couleurStatut(InspectionStatut statut) => switch (statut) {
        InspectionStatut.planifiee => AppColors.info,
        InspectionStatut.enCours => AppColors.warning,
        InspectionStatut.terminee => AppColors.primary,
        InspectionStatut.signee => AppColors.success,
      };

  static String _formaterDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _Pastille extends StatelessWidget {
  final String texte;
  final Color couleur;
  const _Pastille({required this.texte, required this.couleur});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        texte,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: couleur),
      ),
    );
  }
}
