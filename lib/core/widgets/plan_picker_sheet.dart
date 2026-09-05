import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../features/plan/domain/entities/plan.dart';
import '../../features/plan/presentation/cubit/plans_list_cubit.dart';
import '../../features/plan/presentation/widgets/plan_vignette.dart';
import '../../injection_container.dart';
import '../../l10n/l10n_extension.dart';
import '../theme/app_colors.dart';
import 'apparition_en_cascade.dart';
import 'error_view.dart';
import 'liste_chrome.dart';
import 'loading_list.dart';

/// Sélecteur de plan d'un chantier — deuxième étape du parcours « + ».
///
/// ## Pourquoi une feuille et non un écran
///
/// C'est une ÉTAPE, pas une destination : l'utilisateur a appuyé sur « + »
/// pour créer une réserve, et on ne lui demande le plan que parce qu'une
/// réserve se situe sur un plan. Un écran plein l'aurait fait sortir de son
/// geste ; une feuille se referme d'un glissement et le ramène là où il était.
///
/// Le sélecteur de chantier (`choisirChantier`) suit exactement la même
/// grammaire — même bandeau dégradé, même recherche posée dessus. Les deux
/// étapes se succèdent sans que l'écran change de nature.
///
/// ## Trois issues, et pourquoi il en faut trois
///
///  - `null` : la feuille a été refermée — l'utilisateur abandonne, on ne va
///    nulle part ;
///  - `(plan: unPlan)` : le cas courant ;
///  - `(plan: null)` : il a explicitement choisi de continuer SANS plan.
///
/// Cette troisième issue n'est pas un raffinement : un chantier dont les plans
/// n'ont pas encore été déposés n'aurait, sans elle, aucune sortie. Le
/// parcours entier — chantier, puis plan, puis formulaire — se terminerait sur
/// une liste vide et une croix. Créer une réserve doit rester possible avant
/// que les plans n'arrivent.
Future<({Plan? plan})?> choisirPlan(
  BuildContext context, {
  required String chantierId,
  String? chantierNom,
}) {
  return showModalBottomSheet<({Plan? plan})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BlocProvider(
      create: (_) => sl<PlansListCubit>()..charger(chantierId: chantierId),
      child: _PlanPickerSheet(chantierNom: chantierNom),
    ),
  );
}

class _PlanPickerSheet extends StatefulWidget {
  final String? chantierNom;
  const _PlanPickerSheet({this.chantierNom});

  @override
  State<_PlanPickerSheet> createState() => _PlanPickerSheetState();
}

class _PlanPickerSheetState extends State<_PlanPickerSheet> {
  final _recherche = TextEditingController();

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _EnTete(controleur: _recherche, chantierNom: widget.chantierNom),
              Expanded(child: _Corps(scrollController: scrollController)),
            ],
          ),
        );
      },
    );
  }
}

class _EnTete extends StatelessWidget {
  final TextEditingController controleur;
  final String? chantierNom;

  const _EnTete({required this.controleur, this.chantierNom});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, AppColors.primary, AppColors.primaryLight],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ContenuCentre(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                    ),
                    child: const Icon(Icons.map_rounded, color: Colors.white, size: 21),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.planChoisirTitre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          // Le nom du chantier plutôt que « Sur quel plan ? »
                          // quand on le connaît : il rappelle l'étape déjà
                          // franchie, et évite d'avoir à se demander si on
                          // n'a pas choisi le mauvais chantier juste avant.
                          chantierNom ?? l10n.planChoisirSousTitre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip: l10n.commonClose,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ContenuCentre(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: TextField(
                controller: controleur,
                onChanged: (v) => context.read<PlansListCubit>().rechercher(v),
                decoration: InputDecoration(
                  hintText: l10n.planRechercheHint,
                  prefixIcon: const Icon(Icons.search_rounded, size: 21, color: AppColors.textMuted),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Corps extends StatelessWidget {
  final ScrollController scrollController;
  const _Corps({required this.scrollController});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<PlansListCubit, PlansListState>(
      builder: (context, state) {
        switch (state.status) {
          case PlansListStatus.initial:
          case PlansListStatus.chargement:
            return const LoadingList(itemCount: 4, itemHeight: 76);
          case PlansListStatus.erreur:
            return ErrorView(
              message: state.erreur ?? l10n.commonErrorUnknown,
              onRetry: () => context.read<PlansListCubit>().charger(),
            );
          case PlansListStatus.succes:
            final plans = state.itemsFiltres;
            if (plans.isEmpty) {
              return EtatVideIllustre(
                motif: state.filtreEnPlace ? MotifVide.recherche : MotifVide.plan,
                titre: state.filtreEnPlace ? l10n.commonNoResults : l10n.planAucunSurChantier,
                description: state.filtreEnPlace
                    ? l10n.planEssayerAutreMotCle
                    : l10n.planAucunSurChantierAide,
                // Seulement quand le chantier n'a AUCUN plan : une recherche
                // qui ne donne rien se corrige en changeant le mot-clé, pas en
                // renonçant au plan.
                cta: state.filtreEnPlace
                    ? null
                    : BoutonAction(
                        icon: Icons.arrow_forward_rounded,
                        label: l10n.planContinuerSansPlan,
                        onTap: () => Navigator.of(context).pop((plan: null)),
                      ),
              );
            }
            return ContenuCentre(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                itemCount: plans.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => ApparitionEnCascade(
                  rang: i,
                  child: _LignePlan(
                    plan: plans[i],
                    onTap: () => Navigator.of(context).pop((plan: plans[i])),
                  ),
                ),
              ),
            );
        }
      },
    );
  }
}

/// Une ligne de la liste — vignette, nom, format, chevron.
class _LignePlan extends StatelessWidget {
  final Plan plan;
  final VoidCallback onTap;

  const _LignePlan({required this.plan, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              PlanVignette(
                plan: plan,
                icone: Icons.description_outlined,
                couleur: AppColors.primary,
                taille: 46,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      plan.nom,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      plan.format.name.toUpperCase(),
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
