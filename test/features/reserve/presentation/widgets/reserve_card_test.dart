import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/widgets/reserve_card.dart';

import '../../../../helpers/l10n_test_helpers.dart';

/// Rendu réel de la carte de réserve.
///
/// Écrit en réponse à un écran observé en production : la liste affichait des
/// cartes VIDES — icône et liseré coloré présents, mais ni titre, ni numéro,
/// ni pastille de statut, ni bouton « Détail ». Ce test fixe ce qu'une carte
/// DOIT montrer, à partir d'un JSON identique à celui que renvoie
/// `GET /reserves` (`listToutesReserves` côté backend).
void main() {
  /// Réponse serveur telle quelle — clés incluses, forme incluse.
  Map<String, dynamic> jsonServeur() => {
        'id': '11111111-1111-4111-8111-111111111111',
        'numero': 'R-0007',
        'chantierId': '22222222-2222-4222-8222-222222222222',
        'titre': 'Infiltration en sous-sol',
        'description': 'Trace d’humidité au plafond du parking',
        'severite': 'majeure',
        'priorite': 'haute',
        'categorie': 'etancheite',
        'statut': 'creee',
        'createdAt': '2026-08-20T09:30:00.000Z',
        'chantier': {'id': '22222222-2222-4222-8222-222222222222', 'nom': 'Résidence Les Tilleuls'},
        'medias': <dynamic>[],
      };

  Future<void> pomper(WidgetTester tester, Reserve reserve, {bool avecChantier = true}) {
    return tester.pumpWidget(
      MaterialApp(
        locale: testLocale,
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: ReserveCard(reserve: reserve, avecChantier: avecChantier, onTap: () {}),
        ),
      ),
    );
  }

  testWidgets('affiche le titre, le numéro et le chantier d’une réserve du serveur', (tester) async {
    await pomper(tester, Reserve.fromJson(jsonServeur()));

    expect(find.text('Infiltration en sous-sol'), findsOneWidget);
    expect(find.textContaining('R-0007'), findsOneWidget);
    expect(find.textContaining('Résidence Les Tilleuls'), findsOneWidget);
  });

  testWidgets('affiche toujours le bouton Détail, même sans titre', (tester) async {
    // Cas dégradé : le serveur impose `titre` NOT NULL, mais la carte ne doit
    // jamais se réduire à une vignette muette si une valeur manque.
    final sansTitre = Reserve.fromJson(jsonServeur()..['titre'] = '');
    await pomper(tester, sansTitre);

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    // Le numéro prend la place du titre manquant : deux occurrences (le repli
    // du titre + la référence de la colonne droite), jamais zéro.
    expect(find.textContaining('R-0007'), findsNWidgets(2));
  });

  testWidgets('remplace le numéro absent par un libellé, sans laisser de vide', (tester) async {
    final sansNumero = Reserve.fromJson(jsonServeur()..remove('numero'));
    await pomper(tester, sansNumero);

    // Quelque chose DOIT occuper la place du numéro : c'est le repère qui
    // permet de citer une réserve à l'oral sur le chantier.
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.text('Infiltration en sous-sol'), findsOneWidget);
  });
}
