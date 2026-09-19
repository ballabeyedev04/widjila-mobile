import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/services/feedback_sonore.dart';
import 'package:suivie_chantier_mobile/core/widgets/app_alert.dart';

import '../../helpers/l10n_test_helpers.dart';
import '../services/feedback_sonore_test.dart' show LecteurEspion;

/// Le son de succès est joué PAR la confirmation visuelle, pas par les écrans.
///
/// - `AppAlert.success` → carte verte + un son ;
/// - `AppAlert.confirmation` → bandeau + un son ;
/// - `AppAlert.error` → carte rouge, AUCUN son ;
/// - un double appui, une page reconstruite → toujours un seul son.
void main() {
  late LecteurEspion lecteur;

  setUp(() {
    lecteur = LecteurEspion();
    // Horloge fixe : dans un test, tout se passe « au même instant » — ce qui
    // est justement le cas d'un doublon. Les cas qui veulent deux sons
    // distincts réinitialisent la garde explicitement.
    FeedbackSonore.instance = FeedbackSonore(lecteur: lecteur, horloge: () => DateTime(2026, 9, 18));
  });

  tearDown(() => FeedbackSonore.instance = FeedbackSonore());

  /// Un écran avec un bouton qui simule une action : succès ou échec,
  /// confirmé APRÈS un aller-retour asynchrone (comme une réponse d'API).
  Future<void> monter(
    WidgetTester tester, {
    required Future<bool> Function() action,
    bool bandeau = false,
  }) {
    return tester.pumpWidget(MaterialApp(
      locale: testLocale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: Column(
            children: [
              ElevatedButton(
                key: const Key('agir'),
                onPressed: () async {
                  final ok = await action();
                  if (!context.mounted) return;
                  if (ok) {
                    if (bandeau) {
                      AppAlert.confirmation(context, message: 'Membre affecté.');
                    } else {
                      AppAlert.success(context, message: 'Réserve créée.');
                    }
                  } else {
                    AppAlert.error(context, message: 'Le serveur a refusé.');
                  }
                },
                child: const Text('Agir'),
              ),
              ElevatedButton(
                key: const Key('rebuild'),
                onPressed: () => setState(() {}),
                child: const Text('Reconstruire'),
              ),
            ],
          ),
        ),
      ),
    ));
  }

  testWidgets('action réussie → carte verte + son, une seule fois', (tester) async {
    await monter(tester, action: () async => true);

    await tester.tap(find.byKey(const Key('agir')));
    await tester.pumpAndSettle();

    expect(find.text('Réserve créée.'), findsOneWidget);
    expect(lecteur.joues, [FeedbackSonore.assetSucces]);
  });

  testWidgets('action échouée → carte rouge, AUCUN son de succès', (tester) async {
    await monter(tester, action: () async => false);

    await tester.tap(find.byKey(const Key('agir')));
    await tester.pumpAndSettle();

    expect(find.text('Le serveur a refusé.'), findsOneWidget);
    expect(lecteur.joues, isEmpty);
  });

  testWidgets('le son ne part pas au clic : il attend la confirmation', (tester) async {
    // La réponse arrive plus tard : entre le clic et la réponse, silence.
    var repondre = false;
    await monter(tester, action: () async {
      while (!repondre) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return true;
    });

    await tester.tap(find.byKey(const Key('agir')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(lecteur.joues, isEmpty, reason: 'rien tant que le serveur n’a pas répondu');

    repondre = true;
    await tester.pumpAndSettle();
    expect(lecteur.joues, hasLength(1));
  });

  testWidgets('confirmation légère (bandeau) → bandeau + son', (tester) async {
    await monter(tester, action: () async => true, bandeau: true);

    await tester.tap(find.byKey(const Key('agir')));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Membre affecté.'), findsOneWidget);
    expect(lecteur.joues, hasLength(1));
  });

  testWidgets('double appui pendant l’attente du serveur → un seul son', (tester) async {
    // Le pire cas : l'écran n'a pas neutralisé son bouton, les deux appuis
    // partent, les deux réponses arrivent. L'utilisateur doit entendre UN son.
    var appels = 0;
    await monter(tester, action: () async {
      appels++;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return true;
    }, bandeau: true);

    await tester.tap(find.byKey(const Key('agir')));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tap(find.byKey(const Key('agir')));
    await tester.pumpAndSettle();

    expect(appels, 2);
    expect(lecteur.joues, hasLength(1));
  });

  testWidgets('reconstruire la page ne rejoue pas le son', (tester) async {
    await monter(tester, action: () async => true, bandeau: true);

    await tester.tap(find.byKey(const Key('agir')));
    await tester.pumpAndSettle();
    expect(lecteur.joues, hasLength(1));

    FeedbackSonore.instance.reinitialiser(); // la garde n'entre pas en jeu ici
    await tester.tap(find.byKey(const Key('rebuild')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('rebuild')));
    await tester.pumpAndSettle();

    expect(lecteur.joues, hasLength(1), reason: 'le son est lié à l’action, pas à build()');
  });

  testWidgets('deux actions distinctes, espacées → deux sons', (tester) async {
    var instant = DateTime(2026, 9, 18, 12);
    FeedbackSonore.instance = FeedbackSonore(lecteur: lecteur, horloge: () => instant);
    await monter(tester, action: () async => true, bandeau: true);

    await tester.tap(find.byKey(const Key('agir')));
    await tester.pumpAndSettle();
    instant = instant.add(const Duration(seconds: 2));
    await tester.tap(find.byKey(const Key('agir')));
    await tester.pumpAndSettle();

    expect(lecteur.joues, hasLength(2));
  });
}
