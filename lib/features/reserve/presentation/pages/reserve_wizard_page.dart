import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/chantier_structure.dart';
import '../../domain/entities/reserve.dart';
import '../cubit/reserve_wizard_cubit.dart';
import '../cubit/reserve_wizard_state.dart';

class ReserveWizardPage extends StatelessWidget {
  final String chantierId;

  /// Plan par lequel l'assistant a été atteint, le cas échéant.
  ///
  /// Renseigné par le parcours du bouton « + » de la barre : chantier, puis
  /// plan, puis ce formulaire. La réserve créée est alors rattachée à ce plan
  /// côté serveur. Nul quand on arrive par la liste des réserves d'un
  /// chantier, où aucun plan n'a été désigné.
  final String? planId;
  final String? planNom;

  const ReserveWizardPage({
    super.key,
    required this.chantierId,
    this.planId,
    this.planNom,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      // Les deux chargements partent ensemble mais restent INDÉPENDANTS :
      // l'échec du catalogue ne doit pas empêcher l'assistant de s'ouvrir
      // (voir `chargerCorpsEtat`, dont l'erreur est volontairement ignorée).
      create: (_) {
        final cubit = sl<ReserveWizardCubit>(param1: chantierId)
          ..chargerStructure()
          ..chargerCorpsEtat()
          ..chargerPhases();
        if (planId != null) cubit.definirPlan(id: planId!, nom: planNom);
        return cubit;
      },
      child: const _WizardView(),
    );
  }
}

class _WizardView extends StatelessWidget {
  const _WizardView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ReserveWizardCubit, ReserveWizardState>(
      listenWhen: (a, b) => a.soumissionStatus != b.soumissionStatus,
      listener: (context, state) async {
        if (state.soumissionStatus == SoumissionStatus.erreur) {
          AppAlert.error(context, message: state.erreur ?? context.l10n.commonErrorUnknown);
        }
      },
      builder: (context, state) {
        return PopScope(
          // `canPop: false` intercepte AUSSI le geste de retour système et le
          // bouton physique d'Android : n'attraper que la croix laisserait
          // perdre la saisie par les deux chemins les plus fréquents.
          canPop: false,
          onPopInvokedWithResult: (aQuitte, _) async {
            if (aQuitte) return;
            await _quitter(context, state);
          },
          child: Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                ContenuCentre(
                  child: EnTeteListe(
                    titre: context.l10n.syncNomNouvelleReserve,
                    // Croix plutôt que flèche : on ABANDONNE une création en
                    // cours, on ne remonte pas d'un cran dans une hiérarchie.
                    // Elle remplace la cloche, de toute façon inaccessible ici
                    // (écran plein hors coquille).
                    action: IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
                      tooltip: context.l10n.commonClose,
                      onPressed: () => _quitter(context, state),
                    ),
                  ),
                ),
                const _StepIndicator(),
                Expanded(
                  child: switch (state.etape) {
                    0 => const _Etape1InfosGenerales(),
                    1 => const _Etape2Localisation(),
                    _ => const _Etape3Recapitulatif(),
                  },
                ),
                _BarreActions(state: state),
              ],
            ),
          ),
          ),
        );
      },
    );
  }

  /// Demande confirmation avant d'abandonner une saisie en cours.
  ///
  /// L'assistant compte trois étapes : refermer sans un mot pouvait effacer
  /// un titre, une description, une localisation et des photos. La question
  /// n'est posée que s'il y a QUELQUE CHOSE à perdre — sur un formulaire
  /// encore vierge, elle ne serait qu'un obstacle de plus.
  Future<void> _quitter(BuildContext context, ReserveWizardState state) async {
    final navigator = Navigator.of(context);
    if (!state.aDesDonneesSaisies) {
      navigator.pop();
      return;
    }

    final l10n = context.l10n;
    final confirme = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l10n.wizardAbandonTitre),
        content: Text(
          l10n.wizardAbandonMessage,
          style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.wizardAbandonContinuer),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.wizardAbandonQuitter),
          ),
        ],
      ),
    );

    if (confirme == true) navigator.pop();
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReserveWizardCubit, ReserveWizardState>(
      buildWhen: (a, b) => a.etape != b.etape,
      builder: (context, state) {
        final titres = [context.l10n.wizardEtapeInformations, context.l10n.wizardChampLocalisation, context.l10n.wizardEtapeRecapitulatif];
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    _Pastille(numero: i + 1, actif: i == state.etape, complet: i < state.etape),
                    if (i < 2)
                      Expanded(
                        child: Container(
                          height: 2,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          color: i < state.etape ? AppColors.primary : AppColors.border,
                        ),
                      ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                titres[state.etape],
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Pastille extends StatelessWidget {
  final int numero;
  final bool actif;
  final bool complet;
  const _Pastille({required this.numero, required this.actif, required this.complet});

  @override
  Widget build(BuildContext context) {
    final rempli = actif || complet;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: rempli ? AppColors.primary : Colors.white,
        border: Border.all(color: rempli ? AppColors.primary : AppColors.border, width: 1.5),
      ),
      child: complet && !actif
          ? const Icon(Icons.check, size: 15, color: Colors.white)
          : Text('$numero', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: rempli ? Colors.white : AppColors.textMuted)),
    );
  }
}

