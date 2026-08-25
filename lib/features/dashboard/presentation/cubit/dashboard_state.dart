import 'package:equatable/equatable.dart';
import '../../domain/entities/dashboard_stats.dart';

enum DashboardStatus { initial, chargement, succes, erreur }

class DashboardState extends Equatable {
  final DashboardStatus status;
  final DashboardStats? stats;
  final String? erreur;

  const DashboardState({this.status = DashboardStatus.initial, this.stats, this.erreur});

  DashboardState copyWith({DashboardStatus? status, DashboardStats? stats, String? erreur}) {
    return DashboardState(
      status: status ?? this.status,
      stats: stats ?? this.stats,
      erreur: erreur,
    );
  }

  @override
  List<Object?> get props => [status, stats, erreur];
}
