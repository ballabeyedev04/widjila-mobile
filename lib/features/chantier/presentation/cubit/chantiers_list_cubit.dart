import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../dashboard/domain/usecases/get_dashboard_stats.dart';
import '../../domain/entities/chantier.dart';
import '../../domain/repositories/chantier_repository.dart';
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

  /// Faut-il joindre a la liste les DEMANDES en attente de l'utilisateur ?
  ///
  /// Faux partout, sauf pour le selecteur du parcours « depot de plans ».
  ///
  /// Le serveur ecarte les demandes de `GET /chantiers` : un chantier en
  /// attente n'est pas un chantier, et le laisser paraitre dans la liste
  /// generale ferait travailler des equipes sur un projet qui n'existe pas
  /// encore. Mais c'est PRECISEMENT sur ces demandes-la que l'entreprise doit
  /// pouvoir deposer ses plans — `plan.service.js#_refusDepot` ne l'autorise
  /// meme QUE la : une fois le chantier valide, le depot repasse aux roles
  /// operationnels. Sans cette option, une entreprise revenue le lendemain ne
  /// retrouvait plus sa demande dans le selecteur, et n'avait plus aucun moyen
  /// d'y ajouter un plan.
  bool _avecMesDemandes = false;

  /// Nombre de demandes jointes — retire du total des pages suivantes, qui ne
  /// les recompte pas.
  int _nbDemandes = 0;

  ChantiersListCubit({required this.getChantiers, required this.getDashboardStats})
      : super(const ChantiersListState());

  /// A appeler AVANT [charger] : la premiere requete en tient compte.
  void joindreMesDemandes() => _avecMesDemandes = true;

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

    // Les deux appels partent ENSEMBLE : enchaines, ils doubleraient l'attente
    // avant le premier affichage du selecteur.
    final resultats = await Future.wait([
      getChantiers(
        page: 1, limit: _limit, search: state.recherche, statut: state.filtreStatut,
      ),
      if (_avecMesDemandes)
        getChantiers(page: 1, limit: _limit, search: state.recherche, demandes: VueDemandes.miennes),
    ]);
    if (isClosed || jeton != _jetonListe) return;

    // Les demandes en attente seulement. `demandes=mes` renvoie aussi les
    // demandes REFUSEES : y deposer un plan serait refuse par le serveur, et
    // proposer un chantier qu'on ne peut pas servir vaut moins que ne rien
    // proposer.
    final mesDemandes = resultats.length < 2
        ? const <Chantier>[]
        : resultats[1].fold<List<Chantier>>(
            (_) => const [],
            (page) => page.items
                .where((c) => c.statut == ChantierStatut.enAttenteValidation)
                .toList(),
          );
    _nbDemandes = mesDemandes.length;

    resultats[0].fold(
      (failure) => emit(state.copyWith(status: ChantiersListStatus.erreur, erreur: failure.errorMessage)),
      (page) => emit(state.copyWith(
        status: ChantiersListStatus.succes,
        // En TETE : ce sont elles qui attendent quelque chose de
        // l'utilisateur, et leur badge « en attente de validation » dit
        // clairement pourquoi elles ne ressemblent pas aux autres.
        items: [...mesDemandes, ...page.items],
        total: page.total + _nbDemandes,
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
        // `+ _nbDemandes` : les demandes sont en tete de `items` mais ne sont
        // pas comptees par le serveur dans ce total. Sans cette addition,
        // `aPlusDeResultats` retombait a faux une page trop tot.
        total: page.total + _nbDemandes,
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
