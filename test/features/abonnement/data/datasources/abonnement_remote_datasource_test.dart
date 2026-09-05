import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/errors/error_codes.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/features/abonnement/data/datasources/abonnement_remote_datasource.dart';

import '../../../../helpers/dio_espion.dart';

/// L'API Abonnement, du chemin envoyé jusqu'au champ affiché.
///
/// ## Ce que ce fichier vérifie, et que rien d'autre ne voyait
///
/// Trois choses, dans cet ordre :
///
///  1. le CHEMIN et le VERBE réellement partis. Dart accepte n'importe
///     quelle chaîne comme chemin : une faute de frappe ne se voit qu'en
///     production, sous la forme d'un écran qui reste vide ;
///
///  2. la RELECTURE du JSON, à partir d'une réponse écrite telle que le
///     backend la forme — enveloppe `{ success, data }` comprise. Une clé mal
///     orthographiée traverse le `as String?` sans bruit et ressort en
///     `null` : un champ vide à l'écran, qu'on prend pour une donnée absente
///     côté serveur ;
///
///  3. la traduction des REFUS. Le 403 sur l'historique n'est pas une panne :
///     la facturation est réservée aux rôles de gestion, et l'écran doit
///     pouvoir faire la différence.
void main() {
  late DioEspion espion;
  late AbonnementRemoteDataSourceImpl source;

  setUp(() {
    espion = DioEspion();
    source = AbonnementRemoteDataSourceImpl(dio: dioDeTest(espion));
  });

  group('GET /abonnement/plans', () {
    test('appelle la bonne route et relit chaque champ du catalogue', () async {
      // Réponse écrite d'après `vuePublique()` du backend
      // (`subscription.service.js`) — les noms de clés sont les siens.
      espion.repond({
        'success': true,
        'message': 'Plans récupérés',
        'data': {
          'plans': [
            {
              'id': 'p-essentiel',
              'code': 'essentiel',
              'nom': 'Essentiel',
              'description': 'Pour démarrer',
              'prix': 49,
              'devise': 'EUR',
              'periode': 'mois',
              'surDevis': false,
              'limiteUtilisateurs': 2,
              'limiteChantiers': null,
              'fonctionnalites': ['reserves', 'export_pdf'],
              'ordre': 1,
            },
            {
              'id': 'p-entreprise',
              'code': 'entreprise',
              'nom': 'Entreprise',
              'description': 'Sur mesure',
              'prix': null,
              'devise': 'EUR',
              'periode': 'mois',
              'surDevis': true,
              'limiteUtilisateurs': null,
              'limiteChantiers': null,
              'fonctionnalites': ['api', 'hebergement_dedie'],
              'ordre': 3,
            },
          ],
        },
      });

      final formules = await source.getFormules();

      expect(espion.appel, 'GET /abonnement/plans');
      expect(formules, hasLength(2));

      final essentiel = formules.first;
      expect(essentiel.code, 'essentiel');
      expect(essentiel.prix, 49);
      expect(essentiel.limiteUtilisateurs, 2);
      expect(essentiel.fonctionnalites, ['reserves', 'export_pdf']);

      // Le cas qui compte : « sur devis » et « illimité » sont tous deux des
      // `null`, et aucun ne doit devenir 0. Afficher « 0 € » pour une
      // formule sur devis, ou « 0 utilisateur » pour un plan illimité,
      // serait faux dans les deux sens.
      final entreprise = formules.last;
      expect(entreprise.prix, isNull);
      expect(entreprise.surDevis, isTrue);
      expect(entreprise.limiteUtilisateurs, isNull);
    });
  });

  group('GET /abonnement/droits', () {
    test('distingue « aucune fonctionnalité » de « toutes »', () async {
      // `null` = toutes (super-admin), `[]` = aucune. Les confondre ouvrirait
      // l'application entière à une organisation sans droits.
      espion.repond({
        'success': true,
        'data': {
          'droits': {
            'actif': true,
            'source': 'abonnement',
            'planCode': 'pro',
            'planNom': 'Pro',
            'fonctionnalites': ['reserves', 'rapports'],
            'essaiEnCours': false,
            'dateFin': '2026-12-31T00:00:00.000Z',
            'joursRestants': 117,
          },
          'usage': {
            'utilisateurs': {'utilise': 3, 'limite': 5},
            'chantiers': {'utilise': 2, 'limite': null},
          },
        },
      });

      final droits = await source.getDroits();

      expect(espion.appel, 'GET /abonnement/droits');
      expect(droits.actif, isTrue);
      expect(droits.planCode, 'pro');
      expect(droits.fonctionnalites, ['reserves', 'rapports']);
      expect(droits.joursRestants, 117);
      expect(droits.dateFin, isNotNull);
    });

    test('une organisation SANS droits ne reçoit pas « toutes »', () async {
      espion.repond({
        'success': true,
        'data': {
          'droits': {
            'actif': false,
            'source': 'aucun',
            'fonctionnalites': <String>[],
          },
          'usage': <String, dynamic>{},
        },
      });

      final droits = await source.getDroits();

      expect(droits.actif, isFalse);
      // La liste vide est conservée TELLE QUELLE : la transformer en `null`
      // signifierait « toutes les fonctionnalités ».
      expect(droits.fonctionnalites, isEmpty);
      expect(droits.fonctionnalites, isNotNull);
    });
  });

  group('GET /abonnement/historique', () {
    test('accepte un prix en nombre comme en chaîne', () async {
      // Une décimale SQL peut arriver en chaîne selon le pilote. Un cast
      // strict ferait tomber TOUT l'historique pour un seul montant.
      espion.repond({
        'success': true,
        'data': {
          'souscriptions': [
            {
              'id': 's1',
              'planCode': 'essentiel',
              'planNom': 'Essentiel',
              'prixPaye': 49,
              'devise': 'EUR',
              'statut': 'active',
            },
            {
              'id': 's2',
              'planCode': 'pro',
              'planNom': 'Pro',
              'prixPaye': '89.00',
              'devise': 'EUR',
              'statut': 'expiree',
            },
          ],
        },
      });

      final historique = await source.getHistorique();

      expect(espion.appel, 'GET /abonnement/historique');
      expect(historique, hasLength(2));
      expect(historique[0].prixPaye, 49);
      expect(historique[1].prixPaye, 89);
    });

    test('un 403 ressort en exception serveur, pas en liste vide', () async {
      // La facturation est réservée aux rôles de gestion. Le refus doit
      // remonter : le traduire en liste vide ferait croire à un compte sans
      // aucun achat, ce qui est une information fausse.
      espion.repondErreur(403, corps: {
        'success': false,
        'message': 'Accès réservé à la gestion.',
      });

      await expectLater(source.getHistorique(), throwsA(isA<ServerException>()));
    });
  });

  group('refus d’abonnement', () {
    test('le code du serveur est conservé pour la modale', () async {
      // Le mobile ne réécrit pas ce message : lui seul nomme la formule et
      // le plafond. Le préfixe permet à l'écran d'ouvrir une invitation à
      // s'abonner plutôt qu'une alerte rouge sans issue.
      espion.repondErreur(403, corps: {
        'success': false,
        'code': 'SUBSCRIPTION_LIMIT_REACHED',
        'message': 'Votre abonnement Essentiel est limité à 2 utilisateurs.',
      });

      try {
        await source.getDroits();
        fail('un refus aurait dû être levé');
      } on ServerException catch (e) {
        expect(e.message, startsWith(ErrCodes.prefixeAbonnement));
        expect(e.message, contains('SUBSCRIPTION_LIMIT_REACHED'));
        expect(e.message, contains('2 utilisateurs'));
      }
    });
  });

  group('réseau', () {
    test('une coupure ressort en exception réseau', () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test/api/v1'));
      dio.httpClientAdapter = _AdaptateurCoupe();
      final hors = AbonnementRemoteDataSourceImpl(dio: dio);

      await expectLater(hors.getFormules(), throwsA(isA<NetworkException>()));
    });
  });
}

/// Adaptateur qui simule une coupure : aucune réponse, une erreur de
/// connexion — ce que voit un téléphone dans un sous-sol de chantier.
class _AdaptateurCoupe implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, _, _) =>
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'reseau indisponible',
      );

  @override
  void close({bool force = false}) {}
}
