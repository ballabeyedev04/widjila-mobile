import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/errors/error_codes.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/features/organisation/data/datasources/organisation_remote_datasource.dart';

import '../../../../helpers/dio_espion.dart';

/// L'API Organisation.
///
/// ## Deux enveloppes différentes pour la même notion
///
/// Un membre ajouté revient sous la clé `utilisateur`, pas `membre` : c'est
/// un compte d'utilisateur que le serveur vient de créer, et il le nomme
/// comme tel. Se tromper d'enveloppe lève un cast sur une réussite — le
/// membre EXISTE côté serveur, mais l'écran affiche une erreur et l'opérateur
/// recommence, créant un doublon.
///
/// ## Le plafond de la formule
///
/// `POST /organisation/membres` est gardé par le plafond d'utilisateurs de
/// l'abonnement. Son refus n'est pas une panne : c'est une invitation à
/// changer de formule, et le mobile doit pouvoir le reconnaître comme tel.
void main() {
  late DioEspion espion;
  late OrganisationRemoteDataSourceImpl source;

  setUp(() {
    espion = DioEspion();
    source = OrganisationRemoteDataSourceImpl(dio: dioDeTest(espion));
  });

  Map<String, dynamic> utilisateurJson(String id) => {
        'id': id,
        'nom': 'DIOP',
        'prenom': 'Awa',
        'email': 'awa@widjila.com',
        'role': 'ConducteurTravaux',
        'statut': 'actif',
      };

  test('la fiche de l’organisation vient de sa propre route', () async {
    espion.repond({
      'success': true,
      'data': {
        'organisation': {'id': 'o1', 'nom': 'Widjila BTP', 'ville': 'Dakar'},
      },
    });

    final orga = await source.getMonOrganisation();

    expect(espion.appel, 'GET /organisation');
    expect(orga.nom, 'Widjila BTP');
  });

  test('la liste des membres demande une page assez large', () async {
    // Une organisation courante compte quelques dizaines de personnes.
    // S'en tenir à la pagination par défaut couperait la liste sans que
    // l'écran, qui n'affiche pas de pagination, ne le laisse voir.
    espion.repond({
      'success': true,
      'data': {
        'membres': [utilisateurJson('u1')],
      },
    });

    final membres = await source.getMembres();

    expect(espion.appel, 'GET /organisation/membres');
    expect(espion.requete.queryParameters['limit'], 100);
    expect(membres, hasLength(1));
  });

  group('ajout d’un membre', () {
    test('relit l’enveloppe « utilisateur », et ce que l’email est devenu',
        () async {
      // `emailEnvoye` décide de ce que l'écran affiche ensuite : si le
      // courriel n'est pas parti, il faut montrer le mot de passe temporaire
      // à l'opérateur, sans quoi la personne créée ne peut pas se connecter.
      espion.repond({
        'success': true,
        'data': {
          'utilisateur': utilisateurJson('u9'),
          'motDePasseTemporaire': 'Temp-2026!',
          'emailEnvoye': false,
        },
      });

      final resultat = await source.ajouterMembre({'email': 'awa@widjila.com'});

      expect(espion.appel, 'POST /organisation/membres');
      expect(resultat.membre.id, 'u9');
      expect(resultat.motDePasseTemporaire, 'Temp-2026!');
      expect(resultat.emailEnvoye, isFalse);
    });

    test('un courriel parti ne renvoie pas de mot de passe en clair', () async {
      espion.repond({
        'success': true,
        'data': {
          'utilisateur': utilisateurJson('u9'),
          'emailEnvoye': true,
        },
      });

      final resultat = await source.ajouterMembre({'email': 'awa@widjila.com'});

      expect(resultat.emailEnvoye, isTrue);
      expect(resultat.motDePasseTemporaire, isNull);
    });

    test('le PLAFOND de la formule ressort comme un refus reconnaissable',
        () async {
      // Ce n'est pas une panne : c'est le plafond d'utilisateurs de
      // l'abonnement. Le message du serveur nomme la formule et le nombre —
      // il est conservé tel quel, et le préfixe permet à l'écran d'ouvrir
      // une invitation à s'abonner plutôt qu'une alerte sans issue.
      espion.repondErreur(403, corps: {
        'success': false,
        'code': 'SUBSCRIPTION_LIMIT_REACHED',
        'message': 'Votre abonnement Essentiel est limité à 2 utilisateurs '
            '(2 utilisés). Passez à une formule supérieure pour en ajouter.',
      });

      try {
        await source.ajouterMembre({'email': 'awa@widjila.com'});
        fail('le plafond aurait dû être signalé');
      } on ServerException catch (e) {
        expect(e.message, startsWith(ErrCodes.prefixeAbonnement));
        expect(e.message, contains('SUBSCRIPTION_LIMIT_REACHED'));
        // Le message du serveur, INTACT : lui seul nomme la formule et le
        // plafond atteint.
        expect(e.message, contains('Essentiel'));
        expect(e.message, contains('2 utilisateurs'));
      }
    });
  });

  group('intervenants', () {
    test('la lecture passe par l’organisation, la modification par la racine',
        () async {
      // Les deux routes ne sont pas symétriques côté serveur, et c'est
      // volontaire : la liste est cloisonnée par organisation, la
      // modification vise un intervenant par son identifiant.
      espion.repond({
        'success': true,
        'data': {'partenaires': <dynamic>[]},
      });
      await source.getPartenaires();
      expect(espion.appel, 'GET /organisation/partenaires');

      final second = DioEspion();
      final autre = OrganisationRemoteDataSourceImpl(dio: dioDeTest(second));
      second.repond({
        'success': true,
        'data': {
          'partenaire': {'id': 'p1', 'nom': 'Sous-traitant A', 'type': 'sous_traitant'},
        },
      });
      await autre.modifierPartenaire('p1', {'nom': 'Sous-traitant A'});
      expect(second.appel, 'PUT /partenaires/p1');
    });
  });

  test('la modification d’un membre vise son identifiant', () async {
    espion.repond({
      'success': true,
      'data': {'utilisateur': utilisateurJson('u1')},
    });

    await source.modifierMembre('u1', {'statut': 'inactif'});

    expect(espion.appel, 'PUT /organisation/membres/u1');
    expect((espion.requete.data as Map<String, dynamic>)['statut'], 'inactif');
  });
}
