import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Tests — la destination d'une notification survit au contrôle de session.
///
/// ## Le défaut reproduit ici
///
/// Application lancée DEPUIS une alerte :
///   1. `getInitialMessage()` rend le message et la navigation part ;
///   2. `AuthBloc` est encore en `AuthStatus.inconnu` — la vérification de
///      session s'impose un plancher de 1200 ms (`_dureeMinSplash`) ;
///   3. la redirection du routeur ramène sur `/splash` ;
///   4. la session résolue, elle envoie sur le tableau de bord.
///
/// Ce n'est pas une course perdue « parfois » : le plancher la rend
/// systématique. Celui qui touche « Réserve R-108 en retard » atterrit
/// toujours sur son tableau de bord.
///
/// Ces tests reproduisent la MÉCANIQUE de redirection sur un routeur réduit —
/// `PushBootstrap` lui-même exige Firebase, hors de portée d'un test unitaire.
/// Ce qui est vérifié, c'est la règle : naviguer avant l'ouverture de session
/// ne mène nulle part, et une destination gardée de côté aboutit.
void main() {
  /// Routeur calqué sur `app_router.dart` : même règle de redirection.
  ({GoRouter routeur, void Function(bool) definirSession}) construire() {
    var authentifie = false;
    final notificateur = ValueNotifier<int>(0);

    final routeur = GoRouter(
      initialLocation: '/splash',
      refreshListenable: notificateur,
      redirect: (context, state) {
        final loc = state.matchedLocation;
        // Statut inconnu : tout ramène au splash — c'est ici que la
        // destination de l'alerte se perdait.
        if (!authentifie) return loc == '/splash' ? null : '/splash';
        if (loc == '/splash') return '/tableau-de-bord';
        return null;
      },
      routes: [
        GoRoute(path: '/splash', builder: (_, _) => const Text('splash')),
        GoRoute(path: '/tableau-de-bord', builder: (_, _) => const Text('accueil')),
        GoRoute(path: '/reserves/:id', builder: (_, s) => Text('reserve ${s.pathParameters['id']}')),
      ],
    );

    return (
      routeur: routeur,
      definirSession: (valeur) {
        authentifie = valeur;
        notificateur.value++;
      },
    );
  }

  Future<void> monter(WidgetTester tester, GoRouter routeur) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: routeur));
    await tester.pumpAndSettle();
  }

  testWidgets('naviguer AVANT l’ouverture de session ne mène nulle part', (tester) async {
    final app = construire();
    await monter(tester, app.routeur);

    // Ce que faisait `_surOuverture` : partir tout de suite.
    app.routeur.go('/reserves/R-108');
    await tester.pumpAndSettle();

    expect(find.text('reserve R-108'), findsNothing);
    expect(find.text('splash'), findsOneWidget);

    // Puis la session s'ouvre : on atterrit sur l'accueil, pas sur la réserve.
    app.definirSession(true);
    await tester.pumpAndSettle();

    expect(find.text('accueil'), findsOneWidget);
    expect(find.text('reserve R-108'), findsNothing);
  });

  testWidgets('une destination gardée puis rejouée aboutit', (tester) async {
    final app = construire();
    await monter(tester, app.routeur);

    // Ce que fait le correctif : mettre de côté tant que la session n'est pas
    // ouverte, et rejouer APRÈS la frame de bascule.
    const destinationEnAttente = '/reserves/R-108';

    app.definirSession(true);
    await tester.pumpAndSettle();
    app.routeur.go(destinationEnAttente);
    await tester.pumpAndSettle();

    expect(find.text('reserve R-108'), findsOneWidget);
  });

  testWidgets('la redirection d’ouverture de session précède la destination', (tester) async {
    // Justifie le `addPostFrameCallback` : la bascule déclenche elle-même une
    // redirection vers l'accueil. Naviguer dans la même frame passerait AVANT
    // elle, et serait donc écrasé.
    final app = construire();
    await monter(tester, app.routeur);

    app.definirSession(true);
    // `pumpAndSettle` et non un nombre fixe de `pump()` : ce qui est vérifié
    // ici est un ORDRE — la redirection d'ouverture de session aboutit AVANT
    // qu'on demande la destination — et non le nombre de frames que go_router
    // met à l'appliquer, qui est un détail interne de la bibliothèque.
    //
    // Ce test épinglait `await tester.pump()`, une seule frame. Il a cessé de
    // passer alors que ni go_router (16.3.0, inchangé) ni le comportement de
    // l'application n'avaient bougé : la redirection en demande désormais
    // deux. C'était donc une assertion sur la mécanique de la bibliothèque,
    // pas sur la règle que ce fichier documente.
    await tester.pumpAndSettle();
    expect(find.text('accueil'), findsOneWidget);

    app.routeur.go('/reserves/R-108');
    await tester.pumpAndSettle();
    expect(find.text('reserve R-108'), findsOneWidget);
  });
}