class _BarreActions extends StatelessWidget {
  final ReserveWizardState state;
  const _BarreActions({required this.state});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ReserveWizardCubit>();
    final dernier = state.etape == 2;
    final chargement = state.soumissionStatus == SoumissionStatus.enCours;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
        child: Row(
          children: [
            if (state.etape > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: chargement ? null : () => cubit.allerEtape(state.etape - 1),
                  child: Text(context.l10n.commonPrevious),
                ),
              ),
            if (state.etape > 0) const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary, minimumSize: const Size.fromHeight(50)),
                onPressed: chargement || (state.etape == 0 && !state.etape1Valide)
                    ? null
                    : () async {
                        if (!dernier) {
                          cubit.allerEtape(state.etape + 1);
                          return;
                        }
                        final reserve = await cubit.soumettre();
                        if (reserve != null && context.mounted) {
                          await _terminer(context, reserve);
                        }
                      },
                child: chargement
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(dernier ? context.l10n.wizardCreerReserve : context.l10n.commonNext),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _terminer(BuildContext context, Reserve reserve) async {
    // Navigation reportée à la fermeture du popup (bouton OK) — partir
    // pendant que la boîte de dialogue est encore affichée la ferait
    // disparaître de façon abrupte.
    await AppAlert.success(context, message: context.l10n.wizardReserveCreee(reserve.numeroAffiche(context.l10n)));
    if (!context.mounted) return;
    context.pop(true);
    context.push('/reserves/${reserve.id}');
  }
}

