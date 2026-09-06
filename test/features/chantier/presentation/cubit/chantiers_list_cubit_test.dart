import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/entities/chantier.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/repositories/chantier_repository.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/usecases/get_chantiers.dart';
import 'package:suivie_chantier_mobile/features/dashboard/domain/entities/dashboard_stats.dart';
import 'package:suivie_chantier_mobile/features/dashboard/domain/usecases/get_dashboard_stats.dart';
import 'package:suivie_chantier_mobile/features/chantier/presentation/cubit/chantiers_list_cubit.dart';
import 'package:suivie_chantier_mobile/features/chantier/presentation/cubit/chantiers_list_state.dart';

class MockGetChantiers extends Mock implements GetChantiers {}

class MockGetDashboardStats extends Mock implements GetDashboardStats {}

Chantier _chantier(String id) => Chantier(id: id, nom: 'Chantier $id', statut: ChantierStatut.enCours);

void main() {
  late MockGetChantiers getChantiers;
  late MockGetDashboardStats getDashboardStats;

  setUp(() {
    getChantiers = MockGetChantiers();
    getDashboardStats = MockGetDashboardStats();
    // Les compteurs des puces ne sont chargés que par l'écran Chantiers
    // (`chargerCompteurs()`), jamais par `charger()` : le stub sert
    // seulement à ce que le cubit soit constructible.
    when(() => getDashboardStats()).thenAnswer((_) async => const Right(DashboardStats()));
  });

  blocTest<ChantiersListCubit, ChantiersListState>(
    'charger() remplace la liste et repart toujours de la page 1',
    build: () {
      when(() => getChantiers(page: 1, limit: 20, search: '', statut: null))
          .thenAnswer((_) async => Right(ChantierPage(items: [_chantier('a'), _chantier('b')], total: 2)));
      return ChantiersListCubit(getChantiers: getChantiers, getDashboardStats: getDashboardStats);
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const ChantiersListState(status: ChantiersListStatus.chargement),
      isA<ChantiersListState>()
          .having((s) => s.status, 'status', ChantiersListStatus.succes)
          .having((s) => s.items.length, 'items.length', 2)
          .having((s) => s.total, 'total', 2),
    ],
  );

  blocTest<ChantiersListCubit, ChantiersListState>(
    'chargerPageSuivante() AJOUTE à la liste existante sans la remplacer',
    build: () {
      when(() => getChantiers(page: 2, limit: 20, search: '', statut: null))
          .thenAnswer((_) async => Right(ChantierPage(items: [_chantier('c')], total: 3)));
      return ChantiersListCubit(getChantiers: getChantiers, getDashboardStats: getDashboardStats);
    },
    seed: () => ChantiersListState(
      status: ChantiersListStatus.succes,
      items: [_chantier('a'), _chantier('b')],
      total: 3,
      page: 1,
    ),
    act: (cubit) => cubit.chargerPageSuivante(),
    expect: () => [
      isA<ChantiersListState>().having((s) => s.chargementPage, 'chargementPage', true),
      isA<ChantiersListState>()
          .having((s) => s.items.map((c) => c.id).toList(), 'ids', ['a', 'b', 'c'])
          .having((s) => s.page, 'page', 2),
    ],
  );

  blocTest<ChantiersListCubit, ChantiersListState>(
    'chargerPageSuivante() ne fait rien si aPlusDeResultats est déjà false',
    build: () => ChantiersListCubit(getChantiers: getChantiers, getDashboardStats: getDashboardStats),
    seed: () => ChantiersListState(status: ChantiersListStatus.succes, items: [_chantier('a')], total: 1),
    act: (cubit) => cubit.chargerPageSuivante(),
    expect: () => [],
    verify: (_) => verifyNever(() => getChantiers(page: any(named: 'page'), limit: any(named: 'limit'))),
  );

  blocTest<ChantiersListCubit, ChantiersListState>(
    'émet erreur quand le backend échoue',
    build: () {
      when(() => getChantiers(page: 1, limit: 20, search: '', statut: null))
          .thenAnswer((_) async => const Left(NetworkFailure()));
      return ChantiersListCubit(getChantiers: getChantiers, getDashboardStats: getDashboardStats);
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const ChantiersListState(status: ChantiersListStatus.chargement),
      isA<ChantiersListState>().having((s) => s.status, 'status', ChantiersListStatus.erreur),
    ],
  );

  // ── Les demandes en attente, jointes au sélecteur de dépôt ────────────────
  //
  // Le serveur écarte les demandes de `GET /chantiers` : un chantier en
  // attente n'est pas un chantier. Mais c'est PRÉCISÉMENT sur elles qu'une
  // entreprise dépose ses plans — `plan.service.js#_refusDepot` ne l'y
  // autorise même QUE là, le dépôt repassant aux rôles opérationnels une fois
  // le chantier validé. Sans cette jonction, une entreprise revenue le
  // lendemain ne retrouvait plus sa demande, et n'avait plus aucun moyen d'y
  // ajouter un plan.

  Chantier demandeEnAttente(String id) =>
      Chantier(id: id, nom: 'Demande $id', statut: ChantierStatut.enAttenteValidation);

  blocTest<ChantiersListCubit, ChantiersListState>(
    'joindreMesDemandes() met les demandes en attente EN TÊTE de la liste',
    build: () {
      when(() => getChantiers(page: 1, limit: 20, search: '', statut: null))
          .thenAnswer((_) async => Right(ChantierPage(items: [_chantier('a')], total: 1)));
      when(() => getChantiers(
            page: 1, limit: 20, search: '', demandes: VueDemandes.miennes,
          )).thenAnswer((_) async => Right(ChantierPage(items: [demandeEnAttente('d1')], total: 1)));
      return ChantiersListCubit(getChantiers: getChantiers, getDashboardStats: getDashboardStats)
        ..joindreMesDemandes();
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const ChantiersListState(status: ChantiersListStatus.chargement),
      isA<ChantiersListState>()
          .having((s) => s.items.first.id, 'la demande vient en premier', 'd1')
          .having((s) => s.items.length, 'items.length', 2)
          // Le serveur ne compte pas les demandes dans le total de la liste :
          // sans cette addition, `aPlusDeResultats` retombait à faux une page
          // trop tôt.
          .having((s) => s.total, 'total', 2),
    ],
  );

  blocTest<ChantiersListCubit, ChantiersListState>(
    'une demande REFUSÉE n’est pas proposée',
    build: () {
      when(() => getChantiers(page: 1, limit: 20, search: '', statut: null))
          .thenAnswer((_) async => Right(ChantierPage(items: [_chantier('a')], total: 1)));
      // `demandes=mes` renvoie aussi les refusées. Y déposer un plan serait
      // refusé par le serveur, et proposer un chantier qu'on ne peut pas
      // servir vaut moins que ne rien proposer.
      when(() => getChantiers(
            page: 1, limit: 20, search: '', demandes: VueDemandes.miennes,
          )).thenAnswer((_) async => Right(ChantierPage(
            items: [Chantier(id: 'r1', nom: 'Refusée', statut: ChantierStatut.rejete)],
            total: 1,
          )));
      return ChantiersListCubit(getChantiers: getChantiers, getDashboardStats: getDashboardStats)
        ..joindreMesDemandes();
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const ChantiersListState(status: ChantiersListStatus.chargement),
      isA<ChantiersListState>()
          .having((s) => s.items.length, 'items.length', 1)
          .having((s) => s.items.single.id, 'seul le chantier en activité', 'a'),
    ],
  );

  blocTest<ChantiersListCubit, ChantiersListState>(
    'sans jonction, la liste ne demande AUCUNE demande au serveur',
    build: () {
      when(() => getChantiers(page: 1, limit: 20, search: '', statut: null))
          .thenAnswer((_) async => Right(ChantierPage(items: [_chantier('a')], total: 1)));
      return ChantiersListCubit(getChantiers: getChantiers, getDashboardStats: getDashboardStats);
    },
    act: (cubit) => cubit.charger(),
    verify: (_) {
      // Un aller-retour de plus sur chaque écran qui n'en a pas l'usage.
      verifyNever(() => getChantiers(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            search: any(named: 'search'),
            demandes: VueDemandes.miennes,
          ));
    },
  );

  blocTest<ChantiersListCubit, ChantiersListState>(
    'une panne sur les demandes ne fait pas tomber la liste',
    build: () {
      when(() => getChantiers(page: 1, limit: 20, search: '', statut: null))
          .thenAnswer((_) async => Right(ChantierPage(items: [_chantier('a')], total: 1)));
      when(() => getChantiers(
            page: 1, limit: 20, search: '', demandes: VueDemandes.miennes,
          )).thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'boum')));
      return ChantiersListCubit(getChantiers: getChantiers, getDashboardStats: getDashboardStats)
        ..joindreMesDemandes();
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const ChantiersListState(status: ChantiersListStatus.chargement),
      isA<ChantiersListState>()
          .having((s) => s.status, 'status', ChantiersListStatus.succes)
          .having((s) => s.items.length, 'items.length', 1),
    ],
  );
}
