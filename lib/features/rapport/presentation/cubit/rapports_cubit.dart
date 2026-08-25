import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/rapport.dart';
import '../../domain/usecases/rapport_usecases.dart';

enum RapportsStatus { initial, chargement, succes, erreur }

/// Statut de la GÉNÉRATION, distinct de celui de la liste : la fabrication du
/// PDF est longue (le serveur agrège réserves et inspections puis compose le
/// document) et son échec ne doit pas effacer les rapports déjà listés.
enum GenerationStatus { inactif, enCours, succes, erreur }

class RapportsState extends Equatable {
  final RapportsStatus status;
  final List<Rapport> items;
  final String? erreur;

  final GenerationStatus generationStatus;
  final String? generationErreur;

  /// Dernier rapport produit — l'écran propose de l'ouvrir immédiatement,
  /// plutôt que de laisser l'utilisateur le chercher dans la liste.
  final Rapport? dernierGenere;

  const RapportsState({
    this.status = RapportsStatus.initial,
    this.items = const [],
    this.erreur,
    this.generationStatus = GenerationStatus.inactif,
    this.generationErreur,
    this.dernierGenere,
  });

  RapportsState copyWith({
    RapportsStatus? status,
    List<Rapport>? items,
    String? erreur,
    GenerationStatus? generationStatus,
    String? generationErreur,
    bool effacerGenerationErreur = false,
    Rapport? dernierGenere,
    bool effacerDernierGenere = false,
  }) {
    return RapportsState(
      status: status ?? this.status,
      items: items ?? this.items,
      erreur: erreur,
      generationStatus: generationStatus ?? this.generationStatus,
      generationErreur: effacerGenerationErreur ? null : (generationErreur ?? this.generationErreur),
      dernierGenere: effacerDernierGenere ? null : (dernierGenere ?? this.dernierGenere),
    );
  }

  @override
  List<Object?> get props =>
      [status, items, erreur, generationStatus, generationErreur, dernierGenere];
}

class RapportsCubit extends Cubit<RapportsState> {
  final GetRapports getRapports;
  final GenererRapport genererRapport;
  final SupprimerRapport supprimerRapport;
  final String chantierId;

  RapportsCubit({
    required this.getRapports,
    required this.genererRapport,
    required this.supprimerRapport,
    required this.chantierId,
  }) : super(const RapportsState());

  Future<void> charger() async {
    emit(state.copyWith(status: RapportsStatus.chargement));
    final result = await getRapports(chantierId);
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(status: RapportsStatus.erreur, erreur: failure.errorMessage)),
      (items) => emit(state.copyWith(status: RapportsStatus.succes, items: items)),
    );
  }

  Future<void> generer({
    required RapportType type,
    String? statutReserve,
    String? entrepriseId,
    String? batimentId,
  }) async {
    // Verrou de double soumission : la génération est longue, et deux appuis
    // produiraient deux PDF identiques facturés au même chantier.
    if (state.generationStatus == GenerationStatus.enCours) return;
    emit(state.copyWith(generationStatus: GenerationStatus.enCours, effacerGenerationErreur: true));

    final result = await genererRapport(
      chantierId: chantierId,
      type: type,
      statutReserve: statutReserve,
      entrepriseId: entrepriseId,
      batimentId: batimentId,
    );
    if (isClosed) return;

    result.fold(
      (failure) => emit(state.copyWith(
        generationStatus: GenerationStatus.erreur,
        generationErreur: failure.errorMessage,
      )),
      (rapport) => emit(state.copyWith(
        generationStatus: GenerationStatus.succes,
        items: [rapport, ...state.items],
        dernierGenere: rapport,
      )),
    );
  }

  Future<void> supprimer(Rapport rapport) async {
    // Retrait optimiste : la ligne disparaît tout de suite. En cas d'échec on
    // recharge — plutôt que de réinsérer à l'aveugle à la bonne position.
    final avant = state.items;
    emit(state.copyWith(items: state.items.where((r) => r.id != rapport.id).toList()));

    final result = await supprimerRapport(rapport.id);
    if (isClosed) return;
    result.fold(
      (failure) => emit(state.copyWith(items: avant, erreur: failure.errorMessage)),
      (_) => null,
    );
  }

  void accuserReceptionGeneration() => emit(state.copyWith(
        generationStatus: GenerationStatus.inactif,
        effacerGenerationErreur: true,
        effacerDernierGenere: true,
      ));
}
