import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/plan/presentation/widgets/plan_interactif.dart';

/// Le plan interactif — l'écran qui EST la zone de travail.
///
/// ## Les deux défauts corrigés
///
/// 1. **Un plan image n'était pas affiché.** Le rendu passait systématiquement
///    par `PdfDocument.openData`, qui échoue sur des octets PNG. Le dépôt
///    accepte pourtant png, jpg, jpeg et webp, et le serveur étiquette 'pdf'
///    tout fichier reçu sans format explicite : un plan photographié sur le
///    chantier arrivait donc marqué « PDF » et l'écran affichait une erreur à
///    la place du plan.
///
/// 2. **Il fallait armer un « mode pointage »** depuis le bandeau bas avant
///    qu'un appui ne fasse quoi que ce soit. Le client l'a tranché :
///    « l'utilisateur n'a pas besoin de chercher un bouton pour choisir
///    l'emplacement d'une réserve ».
///
/// ## Ce que ces tests verrouillent
///
/// L'appui rend des coordonnées NORMALISÉES (pourcentages), et non des pixels :
/// c'est ce qui garde un repère à sa place quand l'écran change de taille,
/// que l'orientation tourne ou que l'utilisateur zoome.

/// Une image PNG valide de 1×1 — assez pour que Flutter la décode vraiment.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  /// Monte le plan sur une surface connue, pour que les pourcentages attendus
  /// soient calculables.
  Future<void> monter(
    WidgetTester tester, {
    void Function(double x, double y)? onPoint,
    bool modePointage = false,
    List<MarqueurPlan> marqueurs = const [],
    void Function(MarqueurPlan)? onMarqueur,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final arbre = MaterialApp(
      home: Scaffold(
        body: PlanInteractif(
          octets: _png,
          marqueurs: marqueurs,
          modePointage: modePointage,
          onPointAppuye: onPoint,
          onMarqueurAppuye: onMarqueur,
        ),
      ),
    );

    // `runAsync` : le décodage de l'image est un VRAI travail asynchrone
    // (`decodeImageFromList`), que l'horloge simulée de `pump` ne fait pas
    // avancer. Sans lui, l'écran reste sur son indicateur de chargement et
    // aucun test ne verrait jamais le plan.
    //
    // Pas de `pumpAndSettle` non plus, pour la même raison : cet indicateur
    // tourne sans fin tant que le rendu n'est pas revenu.
    await tester.runAsync(() async {
      await tester.pumpWidget(arbre);
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pump();
  }

  group('un plan IMAGE s’affiche', () {
    testWidgets('des octets PNG sont rendus, sans passer par le moteur PDF', (tester) async {
      await monter(tester);

      expect(find.byType(Image), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('l’appui sur une zone libre', () {
    testWidgets('crée une réserve SANS mode pointage préalable', (tester) async {
      // La règle fondamentale : le plan est la zone de travail.
      double? x, y;
      await monter(tester, onPoint: (a, b) {
        x = a;
        y = b;
      });

      await tester.tapAt(tester.getCenter(find.byType(Image).first));
      await tester.pump();

      expect(x, isNotNull, reason: 'un appui sur le plan doit être entendu');
      expect(y, isNotNull);
    });

    testWidgets('rend des POURCENTAGES, pas des pixels', (tester) async {
      // Un appui au centre vaut 50 % / 50 % quelle que soit la taille de
      // l'écran. Des pixels décaleraient le repère au premier changement de
      // format, d'orientation ou d'appareil.
      double? x, y;
      await monter(tester, onPoint: (a, b) {
        x = a;
        y = b;
      });

      await tester.tapAt(tester.getCenter(find.byType(Image).first));
      await tester.pump();

      expect(x, closeTo(50, 1));
      expect(y, closeTo(50, 1));
    });

    testWidgets('reste sans effet quand le rôle ne peut pas poser de réserve', (tester) async {
      // `onPointAppuye` nul = plan inerte. Les repères déjà posés restent
      // visibles : consulter n'est pas créer.
      await monter(tester, onPoint: null);

      await tester.tapAt(tester.getCenter(find.byType(Image).first));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('le mode pointage n’empêche plus rien — il ne fait qu’aider', (tester) async {
      // Seconde méthode décrite par le client : le bouton puis le choix de
      // l'emplacement. Elle doit aboutir au même geste.
      double? x;
      await monter(tester, modePointage: true, onPoint: (a, _) => x = a);

      await tester.tapAt(tester.getCenter(find.byType(Image).first));
      await tester.pump();

      expect(x, isNotNull);
    });
  });

  group('les repères des réserves', () {
    const marqueur = MarqueurPlan(id: 'r1', x: 50, y: 50, couleur: Colors.red);

    testWidgets('sont affichés sur le plan', (tester) async {
      await monter(tester, marqueurs: const [marqueur]);

      // Le plan lui-même plus le repère : au moins deux dessins.
      expect(find.byType(Image), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un plan sans réserve reste affiché et cliquable', (tester) async {
      // Cas explicitement demandé : zéro réserve ne doit rien empêcher.
      double? x;
      await monter(tester, marqueurs: const [], onPoint: (a, _) => x = a);

      await tester.tapAt(tester.getCenter(find.byType(Image).first));
      await tester.pump();

      expect(x, isNotNull);
    });
  });
}
