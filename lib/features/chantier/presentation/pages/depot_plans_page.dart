import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../plan/domain/entities/plan.dart';
import '../../../plan/presentation/widgets/plan_vignette.dart';
import '../../../referentiel/domain/entities/code_niveau.dart';
import '../../../reserve/domain/entities/chantier_structure.dart';
import '../cubit/depot_plans_cubit.dart';
import '../widgets/demande_chantier_sheet.dart';
import '../widgets/niveau_sheet.dart';
import '../../../../core/network/forcer_reseau.dart';

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
  /// Chantier visé, ou `null` pour un dépôt qui PRÉCÈDE la demande — le
  /// parcours décrit par le client : les plans d'abord, le formulaire ensuite.
  final String? chantierId;
  final String? chantierNom;

  const DepotPlansPage({super.key, this.chantierId, this.chantierNom});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DepotPlansCubit(
        chantierId: chantierId,
        getStructure: sl(),
        getPlans: sl(),
        getCodes: sl(),
        creerCode: sl(),
        // Le référentiel des codes d'APPARTEMENT — « A001 » à « A015 » servis
        // par le serveur, et le « + » qui en ajoute pour toute l'organisation.
        getCodesAppartement: sl(),
        creerCodeAppartement: sl(),
        creerBatiment: sl(),
        creerEtage: sl(),
        // Manquait à l'appel alors que le cubit l'exige : l'application ne
        // compilait plus. `CreerZone` est enregistré dans le conteneur
        // (`injection_container.dart:292`) et le cubit s'en sert pour les
        // zones d'un niveau (`depot_plans_cubit.dart:375` et `:607`).
        creerZone: sl(),
        // Les trois gestes que le client demande sur un appartement déjà créé
        // — renommer, supprimer, et gérer ses plans — passent par le serveur
        // comme les ajouts : `POST/PUT/DELETE .../zones` et `DELETE /plans/:id`.
        modifierZone: sl(),
        supprimerZone: sl(),
        supprimerPlan: sl(),
        remplacerFichierPlan: sl(),
        uploaderPlan: sl(),
      )..charger(),
      child: _Vue(chantierNom: chantierNom),
    );
  }
}

class _Vue extends StatelessWidget {
  final String? chantierNom;

  const _Vue({required this.chantierNom});