// ═══════════════════════════ ÉTAPE 1 ═══════════════════════════
class _Etape1InfosGenerales extends StatelessWidget {
  const _Etape1InfosGenerales();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ReserveWizardCubit>();
    return BlocBuilder<ReserveWizardCubit, ReserveWizardState>(
      builder: (context, state) {
        final l10n = context.l10n;
        return ContenuFormulaire(
          child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _Label(l10n.wizardChampTitre),
            TextFormField(
              initialValue: state.titre,
              decoration: InputDecoration(hintText: l10n.wizardTitreHint),
              onChanged: cubit.changerTitre,
            ),
            const SizedBox(height: 18),
            // Phase — OBLIGATOIRE, d'où l'astérisque et l'absence d'option
            // « aucune ». `etape1Valide` bloque le passage à l'étape suivante.
            _Label('${l10n.phaseLabel} *'),
            DropdownButtonFormField<String?>(
              initialValue: state.phaseId,
              isExpanded: true,
              items: [
                DropdownMenuItem(value: null, child: Text(l10n.phaseChoisir)),
                for (final ph in state.phasesDisponibles)
                  DropdownMenuItem(value: ph.id, child: Text(ph.nom)),
              ],
              onChanged: cubit.changerPhase,
            ),
            const SizedBox(height: 16),
            _Label(l10n.corpsEtatLabel),
            DropdownButtonFormField<String?>(
              initialValue: state.corpsEtatId,
              isExpanded: true,
              items: [
                DropdownMenuItem(value: null, child: Text(l10n.corpsEtatAucun)),
                for (final c in state.corpsEtatDisponibles)
                  DropdownMenuItem(value: c.id, child: Text(c.nom)),
              ],
              onChanged: cubit.changerCorpsEtat,
            ),
            const SizedBox(height: 18),
            _Label(l10n.wizardChampPriorite),
            Wrap(
              spacing: 8,
              children: [
                for (final p in ReserveSeverite.values)
                  ChoiceChip(
                    label: Text(p.label(l10n)),
                    selected: state.priorite == p,
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(color: state.priorite == p ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.w600),
                    onSelected: (_) => cubit.changerPriorite(p),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _Label(l10n.commonDescription),
            TextFormField(
              initialValue: state.description,
              maxLines: 4,
              maxLength: 1000,
              decoration: InputDecoration(hintText: l10n.wizardDescriptionHint, alignLabelWithHint: true),
              onChanged: cubit.changerDescription,
            ),
          ],
          ),
        );
      },
    );
  }
}

class _Label extends StatelessWidget {
  final String texte;
  const _Label(this.texte);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(texte, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
    );
  }
}

// ═══════════════════════════ ÉTAPE 2 ═══════════════════════════
/// Rappel discret du plan sur lequel la réserve sera rattachée.
class _BandeauPlan extends StatelessWidget {
  final String nom;
  const _BandeauPlan({required this.nom});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary200),
      ),
      child: Row(
        children: [
          const Icon(Icons.map_rounded, size: 19, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.l10n.reserveWizardPlanAssocie(nom),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Etape2Localisation extends StatelessWidget {
  const _Etape2Localisation();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ReserveWizardCubit>();
    return BlocBuilder<ReserveWizardCubit, ReserveWizardState>(
      builder: (context, state) {
        final l10n = context.l10n;
        if (state.structureStatus == StructureStatus.chargement) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (state.structureStatus == StructureStatus.erreur) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(state.erreur ?? l10n.commonError, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: cubit.chargerStructure, child: Text(l10n.commonRetry)),
                ],
              ),
            ),
          );
        }

        final batiments = state.structure.batiments;
        final etages = state.batiment?.etages ?? const <EtageStructure>[];
        final zones = state.etage?.zones ?? const <ZoneStructure>[];

        return ContenuFormulaire(
          child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Rappel du plan choisi juste avant.
            //
            // Sans lui, l'utilisateur qui vient de traverser deux sélecteurs
            // n'a plus aucune trace de ce qu'il a désigné, et ne peut pas
            // vérifier qu'il ne s'est pas trompé de plan avant d'enregistrer.
            if (state.planNom != null) ...[
              _BandeauPlan(nom: state.planNom!),
              const SizedBox(height: 18),
            ],
            _Label(l10n.wizardChampBatiment),
            DropdownButtonFormField<BatimentStructure>(
              initialValue: state.batiment,
              hint: Text(l10n.wizardSelectionnerBatiment),
              items: [for (final b in batiments) DropdownMenuItem(value: b, child: Text(b.nom))],
              onChanged: batiments.isEmpty ? null : cubit.changerBatiment,
              disabledHint: Text(l10n.wizardAucunBatiment),
            ),
            const SizedBox(height: 16),
            _Label(l10n.wizardChampEtage),
            DropdownButtonFormField<EtageStructure>(
              initialValue: state.etage,
              hint: Text(l10n.wizardSelectionnerEtage),
              items: [for (final e in etages) DropdownMenuItem(value: e, child: Text(e.nom))],
              onChanged: etages.isEmpty ? null : cubit.changerEtage,
              disabledHint: Text(l10n.wizardChoisirBatimentDabord),
            ),
            const SizedBox(height: 16),
            _Label(l10n.wizardChampZone),
            DropdownButtonFormField<ZoneStructure>(
              initialValue: state.zone,
              hint: Text(l10n.wizardSelectionnerZone),
              items: [for (final z in zones) DropdownMenuItem(value: z, child: Text(z.nom))],
              onChanged: zones.isEmpty ? null : cubit.changerZone,
              disabledHint: Text(l10n.wizardChoisirEtageDabord),
            ),
            if (state.structure.lots.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Label(l10n.wizardChampLot),
              DropdownButtonFormField<StructureRef>(
                initialValue: state.lot,
                hint: Text(l10n.wizardSelectionnerLot),
                items: [for (final l in state.structure.lots) DropdownMenuItem(value: l, child: Text(l.nom))],
                onChanged: cubit.changerLot,
              ),
            ],
            const SizedBox(height: 16),
            _Label(l10n.reserveDetailEcheance),
            InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: state.dateLimite ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (date != null) cubit.changerDateLimite(date);
              },
              child: InputDecorator(
                decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today_outlined, size: 18)),
                child: Text(
                  state.dateLimite != null ? DateFormat('dd/MM/yyyy').format(state.dateLimite!) : l10n.wizardAucuneEcheance,
                  style: TextStyle(color: state.dateLimite != null ? AppColors.textPrimary : AppColors.textMuted),
                ),
              ),
            ),
          ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════ ÉTAPE 3 ═══════════════════════════
