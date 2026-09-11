import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../document/domain/entities/document.dart';
import '../../../document/presentation/pages/document_viewer_page.dart';
import '../../domain/entities/configuration_rapport.dart';
import '../../domain/entities/modele_rapport.dart';
import '../../domain/entities/rapport.dart';
import '../cubit/nouveau_rapport_cubit.dart';

/// « + Nouveau rapport » — le parcours du § 3 du cahier des charges :
///
///   Choisir le projet → Choisir un modèle → Choisir les filtres →
///   Choisir les sections → Prévisualiser → Générer
///
/// Ouvert depuis un chantier, l'étape « projet » est sautée. Ouvert avec un
/// rapport [existant], l'assistant reprend sa configuration pour la modifier
/// avant de régénérer (§ 20).
///
/// L'écran se ferme sur le rapport GÉNÉRÉ : l'appelant l'ouvre ensuite.
class NouveauRapportPage extends StatelessWidget {
  final String? chantierId;
  final String? chantierNom;
  final Rapport? existant;

  const NouveauRapportPage({super.key, this.chantierId, this.chantierNom, this.existant});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => NouveauRapportCubit(
        getStructure: sl(),
        getOptions: sl(),
        getProjets: sl(),
        creerRapport: sl(),
        modifierRapport: sl(),
        calculerResume: sl(),
        genererRapport: sl(),
        chantierId: chantierId,
        chantierNom: chantierNom,
        existant: existant,
      )..demarrer(),
      child: _Assistant(modification: existant != null),
    );
  }
}

