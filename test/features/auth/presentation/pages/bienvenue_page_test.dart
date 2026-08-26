import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:suivie_chantier_mobile/core/routes/app_router.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/pages/bienvenue_page.dart';

import '../../../../helpers/l10n_test_helpers.dart';

/// Écran d'accueil du visiteur non connecté.
///
/// Deux exigences du client s'y jouent : les deux portes d'entrée doivent
/// mener aux bons écrans, et la mention « Mode hors ligne » de la maquette
/// d'origine ne doit PAS y figurer — elle promettrait un parcours qui
/// n'existe pas sans session.
void main() {
  /// Routeur minimal : les destinations sont des pages témoins, on vérifie
  /// l'aiguillage, pas le contenu des écrans d'arrivée.
  GoRouter routeurDeTest() => GoRouter(
        initialLocation: AppRoutes.bienvenue,
        routes: [
          GoRoute(path: AppRoutes.bienvenue, builder: (_, _) => const BienvenuePage()),
          GoRoute(path: AppRoutes.login, builder: (_, _) => const Scaffold(body: Text('ECRAN_LOGIN'))),
          GoRoute(path: AppRoutes.register, builder: (_, _) => const Scaffold(body: Text('ECRAN_REGISTER'))),
        ],
      );

  Future<void> pomper(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp.router(
      locale: testLocale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      routerConfig: routeurDeTest(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('affiche la marque, l’accroche et les deux actions', (tester) async {
    await pomper(tester);

    expect(find.text('Widjila'), findsOneWidget);
    expect(find.textContaining('Levez vos réserves'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.text('Créer un compte'), findsOneWidget);
  });

  testWidgets('ne propose PAS de mode hors ligne', (tester) async {
    await pomper(tester);

    expect(find.textContaining('hors ligne'), findsNothing);
    expect(find.textContaining('Hors ligne'), findsNothing);
  });

  testWidgets('« Se connecter » ouvre l’écran de connexion', (tester) async {
    await pomper(tester);

    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(find.text('ECRAN_LOGIN'), findsOneWidget);
  });

  testWidgets('« Créer un compte » ouvre l’inscription', (tester) async {
    await pomper(tester);

    await tester.tap(find.text('Créer un compte'));
    await tester.pumpAndSettle();

    expect(find.text('ECRAN_REGISTER'), findsOneWidget);
  });
}
