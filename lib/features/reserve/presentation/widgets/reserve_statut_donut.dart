import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/reserve.dart';

/// Couleur par statut — même mapping que [ReserveStatutBadge] (donc que
/// `admin/src/utils/constants.js#STATUTS_RESERVE`), pour que badges et
/// donut restent visuellement cohérents.
Color _couleurStatut(ReserveStatut s) {
  switch (s) {
    case ReserveStatut.creee:
      return AppColors.neutral;
    case ReserveStatut.affectee:
      return AppColors.info;
    case ReserveStatut.priseEnCharge:
      return AppColors.info;
    case ReserveStatut.enCours:
      return AppColors.warning;
    case ReserveStatut.corrigee:
      return AppColors.primary;
    case ReserveStatut.aVerifier:
      return AppColors.warning;
    case ReserveStatut.validee:
      return AppColors.success;
    case ReserveStatut.refusee:
      return AppColors.danger;
    case ReserveStatut.rouverte:
      return AppColors.danger;
    case ReserveStatut.enRetard:
      return AppColors.danger;
    case ReserveStatut.cloturee:
      return AppColors.neutral;
  }
}

/// Donut de répartition des réserves par statut. Les chiffres (paramètre
/// [parStatut]) viennent toujours d'un endpoint back (`/dashboard/...`) —
/// ce widget se contente de les dessiner, aucun calcul métier ici.
class ReserveStatutDonut extends StatelessWidget {
  final Map<ReserveStatut, int> parStatut;
  final int total;

  const ReserveStatutDonut({super.key, required this.parStatut, required this.total});

  @override
  Widget build(BuildContext context) {
    final entrees = parStatut.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (total == 0 || entrees.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text(
            context.l10n.dashboardAucuneReserve,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
      );
    }

    // ── Cote a cote, ou l'un sous l'autre ? ────────────────────────────────
    //
    // Le disque occupait 130 px FIXES et la legende recuperait le reste. Sur
    // un telephone de 320 dp, il ne restait que 106 px a la legende — moins
    // que la pastille, le libelle et le compteur reunis : la rangee debordait
    // de 9 px et le compteur passait sous le bord.
    //
    // Un `Wrap` plutot qu'une `Row` : quand les deux ne tiennent plus cote a
    // cote, la legende passe d'elle-meme sous le disque et recupere toute la
    // largeur — ou elle se lit d'ailleurs mieux qu'en colonne etroite.
    //
    // `Wrap` et non `LayoutBuilder` : le tableau de bord place cette carte
    // dans un `IntrinsicHeight` pour egaliser la hauteur des deux colonnes en
    // tablette, et un `LayoutBuilder` ne sait pas repondre a une mesure
    // intrinseque — il fait tomber la mise en page entiere des 700 dp.
    return Wrap(
      alignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 14,
      children: [
        _Disque(entrees: entrees, total: total),
        _Legende(entrees: entrees, total: total),
      ],
    );
  }
}

/// Le disque lui-meme, avec son total au centre.
class _Disque extends StatelessWidget {
  final List<MapEntry<ReserveStatut, int>> entrees;
  final int total;

  const _Disque({required this.entrees, required this.total});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      height: 130,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: [
                for (final e in entrees)
                  PieChartSectionData(
                    value: e.value.toDouble(),
                    color: _couleurStatut(e.key),
                    radius: 24,
                    showTitle: false,
                  ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$total',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                context.l10n.dashboardKpiTotal,
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// La legende : une ligne par statut represente.
class _Legende extends StatelessWidget {
  final List<MapEntry<ReserveStatut, int>> entrees;
  final int total;

  const _Legende({required this.entrees, required this.total});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in entrees) _LegendeLigne(statut: e.key, valeur: e.value, total: total),
      ],
    );
  }
}

class _LegendeLigne extends StatelessWidget {
  final ReserveStatut statut;
  final int valeur;
  final int total;
  const _LegendeLigne({required this.statut, required this.valeur, required this.total});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0 : (valeur / total * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      // `min` et non la valeur par defaut : dans un `Wrap`, une rangee qui
      // reclame toute la largeur disponible forcerait la legende a passer
      // systematiquement sous le disque, meme quand la place ne manque pas.
      // Elle se dimensionne donc a son contenu, et c'est le `Wrap` qui
      // tranche.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: _couleurStatut(statut), shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          // `Flexible` et non `Expanded` : le libelle prend sa largeur
          // naturelle quand la place le permet, et ne se tronque que
          // lorsqu'elle manque vraiment.
          Flexible(
            child: Text(
              statut.label(context.l10n),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 6),
          // Le compteur peut lui aussi manquer de place — une langue plus
          // longue, un texte systeme agrandi. Il retrecit en dernier recours
          // plutot que de pousser la rangee hors de l'ecran.
          Flexible(
            child: Text(
              '$valeur ($pct%)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
