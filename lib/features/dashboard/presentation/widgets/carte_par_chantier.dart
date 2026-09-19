import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../l10n/l10n_extension.dart';
import '../../domain/entities/dashboard_stats.dart';
import 'carte_tableau_de_bord.dart';

/// Répartition des réserves par chantier — une barre par chantier.
///
/// Les chiffres sont ceux de `stats.parChantier` (`DashboardService
/// .statsGlobales`), déjà chargés pour l'aperçu « Vos chantiers » : aucune
/// requête de plus, aucune donnée inventée. La barre pleine est le TOTAL, la
/// portion foncée ce qui reste OUVERT — d'un coup d'œil, le chantier qui
/// accumule et celui qui a soldé.
///
/// Des barres en widgets plutôt qu'un `BarChart` : les noms de chantier sont
/// longs et de longueur inégale ; une étiquette d'axe les tronque ou déborde,
/// une ligne de texte se coupe proprement.
class CarteParChantier extends StatelessWidget {
  final List<DashboardChantierResume> chantiers;

  /// Au-delà, la carte s'allonge sans rien dire de plus : les chantiers les
  /// plus chargés d'abord, les autres restent dans « Vos chantiers ».
  static const maxBarres = 8;

  const CarteParChantier({super.key, required this.chantiers});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tries = [...chantiers]..sort((a, b) => b.reservesTotal.compareTo(a.reservesTotal));
    final visibles = tries.take(maxBarres).toList();
    final maximum = visibles.fold<int>(0, (m, c) => c.reservesTotal > m ? c.reservesTotal : m);

    return CarteTableauDeBord(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EnTeteCarte(titre: l10n.dashboardParChantierTitre, sousTitre: l10n.dashboardParChantierSousTitre),
          const SizedBox(height: 16),
          if (maximum == 0)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 80),
              child: Center(
                child: Text(l10n.dashboardAucuneDonnee, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ),
            )
          else ...[
            for (final c in visibles) ...[
              _Barre(chantier: c, maximum: maximum),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 14,
              children: [
                _Legende(couleur: AppColors.primary.withValues(alpha: 0.25), label: l10n.dashboardKpiTotal),
                _Legende(couleur: AppColors.primary, label: l10n.dashboardParChantierOuvertes),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Barre extends StatelessWidget {
  final DashboardChantierResume chantier;
  final int maximum;
  const _Barre({required this.chantier, required this.maximum});

  @override
  Widget build(BuildContext context) {
    final total = chantier.reservesTotal;
    final ouvertes = chantier.reservesOuvertes;
    final fractionTotal = maximum == 0 ? 0.0 : total / maximum;
    final fractionOuvertes = maximum == 0 ? 0.0 : ouvertes / maximum;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                chantier.nom,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$ouvertes / $total',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Container(color: AppColors.background),
                FractionallySizedBox(
                  widthFactor: fractionTotal.clamp(0.0, 1.0),
                  child: Container(color: AppColors.primary.withValues(alpha: 0.25)),
                ),
                FractionallySizedBox(
                  widthFactor: fractionOuvertes.clamp(0.0, 1.0),
                  child: Container(color: AppColors.primary),
                ),
              ],
            ),
          ),
        ),
      ],
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
        Container(width: 10, height: 10, decoration: BoxDecoration(color: couleur, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}
