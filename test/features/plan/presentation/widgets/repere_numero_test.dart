import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/widgets/plan_interactif.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/l10n/generated/app_localizations.dart';

/// Le NUMÉRO des réserves sur le plan.
///
/// Plusieurs repères rouges ne disent pas laquelle des réserves a été relevée
/// en premier ni laquelle est « la 3 ». Chaque repère porte donc, dans une
/// petite pastille accrochée à la goutte, le numéro que le serveur a attribué
/// à la réserve SUR CE PLAN — la goutte rouge reste, le numéro s'y ajoute.
///
/// Ce que ces tests verrouillent :
///   - le numéro vient du serveur (`numeroPlan`), jamais d'un calcul local ;
///   - il s'affiche sur le repère, et pas sans numéro (point provisoire,
///     réserve créée hors ligne pas encore numérotée) ;
///   - appuyer sur un repère numéroté ouvre LA réserve de ce numéro, pastille
///     comprise ;
///   - la goutte reste ancrée par sa pointe au point enregistré, pastille ou
///     pas ;
///   - le numéro suit le zoom et le déplacement du plan ;
///   - un changement de statut change la couleur, pas le numéro.

/// Une image PNG valide de 1×1 — assez pour que Flutter la décode vraiment.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  Future<void> monter(
    WidgetTester tester, {
    List<MarqueurPlan> marqueurs = const [],
    void Function(MarqueurPlan)? onMarqueur,
    Size ecran = const Size(400, 800),
  }) async {
    tester.view.physicalSize = ecran;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final arbre = MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('fr'),
      home: Scaffold(
        body: PlanInteractif(
          octets: _png,
          marqueurs: marqueurs,
          onMarqueurAppuye: onMarqueur,
        ),
      ),
    );

    // Le décodage de l'image est un vrai travail asynchrone : voir
    // `plan_interactif_test.dart` pour le pourquoi de `runAsync`.
    await tester.runAsync(() async {
      await tester.pumpWidget(arbre);
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pump();
  }

  group('le numéro vient du serveur', () {
    test('`numeroPlan` est lu dans la réponse du détail du plan', () {
      final r = PlanReserve.fromJson({
        'id': 'r1',
        'numero': 'R-0031',
        'numeroPlan': 3,
        'titre': 'Fissure',
        'statut': 'creee',
        'severite': 'moyenne',
        'position': {'x': 40, 'y': 60},
      });
      expect(r.numeroPlan, 3);
      expect(r.numero, 'R-0031', reason: 'le numéro de chantier reste distinct');
    });

    test('absent de la réponse → nul, jamais inventé', () {
      // Une réserve hors plan, ou créée hors ligne et pas encore numérotée :
      // rien à afficher, plutôt qu'un numéro faux dès la synchronisation.
      final r = PlanReserve.fromJson({
        'id': 'r1', 'numero': 'R-0031', 'titre': 'Fissure', 'statut': 'creee', 'severite': 'moyenne',
      });
      expect(r.numeroPlan, isNull);
    });

    test('la fiche complète le lit, le resérialise et le garde à travers une copie', () {
      final r = Reserve.fromJson({
        'id': 'r1', 'numero': 'R-0031', 'numeroPlan': 7, 'chantierId': 'c', 'titre': 'Fissure',
      });
      expect(r.numeroPlan, 7);
      expect(r.toJson()['numeroPlan'], 7, reason: 'le cache hors ligne doit le conserver');

      // Changer de statut ou de titre ne touche pas au numéro.
      expect(r.copierAvecStatut(ReserveStatut.enCours).numeroPlan, 7);
      expect(r.copierAvec(titre: 'Autre').numeroPlan, 7);
    });

    test('un entier servi en décimal ou en texte JSON ne casse rien', () {
      expect(PlanReserve.fromJson({'id': 'r', 'statut': 'creee', 'severite': 'moyenne', 'numeroPlan': 3.0}).numeroPlan, 3);
      expect(PlanReserve.fromJson({'id': 'r', 'statut': 'creee', 'severite': 'moyenne', 'numeroPlan': null}).numeroPlan, isNull);
    });
  });

  group('la pastille sur le repère', () {
    testWidgets('affiche le numéro de chaque réserve, la goutte restant présente', (tester) async {
      await monter(tester, marqueurs: const [
        MarqueurPlan(id: 'a', x: 30, y: 30, couleur: Colors.red, numero: 1),
        MarqueurPlan(id: 'b', x: 60, y: 40, couleur: Colors.red, numero: 2),
        MarqueurPlan(id: 'c', x: 50, y: 70, couleur: Colors.red, numero: 3),
      ]);

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      // La goutte rouge n'est pas remplacée : une épingle par réserve.
      expect(find.byIcon(Icons.place_rounded), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ne dessine PAS de pastille sans numéro', (tester) async {
      // Le point provisoire et une réserve créée hors ligne (pas encore
      // numérotée par le serveur) gardent la goutte seule.
      await monter(tester, marqueurs: const [
        MarqueurPlan(id: 'provisoire', x: 50, y: 50, actif: true),
      ]);

      expect(find.byIcon(Icons.place_rounded), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('annonce « Réserve n°3 » à l’accessibilité', (tester) async {
      final semantique = tester.ensureSemantics();
      await monter(tester, marqueurs: const [
        MarqueurPlan(id: 'c', x: 50, y: 50, couleur: Colors.red, numero: 3),
      ]);
      expect(find.bySemanticsLabel(RegExp('Réserve n°3')), findsOneWidget);
      semantique.dispose();
    });

    testWidgets('la POINTE de la goutte reste sur le point enregistré, pastille ou pas', (tester) async {
      // La pastille élargit la boîte du repère : elle ne doit pas décaler la
      // goutte, dont la pointe désigne le défaut.
      await monter(tester, marqueurs: const [
        MarqueurPlan(id: 'sans', x: 50, y: 50),
        MarqueurPlan(id: 'avec', x: 50, y: 50, numero: 12),
      ]);

      final gouttes = find.byIcon(Icons.place_rounded);
      expect(gouttes, findsNWidgets(2));
      final sans = tester.getRect(gouttes.at(0));
      final avec = tester.getRect(gouttes.at(1));
      expect(avec.center.dx, closeTo(sans.center.dx, 0.01));
      expect(avec.bottom, closeTo(sans.bottom, 0.01));

      // Et la pointe tombe bien à 50 % / 50 % de l'image.
      final image = tester.getRect(find.byType(Image).first);
      final pointe = tester.getRect(find.byType(GestureDetector).last).bottomCenter;
      expect(pointe.dx, closeTo(image.center.dx, 1));
      expect(pointe.dy, closeTo(image.center.dy, 1));
    });

    testWidgets('un numéro à trois chiffres reste entier', (tester) async {
      await monter(tester, marqueurs: const [
        MarqueurPlan(id: 'x', x: 50, y: 50, numero: 124),
      ]);
      expect(find.text('124'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'pas de débordement');
    });
  });

  group('l’appui sur un repère numéroté', () {
    testWidgets('ouvre LA réserve de ce numéro', (tester) async {
      MarqueurPlan? appuye;
      await monter(
        tester,
        marqueurs: const [
          MarqueurPlan(id: 'r1', x: 25, y: 25, numero: 1),
          MarqueurPlan(id: 'r3', x: 75, y: 75, numero: 3),
        ],
        onMarqueur: (m) => appuye = m,
      );

      await tester.tap(find.text('3'));
      await tester.pump();

      expect(appuye?.id, 'r3');
      expect(appuye?.numero, 3);
    });

    testWidgets('sur la pastille comme sur la goutte', (tester) async {
      // La pastille chevauche la goutte : un appui dessus doit compter.
      MarqueurPlan? appuye;
      await monter(
        tester,
        marqueurs: const [MarqueurPlan(id: 'r2', x: 50, y: 50, numero: 2)],
        onMarqueur: (m) => appuye = m,
      );

      await tester.tap(find.byIcon(Icons.place_rounded));
      await tester.pump();
      expect(appuye?.id, 'r2');

      appuye = null;
      await tester.tap(find.text('2'));
      await tester.pump();
      expect(appuye?.id, 'r2');
    });
  });

  group('zoom, déplacement, tailles d’écran', () {
    testWidgets('le numéro suit le plan quand on zoome et qu’on le déplace', (tester) async {
      await monter(tester, marqueurs: const [
        MarqueurPlan(id: 'r1', x: 50, y: 50, numero: 1),
      ]);

      final avantGoutte = tester.getCenter(find.byIcon(Icons.place_rounded));
      final avantNumero = tester.getCenter(find.text('1'));
      final decalage = avantNumero - avantGoutte;

      // Pincement pour zoomer ×2 autour du centre, puis glissement.
      final viewer = find.byType(InteractiveViewer);
      final centre = tester.getCenter(viewer);
      final g1 = await tester.startGesture(centre - const Offset(20, 0));
      final g2 = await tester.startGesture(centre + const Offset(20, 0));
      await tester.pump();
      await g1.moveTo(centre - const Offset(60, 0));
      await g2.moveTo(centre + const Offset(60, 0));
      await tester.pump();
      await g1.up();
      await g2.up();
      await tester.pump();

      await tester.drag(viewer, const Offset(-40, 30));
      await tester.pumpAndSettle();

      final apresGoutte = tester.getCenter(find.byIcon(Icons.place_rounded));
      final apresNumero = tester.getCenter(find.text('1'));

      // Le repère a bougé avec le plan…
      expect(apresGoutte, isNot(equals(avantGoutte)));
      // …et la pastille est restée accrochée à la goutte : même direction, à
      // l'échelle du zoom (elle vit dans le même conteneur transformé).
      final nouveauDecalage = apresNumero - apresGoutte;
      expect(nouveauDecalage.dx.sign, decalage.dx.sign);
      expect(nouveauDecalage.dy.sign, decalage.dy.sign);
      expect(nouveauDecalage.distance, greaterThanOrEqualTo(decalage.distance - 0.01));
      expect(find.text('1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('téléphone étroit et tablette : le numéro reste dessiné au bon endroit', (tester) async {
      for (final ecran in const [Size(360, 640), Size(1024, 1366)]) {
        await monter(
          tester,
          ecran: ecran,
          marqueurs: const [MarqueurPlan(id: 'r5', x: 80, y: 20, numero: 5)],
        );

        final image = tester.getRect(find.byType(Image).first);
        final pointe = tester.getRect(find.byType(GestureDetector).last).bottomCenter;
        expect(pointe.dx, closeTo(image.left + image.width * 0.8, 1), reason: '$ecran');
        expect(pointe.dy, closeTo(image.top + image.height * 0.2, 1), reason: '$ecran');
        expect(find.text('5'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('statut et numéro', () {
    testWidgets('changer la couleur du statut ne change pas le numéro', (tester) async {
      await monter(tester, marqueurs: const [
        MarqueurPlan(id: 'r3', x: 50, y: 50, couleur: Colors.red, numero: 3),
      ]);
      expect(find.text('3'), findsOneWidget);

      // La même réserve, passée « traitée » : autre couleur, même 3.
      await monter(tester, marqueurs: const [
        MarqueurPlan(id: 'r3', x: 50, y: 50, couleur: Colors.green, numero: 3),
      ]);
      expect(find.text('3'), findsOneWidget);
      final goutte = tester.widget<Container>(
        find.ancestor(of: find.byIcon(Icons.place_rounded), matching: find.byType(Container)).first,
      );
      expect((goutte.decoration! as BoxDecoration).color, Colors.green);
    });
  });
}
