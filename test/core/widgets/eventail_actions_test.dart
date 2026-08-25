import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/widgets/eventail_actions.dart';

/// Régression : les pastilles de l'éventail doivent être CLIQUABLES.
///
/// Elles étaient auparavant peintes hors des limites de leur parent (une bande
/// d'ancrage de 1 px, `Clip.none`). Visibles, donc, mais injoignables :
/// `RenderBox.hitTest` abandonne dès que la position sort de `size`. Chaque tap
/// traversait jusqu'à la barrière de fermeture et le menu se refermait sans
/// rien faire.
///
/// Ces tests passent par `tester.tap`, qui vise le centre réel du widget à
/// l'écran et rejoue le vrai parcours de hit-test : ils échouent donc si la
/// régression revient.
void main() {
  ActionRapide action(String label) => (
        icon: Icons.circle,
        label: label,
        couleur: const Color(0xFFF2600C),
        besoinChantier: true,
        dansCoquille: false,
        route: (String? id) => '/chantiers/$id',
      );

  late List<ActionRapide> choisies;
  late int fermetures;

  Widget eventail(List<ActionRapide> actions, {double ancrageX = 0, List<double>? angles}) {
    choisies = [];
    fermetures = 0;
    return MaterialApp(
      home: Scaffold(
        body: EventailActions(
          // Éventail totalement déployé : c'est l'état dans lequel
          // l'utilisateur clique.
          animation: const AlwaysStoppedAnimation<double>(1),
          actions: actions,
          distanceBas: 58,
          ancrageX: ancrageX,
          angles: angles,
          onChoix: choisies.add,
          onFermeture: () => fermetures++,
        ),
      ),
    );
  }

  testWidgets('chaque pastille de l’éventail répond au tap', (tester) async {
    final actions = [
      action('Tableau de bord chantier'),
      action('Équipe'),
      action('Document'),
    ];
    await tester.pumpWidget(eventail(actions));

    for (final attendue in actions) {
      await tester.tap(find.text(attendue.label));
      await tester.pump();
    }

    expect(choisies.map((a) => a.label).toList(),
        ['Tableau de bord chantier', 'Équipe', 'Document']);
    // Aucun tap ne doit avoir traversé jusqu'à la barrière : c'était
    // exactement le symptôme du bug.
    expect(fermetures, 0);
  });

  testWidgets('le tap atteint aussi le disque, pas seulement l’étiquette', (tester) async {
    await tester.pumpWidget(eventail([action('Document')]));

    await tester.tap(find.byIcon(Icons.circle));
    await tester.pump();

    expect(choisies, hasLength(1));
    expect(fermetures, 0);
  });

  testWidgets('un tap sur le fond referme sans rien choisir', (tester) async {
    await tester.pumpWidget(eventail([action('Document')]));

    // Coin haut-gauche : loin de l'arc, donc sur la barrière.
    await tester.tapAt(const Offset(12, 12));
    await tester.pump();

    expect(choisies, isEmpty);
    expect(fermetures, 1);
  });

  testWidgets('un libellé long reste dans les limites de l’écran', (tester) async {
    // Gabarit d'un téléphone étroit : les 800 px par défaut du banc de test
    // masqueraient tout débordement.
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(eventail([
      action('Tableau de bord chantier'),
      action('Équipe'),
      action('Document'),
    ]));

    final largeurEcran = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    for (final label in ['Tableau de bord chantier', 'Équipe', 'Document']) {
      final boite = tester.getRect(find.text(label));
      expect(boite.left, greaterThanOrEqualTo(0), reason: '$label déborde à gauche');
      expect(boite.right, lessThanOrEqualTo(largeurEcran), reason: '$label déborde à droite');
    }
  });

  group('menu de l’onglet Plus (ancré à droite)', () {
    // L'onglet « Plus » est collé au bord droit de la barre : son éventail
    // part de SON bouton, pas du centre. Un arc symétrique enverrait la moitié
    // des pastilles hors de l'écran, où elles seraient injoignables.
    const anglesPlus = [150.0, 100.0];

    Future<void> poserMenu(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(eventail(
        [action('Chantiers'), action('Intervenants')],
        // Centre de l'onglet Plus sur un écran de 390 : ~156 px à droite du
        // milieu.
        ancrageX: 156,
        angles: anglesPlus,
      ));
    }

    testWidgets('les deux entrées restent dans l’écran', (tester) async {
      await poserMenu(tester);

      for (final label in ['Chantiers', 'Intervenants']) {
        final boite = tester.getRect(find.text(label));
        expect(boite.left, greaterThanOrEqualTo(0), reason: '$label déborde à gauche');
        expect(boite.right, lessThanOrEqualTo(390), reason: '$label déborde à droite');
      }
    });

    testWidgets('et restent cliquables', (tester) async {
      await poserMenu(tester);

      await tester.tap(find.text('Chantiers'));
      await tester.tap(find.text('Intervenants'));
      await tester.pump();

      expect(choisies.map((a) => a.label).toList(), ['Chantiers', 'Intervenants']);
      expect(fermetures, 0);
    });

    testWidgets('l’éventail part bien de la droite, pas du centre', (tester) async {
      await poserMenu(tester);

      // Sans prise en compte de l'ancrage, les pastilles se seraient
      // regroupées autour du milieu (195 px).
      final centres = ['Chantiers', 'Intervenants']
          .map((l) => tester.getCenter(find.text(l)).dx)
          .toList();
      expect(centres.every((x) => x > 195), isTrue,
          reason: 'les pastilles doivent se trouver à droite du centre');
    });
  });
}
