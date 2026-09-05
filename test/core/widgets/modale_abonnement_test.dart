import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/errors/error_codes.dart';
import 'package:suivie_chantier_mobile/core/widgets/modale_abonnement.dart';

import '../../helpers/l10n_test_helpers.dart';

/// Le refus d'abonnement, du serveur jusqu'à l'écran.
///
/// ## Ce qui manquait
///
/// Le serveur renvoie depuis toujours un code machine — `SUBSCRIPTION_REQUIRED`,
/// `SUBSCRIPTION_FEATURE_UNAVAILABLE`, `SUBSCRIPTION_LIMIT_REACHED` — et un
/// message qui nomme la formule en cours et le plafond atteint. Le mobile ne
/// lisait pas ce code : il affichait le message comme n'importe quelle erreur,
/// en rouge, avec un simple « OK ».
///
/// Or c'est le seul refus qu'un utilisateur peut lever lui-même. Il mérite une
/// porte de sortie, pas un constat.
void main() {
  const messageServeur =
      'Votre abonnement Essentiel est limité à 2 utilisateurs (2 utilisés). '
      'Passez à une formule supérieure pour en ajouter.';

  group('décodage', () {
    test('reconnaît un plafond atteint et conserve le message du serveur', () {
      // Le message n'est PAS remplacé : lui seul nomme la formule et le
      // plafond. Un texte générique écrit ici perdrait tout ce qui aide.
      final refus = RefusAbonnementDecode.tenter(
        '${ErrCodes.prefixeAbonnement}SUBSCRIPTION_LIMIT_REACHED|$messageServeur',
      );

      expect(refus, isNotNull);
      expect(refus!.raison, RefusAbonnement.limiteAtteinte);
      expect(refus.message, messageServeur);
    });

    test('reconnaît une fonctionnalité absente de la formule', () {
      final refus = RefusAbonnementDecode.tenter(
        '${ErrCodes.prefixeAbonnement}SUBSCRIPTION_FEATURE_UNAVAILABLE|'
        '« Rapports PDF » n’est pas incluse dans votre abonnement Essentiel.',
      );

      expect(refus!.raison, RefusAbonnement.fonctionnaliteAbsente);
    });

    test('reconnaît l’absence totale d’abonnement', () {
      final refus = RefusAbonnementDecode.tenter(
        '${ErrCodes.prefixeAbonnement}SUBSCRIPTION_REQUIRED|Aucun abonnement actif.',
      );

      expect(refus!.raison, RefusAbonnement.aucunAbonnement);
      expect(refus.message, 'Aucun abonnement actif.');
    });

    test('laisse passer un message ORDINAIRE sans le transformer', () {
      // Le mécanisme est un aiguillage, pas un filtre : une panne réseau ou un
      // 500 doit continuer de s'afficher comme une erreur.
      expect(RefusAbonnementDecode.tenter('Chantier introuvable'), isNull);
      expect(RefusAbonnementDecode.tenter(ErrCodes.generic), isNull);
      expect(RefusAbonnementDecode.tenter(''), isNull);
    });

    test('supporte un code inconnu sans perdre le message', () {
      // Le serveur peut ajouter un code demain. On retombe sur le titre
      // générique plutôt que de laisser tomber l'invitation.
      final refus = RefusAbonnementDecode.tenter(
        '${ErrCodes.prefixeAbonnement}SUBSCRIPTION_QUELQUE_CHOSE|Un message utile.',
      );

      expect(refus!.raison, RefusAbonnement.aucunAbonnement);
      expect(refus.message, 'Un message utile.');
    });

    test('supporte un message contenant lui-même une barre verticale', () {
      // On coupe à la PREMIÈRE barre seulement : le reste appartient au
      // message.
      final refus = RefusAbonnementDecode.tenter(
        '${ErrCodes.prefixeAbonnement}SUBSCRIPTION_REQUIRED|a | b | c',
      );

      expect(refus!.message, 'a | b | c');
    });
  });

  group('affichage', () {
    testWidgets('propose une issue vers les formules, pas un simple « OK »',
        (tester) async {
      final refus = RefusAbonnementDecode.tenter(
        '${ErrCodes.prefixeAbonnement}SUBSCRIPTION_LIMIT_REACHED|$messageServeur',
      )!;

      await tester.pumpWidget(MaterialApp(
        locale: testLocale,
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => afficherModaleAbonnement(context, refus),
                child: const Text('declencher'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('declencher'));
      await tester.pumpAndSettle();

      // Le message du serveur, intact.
      expect(find.textContaining('2 utilisateurs'), findsOneWidget);
      // Un titre qui dit ce qui se passe, et non « Erreur ».
      expect(find.text('Vous avez atteint la limite'), findsOneWidget);
      // Et surtout : une porte de sortie.
      expect(find.text('Voir les formules'), findsOneWidget);
      expect(find.text('Plus tard'), findsOneWidget);
    });

    testWidgets('le titre s’adapte a la raison du refus', (tester) async {
      final refus = RefusAbonnementDecode.tenter(
        '${ErrCodes.prefixeAbonnement}SUBSCRIPTION_REQUIRED|Aucun abonnement actif.',
      )!;

      await tester.pumpWidget(MaterialApp(
        locale: testLocale,
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => afficherModaleAbonnement(context, refus),
                child: const Text('declencher'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('declencher'));
      await tester.pumpAndSettle();

      expect(find.text('Un abonnement est nécessaire'), findsOneWidget);
    });
  });
}
