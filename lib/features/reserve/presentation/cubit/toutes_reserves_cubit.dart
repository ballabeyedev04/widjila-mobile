import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/reserve.dart';
import '../../domain/usecases/get_reserve_statuts_count.dart';
import '../../domain/usecases/get_toutes_reserves.dart';
import 'reserves_list_state.dart';

/// Réserves de toute l'organisation — état de l'onglet « Réserves ».
///
/// Réutilise [ReservesListState] plutôt que d'en cloner un identique : les
/// deux écrans (par chantier / transversal) affichent la même liste avec les
/// mêmes filtres, seule la source diffère — y compris `statutsCount`, ici
/// alimenté par les statistiques globales de l'organisation.
class ToutesReservesCubit extends Cubit<ReservesListState> {
  final GetToutesReserves getToutesReserves;
  final GetReserveStatutsCountGlobal getStatutsCountGlobal;

  /// Taille de page. Abaissée à quelques éléments par le bloc « Réserves
  /// récentes » de l'accueil, qui n'affiche qu'un aperçu et n'a aucune raison
  /// de rapatrier une page entière.
  final int limite;

  /// Charge la répartition par statut en même temps que la liste.
  ///
  /// À `false` pour l'aperçu de l'accueil : il n'affiche aucune puce de
  /// filtre, et la page lit déjà les mêmes statistiques par ailleurs — un
  /// second appel à `GET /dashboard` n'apporterait rien.
  final bool avecCompteurs;

  Timer? _debounce;

  /// Voir `ReservesListCubit._jetonListe` — protège des réponses arrivant
  /// dans le désordre (recherche/filtre/pagination entrelacés).
  int _jetonListe = 0;

  ToutesReservesCubit({
    required this.getToutesReserves,
    required this.getStatutsCountGlobal,
    this.limite = 20,
    this.avecCompteurs = true,
  }) : super(const ReservesListState());

  Future<void> charger() async {
    final jeton = ++_jetonListe;
    emit(state.copyWith(status: ReservesListStatus.chargement));

    // Les deux requêtes sont indépendantes : lancées ENSEMBLE, elles ne
    // coûtent qu'un aller-retour au lieu de deux, et les puces de filtre
    // apparaissent avec leurs compteurs en même temps que la liste plutôt
    // qu'un instant après.
    final listeFuture = getToutesReserves(
      page: 1, limit: limite, search: state.recherche, statut: state.filtreStatut,
    );
    final compteursFuture = avecCompteurs ? getStatutsCountGlobal() : null;

    final result = await listeFuture;
    final compteurs = await compteursFuture;
    if (isClosed || jeton != _jetonListe) return;

    // Un échec des COMPTEURS ne doit pas faire échouer l'écran : la liste
    // reste utilisable, les puces gardent simplement les derniers chiffres
    // connus.
    final statutsCount = compteurs?.fold((_) => state.statutsCount, (v) => v) ?? state.statutsCount;

    result.fold(
      (failure) => emit(state.copyWith(status: ReservesListStatus.erreur, erreur: failure.errorMessage)),
      (page) => emit(state.copyWith(
        status: ReservesListStatus.succes,
        items: page.items,
        total: page.total,
        page: 1,
        chargementPage: false,
        statutsCount: statutsCount,
      )),
    );
  }

  /// Recherche debouncée (400 ms) — même délai que partout ailleurs.
  void rechercher(String texte) {
    _debounce?.cancel();
    emit(state.copyWith(recherche: texte));
    _debounce = Timer(const Duration(milliseconds: 400), charger);
  }

  /// `null` = « Toutes » : le filtre est effacé, pas remplacé.
  void filtrerParStatut(ReserveStatut? statut) {
    emit(state.copyWith(filtreStatut: statut, effacerFiltreStatut: statut == null));
    charger();
  }

  Future<void> chargerPageSuivante() async {
    if (state.chargementPage || !state.aPlusDeResultats) return;
    final jeton = ++_jetonListe;
    emit(state.copyWith(chargementPage: true));
    final prochainePage = state.page + 1;
    final result = await getToutesReserves(
      page: prochainePage, limit: limite, search: state.recherche, statut: state.filtreStatut,
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
