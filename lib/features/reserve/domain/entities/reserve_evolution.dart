import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Point mensuel de la série d'évolution — miroir de
/// `DashboardService.evolution()` (`{ mois: 'YYYY-MM', creees, validees }`).
class EvolutionPoint {
  final String mois;
  final int creees;
  final int validees;
  const EvolutionPoint({required this.mois, this.creees = 0, this.validees = 0});

  factory EvolutionPoint.fromJson(Map<String, dynamic> json) => EvolutionPoint(
        mois: json['mois'] as String? ?? '',
        creees: json['creees'] as int? ?? 0,
        validees: json['validees'] as int? ?? 0,
      );

  /// Libellé court pour l'axe du graphe (« 2026-03 » → « Mars » en français,
  /// « Mar » en anglais…) — suit la langue courante de l'app plutôt qu'une
  /// liste figée, voir `LocaleController`.
  String moisLabel(Locale locale) {
    final parts = mois.split('-');
    if (parts.length != 2) return mois;
    final annee = int.tryParse(parts[0]);
    final index = int.tryParse(parts[1]);
    if (annee == null || index == null || index < 1 || index > 12) return mois;
    return DateFormat('MMM', locale.toLanguageTag()).format(DateTime(annee, index));
  }
}

class ReserveEvolution {
  final List<EvolutionPoint> series;
  const ReserveEvolution({this.series = const []});

  factory ReserveEvolution.fromJson(Map<String, dynamic> json) => ReserveEvolution(
        series: (json['series'] as List? ?? []).map((e) => EvolutionPoint.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
