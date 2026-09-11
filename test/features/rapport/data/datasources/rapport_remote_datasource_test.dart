import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/rapport/data/datasources/rapport_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/configuration_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/envoi_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/etat_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/modele_rapport.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/rapport.dart';

import '../../../../helpers/dio_espion.dart';

/// L'API Rapports — § 9 du cahier des charges.
///
/// Un datasource fait deux choses que rien d'autre ne vérifie : il compose
/// une requête (verbe, chemin, corps) et relit une réponse. Une faute de
/// chemin ne se voit ni à l'analyse ni à la compilation — elle se voit en
/// production, sous forme de 404 sur un écran vide.
void main() {
  late DioEspion espion;
  late RapportRemoteDataSourceImpl source;

  setUp(() {
    espion = DioEspion();
    source = RapportRemoteDataSourceImpl(dio: dioDeTest(espion));
  });

  /// Un rapport tel que le serveur le rend (`presenter` du contrôleur).
  Map<String, dynamic> rapportJson([Map<String, dynamic> surcharge = const {}]) => {
        'id': 'r9',
        'chantierId': 'c1',
        'type': 'batiment',
        'nom': 'Rapport Bâtiment A',
        'modele': 'BATIMENT',
        'statut': 'brouillon',
        'fichier_url': null,
        'formats': ['PDF', 'XLSX'],
        'sections': {'summary': true, 'plans': true, 'photos': false, 'location': true, 'history': true},
        'filtres': {
          'batiments': ['b1'],
          'statuts': ['A_TRAITER', 'EN_COURS'],
          'dateDebut': '2026-09-01',
        },
        'version': 1,
        ...surcharge,
      };

  group('lecture de la liste (anciennes routes)', () {
    test('la liste passe par le chemin du chantier', () async {
      espion.repond({
        'success': true,
        'data': {
          'rapports': [rapportJson()],
        },
      });

      final rapports = await source.getRapports('c1');

      expect(espion.appel, 'GET /chantiers/c1/rapports');
      expect(rapports.single.modele, ModeleRapport.batiment);
      expect(rapports.single.etat, EtatRapport.brouillon);
    });

    test('un type INCONNU garde sa valeur brute', () async {
      espion.repond({
        'success': true,
        'data': {
          'rapports': [
            {'id': 'r1', 'chantierId': 'c1', 'type': 'type_ajoute_apres_la_livraison', 'fichier_url': 'u'},
          ],
        },
      });

      final rapport = (await source.getRapports('c1')).single;

      expect(rapport.typeInconnu, isTrue);
      expect(rapport.typeBrut, 'type_ajoute_apres_la_livraison');
    });

    test('la suppression vise le rapport à la racine', () async {
      espion.repond({'success': true, 'data': <String, dynamic>{}});
      await source.supprimerRapport('r1');
      expect(espion.appel, 'DELETE /rapports/r1');
    });
  });

  group('ancien point d’entrée', () {
    test('nomme le chantier dans le chemin ET dans le corps', () async {
      espion.repond({'success': true, 'data': {'rapport': rapportJson()}});

      await source.genererRapport(chantierId: 'c1', type: RapportType.reserves);

      expect(espion.appel, 'POST /chantiers/c1/rapports/generer');
      final corps = espion.requete.data as Map<String, dynamic>;
      expect(corps['chantierId'], 'c1');
      expect(corps['type'], 'reserves');
      // Aucun filtre absent n'est transmis : `null` serait lu comme « aucune
      // entreprise » et le rapport sortirait vide.
      expect(corps.containsKey('statut'), isFalse);
      expect(corps.containsKey('entrepriseId'), isFalse);
    });
  });

  group('§ 9 — configuration', () {
    const configuration = ConfigurationRapport(
      chantierId: 'c1',
      nom: 'Rapport Bâtiment A',
      modele: ModeleRapport.batiment,
      filtres: FiltresRapport(
        batiments: ['b1'],
        statuts: [StatutReserveRapport.aTraiter, StatutReserveRapport.enCours],
      ),
      sections: SectionsRapport(history: true, photos: false),
      formats: {FormatRapport.xlsx, FormatRapport.pdf},
    );

    test('POST /reports porte la configuration du § 10', () async {
      espion.repond({'success': true, 'data': {'rapport': rapportJson()}});

      final rapport = await source.creerRapport(configuration);

      expect(espion.appel, 'POST /reports');
      final corps = espion.requete.data as Map<String, dynamic>;
      expect(corps['chantierId'], 'c1');
      expect(corps['nom'], 'Rapport Bâtiment A');
      expect(corps['modele'], 'BATIMENT');
      expect(corps['filtres'], {
        'batiments': ['b1'],
        'statuts': ['A_TRAITER', 'EN_COURS'],
      });
      expect(corps['sections'], {
        'summary': true, 'plans': true, 'photos': false, 'location': true, 'history': true,
      });
      // Ordre stable, PDF d'abord, quel que soit l'ordre des cases cochées.
      expect(corps['formats'], ['PDF', 'XLSX']);
      expect(rapport.id, 'r9');
    });

    test('une liste de filtre VIDE n’est pas envoyée — elle signifie « Tous »', () async {
      espion.repond({'success': true, 'data': {'rapport': rapportJson()}});

      await source.creerRapport(const ConfigurationRapport(chantierId: 'c1', modele: ModeleRapport.global));

      final corps = espion.requete.data as Map<String, dynamic>;
      expect(corps['filtres'], isEmpty);
    });

    test('PATCH /reports/:id ne renvoie PAS le chantier', () async {
      espion.repond({'success': true, 'data': {'rapport': rapportJson()}});

      await source.modifierRapport('r9', configuration);

      expect(espion.appel, 'PATCH /reports/r9');
      final corps = espion.requete.data as Map<String, dynamic>;
      expect(corps.containsKey('chantierId'), isFalse);
      expect(corps['modele'], 'BATIMENT');
    });

    test('GET /reports/:id relit un rapport complet', () async {
      espion.repond({
        'success': true,
        'data': {
          'rapport': rapportJson({
            'statut': 'envoye',
            'fichier_url': '/uploads/rapports/r9.pdf',
            'fichier_xlsx_url': '/uploads/rapports/r9.xlsx',
            'version': 3,
            'nb_reserves': 42,
            'genere_le': '2026-09-10T08:00:00.000Z',
            'entrepriseCible': {'id': 'p1', 'nom': 'ABC'},
          }),
        },
      });

      final r = await source.detailRapport('r9');

      expect(espion.appel, 'GET /reports/r9');
      expect(r.etat, EtatRapport.envoye);
      expect(r.estDiffuse, isTrue);
      expect(r.aExcel, isTrue);
      expect(r.version, 3);
      expect(r.nbReserves, 42);
      expect(r.entrepriseNom, 'ABC');
      expect(r.filtres.dateDebut, DateTime(2026, 9, 1));
    });
  });

  group('§ 11, § 15, § 20 — génération', () {
    test('POST /reports/:id/generate', () async {
      espion.repond({'success': true, 'data': {'rapport': rapportJson({'statut': 'genere'})}});

      final r = await source.genererRapportConfigure('r9');

      expect(espion.appel, 'POST /reports/r9/generate');
      expect(r.etat, EtatRapport.genere);
    });

    test('la génération dispose d’un délai de réception allongé', () async {
      espion.repond({'success': true, 'data': {'rapport': rapportJson()}});

      await source.genererRapportConfigure('r9');

      expect(espion.requete.receiveTimeout, greaterThanOrEqualTo(const Duration(minutes: 5)));
    });

    test('POST /reports/:id/generate-by-company rend le bilan du § 15', () async {
      espion.repond({
        'success': true,
        'message': '2 rapport(s) généré(s), un par entreprise.',
        'data': {
          'rapports': [rapportJson(), rapportJson({'id': 'r10'})],
          'echecs': [
            {'entreprise': 'XYZ', 'message': 'timeout'},
          ],
          'reservesSansEntreprise': 3,
        },
      });

      final r = await source.genererParEntreprise('r9');

      expect(espion.appel, 'POST /reports/r9/generate-by-company');
      expect(r.nbRapports, 2);
      expect(r.echecs, ['XYZ : timeout']);
      expect(r.reservesSansEntreprise, 3);
    });

    test('le RÉSUMÉ passe par la prévisualisation, en mode « resume »', () async {
      espion.repond({
        'success': true,
        'data': {
          'resume': {
            'total': 12,
            'parStatut': {'A_TRAITER': 5, 'LEVEE': 7, 'INCONNU': 1},
            'parGravite': {'CRITIQUE': 2},
            'entreprises': 3,
          },
        },
      });

      final r = await source.resumeRapport('r9');

      expect(espion.appel, 'GET /reports/r9/preview');
      expect(espion.requete.queryParameters, {'mode': 'resume'});
      expect(r.total, 12);
      expect(r.parStatut[StatutReserveRapport.aTraiter], 5);
      expect(r.parStatut.length, 2); // la clé inconnue est ignorée, pas inventée
      expect(r.entreprises, 3);
    });
  });

  group('§ 14 et § 18 — partage et historique', () {
    test('POST /reports/:id/share rend le lien EN CLAIR, une fois', () async {
      espion.repond({
        'success': true,
        'data': {
          'url': 'https://api.widjila.test/api/v1/r/abc',
          'partage': {'id': 'p1', 'expireLe': '2026-10-10T00:00:00.000Z', 'authentificationRequise': true},
        },
      });

      final lien = await source.partager('r9', expireDansJours: 30, authentificationRequise: true);

      expect(espion.appel, 'POST /reports/r9/share');
      expect(espion.requete.data, {'expireDansJours': 30, 'authentificationRequise': true});
      expect(lien.url, 'https://api.widjila.test/api/v1/r/abc');
      expect(lien.authentificationRequise, isTrue);
    });

    test('la liste des liens et la révocation', () async {
      espion.repond({
        'success': true,
        'data': {
          'partages': [
            {'id': 'p1', 'nbAcces': 4, 'actif': true},
            {'id': 'p2', 'actif': false, 'revoqueLe': '2026-09-11T00:00:00.000Z'},
          ],
        },
      });

      final partages = await source.partages('r9');
      expect(espion.appel, 'GET /reports/r9/shares');
      expect(partages.map((p) => p.actif), [true, false]);
      expect(partages.first.nbAcces, 4);

      final espion2 = DioEspion()..repond({'success': true});
      await RapportRemoteDataSourceImpl(dio: dioDeTest(espion2)).revoquerPartage('r9', 'p1');
      expect(espion2.appel, 'DELETE /reports/r9/shares/p1');
    });

    test('GET /reports/:id/history rend les libellés du serveur', () async {
      espion.repond({
        'success': true,
        'data': {
          'historique': [
            {'id': 'h1', 'action': 'cree', 'libelle': 'Rapport créé', 'acteur': 'Balla Beye', 'date': '2026-09-10T08:00:00.000Z'},
            {'id': 'h2', 'action': 'consulte_via_lien', 'libelle': 'Rapport consulté via lien', 'acteur': null},
          ],
        },
      });

      final h = await source.historique('r9');

      expect(espion.appel, 'GET /reports/r9/history');
      expect(h.map((e) => e.libelle), ['Rapport créé', 'Rapport consulté via lien']);
      expect(h.last.acteur, isNull);
    });

    test('dupliquer et archiver', () async {
      espion.repond({'success': true, 'data': {'rapport': rapportJson({'id': 'r10'})}});
      final copie = await source.dupliquer('r9');
      expect(espion.appel, 'POST /reports/r9/duplicate');
      expect(copie.id, 'r10');

      final espion2 = DioEspion()..repond({'success': true, 'data': {'rapport': rapportJson({'statut': 'archive'})}});
      final archive = await RapportRemoteDataSourceImpl(dio: dioDeTest(espion2)).archiver('r9');
      expect(espion2.appel, 'POST /reports/r9/archive');
      expect(archive.etat, EtatRapport.archive);
    });
  });

  group('§ 13 — envoi par e-mail', () {
    test('PRÉPARER est un GET — il ne doit rien envoyer', () async {
      espion.repond({
        'success': true,
        'data': {
          'envoi': {
            'rapportId': 'r1',
            'chantierNom': 'Résidence Horizon',
            'objet': 'Rapport de chantier – Résidence Horizon – 09/09/2026',
            'message': 'Bonjour,',
            'expediteur': 'Balla Beye',
            'nbReserves': 12,
            'destinataires': [
              {'id': 'p1', 'nom': 'SARL Toiture', 'email': 'toiture@ex.fr'},
              {'id': 'p2', 'nom': 'Sans adresse', 'email': '   '},
            ],
            'copies': [
              {'id': 'c1', 'nom': 'MOA', 'email': 'moa@ex.fr'},
            ],
            'candidats': [
              {'id': 'p1', 'nom': 'SARL Toiture', 'email': 'toiture@ex.fr', 'type': 'partenaire'},
              {'id': 'c1', 'nom': 'MOA', 'email': 'moa@ex.fr', 'type': 'partenaire'},
              {'id': 'u1', 'nom': 'Awa Diop', 'email': 'awa@widjila.com', 'type': 'membre'},
            ],
            'sansEmail': ['Sans adresse'],
            'mode': 'lien',
            'taille': 12582912,
            'pieceJointe': {'nom': 'rapport-RH.pdf', 'url': '/uploads/rapports/x.pdf'},
          },
        },
      });

      final envoi = await source.preparerEnvoi('r1');

      expect(espion.appel, 'GET /reports/r1/send-email');
      expect(envoi.objet, 'Rapport de chantier – Résidence Horizon – 09/09/2026');
      expect(envoi.destinatairesJoignables, hasLength(1));
      expect(envoi.copiesJoignables.single.email, 'moa@ex.fr');
      expect(envoi.mode, ModeEnvoiRapport.lien);
      expect(envoi.taille, 12582912);
      // Seul le membre qui n'est pas déjà proposé peut être AJOUTÉ.
      expect(envoi.candidatsSupplementaires.map((c) => c.email), ['awa@widjila.com']);
    });

    test('ENVOYER sans modification ne poste que les RETRAITS', () async {
      espion.repond({'success': true, 'message': 'Rapport envoyé à 1 destinataire(s).'});

      final message = await source.envoyerRapport('r1', const DemandeEnvoiRapport(exclure: ['plomberie@ex.fr']));

      expect(espion.appel, 'POST /reports/r1/send-email');
      final corps = espion.requete.data as Map<String, dynamic>;
      // Le serveur recalcule alors lui-même les destinataires.
      expect(corps.keys.toList(), ['exclure']);
      expect(corps['exclure'], ['plomberie@ex.fr']);
      expect(message, 'Rapport envoyé à 1 destinataire(s).');
    });

    test('ENVOYER avec les choix de l’utilisateur transmet listes, objet, message et forme', () async {
      espion.repond({'success': true, 'message': 'ok'});

      await source.envoyerRapport(
        'r1',
        const DemandeEnvoiRapport(
          destinataires: ['toiture@ex.fr', 'awa@widjila.com'],
          copies: [],
          objet: 'OPR bâtiment A',
          message: 'Merci.',
          mode: ModeEnvoiRapport.lien,
        ),
      );

      expect(espion.requete.data, {
        'exclure': <String>[],
        'destinataires': ['toiture@ex.fr', 'awa@widjila.com'],
        'copies': <String>[],
        'objet': 'OPR bâtiment A',
        'message': 'Merci.',
        'mode': 'lien',
      });
    });
  });

  group('listes des filtres', () {
    test('les projets, avec leur code', () async {
      espion.repond({
        'success': true,
        'data': {
          'chantiers': [
            {'id': 'c1', 'nom': 'Résidence Les Jardins', 'code': 'RJ-2026'},
          ],
        },
      });

      final projets = await source.getProjets();

      expect(espion.appel, 'GET /chantiers');
      expect(projets.single.detail, 'RJ-2026');
    });

    test('les entreprises DU CHANTIER', () async {
      espion.repond({
        'success': true,
        'data': {
          'partenaires': [
            {'id': 'p1', 'nom': 'ABC Carrelage'},
          ],
        },
      });

      final entreprises = await source.getEntreprisesChantier('c1');

      expect(espion.appel, 'GET /chantiers/c1/partenaires');
      expect(entreprises.single.nom, 'ABC Carrelage');
    });

    test('les corps d’état actifs', () async {
      espion.repond({
        'success': true,
        'data': {
          'corpsEtat': [
            {'id': 'ce1', 'nom': 'Carrelage'},
          ],
        },
      });

      final corps = await source.getCorpsEtat();

      expect(espion.appel, 'GET /corps-etat/actifs');
      expect(corps.single.nom, 'Carrelage');
    });
  });
}
