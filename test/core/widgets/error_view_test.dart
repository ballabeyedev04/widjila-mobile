import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/errors/error_codes.dart';
import 'package:suivie_chantier_mobile/core/widgets/error_view.dart';
import 'package:suivie_chantier_mobile/l10n/generated/app_localizations.dart';

import '../../helpers/l10n_test_helpers.dart';

Widget _app(Widget enfant) => MaterialApp(
      locale: testLocale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(body: enfant),
    );

/// Audit observabilité — l'écran d'erreur ne montre plus les marqueurs internes.
///
/// Défaut reproduit : seule `AppAlert.error` traduisait les marqueurs de la
/// couche réseau. `ErrorView` — l'écran d'erreur d'une trentaine de pages —
/// affichait « __ERR_SERVICE_UNAVAILABLE__ » en toutes lettres quand l'API
/// répondait 503 sans message.
void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(testLocale);
  });

  testWidgets('un marqueur de la couche réseau est traduit', (tester) async {
    await tester.pumpWidget(_app(ErrorView(message: ErrCodes.serviceUnavailable, onRetry: () {})));

    expect(find.text(l10n.errServiceUnavailable), findsOneWidget);
    expect(find.textContaining('__ERR_'), findsNothing);
  });

  testWidgets('le marqueur générique aussi', (tester) async {
    await tester.pumpWidget(_app(const ErrorView(message: ErrCodes.generic)));

    expect(find.text(l10n.commonErrorUnknown), findsOneWidget);
  });

  testWidgets('un refus d’abonnement montre le texte du serveur, sans son préfixe technique', (tester) async {
    await tester.pumpWidget(_app(const ErrorView(
      message: '${ErrCodes.prefixeAbonnement}SUBSCRIPTION_LIMIT_REACHED|Votre abonnement est limité à 2 chantiers',
    )));

    expect(find.text('Votre abonnement est limité à 2 chantiers'), findsOneWidget);
    expect(find.textContaining('SUBSCRIPTION_'), findsNothing);
  });

  testWidgets('un message ordinaire du serveur passe inchangé', (tester) async {
    await tester.pumpWidget(_app(const ErrorView(message: 'Chantier introuvable')));

    expect(find.text('Chantier introuvable'), findsOneWidget);
  });
}
