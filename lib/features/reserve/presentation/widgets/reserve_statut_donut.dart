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
    final entrees = parStatut.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));

    if (total == 0 || entrees.isEmpty) {
      return SizedBox(
        height: 160,
        child: Center(
          child: Text(context.l10n.dashboardAucuneReserve, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ),
      );
    }

    return Row(
      children: [
        SizedBox(
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
                  Text('$total', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  Text(context.l10n.dashboardKpiTotal, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in entrees) _LegendeLigne(statut: e.key, valeur: e.value, total: total),
            ],
          ),
        ),
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
      child: Row(
        children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: _couleurStatut(statut), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(statut.label(context.l10n), style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis),
          ),
          Text('$valeur ($pct%)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