class _Assistant extends StatelessWidget {
  final bool modification;
  const _Assistant({required this.modification});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: BlocConsumer<NouveauRapportCubit, NouveauRapportState>(
          listenWhen: (a, b) => b.erreur != null || (a.rapportGenere == null && b.rapportGenere != null),
          listener: (context, state) {
            if (state.rapportGenere != null) {
              Navigator.of(context).pop(state.rapportGenere);
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.erreur!)));
          },
          builder: (context, state) {
            return Column(
              children: [
                ContenuCentre(
                  child: EnTeteListe(
                    titre: state.chantierNom ?? (modification ? l10n.rapportModifier : l10n.rapportNouveau),
                    avecRetour: true,
                    avecCloche: false,
                  ),
                ),
                _Etapes(state: state),
                if (state.occupe) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: ContenuCentre(
                    child: switch (state.etape) {
                      EtapeRapport.projet => _EtapeProjet(state: state),
                      EtapeRapport.modele => _EtapeModele(state: state),
                      EtapeRapport.filtres => _EtapeFiltres(state: state),
                      EtapeRapport.sections => _EtapeSections(state: state),
                      EtapeRapport.apercu => _EtapeApercu(state: state),
                    },
                  ),
                ),
                _BarreNavigation(state: state),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _libelleEtape(AppLocalizations l10n, EtapeRapport etape) => switch (etape) {
      EtapeRapport.projet => l10n.rapportEtapeProjet,
      EtapeRapport.modele => l10n.rapportEtapeModele,
      EtapeRapport.filtres => l10n.rapportEtapeFiltres,
      EtapeRapport.sections => l10n.rapportEtapeSections,
      EtapeRapport.apercu => l10n.rapportEtapeApercu,
    };

/// Le fil des étapes — l'utilisateur voit où il en est du parcours.
class _Etapes extends StatelessWidget {
  final NouveauRapportState state;
  const _Etapes({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final courante = state.indexEtape;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          for (final (i, etape) in state.etapes.indexed) ...[
            if (i > 0) const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textMuted),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: i == courante ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: i <= courante ? AppColors.primary : AppColors.border),
              ),
              child: Text(
                '${i + 1}. ${_libelleEtape(l10n, etape)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: i == courante ? Colors.white : (i < courante ? AppColors.primary : AppColors.textMuted),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/* ══════════════════════════════════════════════════════════════════════════
   Étape 1 — le projet
   ══════════════════════════════════════════════════════════════════════════ */

class _EtapeProjet extends StatelessWidget {
  final NouveauRapportState state;
  const _EtapeProjet({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<NouveauRapportCubit>();

    if (state.projetsStatut == ChargementWizard.enCours || state.projetsStatut == ChargementWizard.inactif) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.projetsStatut == ChargementWizard.erreur) {
      return ErrorView(message: l10n.commonError, onRetry: cubit.chargerProjets);
    }
    if (state.projets.isEmpty) {
      return Center(child: Text(l10n.rapportAucunProjet, style: const TextStyle(color: AppColors.textMuted)));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        _TitreEtape(l10n.rapportChoisirProjet),
        for (final projet in state.projets)
          _CarteChoix(
            titre: projet.nom,
            sousTitre: projet.detail,
            choisi: projet.id == state.chantierId,
            onTap: () => cubit.choisirProjet(projet),
          ),
      ],
    );
  }
}

/* ══════════════════════════════════════════════════════════════════════════
   Étape 2 — le modèle (§ 5)
   ══════════════════════════════════════════════════════════════════════════ */

class _EtapeModele extends StatelessWidget {
  final NouveauRapportState state;
  const _EtapeModele({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<NouveauRapportCubit>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        TextFormField(
          initialValue: state.nom,
          maxLength: 200,
          onChanged: cubit.definirNom,
          decoration: InputDecoration(
            labelText: l10n.rapportNomChamp,
            helperText: l10n.rapportNomAide,
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        _TitreEtape(l10n.rapportChoisirModele),
        for (final modele in ModeleRapport.values)
          _CarteChoix(
            titre: modele.label(l10n),
            sousTitre: modele.description(l10n),
            choisi: state.modele == modele,
            onTap: () => cubit.choisirModele(modele),
          ),
      ],
    );
  }
}

/* ══════════════════════════════════════════════════════════════════════════
   Étape 3 — les filtres (§ 4)
   ══════════════════════════════════════════════════════════════════════════ */

class _EtapeFiltres extends StatelessWidget {
  final NouveauRapportState state;
  const _EtapeFiltres({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<NouveauRapportCubit>();
    final requis = state.modele?.filtresRequis ?? const <FiltreRequis>{};

    if (state.optionsStatut == ChargementWizard.enCours || state.optionsStatut == ChargementWizard.inactif) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(l10n.rapportChargementOptions, style: const TextStyle(color: AppColors.textMuted)),
          ],
        ),
      );
    }
    if (state.optionsStatut == ChargementWizard.erreur) {
      return ErrorView(message: l10n.rapportOptionsIndisponibles, onRetry: cubit.chargerOptions);
    }

    final plusieursBatiments = (state.structure?.batiments.length ?? 0) > 1;
    final f = state.filtres;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        if (state.manquants.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final m in state.manquants)
                  Text(_messageManquant(l10n, m), style: const TextStyle(color: AppColors.danger, fontSize: 13)),
              ],
            ),
          ),
        _GroupeFiltre(
          titre: l10n.rapportFiltreBatiment,
          requis: requis.contains(FiltreRequis.batiment),
          vide: l10n.rapportAucunBatiment,
          toutes: l10n.rapportFiltreTous,
          aucunChoix: f.batiments.isEmpty,
          options: [
            for (final b in state.structure?.batiments ?? const [])
              _Option(b.id, b.nom, f.batiments.contains(b.id), () => cubit.basculerBatiment(b.id)),
          ],
        ),
        _GroupeFiltre(
          titre: l10n.rapportFiltreNiveau,
          requis: requis.contains(FiltreRequis.etageOuZone),
          vide: l10n.rapportAucunBatiment,
          toutes: l10n.rapportFiltreTous,
          aucunChoix: f.etages.isEmpty,
          options: [
            for (final p in state.etagesProposes)
              _Option(
                p.etage.id,
                plusieursBatiments ? '${p.batiment.nom} · ${p.etage.nom}' : p.etage.nom,
                f.etages.contains(p.etage.id),
                () => cubit.basculerEtage(p.etage.id),
              ),
          ],
        ),
        if (state.zonesProposees.isNotEmpty)
          _GroupeFiltre(
            titre: l10n.rapportFiltreZone,
            requis: requis.contains(FiltreRequis.etageOuZone),
            vide: '',
            toutes: l10n.rapportFiltreTous,
            aucunChoix: f.zones.isEmpty,
            options: [
              for (final p in state.zonesProposees)
                _Option(p.zone.id, '${p.etage.nom} · ${p.zone.nom}', f.zones.contains(p.zone.id),
                    () => cubit.basculerZone(p.zone.id)),
            ],
          ),
        _GroupeFiltre(
          titre: l10n.rapportFiltreEntreprise,
          requis: requis.contains(FiltreRequis.entreprise),
          vide: l10n.rapportAucuneEntreprise,
          toutes: l10n.rapportFiltreToutes,
          aucunChoix: f.entreprises.isEmpty,
          options: [
            for (final e in state.entreprises)
              _Option(e.id, e.nom, f.entreprises.contains(e.id), () => cubit.basculerEntreprise(e.id)),
          ],
        ),
        _GroupeFiltre(
          titre: l10n.rapportFiltreCorpsEtat,
          requis: requis.contains(FiltreRequis.corpsEtat),
          vide: l10n.rapportAucunCorpsEtat,
          toutes: l10n.rapportFiltreTous,
          aucunChoix: f.corpsEtat.isEmpty,
          options: [
            for (final c in state.corpsEtat)
              _Option(c.id, c.nom, f.corpsEtat.contains(c.id), () => cubit.basculerCorpsEtat(c.id)),
          ],
        ),
        _GroupeFiltre(
          titre: l10n.rapportFiltreStatut,
          requis: false,
          vide: '',
          toutes: l10n.rapportFiltreTous,
          aucunChoix: f.statuts.isEmpty,
          options: [
            for (final s in StatutReserveRapport.values)
              _Option(s.raw, s.label(l10n), f.statuts.contains(s), () => cubit.basculerStatut(s)),
          ],
        ),
        _GroupeFiltre(
          titre: l10n.rapportFiltreGravite,
          requis: false,
          vide: '',
          toutes: l10n.rapportFiltreToutes,
          aucunChoix: f.gravites.isEmpty,
          options: [
            for (final g in GraviteRapport.values)
              _Option(g.raw, g.label(l10n), f.gravites.contains(g), () => cubit.basculerGravite(g)),
          ],
        ),
        _Periode(filtres: f),
      ],
    );
  }

  static String _messageManquant(AppLocalizations l10n, FiltreRequis m) => switch (m) {
        FiltreRequis.batiment => l10n.rapportRequisBatiment,
        FiltreRequis.etageOuZone => l10n.rapportRequisEtageZone,
        FiltreRequis.entreprise => l10n.rapportRequisEntreprise,
        FiltreRequis.corpsEtat => l10n.rapportRequisCorpsEtat,
      };
}

