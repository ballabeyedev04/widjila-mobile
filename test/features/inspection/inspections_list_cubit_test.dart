import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/inspection/domain/entities/inspection.dart';
import 'package:suivie_chantier_mobile/features/inspection/domain/repositories/inspection_repository.dart';
import 'package:suivie_chantier_mobile/features/inspection/domain/usecases/inspection_usecases.dart';
import 'package:suivie_chantier_mobile/features/inspection/presentation/cubit/inspections_list_cubit.dart';
import 'package:suivie_chantier_mobile/features/inspection/presentation/cubit/inspections_list_state.dart';

class _MockRepository extends Mock implements InspectionRepository {}

void main() {
  late _MockRepository repository;
  late InspectionsListCubit cubit;

  const chantierId = 'c1';

  Inspection visite({
    String id = 'i1',
    InspectionStatut statut = InspectionStatut.planifiee,
    DateTime? date,
  }) =>
      Inspection(id: id, chantierId: chantierId, statut: statut, dateVisite: date);

  InspectionsListCubit construire() => InspectionsListCubit(
        getInspections: GetInspections(repository),
        creerInspection: CreerInspection(repository),
        chantierId: chantierId,
      );

  setUpAll(() {
    registerFallbackValue(InspectionStatut.planifiee);
    registerFallbackValue(InspectionType.inspection);
  });

  setUp(() => repository = _MockRepository());
  tearDown(() async => cubit.close());

  group('charger', () {
    test('remplit la liste', () async {
      when(() => repository.getInspections(
            chantierId: any(named: 'chantierId'),
            statut: any(named: 'statut'),
          )).thenAnswer((_) async => Right([visite()]));

      cubit = construire();
      await cubit.charger();

      expect(cubit.state.status, InspectionsListStatus.succes);
      expect(cubit.state.items, hasLength(1));
    });

    test('remonte l\'erreur', () async {
      when(() => repository.getInspections(
            chantierId: any(named: 'chantierId'),
            statut: any(named: 'statut'),
          )).thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'hors ligne')));

      cubit = construire();
      await cubit.charger();

      expect(cubit.state.status, InspectionsListStatus.erreur);
      expect(cubit.state.erreur, 'hors ligne');
    });

    test('une réponse PÉRIMÉE n\'écrase pas une plus récente', () async {
      // Deux filtres enchaînés : la première requête répond APRÈS la seconde.
      // Sans jeton, l'écran afficherait le résultat du filtre abandonné.
      var appel = 0;
      when(() => repository.getInspections(
            chantierId: any(named: 'chantierId'),
            statut: any(named: 'statut'),
          )).thenAnswer((_) async {
        appel++;
        if (appel == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          return Right([visite(id: 'ancienne')]);
        }
        return Right([visite(id: 'recente')]);
      });

      cubit = construire();
      final lente = cubit.charger();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final rapide = cubit.charger();

      await Future.wait([lente, rapide]);

      expect(cubit.state.items.single.id, 'recente');
    });
  });

  group('planifier', () {
    setUp(() {
      when(() => repository.getInspections(
            chantierId: any(named: 'chantierId'),
            statut: any(named: 'statut'),
          )).thenAnswer((_) async => const Right([]));
    });

    test('insère la visite créée en tête', () async {
      when(() => repository.creerInspection(
            chantierId: any(named: 'chantierId'),
            type: any(named: 'type'),
            dateVisite: any(named: 'dateVisite'),
            libellesChecklist: any(named: 'libellesChecklist'),
          )).thenAnswer((_) async => Right(visite(id: 'neuve')));

      cubit = construire();
      await cubit.charger();
      await cubit.planifier(type: InspectionType.opr, libellesChecklist: const ['A', 'B']);

      expect(cubit.state.creationStatus, CreationInspectionStatus.succes);
      expect(cubit.state.items.first.id, 'neuve');
    });

    test('ignore un second appui pendant la création', () async {
      var appels = 0;
      when(() => repository.creerInspection(
            chantierId: any(named: 'chantierId'),
            type: any(named: 'type'),
            dateVisite: any(named: 'dateVisite'),
            libellesChecklist: any(named: 'libellesChecklist'),
          )).thenAnswer((_) async {
        appels++;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return Right(visite(id: 'neuve'));
      });

      cubit = construire();
      final a = cubit.planifier(type: InspectionType.inspection);
      final b = cubit.planifier(type: InspectionType.inspection);
      await Future.wait([a, b]);

      // Deux visites identiques créées pour un double tap seraient à
      // supprimer à la main ensuite.
      expect(appels, 1);
    });
  });

  group('enRetard', () {
    Inspection planifieeLe(DateTime d) => visite(statut: InspectionStatut.planifiee, date: d);

    test('une visite planifiée dont la date est passée est en retard', () {
      final hier = DateTime.now().subtract(const Duration(days: 1));
      final state = InspectionsListState(items: [planifieeLe(hier)]);
      expect(state.enRetard, hasLength(1));
    });

    test('une visite planifiée AUJOURD\'HUI n\'est pas en retard', () {
      // Comparaison sur la date seule : sinon une visite du jour basculerait
      // en « retard » dès minuit une.
      final maintenant = DateTime.now();
      final state = InspectionsListState(items: [planifieeLe(maintenant)]);
      expect(state.enRetard, isEmpty);
    });

    test('une visite DÉJÀ démarrée n\'est jamais en retard', () {
      final hier = DateTime.now().subtract(const Duration(days: 3));
      final state = InspectionsListState(
        items: [visite(statut: InspectionStatut.enCours, date: hier)],
      );
      expect(state.enRetard, isEmpty);
    });

    test('une visite sans date n\'est pas en retard', () {
      final state = InspectionsListState(items: [visite()]);
      expect(state.enRetard, isEmpty);
    });
  });

  group('enCours', () {
    test('ne retient que les visites ouvertes', () {
      final state = InspectionsListState(items: [
        visite(id: 'a', statut: InspectionStatut.planifiee),
        visite(id: 'b', statut: InspectionStatut.enCours),
        visite(id: 'c', statut: InspectionStatut.terminee),
        visite(id: 'd', statut: InspectionStatut.signee),
      ]);

      expect(state.enCours.map((i) => i.id), ['a', 'b']);
    });
  });

  test('remplacer met à jour une ligne sans recharger', () async {
    when(() => repository.getInspections(
          chantierId: any(named: 'chantierId'),
          statut: any(named: 'statut'),
        )).thenAnswer((_) async => Right([visite(id: 'i1'), visite(id: 'i2')]));

    cubit = construire();
    await cubit.charger();

    cubit.remplacer(visite(id: 'i2', statut: InspectionStatut.signee));

    expect(cubit.state.items[1].statut, InspectionStatut.signee);
    expect(cubit.state.items[0].statut, InspectionStatut.planifiee);
    verify(() => repository.getInspections(
          chantierId: any(named: 'chantierId'),
          statut: any(named: 'statut'),
        )).called(1);
  });
}
