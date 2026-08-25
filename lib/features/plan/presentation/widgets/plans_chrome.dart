import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/plan.dart';
import '../cubit/plans_list_cubit.dart';

/// Date de dépôt et format du fichier, séparés d'un trait vertical — même
/// vocabulaire visuel que la ligne méta des cartes de réserve, pour que les
/// deux listes se lisent de la même façon.
class MetaPlan extends StatelessWidget {
  final Plan plan;
  const MetaPlan({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 12.5, color: AppColors.textSecondary);
    final date = plan.createdAt;

    return Row(
      children: [
        if (date != null) ...[
          const Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.textMuted),
          const SizedBox(width: 5),
          Text(DateFormat('dd MMM yyyy').format(date), style: style),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(width: 1, height: 12, color: AppColors.border),
          ),
        ],
        const Icon(Icons.insert_drive_file_outlined, size: 13, color: AppColors.textMuted),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            '${plan.format.label} · v${plan.version}',
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Intertitre de section de la liste des plans, avec compteur optionnel.
class TitreSectionPlans extends StatelessWidget {
  final String texte;
  final int? compteur;

  const TitreSectionPlans(this.texte, {super.key, this.compteur});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          texte,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
        ),
        if (compteur != null) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$compteur',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
            ),
          ),
        ],
      ],
    );
  }
}

/// Icône par format de plan — donne aux puces la même silhouette
/// reconnaissable que celles des réserves.
IconData iconeFormatPlan(PlanFormat format) => switch (format) {
      PlanFormat.pdf => Icons.picture_as_pdf_outlined,
      PlanFormat.dwg => Icons.architecture_rounded,
      PlanFormat.ifc => Icons.view_in_ar_outlined,
    };

/// Rangée de puces de format, chacune avec SON compteur.
///
/// Pendant exact de la rangée des réserves (`RangeeFiltresReserve`) : même
/// [ChipFiltre], même espacement, même défilement horizontal — les deux
/// listes se lisent ainsi de la même façon, à ceci près qu'un plan se range
/// par format là où une réserve se range par statut. Seuls les formats
/// réellement déposés apparaissent : une puce « IFC (0) » n'apprend rien.
class RangeeFiltresPlan extends StatelessWidget {
  const RangeeFiltresPlan({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<PlansListCubit, PlansListState>(
      buildWhen: (a, b) => a.filtreFormat != b.filtreFormat || a.items != b.items,
      builder: (context, state) {
        final formats = state.formatsPresents;
        // Une seule famille de fichiers : la rangée n'offrirait aucun choix.
        if (formats.length < 2) return const SizedBox.shrink();

        final cubit = context.read<PlansListCubit>();
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
                    label: '${l10n.equipeFiltreTous} (${state.comptePourFormat(null)})',
                    actif: state.filtreFormat == null,
                    onTap: () => cubit.filtrerParFormat(null),
                  ),
                  for (final f in formats) ...[
                    const SizedBox(width: 9),
                    ChipFiltre(
                      icon: iconeFormatPlan(f),
                      label: '${f.label} (${state.comptePourFormat(f)})',
                      actif: state.filtreFormat == f,
                      onTap: () => cubit.filtrerParFormat(f),
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

/// Bouton « Filtrer » de la liste des plans.
///
/// Le filtre porte sur le FORMAT (pdf / dwg / ifc) : c'est la seule facette
/// réellement discriminante côté données — un plan n'a pas de statut,
/// contrairement à une réserve.
///
/// Le format choisi vit dans le CUBIT (`filtreFormat`), pas dans l'état local
/// du bouton : les puces de [RangeeFiltresPlan] et ce bouton pilotent la même
/// valeur, et cochent donc toujours la même entrée.
class BoutonFiltrerPlans extends StatelessWidget {
  const BoutonFiltrerPlans({super.key});

  Future<void> _ouvrir(BuildContext context) async {
    final l10n = context.l10n;
    final cubit = context.read<PlansListCubit>();
    final courant = cubit.state.filtreFormat;

    // Sentinelle : `null` ne doit signifier QUE « feuille abandonnée ». Sans
    // elle, choisir « Tous » et fermer d'un glissement produiraient la même
    // valeur, et l'abandon réinitialiserait le filtre par surprise.
    const sentinelleTous = '__tous__';

    final choix = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => SafeArea(
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
            for (final f in PlanFormat.values)
              ListTile(
                leading: Icon(iconeFormatPlan(f), size: 20, color: AppColors.textSecondary),
                title: Text(f.label),
                trailing: courant == f ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                onTap: () => Navigator.of(sheetContext).pop(f.raw),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choix == null || !context.mounted) return;
    cubit.filtrerParFormat(choix == sentinelleTous ? null : PlanFormatX.fromString(choix));
  }

  @override
  Widget build(BuildContext context) {
    final actif = context.select((PlansListCubit c) => c.state.filtreFormat) != null;

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
                context.l10n.planFiltrer,
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