class _Option {
  final String id;
  final String libelle;
  final bool choisi;
  final VoidCallback onTap;
  const _Option(this.id, this.libelle, this.choisi, this.onTap);
}

/// Un filtre « Tous ou sélection » (§ 4) : aucune puce cochée vaut « Tous ».
class _GroupeFiltre extends StatelessWidget {
  final String titre;
  final bool requis;
  final String vide;
  final String toutes;
  final bool aucunChoix;
  final List<_Option> options;

  const _GroupeFiltre({
    required this.titre,
    required this.requis,
    required this.vide,
    required this.toutes,
    required this.aucunChoix,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(titre, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              if (aucunChoix && options.isNotEmpty)
                Text('($toutes)', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              if (requis)
                Text(
                  l10n.rapportFiltreRequis,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.primary, fontWeight: FontWeight.w700),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (options.isEmpty && vide.isNotEmpty)
            Text(vide, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted))
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final o in options)
                  FilterChip(
                    label: Text(o.libelle, overflow: TextOverflow.ellipsis),
                    selected: o.choisi,
                    onSelected: (_) => o.onTap(),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Période : date de début / date de fin (§ 4).
class _Periode extends StatelessWidget {
  final FiltresRapport filtres;
  const _Periode({required this.filtres});

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<NouveauRapportCubit>();

    Future<DateTime?> choisir(DateTime? initiale) => showDatePicker(
          context: context,
          initialDate: initiale ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.rapportFiltrePeriode, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.event_rounded, size: 16),
              label: Text(filtres.dateDebut == null ? l10n.rapportPeriodeDebut : _date(filtres.dateDebut!)),
              onPressed: () async {
                final d = await choisir(filtres.dateDebut);
                if (d != null) cubit.definirPeriode(debut: d);
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_available_rounded, size: 16),
              label: Text(filtres.dateFin == null ? l10n.rapportPeriodeFin : _date(filtres.dateFin!)),
              onPressed: () async {
                final d = await choisir(filtres.dateFin);
                if (d != null) cubit.definirPeriode(fin: d);
              },
            ),
            if (filtres.dateDebut != null || filtres.dateFin != null)
              TextButton(onPressed: cubit.effacerPeriode, child: Text(l10n.rapportPeriodeEffacer)),
          ],
        ),
      ],
    );
  }
}

/* ══════════════════════════════════════════════════════════════════════════
   Étape 4 — les sections (§ 10) et le format (§ 4)
   ══════════════════════════════════════════════════════════════════════════ */

class _EtapeSections extends StatelessWidget {
  final NouveauRapportState state;
  const _EtapeSections({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<NouveauRapportCubit>();
    final s = state.sections;

    Widget section(String titre, String aide, bool valeur, SectionsRapport Function(bool) appliquer) =>
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: valeur,
          onChanged: (v) => cubit.definirSections(appliquer(v)),
          title: Text(titre, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          subtitle: Text(aide, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        section(l10n.rapportSectionSummary, l10n.rapportSectionSummaryAide, s.summary, (v) => s.copyWith(summary: v)),
        section(l10n.rapportSectionPlans, l10n.rapportSectionPlansAide, s.plans, (v) => s.copyWith(plans: v)),
        section(l10n.rapportSectionPhotos, l10n.rapportSectionPhotosAide, s.photos, (v) => s.copyWith(photos: v)),
        section(l10n.rapportSectionLocation, l10n.rapportSectionLocationAide, s.location,
            (v) => s.copyWith(location: v)),
        section(l10n.rapportSectionHistory, l10n.rapportSectionHistoryAide, s.history, (v) => s.copyWith(history: v)),
        const SizedBox(height: 12),
        Text(l10n.rapportFiltreFormat, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final format in FormatRapport.values)
              FilterChip(
                label: Text(format.label(l10n)),
                selected: state.formats.contains(format),
                onSelected: (_) => cubit.basculerFormat(format),
              ),
          ],
        ),
        if (state.formatManquant)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(l10n.rapportFormatRequis, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ),
      ],
    );
  }
}

