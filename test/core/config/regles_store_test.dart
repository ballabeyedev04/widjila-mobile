import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/config/regles_store.dart';
import 'package:suivie_chantier_mobile/core/errors/error_codes.dart';
import 'package:suivie_chantier_mobile/core/widgets/modale_abonnement.dart';

import '../../helpers/l10n_test_helpers.dart';

/// Ce que l'application montre selon la boutique qui la distribue.
///
/// ## Le refus d'Apple (23/09/2026, 1.0 (15)), directive 3.1.1
///
///  1. accès à un contenu payant achetable hors achat intégré — l'écran
///     Abonnement affichait les tarifs et ouvrait le paiement Stripe dans
///     le navigateur ;
///  2. l'inscription d'une entreprise, assimilée à un canal d'achat externe.
///
/// Sur iOS, l'application est donc un CLIENT de l'abonnement : aucun tarif,
/// aucun bouton d'achat, aucun lien vers la page de paiement, aucune création
/// de compte. Android et le web ne changent pas.
///
/// Ces tests sont la garde : un bouton de vente qui reviendrait sur iOS les
/// ferait échouer avant d'atteindre l'App Store.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('la règle elle-même', () {
    test('iOS : ni commerce ni inscription', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(ReglesStore.commerceAutorise, isFalse);
      expect(ReglesStore.inscriptionAutorisee, isFalse);
    });

    test('Android : rien ne change — la vente y reste ouverte', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      expect(ReglesStore.commerceAutorise, isTrue);
      expect(ReglesStore.inscriptionAutorisee, isTrue);
    });
  });

  group('la modale de refus d’abonnement', () {
    /// Monte la modale SOUS [plateforme], puis relâche la surcharge : Flutter
    /// vérifie après chaque `testWidgets` qu'aucune variable de débogage n'est
    /// restée posée — l'arbre est déjà construit, les assertions qui suivent
    /// portent dessus.
    Future<void> monter(WidgetTester tester, TargetPlatform plateforme) async {
      debugDefaultTargetPlatformOverride = plateforme;
      await tester.pumpWidget(MaterialApp(
        locale: testLocale,
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => afficherModaleAbonnement(
                context,
                RefusAbonnementDecode.tenter(
                  '${ErrCodes.prefixeAbonnement}SUBSCRIPTION_REQUIRED|Abonnement requis.',
                )!,
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    }

    testWidgets('iOS : aucun renvoi vers les formules, on dit à qui s’adresser', (tester) async {
      await monter(tester, TargetPlatform.iOS);

      expect(find.text('Voir les formules'), findsNothing);
      expect(find.textContaining('administrateur de votre organisation'), findsOneWidget);
      // Ni tarif, ni adresse où payer : l'App Store interdit l'un comme l'autre.
      expect(find.textContaining('€'), findsNothing);
      expect(find.textContaining('widjila.com'), findsNothing);
    });

    testWidgets('Android : le bouton « Voir les formules » reste', (tester) async {
      await monter(tester, TargetPlatform.android);

      expect(find.text('Voir les formules'), findsOneWidget);
    });
  });
}
