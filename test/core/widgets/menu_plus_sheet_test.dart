import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/widgets/action_rapide.dart';
import 'package:suivie_chantier_mobile/core/widgets/menu_plus_sheet.dart';

import '../../helpers/l10n_test_helpers.dart';

ActionRapide _entree(String label) => (
      icon: Icons.circle,
      label: label,
      couleur: const Color(0xFFF2600C),
      besoinChantier: false,
      avecCreation: false,
      dansCoquille: true,
      route: (String? _) => '/x',
    );

/// Menu de l'onglet « Plus ».
///
/// ## Pourquoi il a remplacé l'éventail en arc
///
/// Les entrées se déployaient sur un arc de cercle autour du bouton. Lisible
/// jusqu'à trois ou quatre ; au-delà les pastilles se chevauchaient et les
/// branches basses sortaient de l'écran. Le menu en compte désormais jusqu'à
/// sept — « Tableau de bord chantier » et « Envoi de plans » ont quitté le
/// bouton « + » central pour le rejoindre.
///
/// Ce test verrouille la propriété qui manquait à l'arc : le menu affiche
/// TOUTES ses entrées, quel qu'en soit le nombre, y compris sur l'écran le
/// plus étroit.
void main() {
  Future<ActionRapide?> ouvrir(
    WidgetTester tester,
    List<ActionRapide> entrees, {
    double largeur = 390,
  }) async {
    tester.view.physicalSize = Size(largeur, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    ActionRapide? resultat;
    await tester.pumpWidget(MaterialApp(
      locale: testLocale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => resultat = await ouvrirMenuPlus(context, entrees),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    return resultat;
  }

  testWidgets('affiche les sept entrées sur un écran étroit, sans exception', (tester) async {
    final erreurs = <FlutterErrorDetails>[];
    final precedent = FlutterError.onError;
    FlutterError.onError = erreurs.add;

    final entrees = [
      _entree('Tableau de bord chantier'),
      _entree('Envoi de plans'),
      _entree('Équipe'),
      _entree('Chantiers'),
      _entree('Document'),
      _entree('Suivi des demandes'),
      _entree('Intervenants'),
    ];

    await ouvrir(tester, entrees, largeur: 320);
    FlutterError.onError = precedent;

    expect(erreurs.map((e) => e.exceptionAsString()).toList(), isEmpty);
    for (final e in entrees) {
      expect(find.text(e.label), findsOneWidget, reason: e.label);
    }
  });

  testWidgets('renvoie l’entrée choisie et se referme', (tester) async {
    final entrees = [_entree('Équipe'), _entree('Chantiers')];

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    ActionRapide? resultat;
    await tester.pumpWidget(MaterialApp(
      locale: testLocale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => resultat = await ouvrirMenuPlus(context, entrees),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chantiers'));
    await tester.pumpAndSettle();

    expect(resultat?.label, 'Chantiers');
    expect(find.text('Équipe'), findsNothing, reason: 'la feuille doit s’être refermée');
  });

  testWidgets('renvoie null quand on referme sans choisir', (tester) async {
    // Distinguer « rien choisi » de « choisi » n'est pas cosmétique : la
    // coquille enchaîne sur un sélecteur de chantier après un choix. Confondre
    // les deux ouvrirait un sélecteur à qui referme le menu.
    final resultat = await ouvrir(tester, [_entree('Équipe')]);
    expect(resultat, isNull);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Équipe'), findsNothing);
  });
}
