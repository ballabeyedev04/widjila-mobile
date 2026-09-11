import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';

/// Le point d'une réserve sur son plan, lu depuis le détail du serveur.
///
/// Sans lui, la fiche ne pouvait que NOMMER le plan (« arkada_13_2np3.jpg »)
/// sans montrer où se trouve le défaut. Et un repère faux est pire qu'un
/// repère absent : il envoie constater un défaut au mauvais endroit — d'où
/// les cas « illisible → pas de repère » ci-dessous.
void main() {
  Map<String, dynamic> detail({Object? position}) => {
        'id': 'r1',
        'numero': 'R-0003',
        'chantierId': 'c1',
        'titre': 'Peinture à refaire',
        'plan': {'id': 'p1', 'nom': 'arkada_13_2np3.jpg', 'version': 3, 'fichier_url': '/uploads/plans/a.jpg'},
        'position': ?position,
      };

  group('ReservePositionRef — lecture', () {
    test('lit x, y et la page du détail', () {
      final r = Reserve.fromJson(detail(position: {'x': 42.5, 'y': 61.25, 'page': 2}));

      expect(r.position, const ReservePositionRef(x: 42.5, y: 61.25, page: 2));
    });

    test('accepte un DECIMAL servi en chaîne', () {
      final r = Reserve.fromJson(detail(position: {'x': '42.50', 'y': '61.25'}));

      expect(r.position?.x, 42.5);
      expect(r.position?.page, 1, reason: 'page absente = page 1');
    });

    test('borne les coordonnées à la page', () {
      final r = Reserve.fromJson(detail(position: {'x': 104, 'y': -3}));

      expect(r.position, const ReservePositionRef(x: 100, y: 0));
    });

    test('point absent ou illisible : AUCUN repère, jamais (0, 0)', () {
      expect(Reserve.fromJson(detail()).position, isNull);
      expect(Reserve.fromJson(detail(position: {'x': null, 'y': 12})).position, isNull);
      expect(Reserve.fromJson(detail(position: 'n/a')).position, isNull);
    });
  });

  group('cache hors ligne', () {
    test('toJson → fromJson garde le repère', () {
      final r = Reserve.fromJson(detail(position: {'x': 10, 'y': 20, 'page': 3}));

      expect(Reserve.fromJson(r.toJson()).position, r.position);
    });
  });

  group('copierAvec — « null = inchangé »', () {
    final origine = Reserve.fromJson({
      ...detail(position: {'x': 10, 'y': 20}),
      'medias': [
        {'id': 'm1', 'type': 'photo', 'url': '/uploads/m1.jpg'},
      ],
      'historiques': [
        {'id': 'h1', 'action': 'creation'},
      ],
    });

    test('un changement de statut garde plan, repère, photos et historique', () {
      final copie = origine.copierAvecStatut(ReserveStatut.enCours);

      expect(copie.statut, ReserveStatut.enCours);
      expect(copie.plan, origine.plan);
      expect(copie.position, origine.position);
      expect(copie.medias, origine.medias);
      expect(copie.historiques, origine.historiques);
      expect(copie.photoApercu, origine.photoApercu);
    });
  });
}
