import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/user_role.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_alert.dart';
import '../../../../core/widgets/chantier_picker_sheet.dart';
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

  /// Parcours d'import : chantier → fichier → nom et format → envoi.
  ///
  /// Le chantier n'est demandé que depuis l'onglet transversal ; ouvert depuis
  /// un chantier, l'écran connaît déjà le sien.
  Future<void> _importer() async {
    final cubit = context.read<PlansListCubit>();

    var chantierId = widget.chantierId;
    if (chantierId == null) {
      final chantier = await choisirChantier(context, titre: context.l10n.planImporterBouton);
      if (chantier == null || !mounted) return;
      chantierId = chantier.id;
    }

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
      chantierIdCourant: widget.chantierId,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Le serveur réserve l'import aux rôles OPERATIONNEL_CONTROLE (voir
    // `backend/src/modules/plan/route/plan.route.js`).
    final peutImporter = context.select(
      (AuthBloc b) => b.state.utilisateur?.role.estOperationnelOuControle ?? false,
    );

    return Scaffold(
      // Blanc, comme la maquette. La LISTE repose sur le gris de fond (voir
      // _Liste) : des cartes blanches sur une page blanche perdraient tout
      // relief.
      backgroundColor: AppColors.surface,
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
            final l10n = context.l10n;
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
                            onImporter: _importer,
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
  final VoidCallback onImporter;

  const _EtatVide({
    required this.rechercheActive,
    required this.peutImporter,
    required this.importEnCours,
    required this.onImporter,
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
              icon: Icons.cloud_upload_outlined,
              label: l10n.planImporterBouton,
              enCours: importEnCours,
              onTap: onImporter,
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
        onRefresh: () => context.read<PlansListCubit>().charger(chantierId: chantierId),
        child: ContenuCentre(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
            children: [
              // « Mes plans » met en avant le plan le plus récemment déposé :
              // c'est celui sur lequel on revient le plus souvent juste après
              // l'avoir importé. Le reste suit dans la liste complète.
              TitreSectionPlans(context.l10n.planMesPlans),
              const SizedBox(height: 10),
              _CartePlan(
                plan: plans.first,
                avecChantier: avecChantier,
                miseEnAvant: true,
                onTap: () => context.push('/plans/${plans.first.id}'),
              ),
              if (plans.length > 1) ...[
                const SizedBox(height: 22),
                TitreSectionPlans(context.l10n.planTousLesPlans, compteur: plans.length - 1),
                const SizedBox(height: 10),
                for (var i = 1; i < plans.length; i++) ...[
                  _CartePlan(
                    plan: plans[i],
                    avecChantier: avecChantier,
                    onTap: () => context.push('/plans/${plans[i].id}'),
                  ),
                  if (i < plans.length - 1) const SizedBox(height: 10),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CartePlan extends StatelessWidget {
  final Plan plan;
  final bool avecChantier;
  final VoidCallback onTap;

  /// Carte de tête de la section « Mes plans » — liseré et vignette teintés de
  /// l'orange de marque, pour la détacher de la liste qui suit.
  final bool miseEnAvant;

  const _CartePlan({
    required this.plan,
    required this.avecChantier,
    required this.onTap,
    this.miseEnAvant = false,
  });

  /// Couleur stable dérivée de l'identifiant — voir `reserve_card.dart` pour
  /// le raisonnement (un index de liste changerait au moindre filtre).
  static const List<Color> _palette = [
    Color(0xFF4F86F7),
    Color(0xFF34C759),
    Color(0xFF8B5CF6),
    Color(0xFFF5A623),
    Color(0xFF00BCD4),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final couleur =
        miseEnAvant ? AppColors.primary : _palette[plan.id.hashCode.abs() % _palette.length];

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border(left: BorderSide(color: couleur, width: 4)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4)),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Aperçu de la première page du plan, plutôt qu'un pictogramme :
              // c'est ce qui permet de reconnaître un plan sans l'ouvrir.
              // L'icône reste le repli (format non rendu, réseau coupé…).
              PlanVignette(
                plan: plan,
                icone: miseEnAvant ? Icons.map_rounded : Icons.description_outlined,
                couleur: couleur,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      plan.nom,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (avecChantier && plan.chantierNom != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        plan.chantierNom!,
                        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 9),
                    MetaPlan(plan: plan),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onTap,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary, width: 1.4),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.visibility_outlined, size: 15),
                    label: Text(
                      l10n.planDetailBouton,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
