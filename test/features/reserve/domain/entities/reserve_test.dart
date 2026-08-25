import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';
import 'package:suivie_chantier_mobile/l10n/generated/app_localizations.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('fr'));
  });

  group('ReserveStatutX', () {
    test('fromString/raw font l\'aller-retour pour chaque statut backend', () {
      const valeursBrutes = [
        'creee', 'affectee', 'prise_en_charge', 'en_cours', 'corrigee', 'a_verifier',
        'validee', 'refusee', 'rouverte', 'en_retard', 'cloturee',
      ];
      for (final brut in valeursBrutes) {
        expect(ReserveStatutX.fromString(brut).raw, brut, reason: 'round-trip pour "$brut"');
      }
    });

    test('fromString retombe sur "creee" pour une valeur inconnue/nulle', () {
      expect(ReserveStatutX.fromString(null), ReserveStatut.creee);
      expect(ReserveStatutX.fromString('statut_inexistant'), ReserveStatut.creee);
    });
  });

  group('Reserve.fromJson', () {
    test('parse une réserve complète (détail)', () {
      final json = {
        'id': 'r1',
        'numero': 'R-0001',
        'chantierId': 'c1',
        'titre': 'Fissure mur',
        'description': 'Fissure visible côté cour',
        'severite': 'haute',
        'priorite': 'critique',
        'categorie': 'gros_oeuvre',
        'statut': 'en_cours',
        'date_limite': '2026-09-01',
        'createdAt': '2026-08-01T10:00:00.000Z',
        'batiment': {'id': 'b1', 'nom': 'Bâtiment A'},
        'etage': {'id': 'e1', 'nom': 'Étage 2'},
        'assigne': {'id': 'u1', 'nom': 'Diop', 'prenom': 'Awa'},
        'medias': [
          {'id': 'm1', 'type': 'photo', 'url': 'https://cdn.test/photo.jpg'},
        ],
        'historiques': [
          {'id': 'h1', 'action': 'creation', 'createdAt': '2026-08-01T10:00:00.000Z'},
        ],
      };

      final reserve = Reserve.fromJson(json);

      expect(reserve.id, 'r1');
      expect(reserve.numero, 'R-0001');
      expect(reserve.titre, 'Fissure mur');
      expect(reserve.statut, ReserveStatut.enCours);
      expect(reserve.severite, ReserveSeverite.haute);
      expect(reserve.priorite, ReserveSeverite.critique);
      expect(reserve.categorie, ReserveCategorie.grosOeuvre);
      expect(reserve.localisationLabel(l10n), 'Bâtiment A · Étage 2');
      expect(reserve.assigne?.nomComplet, 'Awa Diop');
      expect(reserve.medias, hasLength(1));
      expect(reserve.photoApercu, 'https://cdn.test/photo.jpg');
      expect(reserve.historiques, hasLength(1));
      expect(reserve.historiques.first.libelle(l10n), 'Réserve créée');
    });

    test('valeurs par défaut sûres quand les champs optionnels sont absents (liste)', () {
      final json = {'id': 'r2', 'numero': 'R-0002', 'titre': 'Sans localisation'};
      final reserve = Reserve.fromJson(json);

      expect(reserve.localisationLabel(l10n), 'Non localisée');
      expect(reserve.statut, ReserveStatut.creee);
      expect(reserve.medias, isEmpty);
      expect(reserve.photoApercu, isNull);
    });
  });

  // `toJson` alimente le cache local hors ligne (voir `CacheReserves`) : une
  // réserve écrite en cache doit se relire IDENTIQUE, sans perte de champ.
  // C'est ce round-trip que ces tests verrouillent — écrit à la main, il est
  // le point le plus probable d'une divergence silencieuse entre une clé de
  // `toJson` et celle attendue par `fromJson`.
  group('Reserve.toJson — round-trip avec fromJson', () {
    test('une réserve complète (détail) survit à un aller-retour JSON', () {
      final original = Reserve.fromJson({
        'id': 'r1',
        'numero': 'R-0001',
        'chantierId': 'c1',
        'titre': 'Fissure mur',
        'description': 'Fissure visible côté cour',
        'severite': 'haute',
        'priorite': 'critique',
        'categorie': 'gros_oeuvre',
        'statut': 'en_cours',
        'date_limite': '2026-09-01',
        'createdAt': '2026-08-01T10:00:00.000Z',
        'batiment': {'id': 'b1', 'nom': 'Bâtiment A'},
        'etage': {'id': 'e1', 'nom': 'Étage 2'},
        'zone': {'id': 'z1', 'nom': 'Zone nord'},
        'lot': {'id': 'l1', 'nom': 'Lot 3'},
        'entreprise': {'id': 'ent1', 'nom': 'Entreprise X'},
        'chantier': {'id': 'c1', 'nom': 'Résidence Y'},
        'assigne': {'id': 'u1', 'nom': 'Diop', 'prenom': 'Awa'},
        'createur': {'id': 'u2', 'nom': 'Ba', 'prenom': 'Modou'},
        'motif_refus': 'Non conforme',
        'medias': [
          {'id': 'm1', 'type': 'photo', 'url': 'https://cdn.test/photo.jpg', 'thumbnail_url': 'https://cdn.test/t.jpg', 'pris_le': '2026-08-01T11:00:00.000Z'},
        ],
        'historiques': [
          {'id': 'h1', 'action': 'creation', 'createdAt': '2026-08-01T10:00:00.000Z', 'utilisateur': {'id': 'u2', 'nom': 'Ba', 'prenom': 'Modou'}},
        ],
      });

      final reconstruite = Reserve.fromJson(original.toJson());

      expect(reconstruite, original, reason: 'Equatable compare TOUS les champs déclarés dans props');
      // Les sous-objets doivent eux aussi survivre, pas seulement les champs
      // scalaires portés directement par Reserve.
      expect(reconstruite.batiment?.nom, 'Bâtiment A');
      expect(reconstruite.medias.single.thumbnailUrl, 'https://cdn.test/t.jpg');
      expect(reconstruite.historiques.single.utilisateur?.nomComplet, 'Modou Ba');
    });

    test('une réserve minimale (champs optionnels absents) survit au round-trip', () {
      final original = Reserve.fromJson({'id': 'r2', 'numero': 'R-0002', 'titre': 'Minimale'});
      final reconstruite = Reserve.fromJson(original.toJson());
      expect(reconstruite, original);
    });
  });

  group('Reserve.copierAvecStatut', () {
    test('change uniquement le statut, tout le reste est préservé', () {
      final original = Reserve.fromJson({
        'id': 'r1', 'numero': 'R-0001', 'titre': 'Fissure', 'statut': 'creee',
        'assigne': {'id': 'u1', 'nom': 'Diop', 'prenom': 'Awa'},
      });

      final maj = original.copierAvecStatut(ReserveStatut.enCours);

      expect(maj.statut, ReserveStatut.enCours);
      expect(maj.id, original.id);
      expect(maj.titre, original.titre);
      expect(maj.assigne, original.assigne);
      // L'original, lui, ne doit pas être modifié — copierAvecStatut renvoie
      // une NOUVELLE instance.
      expect(original.statut, ReserveStatut.creee);
    });
  });
}
