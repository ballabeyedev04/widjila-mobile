import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/features/dashboard/presentation/widgets/derniers_plans.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_plans_chantier.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_tous_plans.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/uploader_plan.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/cubit/plans_list_cubit.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../../../helpers/l10n_test_helpers.dart';

class _MockGetTousPlans extends Mock implements GetTousPlans {}

class _MockGetPlansChantier extends Mock implements GetPlansChantier {}

class _MockUploaderPlan extends Mock implements UploaderPlan {}

/// Rendu réel de la bande « Derniers plans » du tableau de bord.
///
/// Écrit en réponse à un écran observé : sur un compte neuf, la section
/// n'apparaissait NULLE PART entre « Vue d'ensemble » et « Aperçu général ».
/// Elle était pourtant bien branchée — elle se repliait simplement sur du vide
/// quand il n'y avait aucun plan, ce qui la rendait indiscernable d'une
/// section oubliée.
///
/// Ces tests fixent ce que la bande DOIT montrer dans chacun des trois états.
void main() {
  late _MockGetTousPlans getTousPlans;

  setUp(() {
    getTousPlans = _MockGetTousPlans();

    // Le widget résout son cubit par le conteneur d'injection : on l'y
    // enregistre le temps du test, plutôt que d'ouvrir une porte de test dans
    // le widget lui-même.
    sl.registerFactory<PlansListCubit>(() => PlansListCubit(
          getTousPlans: getTousPlans,
          getPlansChantier: _MockGetPlansChantier(),
          uploaderPlan: _MockUploaderPlan(),
        ));
  });

  tearDown(() => sl.reset());

  Plan plan(String nom, {DateTime? cree}) => Plan(
        id: 'p-$nom',
        chantierId: 'c1',
        nom: nom,
        fichierUrl: 'https://exemple.test/$nom.pdf',
        chantierNom: 'Résidence Les Filaos',
        createdAt: cree,
      );

  Future<void> pomper(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: testLocale,
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: const Scaffold(body: SingleChildScrollView(child: DerniersPlans())),
      ),
    );
    // Deux passes : la première monte le widget, la seconde laisse le cubit
    // émettre sa réponse.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('affiche le titre ET un message quand aucun plan n’existe', (tester) async {
    // C'est le cas qui a fait croire à un oubli. La section doit garder sa
    // place, avec un message qui dit pourquoi elle est vide.
    when(() => getTousPlans())
        .thenAnswer((_) async => const Right(<Plan>[]));

    await pomper(tester);

    expect(find.text('Derniers plans'), findsOneWidget);
    expect(find.text('Aucun plan pour le moment'), findsOneWidget);
  });

  testWidgets('ne montre aucune flèche sur une bande vide', (tester) async {
    // Deux boutons inertes feraient chercher un contenu qui n'existe pas.
    when(() => getTousPlans())
        .thenAnswer((_) async => const Right(<Plan>[]));

    await pomper(tester);

    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
  });

  testWidgets('affiche les plans, leur chantier et leur date', (tester) async {
    when(() => getTousPlans()).thenAnswer(
      (_) async => Right([plan('Niveau R+1', cree: DateTime(2026, 8, 30))]),
    );

    await pomper(tester);

    expect(find.text('Niveau R+1'), findsOneWidget);
    expect(find.text('Résidence Les Filaos'), findsOneWidget);
    // La date distingue la dernière version de l'avant-dernière quand les
    // noms se ressemblent.
    expect(find.textContaining('2026'), findsOneWidget);
    expect(find.text('Aucun plan pour le moment'), findsNothing);
  });

  testWidgets('n’affiche pas « aucun plan » quand le chargement a échoué', (tester) async {
    // On ignore alors s'il existe des plans : l'affirmer serait faux.
    when(() => getTousPlans())
        .thenAnswer((_) async => const Left(NetworkFailure()));

    await pomper(tester);

    expect(find.text('Aucun plan pour le moment'), findsNothing);
    expect(find.text('Derniers plans'), findsNothing);
  });

  testWidgets('n’affiche que huit plans au maximum', (tester) async {
    when(() => getTousPlans()).thenAnswer(
      (_) async => Right([
        for (var i = 0; i < 12; i++)
          plan('Plan $i', cree: DateTime(2026, 1, 1).add(Duration(days: i))),
      ]),
    );

    await pomper(tester);

    // Le plus récent est présent, le neuvième en partant du haut ne l'est pas.
    expect(find.text('Plan 11'), findsOneWidget);
    expect(find.text('Plan 3'), findsNothing);
  });
}
