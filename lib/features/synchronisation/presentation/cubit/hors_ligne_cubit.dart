import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/telechargement_chantier.dart';

/// État de la carte « Disponible hors connexion » d'un chantier.
class HorsLigneState extends Equatable {
  /// Dernier téléchargement COMPLET, `null` s'il n'y en a jamais eu.
  final DateTime? derniereSynchro;
  final bool enCours;
  final ProgressionTelechargement progression;

  /// Raison du dernier échec, `null` si tout va bien.
  final String? erreur;

  const HorsLigneState({
    this.derniereSynchro,
    this.enCours = false,
    this.progression = const ProgressionTelechargement(0, 0),
    this.erreur,
  });

  HorsLigneState copyWith({
    DateTime? derniereSynchro,
    bool? enCours,
    ProgressionTelechargement? progression,
    String? erreur,
    bool effacerErreur = false,
  }) =>
      HorsLigneState(
        derniereSynchro: derniereSynchro ?? this.derniereSynchro,
        enCours: enCours ?? this.enCours,
        progression: progression ?? this.progression,
        erreur: effacerErreur ? null : (erreur ?? this.erreur),
      );

  @override
  List<Object?> get props => [derniereSynchro, enCours, progression, erreur];
}

class HorsLigneCubit extends Cubit<HorsLigneState> {
  final TelechargementChantier _service;
  final String chantierId;

  HorsLigneCubit(this._service, {required this.chantierId}) : super(const HorsLigneState());

  Future<void> charger() async {
    final date = await _service.derniereSynchro(chantierId);
    if (!isClosed) emit(state.copyWith(derniereSynchro: date));
  }

  Future<void> telecharger() async {
    if (state.enCours) return;
    emit(state.copyWith(enCours: true, effacerErreur: true, progression: const ProgressionTelechargement(0, 0)));
    final resultat = await _service.telecharger(
      chantierId,
      surProgression: (p) {
        if (!isClosed) emit(state.copyWith(progression: p));
      },
    );
    if (isClosed) return;
    emit(state.copyWith(
      enCours: false,
      derniereSynchro: resultat.date,
      erreur: resultat.complet ? null : (resultat.message ?? 'Téléchargement incomplet'),
      effacerErreur: resultat.complet,
    ));
  }
}