class _Etape3Recapitulatif extends StatelessWidget {
  const _Etape3Recapitulatif();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReserveWizardCubit, ReserveWizardState>(
      builder: (context, state) {
        final l10n = context.l10n;
        final localisation = [state.batiment?.nom, state.etage?.nom, state.zone?.nom].whereType<String>().join(' · ');
        return ContenuFormulaire(
          child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state.titre, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _Recap(
                      l10n.phaseLabel,
                      state.phasesDisponibles
                              .where((p) => p.id == state.phaseId)
                              .map((p) => p.nom)
                              .firstOrNull ??
                          '—',
                    ),
                    _Recap(
                      l10n.corpsEtatLabel,
                      // Le récapitulatif montre le NOM du métier, pas son
                      // identifiant : `firstWhere` sur la liste déjà chargée
                      // évite une seconde requête pour un simple libellé.
                      state.corpsEtatDisponibles
                              .where((c) => c.id == state.corpsEtatId)
                              .map((c) => c.nom)
                              .firstOrNull ??
                          l10n.corpsEtatAucun,
                    ),
                    _Recap(l10n.wizardChampPriorite, state.priorite.label(l10n)),
                    _Recap(l10n.wizardChampLocalisation, localisation.isEmpty ? l10n.wizardNonRenseignee : localisation),
                    if (state.lot != null) _Recap(l10n.wizardChampLot, state.lot!.nom),
                    if (state.dateLimite != null) _Recap(l10n.reserveDetailEcheance, DateFormat('dd/MM/yyyy').format(state.dateLimite!)),
                    if (state.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(l10n.commonDescription, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppColors.textMuted)),
                      const SizedBox(height: 4),
                      Text(state.description, style: const TextStyle(color: AppColors.textSecondary)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.wizardPhotosApresCreation,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
          ],
          ),
        );
      },
    );
  }
}

class _Recap extends StatelessWidget {
  final String label;
  final String valeur;
  const _Recap(this.label, this.valeur);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted))),
          Expanded(child: Text(valeur, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
