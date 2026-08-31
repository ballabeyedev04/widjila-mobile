import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/chantier.dart';
import '../../domain/repositories/chantier_repository.dart';
import '../../domain/usecases/get_chantiers.dart';

enum DemandesStatus { initial, chargement, succes, erreur }

class DemandesChantierState extends Equatable {
  final DemandesStatus status;

  /// Vue courante — le serveur écarte les demandes de la liste par défaut,
  /// c'est ce champ qui rouvre explicitement la réserve.
  final VueDemandes vue;

  final List<Chantier> items;
  final String? erreur;

  const DemandesChantierState({
    this.status = DemandesStatus.initial,
    this.vue = VueDemandes.miennes,
    this.items = const [],
    this.erreur,
  });

  DemandesChantierState copyWith({
    DemandesStatus? status,
    VueDemandes? vue,
    List<Chantier>? items,
    String? erreur,
    bool effacerErreur = false,
  }) {
    return DemandesChantierState(
      status: status ?? this.status,
      vue: vue ?? this.vue,
      items: items ?? this.items,
      erreur: effacerErreur ? null : (erreur ?? this.erreur),
    );
  }

  @override
  List<Object?> get props => [status, vue, items, erreur];
}

/// Suivi des demandes de création de chantier.
///
/// Deux vues sur la même liste serveur : les demandes du compte connecté, et
/// — pour ceux qui décident — la file d'attente à trancher.
///
/// Pas de pagination : une organisation n'a pas cinquante demandes en cours,
/// et une file qui se pagine se traite mal. La limite reste haute pour que le
/// serveur n'en tronque pas silencieusement une partie.
class DemandesChantierCubit extends Cubit<DemandesChantierState> {
  final GetChantiers getChantiers;

  static const _limit = 100;

  DemandesChantierCubit({required this.getChantiers}) : super(const DemandesChantierState());

  /// Bascule de vue. Recharge : les deux vues n'ont ni le même contenu ni le
  /// même filtre serveur, garder l'ancienne liste le temps de l'appel ferait
  /// croire à un onglet mal branché.
  Future<void> changerVue(VueDemandes vue) async {
    if (vue == state.vue && state.status != DemandesStatus.initial) return;
    emit(state.copyWith(vue: vue, items: const [], effacerErreur: true));
    await charger();
  }

  Future<void> charger() async {
    emit(state.copyWith(status: DemandesStatus.chargement, effacerErreur: true));

    final result = await getChantiers(limit: _limit, demandes: state.vue);
    if (isClosed) return;

    result.fold(
      (echec) => emit(state.copyWith(status: DemandesStatus.erreur, erreur: echec.errorMessage)),
      (page) => emit(state.copyWith(status: DemandesStatus.succes, items: page.items)),
    );
  }
}
