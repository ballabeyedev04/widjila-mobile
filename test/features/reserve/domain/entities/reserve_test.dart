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
      // Miroir EXACT de `config/enums.js#STATUT_RESERVE` (backend), dans l'ordre.
      const valeursBrutes = [
        'creee', 'affectee', 'prise_en_charge', 'en_cours', 'a_surveiller', 'a_echeance',
        'corrigee', 'traitee', 'a_verifier', 'validee', 'levee', 'refusee', 'rouverte',
        'en_retard', 'cloturee',
      ];
      expect(ReserveStatut.values.map((s) => s.raw).toList(), valeursBrutes,
          reason: 'l\'enum doit suivre l\'ordre du cycle de vie du serveur');
      for (final brut in valeursBrutes) {
        expect(ReserveStatutX.fromString(brut).raw, brut, reason: 'round-trip pour "$brut"');
      }
    });

    test('fromString retombe sur "creee" pour une valeur inconnue/nulle', () {
      expect(ReserveStatutX.fromString(null), ReserveStatut.creee);
      expect(ReserveStatutX.fromString('statut_inexistant'), ReserveStatut.creee);
    });
  });

  group('ReserveHistoriqueEntry — deux formes JSON, une seule lecture', () {
    test('forme NORMALISÉE (GET /reserves/:id/historique)', () {
      final e = ReserveHistoriqueEntry.fromJson({
        'id': 'h1',
        'action': 'validation',
        'date': '2026-09-20T16:48:00.000Z',
        'utilisateur': {'id': 'u1', 'nom': 'Dupont', 'prenom': 'Jean'},
        'changementStatut': true,
        'ancienStatut': 'traitee',
        'nouveauStatut': 'levee',
        'motif': null,
      });

      expect(e.estChangementStatut, isTrue);
      expect(e.ancienStatut, ReserveStatut.traitee);
      expect(e.nouveauStatut, ReserveStatut.levee);
      expect(e.createdAt, DateTime.utc(2026, 9, 20, 16, 48));
      expect(e.utilisateur?.nomComplet, 'Jean Dupont');
    });

    test('forme BRUTE jointe au détail : les statuts sont lus dans les valeurs', () {
      final e = ReserveHistoriqueEntry.fromJson({
        'id': 'h1',
        'action': 'statut',
        'createdAt': '2026-09-18T14:32:00.000Z',
        'anciennes_valeurs': {'statut': 'creee'},
        'nouvelles_valeurs': {'statut': 'a_surveiller'},
        'utilisateur': {'id': 'u1', 'nom': 'BEYE', 'prenom': 'Balla'},
      });

      expect(e.estChangementStatut, isTrue);
      expect(e.ancienStatut, ReserveStatut.creee);
      expect(e.nouveauStatut, ReserveStatut.aSurveiller);
    });

    test('forme brute : la création porte le statut initial, sans ancien', () {
      final e = ReserveHistoriqueEntry.fromJson({
        'id': 'h0',
        'action': 'creation',
        'createdAt': '2026-09-15T08:00:00.000Z',
        'nouvelles_valeurs': {'titre': 'Fissure', 'statut': 'creee'},
      });

      expect(e.estChangementStatut, isTrue);
      expect(e.ancienStatut, isNull);
      expect(e.nouveauStatut, ReserveStatut.creee);
    });

    test('forme brute : un commentaire ou un même statut n’est pas un changement', () {
      final commentaire = ReserveHistoriqueEntry.fromJson({
        'id': 'h2', 'action': 'commentaire', 'nouvelles_valeurs': {'message': 'ok'},
      });
      final identique = ReserveHistoriqueEntry.fromJson({
        'id': 'h3', 'action': 'modification',
        'anciennes_valeurs': {'statut': 'creee'}, 'nouvelles_valeurs': {'statut': 'creee'},
      });

      expect(commentaire.estChangementStatut, isFalse);
      expect(identique.estChangementStatut, isFalse);
      expect(identique.nouveauStatut, isNull);
    });

    test('le motif d’un refus est lu dans les deux formes', () {
      final brute = ReserveHistoriqueEntry.fromJson({
        'id': 'h4', 'action': 'refus',
        'anciennes_valeurs': {'statut': 'traitee'},
        'nouvelles_valeurs': {'statut': 'refusee', 'motif': 'Joint non conforme'},
      });
      final normalisee = ReserveHistoriqueEntry.fromJson({
        'id': 'h4', 'action': 'refus', 'changementStatut': true,
        'ancienStatut': 'traitee', 'nouveauStatut': 'refusee', 'motif': 'Joint non conforme',
      });

      expect(brute.motif, 'Joint non conforme');
      expect(normalisee.motif, 'Joint non conforme');
    });

    test('toJson/fromJson font l’aller-retour (cache hors ligne)', () {
      final e = ReserveHistoriqueEntry(
        id: 'h1',
        action: 'statut',
        createdAt: DateTime.utc(2026, 9, 18, 14, 32),
        utilisateur: const ReserveUtilisateurRef(id: 'u1', nom: 'BEYE', prenom: 'Balla'),
        ancienStatut: ReserveStatut.creee,
        nouveauStatut: ReserveStatut.aSurveiller,
        motif: null,
      );

      expect(ReserveHistoriqueEntry.fromJson(e.toJson()), e);
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

  group('Reserve.estFige — miroir de STATUTS_FIGES', () {
    // Le serveur refuse la modification (`reserve.service.js:907`) comme la
    // suppression (`:1157`) d'une reserve validee ou cloturee. L'ecran de
    // detail ne regardait que le ROLE : la confirmation rouge de suppression
    // s'ouvrait sur un objet que le serveur refuse de supprimer.
    Reserve avecStatut(ReserveStatut statut) => Reserve(
          id: 'r1',
          numero: 'R-0001',
          chantierId: 'c1',
          titre: 'Fissure',
          statut: statut,
        );

    test('validee, levee et cloturee sont figees', () {
      expect(avecStatut(ReserveStatut.validee).estFige, isTrue);
      expect(avecStatut(ReserveStatut.levee).estFige, isTrue);
      expect(avecStatut(ReserveStatut.cloturee).estFige, isTrue);
    });

    test('les familles de statuts suivent le serveur (LEVEES / FERMES)', () {
      expect(ReserveStatut.values.where((s) => s.estLevee), [ReserveStatut.validee, ReserveStatut.levee]);
      expect(ReserveStatut.values.where((s) => s.estFerme),
          [ReserveStatut.validee, ReserveStatut.levee, ReserveStatut.cloturee]);
      // « Traitee » attend le controle : elle n'est pas fermee.
      expect(ReserveStatut.traitee.estFerme, isFalse);
    });

    test('les statuts du client ont chacun un libelle distinct', () {
      final libelles = statutsSuiviClient.map((s) => s.label(l10n)).toList();
      expect(libelles, ['En retard', 'À surveiller', 'À échéance', 'Traitée', 'Refusée', 'Levée']);
      // « Validee » et « levee » ne partagent plus le meme mot.
      expect(ReserveStatut.validee.label(l10n), isNot(ReserveStatut.levee.label(l10n)));
    });

    test('aucun autre statut ne l est', () {
      for (final statut in ReserveStatut.values) {
        if (statut.estFerme) continue;
        expect(avecStatut(statut).estFige, isFalse, reason: 'pour $statut');
      }
    });
  });

  group('Reserve — corps d etat et phase', () {
    // Servis par les deux listes et par le detail
    // (`reserve.service.js:718-719` et `:846-847`), ils n'etaient lus par
    // personne. La phase est pourtant OBLIGATOIRE a la creation : on la
    // faisait choisir sans jamais la restituer.
    Map<String, dynamic> jsonServeur() => {
          'id': 'r1',
          'numero': 'R-0007',
          'chantierId': 'c1',
          'titre': 'Infiltration',
          'statut': 'creee',
          'corpsEtat': {'id': 'ce1', 'nom': 'Plomberie', 'code': 'PLB'},
          'phase': {'id': 'ph1', 'nom': 'Second oeuvre', 'ordre': 2},
          'plan': {'id': 'pl1', 'nom': 'R+2'},
        };

    test('fromJson les lit', () {
      final r = Reserve.fromJson(jsonServeur());

      expect(r.corpsEtat?.nom, 'Plomberie');
      expect(r.phase?.nom, 'Second oeuvre');
    });

    test('toJson les reserialise — le cache hors ligne repasse par la', () {
      final r = Reserve.fromJson(jsonServeur());
      final relu = Reserve.fromJson(r.toJson());

      expect(relu.corpsEtat?.id, 'ce1');
      expect(relu.phase?.id, 'ph1');
    });

    test('copierAvecStatut ne perd ni le plan, ni le metier, ni la phase', () {
      // `plan` n'etait deja pas recopie : une mise a jour optimiste de statut
      // faisait disparaitre de la fiche le plan sur lequel la reserve avait
      // ete relevee, alors que le champ figure dans `props`.
      final copie = Reserve.fromJson(jsonServeur()).copierAvecStatut(ReserveStatut.enCours);

      expect(copie.statut, ReserveStatut.enCours);
      expect(copie.plan?.id, 'pl1');
      expect(copie.corpsEtat?.nom, 'Plomberie');
      expect(copie.phase?.nom, 'Second oeuvre');
    });
  });
}
