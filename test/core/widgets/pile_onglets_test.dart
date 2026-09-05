import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/widgets/pile_onglets.dart';

/// Tests — conservation de l'état des onglets.
///
/// Le défaut corrigé : chaque changement d'onglet recréait le sous-arbre, donc
/// relançait `..charger()` des cubits et perdait défilement et filtres. Un
/// aller-retour Accueil → Réserves → Accueil valait trois appels réseau.
///
/// Ce qui doit être verrouillé :
///   1. l'état d'un onglet SURVIT à un aller-retour ;
///   2. les branches invisibles ne sont pas construites à chaque frame ;
///   3. l'animation d'entrée est toujours jouée — le correctif ne devait pas
///      coûter le fondu qui marque le changement ;
///   4. la branche sortante reste visible pendant l'animation, sans quoi
///      l'écran virerait au blanc.
void main() {
  Widget pile(int index, List<Widget> enfants) => MaterialApp(
        home: PileOnglets(index: index, enfants: enfants),
      );

  testWidgets('l’état d’un onglet survit à un aller-retour', (tester) async {
    var creations = 0;
    final enfants = [
      _Ecran(nom: 'accueil', surCreation: () => creations++),
      const _Ecran(nom: 'reserves'),
    ];

    await tester.pumpWidget(pile(0, enfants));
    expect(creations, 1);

    // On modifie l'état local de l'onglet Accueil (équivalent d'un
    // défilement, d'un filtre saisi, d'une liste chargée).
    await tester.tap(find.text('accueil : 0'));
    await tester.pump();
    expect(find.text('accueil : 1'), findsOneWidget);

    // Aller sur Réserves, puis revenir.
    await tester.pumpWidget(pile(1, enfants));
    await tester.pumpAndSettle();
    await tester.pumpWidget(pile(0, enfants));
    await tester.pumpAndSettle();

    // Sans le correctif : `creations` vaudrait 2 et le compteur serait revenu
    // à 0 — l'écran aurait été reconstruit, et son cubit rechargé.
    expect(creations, 1, reason: 'l’onglet ne doit PAS être recréé');
    expect(find.text('accueil : 1'), findsOneWidget, reason: 'l’état est conservé');
  });

  testWidgets('les onglets invisibles restent montés mais hors scène', (tester) async {
    await tester.pumpWidget(pile(0, const [
      _Ecran(nom: 'accueil'),
      _Ecran(nom: 'reserves'),
    ]));
    await tester.pumpAndSettle();

    // Monté (donc trouvable dans l'arbre)…
    expect(find.text('reserves : 0', skipOffstage: false), findsOneWidget);
    // …mais bien hors scène : invisible à l'utilisateur.
    expect(find.text('reserves : 0'), findsNothing);
  });

  testWidgets('l’animation d’entrée est jouée', (tester) async {
    final enfants = [const _Ecran(nom: 'accueil'), const _Ecran(nom: 'reserves')];

    await tester.pumpWidget(pile(0, enfants));
    await tester.pumpAndSettle();

    await tester.pumpWidget(pile(1, enfants));
    await tester.pump(); // démarre l'animation
    await tester.pump(const Duration(milliseconds: 60));

    final opacite = tester.widget<FadeTransition>(
      find.ancestor(
        of: find.text('reserves : 0'),
        matching: find.byType(FadeTransition),
      ).first,
    );
    // À mi-parcours : ni invisible, ni déjà opaque.
    expect(opacite.opacity.value, greaterThan(0.0));
    expect(opacite.opacity.value, lessThan(1.0));

    await tester.pumpAndSettle();
    expect(opacite.opacity.value, 1.0);
  });

  testWidgets('l’onglet sortant reste visible pendant l’animation', (tester) async {
    final enfants = [const _Ecran(nom: 'accueil'), const _Ecran(nom: 'reserves')];

    await tester.pumpWidget(pile(0, enfants));
    await tester.pumpAndSettle();

    await tester.pumpWidget(pile(1, enfants));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // Sans cela, l'écran virerait au blanc le temps du fondu.
    expect(find.text('accueil : 0'), findsOneWidget);

    await tester.pumpAndSettle();
    // Une fois l'entrant opaque, le sortant repasse hors scène.
    expect(find.text('accueil : 0'), findsNothing);
  });
}

/// Écran de test : compte ses créations et porte un état local.
class _Ecran extends StatefulWidget {
  final String nom;
  final VoidCallback? surCreation;

  const _Ecran({required this.nom, this.surCreation});

  @override
  State<_Ecran> createState() => _EcranState();
}

class _EcranState extends State<_Ecran> {
  int _compteur = 0;

  @override
  void initState() {
    super.initState();
    widget.surCreation?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Center(
        child: GestureDetector(
          onTap: () => setState(() => _compteur++),
          child: Text('${widget.nom} : $_compteur'),
        ),
      ),
    );
  }
}
