import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/inspection.dart';
import '../../domain/usecases/inspection_usecases.dart';
import '../cubit/inspection_detail_cubit.dart';
import '../cubit/inspection_detail_state.dart';

/// Détail d'une visite : points de contrôle et convoqués.
///
/// C'est l'écran qui justifie le module sur mobile — cocher quarante points en
/// marchant dans un bâtiment. Les bascules sont OPTIMISTES (voir
/// `InspectionDetailCubit.basculerLigne`) : la case répond immédiatement, le
/// réseau suit.
class InspectionDetailPage extends StatelessWidget {
  final String inspectionId;
  const InspectionDetailPage({super.key, required this.inspectionId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => InspectionDetailCubit(
        getInspection: sl<GetInspection>(),
        cocherLigne: sl<CocherLigneChecklist>(),
        changerStatut: sl<ChangerStatutInspection>(),
        getConvocations: sl<GetConvocations>(),
        repondreConvocation: sl<RepondreConvocation>(),
        inspectionId: inspectionId,
      )..charger(),
      child: const _Vue(),
    );
  }
}

class _Vue extends StatelessWidget {
  const _Vue();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocConsumer<InspectionDetailCubit, InspectionDetailState>(
      listenWhen: (a, b) => a.erreurAction != b.erreurAction && b.erreurAction != null,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.erreurAction!)),
        );
        context.read<InspectionDetailCubit>().accuserReceptionErreur();
      },
      builder: (context, state) {
        final cubit = context.read<InspectionDetailCubit>();
        final inspection = state.inspection;

        return PopScope(
          canPop: false,
          // Renvoie la visite à jour à la liste : elle remplace sa ligne au
          // lieu de tout recharger au retour.
          onPopInvokedWithResult: (aQuitte, _) {
            if (aQuitte) return;
            Navigator.of(context).pop(inspection);
          },
          child: Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  ContenuCentre(
                    child: EnTeteListe(
                      titre: inspection?.type.label(l10n) ?? l10n.inspectionsTitre,
                      avecRetour: true,
                      avecCloche: false,
                    ),
                  ),
                  Expanded(child: _Corps(state: state)),
                ],
              ),
            ),
            bottomNavigationBar: inspection == null
                ? null
                : _BarreProgression(inspection: inspection, cubit: cubit),
          ),
        );
      },
    );
  }
}

