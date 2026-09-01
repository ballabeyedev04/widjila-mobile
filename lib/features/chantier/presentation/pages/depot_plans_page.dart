import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../plan/domain/entities/plan.dart';
import '../../../referentiel/domain/entities/code_niveau.dart';
import '../../../reserve/domain/entities/chantier_structure.dart';
import '../cubit/depot_plans_cubit.dart';
import '../widgets/niveau_sheet.dart';

/// Extensions acceptées — les mêmes que l'import de plan existant, et que
/// celles vérifiées par le serveur (`upload.validateMagicBytes`).
const _extensions = ['pdf', 'png', 'jpg', 'jpeg', 'dwg', 'dxf'];

/// Dépôt des plans d'un chantier.
///
/// Le parcours décrit par le client : l'entreprise dépose le plan GLOBAL, qui
/// montre les bâtiments ; elle entre dans un bâtiment et y trouve trois
/// sections — SOUS-SOLS · ÉTAGES · TOITURE — chacune avec son « + ».
///
/// Chaque ajout part au serveur SUR-LE-CHAMP. Sur un chantier, l'application
/// se ferme, la batterie tombe, le réseau saute : un brouillon de dix plans
/// perdu à la dernière seconde serait bien pire qu'un dépôt partiel, qui se
/// complète en rouvrant l'écran.
class DepotPlansPage extends StatelessWidget {
  final String chantierId;
  final String? chantierNom;

  const DepotPlansPage({super.key, required this.chantierId, this.chantierNom});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DepotPlansCubit(
        chantierId: chantierId,
        getStructure: sl(),
        getPlans: sl(),
        getCodes: sl(),
        creerCode: sl(),
        creerBatiment: sl(),
        creerEtage: sl(),
        uploaderPlan: sl(),
      )..charger(),
      child: _Vue(chantierNom: chantierNom),
    );
  }
}

class _Vue extends StatelessWidget {
  final String? chantierNom;

