import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/widgets/apercu_plan_reserve.dart';

import '../../../../helpers/l10n_test_helpers.dart';

/// L'aperçu du plan sur la fiche d'une réserve.
///
/// Ce qui compte ici n'est pas qu'une image s'affiche : c'est que le repère
/// tombe EXACTEMENT sur le point relevé. Un repère décalé de quelques pixels
/// sur un plan d'appartement désigne la mauvaise cloison.
void main() {
  const repere = ValueKey('repere-reserve');
  const image = ValueKey('apercu-plan-image');

  /// Un plan de test PAYSAGE (2:1) : un plan carré ne verrait pas une
  /// inversion largeur/hauteur.
  Future<Uint8List> png(int largeur, int hauteur) async {
    final enregistreur = ui.PictureRecorder();
    Canvas(enregistreur).drawRect(
      Rect.fromLTWH(0, 0, largeur.toDouble(), hauteur.toDouble()),
      Paint()..color = Colors.white,
    );
    final img = await enregistreur.endRecording().toImage(largeur, hauteur);
    final donnees = await img.toByteData(format: ui.ImageByteFormat.png);
    return donnees!.buffer.asUint8List();
  }

  ReservePlanRef plan(String fichier) =>
      ReservePlanRef(id: 'p1', nom: 'arkada_13_2np3.jpg', version: 3, fichierUrl: '/uploads/$fichier');

  Widget hote(Widget enfant) => MaterialApp(
        locale: testLocale,
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: enfant)),
      );

  /// Monte l'aperçu et laisse le décodage de l'image aboutir — il se fait
  /// hors de l'horloge simulée des tests.
  Future<void> monter(WidgetTester tester, Widget apercu) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(hote(apercu));
      for (var i = 0; i < 40 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
      }
    });
    await tester.pump();
  }

  testWidgets('la POINTE du repère est exactement sur le point relevé', (tester) async {
    late Uint8List octets;
    await tester.runAsync(() async => octets = await png(400, 200));

    await monter(
      tester,
      ApercuPlanReserve(
        plan: plan('paysage.png'),
        position: const ReservePositionRef(x: 25, y: 60),
        libelle: 'R-0003',
        couleur: Colors.red,
        telecharger: (_) async => octets,
      ),
    );

    expect(find.byKey(repere), findsOneWidget);
    final zone = tester.getRect(find.byKey(image));
    // Proportions RÉELLES du plan : étiré autrement, le repère dériverait.
    expect(zone.width / zone.height, closeTo(2, 0.01));

    final epingle = tester.getRect(find.byKey(repere));
    expect(epingle.center.dx, closeTo(zone.left + 0.25 * zone.width, 0.5));
    expect(epingle.bottom, closeTo(zone.top + 0.60 * zone.height, 0.5));
    // Le numéro, pour ne confondre ce repère avec rien d'autre.
    expect(find.text('R-0003'), findsOneWidget);
    expect(find.text('Emplacement sur le plan'), findsOneWidget);
  });

  testWidgets('sans point relevé : le plan, sans repère inventé', (tester) async {
    late Uint8List octets;
    await tester.runAsync(() async => octets = await png(200, 300));

    await monter(
      tester,
      ApercuPlanReserve(
        plan: plan('sans-point.png'),
        position: null,
        libelle: 'R-0004',
        couleur: Colors.red,
        telecharger: (_) async => octets,
      ),
    );

    expect(find.byKey(image), findsOneWidget);
    expect(find.byKey(repere), findsNothing);
    expect(find.text('Aucun point n’a été posé sur ce plan pour cette réserve.'), findsOneWidget);
  });

  testWidgets('plan injoignable : un message, et la fiche reste debout', (tester) async {
    await monter(
      tester,
      ApercuPlanReserve(
        plan: plan('injoignable.png'),
        position: const ReservePositionRef(x: 50, y: 50),
        libelle: 'R-0005',
        couleur: Colors.red,
        telecharger: (_) async => throw Exception('réseau coupé'),
      ),
    );

    expect(find.text('Aperçu du plan indisponible'), findsOneWidget);
    expect(find.byKey(repere), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('« Voir le plan » ouvre la visionneuse complète', (tester) async {
    late Uint8List octets;
    await tester.runAsync(() async => octets = await png(300, 300));
    var ouvert = 0;

    await monter(
      tester,
      ApercuPlanReserve(
        plan: plan('lien.png'),
        position: const ReservePositionRef(x: 50, y: 50),
        libelle: 'R-0006',
        couleur: Colors.red,
        onOuvrirPlan: () => ouvert++,
        telecharger: (_) async => octets,
      ),
    );

    await tester.tap(find.text('Voir le plan'));
    expect(ouvert, 1);
  });

  testWidgets('un appui sur le plan l’agrandit en plein écran', (tester) async {
    late Uint8List octets;
    await tester.runAsync(() async => octets = await png(300, 300));

    await monter(
      tester,
      ApercuPlanReserve(
        plan: plan('plein-ecran.png'),
        position: const ReservePositionRef(x: 50, y: 50),
        libelle: 'R-0007',
        couleur: Colors.red,
        telecharger: (_) async => octets,
      ),
    );

    await tester.tap(find.byKey(image));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Le titre du plan, dans la barre de l'écran plein.
    expect(find.widgetWithText(AppBar, 'arkada_13_2np3.jpg'), findsOneWidget);
  });
}