class _Corps extends StatelessWidget {
  final InspectionDetailState state;
  const _Corps({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<InspectionDetailCubit>();

    if (state.status == InspectionDetailStatus.chargement && state.inspection == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.status == InspectionDetailStatus.erreur && state.inspection == null) {
      return ErrorView(message: state.erreur ?? l10n.commonError, onRetry: cubit.charger);
    }

    final inspection = state.inspection;
    if (inspection == null) return const SizedBox.shrink();

    return ContenuCentre(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          _Entete(inspection: inspection),

          if (inspection.statut.estFigee) ...[
            const SizedBox(height: 14),
            _Bandeau(
              icone: Icons.lock_outline_rounded,
              texte: l10n.inspectionFigee,
              couleur: AppColors.info,
            ),
          ],

          const SizedBox(height: 22),
          _TitreSection(
            texte: l10n.inspectionOngletChecklist,
            compteur: inspection.nbPoints,
          ),
          const SizedBox(height: 10),

          if (inspection.checklist.isEmpty)
            _TexteVide(texte: l10n.inspectionAucunPoint)
          else
            for (final ligne in inspection.checklist)
              _LigneChecklistTuile(
                ligne: ligne,
                verrouillee: inspection.statut.estFigee,
                enCours: state.lignesEnCours.contains(ligne.id),
                onTap: () => cubit.basculerLigne(ligne),
              ),

          const SizedBox(height: 26),
          _TitreSection(
            texte: l10n.inspectionOngletConvocations,
            compteur: state.convocations.length,
          ),
          const SizedBox(height: 10),

          if (state.convocations.isEmpty)
            _TexteVide(texte: l10n.inspectionAucunConvoque)
          else
            for (final convocation in state.convocations)
              _TuileConvocation(convocation: convocation),

          if ((inspection.compteRendu ?? '').isNotEmpty) ...[
            const SizedBox(height: 26),
            _TitreSection(texte: l10n.inspectionCompteRendu),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                inspection.compteRendu!,
                style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Entete extends StatelessWidget {
  final Inspection inspection;
  const _Entete({required this.inspection});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  inspection.dateVisite != null
                      ? '${inspection.dateVisite!.day.toString().padLeft(2, '0')}/${inspection.dateVisite!.month.toString().padLeft(2, '0')}/${inspection.dateVisite!.year}'
                      : l10n.inspectionSansDate,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  inspection.statut.label(l10n),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          if (inspection.inspecteur != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.person_outline_rounded, size: 15, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Text(
                  '${l10n.inspectionInspecteur} · ${inspection.inspecteur!.nomComplet}',
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LigneChecklistTuile extends StatelessWidget {
  final LigneChecklist ligne;
  final bool verrouillee;
  final bool enCours;
  final VoidCallback onTap;

  const _LigneChecklistTuile({
    required this.ligne,
    required this.verrouillee,
    required this.enCours,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: verrouillee ? null : onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: ligne.coche ? AppColors.success.withValues(alpha: 0.4) : AppColors.border,
              ),
            ),
            child: Row(
              children: [
                // La case reste visible pendant l'envoi, avec un voile : la
                // remplacer par un spinner ferait sauter la mise en page à
                // chaque coche.
                Opacity(
                  opacity: enCours ? 0.45 : 1,
                  child: Icon(
                    ligne.coche
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 22,
                    color: ligne.coche ? AppColors.success : AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ligne.libelle,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: ligne.coche ? AppColors.textMuted : AppColors.textPrimary,
                          decoration: ligne.coche ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if ((ligne.commentaire ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          ligne.commentaire!,
                          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                if (verrouillee)
                  const Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TuileConvocation extends StatelessWidget {
  final Convocation convocation;
  const _TuileConvocation({required this.convocation});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final couleur = switch (convocation.statut) {
      StatutConvocation.present || StatutConvocation.accepte => AppColors.success,
      StatutConvocation.absent || StatutConvocation.decline => AppColors.danger,
      StatutConvocation.invite => AppColors.textMuted,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Icon(Icons.person_rounded, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                convocation.utilisateur?.nomComplet ?? '—',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            Text(
              convocation.statut.label(l10n),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: couleur),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barre du bas : avancement, et l'action qui fait progresser la visite.
class _BarreProgression extends StatelessWidget {
  final Inspection inspection;
  final InspectionDetailCubit cubit;

  const _BarreProgression({required this.inspection, required this.cubit});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    // Une visite signée n'a plus d'étape suivante — la barre disparaît plutôt
    // que d'afficher un bouton inerte.
    if (inspection.statut.estFigee) return const SizedBox.shrink();

    final (libelle, suivant) = switch (inspection.statut) {
      InspectionStatut.planifiee => (l10n.inspectionDemarrer, InspectionStatut.enCours),
      InspectionStatut.enCours => (l10n.inspectionTerminer, InspectionStatut.terminee),
      InspectionStatut.terminee => (l10n.inspectionSigner, InspectionStatut.signee),
      InspectionStatut.signee => ('', InspectionStatut.signee),
    };

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            if (inspection.nbPoints > 0) ...[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.inspectionAvancement(inspection.nbCoches, inspection.nbPoints),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: inspection.avancement,
                        minHeight: 5,
                        backgroundColor: AppColors.neutralBg,
                        valueColor: AlwaysStoppedAnimation(
                          inspection.estComplete ? AppColors.success : AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
            ],
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => cubit.avancerVers(suivant),
              child: Text(
                libelle,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitreSection extends StatelessWidget {
  final String texte;
  final int? compteur;
  const _TitreSection({required this.texte, this.compteur});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          texte,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        if (compteur != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.neutralBg,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              '$compteur',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TexteVide extends StatelessWidget {
  final String texte;
  const _TexteVide({required this.texte});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          texte,
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      );
}

class _Bandeau extends StatelessWidget {
  final IconData icone;
  final String texte;
  final Color couleur;
  const _Bandeau({required this.icone, required this.texte, required this.couleur});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: couleur.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icone, size: 17, color: couleur),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                texte,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
}
