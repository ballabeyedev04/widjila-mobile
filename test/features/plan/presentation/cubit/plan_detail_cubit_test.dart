import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_plan_detail.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/cubit/plan_detail_cubit.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';

class MockGetPlanDetail extends Mock implements GetPlanDetail {}

PlanReserve _reserve(String id, {String titre = 'Fissure'}) => PlanReserve(
      id: id,
      numero: 'R-$id',
      titre: titre,
      statut: ReserveStatut.creee,
      severite: ReserveSeverite.moyenne,
      position: const PlanPosition(x: 10, y: 20),
    );

Plan _plan({String id = 'p1', List<PlanReserve> reserves = const []}) => Plan(
      id: id,
      chantierId: 'chantier-1',
      nom: 'Plan RDC',
      fichierUrl: 'https://exemple.test/$id.pdf',
      reserves: reserves,
    );

void main() {
  late MockGetPlanDetail getPlanDetail;

  setUp(() {
    getPlanDetail = MockGetPlanDetail();
  });

  PlanDetailCubit build() => PlanDetailCubit(getPlanDetail: getPlanDetail);

  group('charger()', () {
    blocTest<PlanDetailCubit, PlanDetailState>(
      'succès : charge le plan et ses réserves positionnées',
      build: () {
        final plan = _plan(reserves: [_reserve('r1'), _reserve('r2')]);
        when(() => getPlanDetail('p1')).thenAnswer((_) async => Right(plan));
        return build();
      },
      act: (cubit) => cubit.charger('p1'),
      expect: () => [
        const PlanDetailState(status: PlanDetailStatus.chargement),
        isA<PlanDetailState>()
            .having((s) => s.status, 'status', PlanDetailStatus.succes)
            .having((s) => s.plan?.id, 'plan.id', 'p1')
            .having((s) => s.plan?.reserves.length, 'plan.reserves.length', 2),
      ],
    );

    blocTest<PlanDetailCubit, PlanDetailState>(
      'échec : le plan est introuvable → status erreur',
      build: () {
        when(() => getPlanDetail('inconnu'))
            .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Plan introuvable', statusCode: 404)));
        return build();
      },
      act: (cubit) => cubit.charger('inconnu'),
      expect: () => [
        const PlanDetailState(status: PlanDetailStatus.chargement),
        isA<PlanDetailState>()
            .having((s) => s.status, 'status', PlanDetailStatus.erreur)
            .having((s) => s.erreur, 'erreur', 'Plan introuvable'),
      ],
    );
  });

  group('selectionner()', () {
    blocTest<PlanDetailCubit, PlanDetailState>(
      'sélectionne le repère d\'une réserve',
      build: build,
      seed: () => PlanDetailState(status: PlanDetailStatus.succes, plan: _plan(reserves: [_reserve('r1'), _reserve('r2')])),
      act: (cubit) => cubit.selectionner('r1'),
      expect: () => [
        isA<PlanDetailState>().having((s) => s.reserveSelectionneeId, 'reserveSelectionneeId', 'r1'),
      ],
    );

    blocTest<PlanDetailCubit, PlanDetailState>(
      'retoucher le même repère le désélectionne (bascule)',
      build: build,
      seed: () => PlanDetailState(
        status: PlanDetailStatus.succes,
        plan: _plan(reserves: [_reserve('r1')]),
        reserveSelectionneeId: 'r1',
      ),
      act: (cubit) => cubit.selectionner('r1'),
      expect: () => [
        isA<PlanDetailState>().having((s) => s.reserveSelectionneeId, 'reserveSelectionneeId', isNull),
      ],
    );

    blocTest<PlanDetailCubit, PlanDetailState>(
      'sélectionner un autre repère bascule directement dessus',
      build: build,
      seed: () => PlanDetailState(
        status: PlanDetailStatus.succes,
        plan: _plan(reserves: [_reserve('r1'), _reserve('r2')]),
        reserveSelectionneeId: 'r1',
      ),
      act: (cubit) => cubit.selectionner('r2'),
      expect: () => [
        isA<PlanDetailState>().having((s) => s.reserveSelectionneeId, 'reserveSelectionneeId', 'r2'),
      ],
    );
  });

  group('effacerSelection()', () {
    blocTest<PlanDetailCubit, PlanDetailState>(
      'efface le repère sélectionné',
      build: build,
      seed: () => PlanDetailState(
        status: PlanDetailStatus.succes,
        plan: _plan(reserves: [_reserve('r1')]),
        reserveSelectionneeId: 'r1',
      ),
      act: (cubit) => cubit.effacerSelection(),
      expect: () => [
        isA<PlanDetailState>().having((s) => s.reserveSelectionneeId, 'reserveSelectionneeId', isNull),
      ],
    );
  });

  group('reserveSelectionnee (getter)', () {
    test('renvoie la PlanReserve correspondant à l\'id sélectionné', () {
      final r1 = _reserve('r1', titre: 'Fissure mur porteur');
      final r2 = _reserve('r2', titre: 'Peinture écaillée');
      final state = PlanDetailState(
        status: PlanDetailStatus.succes,
        plan: _plan(reserves: [r1, r2]),
        reserveSelectionneeId: 'r2',
      );

      expect(state.reserveSelectionnee, r2);
      expect(state.reserveSelectionnee?.titre, 'Peinture écaillée');
    });

    test('renvoie null quand aucun repère n\'est sélectionné', () {
      final state = PlanDetailState(
        status: PlanDetailStatus.succes,
        plan: _plan(reserves: [_reserve('r1')]),
      );

      expect(state.reserveSelectionnee, isNull);
    });

    test('renvoie null quand aucun plan n\'est encore chargé', () {
      const state = PlanDetailState(reserveSelectionneeId: 'r1');

      expect(state.reserveSelectionnee, isNull);
    });

    test('renvoie null quand l\'id sélectionné ne correspond à aucune réserve du plan', () {
      final state = PlanDetailState(
        status: PlanDetailStatus.succes,
        plan: _plan(reserves: [_reserve('r1')]),
        reserveSelectionneeId: 'introuvable',
      );

      expect(state.reserveSelectionnee, isNull);
    });
  });
}
