import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/errors/exception_to_failure.dart';
import '../../../../core/errors/failure.dart';
import '../../domain/entities/reserve.dart';
import '../../domain/repositories/reserve_repository.dart';
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

    // Les deux requêtes partent ENSEMBLE — un seul aller-retour au lieu de
    // deux — mais elles ne sont plus ATTENDUES ensemble.
    //
    // La version précédente enchaînait `await liste` puis `await compteurs`
    // avant le moindre `emit`. Les compteurs ne servent qu'à décorer les
    // puces de filtre, mais ils retenaient la liste en otage : tant que
    // `GET /dashboard` n'avait pas répondu, l'état restait « chargement » et
    // l'écran gardait son squelette gris. Une organisation sans aucune
    // réserve ne voyait donc JAMAIS le message « Aucune réserve » — juste six
    // rectangles qui scintillent, sans rien pour comprendre.
    if (avecCompteurs) unawaited(_rafraichirCompteurs(jeton));

    final result = await _lister(page: 1);
    if (isClosed || jeton != _jetonListe) return;

    result.fold(
      (failure) => emit(state.copyWith(status: ReservesListStatus.erreur, erreur: failure.errorMessage)),
      (page) => emit(state.copyWith(
        status: ReservesListStatus.succes,
        items: page.items,
        total: page.total,
        page: 1,
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
    final result = await _protege(getStatutsCountGlobal.call);
    if (isClosed || jeton != _jetonListe) return;
    result.fold(
      (_) {},
      (compteurs) => emit(state.copyWith(statutsCount: compteurs)),
    );
  }

  Future<Either<Failure, ReservePage>> _lister({required int page}) => _protege(
        () => getToutesReserves(
          page: page, limit: limite, search: state.recherche, statut: state.filtreStatut,
        ),
      );

  /// Convertit une exception ÉCHAPPÉE en `Left`.
  ///
  /// Les dépôts renvoient normalement un `Either` et n'exposent pas
  /// d'exception. « Normalement » ne suffit pas ici : si une seule s'échappe,
  /// le `Future` se termine en erreur, aucun `emit` n'a lieu, et l'écran reste
  /// bloqué sur son squelette — l'utilisateur n'a alors ni liste, ni message,
  /// ni bouton pour réessayer. Une erreur affichée vaut mieux qu'un écran
  /// figé.
  Future<Either<Failure, T>> _protege<T>(
    Future<Either<Failure, T>> Function() action,
  ) async {
    try {
      return await action();
    } catch (e) {
      return Left(exceptionToFailure(e));
    }
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
    final result = await _lister(page: prochainePage);
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
