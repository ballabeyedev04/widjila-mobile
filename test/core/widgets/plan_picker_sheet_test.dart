import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/widgets/plan_picker_sheet.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_plans_chantier.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/get_tous_plans.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/usecases/uploader_plan.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/cubit/plans_list_cubit.dart';
import 'package:suivie_chantier_mobile/injection_container.dart';

import '../../helpers/l10n_test_helpers.dart';

class _MockPlansChantier extends Mock implements GetPlansChantier {}

class _MockTousPlans extends Mock implements GetTousPlans {}

class _MockUploader extends Mock implements UploaderPlan {}

Plan _plan(String id, String nom) => Plan(
      id: id,
      chantierId: 'c-1',
      nom: nom,
      fichierUrl: '/uploads/$id.pdf',
    );

/// Sélecteur de plan — deuxième étape du bouton « + ».
///
/// ## Pourquoi trois issues et non deux
///
/// Le parcours demandé est : chantier, puis plan, puis le formulaire de
/// réserve. Un sélecteur qui ne saurait dire que « ce plan » ou « rien »
/// enfermerait le premier utilisateur venu : sur un chantier dont les plans
/// ne sont pas encore déposés, la liste est vide et la seule sortie est la
/// croix — le parcours entier s'arrête là, sans réserve créée.
///
/// D'où la troisième issue, « continuer sans plan », et d'où ces tests : c'est
/// exactement la distinction qu'une simplification ultérieure ferait
/// disparaître.
void main() {
  late _MockPlansChantier plansChantier;

  setUp(() {
    plansChantier = _MockPlansChantier();
    if (sl.isRegistered<PlansListCubit>()) sl.unregister<PlansListCubit>();
    sl.registerFactory<PlansListCubit>(() => PlansListCubit(
          getTousPlans: _MockTousPlans(),
          getPlansChantier: plansChantier,
          uploaderPlan: _MockUploader(),
        ));
  });

  tearDown(() {
    if (sl.isRegistered<PlansListCubit>()) sl.unregister<PlansListCubit>();
  });

  Future<({Plan? plan})?> ouvrir(WidgetTester tester, List<Plan> plans) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    when(() => plansChantier(any())).thenAnswer(
      (_) async => Right<Failure, List<Plan>>(plans),
    );

    ({Plan? plan})? resultat;
    var appele = false;

    await tester.pumpWidget(MaterialApp(
      locale: testLocale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                resultat = await choisirPlan(context, chantierId: 'c-1', chantierNom: 'Résidence Les Almadies');
                appele = true;
              },
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(appele, isFalse, reason: 'la feuille est encore ouverte');
    return resultat;
  }

  testWidgets('liste les plans du chantier et rappelle son nom', (tester) async {
    await ouvrir(tester, [_plan('p1', 'Plan de masse'), _plan('p2', 'RDC')]);

    expect(find.text('Plan de masse'), findsOneWidget);
    expect(find.text('RDC'), findsOneWidget);
    // Le nom du chantier déjà choisi : sans lui, impossible de vérifier qu'on
    // ne s'est pas trompé à l'étape précédente.
    expect(find.text('Résidence Les Almadies'), findsOneWidget);
  });

  testWidgets('renvoie le plan choisi', (tester) async {
    ({Plan? plan})? resultat;

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    when(() => plansChantier(any())).thenAnswer(
      (_) async => Right<Failure, List<Plan>>([_plan('p1', 'Plan de masse'), _plan('p2', 'RDC')]),
    );

    await tester.pumpWidget(MaterialApp(
      locale: testLocale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => resultat = await choisirPlan(context, chantierId: 'c-1'),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RDC'));
    await tester.pumpAndSettle();

    expect(resultat, isNotNull);
    expect(resultat!.plan?.id, 'p2');
  });

  testWidgets('propose de continuer SANS plan quand le chantier n’en a aucun', (tester) async {
    await ouvrir(tester, const []);

    // Sans ce bouton, le parcours s'arrête ici : liste vide, et pour seule
    // sortie la croix.
    expect(find.text('Continuer sans plan'), findsOneWidget);
  });

  testWidgets('« continuer sans plan » se distingue d’un abandon', (tester) async {
    ({Plan? plan})? resultat;
    var termine = false;

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    when(() => plansChantier(any())).thenAnswer(
      (_) async => const Right<Failure, List<Plan>>([]),
    );

    await tester.pumpWidget(MaterialApp(
      locale: testLocale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                resultat = await choisirPlan(context, chantierId: 'c-1');
                termine = true;
              },
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuer sans plan'));
    await tester.pumpAndSettle();

    expect(termine, isTrue);
    // Un enregistrement, mais sans plan : l'appelant enchaîne sur le
    // formulaire. `null` aurait signifié « abandon » et tout arrêté.
    expect(resultat, isNotNull);
    expect(resultat!.plan, isNull);
  });

  testWidgets('la croix renvoie null — c’est un abandon', (tester) async {
    ({Plan? plan})? resultat;
    var termine = false;

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    when(() => plansChantier(any())).thenAnswer(
      (_) async => Right<Failure, List<Plan>>([_plan('p1', 'Plan de masse')]),
    );

    await tester.pumpWidget(MaterialApp(
      locale: testLocale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                resultat = await choisirPlan(context, chantierId: 'c-1');
                termine = true;
              },
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(termine, isTrue);
    expect(resultat, isNull);
  });
}
