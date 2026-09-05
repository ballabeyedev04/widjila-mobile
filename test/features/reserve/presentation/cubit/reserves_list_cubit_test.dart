import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/repositories/reserve_repository.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_reserve_statuts_count.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/usecases/get_reserves.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/cubit/reserves_list_cubit.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/cubit/reserves_list_state.dart';

class MockGetReserves extends Mock implements GetReserves {}

class MockGetReserveStatutsCount extends Mock implements GetReserveStatutsCount {}

Reserve _reserve(String id, {ReserveStatut statut = ReserveStatut.creee}) =>
    Reserve(id: id, numero: 'R-$id', chantierId: 'chantier-1', titre: 'Réserve $id', statut: statut);

const _chantierId = 'chantier-1';

void main() {
  late MockGetReserves getReserves;
  late MockGetReserveStatutsCount getReserveStatutsCount;

  setUp(() {
    getReserves = MockGetReserves();
    getReserveStatutsCount = MockGetReserveStatutsCount();
    // Stub par défaut : la plupart des tests ne s'intéressent pas aux
    // compteurs de statut, seulement à la pagination de la liste.
    when(() => getReserveStatutsCount(_chantierId))
        .thenAnswer((_) async => const Right(ReserveStatutsCount(parStatut: {}, total: 0)));
  });

  ReservesListCubit build() => ReservesListCubit(
        getReserves: getReserves,
        getReserveStatutsCount: getReserveStatutsCount,
        chantierId: _chantierId,
      );

  blocTest<ReservesListCubit, ReservesListState>(
    'charger() finit avec la liste ET les compteurs',
    build: () {
      when(() => getReserves(chantierId: _chantierId, page: 1, limit: 20, search: '', statut: null))
          .thenAnswer((_) async => Right(ReservePage(items: [_reserve('a'), _reserve('b')], total: 2)));
      when(() => getReserveStatutsCount(_chantierId)).thenAnswer(
        (_) async => const Right(ReserveStatutsCount(parStatut: {ReserveStatut.creee: 2}, total: 2)),
      );
      return build();
    },
    act: (cubit) => cubit.charger(),
    // Les deux appels partent ensemble et arrivent SÉPARÉMENT : les compteurs
    // se posent dès qu'ils sont là, sans attendre la liste, d'où un état
    // intermédiaire encore en chargement. C'est le prix — et le point — de la
    // désolidarisation vérifiée par le test suivant.
    skip: 1,
    expect: () => [
      isA<ReservesListState>()
          .having((s) => s.status, 'status', ReservesListStatus.chargement)
          .having((s) => s.statutsCount.total, 'statutsCount.total', 2),
      isA<ReservesListState>()
          .having((s) => s.status, 'status', ReservesListStatus.succes)
          .having((s) => s.items.length, 'items.length', 2)
          .having((s) => s.statutsCount.total, 'statutsCount.total', 2),
    ],
  );

  test('la liste s’affiche même si les compteurs ne répondent JAMAIS', () async {
    // Les compteurs ne chiffrent que les puces de filtre. Attendus avant le
    // moindre `emit`, ils retenaient la liste en otage : sur un chantier sans
    // réserve, l'écran gardait son squelette de chargement et le message
    // « Aucune réserve » n'apparaissait jamais.
    when(() => getReserves(chantierId: _chantierId, page: 1, limit: 20, search: '', statut: null))
        .thenAnswer((_) async => const Right(ReservePage(items: [], total: 0)));
    when(() => getReserveStatutsCount(_chantierId))
        .thenAnswer((_) => Completer<Either<Failure, ReserveStatutsCount>>().future);

    final cubit = build();
    await cubit.charger();

    expect(cubit.state.status, ReservesListStatus.succes);
    expect(cubit.state.items, isEmpty);
    await cubit.close();
  });

  blocTest<ReservesListCubit, ReservesListState>(
    'filtrerParStatut() relance charger() avec le filtre et repart de la page 1',
    build: () {
      when(() => getReserves(chantierId: _chantierId, page: 1, limit: 20, search: '', statut: ReserveStatut.validee))
          .thenAnswer((_) async => Right(ReservePage(items: [_reserve('a', statut: ReserveStatut.validee)], total: 1)));
      return build();
    },
    act: (cubit) => cubit.filtrerParStatut(ReserveStatut.validee),
    expect: () => [
      isA<ReservesListState>().having((s) => s.filtreStatut, 'filtreStatut', ReserveStatut.validee),
      isA<ReservesListState>().having((s) => s.status, 'status', ReservesListStatus.chargement),
      isA<ReservesListState>()
          .having((s) => s.status, 'status', ReservesListStatus.succes)
          .having((s) => s.items.single.statut, 'statut de l\'unique item', ReserveStatut.validee),
    ],
  );

  blocTest<ReservesListCubit, ReservesListState>(
    'chargerPageSuivante() ajoute à la liste sans la remplacer',
    build: () {
      when(() => getReserves(chantierId: _chantierId, page: 2, limit: 20, search: '', statut: null))
          .thenAnswer((_) async => Right(ReservePage(items: [_reserve('c')], total: 3)));
      return build();
    },
    seed: () => ReservesListState(status: ReservesListStatus.succes, items: [_reserve('a'), _reserve('b')], total: 3),
    act: (cubit) => cubit.chargerPageSuivante(),
    expect: () => [
      isA<ReservesListState>().having((s) => s.chargementPage, 'chargementPage', true),
      isA<ReservesListState>()
          .having((s) => s.items.map((r) => r.id).toList(), 'ids', ['a', 'b', 'c'])
          .having((s) => s.page, 'page', 2),
    ],
  );

  blocTest<ReservesListCubit, ReservesListState>(
    'émet erreur quand le back échoue, sans casser sur une panne des compteurs',
    build: () {
      when(() => getReserves(chantierId: _chantierId, page: 1, limit: 20, search: '', statut: null))
          .thenAnswer((_) async => const Left(NetworkFailure()));
      when(() => getReserveStatutsCount(_chantierId)).thenAnswer((_) async => const Left(NetworkFailure()));
      return build();
    },
    act: (cubit) => cubit.charger(),
    expect: () => [
      const ReservesListState(status: ReservesListStatus.chargement),
      isA<ReservesListState>().having((s) => s.status, 'status', ReservesListStatus.erreur),
    ],
  );
}
