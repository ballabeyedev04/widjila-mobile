import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/rapport/data/datasources/rapport_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/rapport/domain/entities/rapport.dart';

import '../../../../helpers/dio_espion.dart';

/// L'API Rapport.
///
/// ## Un type inconnu ne doit pas devenir un libellé faux
///
/// Le serveur peut renvoyer un type de rapport que cette version du mobile ne
/// connaît pas — un type ajouté après la dernière livraison. L'entité
/// conserve alors la valeur BRUTE et l'écran l'affiche telle quelle, au lieu
/// de la ranger silencieusement sous le premier type de la liste. Un rapport
/// « Levée de réserves » présenté comme « Réserves » n'est pas un détail : ce
/// sont deux documents différents, et c'est le nom affiché qui décide lequel
/// on ouvre.
void main() {
  late DioEspion espion;
  late RapportRemoteDataSourceImpl source;

  setUp(() {
    espion = DioEspion();
    source = RapportRemoteDataSourceImpl(dio: dioDeTest(espion));
  });

  test('la liste passe par le chemin du chantier', () async {
    espion.repond({
      'success': true,
      'data': {
        'rapports': [
          {
            'id': 'r1',
            'chantierId': 'c1',
            'type': 'reserves',
            'fichier_url': 'https://exemple.test/r1.pdf',
          },
        ],
      },
    });

    final rapports = await source.getRapports('c1');

    expect(espion.appel, 'GET /chantiers/c1/rapports');
    expect(rapports, hasLength(1));
  });

  test('un type INCONNU garde sa valeur brute', () async {
    espion.repond({
      'success': true,
      'data': {
        'rapports': [
          {
            'id': 'r1',
            'chantierId': 'c1',
            'type': 'type_ajoute_apres_la_livraison',
            'fichier_url': 'https://exemple.test/r1.pdf',
          },
        ],
      },
    });

    final rapport = (await source.getRapports('c1')).single;

    // La valeur brute est conservée : l'écran l'affichera plutôt qu'un
    // libellé faux emprunté au premier type de la liste.
    expect(rapport.typeInconnu, isTrue);
    expect(rapport.typeBrut, 'type_ajoute_apres_la_livraison');
  });

  group('génération', () {
    test('nomme le chantier dans le chemin ET dans le corps', () async {
      // La redondance vient du serveur : le schéma Joi exige `chantierId`
      // dans le corps. La retirer provoquerait un 400.
      espion.repond({
        'success': true,
        'data': {
          'rapport': {
            'id': 'r9',
            'chantierId': 'c1',
            'type': 'reserves',
            'fichier_url': 'https://exemple.test/r9.pdf',
          },
        },
      });

      await source.genererRapport(chantierId: 'c1', type: RapportType.reserves);

      expect(espion.appel, 'POST /chantiers/c1/rapports/generer');
      final corps = espion.requete.data as Map<String, dynamic>;
      expect(corps['chantierId'], 'c1');
      expect(corps['type'], RapportType.reserves.raw);
    });

    test('les filtres absents ne sont pas envoyés', () async {
      // Un `entrepriseId: null` transmis serait interprété comme un filtre
      // sur « aucune entreprise » : le rapport sortirait vide.
      espion.repond({
        'success': true,
        'data': {
          'rapport': {
            'id': 'r9',
            'chantierId': 'c1',
            'type': 'reserves',
            'fichier_url': 'https://exemple.test/r9.pdf',
          },
        },
      });

      await source.genererRapport(chantierId: 'c1', type: RapportType.reserves);

      final corps = espion.requete.data as Map<String, dynamic>;
      expect(corps.containsKey('statut'), isFalse);
      expect(corps.containsKey('entrepriseId'), isFalse);
      expect(corps.containsKey('batimentId'), isFalse);
    });

    test('les filtres fournis partent sous leurs noms serveur', () async {
      espion.repond({
        'success': true,
        'data': {
          'rapport': {
            'id': 'r9',
            'chantierId': 'c1',
            'type': 'reserves',
            'fichier_url': 'https://exemple.test/r9.pdf',
          },
        },
      });

      await source.genererRapport(
        chantierId: 'c1',
        type: RapportType.reserves,
        statutReserve: 'en_cours',
        entrepriseId: 'p1',
        batimentId: 'b1',
      );

      final corps = espion.requete.data as Map<String, dynamic>;
      // Le paramètre s'appelle `statut` côté serveur, pas `statutReserve`.
      expect(corps['statut'], 'en_cours');
      expect(corps['entrepriseId'], 'p1');
      expect(corps['batimentId'], 'b1');
    });
  });

  test('la suppression vise le rapport à la racine, pas via le chantier',
      () async {
    espion.repond({'success': true, 'data': <String, dynamic>{}});

    await source.supprimerRapport('r1');

    expect(espion.appel, 'DELETE /rapports/r1');
  });
}
