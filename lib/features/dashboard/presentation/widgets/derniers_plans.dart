import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routes/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../../plan/domain/entities/plan.dart';
import '../../../plan/presentation/cubit/plans_list_cubit.dart';
import '../../../plan/presentation/widgets/plan_vignette.dart';

/// Nombre de plans montrés — demandé par le client.
const _combien = 8;

/// Les [_combien] plans les plus récents.
///
/// Un plan sans date passe EN DERNIER plutôt que de remonter en tête : un
/// `createdAt` absent est une information manquante, pas une date nulle, et
/// le trier comme telle mettrait les plans les moins renseignés en avant.
///
/// La liste reçue n'est pas modifiée : elle appartient à l'état du cubit.
@visibleForTesting
List<Plan> derniersPlans(List<Plan> plans) {
  final tries = [...plans]
    ..sort((a, b) {
      final da = a.createdAt, db = b.createdAt;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
  return tries.take(_combien).toList();
}

/// Bande horizontale des derniers plans ajoutés.
///
/// ── Pourquoi ici ──────────────────────────────────────────────────────────
/// Entre « Vue d'ensemble » et « Aperçu général » : le chef de chantier ouvre
/// l'application pour aller sur un plan, et devait jusqu'ici passer par
/// l'onglet Plans puis chercher. Les huit derniers couvrent l'écrasante
/// majorité des ouvertures.
///
/// ── Défilement ────────────────────────────────────────────────────────────
/// Au doigt, et par les deux flèches. Celles-ci s'effacent en bout de course
/// plutôt que de rester grisées : un bouton visible mais inerte fait douter
/// que l'appui ait été pris en compte.
class DerniersPlans extends StatelessWidget {
  /// Espace laisse SOUS la bande.
  ///
  /// Porte par le widget et non par le parent : sans plan a montrer la bande
  /// se replie sur du vide, et une marge ecrite cote parent laisserait alors
  /// un trou entre les deux blocs qui l'encadrent.
  final double margeBas;

  const DerniersPlans({super.key, this.margeBas = 18});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<PlansListCubit>()..charger(),
      child: _Bande(margeBas: margeBas),
    );
  }
}

class _Bande extends StatefulWidget {
  final double margeBas;

  const _Bande({required this.margeBas});

  @override
  State<_Bande> createState() => _BandeState();
}

class _BandeState extends State<_Bande> {
  final _defilement = ScrollController();

  /// Largeur d'une carte plus son écart — le pas d'un appui sur une flèche.
  static const _pas = 172.0;
  static const _hauteur = 186.0;

  @override
  void initState() {
    super.initState();
    // Redessine les flèches quand on atteint une extrémité.
    _defilement.addListener(_rafraichir);
  }

  @override
  void dispose() {
    _defilement
      ..removeListener(_rafraichir)
      ..dispose();
    super.dispose();
  }

  void _rafraichir() {
    if (mounted) setState(() {});
  }

  bool get _peutReculer => _defilement.hasClients && _defilement.offset > 4;

  bool get _peutAvancer =>
      _defilement.hasClients &&
      _defilement.offset < _defilement.position.maxScrollExtent - 4;

  void _glisser(int sens) {
    if (!_defilement.hasClients) return;
    final cible = (_defilement.offset + sens * _pas * 2)
        .clamp(0.0, _defilement.position.maxScrollExtent);
    _defilement.animateTo(
      cible,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<PlansListCubit, PlansListState>(
      builder: (context, etat) {
        // Rien tant qu'il n'y a rien à montrer : une section vide entre deux
        // blocs pleins ferait croire à un défaut d'affichage.
        if (etat.status == PlansListStatus.chargement && etat.items.isEmpty) {
          return const SizedBox.shrink();
        }
        if (etat.items.isEmpty) return const SizedBox.shrink();

        final derniers = derniersPlans(etat.items);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.dashboardDerniersPlans,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                _Fleche(
                  icone: Icons.chevron_left_rounded,
                  actif: _peutReculer,
                  libelle: l10n.dashboardPlansPrecedents,
                  onTap: () => _glisser(-1),
                ),
                const SizedBox(width: 6),
                _Fleche(
                  icone: Icons.chevron_right_rounded,
                  actif: _peutAvancer,
                  libelle: l10n.dashboardPlansSuivants,
                  onTap: () => _glisser(1),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: _hauteur,
              child: ListView.separated(
                controller: _defilement,
                scrollDirection: Axis.horizontal,
                // `ClampingScrollPhysics` : sur Android, l'effet élastique
                // d'iOS renverrait `offset` hors bornes et ferait clignoter
                // les flèches en fin de course.
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: derniers.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) => _Carte(plan: derniers[i]),
              ),
            ),
            SizedBox(height: widget.margeBas),
          ],
        );
      },
    );
  }
}

/// Flèche de défilement — masquée, et non grisée, en bout de course.
class _Fleche extends StatelessWidget {
  final IconData icone;
  final bool actif;
  final String libelle;
  final VoidCallback onTap;

  const _Fleche({
    required this.icone,
    required this.actif,
    required this.libelle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: actif ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: IgnorePointer(
        ignoring: !actif,
        child: Material(
          color: AppColors.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Tooltip(
              message: libelle,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(icone, size: 20, color: AppColors.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Une carte de la bande : l'aperçu réel du plan, son nom, son chantier.
class _Carte extends StatelessWidget {
  final Plan plan;

  const _Carte({required this.plan});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push(
            AppRoutes.planDetail.replaceFirst(':id', plan.id),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // L'aperçu de la PREMIÈRE PAGE, pas une icône générique :
                // c'est ce qui permet de reconnaître un plan d'un coup d'œil.
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                  child: PlanVignette(
                    plan: plan,
                    icone: Icons.map_rounded,
                    couleur: AppColors.primary,
                    taille: 112,
                    largeur: 160,
                    // Les angles sont deja arrondis par le `ClipRRect`, qui
                    // n'arrondit que le haut : un rayon ici redecouperait le
                    // bas et laisserait deux encoches sur le texte.
                    rayon: 0,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.nom,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        plan.chantierNom ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                      ),
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
