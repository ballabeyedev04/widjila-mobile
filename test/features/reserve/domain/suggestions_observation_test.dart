import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/suggestions_observation.dart';

/// Logique du champ « Observation » : suggestions et ajout de la dictée.
void main() {
  group('joindreDictee — la dictée s’ajoute, elle ne remplace jamais', () {
    test('« client VIP » + « livraison demain » → « client VIP livraison demain »', () {
      expect(joindreDictee('client VIP', 'livraison demain'), 'client VIP livraison demain');
    });

    test('champ vide : le texte dicté seul', () {
      expect(joindreDictee('', 'client demande livraison demain'), 'client demande livraison demain');
    });

    test('dictée vide : le texte existant intact', () {
      expect(joindreDictee('client VIP', '   '), 'client VIP');
    });

    test('espaces en fin de texte : un seul espace de séparation', () {
      expect(joindreDictee('client VIP   ', 'livraison'), 'client VIP livraison');
    });

    test('un retour à la ligne volontaire est conservé', () {
      expect(joindreDictee('client VIP\n', 'livraison'), 'client VIP\nlivraison');
    });
  });

  group('suggestionsObservation', () {
    const historique = ['coins casse', 'fissure plafond', 'Joint de carrelage à reprendre'];

    test('« coi » propose « coins casse », et seulement elle', () {
      expect(suggestionsObservation(historique, 'coi'), ['coins casse']);
    });

    test('insensible à la casse et aux accents', () {
      expect(suggestionsObservation(['Coins cassés'], 'COINS CASSES'), isEmpty,
          reason: 'identique à la saisie : rien à proposer');
      expect(suggestionsObservation(['Coins cassés'], 'COINS CAS'), ['Coins cassés']);
      expect(suggestionsObservation(['Joint à reprendre'], 'joint a'), ['Joint à reprendre']);
    });

    test('pertinente : un mot saisi doit être le DÉBUT d’un mot de l’observation', () {
      expect(suggestionsObservation(historique, 'carrel'), ['Joint de carrelage à reprendre']);
      expect(suggestionsObservation(historique, 'ssure'), isEmpty);
    });

    test('aucune suggestion ne correspond : liste vide', () {
      expect(suggestionsObservation(historique, 'peinture'), isEmpty);
    });

    test('moins de deux caractères : rien (pas tout l’historique)', () {
      expect(suggestionsObservation(historique, 'c'), isEmpty);
      expect(suggestionsObservation(historique, ''), isEmpty);
    });

    test('sans doublon (casse, accents, espaces près)', () {
      expect(
        suggestionsObservation(['coins cassés', 'Coins  CASSES', 'coins casses'], 'coi'),
        ['coins cassés'],
      );
    });

    test('celles qui COMMENCENT par la saisie d’abord, et au plus quatre', () {
      final beaucoup = ['mur fissuré', 'fissure 1', 'fissure 2', 'fissure 3', 'fissure 4', 'fissure 5'];
      final s = suggestionsObservation(beaucoup, 'fis');

      expect(s, hasLength(4));
      expect(s.first, 'fissure 1');
      expect(s, isNot(contains('mur fissuré')));
    });
  });

  group('phrase en cours', () {
    test('une suggestion ne remplace que la phrase en cours', () {
      expect(remplacerFragment('client VIP. coi', 'coins casse'), 'client VIP. coins casse');
      expect(remplacerFragment('ligne 1\ncoi', 'coins casse'), 'ligne 1\ncoins casse');
      expect(remplacerFragment('coi', 'coins casse'), 'coins casse');
    });

    test('le fragment suit le dernier séparateur de phrase', () {
      expect(fragmentEnCours('a. b; c').fragment, 'c');
      expect(fragmentEnCours('sans séparateur').fragment, 'sans séparateur');
    });
  });

  group('memoriserObservation', () {
    test('en tête, sans doublon, bornée', () {
      // « Coins cassé » remplace « coins casse » (même observation, accent près)
      // et passe en tête.
      final h = memoriserObservation(['fissure', 'coins casse'], 'Coins cassé', max: 3);
      expect(h, ['Coins cassé', 'fissure']);

      expect(memoriserObservation(['coins casse'], 'COINS CASSE'), ['COINS CASSE']);
      expect(memoriserObservation(['a', 'b', 'c'], 'd', max: 3), ['d', 'a', 'b']);
    });

    test('ignore les observations vides ou trop longues', () {
      expect(memoriserObservation(['a'], '   '), ['a']);
      expect(memoriserObservation(['a'], 'x' * 400), ['a']);
    });
  });
}
