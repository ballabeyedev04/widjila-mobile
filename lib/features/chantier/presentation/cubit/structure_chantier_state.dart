import 'package:equatable/equatable.dart';

import '../../../reserve/domain/entities/chantier_structure.dart';

enum StructureStatus { chargement, succes, erreur }

class StructureChantierState extends Equatable {
  final StructureStatus status;
  final ChantierStructure? structure;
  final String? erreur;

  /// Une modification est en cours d'envoi — les gestes qui en lanceraient
  /// une seconde sont neutralisés jusqu'au retour du serveur.
  final bool actionEnCours;

  const StructureChantierState({
    this.status = StructureStatus.chargement,
    this.structure,
    this.erreur,
    this.actionEnCours = false,
  });

  StructureChantierState copyWith({
    StructureStatus? status,
    ChantierStructure? structure,
    String? erreur,
    bool effacerErreur = false,
    bool? actionEnCours,
  }) {
    return StructureChantierState(
      status: status ?? this.status,
      structure: structure ?? this.structure,
      erreur: effacerErreur ? null : (erreur ?? this.erreur),
      actionEnCours: actionEnCours ?? this.actionEnCours,
    );
  }

  @override
  List<Object?> get props => [status, structure, erreur, actionEnCours];
}
