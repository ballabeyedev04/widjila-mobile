import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/features/chantier/data/datasources/chantier_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/entities/chantier.dart';
import 'package:suivie_chantier_mobile/features/chantier/domain/repositories/chantier_repository.dart';
import 'package:suivie_chantier_mobile/features/referentiel/domain/entities/code_niveau.dart';

import '../../../../helpers/dio_espion.dart';

/// L'API Chantier, telle qu'elle part réellement.
///
/// ## Les deux pièges de cette API
///
/// **Le fuseau horaire.** Le serveur attend une DATE de chantier
/// (`yyyy-MM-dd`), pas un instant. Envoyer un horodatage complet décale la
/// date d'un jour pour tout fuseau à l'ouest de Greenwich une fois converti
/// en UTC : un chantier démarré le 1er mars s'enregistre au 28 février. Ce
/// genre de faute ne se voit jamais sur la machine de développement, qui est
/// à Paris.
///
/// **Les champs vides.** Le schéma Joi tolère une chaîne vide, mais une
/// chaîne vide EN BASE se relit ensuite comme une valeur renseignée : la
/// fiche affiche un code de chantier vide au lieu de masquer la ligne. Les
/// champs non remplis doivent donc être omis, pas envoyés à vide.
void main() {
  late DioEspion espion;
  late ChantierRemoteDataSourceImpl source;

  setUp(() {
    espion = DioEspion();
    source = ChantierRemoteDataSourceImpl(dio: dioDeTest(espion));
  });

  Map<String, dynamic> chantierJson(String id) => {
        'id': id,
        'nom': 'Residence Les Cedres',
        'code': 'RLC-2026',
        'statut': 'en_cours',
        'adresse': '12 rue des Acacias',
      };

  group('GET /chantiers', () {
    test('envoie la pagination et relit la liste avec son total', () async {
      espion.repond({
        'success': true,
        'data': {
          'chantiers': [chantierJson('c1'), chantierJson('c2')],
          'total': 47,
        },
      });

      final page = await source.getChantiers(page: 3, limit: 20);

      expect(espion.appel, 'GET /chantiers');
      expect(espion.requete.queryParameters['page'], 3);
      expect(espion.requete.queryParameters['limit'], 20);
      expect(page.items, hasLength(2));
      // Le total vient du SERVEUR, pas de la longueur de la page : s'en
      // remettre à `items.length` afficherait « 2 chantiers » sur une liste
      // qui en compte 47.
      expect(page.total, 47);
    });

    test('n’envoie ni recherche vide ni filtre absent', () async {
      // Un `search=` vide n'est pas neutre côté serveur : il déclenche une
      // clause `LIKE '%%'` qui écarte les lignes dont le champ est nul.
      espion.repond({
        'success': true,
        'data': {'chantiers': <dynamic>[], 'total': 0},
      });

      await source.getChantiers(search: '');

      expect(espion.requete.queryParameters.containsKey('search'), isFalse);
      expect(espion.requete.queryParameters.containsKey('statut'), isFalse);
      expect(espion.requete.queryParameters.containsKey('demandes'), isFalse);
    });

    test('le filtre de statut part sous sa forme SERVEUR', () async {
      espion.repond({
        'success': true,
        'data': {'chantiers': <dynamic>[], 'total': 0},
      });

      await source.getChantiers(statut: ChantierStatut.enAttenteValidation);

      // `en_attente_validation`, et non `enAttenteValidation` : le serveur ne
      // connaît que sa propre écriture.
      expect(espion.requete.queryParameters['statut'], 'en_attente_validation');
    });

    test('la vue des demandes est demandée explicitement', () async {
      // Sans ce paramètre, le serveur écarte les demandes : l'écran de suivi
      // resterait vide en permanence.
      espion.repond({
        'success': true,
        'data': {'chantiers': <dynamic>[], 'total': 0},
      });

      await source.getChantiers(demandes: VueDemandes.miennes);

      expect(espion.requete.queryParameters['demandes'], isNotNull);
    });
  });

  group('POST /chantiers', () {
    test('envoie une DATE seule, jamais un horodatage', () async {
      espion.repond({
        'success': true,
        'data': {'chantier': chantierJson('c9')},
      });

      await source.creerChantier(
        nom: 'Nouveau chantier',
        // 1er mars à 00 h 30 heure locale : converti en UTC depuis un fuseau
        // à l'ouest, cet instant retombe au 28 février.
        dateDebut: DateTime(2026, 3, 1, 0, 30),
      );

      final corps = espion.requete.data as Map<String, dynamic>;
      expect(corps['date_debut'], '2026-03-01');
      expect(corps['date_debut'], isNot(contains('T')));
    });

    test('omet les champs vides au lieu de les envoyer à vide', () async {
      espion.repond({
        'success': true,
        'data': {'chantier': chantierJson('c9')},
      });

      await source.creerChantier(nom: 'Minimal', code: '', adresse: '', description: '');

      final corps = espion.requete.data as Map<String, dynamic>;
      expect(corps['nom'], 'Minimal');
      expect(corps.containsKey('code'), isFalse);
      expect(corps.containsKey('adresse'), isFalse);
      expect(corps.containsKey('description'), isFalse);
    });

    test('n’envoie AUCUN statut : c’est le serveur qui décide', () async {
      // Toute création hors super-admin naît « en_attente_validation ». En
      // envoyer un depuis le mobile laisserait croire qu'il en décide.
      espion.repond({
        'success': true,
        'data': {'chantier': chantierJson('c9')},
      });

      await source.creerChantier(nom: 'Demande');

      expect((espion.requete.data as Map<String, dynamic>).containsKey('statut'), isFalse);
    });
  });

  group('structure', () {
    test('POST bâtiment vise le chantier dans le chemin', () async {
      espion.repond({
        'success': true,
        'data': {
          'batiment': {'id': 'b1', 'nom': 'Bâtiment A'},
        },
      });

      await source.creerBatiment('c1', nom: 'Bâtiment A');

      expect(espion.appel, 'POST /chantiers/c1/batiments');
      expect((espion.requete.data as Map<String, dynamic>)['nom'], 'Bâtiment A');
    });

    test('POST étage vise le bâtiment et nomme la nature du niveau', () async {
      espion.repond({
        'success': true,
        'data': {
          'etage': {'id': 'e1', 'nom': 'R+2'},
        },
      });

      await source.creerEtage('c1', 'b1', nom: 'R+2', typeNiveau: TypeNiveau.etage);

      expect(espion.appel, 'POST /chantiers/c1/batiments/b1/etages');
      final corps = espion.requete.data as Map<String, dynamic>;
      expect(corps['nom'], 'R+2');
      // La nature du niveau range l'étage sous « SOUS-SOLS », « ÉTAGES » ou
      // « TOITURE » : elle part sous l'écriture du serveur.
      expect(corps['typeNiveau'], TypeNiveau.etage.raw);
    });
  });

  group('GET /chantiers/:id', () {
    test('relit la fiche depuis son enveloppe', () async {
      espion.repond({
        'success': true,
        'data': {'chantier': chantierJson('c1')},
      });

      final chantier = await source.getChantierDetail('c1');

      expect(espion.appel, 'GET /chantiers/c1');
      expect(chantier.id, 'c1');
      expect(chantier.nom, 'Residence Les Cedres');
      expect(chantier.statut, ChantierStatut.enCours);
    });
  });
}
