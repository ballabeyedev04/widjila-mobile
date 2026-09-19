import 'package:equatable/equatable.dart';
import '../../domain/entities/dashboard_stats.dart';

enum DashboardStatus { initial, chargement, succes, erreur }

class DashboardState extends Equatable {
  final DashboardStatus status;
  final DashboardStats? stats;
  final String? erreur;

  /// Courbe d'évolution — chargée EN PARALLÈLE des statistiques, avec son
  /// propre état : un échec de `/dashboard/evolution` laisse le reste de
  /// l'écran (cartes, donut, chantiers) parfaitement lisible, et la carte du
  /// graphique dit seule qu'elle n'a pas pu charger.
  final DashboardStatus evolutionStatus;
  final DashboardEvolution? evolution;

  const DashboardState({
    this.status = DashboardStatus.initial,
    this.stats,
    this.erreur,
    this.evolutionStatus = DashboardStatus.initial,
    this.evolution,
  });

  DashboardState copyWith({
    DashboardStatus? status,
    DashboardStats? stats,
    String? erreur,
    DashboardStatus? evolutionStatus,
    DashboardEvolution? evolution,
  }) {
    return DashboardState(
      status: status ?? this.status,
      stats: stats ?? this.stats,
      erreur: erreur,
      evolutionStatus: evolutionStatus ?? this.evolutionStatus,
      evolution: evolution ?? this.evolution,
    );
  }

  @override
  List<Object?> get props => [status, stats, erreur, evolutionStatus, evolution];
}
