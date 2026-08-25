import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/entities/chantier.dart';

void main() {
  // Même raison d'être que le round-trip de `Reserve` : `toJson` alimente
  // `CacheChantiers`, la relecture hors ligne passe par `fromJson`. Un champ
  // oublié dans l'un des deux se manifesterait uniquement hors ligne, jamais
  // en usage connecté — donc jamais repéré sans ce test.
  group('Chantier — round-trip toJson/fromJson', () {
    test('un chantier complet (liste, avec statistiques) survit au round-trip', () {
      final original = Chantier.fromJson({
        'id': 'c1',
        'code': 'CH-001',
        'nom': 'Résidence Les Ormes',
        'description': 'Construction de 40 logements',
        'adresse': '12 rue des Ormes',
        'date_debut': '2026-01-15T00:00:00.000Z',
        'date_fin': '2027-06-30T00:00:00.000Z',
        'statut': 'en_cours',
        'responsable': {'id': 'u1', 'nom': 'Diop', 'prenom': 'Awa', 'email': 'awa@test.com'},
        'reservesStats': {'total': 42, 'ouvertes': 7},
      });

      final reconstruit = Chantier.fromJson(original.toJson());

      expect(reconstruit, original);
      expect(reconstruit.responsable?.nomComplet, 'Awa Diop');
      expect(reconstruit.reservesTotal, 42);
      expect(reconstruit.reservesOuvertes, 7);
    });

    test('un chantier minimal (détail, sans statistiques ni responsable) survit au round-trip', () {
      final original = Chantier.fromJson({'id': 'c2', 'nom': 'Chantier nu', 'statut': 'en_preparation'});
      final reconstruit = Chantier.fromJson(original.toJson());

      expect(reconstruit, original);
      expect(reconstruit.responsable, isNull);
      expect(reconstruit.reservesTotal, isNull);
      // `reservesStats` ne doit PAS apparaître dans le JSON si les deux
      // champs sont absents — un objet vide romprait la distinction entre
      // « pas encore chargé » et « chargé, zéro réserve ».
      expect(original.toJson().containsKey('reservesStats'), isFalse);
    });
  });
}
