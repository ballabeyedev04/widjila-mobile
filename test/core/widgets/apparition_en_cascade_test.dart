import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/widgets/apparition_en_cascade.dart';

/// Apparition échelonnée des éléments de liste.
///
/// Trois choses doivent tenir, et ce sont exactement les trois qui ratent
/// quand on écrit ce genre d'animation à la main :
///
///   1. l'élément finit VISIBLE et à sa place. Une animation qui s'arrête à
///      mi-course, ou qui laisse un décalage résiduel, produit une liste
///      définitivement de travers — le pire résultat possible, puisqu'il ne
///      ressemble pas à un bug ;
///   2. le décalage est PLAFONNÉ. Sans cela, la vingtième ligne attendrait
///      près d'une seconde et une longue liste se remplirait au
///      compte-gouttes ;
///   3. une reconstruction ne relance PAS l'animation. Un changement de filtre
///      ou la mise à jour d'un statut ferait sinon clignoter toute la liste.
void main() {
  /// Opacité courante du fondu enveloppant [cle].
  double opacite(WidgetTester tester, Key cle) {
    final fondu = tester.widget<FadeTransition>(
      find.ancestor(of: find.byKey(cle), matching: find.byType(FadeTransition)).first,
    );
    return fondu.opacity.value;
  }

  Widget enveloppe(Widget enfant) => MaterialApp(home: Scaffold(body: enfant));

  testWidgets('l’élément part invisible et finit pleinement visible', (tester) async {
    const cle = Key('ligne');
    await tester.pumpWidget(enveloppe(
      const ApparitionEnCascade(rang: 0, child: SizedBox(key: cle, height: 40)),
    ));

    expect(opacite(tester, cle), 0.0, reason: 'sans quoi il n’y a pas d’apparition');

    await tester.pumpAndSettle();
    expect(opacite(tester, cle), 1.0);

    // Et remis à sa place : un décalage résiduel laisserait la liste de
    // travers pour toujours.
    final glissement = tester.widget<SlideTransition>(
      find.ancestor(of: find.byKey(cle), matching: find.byType(SlideTransition)).first,
    );
    expect(glissement.position.value, Offset.zero);
  });

  testWidgets('un rang plus élevé apparaît plus tard', (tester) async {
    await tester.pumpWidget(enveloppe(
      const Column(children: [
        ApparitionEnCascade(rang: 0, child: SizedBox(key: Key('a'), height: 20)),
        ApparitionEnCascade(rang: 3, child: SizedBox(key: Key('b'), height: 20)),
      ]),
    ));

    // 100 ms : le premier est bien engagé, le second attend encore son tour
    // (3 × 45 ms de palier).
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacite(tester, const Key('a')), greaterThan(opacite(tester, const Key('b'))));

    await tester.pumpAndSettle();
    expect(opacite(tester, const Key('a')), 1.0);
    expect(opacite(tester, const Key('b')), 1.0);
  });

  testWidgets('le décalage est plafonné — une longue liste ne traîne pas', (tester) async {
    // Rang 40 : sans plafond, l'attente serait de 1,8 s avant même de
    // commencer à apparaître.
    await tester.pumpWidget(enveloppe(
      const ApparitionEnCascade(rang: 40, child: SizedBox(key: Key('loin'), height: 20)),
    ));

    await tester.pump(const Duration(milliseconds: 700));
    expect(
      opacite(tester, const Key('loin')),
      1.0,
      reason: 'au-delà du plafond, toutes les lignes partent ensemble',
    );
  });

  testWidgets('une reconstruction ne relance pas l’animation', (tester) async {
    const cle = Key('ligne');

    Widget avec(String texte) => enveloppe(
          ApparitionEnCascade(rang: 0, child: Text(texte, key: cle)),
        );

    await tester.pumpWidget(avec('avant'));
    await tester.pumpAndSettle();
    expect(opacite(tester, cle), 1.0);

    // Même position, contenu différent : la ligne se reconstruit, elle
    // n'arrive pas.
    await tester.pumpWidget(avec('après'));
    await tester.pump();
    expect(
      opacite(tester, cle),
      1.0,
      reason: 'sinon toute la liste clignote au moindre changement de filtre',
    );
  });
}
