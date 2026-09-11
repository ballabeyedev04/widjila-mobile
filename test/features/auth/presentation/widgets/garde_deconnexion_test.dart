import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/offline/file_attente.dart';
import 'package:suivie_chantier_mobile/features/auth/presentation/widgets/garde_deconnexion.dart';
import 'package:suivie_chantier_mobile/l10n/generated/app_localizations.dart';

class _MockFile extends Mock implements FileAttente {}

/// Audit synchronisation — la déconnexion volontaire ne détruit plus en
/// silence le travail hors ligne pas encore envoyé.
void main() {
  late _MockFile file;
  bool? resultat;

  setUp(() {
    file = _MockFile();
    resultat = null;
  });

  Future<void> monter(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => resultat = await confirmerPerteTravailNonEnvoye(context, file: file),
            child: const Text('Déconnexion'),
          ),
        ),
      ),
    ));
  }

  testWidgets('rien en attente : déconnexion autorisée, sans question', (tester) async {
    when(() => file.nombreEnAttente()).thenAnswer((_) async => 0);
    when(() => file.nombreEnEchec()).thenAnswer((_) async => 0);
    await monter(tester);

    await tester.tap(find.text('Déconnexion'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(resultat, isTrue);
  });

  testWidgets('travail en attente : l’utilisateur est prévenu, et « Annuler » garde la session', (tester) async {
    when(() => file.nombreEnAttente()).thenAnswer((_) async => 2);
    when(() => file.nombreEnEchec()).thenAnswer((_) async => 1);
    await monter(tester);

    await tester.tap(find.text('Déconnexion'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('3 actions'), findsOneWidget, reason: 'le nombre exact d’actions menacées est dit');
    expect(find.textContaining('définitivement perdues'), findsOneWidget);

    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(resultat, isFalse);
  });

  testWidgets('perte acceptée en connaissance de cause : déconnexion autorisée', (tester) async {
    when(() => file.nombreEnAttente()).thenAnswer((_) async => 1);
    when(() => file.nombreEnEchec()).thenAnswer((_) async => 0);
    await monter(tester);

    await tester.tap(find.text('Déconnexion'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 action'), findsOneWidget);

    await tester.tap(find.text('Se déconnecter et perdre'));
    await tester.pumpAndSettle();
    expect(resultat, isTrue);
  });
}
