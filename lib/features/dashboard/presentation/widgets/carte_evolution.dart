import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/dashboard_stats.dart';
import '../cubit/dashboard_state.dart';
import 'carte_tableau_de_bord.dart';

/// Les trois séries de la courbe, avec leur couleur — les mêmes que les
/// cartes KPI (« Levées » vert, « Traitées » violet) pour qu'un même mot ait
/// la même couleur d'un bout à l'autre de l'écran.
const _couleurCreees = AppColors.primary;
const _couleurTraitees = Color(0xFF7C3AED);
const _couleurLevees = AppColors.success;

/// Évolution mensuelle des réserves — créées, traitées, levées.
///
/// Les points viennent de `GET /dashboard/evolution`, calculés par le
/// serveur depuis l'historique des réserves. Ce widget les dessine, et sait
/// dire qu'il charge, qu'il a échoué, ou qu'il n'y a rien à montrer — jamais
/// un graphique vide sans explication.
class CarteEvolution extends StatelessWidget {
  final DashboardStatus status;
  final DashboardEvolution? evolution;

  const CarteEvolution({super.key, required this.status, required this.evolution});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CarteTableauDeBord(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EnTeteCarte(titre: l10n.dashboardEvolutionTitre, sousTitre: l10n.dashboardEvolutionSousTitre),
          const SizedBox(height: 16),
          _corps(context),
        ],
      ),
    );
  }

  Widget _corps(BuildContext context) {
    final l10n = context.l10n;
    final courbe = evolution;
    switch (status) {
      case DashboardStatus.initial:
      case DashboardStatus.chargement:
        return const SizedBox(
          height: 160,
          child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
        );
      case DashboardStatus.erreur:
        return _Message(texte: l10n.dashboardEvolutionErreur, icone: Icons.cloud_off_rounded);
      case DashboardStatus.succes:
        if (courbe == null || !courbe.aDesDonnees) {
          return _Message(texte: l10n.dashboardAucuneDonnee, icone: Icons.show_chart_rounded);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 180, child: _Courbe(series: courbe.series)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _LegendeSerie(couleur: _couleurCreees, label: l10n.dashboardEvolutionCreees),
                _LegendeSerie(couleur: _couleurTraitees, label: l10n.dashboardEvolutionTraitees),
                _LegendeSerie(couleur: _couleurLevees, label: l10n.dashboardEvolutionLevees),
              ],
            ),
          ],
        );
    }
  }
}

class _Message extends StatelessWidget {
  final String texte;
  final IconData icone;
  const _Message({required this.texte, required this.icone});

  @override
  Widget build(BuildContext context) {
    // Une hauteur MINIMALE, pas fixe : en gros texte, le message passe sur
    // deux lignes et une boîte de 120 px débordait.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 120),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, color: AppColors.textMuted, size: 26),
              const SizedBox(height: 8),
              Text(texte, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Courbe extends StatelessWidget {
  final List<DashboardEvolutionPoint> series;
  const _Courbe({required this.series});

  /// « sept. » plutôt que « 2026-09 » : le mois est ce qu'on lit, l'année se
  /// devine. Le format suit la langue de l'application.
  String _libelleMois(BuildContext context, String mois) {
    final parties = mois.split('-');
    if (parties.length != 2) return mois;
    final annee = int.tryParse(parties[0]);
    final m = int.tryParse(parties[1]);
    if (annee == null || m == null) return mois;
    return DateFormat.MMM(Localizations.localeOf(context).toString()).format(DateTime(annee, m));
  }

  @override
  Widget build(BuildContext context) {
    final maxY = series.fold<int>(0, (m, p) => [m, p.creees, p.traitees, p.levees].reduce((a, b) => a > b ? a : b));
    // Un pas d'axe lisible : au plus ~4 graduations.
    final pas = maxY <= 4 ? 1.0 : (maxY / 4).ceilToDouble();
    final plafond = (maxY / pas).ceil() * pas;

    LineChartBarData ligne(Color couleur, int Function(DashboardEvolutionPoint) valeur) => LineChartBarData(
          spots: [for (var i = 0; i < series.length; i++) FlSpot(i.toDouble(), valeur(series[i]).toDouble())],
          color: couleur,
          barWidth: 2.5,
          isCurved: true,
          curveSmoothness: 0.25,
          preventCurveOverShooting: true,
          dotData: FlDotData(
            show: true,
            getDotPainter: (_, _, _, _) => FlDotCirclePainter(radius: 2.5, color: couleur, strokeWidth: 0),
          ),
          belowBarData: BarAreaData(show: true, color: couleur.withValues(alpha: 0.06)),
        );

    // Toutes les étiquettes de mois ne tiennent pas sur un téléphone : on en
    // garde une sur `saut`, la première et la dernière comprises.
    final saut = (series.length / 6).ceil().clamp(1, 12);

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (series.length - 1).clamp(0, 1 << 20).toDouble(),
        minY: 0,
        maxY: plafond == 0 ? 1 : plafond,
        clipData: const FlClipData.all(),
        lineTouchData: const LineTouchData(enabled: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: pas,
          getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: pas,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 1,
              getTitlesWidget: (v, _) {
                final i = v.round();
                if (i < 0 || i >= series.length || (v - i).abs() > 0.01) return const SizedBox.shrink();
                if (i % saut != 0 && i != series.length - 1) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _libelleMois(context, series[i].mois),
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          ligne(_couleurCreees, (p) => p.creees),
          ligne(_couleurTraitees, (p) => p.traitees),
          ligne(_couleurLevees, (p) => p.levees),
        ],
      ),
    );
  }
}

class _LegendeSerie extends StatelessWidget {
  final Color couleur;
  final String label;
  const _LegendeSerie({required this.couleur, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 3, decoration: BoxDecoration(color: couleur, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}