/* ══════════════════════════════════════════════════════════════════════════
   Étape 5 — aperçu, prévisualisation, génération (§ 20, § 11)
   ══════════════════════════════════════════════════════════════════════════ */

class _EtapeApercu extends StatelessWidget {
  final NouveauRapportState state;
  const _EtapeApercu({required this.state});

  Future<void> _previsualiser(BuildContext context) async {
    final cubit = context.read<NouveauRapportCubit>();
    final chemin = await cubit.cheminPrevisualisation();
    if (chemin == null || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DocumentViewerPage(
        document: ChantierDocument(
          id: cubit.state.rapportId ?? 'apercu',
          chantierId: cubit.state.chantierId ?? '',
          nomFichier: 'previsualisation.pdf',
          fichierUrl: chemin,
          mimeType: 'application/pdf',
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<NouveauRapportCubit>();
    final resume = state.resume;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.modele?.label(l10n) ?? '',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (state.action == ActionWizard.resume || (resume == null && state.resumeErreur == null))
                Text(l10n.rapportResumeChargement, style: const TextStyle(color: AppColors.textMuted))
              else if (resume == null)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.resumeErreur ?? l10n.rapportResumeIndisponible,
                        style: const TextStyle(color: AppColors.danger, fontSize: 13),
                      ),
                    ),
                    TextButton(onPressed: cubit.actualiserResume, child: Text(l10n.commonRetry)),
                  ],
                )
              else ...[
                Text(
                  l10n.rapportResumeReserves(resume.total),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(l10n.rapportResumeEntreprises(resume.entreprises),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in StatutReserveRapport.values)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text('${s.label(l10n)} : ${resume.parStatut[s] ?? 0}', style: const TextStyle(fontSize: 12)),
                      ),
                  ],
                ),
                if (resume.total == 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(l10n.rapportResumeVide, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: state.occupe ? null : () => _previsualiser(context),
          icon: const Icon(Icons.visibility_outlined, size: 18),
          label: Text(l10n.rapportPrevisualiserBouton),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: state.occupe ? null : cubit.generer,
          icon: state.action == ActionWizard.generation
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.picture_as_pdf_rounded, size: 18),
          label: Text(state.action == ActionWizard.generation ? l10n.rapportGeneration : l10n.rapportGenererBouton),
        ),
        const SizedBox(height: 8),
        Text(l10n.rapportGenerationLongue, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 8),
        TextButton(
          onPressed: state.occupe
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final id = await cubit.enregistrer();
                  if (id != null) messenger.showSnackBar(SnackBar(content: Text(l10n.rapportBrouillonEnregistre)));
                },
          child: Text(l10n.rapportEnregistrerBrouillon),
        ),
      ],
    );
  }
}

/* ══════════════════════════════════════════════════════════════════════════
   Éléments communs
   ══════════════════════════════════════════════════════════════════════════ */

class _BarreNavigation extends StatelessWidget {
  final NouveauRapportState state;
  const _BarreNavigation({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<NouveauRapportCubit>();
    final bloque = state.occupe ||
        (state.etape == EtapeRapport.projet && state.chantierId == null) ||
        (state.etape == EtapeRapport.modele && state.modele == null);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (state.indexEtape > 0)
            OutlinedButton.icon(
              onPressed: state.occupe ? null : cubit.precedent,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text(l10n.rapportPrecedent),
            ),
          const Spacer(),
          if (state.etape != EtapeRapport.apercu)
            FilledButton.icon(
              onPressed: bloque ? null : cubit.suivant,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(l10n.rapportSuivant),
            ),
        ],
      ),
    );
  }
}

class _TitreEtape extends StatelessWidget {
  final String texte;
  const _TitreEtape(this.texte);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(texte, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );
}

class _CarteChoix extends StatelessWidget {
  final String titre;
  final String? sousTitre;
  final bool choisi;
  final VoidCallback onTap;

  const _CarteChoix({required this.titre, required this.choisi, required this.onTap, this.sousTitre});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: choisi ? AppColors.primary : AppColors.border, width: choisi ? 1.6 : 1),
            ),
            child: Row(
              children: [
                Icon(
                  choisi ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: choisi ? AppColors.primary : AppColors.textMuted,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titre, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                      if (sousTitre != null && sousTitre!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(sousTitre!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.3)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
