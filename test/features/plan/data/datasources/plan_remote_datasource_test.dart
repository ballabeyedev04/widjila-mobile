import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/plan/data/datasources/plan_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/plan/domain/entities/plan.dart';

import '../../../../helpers/dio_espion.dart';

/// L'API Plan.
///
/// ## Le nom du champ de fichier
///
/// Le serveur lit le fichier sous le nom `fichier`
/// (`upload.single('fichier')`). Un autre nom ne provoque pas d'erreur de
/// transport : la requête part, arrive, et le serveur répond simplement
/// « aucun fichier reçu ». Le dépôt échoue sans que rien, côté mobile,
/// n'indique pourquoi.
///
/// ## Deux listes qui ne sont pas la même
///
/// `/plans` traverse tous les chantiers accessibles au compte ;
/// `/chantiers/:id/plans` s'en tient à un seul. Les confondre remplirait
/// l'écran d'un chantier avec les plans de tous les autres — ou le laisserait
/// vide.
void main() {
  late DioEspion espion;
  late PlanRemoteDataSourceImpl source;
  late Directory dossier;

  setUp(() {
    espion = DioEspion();
    source = PlanRemoteDataSourceImpl(dio: dioDeTest(espion));
    dossier = Directory.systemTemp.createTempSync('plans_test');
  });

  tearDown(() => dossier.deleteSync(recursive: true));

  /// Un fichier réel sur disque — `MultipartFile.fromFile` le lit vraiment.
  String fichierTemporaire(String nom) {
    final f = File('${dossier.path}${Platform.pathSeparator}$nom')
      ..writeAsBytesSync(List<int>.filled(64, 0));
    return f.path;
  }

  Map<String, dynamic> planJson(String id) => {
        'id': id,
        'chantierId': 'c1',
        'nom': 'Niveau R+2',
        'fichier_url': 'https://exemple.test/$id.pdf',
      };

  group('listes', () {
    test('la liste globale n’est pas celle d’un chantier', () async {
      espion.repond({
        'success': true,
        'data': {
          'plans': [planJson('p1')],
        },
      });

      await source.getTousPlans();

      expect(espion.appel, 'GET /plans');
    });

    test('la liste d’un chantier passe par son chemin', () async {
      espion.repond({
        'success': true,
        'data': {
          'plans': [planJson('p1')],
        },
      });

      final plans = await source.getPlansChantier('c1');

      expect(espion.appel, 'GET /chantiers/c1/plans');
      expect(plans, hasLength(1));
    });

    test('la fiche d’un plan est lue sous l’enveloppe « plan »', () async {
      espion.repond({
        'success': true,
        'data': {'plan': planJson('p1')},
      });

      final plan = await source.getPlanDetail('p1');

      expect(espion.appel, 'GET /plans/p1');
      expect(plan.nom, 'Niveau R+2');
    });
  });

  group('dépôt', () {
    test('le fichier part sous le nom attendu par le serveur', () async {
      espion.repond({
        'success': true,
        'data': {'plan': planJson('p9')},
      });

      await source.uploaderPlan(
        chantierId: 'c1',
        cheminFichier: fichierTemporaire('plan.pdf'),
        nom: 'Niveau R+2',
      );

      expect(espion.appel, 'POST /chantiers/c1/plans');
      final formulaire = espion.requete.data as FormData;
      // `fichier` — un autre nom ferait répondre « aucun fichier reçu ».
      expect(formulaire.files.map((e) => e.key), contains('fichier'));
      expect(
        formulaire.fields.firstWhere((e) => e.key == 'nom').value,
        'Niveau R+2',
      );
    });

    test('un plan SANS localisation ne porte aucun des trois identifiants',
        () async {
      // Aucun des trois : le plan est le plan GLOBAL du chantier. Envoyer un
      // identifiant vide le rattacherait à un niveau inexistant.
      espion.repond({
        'success': true,
        'data': {'plan': planJson('p9')},
      });

      await source.uploaderPlan(
        chantierId: 'c1',
        cheminFichier: fichierTemporaire('plan.pdf'),
        nom: 'Plan de masse',
        batimentId: '',
        etageId: '',
        zoneId: '',
      );

      final cles = (espion.requete.data as FormData).fields.map((e) => e.key);
      expect(cles, isNot(contains('batimentId')));
      expect(cles, isNot(contains('etageId')));
      expect(cles, isNot(contains('zoneId')));
    });

    test('le niveau décrit est transmis quand il est fourni', () async {
      espion.repond({
        'success': true,
        'data': {'plan': planJson('p9')},
      });

      await source.uploaderPlan(
        chantierId: 'c1',
        cheminFichier: fichierTemporaire('plan.pdf'),
        nom: 'Niveau R+2',
        etageId: 'e1',
        format: PlanFormat.pdf,
      );

      final champs = (espion.requete.data as FormData).fields;
      expect(champs.firstWhere((e) => e.key == 'etageId').value, 'e1');
      expect(champs.firstWhere((e) => e.key == 'format').value, PlanFormat.pdf.raw);
    });
  });
}
