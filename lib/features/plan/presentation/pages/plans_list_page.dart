import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/apparition_en_cascade.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/chantier_picker_sheet.dart';
import '../../../../core/routes/app_router.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../core/widgets/loading_list.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/plan.dart';
import '../cubit/plans_list_cubit.dart';
import '../widgets/plan_vignette.dart';
import '../widgets/plans_chrome.dart';
import '../widgets/import_plan_sheet.dart';
import '../../../../core/network/forcer_reseau.dart';

/// Extensions acceptées à l'import.
///
/// Alignées sur la liste blanche du serveur (`allowedMimeTypes` dans
/// `backend/src/config/security.js`), qui vérifie EN PLUS les magic bytes du
/// fichier : un PDF renommé en `.png` est rejeté côté serveur. Filtrer ici
/// évite simplement à l'utilisateur de choisir un fichier voué au refus.
const _extensionsAcceptees = ['pdf', 'png', 'jpg', 'jpeg', 'webp'];

/// Liste des plans — onglet « Plans » (tous chantiers) ou plans d'un
/// chantier donné lorsque [chantierId] est fourni.
class PlansListPage extends StatelessWidget {
  final String? chantierId;
  const PlansListPage({super.key, this.chantierId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<PlansListCubit>()..charger(chantierId: chantierId),
      child: _PlansListView(chantierId: chantierId),
    );
  }
}

class _PlansListView extends StatefulWidget {
  final String? chantierId;
  const _PlansListView({required this.chantierId});

  @override
  State<_PlansListView> createState() => _PlansListViewState();
}

class _PlansListViewState extends State<_PlansListView> {
  bool get _estSousEcran => widget.chantierId != null;

  /// Ajout de plans depuis l'onglet transversal : chantier, puis l'écran de
  /// dépôt.
  ///
  /// ## Pourquoi le sélecteur de chantier puis un ÉCRAN, et non un fichier
  ///
  /// Un plan appartient à un chantier — l'onglet, lui, est transversal : il
  /// faut donc désigner le chantier avant toute chose. Le sélecteur propose
  /// aussi d'en CRÉER un : une entreprise qui arrive avec ses plans et aucun
  /// chantier enregistré tombait jusqu'ici sur une liste vide sans issue.
  ///
  /// Ensuite vient l'écran de dépôt et non un simple choix de fichier : les
  /// plans d'un chantier forment une structure — le plan global, puis les
  /// bâtiments, puis les niveaux de chacun. Envoyer les fichiers un à un
  /// laissait à l'utilisateur la charge de reconstituer cette structure
  /// ensuite, à la main, depuis un autre écran.
  Future<void> _ajouterPlans() async {
    final chantier = await choisirChantier(
      context,
      titre: context.l10n.planAjouterBouton,
      avecCreation: true,
      // Les demandes en attente sont ICI des cibles légitimes, et même les
      // seules pour une entreprise : `plan.service.js#_refusDepot` lui refuse
      // le dépôt dès que le chantier est validé. Sans elles, une entreprise
      // revenue le lendemain ne retrouvait plus sa demande.
      inclureMesDemandes: true,
    );
    if (chantier == null || !mounted || !context.mounted) return;

    context.push(
      '${AppRoutes.depotPlans.replaceFirst(':chantierId', chantier.id)}'
      '?nom=${Uri.encodeComponent(chantier.nom)}',
    );
  }

  /// Import d'un plan ISOLÉ — réservé à l'écran d'un chantier donné.
  ///
  /// Ici le chantier est connu et la structure existe déjà : on vient
  /// simplement ajouter une pièce, souvent une nouvelle version. Passer par
  /// l'écran de dépôt complet pour un seul fichier serait disproportionné.
  Future<void> _importer() async {
    final cubit = context.read<PlansListCubit>();
    final chantierId = widget.chantierId!;

    final choix = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _extensionsAcceptees,
      withData: false,
    );
    final chemin = choix?.files.singleOrNull?.path;
    if (chemin == null || !mounted) return;

    // Le nom du fichier sert de proposition : c'est presque toujours le bon,
    // et le retaper à chaque import serait pénible sur un chantier.
    final nomFichier = choix!.files.single.name;
    final detail = await demanderDetailPlan(context, nomPropose: nomFichier);
    if (detail == null || !mounted) return;

