import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/reserve/data/historique_observations.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/widgets/champ_observation.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/widgets/dictee_vocale.dart';
import 'package:suivie_chantier_mobile/l10n/generated/app_localizations.dart';

import '../../../../helpers/l10n_test_helpers.dart';

/// Moteur factice : on lui fait « dire » ce que le test veut, sans micro.
class _MoteurFactice implements MoteurDictee {
  ErreurDictee? erreurPreparation;
  void Function(String texte, bool definitif)? _surResultat;
  void Function(ErreurDictee? erreur)? _surFin;
  int ecoutes = 0;
  int arrets = 0;
  int annulations = 0;

  @override
  Future<ErreurDictee?> preparer() async => erreurPreparation;

  @override
  Future<void> ecouter({
    required String langue,
    required void Function(String texte, bool definitif) surResultat,
    required void Function(ErreurDictee? erreur) surFin,
  }) async {
    ecoutes++;
    _surResultat = surResultat;
    _surFin = surFin;
  }

  @override
  Future<void> arreter() async => arrets++;

  @override
  Future<void> annuler() async => annulations++;

  void dire(String texte, {bool definitif = false}) => _surResultat!(texte, definitif);
  void finir([ErreurDictee? erreur]) => _surFin!(erreur);
}

class _SourceFactice implements SourceObservations {
  final List<String> liste;
  const _SourceFactice(this.liste);

  @override
  Future<List<String>> charger() async => liste;
}

