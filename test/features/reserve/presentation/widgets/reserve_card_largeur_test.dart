import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/features/reserve/presentation/widgets/reserve_card.dart';

import '../../../../helpers/l10n_test_helpers.dart';

/// Combien de place reste-t-il au TEXTE d'une carte de réserve ?
///
/// Écrit en réponse à un écran observé sur téléphone : la liste montrait des
/// cartes complètes — liseré, vignette, pastille de statut, bouton « Détail » —
/// mais le titre, le chantier et la ligne auteur/date étaient illisibles,
/// réduits à quelques pixels.
///
/// Aucun test existant ne pouvait le voir :
///
///   - le balayage des formats ne guette qu'un `RenderFlex overflowed`, et une
///     colonne `Expanded` qui s'écrase ne déborde pas — elle rétrécit en
///     silence ;
///   - `find.text` trouve un texte présent dans l'ARBRE, qu'il soit large de
///     200 px ou de 3 px.
///
/// On mesure donc la largeur RÉELLEMENT PEINTE du titre.
void main() {
  Map<String, dynamic> jsonServeur({String statut = 'prise_en_charge'}) => {
        'id': '11111111-1111-4111-8111-111111111111',
        'numero': 'R-0007',
        'chantierId': '22222222-2222-4222-8222-222222222222',
        'titre': 'Infiltration en sous-sol du bâtiment A',
        'severite': 'haute',
        'categorie': 'etancheite',
        'statut': statut,
        'createdAt': '2026-08-20T09:30:00.000Z',
        'chantier': {'id': '22222222-2222-4222-8222-222222222222', 'nom': 'Résidence Les Tilleuls'},
        'createur': {'id': '33333333-3333-4333-8333-333333333333', 'nom': 'Diop', 'prenom': 'Moussa'},
        'medias': <dynamic>[],
      };

  /// Largeur peinte du titre de la carte.
  Future<double> largeurDuTitre(
    WidgetTester tester, {
    required Size ecran,
    String statut = 'prise_en_charge',
  }) async {
    tester.view.physicalSize = ecran;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: testLocale,
        localizationsDelegates: testLocalizationsDelegates,
        supportedLocales: testSupportedLocales,
        home: Scaffold(
          body: Padding(
            // Les marges réelles des deux listes de réserves.
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ReserveCard(
              reserve: Reserve.fromJson(jsonServeur(statut: statut)),
              avecChantier: true,
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return tester
        .renderObject<RenderBox>(find.text('Infiltration en sous-sol du bâtiment A'))
        .size
        .width;
  }

  group('la carte laisse une place lisible au texte', () {
    // 320 dp : petit Android encore courant sur les chantiers.
    testWidgets('sur un petit téléphone (320 dp)', (tester) async {
      final largeur = await largeurDuTitre(tester, ecran: const Size(320, 640));

      // Seuil délibérément bas : on ne juge pas l'esthétique, on constate que
      // le titre n'est pas réduit à un moignon. En dessous, la carte est
      // illisible — c'est le défaut rapporté.
      expect(largeur, greaterThan(100));
    });

    testWidgets('avec le statut au libellé le plus long', (tester) async {
      // La pastille de statut n'avait ni largeur maximale ni troncature : son
      // libellé fixait à lui seul la largeur de la colonne de droite, et
      // prenait cette place au texte.
      final court = await largeurDuTitre(tester, ecran: const Size(360, 640), statut: 'creee');
      final long = await largeurDuTitre(tester, ecran: const Size(360, 640), statut: 'prise_en_charge');

      // Le titre ne doit pas se rétracter parce qu'une réserve a changé de
      // statut : deux réserves côte à côte dans la même liste seraient alors
      // cadrées différemment.
      expect((court - long).abs(), lessThan(1.0));
    });

    testWidgets('sur un téléphone standard (390 dp)', (tester) async {
      final largeur = await largeurDuTitre(tester, ecran: const Size(390, 844));
      expect(largeur, greaterThan(150));
    });
  });
}
