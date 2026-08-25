import 'package:equatable/equatable.dart';
import '../../domain/repositories/reserve_repository.dart';
import '../../domain/entities/reserve_evolution.dart';

enum ChantierDashboardStatus { chargement, succes, erreur }

class ChantierDashboardState extends Equatable {
  final ChantierDashboardStatus status;
  final ReserveStatutsCount statutsCount;
  final ReserveEvolution evolution;
  final String? erreur;

  const ChantierDashboardState({
    this.status = ChantierDashboardStatus.chargement,
    this.statutsCount = const ReserveStatutsCount(parStatut: {}, total: 0),
    this.evolution = const ReserveEvolution(),
    this.erreur,
  });

  ChantierDashboardState copyWith({
    ChantierDashboardStatus? status,
    ReserveStatutsCount? statutsCount,
    ReserveEvolution? evolution,
    String? erreur,
  }) {
    return ChantierDashboardState(
      status: status ?? this.status,
      statutsCount: statutsCount ?? this.statutsCount,
      evolution: evolution ?? this.evolution,
      erreur: erreur,
    );
  }

  @override
  List<Object?> get props => [status, statutsCount, evolution, erreur];
}
