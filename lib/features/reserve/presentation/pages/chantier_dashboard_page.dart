import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/fiche_chrome.dart';
import '../../../../core/widgets/liste_chrome.dart';
import '../../../../injection_container.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/reserve_evolution.dart';
import '../cubit/chantier_dashboard_cubit.dart';
import '../cubit/chantier_dashboard_state.dart';
import '../widgets/reserve_statut_donut.dart';

class ChantierDashboardPage extends StatelessWidget {
  final String chantierId;
  const ChantierDashboardPage({super.key, required this.chantierId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ChantierDashboardCubit>(param1: chantierId)..charger(),
      child: const _ChantierDashboardView(),
    );
  }
}

class _ChantierDashboardView extends StatelessWidget {
  const _ChantierDashboardView();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      // Blanc, comme Réserves et Plans. Le CONTENU repose sur le gris de fond
      // (voir plus bas) : des cartes blanches sur une page blanche perdraient
      // tout relief.
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ContenuCentre(
              child: EnTeteListe(
                titre: l10n.chantierDetailTableauBord,
                avecRetour: true,
                // Écran plein hors coquille : pas de NotificationsCubit ici.
                avecCloche: false,
              ),
            ),
            Expanded(
              child: BlocBuilder<ChantierDashboardCubit, ChantierDashboardState>(
                builder: (context, state) {
                  switch (state.status) {
                    case ChantierDashboardStatus.chargement:
                      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                    case ChantierDashboardStatus.erreur:
                      return ErrorView(
                        message: state.erreur ?? l10n.commonErrorUnknown,
                        onRetry: () => context.read<ChantierDashboardCubit>().charger(),
                      );
                    case ChantierDashboardStatus.succes:
                      return ColoredBox(
                        color: AppColors.background,
                        child: RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: () => context.read<ChantierDashboardCubit>().charger(),
                          child: ContenuCentre(
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                              children: [
                                _SousTitre(l10n.chantierDashboardSousTitre),
                                const SizedBox(height: 14),
                                CarteFiche(
                                  icone: Icons.donut_large_rounded,
                                  titre: l10n.chantierDashboardRepartitionParStatut,
                                  child: ReserveStatutDonut(
                                    parStatut: state.statutsCount.parStatut,
                                    total: state.statutsCount.total,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                CarteFiche(
                                  icone: Icons.show_chart_rounded,
                                  titre: l10n.chantierDashboardEvolution,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          _Legende(
                                            couleur: AppColors.primary,
                                            label: l10n.chantierDashboardCreees,
                                          ),
                                          const SizedBox(width: 16),
                                          _Legende(
                                            couleur: AppColors.success,
                                            label: l10n.dashboardKpiLevees,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 18),
                                      SizedBox(
                                        height: 180,
                                        child: state.evolution.series.isEmpty
                                            ? Center(
                                                child: Text(
                                                  l10n.chantierDashboardPasAssezDeDonnees,
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: AppColors.textMuted,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              )
                                            : _EvolutionChart(series: state.evolution.series),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Phrase de contexte sous le titre — dit de quoi parlent les graphiques,
/// que l'en-tête seul (« Tableau de bord ») laisse deviner.
class _SousTitre extends StatelessWidget {
  final String texte;
  const _SousTitre(this.texte);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        texte,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
    );
  }
}

class _Legende extends StatelessWidget {
  final Color couleur;
  final String label;
  const _Legende({required this.couleur, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: couleur, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _EvolutionChart extends StatelessWidget {
  final List<EvolutionPoint> series;
  const _EvolutionChart({required this.series});

  @override
  Widget build(BuildContext context) {
    final maxY = series
        .map((p) => p.creees > p.validees ? p.creees : p.validees)
        .fold<int>(0, (a, b) => a > b ? a : b)
        .toDouble();
    final plafond = maxY <= 0 ? 5.0 : (maxY * 1.2);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: plafond,
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: plafond / 4, getDrawingHorizontalLine: (_) => FlLine(color: AppColors.border, strokeWidth: 1)),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, interval: plafond / 4 == 0 ? 1 : plafond / 4)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= series.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(series[i].moisLabel(Localizations.localeOf(context)), style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          _ligne(series.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.creees.toDouble())).toList(), AppColors.primary),
          _ligne(series.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value.validees.toDouble())).toList(), AppColors.success),
        ],
      ),
    );
  }

  LineChartBarData _ligne(List<FlSpot> spots, Color couleur) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      color: couleur,
      barWidth: 2.5,
      dotData: const FlDotData(show: true),
      belowBarData: BarAreaData(show: true, color: couleur.withValues(alpha: 0.08)),
    );
  }
}