  const _Vue({required this.chantierNom});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.depotPlansTitre, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if (chantierNom != null)
              Text(
                chantierNom!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
          ],
        ),
      ),
      body: BlocConsumer<DepotPlansCubit, DepotPlansState>(
        listenWhen: (a, b) => a.erreur != b.erreur || a.messageSucces != b.messageSucces,
        listener: (context, etat) {
          final message = etat.erreur ?? etat.messageSucces;
          if (message == null) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: etat.erreur != null ? AppColors.danger : AppColors.success,
            ),
          );
          context.read<DepotPlansCubit>().effacerMessages();
        },
        builder: (context, etat) {
          if (etat.status == DepotStatus.chargement && etat.batiments.isEmpty) {
            return const LoadingList();
          }
          if (etat.status == DepotStatus.erreur) {
            return ErrorView(
              message: etat.erreur ?? '',
              onRetry: context.read<DepotPlansCubit>().charger,
            );
          }

          return Stack(
            children: [
              _Contenu(etat: etat),
              // Bandeau d'envoi plutôt qu'un voile opaque : la liste reste
              // lisible pendant le dépôt, et l'utilisateur voit ce qu'il a
              // déjà fourni.
              if (etat.envoiEnCours)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Material(
                    color: AppColors.primary,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            l10n.depotEnvoiEnCours,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Contenu extends StatelessWidget {
  final DepotPlansState etat;

  const _Contenu({required this.etat});

  /// Le plan GLOBAL du chantier : celui qui n'est rattaché à rien.
  Plan? get _planGlobal {
    for (final p in etat.plans) {
      if (p.batiment == null && p.etage == null && p.zone == null) return p;
    }
    return null;
  }

  Future<void> _deposerGlobal(BuildContext context) async {
    final fichier = await _choisirFichier();
    if (fichier == null || !context.mounted) return;
    context.read<DepotPlansCubit>().deposerPlanGlobal(
          cheminFichier: fichier.chemin,
          nom: fichier.nom,
        );
  }

  Future<void> _ajouterBatiment(BuildContext context) async {
    final nom = await _demanderNomBatiment(context);
    if (nom == null || !context.mounted) return;
    context.read<DepotPlansCubit>().ajouterBatiment(nom: nom);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final global = _planGlobal;

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: context.read<DepotPlansCubit>().charger,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ── Plan global ────────────────────────────────────────────────
          _TitreSection(l10n.depotPlanGlobal),
          const SizedBox(height: 8),
          _CarteAction(
            icone: global == null ? Icons.upload_file_rounded : Icons.check_circle_rounded,
            couleur: global == null ? AppColors.primary : AppColors.success,
            titre: global?.nom ?? l10n.depotNiveauChoisirFichier,
            sousTitre: l10n.depotPlanGlobalAide,
            onTap: () => _deposerGlobal(context),
          ),
          const SizedBox(height: 22),

          // ── Bâtiments ──────────────────────────────────────────────────
          Row(
            children: [
              Expanded(child: _TitreSection(l10n.depotBatiments)),
              TextButton.icon(
                onPressed: () => _ajouterBatiment(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(l10n.depotAjouterBatiment),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (etat.batiments.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: EmptyState(
                icon: Icons.apartment_outlined,
                title: l10n.depotAucunBatiment,
                subtitle: l10n.depotAucunBatimentAide,
              ),
            )
          else
            for (final b in etat.batiments)
              _CarteBatiment(batiment: b, plans: etat.plans),
        ],
      ),
    );
  }
}

/// Une carte de bâtiment, dépliable sur ses trois sections.
class _CarteBatiment extends StatelessWidget {
  final BatimentStructure batiment;
  final List<Plan> plans;

  const _CarteBatiment({required this.batiment, required this.plans});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.apartment_outlined, color: AppColors.primary),
        title: Text(
          batiment.nom,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        subtitle: Text(
          l10n.planNavNZones(batiment.etages.length),
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        children: [
          for (final type in TypeNiveau.values)
            _Section(batiment: batiment, type: type, plans: plans),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Une des trois sections — SOUS-SOLS, ÉTAGES ou TOITURE.
class _Section extends StatelessWidget {
  final BatimentStructure batiment;
  final TypeNiveau type;
  final List<Plan> plans;

  const _Section({required this.batiment, required this.type, required this.plans});

  String _titre(BuildContext context) {
    final l10n = context.l10n;
    switch (type) {
      case TypeNiveau.sousSol:
        return l10n.depotSectionSousSols;
      case TypeNiveau.etage:
        return l10n.depotSectionEtages;
      case TypeNiveau.toiture:
        return l10n.depotSectionToiture;
    }
  }

  Future<void> _ajouter(BuildContext context) async {
    final cubit = context.read<DepotPlansCubit>();
    final saisie = await ouvrirFeuilleNiveau(context, type: type, cubit: cubit);
    if (saisie == null) return;

    await cubit.ajouterNiveau(
      batimentId: batiment.id,
      typeNiveau: type,
      codeNiveau: saisie.code,
      description: saisie.description,
      cheminFichier: saisie.cheminFichier,
      nomFichier: saisie.nomFichier,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // La nature du niveau vient du serveur ; les étages saisis avant ce
    // référentiel valent tous « etage », par défaut de la migration.
    final niveaux = batiment.etages.where((e) => e.typeNiveau == type).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _titre(context),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _ajouter(context),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text(l10n.depotAjouterNiveau),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              ),
            ],
          ),
          if (niveaux.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.depotAucunNiveau,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
              ),
            )
          else
            for (final n in niveaux) _LigneNiveau(niveau: n, plans: plans),
        ],
      ),
    );
  }
}

class _LigneNiveau extends StatelessWidget {
  final EtageStructure niveau;
  final List<Plan> plans;

  const _LigneNiveau({required this.niveau, required this.plans});

  /// Ce niveau a-t-il déjà son plan ?
  bool get _aUnPlan => plans.any((p) => p.etage?.id == niveau.id);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            _aUnPlan ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 17,
            // La pastille dit d'un coup d'œil ce qui reste à fournir : un
            // niveau créé sans son plan est le cas qu'on veut voir.
            color: _aUnPlan ? AppColors.success : AppColors.textMuted,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              niveau.nom,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitreSection extends StatelessWidget {
  final String texte;
  const _TitreSection(this.texte);

  @override
  Widget build(BuildContext context) => Text(
        texte,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      );
}

class _CarteAction extends StatelessWidget {
  final IconData icone;
  final Color couleur;
  final String titre;
  final String sousTitre;
  final VoidCallback onTap;

  const _CarteAction({
    required this.icone,
    required this.couleur,
    required this.titre,
    required this.sousTitre,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(icone, color: couleur, size: 26),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sousTitre,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
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

// ── Saisie d'un fichier ──────────────────────────────────────────────────────

class _FichierChoisi {
  final String chemin;
  final String nom;
  const _FichierChoisi({required this.chemin, required this.nom});
}

Future<_FichierChoisi?> _choisirFichier() async {
  final choix = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: _extensions,
    withData: false,
  );
  final fichier = choix?.files.singleOrNull;
  final chemin = fichier?.path;
  if (fichier == null || chemin == null) return null;
  return _FichierChoisi(chemin: chemin, nom: fichier.name);
}

Future<String?> _demanderNomBatiment(BuildContext context) {
  final l10n = context.l10n;
  final ctrl = TextEditingController();

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.depotAjouterBatiment),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.depotBatimentNom),
        onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim().isEmpty ? null : v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            final v = ctrl.text.trim();
            Navigator.of(dialogContext).pop(v.isEmpty ? null : v);
          },
          child: Text(l10n.commonSave),
        ),
      ],
    ),
  );
}