  /// « Envoyer » — le geste qui clôt le dépôt et ouvre la demande.
  ///
  /// L'ordre décrit par le client : les plans d'abord, le formulaire de
  /// demande ensuite, et le rattachement à sa validation. C'est aussi le seul
  /// ordre où le courriel des valideurs annonce une demande COMPLÈTE : le
  /// formulaire en premier leur envoyait un chantier vide, les plans arrivant
  /// après.
  ///
  /// Rien n'est encore parti au serveur à cet instant : le message « Plans
  /// envoyés » n'apparaît qu'une fois le téléversement réellement terminé.
  /// L'annoncer avant l'envoi serait plus fidèle au brief mais faux — et un
  /// dépôt raté passerait pour un succès.
  Future<void> _envoyer(BuildContext context) async {
    final cubit = context.read<DepotPlansCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    if (!cubit.aQuelqueChoseAEnvoyer) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.depotRienAEnvoyer)));
      return;
    }

    final chantier = await demanderChantier(context);
    if (chantier == null || !context.mounted) return;

    final echec = await cubit.envoyerVers(chantier.id);
    if (!context.mounted) return;

    if (echec == null) {
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.depotPlansEnvoyes),
        backgroundColor: AppColors.success,
      ));
    }
    // Un échec partiel n'est pas annoncé ici : le cubit l'a déjà posé dans
    // l'état, le bandeau l'affiche, et l'écran montre désormais l'état RÉEL
    // du serveur — donc ce qui reste à reprendre.
  }

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
      // Le bouton vit en BAS et hors de la liste : il conclut le parcours, et
      // le chercher au bout d'un défilement de dix niveaux serait pénible.
      bottomNavigationBar: !context.read<DepotPlansCubit>().brouillon
          ? null
          : BlocBuilder<DepotPlansCubit, DepotPlansState>(
              builder: (context, etat) => SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: etat.envoiEnCours ? null : () => _envoyer(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: Text(
                    l10n.depotEnvoyer,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
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
      onRefresh: forcerReseau(context.read<DepotPlansCubit>().charger),
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
              // `Flexible` + ellipse : le libellé est traduit, et « Gebäude
              // hinzufügen » à côté du titre de section dépassait de 34 points
              // sur un téléphone de 320 dp — mesuré par le balayage des
              // formats. L'icône « + » reste, elle, toujours visible : c'est
              // elle qui porte le sens de l'action.
              Flexible(
                child: TextButton.icon(
                  onPressed: () => _ajouterBatiment(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(
                    l10n.depotAjouterBatiment,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
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
      appartements: saisie.appartements,
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
              // Même raison qu'au-dessus : un libellé traduit à côté d'un titre
              // de section, sur la largeur d'un petit téléphone.
              Flexible(
                child: TextButton.icon(
                  onPressed: () => _ajouter(context),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text(
                    l10n.depotAjouterNiveau,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
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
            for (final n in niveaux)
              _LigneNiveau(batiment: batiment, niveau: n, plans: plans),
        ],
      ),
    );
  }
}

/// Un niveau, DÉPLIABLE sur ses appartements.
///
/// Le client : « il faut qu'on puisse voir du R+1 avec tous les plans des
/// appartements à l'intérieur ». La ligne ne se contente donc plus d'annoncer
/// le niveau : elle l'ouvre.
///
/// Les appartements VIENNENT DU SERVEUR — `EtageStructure.zones`, servi par la
/// structure du chantier. L'écran ne les invente pas : il montre ceux qui
/// existent et permet d'ajouter ceux qui manquent.
class _LigneNiveau extends StatelessWidget {
  final BatimentStructure batiment;
  final EtageStructure niveau;
  final List<Plan> plans;

  const _LigneNiveau({
    required this.batiment,
    required this.niveau,
    required this.plans,
  });

  /// Ce niveau a-t-il déjà son plan ?
  bool get _aUnPlan => plans.any((p) => p.etage?.id == niveau.id);

  Future<void> _ajouterAppartement(BuildContext context) async {
    final cubit = context.read<DepotPlansCubit>();
    final saisie = await _demanderAppartement(context);
    if (saisie == null) return;

    await cubit.ajouterAppartement(
      batimentId: batiment.id,
      etageId: niveau.id,
      code: saisie.code,
      plans: saisie.fichier == null
          ? const []
          : [SaisieFichierPlan(chemin: saisie.fichier!.chemin, nom: saisie.fichier!.nom)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Theme(
      // Le trait de séparation par défaut d'`ExpansionTile` couperait la carte
      // du bâtiment en deux à chaque niveau.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(left: 4, bottom: 8),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          _aUnPlan ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 17,
          // La pastille dit d'un coup d'œil ce qui reste à fournir : un
          // niveau créé sans son plan est le cas qu'on veut voir.
          color: _aUnPlan ? AppColors.success : AppColors.textMuted,
        ),
        title: Text(
          niveau.nom,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
        ),
        subtitle: Text(
          l10n.depotAppartementsCompte(niveau.zones.length),
          style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
        ),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.depotAppartementsTitre.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Flexible(
                child: TextButton.icon(
                  onPressed: () => _ajouterAppartement(context),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text(
                    l10n.depotAppartementAjouter,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ),
            ],
          ),
          if (niveau.zones.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.depotAppartementAucun,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
                ),
              ),
            )
          else
            for (final z in niveau.zones)
              _CarteAppartement(
                batiment: batiment,
                niveau: niveau,
                zone: z,
                // Les plans de CET appartement, et d'aucun autre.
                plans: plans.where((p) => p.zone?.id == z.id).toList(),
              ),
        ],
      ),
    );
  }
}

/// Un appartement et ses plans.
class _CarteAppartement extends StatelessWidget {
  final BatimentStructure batiment;
  final EtageStructure niveau;
  final ZoneStructure zone;
  final List<Plan> plans;

  const _CarteAppartement({
    required this.batiment,
    required this.niveau,
    required this.zone,
    required this.plans,
  });

  Future<void> _renommer(BuildContext context) async {
    final cubit = context.read<DepotPlansCubit>();
    final l10n = context.l10n;
    final nom = await _demanderTexte(
      context,
      titre: l10n.depotAppartementRenommer,
      libelle: l10n.depotAppartementNouveauNom,
      valeurInitiale: zone.nom,
    );
    if (nom == null) return;

    await cubit.renommerAppartement(
      batimentId: batiment.id,
      etageId: niveau.id,
      zoneId: zone.id,
      nom: nom,
    );
  }

  Future<void> _supprimer(BuildContext context) async {
    final cubit = context.read<DepotPlansCubit>();
    final l10n = context.l10n;
    // Un appartement emporte ses plans : la confirmation le dit, plutôt que de
    // le laisser découvrir après coup.
    final ok = await _confirmer(context, l10n.depotAppartementSupprimerConfirme(zone.nom));
    if (!ok) return;

    await cubit.supprimerAppartement(
      batimentId: batiment.id,
      etageId: niveau.id,
      zoneId: zone.id,
    );
  }

  Future<void> _ajouterPlan(BuildContext context) async {
    final cubit = context.read<DepotPlansCubit>();
    final fichier = await _choisirFichier();
    if (fichier == null) return;
    await cubit.ajouterPlanAppartement(
      zoneId: zone.id,
      cheminFichier: fichier.chemin,
      nom: fichier.nom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      margin: const EdgeInsets.only(bottom: 10, right: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.meeting_room_outlined, size: 17, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  zone.nom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _renommer(context),
                icon: const Icon(Icons.edit_outlined, size: 17),
                tooltip: l10n.depotAppartementRenommer,
                visualDensity: VisualDensity.compact,
                color: AppColors.textSecondary,
              ),
              IconButton(
                onPressed: () => _supprimer(context),
                icon: const Icon(Icons.delete_outline_rounded, size: 17),
                tooltip: l10n.commonDelete,
                visualDensity: VisualDensity.compact,
                color: AppColors.danger,
              ),
            ],
          ),
          if (plans.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 25, top: 2, bottom: 4),
              child: Text(
                l10n.depotPlanAucun,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            )
          else
            for (final plan in plans) _LignePlanAppartement(plan: plan),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _ajouterPlan(context),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
              label: Text(l10n.depotPlanAjouter, maxLines: 1, overflow: TextOverflow.ellipsis),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un plan d'appartement : sa VIGNETTE, son nom, et ce qu'on peut en faire.
class _LignePlanAppartement extends StatelessWidget {
  final Plan plan;

  const _LignePlanAppartement({required this.plan});

  /// Un plan encore en brouillon n'existe pas côté serveur : il n'a ni page de
  /// consultation ni version à remplacer. On ne propose donc que de le retirer.
  bool get _envoye => !plan.id.startsWith('brouillon-');

  Future<void> _remplacer(BuildContext context) async {
    final cubit = context.read<DepotPlansCubit>();
    final fichier = await _choisirFichier();
    if (fichier == null) return;
    await cubit.remplacerPlan(
      planId: plan.id,
      cheminFichier: fichier.chemin,
      nom: fichier.nom,
    );
  }

  Future<void> _supprimer(BuildContext context) async {
    final cubit = context.read<DepotPlansCubit>();
    final l10n = context.l10n;
    final ok = await _confirmer(context, l10n.depotPlanSupprimerConfirme(plan.nom));
    if (!ok) return;
    await cubit.supprimerPlanFichier(plan.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.only(left: 25, top: 4, bottom: 4, right: 2),
      child: Row(
        children: [
          // La vignette montre la PREMIÈRE PAGE du document : c'est ce qui
          // permet de reconnaître un plan sans l'ouvrir.
          PlanVignette(
            plan: plan,
            icone: Icons.description_outlined,
            couleur: AppColors.primary,
            taille: 44,
            rayon: 10,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  plan.nom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
                ),
                if (!_envoye)
                  Text(
                    l10n.depotPlanLocalNonEnvoye,
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          if (_envoye)
            IconButton(
              onPressed: () => context.push('/plans/${plan.id}'),
              icon: const Icon(Icons.visibility_outlined, size: 17),
              tooltip: l10n.depotPlanPrevisualiser,
              visualDensity: VisualDensity.compact,
              color: AppColors.textSecondary,
            ),
          IconButton(
            onPressed: () => _remplacer(context),
            icon: const Icon(Icons.swap_horiz_rounded, size: 17),
            tooltip: l10n.depotFichierRemplacer,
            visualDensity: VisualDensity.compact,
            color: AppColors.textSecondary,
          ),
          IconButton(
            onPressed: () => _supprimer(context),
            icon: const Icon(Icons.delete_outline_rounded, size: 17),
            tooltip: l10n.commonDelete,
            visualDensity: VisualDensity.compact,
            color: AppColors.danger,
          ),
        ],
      ),
    );
  }
}

/// Ce qu'un appartement ajouté depuis le niveau porte : son code, et un
/// premier plan facultatif.
class _SaisieAppartementRapide {
  final String code;
  final _FichierChoisi? fichier;
  const _SaisieAppartementRapide({required this.code, this.fichier});
}

/// Formulaire d'ajout d'un appartement — nom, puis plan avec APERÇU.
///
/// Le client demande de ne pas enregistrer l'image sans qu'on ait pu la
/// vérifier : le fichier choisi s'affiche donc dans la boîte, avec de quoi en
/// choisir un autre ou le retirer, avant toute validation.
Future<_SaisieAppartementRapide?> _demanderAppartement(BuildContext context) {
  final l10n = context.l10n;
  final cubit = context.read<DepotPlansCubit>();
  final ctrl = TextEditingController();

  return showDialog<_SaisieAppartementRapide>(
    context: context,
    builder: (dialogContext) {
      _FichierChoisi? fichier;
      String? codeChoisi;
      var creationOuverte = false;
      var creationEnCours = false;

      return StatefulBuilder(
        builder: (builderContext, setEtat) {
          // Le référentiel servi par le serveur — « A001 » à « A015 », plus ce
          // que l'organisation a ajouté. La MÊME liste que la feuille de
          // niveau : deux saisies divergentes du même logement ne se
          // rapprocheraient plus.
          final codes = cubit.state.codesAppartement;

          Future<void> creerCode() async {
            final saisi = ctrl.text.trim();
            if (saisi.isEmpty) return;
            setEtat(() => creationEnCours = true);
            final cree = await cubit.ajouterCodeAppartement(saisi);
            setEtat(() {
              creationEnCours = false;
              if (cree != null) {
                codeChoisi = cree.code;
                creationOuverte = false;
                ctrl.clear();
              }
            });
          }

          return AlertDialog(
          title: Text(l10n.depotAppartementAjouter),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: codeChoisi,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.depotAppartementCode,
                        isDense: true,
                        prefixIcon: const Icon(Icons.meeting_room_outlined, size: 20),
                      ),
                      items: [
                        for (final c in codes)
                          DropdownMenuItem(
                            value: c.code,
                            child: Text(c.libelle, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (v) => setEtat(() => codeChoisi = v),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Le « + » : créer un code absent, comme pour les niveaux.
                  IconButton.filledTonal(
                    tooltip: l10n.depotAppartementNouveauCode,
                    icon: Icon(creationOuverte ? Icons.close_rounded : Icons.add_rounded),
                    onPressed: () => setEtat(() {
                      creationOuverte = !creationOuverte;
                      ctrl.clear();
                    }),
                  ),
                ],
              ),
              if (creationOuverte) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ctrl,
                        autofocus: true,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: l10n.depotAppartementNouveauCode,
                          isDense: true,
                          prefixIcon: const Icon(Icons.tag_rounded, size: 20),
                        ),
                        onSubmitted: (_) => creerCode(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: creationEnCours ? null : creerCode,
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                      child: creationEnCours
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(l10n.depotNiveauCreerCode),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Text(
                l10n.depotAppartementPlan,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 6),
              if (fichier == null)
                OutlinedButton.icon(
                  onPressed: () async {
                    final choisi = await _choisirFichier();
                    if (choisi != null) setEtat(() => fichier = choisi);
                  },
                  icon: const Icon(Icons.upload_file_rounded, size: 17),
                  label: Text(l10n.depotNiveauChoisirFichier),
                )
              else
                Row(
                  children: [
                    const Icon(Icons.description_outlined, size: 18, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fichier!.nom,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        final choisi = await _choisirFichier();
                        if (choisi != null) setEtat(() => fichier = choisi);
                      },
                      icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                      tooltip: l10n.depotFichierRemplacer,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      onPressed: () => setEtat(() => fichier = null),
                      icon: const Icon(Icons.close_rounded, size: 17),
                      tooltip: l10n.depotFichierRetirer,
                      visualDensity: VisualDensity.compact,
                      color: AppColors.danger,
                    ),
                  ],
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () {
                // Un code CHOISI dans la liste, jamais une saisie libre : le
                // champ de création sert à alimenter le référentiel, pas à le
                // contourner.
                final code = codeChoisi;
                if (code == null || code.isEmpty) return;
                Navigator.of(dialogContext).pop(
                  _SaisieAppartementRapide(code: code, fichier: fichier),
                );
              },
              child: Text(l10n.commonConfirm),
            ),
          ],
        );
        },
      );
    },
  ).whenComplete(ctrl.dispose);
}

/// Petite boîte de saisie d'un texte — le renommage d'un appartement.
Future<String?> _demanderTexte(
  BuildContext context, {
  required String titre,
  required String libelle,
  String? valeurInitiale,
}) {
  final l10n = context.l10n;
  final ctrl = TextEditingController(text: valeurInitiale);

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(titre),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(labelText: libelle),
        onSubmitted: (v) =>
            Navigator.of(dialogContext).pop(v.trim().isEmpty ? null : v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () {
            final v = ctrl.text.trim();
            Navigator.of(dialogContext).pop(v.isEmpty ? null : v);
          },
          child: Text(l10n.commonConfirm),
        ),
      ],
    ),
  ).whenComplete(ctrl.dispose);
}

/// Confirmation d'un geste destructeur.
Future<bool> _confirmer(BuildContext context, String question) async {
  final l10n = context.l10n;
  final reponse = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      content: Text(question),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.commonDelete),
        ),
      ],
    ),
  );
  return reponse ?? false;
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

  // Le contrôleur est libéré À LA FERMETURE du dialogue, pas avant : il vit
  // aussi longtemps que le champ. Sans cela, chaque bâtiment ajouté laissait
  // derrière lui un `ChangeNotifier` et son écouteur de texte.
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
  ).whenComplete(ctrl.dispose);
}