/// Champ « Observation » : dictée (ajout au texte, arrêt, erreurs) et
/// suggestions. Le moteur factice rend chaque scénario reproductible.
void main() {
  late AppLocalizations l10n;
  late _MoteurFactice moteur;
  late TextEditingController controleur;

  setUpAll(() async => l10n = await AppLocalizations.delegate.load(testLocale));

  setUp(() {
    moteur = _MoteurFactice();
    controleur = TextEditingController();
  });

  Future<void> pomper(WidgetTester tester, {List<String> historique = const []}) async {
    await tester.pumpWidget(MaterialApp(
      locale: testLocale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ChampObservation(
            controller: controleur,
            labelText: 'Observation',
            hintText: 'Décrivez le défaut',
            historique: _SourceFactice(historique),
            moteur: moteur,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  final micro = find.byKey(const ValueKey('micro-observation'));

  /// Appuie sur le micro et laisse la préparation (asynchrone) aboutir.
  Future<void> dicter(WidgetTester tester) async {
    await tester.tap(micro);
    await tester.pump();
    await tester.pump();
  }

  group('dictée', () {
    testWidgets('« client VIP » + dictée « livraison demain » → « client VIP livraison demain »', (tester) async {
      await pomper(tester);
      await tester.enterText(find.byType(TextFormField), 'client VIP');

      await dicter(tester);
      expect(find.text(l10n.reserveNouvDicteeEcoute), findsOneWidget, reason: 'l’écoute est clairement signalée');
      expect(find.byTooltip(l10n.reserveNouvDicteeArreter), findsOneWidget);

      moteur.dire('livraison');
      await tester.pump();
      expect(controleur.text, 'client VIP livraison', reason: 'le texte apparaît pendant qu’on parle');

      moteur.dire('livraison demain', definitif: true);
      moteur.finir();
      await tester.pump();

      expect(controleur.text, 'client VIP livraison demain');
      expect(find.text(l10n.reserveNouvDicteeEcoute), findsNothing);
      expect(find.byTooltip(l10n.reserveNouvDicter), findsOneWidget, reason: 'micro revenu au repos');
    });

    testWidgets('plusieurs dictées successives s’ajoutent les unes aux autres', (tester) async {
      await pomper(tester);

      await dicter(tester);
      moteur.dire('coins cassés', definitif: true);
      moteur.finir();
      await tester.pump();

      await dicter(tester);
      moteur.dire('sur la porte', definitif: true);
      moteur.finir();
      await tester.pump();

      expect(controleur.text, 'coins cassés sur la porte');
      expect(moteur.ecoutes, 2);
    });

    testWidgets('la saisie manuelle reste possible après une dictée, et une dictée suivante s’y ajoute', (tester) async {
      await pomper(tester);
      await dicter(tester);
      moteur.dire('fissure', definitif: true);
      moteur.finir();
      await tester.pump();

      await tester.enterText(find.byType(TextFormField), 'fissure au plafond');
      await dicter(tester);
      moteur.dire('de la cuisine', definitif: true);
      moteur.finir();
      await tester.pump();

      expect(controleur.text, 'fissure au plafond de la cuisine');
    });

    testWidgets('un second appui sur le micro arrête l’écoute, sans message d’erreur', (tester) async {
      await pomper(tester);
      await dicter(tester);

      await tester.tap(micro);
      await tester.pump();
      expect(moteur.arrets, 1);

      moteur.finir();
      await tester.pump();
      expect(find.text(l10n.reserveNouvDicteeEcoute), findsNothing);
      expect(find.text(l10n.reserveNouvDicteeAucuneParole), findsNothing);
    });

    testWidgets('taper au clavier pendant l’écoute l’arrête, et un résultat tardif n’écrase rien', (tester) async {
      await pomper(tester);
      await dicter(tester);
      moteur.dire('bonjour');
      await tester.pump();

      await tester.enterText(find.byType(TextFormField), 'texte tapé à la main');
      await tester.pump();
      moteur.dire('bonjour tout le monde', definitif: true);
      await tester.pump();

      expect(moteur.annulations, 1);
      expect(controleur.text, 'texte tapé à la main');
    });
  });

  group('erreurs — le texte déjà saisi n’est jamais perdu', () {
    testWidgets('micro refusé', (tester) async {
      await pomper(tester);
      await tester.enterText(find.byType(TextFormField), 'client VIP');
      moteur.erreurPreparation = ErreurDictee.microRefuse;

      await dicter(tester);

      expect(find.text(l10n.reserveNouvDicteeMicroRefuse), findsOneWidget);
      expect(controleur.text, 'client VIP');
      expect(moteur.ecoutes, 0);
    });

    testWidgets('appareil sans reconnaissance vocale', (tester) async {
      await pomper(tester);
      moteur.erreurPreparation = ErreurDictee.indisponible;

      await dicter(tester);

      expect(find.text(l10n.reserveNouvDicteeIndisponible), findsOneWidget);
    });

    testWidgets('aucune parole détectée', (tester) async {
      await pomper(tester);
      await dicter(tester);

      moteur.finir(ErreurDictee.aucuneParole);
      await tester.pump();

      expect(find.text(l10n.reserveNouvDicteeAucuneParole), findsOneWidget);
    });

    testWidgets('silence final après des mots reconnus : pas d’erreur', (tester) async {
      await pomper(tester);
      await dicter(tester);
      moteur.dire('coins cassés');
      moteur.finir(ErreurDictee.aucuneParole);
      await tester.pump();

      expect(find.text(l10n.reserveNouvDicteeAucuneParole), findsNothing);
      expect(controleur.text, 'coins cassés');
    });

    testWidgets('reconnaissance interrompue (réseau) : ce qui a été reconnu est gardé', (tester) async {
      await pomper(tester);
      await tester.enterText(find.byType(TextFormField), 'client VIP');
      await dicter(tester);
      moteur.dire('livraison');
      moteur.finir(ErreurDictee.reseau);
      await tester.pump();

      expect(find.text(l10n.reserveNouvDicteeReseau), findsOneWidget);
      expect(controleur.text, 'client VIP livraison');
    });

    testWidgets('interruption quelconque', (tester) async {
      await pomper(tester);
      await dicter(tester);
      moteur.finir(ErreurDictee.interrompue);
      await tester.pump();

      expect(find.text(l10n.reserveNouvDicteeInterrompue), findsOneWidget);
    });
  });

  group('suggestions', () {
    testWidgets('« coi » propose « coins casse » ; la choisir l’insère', (tester) async {
      await pomper(tester, historique: ['coins casse', 'fissure plafond']);

      await tester.enterText(find.byType(TextFormField), 'coi');
      await tester.pump();

      expect(find.byKey(const ValueKey('suggestion-coins casse')), findsOneWidget);
      expect(find.byKey(const ValueKey('suggestion-fissure plafond')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('suggestion-coins casse')));
      await tester.pump();

      expect(controleur.text, 'coins casse');
      expect(find.byKey(const ValueKey('suggestion-coins casse')), findsNothing,
          reason: 'déjà exactement ce qui est écrit');
    });

    testWidgets('une nouvelle observation se saisit librement, sans suggestion', (tester) async {
      await pomper(tester, historique: ['coins casse']);

      await tester.enterText(find.byType(TextFormField), 'peinture écaillée');
      await tester.pump();

      expect(find.text(l10n.reserveNouvSuggestionsTitre), findsNothing);
      expect(controleur.text, 'peinture écaillée');
    });

    testWidgets('sans historique : le champ fonctionne normalement', (tester) async {
      await pomper(tester);

      await tester.enterText(find.byType(TextFormField), 'coins');
      await tester.pump();

      expect(find.text(l10n.reserveNouvSuggestionsTitre), findsNothing);
      expect(controleur.text, 'coins');
    });

    testWidgets('la suggestion ne remplace que la phrase en cours', (tester) async {
      await pomper(tester, historique: ['coins casse']);

      await tester.enterText(find.byType(TextFormField), 'client VIP. coi');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('suggestion-coins casse')));
      await tester.pump();

      expect(controleur.text, 'client VIP. coins casse');
    });

    testWidgets('pas de suggestions pendant l’écoute', (tester) async {
      await pomper(tester, historique: ['coins casse']);
      await tester.enterText(find.byType(TextFormField), 'coi');
      await tester.pump();

      await dicter(tester);

      expect(find.byKey(const ValueKey('suggestion-coins casse')), findsNothing);
    });
  });

  test('codes d’erreur natifs → message', () {
    expect(erreurDicteeDepuisCode('error_no_match'), ErreurDictee.aucuneParole);
    expect(erreurDicteeDepuisCode('error_speech_timeout'), ErreurDictee.aucuneParole);
    expect(erreurDicteeDepuisCode('error_permission'), ErreurDictee.microRefuse);
    expect(erreurDicteeDepuisCode('error_insufficient_permissions'), ErreurDictee.microRefuse);
    expect(erreurDicteeDepuisCode('error_network'), ErreurDictee.reseau);
    expect(erreurDicteeDepuisCode('error_busy'), ErreurDictee.interrompue);
  });
}
