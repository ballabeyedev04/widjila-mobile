import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../dashboard/domain/usecases/get_dashboard_stats.dart';
import '../../domain/entities/chantier.dart';
import '../../domain/usecases/get_chantiers.dart';
import 'chantiers_list_state.dart';

class ChantiersListCubit extends Cubit<ChantiersListState> {
  final GetChantiers getChantiers;
  final GetDashboardStats getDashboardStats;
  static const _limit = 20;

  Timer? _debounce;

  /// Voir `ReservesListCubit._jetonListe` — protège des réponses arrivant
  /// dans le désordre (recherche debouncée, pagination et rafraîchissement
  /// pouvant s'entrelacer sur un réseau lent).
  int _jetonListe = 0;

  ChantiersListCubit({required this.getChantiers, required this.getDashboardStats})
      : super(const ChantiersListState());

  /// Charge les compteurs des puces de statut.
  ///
  /// Appelé par l'écran « Chantiers » SEUL, pas par le sélecteur de chantier
  /// du menu : celui-ci n'affiche aucune puce, un appel à `GET /dashboard` y
  /// serait payé pour rien.
  ///
  /// Un échec est silencieux : les puces gardent leur dernier compte et la
  /// liste, elle, reste parfaitement utilisable — ce n'est pas une raison
  /// pour barrer l'écran d'un message d'erreur.
  Future<void> chargerCompteurs() async {
    final result = await getDashboardStats();
    if (isClosed) return;
    result.fold(
      (_) {},
      (stats) {
        final compteurs = <ChantierStatut, int>{};
        for (final resume in stats.parChantier) {
          compteurs[resume.statut] = (compteurs[resume.statut] ?? 0) + 1;
        }
        emit(state.copyWith(
          compteursParStatut: compteurs,
          // `stats.chantiers` est le compte serveur ; `parChantier` peut être
          // tronqué par le back, on prend donc le plus fiable des deux.
          totalGlobal: stats.chantiers,
        ));
      },
    );
  }

  Future<void> charger() async {
    final jeton = ++_jetonListe;
    emit(state.copyWith(status: ChantiersListStatus.chargement));
    final result = await getChantiers(
      page: 1, limit: _limit, search: state.recherche, statut: state.filtreStatut,
    );
    if (isClosed || jeton != _jetonListe) return;
    result.fold(
      (failure) => emit(state.copyWith(status: ChantiersListStatus.erreur, erreur: failure.errorMessage)),
      (page) => emit(state.copyWith(
        status: ChantiersListStatus.succes,
        items: page.items,
        total: page.total,
        page: 1,
        chargementPage: false,
      )),
    );
  }

  /// Recherche debouncée (400 ms) — même délai que l'admin web
  /// (`useServerList.js`), repart systématiquement de la page 1.
  void rechercher(String texte) {
    _debounce?.cancel();
    emit(state.copyWith(recherche: texte));
    _debounce = Timer(const Duration(milliseconds: 400), charger);
  }

  /// `null` = « Tous » : le filtre est effacé, pas remplacé.
  void filtrerParStatut(ChantierStatut? statut) {
    emit(state.copyWith(filtreStatut: statut, effacerFiltreStatut: statut == null));
    charger();
  }

  Future<void> chargerPageSuivante() async {
    if (state.chargementPage || !state.aPlusDeResultats) return;
    final jeton = ++_jetonListe;
    emit(state.copyWith(chargementPage: true));
    final prochainePage = state.page + 1;
    final result = await getChantiers(
      page: prochainePage, limit: _limit, search: state.recherche, statut: state.filtreStatut,
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
