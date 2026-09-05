import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/error_view.dart';
import 'package:suivie_chantier_mobile/features/inspection/domain/entities/inspection.dart';
import 'package:suivie_chantier_mobile/features/inspection/domain/usecases/inspection_usecases.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';
import 'package:suivie_chantier_mobile/features/inspection/presentation/pages/inspection_detail_page.dart';

import '../../../../helpers/pompe_page.dart';

class _MockGet extends Mock implements GetInspection {}

class _MockCocher extends Mock implements CocherLigneChecklist {}

class _MockStatut extends Mock implements ChangerStatutInspection {}

class _MockConvocations extends Mock implements GetConvocations {}

class _MockRepondre extends Mock implements RepondreConvocation {}

/// La fiche d'une inspection.
///
/// ## Deux requêtes, une seule fiche
///
/// La visite et ses convocations sont lues séparément. Les convocations ne
/// sont pas le sujet de l'écran : leur échec ne doit pas emporter la
/// checklist, qui est la raison d'être de la fiche et la seule chose qu'on
/// vient y faire sur un chantier.
///
/// ## Une visite sans checklist
///
/// C'est le cas normal d'une visite qui vient d'être planifiée. La fiche
/// calcule un avancement : sans point de contrôle, la division serait un
/// `NaN` et la barre de progression se dessinerait de travers — ou pas du
/// tout.
void main() {
  late _MockGet getInspection;
  late _MockConvocations getConvocations;

  void desinscrire() {
    if (sl.isRegistered<GetInspection>()) sl.unregister<GetInspection>();
    if (sl.isRegistered<CocherLigneChecklist>()) sl.unregister<CocherLigneChecklist>();
    if (sl.isRegistered<ChangerStatutInspection>()) sl.unregister<ChangerStatutInspection>();
    if (sl.isRegistered<GetConvocations>()) sl.unregister<GetConvocations>();
    if (sl.isRegistered<RepondreConvocation>()) sl.unregister<RepondreConvocation>();
  }

  setUp(() {
    getInspection = _MockGet();
    getConvocations = _MockConvocations();
    when(() => getConvocations(any()))
        .thenAnswer((_) async => const Right<Failure, List<Convocation>>([]));

    desinscrire();
    sl.registerFactory<GetInspection>(() => getInspection);
    sl.registerFactory<CocherLigneChecklist>(() => _MockCocher());
    sl.registerFactory<ChangerStatutInspection>(() => _MockStatut());
    sl.registerFactory<GetConvocations>(() => getConvocations);
    sl.registerFactory<RepondreConvocation>(() => _MockRepondre());
  });

  tearDown(desinscrire);

  const page = InspectionDetailPage(inspectionId: 'i1');

  const visiteNue = Inspection(id: 'i1', chantierId: 'c1');

  testWidgets('un indicateur pendant le chargement', (tester) async {
    final attente = Completer<Either<Failure, Inspection>>();
    when(() => getInspection(any())).thenAnswer((_) => attente.future);

    await pomperPage(tester, page);

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(tester.takeException(), isNull);

    attente.complete(const Right(visiteNue));
    await tester.pumpAndSettle();
  });

  testWidgets('visite introuvable : une erreur explicite', (tester) async {
    when(() => getInspection(any())).thenAnswer(
      (_) async => const Left<Failure, Inspection>(
        ServerFailure(errorMessage: 'Inspection introuvable', statusCode: 404),
      ),
    );

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('visite SANS checklist : la fiche tient, sans avancement bancal',
      (tester) async {
    when(() => getInspection(any()))
        .thenAnswer((_) async => const Right<Failure, Inspection>(visiteNue));

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.byType(ErrorView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('les convocations en panne n’emportent pas la checklist',
      (tester) async {
    // Les convocations ne sont pas le sujet de l'écran. Leur échec ne doit
    // pas retirer la checklist, seule chose qu'on vient faire ici.
    when(() => getInspection(any())).thenAnswer(
      (_) async => Right<Failure, Inspection>(
        Inspection(
          id: 'i1',
          chantierId: 'c1',
          dateVisite: DateTime(2026, 5, 20),
          checklist: const [
            LigneChecklist(id: 'l1', libelle: 'Etancheite toiture'),
            LigneChecklist(id: 'l2', libelle: 'Garde-corps', coche: true),
          ],
        ),
      ),
    );
    when(() => getConvocations(any())).thenAnswer(
      (_) async => const Left<Failure, List<Convocation>>(
        ServerFailure(errorMessage: 'Indisponible'),
      ),
    );

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.textContaining('Etancheite toiture'), findsOneWidget);
    expect(find.textContaining('Garde-corps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
