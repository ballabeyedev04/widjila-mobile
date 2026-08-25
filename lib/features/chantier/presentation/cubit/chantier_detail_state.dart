import 'package:equatable/equatable.dart';
import '../../domain/entities/chantier.dart';

enum ChantierDetailStatus { chargement, succes, erreur }

class ChantierDetailState extends Equatable {
  final ChantierDetailStatus status;
  final Chantier? chantier;
  final String? erreur;

  const ChantierDetailState({this.status = ChantierDetailStatus.chargement, this.chantier, this.erreur});

  ChantierDetailState copyWith({ChantierDetailStatus? status, Chantier? chantier, String? erreur}) {
    return ChantierDetailState(status: status ?? this.status, chantier: chantier ?? this.chantier, erreur: erreur);
  }

  @override
  List<Object?> get props => [status, chantier, erreur];
}
