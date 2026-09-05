import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/features/reserve/data/datasources/reserve_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/reserve/domain/entities/reserve.dart';

import '../../../../helpers/dio_espion.dart';

/// L'API Réserve — la plus large de l'application, et la plus exposée.
///
/// ## Pourquoi elle mérite le plus de tests
///
/// C'est la seule API que l'utilisateur alimente DEPUIS le chantier, souvent
/// hors ligne, souvent d'une main. Ses corps de requête portent des
/// énumérations (statut, gravité, catégorie) dont le mobile et le serveur ne
/// partagent pas l'écriture : `enCours` côté Dart, `en_cours` côté serveur.
/// Une conversion oubliée passe l'analyse, part sur le réseau, et revient en
/// 400 — sur un relevé qu'il faut refaire.
///
/// Le second point est la POSITION sur plan : le serveur exige le couple
/// (x, y). En envoyer un seul décrirait un point qui n'existe pas.
void main() {
  late DioEspion espion;
  late ReserveRemoteDataSourceImpl source;

  setUp(() {
    espion = DioEspion();
    source = ReserveRemoteDataSourceImpl(dio: dioDeTest(espion));
  });

  Map<String, dynamic> reserveJson(String id) => {
        'id': id,
        'numero': 'R-001',
        'chantierId': 'c1',
        'titre': 'Fissure mur nord',
        'statut': 'creee',
        'severite': 'moyenne',
      };

  group('listes', () {
    test('les réserves d’un chantier passent par le chemin du chantier', () async {
      espion.repond({
        'success': true,
        'data': {
          'reserves': [reserveJson('r1')],
          'total': 12,
        },
      });

      final page = await source.getReserves(chantierId: 'c1', page: 2, limit: 20);

      expect(espion.appel, 'GET /chantiers/c1/reserves');
      expect(espion.requete.queryParameters['page'], 2);
      expect(page.total, 12);
    });

    test('la liste GLOBALE a sa propre route, sans chantier', () async {
      // Ce n'est pas la même donnée : la route globale traverse tous les
      // chantiers auxquels le compte a accès. La confondre avec la liste
      // d'un chantier donnerait un onglet « Toutes les réserves » vide.
      espion.repond({
        'success': true,
        'data': {'reserves': <dynamic>[], 'total': 0},
      });

      await source.getToutesReserves();

      expect(espion.appel, 'GET /reserves');
    });

    test('le filtre de statut part sous l’écriture du serveur', () async {
      espion.repond({
        'success': true,
        'data': {'reserves': <dynamic>[], 'total': 0},
      });

      await source.getToutesReserves(statut: ReserveStatut.enCours);

      expect(espion.requete.queryParameters['statut'], ReserveStatut.enCours.raw);
      expect(espion.requete.queryParameters['statut'], isNot('enCours'));
    });

    test('une recherche vide n’est pas envoyée', () async {
      espion.repond({
        'success': true,
        'data': {'reserves': <dynamic>[], 'total': 0},
      });

      await source.getToutesReserves(search: '');

      expect(espion.requete.queryParameters.containsKey('search'), isFalse);
    });
  });

  group('création', () {
    test('la position sur plan part en COUPLE, jamais seule', () async {
      espion.repond({
        'success': true,
        'data': {'reserve': reserveJson('r9')},
      });

      await source.creerReserve(
        chantierId: 'c1',
        titre: 'Fissure',
        priorite: ReserveSeverite.critique,
        categorie: ReserveCategorie.autre,
        planId: 'p1',
        positionX: 0.42,
        positionY: 0.67,
      );

      expect(espion.appel, 'POST /chantiers/c1/reserves');
      final position = (espion.requete.data as Map<String, dynamic>)['position']
          as Map<String, dynamic>;
      expect(position['x'], 0.42);
      expect(position['y'], 0.67);
    });

    test('une seule coordonnée n’envoie AUCUNE position', () async {
      // Un point à moitié défini n'est pas un point. Le serveur exige le
      // couple ; envoyer la moitié reviendrait à provoquer un 400 sur un
      // relevé par ailleurs valable.
      espion.repond({
        'success': true,
        'data': {'reserve': reserveJson('r9')},
      });

      await source.creerReserve(
        chantierId: 'c1',
        titre: 'Fissure',
        priorite: ReserveSeverite.moyenne,
        categorie: ReserveCategorie.autre,
        positionX: 0.42,
      );

      expect((espion.requete.data as Map<String, dynamic>).containsKey('position'), isFalse);
    });

    test('la gravité non precisee retombe sur la priorite', () async {
      espion.repond({
        'success': true,
        'data': {'reserve': reserveJson('r9')},
      });

      await source.creerReserve(
        chantierId: 'c1',
        titre: 'Fissure',
        priorite: ReserveSeverite.critique,
        categorie: ReserveCategorie.autre,
      );

      final corps = espion.requete.data as Map<String, dynamic>;
      expect(corps['priorite'], ReserveSeverite.critique.raw);
      expect(corps['severite'], ReserveSeverite.critique.raw);
    });

    test('l’échéance part en DATE seule', () async {
      espion.repond({
        'success': true,
        'data': {'reserve': reserveJson('r9')},
      });

      await source.creerReserve(
        chantierId: 'c1',
        titre: 'Fissure',
        priorite: ReserveSeverite.moyenne,
        categorie: ReserveCategorie.autre,
        dateLimite: DateTime(2026, 11, 5),
      );

      expect((espion.requete.data as Map<String, dynamic>)['date_limite'], '2026-11-05');
    });

    test('un identifiant fourni est transmis — la reprise hors ligne en depend',
        () async {
      // Une réserve créée hors ligne porte déjà son identifiant local. Le
      // renvoyer permet au serveur de reconnaître un doublon si la
      // synchronisation repart deux fois.
      espion.repond({
        'success': true,
        'data': {'reserve': reserveJson('local-1')},
      });

      await source.creerReserve(
        chantierId: 'c1',
        id: 'local-1',
        titre: 'Fissure',
        priorite: ReserveSeverite.moyenne,
        categorie: ReserveCategorie.autre,
      );

      expect((espion.requete.data as Map<String, dynamic>)['id'], 'local-1');
    });
  });

  group('changement de statut', () {
    test('utilise PATCH, avec le statut sous l’écriture du serveur', () async {
      espion.repond({
        'success': true,
        'data': {'reserve': reserveJson('r1')},
      });

      await source.changerStatut(reserveId: 'r1', statut: ReserveStatut.validee);

      expect(espion.appel, 'PATCH /reserves/r1/statut');
      expect((espion.requete.data as Map<String, dynamic>)['statut'],
          ReserveStatut.validee.raw);
    });

    test('un motif vide n’est pas envoyé', () async {
      espion.repond({
        'success': true,
        'data': {'reserve': reserveJson('r1')},
      });

      await source.changerStatut(
          reserveId: 'r1', statut: ReserveStatut.validee, motif: '');

      expect((espion.requete.data as Map<String, dynamic>).containsKey('motif'), isFalse);
    });
  });

  group('collaboration', () {
    test('les commentaires sont lus et écrits sur la même route', () async {
      espion.repond({
        'success': true,
        'data': {'commentaires': <dynamic>[]},
      });

      await source.getCommentaires('r1');
      expect(espion.appel, 'GET /reserves/r1/commentaires');
    });

    test('retirer une affectation vise les DEUX identifiants', () async {
      espion.repond({'success': true, 'data': <String, dynamic>{}});

      await source.retirerAffectation('r1', 'a1');

      expect(espion.appel, 'DELETE /reserves/r1/affectations/a1');
    });
  });

  group('agrégats', () {
    test('l’évolution vient du tableau de bord, pas des réserves', () async {
      // Deux modules distincts côté serveur : la série mensuelle est
      // calculée par le tableau de bord.
      espion.repond({
        'success': true,
        'data': {
          'stats': {
            'series': [
              {'mois': '2026-01', 'creees': 4, 'validees': 1},
            ],
          },
        },
      });

      final evolution = await source.getEvolution('c1');

      expect(espion.appel, 'GET /dashboard/chantiers/c1/evolution');
      expect(evolution.series, hasLength(1));
      expect(evolution.series.first.mois, '2026-01');
      expect(evolution.series.first.creees, 4);
    });

    test('la structure d’un chantier vient de sa fiche', () async {
      espion.repond({
        'success': true,
        'data': {
          'chantier': {'id': 'c1', 'nom': 'Les Cedres', 'batiments': <dynamic>[]},
        },
      });

      await source.getStructure('c1');

      expect(espion.appel, 'GET /chantiers/c1');
    });
  });

  group('refus', () {
    test('un 404 ressort en exception serveur', () async {
      espion.repondErreur(404, corps: {
        'success': false,
        'message': 'Réserve introuvable',
      });

      await expectLater(
        source.getReserveDetail('inexistante'),
        throwsA(isA<ServerException>()),
      );
    });
  });
}
