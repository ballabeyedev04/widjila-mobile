import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/error_view.dart';
import 'package:suivie_chantier_mobile/core/widgets/loading_list.dart';
import 'package:suivie_chantier_mobile/features/inspection/domain/entities/inspection.dart';
import 'package:suivie_chantier_mobile/features/inspection/domain/usecases/inspection_usecases.dart';
import 'package:suivie_chantier_mobile/features/inspection/presentation/pages/inspections_list_page.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/balayage_responsive.dart';
import '../../../../helpers/pompe_page.dart';

class _MockGetInspections extends Mock implements GetInspections {}

class _MockCreer extends Mock implements CreerInspection {}

/// L'écran Inspections, dans ses quatre situations.
///
/// Voir `rapports_list_page_test.dart` pour le raisonnement complet : la page
/// résout ses cas d'usage dans `sl` au moment du `build`, et une liste vide
/// n'est pas une panne.
void main() {
  late _MockGetInspections getInspections;

  Inspection inspection(String id) => Inspection(
        id: id,
        chantierId: 'c1',
        dateVisite: DateTime(2026, 5, 20),
      );

  setUp(() {
    getInspections = _MockGetInspections();
    if (sl.isRegistered<GetInspections>()) sl.unregister<GetInspections>();
    if (sl.isRegistered<CreerInspection>()) sl.unregister<CreerInspection>();
    sl.registerFactory<GetInspections>(() => getInspections);
    sl.registerFactory<CreerInspection>(() => _MockCreer());
  });

  tearDown(() {
    if (sl.isRegistered<GetInspections>()) sl.unregister<GetInspections>();
    if (sl.isRegistered<CreerInspection>()) sl.unregister<CreerInspection>();
  });

  const page = InspectionsListPage(chantierId: 'c1', chantierNom: 'Les Cèdres');

  testWidgets('un squelette pendant le chargement', (tester) async {
    final attente = Completer<Either<Failure, List<Inspection>>>();
    when(() => getInspections(chantierId: any(named: 'chantierId'), statut: any(named: 'statut')))
        .thenAnswer((_) => attente.future);

    await pomperPage(tester, page);

    expect(find.byType(LoadingList), findsOneWidget);
    expect(tester.takeException(), isNull);

    attente.complete(const Right([]));
    await tester.pumpAndSettle();
  });

  testWidgets('liste vide : un message qui dit quoi faire', (tester) async {
    when(() => getInspections(chantierId: any(named: 'chantierId'), statut: any(named: 'statut')))
        .thenAnswer((_) async => const Right<Failure, List<Inspection>>([]));

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.text('Aucune inspection'), findsOneWidget);
    expect(find.textContaining('Planifiez une visite'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('panne serveur : une erreur, et de quoi réessayer', (tester) async {
    when(() => getInspections(chantierId: any(named: 'chantierId'), statut: any(named: 'statut')))
        .thenAnswer((_) async =>
            const Left<Failure, List<Inspection>>(ServerFailure(errorMessage: 'Service indisponible')));

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.text('Aucune inspection'), findsNothing);
    expect(find.byType(ErrorView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('affiche les inspections reçues', (tester) async {
    when(() => getInspections(chantierId: any(named: 'chantierId'), statut: any(named: 'statut')))
        .thenAnswer((_) async =>
            Right<Failure, List<Inspection>>([inspection('i1'), inspection('i2')]));

    await pomperPage(tester, page);
    await tester.pumpAndSettle();

    expect(find.text('Aucune inspection'), findsNothing);
    expect(find.byType(ErrorView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('mise en page — balayage des formats', () {
    // Un ecran dessine sur un telephone de 390 dp passe presque toujours a
    // 390 dp. Les debordements se produisent aux EXTREMES : sur un petit
    // Android de 320 dp encore courant sur les chantiers, et sur une tablette
    // ou une rangee concue serree se distend.
    //
    // `flutter_test` remonte un `RenderFlex overflowed` comme une exception :
    // pomper l'ecran a chaque format et verifier qu'aucune n'a ete levee
    // transforme l'audit visuel en mesure repetable.
    for (final format in tousLesFormats) {
      testWidgets('sans debordement sur $format', (tester) async {
        when(() => getInspections(
              chantierId: any(named: 'chantierId'),
              statut: any(named: 'statut'),
            )).thenAnswer((_) async =>
            Right<Failure, List<Inspection>>([inspection('i1'), inspection('i2')]));

        await pomperPage(tester, page, taille: format.taille);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'debordement de mise en page sur $format');
      });
    }
  });
}
