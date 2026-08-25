import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_plans_chantier.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_tous_plans.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/uploader_plan.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/cubit/plans_list_cubit.dart';

class MockGetTousPlans extends Mock implements GetTousPlans {}

class MockGetPlansChantier extends Mock implements GetPlansChantier {}

class MockUploaderPlan extends Mock implements UploaderPlan {}

Plan _plan(String id, {String nom = 'Plan', String chantierId = 'chantier-1', String? chantierNom}) => Plan(
      id: id,
      chantierId: chantierId,
      nom: nom,
      fichierUrl: 'https://exemple.test/$id.pdf',
      chantierNom: chantierNom,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(PlanFormat.pdf);
  });

  late MockGetTousPlans getTousPlans;
  late MockGetPlansChantier getPlansChantier;
  late MockUploaderPlan uploaderPlan;

  setUp(() {
    getTousPlans = MockGetTousPlans();
    getPlansChantier = MockGetPlansChantier();
    uploaderPlan = MockUploaderPlan();
  });

  PlansListCubit build() => PlansListCubit(
        getTousPlans: getTousPlans,
        getPlansChantier: getPlansChantier,
        uploaderPlan: uploaderPlan,
      );

  group('charger()', () {
    blocTest<PlansListCubit, PlansListState>(
      'sans chantierId : appelle getTousPlans() et charge la liste transversale',
      build: () {
        when(() => getTousPlans()).thenAnswer((_) async => Right([_plan('a'), _plan('b')]));
        return build();
      },
      act: (cubit) => cubit.charger(),
      expect: () => [
        const PlansListState(status: PlansListStatus.chargement),
        isA<PlansListState>()
            .having((s) => s.status, 'status', PlansListStatus.succes)
            .having((s) => s.items.length, 'items.length', 2),
      ],
      verify: (_) {
        verifyNever(() => getPlansChantier(any()));
      },
    );

    blocTest<PlansListCubit, PlansListState>(
      'sans chantierId : erreur du back → status erreur',
      build: () {
        when(() => getTousPlans()).thenAnswer((_) async => const Left(NetworkFailure()));
        return build();
      },
      act: (cubit) => cubit.charger(),
      expect: () => [
        const PlansListState(status: PlansListStatus.chargement),
        isA<PlansListState>()
            .having((s) => s.status, 'status', PlansListStatus.erreur)
            .having((s) => s.erreur, 'erreur', isNotNull),
      ],
    );

    blocTest<PlansListCubit, PlansListState>(
      'avec chantierId : appelle getPlansChantier() pour ce chantier précisément',
      build: () {
        when(() => getPlansChantier('chantier-1')).thenAnswer((_) async => Right([_plan('a')]));
        return build();
      },
      act: (cubit) => cubit.charger(chantierId: 'chantier-1'),
      expect: () => [
        const PlansListState(status: PlansListStatus.chargement),
        isA<PlansListState>()
            .having((s) => s.status, 'status', PlansListStatus.succes)
            .having((s) => s.items.single.id, 'items.single.id', 'a'),
      ],
      verify: (_) {
        verify(() => getPlansChantier('chantier-1')).called(1);
        verifyNever(() => getTousPlans());
      },
    );
  });

  group('importer()', () {
    blocTest<PlansListCubit, PlansListState>(
      'succès : bascule importEnCours, pose le message puis recharge la liste',
      build: () {
        when(() => uploaderPlan(
              chantierId: any(named: 'chantierId'),
              cheminFichier: any(named: 'cheminFichier'),
              nom: any(named: 'nom'),
              format: any(named: 'format'),
            )).thenAnswer((_) async => Right(_plan('nouveau', nom: 'Plan RDC')));
        when(() => getTousPlans()).thenAnswer((_) async => Right([_plan('nouveau', nom: 'Plan RDC')]));
        return build();
      },
      act: (cubit) => cubit.importer(
        chantierId: 'chantier-1',
        cheminFichier: '/tmp/plan.pdf',
        nom: 'Plan RDC',
      ),
      expect: () => [
        isA<PlansListState>().having((s) => s.importEnCours, 'importEnCours', true),
        isA<PlansListState>()
            .having((s) => s.importEnCours, 'importEnCours', false)
            .having((s) => s.messageSucces, 'messageSucces', '« Plan RDC » importé.'),
        isA<PlansListState>().having((s) => s.status, 'status', PlansListStatus.chargement),
        isA<PlansListState>()
            .having((s) => s.status, 'status', PlansListStatus.succes)
            .having((s) => s.items.single.nom, 'items.single.nom', 'Plan RDC'),
      ],
      verify: (_) {
        // Pas de chantierIdCourant fourni : le rechargement repart sur la liste transversale.
        verify(() => getTousPlans()).called(1);
      },
    );

    blocTest<PlansListCubit, PlansListState>(
      'succès avec chantierIdCourant : recharge via getPlansChantier(), pas getTousPlans()',
      build: () {
        when(() => uploaderPlan(
              chantierId: any(named: 'chantierId'),
              cheminFichier: any(named: 'cheminFichier'),
              nom: any(named: 'nom'),
              format: any(named: 'format'),
            )).thenAnswer((_) async => Right(_plan('nouveau', nom: 'Plan étage 1')));
        when(() => getPlansChantier('chantier-1'))
            .thenAnswer((_) async => Right([_plan('nouveau', nom: 'Plan étage 1')]));
        return build();
      },
      act: (cubit) => cubit.importer(
        chantierId: 'chantier-1',
        cheminFichier: '/tmp/plan.pdf',
        nom: 'Plan étage 1',
        chantierIdCourant: 'chantier-1',
      ),
      expect: () => [
        isA<PlansListState>().having((s) => s.importEnCours, 'importEnCours', true),
        isA<PlansListState>().having((s) => s.importEnCours, 'importEnCours', false),
        isA<PlansListState>().having((s) => s.status, 'status', PlansListStatus.chargement),
        isA<PlansListState>().having((s) => s.status, 'status', PlansListStatus.succes),
      ],
      verify: (_) {
        verify(() => getPlansChantier('chantier-1')).called(1);
        verifyNever(() => getTousPlans());
      },
    );

    blocTest<PlansListCubit, PlansListState>(
      'échec : importEnCours repasse à false et l\'erreur est posée, sans rechargement',
      build: () {
        when(() => uploaderPlan(
              chantierId: any(named: 'chantierId'),
              cheminFichier: any(named: 'cheminFichier'),
              nom: any(named: 'nom'),
              format: any(named: 'format'),
            )).thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'Format non supporté')));
        return build();
      },
      act: (cubit) => cubit.importer(
        chantierId: 'chantier-1',
        cheminFichier: '/tmp/plan.dwg',
        nom: 'Plan invalide',
      ),
      expect: () => [
        isA<PlansListState>().having((s) => s.importEnCours, 'importEnCours', true),
        isA<PlansListState>()
            .having((s) => s.importEnCours, 'importEnCours', false)
            .having((s) => s.erreur, 'erreur', 'Format non supporté'),
      ],
      verify: (_) {
        verifyNever(() => getTousPlans());
        verifyNever(() => getPlansChantier(any()));
      },
    );

    blocTest<PlansListCubit, PlansListState>(
      'un import déjà en cours est ignoré : aucun nouvel appel, aucune émission',
      build: () {
        when(() => uploaderPlan(
              chantierId: any(named: 'chantierId'),
              cheminFichier: any(named: 'cheminFichier'),
              nom: any(named: 'nom'),
              format: any(named: 'format'),
            )).thenAnswer((_) async => Right(_plan('x')));
        return build();
      },
      seed: () => const PlansListState(importEnCours: true),
      act: (cubit) => cubit.importer(
        chantierId: 'chantier-1',
        cheminFichier: '/tmp/plan.pdf',
        nom: 'Plan',
      ),
      expect: () => [],
      verify: (_) {
        verifyNever(() => uploaderPlan(
              chantierId: any(named: 'chantierId'),
              cheminFichier: any(named: 'cheminFichier'),
              nom: any(named: 'nom'),
              format: any(named: 'format'),
            ));
      },
    );
  });

  group('rechercher() / itemsFiltres', () {
    blocTest<PlansListCubit, PlansListState>(
      'filtre localement sur le nom du plan',
      build: build,
      seed: () => PlansListState(
        status: PlansListStatus.succes,
        items: [
          _plan('a', nom: 'Plan RDC', chantierNom: 'Résidence des Fleurs'),
          _plan('b', nom: 'Plan étage 1', chantierNom: 'Résidence des Fleurs'),
          _plan('c', nom: 'Charpente', chantierNom: 'Tour Nord'),
        ],
      ),
      act: (cubit) => cubit.rechercher('rdc'),
      expect: () => [
        isA<PlansListState>()
            .having((s) => s.recherche, 'recherche', 'rdc')
            .having((s) => s.itemsFiltres.map((p) => p.id).toList(), 'itemsFiltres', ['a']),
      ],
    );

    blocTest<PlansListCubit, PlansListState>(
      'filtre localement sur le nom du chantier',
      build: build,
      seed: () => PlansListState(
        status: PlansListStatus.succes,
        items: [
          _plan('a', nom: 'Plan RDC', chantierNom: 'Résidence des Fleurs'),
          _plan('b', nom: 'Charpente', chantierNom: 'Tour Nord'),
        ],
      ),
      act: (cubit) => cubit.rechercher('tour'),
      expect: () => [
        isA<PlansListState>().having((s) => s.itemsFiltres.map((p) => p.id).toList(), 'itemsFiltres', ['b']),
      ],
    );

    blocTest<PlansListCubit, PlansListState>(
      'recherche vide : itemsFiltres renvoie la liste complète, sans filtrage',
      build: build,
      // `recherche` non vide au départ : sinon `rechercher('')` reproduit
      // exactement l'état courant (déjà `recherche: ''` par défaut) et le
      // Cubit — état `Equatable` inchangé — n'émet rien du tout, ce que
      // `blocTest` verrait comme une liste d'émissions vide plutôt que
      // comme la levée du filtre attendue ici.
      seed: () => PlansListState(
        status: PlansListStatus.succes,
        items: [_plan('a'), _plan('b')],
        recherche: 'texte précédent',
      ),
      act: (cubit) => cubit.rechercher(''),
      expect: () => [
        isA<PlansListState>().having((s) => s.itemsFiltres.length, 'itemsFiltres.length', 2),
      ],
    );
  });

  group('effacerMessage()', () {
    blocTest<PlansListCubit, PlansListState>(
      'efface le message de succès affiché',
      build: build,
      seed: () => const PlansListState(messageSucces: '« Plan » importé.'),
      act: (cubit) => cubit.effacerMessage(),
      expect: () => [
        isA<PlansListState>().having((s) => s.messageSucces, 'messageSucces', isNull),
      ],
    );

    blocTest<PlansListCubit, PlansListState>(
      'rien à effacer : aucune émission',
      build: build,
      seed: () => const PlansListState(),
      act: (cubit) => cubit.effacerMessage(),
      expect: () => [],
    );
  });
}
