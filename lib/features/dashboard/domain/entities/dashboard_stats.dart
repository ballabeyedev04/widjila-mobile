import 'package:equatable/equatable.dart';
import '../../../chantier/domain/entities/chantier.dart';
import '../../../reserve/domain/entities/reserve.dart';

/// Résumé d'un chantier pour l'aperçu du tableau de bord — miroir de
/// `stats.parChantier` (`DashboardService.statsGlobales`).
class DashboardChantierResume extends Equatable {
  final String id;
  final String nom;
  final String? code;
  final ChantierStatut statut;
  final int reservesTotal;
  final int reservesOuvertes;
  final int batiments;

  const DashboardChantierResume({
    required this.id,
    required this.nom,
    this.code,
    required this.statut,
    this.reservesTotal = 0,
    this.reservesOuvertes = 0,
    this.batiments = 0,
  });

  factory DashboardChantierResume.fromJson(Map<String, dynamic> json) {
    final reserves = json['reserves'] as Map<String, dynamic>? ?? const {};
    return DashboardChantierResume(
      id: json['id'] as String,
      nom: json['nom'] as String? ?? '',
      code: json['code'] as String?,
      statut: ChantierStatutX.fromString(json['statut'] as String?),
      reservesTotal: reserves['total'] as int? ?? 0,
      reservesOuvertes: reserves['ouvertes'] as int? ?? 0,
      batiments: json['batiments'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [id, nom, code, statut, reservesTotal, reservesOuvertes, batiments];
}

/// Statistiques globales — miroir de `DashboardService.statsGlobales()`
/// (`backend/src/modules/dashboard/service/dashboard.service.js`).
class ReservesStats extends Equatable {
  final int total;
  final int ouvertes;
  final int validees;
  final int refusees;
  final int enRetard;

  const ReservesStats({
    this.total = 0,
    this.ouvertes = 0,
    this.validees = 0,
    this.refusees = 0,
    this.enRetard = 0,
  });

  factory ReservesStats.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ReservesStats();
    return ReservesStats(
      total: json['total'] as int? ?? 0,
      ouvertes: json['ouvertes'] as int? ?? 0,
      validees: json['validees'] as int? ?? 0,
      refusees: json['refusees'] as int? ?? 0,
      enRetard: json['enRetard'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [total, ouvertes, validees, refusees, enRetard];
}

class DashboardStats extends Equatable {
  final int chantiers;
  final ReservesStats reserves;
  final int plans;
  final int inspections;
  final int documents;
  final int utilisateurs;

  /// Répartition des réserves par statut (`DashboardService.statsGlobales`
  /// → `stats.parStatut`) — chiffres bruts du back, seul le donut de
  /// l'écran d'accueil est calculé/dessiné côté mobile à partir d'eux.
  final Map<ReserveStatut, int> parStatut;

  /// Répartition des réserves par sévérité (`stats.parSeverite`).
  final Map<ReserveSeverite, int> parSeverite;

  /// Résumé par chantier (`stats.parChantier`) — alimente l'aperçu
  /// "Chantiers" du tableau de bord.
  final List<DashboardChantierResume> parChantier;

  const DashboardStats({
    this.chantiers = 0,
    this.reserves = const ReservesStats(),
    this.plans = 0,
    this.inspections = 0,
    this.documents = 0,
    this.utilisateurs = 0,
    this.parStatut = const {},
    this.parSeverite = const {},
    this.parChantier = const [],
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    final parStatutRaw = (json['parStatut'] as Map<String, dynamic>?) ?? const {};
    final parSeveriteRaw = (json['parSeverite'] as Map<String, dynamic>?) ?? const {};
    final parChantierRaw = (json['parChantier'] as List?) ?? const [];
    return DashboardStats(
      chantiers: json['chantiers'] as int? ?? 0,
      reserves: ReservesStats.fromJson(json['reserves'] as Map<String, dynamic>?),
      plans: json['plans'] as int? ?? 0,
      inspections: json['inspections'] as int? ?? 0,
      documents: json['documents'] as int? ?? 0,
      utilisateurs: json['utilisateurs'] as int? ?? 0,
      parStatut: {for (final entry in parStatutRaw.entries) ReserveStatutX.fromString(entry.key): entry.value as int},
      parSeverite: {
        for (final entry in parSeveriteRaw.entries) ReserveSeveriteX.fromString(entry.key): entry.value as int,
      },
      parChantier: parChantierRaw
          .map((e) => DashboardChantierResume.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  List<Object?> get props =>
      [chantiers, reserves, plans, inspections, documents, utilisateurs, parStatut, parSeverite, parChantier];
}

/// Un point de la courbe d'évolution — miroir d'un élément de
/// `stats.series` servi par `GET /dashboard/evolution`
/// (`DashboardService.evolution`). `mois` est au format `AAAA-MM`.
class DashboardEvolutionPoint extends Equatable {
  final String mois;
  final int creees;
  final int traitees;
  final int levees;

  const DashboardEvolutionPoint({
    required this.mois,
    this.creees = 0,
    this.traitees = 0,
    this.levees = 0,
  });

  factory DashboardEvolutionPoint.fromJson(Map<String, dynamic> json) {
    return DashboardEvolutionPoint(
      mois: json['mois'] as String? ?? '',
      creees: json['creees'] as int? ?? 0,
      traitees: json['traitees'] as int? ?? 0,
      // `levees` est le nom actuel ; `validees` son ancien nom, encore servi
      // par le serveur pour l'admin web. L'un ou l'autre, jamais les deux.
      levees: json['levees'] as int? ?? json['validees'] as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [mois, creees, traitees, levees];
}

/// Évolution mensuelle des réserves (créées / traitées / levées), calculée
/// par le serveur depuis l'historique des réserves. Le mobile ne fait que la
/// dessiner.
class DashboardEvolution extends Equatable {
  final List<DashboardEvolutionPoint> series;

  const DashboardEvolution({this.series = const []});

  factory DashboardEvolution.fromJson(Map<String, dynamic> json) {
    final brut = (json['series'] as List?) ?? const [];
    return DashboardEvolution(
      series: brut.map((e) => DashboardEvolutionPoint.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  /// Vrai si au moins un point porte une valeur : une courbe de zéros ne
  /// mérite pas un graphique, mais un message.
  bool get aDesDonnees => series.any((p) => p.creees > 0 || p.traitees > 0 || p.levees > 0);

  @override
  List<Object?> get props => [series];
}
