import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:suivie_chantier_mobile/core/routes/retour.dart';

/// Tests — retour arrière sûr.
///
/// ## Le défaut corrigé
///
/// `context.pop()` ne fait RIEN quand la pile est vide, et elle l'est souvent
/// dans cette application :
///
///  - `/equipe`, `/abonnement`, `/chantiers`, `/intervenants` sont atteints
///    par `go()` depuis le menu « Plus » — `push` y superposerait deux barres
///    de navigation (voir `app_shell.dart`) ;
///  - `/reserves/:id` et `/plans/:id` sont ouverts par `go()` depuis une
///    notification, hors de l'application ;
///  - `/reinitialiser-mot-de-passe` arrive par le lien d'un courriel.
///
/// La flèche de retour ne répondait alors pas. Sur Android, c'est pire :
/// faute de route à dépiler, le bouton retour matériel FERME l'application.
void main() {
  /// Routeur minimal : un accueil, un écran empilable, un écran de repli.
  GoRouter construire() => GoRouter(
        initialLocation: '/accueil',
        routes: [
          GoRoute(path: '/accueil', builder: (_, _) => const Text('accueil')),
          GoRoute(path: '/plans', builder: (_, _) => const Text('plans')),
          GoRoute(
            path: '/detail',
            builder: (context, _) => TextButton(
              onPressed: () => context.retourVers('/plans'),
              child: const Text('detail'),
            ),
          ),
        ],
      );

  Future<GoRouter> monter(WidgetTester tester) async {
    final routeur = construire();
    await tester.pumpWidget(MaterialApp.router(routerConfig: routeur));
    await tester.pumpAndSettle();
    return routeur;
  }

  testWidgets('dépile quand il y a une pile (écran atteint par push)', (tester) async {
    final routeur = await monter(tester);

    routeur.push('/detail');
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);

    await tester.tap(find.text('detail'));
    await tester.pumpAndSettle();

    // On revient à l'écran d'où l'on venait, pas au repli.
    expect(find.text('accueil'), findsOneWidget);
    expect(find.text('plans'), findsNothing);
  });

  testWidgets('rejoint le repli quand la pile est vide (écran atteint par go)', (tester) async {
    final routeur = await monter(tester);

    // `go` REMPLACE : c'est ce que fait le menu « Plus » et l'ouverture depuis
    // une notification.
    routeur.go('/detail');
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);

    await tester.tap(find.text('detail'));
    await tester.pumpAndSettle();

    // Sans le correctif, rien ne se serait passé : l'écran serait resté
    // affiché, flèche de retour inerte.
    expect(find.text('plans'), findsOneWidget);
    expect(find.text('detail'), findsNothing);
  });

  testWidgets('ne laisse jamais l’écran inchangé', (tester) async {
    // Le contrat qui compte : quelle que soit la façon dont on est arrivé,
    // le retour aboutit quelque part. Jamais de cul-de-sac.
    for (final parPush in [true, false]) {
      final routeur = await monter(tester);
      parPush ? routeur.push('/detail') : routeur.go('/detail');
      await tester.pumpAndSettle();

      await tester.tap(find.text('detail'));
      await tester.pumpAndSettle();

      expect(find.text('detail'), findsNothing,
          reason: parPush ? 'après un push' : 'après un go');
    }
  });
}
