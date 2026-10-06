import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/offline/cache_reserves.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/features/plan/data/datasources/plan_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/plan/data/repositories/plan_repository_impl.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';

class MockPlanRemoteDataSource extends Mock implements PlanRemoteDataSource {}

class MockCacheReserves extends Mock implements CacheReserves {}

Plan _plan({String id = 'p1', String chantierId = 'chantier-1'}) => Plan(
      id: id,
      chantierId: chantierId,
      nom: 'Plan RDC',
      fichierUrl: 'https://exemple.test/$id.pdf',
    );

void main() {
  setUpAll(() {
    registerFallbackValue(PlanFormat.pdf);
  });

  late MockPlanRemoteDataSource remote;
  late PlanRepositoryImpl repository;

  setUp(() {
    remote = MockPlanRemoteDataSource();
    repository = PlanRepositoryImpl(remote);
  });

  group('getTousPlans', () {
    test('succès : renvoie la liste des plans à droite', () async {
      when(() => remote.getTousPlans()).thenAnswer((_) async => [_plan(id: 'a'), _plan(id: 'b')]);

      final resultat = await repository.getTousPlans();

      expect(resultat, isA<Right<Failure, List<Plan>>>());
      resultat.fold((_) => fail('doit réussir'), (plans) => expect(plans.map((p) => p.id), ['a', 'b']));
    });

    test('coupure réseau : NetworkException devient NetworkFailure à gauche', () async {
      when(() => remote.getTousPlans()).thenThrow(const NetworkException());

      final resultat = await repository.getTousPlans();

      expect(resultat.isLeft(), isTrue);
      resultat.fold((failure) => expect(failure, isA<NetworkFailure>()), (_) => fail('doit échouer'));
    });
  });

  group('getPlansChantier', () {
    test('succès : renvoie les plans du chantier demandé', () async {
      when(() => remote.getPlansChantier('chantier-1')).thenAnswer((_) async => [_plan(id: 'a')]);

      final resultat = await repository.getPlansChantier('chantier-1');

      expect(resultat.isRight(), isTrue);
      resultat.fold((_) => fail('doit réussir'), (plans) => expect(plans.single.id, 'a'));
    });

    test('erreur serveur : ServerException devient ServerFailure avec le code HTTP', () async {
      when(() => remote.getPlansChantier('chantier-1'))
          .thenThrow(const ServerException(message: 'Chantier introuvable', statusCode: 404));

      final resultat = await repository.getPlansChantier('chantier-1');

      expect(resultat.isLeft(), isTrue);
      resultat.fold((failure) {
        expect(failure, isA<ServerFailure>());
        expect(failure.errorMessage, 'Chantier introuvable');
        expect((failure as ServerFailure).statusCode, 404);
      }, (_) => fail('doit échouer'));
    });
  });

  group('getPlanDetail', () {
    test('succès : renvoie le plan avec ses réserves', () async {
      when(() => remote.getPlanDetail('p1')).thenAnswer((_) async => _plan(id: 'p1'));

      final resultat = await repository.getPlanDetail('p1');

      expect(resultat.isRight(), isTrue);
      resultat.fold((_) => fail('doit réussir'), (plan) => expect(plan.id, 'p1'));
    });

    test('échec : exception non reconnue retombe sur un ServerFailure générique', () async {
      when(() => remote.getPlanDetail('introuvable')).thenThrow(Exception('boom'));

      final resultat = await repository.getPlanDetail('introuvable');

      expect(resultat.isLeft(), isTrue);
      resultat.fold((failure) => expect(failure, isA<ServerFailure>()), (_) => fail('doit échouer'));
    });
  });

  group('uploaderPlan', () {
    test('succès : transmet les paramètres à la source de données et renvoie le plan créé', () async {
      when(() => remote.uploaderPlan(
            chantierId: any(named: 'chantierId'),
            cheminFichier: any(named: 'cheminFichier'),
            nom: any(named: 'nom'),
            format: any(named: 'format'),
          )).thenAnswer((_) async => _plan(id: 'nouveau'));

      final resultat = await repository.uploaderPlan(
        chantierId: 'chantier-1',
        cheminFichier: '/tmp/plan.pdf',
        nom: 'Plan RDC',
        format: PlanFormat.pdf,
      );

      expect(resultat.isRight(), isTrue);
      resultat.fold((_) => fail('doit réussir'), (plan) => expect(plan.id, 'nouveau'));
      verify(() => remote.uploaderPlan(
            chantierId: 'chantier-1',
            cheminFichier: '/tmp/plan.pdf',
            nom: 'Plan RDC',
            format: PlanFormat.pdf,
          )).called(1);
    });

    test('échec : session expirée devient AuthFailure', () async {
      when(() => remote.uploaderPlan(
            chantierId: any(named: 'chantierId'),
            cheminFichier: any(named: 'cheminFichier'),
            nom: any(named: 'nom'),
            format: any(named: 'format'),
          )).thenThrow(const UnauthorizedException());

      final resultat = await repository.uploaderPlan(
        chantierId: 'chantier-1',
        cheminFichier: '/tmp/plan.dwg',
        nom: 'Plan sous-sol',
      );

      expect(resultat.isLeft(), isTrue);
      resultat.fold((failure) => expect(failure, isA<AuthFailure>()), (_) => fail('doit échouer'));
    });
  });
  group('getPlanDetail — réserves créées sans réseau', () {
    Reserve locale({String id = 'r-local', String planId = 'p1', bool avecPosition = true}) => Reserve.fromJson({
          'id': id,
          'numero': 'R-?',
          'chantierId': 'chantier-1',
          'titre': 'Fissure',
          'statut': 'creee',
          'severite': 'haute',
          'plan': {'id': planId, 'nom': 'Plan RDC'},
          if (avecPosition) 'position': {'x': 40.0, 'y': 60.0, 'page': 2},
        });

    test('une réserve locale posée sur le plan y apparaît tout de suite, à son point', () async {
      final cache = MockCacheReserves();
      when(() => cache.listerParChantier('chantier-1')).thenAnswer((_) async => [locale()]);
      when(() => remote.getPlanDetail('p1')).thenAnswer((_) async => _plan());
      final repo = PlanRepositoryImpl(remote, reservesLocales: cache);

      final plan = (await repo.getPlanDetail('p1')).getOrElse(() => throw 'attendu Right');

      expect(plan.reserves.map((r) => r.id), ['r-local']);
      expect(plan.reserves.single.position!.x, 40.0);
      expect(plan.reserves.single.position!.page, 2);
    });

    test('une réserve d’un AUTRE plan, ou sans point, n’est pas ajoutée', () async {
      final cache = MockCacheReserves();
      when(() => cache.listerParChantier('chantier-1')).thenAnswer(
          (_) async => [locale(id: 'a', planId: 'autre'), locale(id: 'b', avecPosition: false)]);
      when(() => remote.getPlanDetail('p1')).thenAnswer((_) async => _plan());
      final repo = PlanRepositoryImpl(remote, reservesLocales: cache);

      final plan = (await repo.getPlanDetail('p1')).getOrElse(() => throw 'attendu Right');

      expect(plan.reserves, isEmpty);
    });

    test('une base locale illisible laisse le plan tel que le serveur l’a donné', () async {
      final cache = MockCacheReserves();
      when(() => cache.listerParChantier(any())).thenThrow(Exception('base verrouillée'));
      when(() => remote.getPlanDetail('p1')).thenAnswer((_) async => _plan());
      final repo = PlanRepositoryImpl(remote, reservesLocales: cache);

      expect((await repo.getPlanDetail('p1')).isRight(), isTrue);
    });
  });
}
