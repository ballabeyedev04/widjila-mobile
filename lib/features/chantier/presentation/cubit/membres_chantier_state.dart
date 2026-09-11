import 'package:equatable/equatable.dart';

import '../../domain/entities/membre_chantier.dart';

enum MembresChantierStatus { chargement, succes, erreur }

class MembresChantierState extends Equatable {
  final MembresChantierStatus status;
  final List<MembreChantier> membres;
  final String? erreur;
  final bool actionEnCours;

  const MembresChantierState({
    this.status = MembresChantierStatus.chargement,
    this.membres = const [],
    this.erreur,
    this.actionEnCours = false,
  });

  MembresChantierState copyWith({
    MembresChantierStatus? status,
    List<MembreChantier>? membres,
    String? erreur,
    bool effacerErreur = false,
    bool? actionEnCours,
  }) {
    return MembresChantierState(
      status: status ?? this.status,
      membres: membres ?? this.membres,
      erreur: effacerErreur ? null : (erreur ?? this.erreur),
      actionEnCours: actionEnCours ?? this.actionEnCours,
    );
  }

  @override
  List<Object?> get props => [status, membres, erreur, actionEnCours];
}
