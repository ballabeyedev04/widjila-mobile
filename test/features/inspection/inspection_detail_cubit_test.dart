import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/inspection/domain/entities/inspection.dart';
import 'package:suivie_chantier_mobile/features/inspection/domain/repositories/inspection_repository.dart';
import 'package:suivie_chantier_mobile/features/inspection/domain/usecases/inspection_usecases.dart';
import 'package:suivie_chantier_mobile/features/inspection/presentation/cubit/inspection_detail_cubit.dart';
import 'package:suivie_chantier_mobile/features/inspection/presentation/cubit/inspection_detail_state.dart';

class _MockRepository extends Mock implements InspectionRepository {}

/// Le cochage est OPTIMISTE : la case bascule avant la réponse du serveur.
/// C'est ce qui rend la saisie utilisable sur un chantier, et c'est aussi la
/// partie la plus facile à casser — d'où la densité de tests ici.
void main() {
  late _MockRepository repository;
  late InspectionDetailCubit cubit;

  const inspectionId = 'i1';

  Inspection inspectionAvec({
    InspectionStatut statut = InspectionStatut.enCours,
    List<LigneChecklist> checklist = const [
      LigneChecklist(id: 'l1', libelle: 'Étanchéité'),
      LigneChecklist(id: 'l2', libelle: 'Garde-corps', coche: true),
    ],
  }) =>
      Inspection(id: inspectionId, chantierId: 'c1', statut: statut, checklist: checklist);

  InspectionDetailCubit construire() => InspectionDetailCubit(
        getInspection: GetInspection(repository),
        cocherLigne: CocherLigneChecklist(repository),
        changerStatut: ChangerStatutInspection(repository),
        getConvocations: GetConvocations(repository),
        repondreConvocation: RepondreConvocation(repository),
        inspectionId: inspectionId,
      );

  // `any(named: 'statut')` porte sur un enum : mocktail exige une valeur de
  // repli pour tout type qui n'est pas primitif.
  setUpAll(() {
    registerFallbackValue(InspectionStatut.planifiee);
    registerFallbackValue(StatutConvocation.invite);
  });

  setUp(() {
    repository = _MockRepository();
    when(() => repository.getConvocations(any())).thenAnswer((_) async => const Right([]));
  });

  tearDown(() async => cubit.close());

  group('chargement', () {
    test('charge la visite et ses convocations', () async {
      when(() => repository.getInspection(any()))
          .thenAnswer((_) async => Right(inspectionAvec()));
      when(() => repository.getConvocations(any())).thenAnswer(
        (_) async => const Right([Convocation(id: 'cv1', statut: StatutConvocation.accepte)]),
      );

      cubit = construire();
      await cubit.charger();

      expect(cubit.state.status, InspectionDetailStatus.succes);
      expect(cubit.state.inspection?.checklist, hasLength(2));
      expect(cubit.state.convocations, hasLength(1));
    });

    test('un échec des CONVOCATIONS ne fait pas échouer l\'écran', () async {
      // La checklist doit rester utilisable même si la liste des convoqués
      // n'a pas pu être récupérée : ce sont deux appels distincts.
      when(() => repository.getInspection(any()))
          .thenAnswer((_) async => Right(inspectionAvec()));
      when(() => repository.getConvocations(any()))
          .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'boom')));

      cubit = construire();
      await cubit.charger();

      expect(cubit.state.status, InspectionDetailStatus.succes);
      expect(cubit.state.inspection, isNotNull);
      expect(cubit.state.convocations, isEmpty);
    });

    test('un échec de la VISITE met l\'écran en erreur', () async {
      when(() => repository.getInspection(any()))
          .thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'injoignable')));

      cubit = construire();
      await cubit.charger();

      expect(cubit.state.status, InspectionDetailStatus.erreur);
      expect(cubit.state.erreur, 'injoignable');
    });
  });

  group('basculerLigne — mise à jour optimiste', () {
    setUp(() {
      when(() => repository.getInspection(any()))
          .thenAnswer((_) async => Right(inspectionAvec()));
    });

    test('coche immédiatement, avant la réponse du serveur', () async {
      when(() => repository.cocherLigne(
            inspectionId: any(named: 'inspectionId'),
            ligneId: any(named: 'ligneId'),
            coche: any(named: 'coche'),
            commentaire: any(named: 'commentaire'),
          )).thenAnswer((_) async {
        // Pendant que la requête est « en vol », la case doit DÉJÀ être cochée.
        final ligne = cubit.state.inspection!.checklist.firstWhere((l) => l.id == 'l1');
        expect(ligne.coche, isTrue, reason: 'la bascule doit être immédiate');
        expect(cubit.state.lignesEnCours, contains('l1'));
        return const Right(LigneChecklist(id: 'l1', libelle: 'Étanchéité', coche: true));
      });

      cubit = construire();
      await cubit.charger();
      final ligne = cubit.state.inspection!.checklist.first;

      await cubit.basculerLigne(ligne);

      expect(cubit.state.inspection!.checklist.first.coche, isTrue);
      expect(cubit.state.lignesEnCours, isEmpty);
    });

    test('revient en arrière si le serveur refuse', () async {
      when(() => repository.cocherLigne(
            inspectionId: any(named: 'inspectionId'),
            ligneId: any(named: 'ligneId'),
            coche: any(named: 'coche'),
            commentaire: any(named: 'commentaire'),
          )).thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'refusé')));

      cubit = construire();
      await cubit.charger();
      final ligne = cubit.state.inspection!.checklist.first; // l1, non cochée

      await cubit.basculerLigne(ligne);

      // La case reprend sa valeur d'origine — sinon l'utilisateur croirait
      // avoir validé un point qui ne l'est pas côté serveur.
      expect(cubit.state.inspection!.checklist.first.coche, isFalse);
      expect(cubit.state.erreurAction, 'refusé');
      expect(cubit.state.lignesEnCours, isEmpty);
    });

    test('décoche une ligne déjà cochée', () async {
      when(() => repository.cocherLigne(
            inspectionId: any(named: 'inspectionId'),
            ligneId: any(named: 'ligneId'),
            coche: any(named: 'coche'),
            commentaire: any(named: 'commentaire'),
          )).thenAnswer((_) async => const Right(LigneChecklist(id: 'l2', libelle: 'x')));

      cubit = construire();
      await cubit.charger();
      final ligne = cubit.state.inspection!.checklist[1]; // l2, cochée

      await cubit.basculerLigne(ligne);

      expect(cubit.state.inspection!.checklist[1].coche, isFalse);
      verify(() => repository.cocherLigne(
            inspectionId: inspectionId,
            ligneId: 'l2',
            coche: false,
            commentaire: null,
          )).called(1);
    });

    test('ignore une seconde bascule sur la MÊME ligne pendant l\'envoi', () async {
      var appels = 0;
      when(() => repository.cocherLigne(
            inspectionId: any(named: 'inspectionId'),
            ligneId: any(named: 'ligneId'),
            coche: any(named: 'coche'),
            commentaire: any(named: 'commentaire'),
          )).thenAnswer((_) async {
        appels++;
        await Future<void>.delayed(const Duration(milliseconds: 40));
        return const Right(LigneChecklist(id: 'l1', libelle: 'x', coche: true));
      });

      cubit = construire();
      await cubit.charger();
      final ligne = cubit.state.inspection!.checklist.first;

      // Double tap rapide : sans le verrou, la ligne serait cochée puis
      // décochée, et l'état final contredirait le serveur.
      final a = cubit.basculerLigne(ligne);
      final b = cubit.basculerLigne(ligne);
      await Future.wait([a, b]);

      expect(appels, 1);
      expect(cubit.state.inspection!.checklist.first.coche, isTrue);
    });

    test('n\'envoie RIEN sur une visite signée', () async {
      when(() => repository.getInspection(any()))
          .thenAnswer((_) async => Right(inspectionAvec(statut: InspectionStatut.signee)));

      cubit = construire();
      await cubit.charger();
      final ligne = cubit.state.inspection!.checklist.first;

      await cubit.basculerLigne(ligne);

      // Le serveur refuserait de toute façon ; laisser la case bouger
      // ferait croire à une modification prise en compte.
      verifyNever(() => repository.cocherLigne(
            inspectionId: any(named: 'inspectionId'),
            ligneId: any(named: 'ligneId'),
            coche: any(named: 'coche'),
            commentaire: any(named: 'commentaire'),
          ));
      expect(cubit.state.inspection!.checklist.first.coche, isFalse);
    });
  });

  group('avancerVers', () {
    test('remplace la visite par celle renvoyée', () async {
      when(() => repository.getInspection(any()))
          .thenAnswer((_) async => Right(inspectionAvec()));
      when(() => repository.changerStatut(
            id: any(named: 'id'),
            statut: any(named: 'statut'),
            compteRendu: any(named: 'compteRendu'),
          )).thenAnswer((_) async => Right(inspectionAvec(statut: InspectionStatut.terminee)));

      cubit = construire();
      await cubit.charger();
      await cubit.avancerVers(InspectionStatut.terminee);

      expect(cubit.state.inspection!.statut, InspectionStatut.terminee);
    });

    test('signale l\'erreur sans vider l\'écran', () async {
      when(() => repository.getInspection(any()))
          .thenAnswer((_) async => Right(inspectionAvec()));
      when(() => repository.changerStatut(
            id: any(named: 'id'),
            statut: any(named: 'statut'),
            compteRendu: any(named: 'compteRendu'),
          )).thenAnswer((_) async => const Left(ServerFailure(errorMessage: 'interdit')));

      cubit = construire();
      await cubit.charger();
      await cubit.avancerVers(InspectionStatut.signee);

      expect(cubit.state.erreurAction, 'interdit');
      expect(cubit.state.inspection, isNotNull, reason: 'la visite reste lisible');
      expect(cubit.state.inspection!.statut, InspectionStatut.enCours);
    });
  });
}