    await cubit.importer(
      chantierId: chantierId,
      cheminFichier: chemin,
      nom: detail.nom,
      format: detail.format,
      typePlan: detail.typePlan,
      datePlan: detail.datePlan,
      chantierIdCourant: widget.chantierId,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Le serveur réserve l'import aux rôles OPERATIONNEL_CONTROLE (voir
    // `backend/src/modules/plan/route/plan.route.js`).
    final peutImporter = context.select(
      (AuthBloc b) => b.state.utilisateur?.role.peutDeposerPlans ?? false,
    );
    final l10n = context.l10n;

    return Scaffold(
      // Blanc, comme la maquette. La LISTE repose sur le gris de fond (voir
      // _Liste) : des cartes blanches sur une page blanche perdraient tout
      // relief.
      backgroundColor: AppColors.surface,
      // Le bouton d'ajout doit rester atteignable une fois la liste REMPLIE.
      //
      // Il ne vivait que dans l'état vide : dès le premier plan déposé, plus
      // rien sur cet écran ne permettait d'en ajouter un deuxième. Le « + » de
      // la barre ne le propose plus non plus — il crée désormais une réserve.
      floatingActionButton: !peutImporter
          ? null
          : FloatingActionButton.extended(
              onPressed: _estSousEcran ? _importer : _ajouterPlans,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 6,
              icon: Icon(_estSousEcran ? Icons.cloud_upload_outlined : Icons.add_rounded),
              label: Text(
                _estSousEcran ? l10n.planImporterBouton : l10n.planAjouterBouton,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
      body: SafeArea(
        bottom: false,
        child: BlocConsumer<PlansListCubit, PlansListState>(
          listenWhen: (a, b) => a.messageSucces != b.messageSucces || a.erreur != b.erreur,
          listener: (context, state) {
            if (state.messageSucces != null) {
              AppAlert.success(context, message: state.messageSucces!);
              context.read<PlansListCubit>().effacerMessage();
            } else if (state.erreur != null && state.status == PlansListStatus.succes) {
              // Échec d'import : la liste reste affichée, seule une alerte
              // signale le problème. Une erreur de CHARGEMENT, elle, est déjà
              // rendue en pleine page par ErrorView ci-dessous.
              AppAlert.error(context, message: state.erreur!);
              context.read<PlansListCubit>().effacerMessage();
            }
          },
          builder: (context, state) {
            return Column(
              children: [
                ContenuCentre(
                  child: EnTeteListe(
                    titre: l10n.navPlans,
                    avecRetour: _estSousEcran,
                    // Ouvert depuis un chantier, l'écran est HORS de la
                    // coquille : le NotificationsCubit dont dépend la cloche
                    // n'y est pas fourni.
                    avecCloche: !_estSousEcran,
                  ),
                ),
                ContenuCentre(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onChanged: (v) => context.read<PlansListCubit>().rechercher(v),
                            decoration: InputDecoration(
                              hintText: l10n.planRechercheHint,
                              prefixIcon: const Icon(Icons.search_rounded, size: 21, color: AppColors.textMuted),
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
                        const BoutonFiltrerPlans(),
                      ],
                    ),
                  ),
                ),
                const RangeeFiltresPlan(),
                Expanded(
                  child: switch (state.status) {
                    PlansListStatus.initial || PlansListStatus.chargement => const LoadingList(),
                    PlansListStatus.erreur => ErrorView(
                        message: state.erreur ?? l10n.commonErrorUnknown,
                        onRetry: () => context.read<PlansListCubit>().charger(chantierId: widget.chantierId),
                      ),
                    PlansListStatus.succes => state.itemsFiltres.isEmpty
                        ? _EtatVide(
                            rechercheActive: state.filtreEnPlace,
                            peutImporter: peutImporter,
                            importEnCours: state.importEnCours,
                            sousEcranChantier: _estSousEcran,
                            onAjouter: _estSousEcran ? _importer : _ajouterPlans,
                          )
                        : _Liste(
                            plans: state.itemsFiltres,
                            avecChantier: !_estSousEcran,
                            chantierId: widget.chantierId,
                          ),
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EtatVide extends StatelessWidget {
  final bool rechercheActive;
  final bool peutImporter;
  final bool importEnCours;

  /// Ouvert depuis UN chantier : le bouton importe un fichier. Depuis
  /// l'onglet transversal, il ouvre le parcours de dépôt complet.
  final bool sousEcranChantier;

  final VoidCallback onAjouter;

  const _EtatVide({
    required this.rechercheActive,
    required this.peutImporter,
    required this.importEnCours,
    required this.sousEcranChantier,
    required this.onAjouter,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (rechercheActive) {
      return EtatVideIllustre(
        motif: MotifVide.recherche,
        titre: l10n.commonNoResults,
        description: l10n.planEssayerAutreMotCle,
      );
    }

    return EtatVideIllustre(
      motif: MotifVide.plan,
      titre: l10n.planAucun,
      description: peutImporter ? l10n.planAucunDescriptionPeutImporter : l10n.planAucunDescriptionSansDroit,
      cta: peutImporter
          ? BoutonAction(
              icon: sousEcranChantier ? Icons.cloud_upload_outlined : Icons.add_rounded,
              label: sousEcranChantier ? l10n.planImporterBouton : l10n.planAjouterBouton,
              enCours: importEnCours,
              onTap: onAjouter,
            )
          : null,
    );
  }
}

class _Liste extends StatelessWidget {
  final List<Plan> plans;
  final bool avecChantier;
  final String? chantierId;

  const _Liste({required this.plans, required this.avecChantier, required this.chantierId});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: forcerReseau(() => context.read<PlansListCubit>().charger(chantierId: chantierId)),
        // `CustomScrollView` et non un `ListView` à enfants explicites.
        //
        // ## Pourquoi ce n'est pas cosmétique
        //
        // Un `ListView(children: [...])` construit TOUS ses enfants dès la
        // première image. Or chaque carte porte une [PlanVignette], qui
        // télécharge le PDF et en rasterise la première page. Trente plans,
        // c'était donc trente téléchargements et trente rendus natifs lancés
        // ensemble — pour deux ou trois cartes réellement visibles. L'écran
        // se figeait à l'ouverture, et le reste de l'application avec lui.
        //
        // Un sliver paresseux ne construit que ce qui approche de l'écran :
        // les vignettes se rendent au fil du défilement.
        child: ContenuCentre(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                sliver: SliverList.list(
                  children: [
                    // « Mes plans » met en avant le plan le plus récemment
                    // déposé : c'est celui sur lequel on revient le plus
                    // souvent juste après l'avoir importé. Le reste suit dans
                    // la liste complète.
                    TitreSectionPlans(context.l10n.planMesPlans),
                    const SizedBox(height: 10),
                    ApparitionEnCascade(
                      rang: 0,
                      child: _CartePlan(
                        plan: plans.first,
                        avecChantier: avecChantier,
                        miseEnAvant: true,
                        onTap: () => context.push('/plans/${plans.first.id}'),
                      ),
                    ),
                    if (plans.length > 1) ...[
                      const SizedBox(height: 22),
                      TitreSectionPlans(context.l10n.planTousLesPlans, compteur: plans.length - 1),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                sliver: SliverList.separated(
                  itemCount: plans.length > 1 ? plans.length - 1 : 0,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, i) {
                    final plan = plans[i + 1];
                    return ApparitionEnCascade(
                      rang: i + 1,
                      child: _CartePlan(
                        plan: plan,
                        avecChantier: avecChantier,
                        onTap: () => context.push('/plans/${plan.id}'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Carte d'un plan : le PLAN d'abord, ses informations ensuite.
///
/// ## Ce qu'elle remplace
///
/// L'ancienne carte posait côte à côte une vignette de 52 points, une colonne
/// de texte et un bouton « Détail ». Sur un téléphone de 360 points, le texte
/// n'avait plus que 98 points de large : la ligne date + format débordait de
/// 95 points, le nom s'écrasait, et l'ombre — peinte PAR-DESSUS le fond blanc
/// — grisait toute la carte. On voyait un grand bloc gris et un timbre-poste
/// rogné (`BoxFit.cover`) qui ne montrait pas le plan.
///
/// Désormais : l'aperçu occupe toute la largeur, le plan est montré EN ENTIER
/// (`BoxFit.contain`) comme une feuille posée sur la table, rendu assez fin
/// pour qu'on en lise les traits. La carte entière s'ouvre au toucher : le
/// bouton « Détail » ne faisait que répéter ce geste.
class _CartePlan extends StatelessWidget {
  final Plan plan;
  final bool avecChantier;
  final VoidCallback onTap;

  /// Carte de tête de la section « Mes plans » — aperçu plus haut et contour
  /// orange, pour la détacher de la liste qui suit.
  final bool miseEnAvant;

  const _CartePlan({
    required this.plan,
    required this.avecChantier,
    required this.onTap,
    this.miseEnAvant = false,
  });

  /// Où se trouve le plan : chantier (liste transversale) puis bâtiment,
  /// niveau, appartement — « Résidence Les Almadies · Bâtiment A · R+2 ».
  String? _emplacement() {
    final parties = <String>[
      if (avecChantier && plan.chantierNom != null) plan.chantierNom!,
      for (final niveau in [plan.batiment, plan.etage, plan.zone])
        if (niveau != null && niveau.nom.trim().isNotEmpty) niveau.nom.trim(),
    ];
    return parties.isEmpty ? null : parties.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final emplacement = _emplacement();
    // La date DU PLAN quand elle est connue, sinon celle du dépôt.
    final date = plan.datePlan ?? plan.createdAt;
    final type = plan.typePlan?.trim();

    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: miseEnAvant ? AppColors.primary.withValues(alpha: 0.55) : AppColors.border,
          width: miseEnAvant ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ApercuPlan(plan: plan, miseEnAvant: miseEnAvant),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 13),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.nom,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            height: 1.25,
                          ),
                        ),
                        if (emplacement != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            emplacement,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                          ),
                        ],
                        if (date != null || (type != null && type.isNotEmpty)) ...[
                          const SizedBox(height: 8),
                          // `Wrap` et non `Row` : c'est une rangée de ce genre qui
                          // débordait. Trop longue, elle passe à la ligne.
                          Wrap(
                            spacing: 14,
                            runSpacing: 4,
                            children: [
                              if (date != null)
                                _InfoPlan(icone: Icons.event_outlined, texte: dateCourtePlan(context, date)),
                              if (type != null && type.isNotEmpty)
                                _InfoPlan(icone: Icons.category_outlined, texte: type),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// L'aperçu du plan, en tête de carte : la feuille sur la table.
class _ApercuPlan extends StatelessWidget {
  final Plan plan;
  final bool miseEnAvant;

  const _ApercuPlan({required this.plan, required this.miseEnAvant});

  /// Gris très clair, légèrement bleuté : la « table » sur laquelle la feuille
  /// blanche du plan se détache sans cadre appuyé.
  static const Color _table = Color(0xFFE9EDF2);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final aTraiter = plan.nombreReservesATraiter;
    // « 3 à traiter » quand le serveur le sait, sinon le total des réserves.
    final String? reserves = (aTraiter != null && aTraiter > 0)
        ? l10n.planCtxNATraiter(aTraiter)
        : (plan.nombreReserves > 0 ? l10n.planExplorerNReserves(plan.nombreReserves) : null);

    return AspectRatio(
      key: ValueKey('apercu-${plan.id}'),
      aspectRatio: miseEnAvant ? 4 / 3 : 16 / 10,
      child: ColoredBox(
        color: _table,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: DecoratedBox(
                // Ombre SOUS la feuille (fond de la décoration, peint avant
                // l'enfant) — et non par-dessus comme l'ancienne carte.
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: PlanVignette(
                  plan: plan,
                  icone: Icons.map_outlined,
                  couleur: AppColors.primary,
                  taille: double.infinity,
                  largeur: double.infinity,
                  rayon: 6,
                  ajustement: BoxFit.contain,
                  fond: Colors.white,
                  // Assez fin pour une carte pleine largeur sur un écran à
                  // densité 3, sans peser comme le PDF d'origine.
                  largeurRendu: 900,
                ),
              ),
            ),
            if (plan.version > 1)
              Positioned(
                top: 18,
                right: 18,
                child: _PastilleApercu(texte: 'v${plan.version}'),
              ),
            if (reserves != null)
              Positioned(
                left: 18,
                bottom: 18,
                child: _PastilleApercu(
                  texte: reserves,
                  icone: Icons.flag_rounded,
                  accent: aTraiter != null && aTraiter > 0,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Étiquette posée sur l'aperçu : version, réserves.
class _PastilleApercu extends StatelessWidget {
  final String texte;
  final IconData? icone;

  /// Orange de marque : ce qui demande une action (réserves à traiter).
  final bool accent;

  const _PastilleApercu({required this.texte, this.icone, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final couleur = accent ? Colors.white : AppColors.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: accent ? AppColors.primary : Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, size: 13, color: couleur),
            const SizedBox(width: 4),
          ],
          Text(texte, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: couleur)),
        ],
      ),
    );
  }
}

/// Une information de pied de carte : icône discrète et texte.
class _InfoPlan extends StatelessWidget {
  final IconData icone;
  final String texte;

  const _InfoPlan({required this.icone, required this.texte});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            texte,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}
