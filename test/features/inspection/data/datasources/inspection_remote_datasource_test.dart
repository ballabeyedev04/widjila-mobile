import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/inspection/data/datasources/inspection_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/inspection/domain/entities/inspection.dart';

import '../../../../helpers/dio_espion.dart';

/// L'API Inspection.
///
/// ## Le type d'inspection n'est PAS une énumération
///
/// Il vient du référentiel administrable (`/types-inspection/actifs`). Le
/// figer en énumération côté mobile empêcherait d'utiliser un type ajouté par
/// l'administrateur du client — ce qui est précisément la raison d'être d'un
/// référentiel administrable. Le datasource envoie donc un CODE brut, et ce
/// test le fige.
///
/// ## La date de visite
///
/// `date_visite` est un `DATEONLY` côté serveur. Envoyer un instant complet
/// fait basculer la visite d'un jour selon l'heure de saisie et le fuseau :
/// une inspection planifiée le lundi à 23 h s'enregistre au dimanche.
void main() {
  late DioEspion espion;
  late InspectionRemoteDataSourceImpl source;

  setUp(() {
    espion = DioEspion();
    source = InspectionRemoteDataSourceImpl(dio: dioDeTest(espion));
  });

  Map<String, dynamic> inspectionJson(String id) => {
        'id': id,
        'chantierId': 'c1',
        'statut': 'planifiee',
      };

  group('liste', () {
    test('passe par le chemin du chantier', () async {
      espion.repond({
        'success': true,
        'data': {
          'inspections': [inspectionJson('i1')],
        },
      });

      final inspections = await source.getInspections(chantierId: 'c1');

      expect(espion.appel, 'GET /chantiers/c1/inspections');
      expect(inspections, hasLength(1));
    });

    test('sans filtre, aucun paramètre de statut n’est envoyé', () async {
      espion.repond({
        'success': true,
        'data': {'inspections': <dynamic>[]},
      });

      await source.getInspections(chantierId: 'c1');

      expect(espion.requete.queryParameters.containsKey('statut'), isFalse);
    });

    test('le filtre part sous l’écriture du serveur', () async {
      espion.repond({
        'success': true,
        'data': {'inspections': <dynamic>[]},
      });

      await source.getInspections(
          chantierId: 'c1', statut: InspectionStatut.planifiee);

      expect(espion.requete.queryParameters['statut'],
          InspectionStatut.planifiee.raw);
    });
  });

  group('création', () {
    test('le type part en CODE brut, pas en énumération figée', () async {
      // Un type ajouté par l'administrateur du client doit fonctionner sans
      // livraison de l'application.
      espion.repond({
        'success': true,
        'data': {'inspection': inspectionJson('i9')},
      });

      await source.creerInspection(chantierId: 'c1', typeCode: 'reception_partielle');

      expect(espion.appel, 'POST /chantiers/c1/inspections');
      expect((espion.requete.data as Map<String, dynamic>)['type'],
          'reception_partielle');
    });

    test('la date de visite part en DATE seule', () async {
      espion.repond({
        'success': true,
        'data': {'inspection': inspectionJson('i9')},
      });

      // 23 h : converti en instant avec fuseau, ce moment bascule d'un jour.
      await source.creerInspection(
        chantierId: 'c1',
        typeCode: 'inspection',
        dateVisite: DateTime(2026, 6, 15, 23, 0),
      );

      expect((espion.requete.data as Map<String, dynamic>)['date_visite'],
          '2026-06-15');
    });

    test('une checklist vide n’est pas envoyée', () async {
      // Le serveur pose alors sa propre liste par défaut. Lui envoyer un
      // tableau vide la remplacerait par rien.
      espion.repond({
        'success': true,
        'data': {'inspection': inspectionJson('i9')},
      });

      await source.creerInspection(chantierId: 'c1', typeCode: 'inspection');

      expect((espion.requete.data as Map<String, dynamic>).containsKey('checklist'),
          isFalse);
    });

    test('une checklist fournie part en objets, pas en chaînes', () async {
      espion.repond({
        'success': true,
        'data': {'inspection': inspectionJson('i9')},
      });

      await source.creerInspection(
        chantierId: 'c1',
        typeCode: 'inspection',
        libellesChecklist: const ['Etancheite toiture', 'Garde-corps'],
      );

      final checklist =
          (espion.requete.data as Map<String, dynamic>)['checklist'] as List;
      expect(checklist, hasLength(2));
      expect((checklist.first as Map)['libelle'], 'Etancheite toiture');
    });
  });

  test('le changement de statut utilise PUT et le compte rendu en serpent',
      () async {
    espion.repond({
      'success': true,
      'data': {'inspection': inspectionJson('i1')},
    });

    await source.changerStatut(
      id: 'i1',
      statut: InspectionStatut.terminee,
      compteRendu: 'Rien a signaler.',
    );

    expect(espion.appel, 'PUT /inspections/i1');
    final corps = espion.requete.data as Map<String, dynamic>;
    expect(corps['statut'], InspectionStatut.terminee.raw);
    expect(corps['compte_rendu'], 'Rien a signaler.');
  });

  test('cocher une ligne vise l’inspection ET la ligne', () async {
    espion.repond({
      'success': true,
      'data': {
        'ligne': {'id': 'l1', 'libelle': 'Garde-corps', 'coche': true},
      },
    });

    await source.cocherLigne(inspectionId: 'i1', ligneId: 'l1', coche: true);

    expect(espion.appel, 'PATCH /inspections/i1/checklist/l1');
  });

  test('les convocations ont leur propre route', () async {
    espion.repond({
      'success': true,
      'data': {'convocations': <dynamic>[]},
    });

    await source.getConvocations('i1');

    expect(espion.appel, 'GET /inspections/i1/convocations');
  });
}
