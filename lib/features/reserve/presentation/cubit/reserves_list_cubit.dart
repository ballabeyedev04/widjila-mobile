import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/entities/reserve.dart';
import '../../domain/usecases/get_reserve_statuts_count.dart';
import '../../domain/usecases/get_reserves.dart';
import 'reserves_list_state.dart';

class ReservesListCubit extends Cubit<ReservesListState> {
  final GetReserves getReserves;
  final GetReserveStatutsCount getReserveStatutsCount;
  final String chantierId;
  static const _limit = 20;

  Timer? _debounce;

  /// Numéro de la requête de liste la plus récente.
  ///
  /// Le debounce annule le TIMER, jamais la requête déjà partie. Sans ce
  /// jeton, deux frappes rapprochées sur un réseau lent produisaient :
  /// « fis » part (8 s) → « fissure » part (2 s) → « fissure » s'affiche →
  /// puis la réponse de « fis » arrive et ÉCRASE la liste, alors que le champ
  /// de recherche affiche toujours « fissure ». Toute réponse dont le jeton
  /// n'est plus le courant est désormais ignorée.
  int _jetonListe = 0;

  ReservesListCubit({
    required this.getReserves,
    required this.getReserveStatutsCount,
    required this.chantierId,
  }) : super(const ReservesListState());

  Future<void> charger() async {
    final jeton = ++_jetonListe;
    emit(state.copyWith(status: ReservesListStatus.chargement));

    // Les deux appels partent ENSEMBLE, mais ne sont plus ATTENDUS ensemble.
    //
    // Ils l'étaient : `await` sur la liste, puis `await` sur les compteurs,
    // avant le moindre `emit`. Les compteurs ne servent qu'à chiffrer les
    // puces de filtre, mais ils retenaient la liste — tant que
    // `GET /reserves/statuts-count` n'avait pas répondu, l'écran gardait son
    // squelette de chargement alors que les réserves étaient déjà là. Sur un
    // chantier sans aucune réserve, l'état vide n'apparaissait donc jamais.
    unawaited(_rafraichirCompteurs(jeton));

    final pageResult = await getReserves(
      chantierId: chantierId, page: 1, limit: _limit, search: state.recherche, statut: state.filtreStatut,
    );

    // `isClosed` : l'utilisateur a pu quitter l'écran pendant le chargement.
    // Émettre sur un cubit fermé lève une `StateError` non gérée, remontée
    // comme crash fatal par `runZonedGuarded` (voir main.dart).
    if (isClosed || jeton != _jetonListe) return;

    pageResult.fold(
      (failure) => emit(state.copyWith(status: ReservesListStatus.erreur, erreur: failure.errorMessage)),
      (page) => emit(state.copyWith(
        status: ReservesListStatus.succes,
        items: page.items,
        total: page.total,
        page: 1,
        // Une pagination éventuellement en vol devient caduque : son résultat
        // sera rejeté par le jeton, et l'indicateur ne doit pas rester bloqué.
        chargementPage: false,
      )),
    );
  }

  /// Charge la répartition par statut SANS bloquer la liste.
  ///
  /// Un échec ne fait rien échouer : les puces gardent les derniers chiffres
  /// connus, et la liste — la seule chose que l'utilisateur est venu voir —
  /// s'affiche de toute façon.
  Future<void> _rafraichirCompteurs(int jeton) async {
    final result = await getReserveStatutsCount(chantierId);
    if (isClosed || jeton != _jetonListe) return;
    result.fold(
      (_) {},
      (compteurs) => emit(state.copyWith(statutsCount: compteurs)),
    );
  }

  /// Recherche debouncée (400 ms) — même délai que le reste de l'app.
  void rechercher(String texte) {
    _debounce?.cancel();
    emit(state.copyWith(recherche: texte));
    _debounce = Timer(const Duration(milliseconds: 400), charger);
  }

  void filtrerParStatut(ReserveStatut? statut) {
    if (statut == null) {
      emit(state.copyWith(effacerFiltreStatut: true));
    } else {
      emit(state.copyWith(filtreStatut: statut));
    }
    charger();
  }

  Future<void> chargerPageSuivante() async {
    if (state.chargementPage || !state.aPlusDeResultats) return;
    // MÊME jeton que `charger()` : un rafraîchissement lancé pendant qu'une
    // page 2 est en vol invalide cette dernière. Sans ça, la page 2 arrivait
    // après le rafraîchissement et s'AJOUTAIT à la liste fraîchement
    // remplacée (`[...state.items, ...page.items]`) — doublons à l'écran et
    // compteurs faux.
    final jeton = ++_jetonListe;
    emit(state.copyWith(chargementPage: true));
    final prochainePage = state.page + 1;
    final result = await getReserves(
      chantierId: chantierId, page: prochainePage, limit: _limit, search: state.recherche, statut: state.filtreStatut,
    );
    if (isClosed || jeton != _jetonListe) return;
    result.fold(
      (failure) => emit(state.copyWith(chargementPage: false, erreur: failure.errorMessage)),
      (page) => emit(state.copyWith(
        chargementPage: false,
        items: [...state.items, ...page.items],
        total: page.total,
        page: prochainePage,
      )),
    );
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
