import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/services/token_service.dart';
import 'package:suivie_chantier_mobile/features/account/data/datasources/account_remote_datasource.dart';

import '../../../../helpers/dio_espion.dart';

class _MockTokens extends Mock implements TokenService {}

/// L'API Compte.
///
/// ## Le changement de mot de passe, cas le plus délicat de l'application
///
/// Trois choses s'enchaînent, et chacune peut déconnecter l'utilisateur qui
/// vient précisément de SÉCURISER son compte :
///
///  1. le jeton de renouvellement de CET appareil est envoyé, pour que le
///     serveur épargne cette session en révoquant les autres. Absent, le
///     serveur révoque tout — un défaut prudent, mais qui oblige à se
///     reconnecter ;
///
///  2. le serveur incrémente `token_version` : le jeton d'accès courant meurt
///     à la seconde même ;
///
///  3. le serveur renvoie un jeton neuf, que le mobile DOIT enregistrer.
///     Sans cela, la requête suivante repart avec l'ancien et l'utilisateur
///     est déconnecté par son propre geste de sécurisation.
///
/// ## Le profil : `null` et chaîne vide ne sont pas la même chose
///
/// `null` signifie « champ non touché » et n'est pas envoyé. La chaîne vide
/// est TRANSMISE : c'est ainsi qu'on efface un téléphone. Les confondre rend
/// l'effacement impossible, sans aucun message d'erreur — le champ revient
/// simplement inchangé.
void main() {
  late DioEspion espion;
  late _MockTokens tokens;
  late AccountRemoteDataSourceImpl source;

  setUp(() {
    espion = DioEspion();
    tokens = _MockTokens();
    when(tokens.getRefreshToken).thenAnswer((_) async => 'jeton-renouvellement');
    when(() => tokens.setToken(any())).thenAnswer((_) async {});
    source = AccountRemoteDataSourceImpl(dio: dioDeTest(espion), tokenService: tokens);
  });

  Map<String, dynamic> utilisateurJson({bool mfa = false}) => {
        'id': 'u1',
        'nom': 'BEYE',
        'prenom': 'Balla',
        'email': 'balla@widjila.com',
        'role': 'ConducteurTravaux',
        'statut': 'actif',
        'mfaActive': mfa,
      };

  group('changement de mot de passe', () {
    test('envoie le jeton de CET appareil pour épargner sa session', () async {
      espion.repond({
        'success': true,
        'data': {'accessToken': 'jeton-neuf', 'sessionsRevoquees': 2},
      });

      final revoquees = await source.changerMotDePasse(
        ancienMotDePasse: 'Ancien-2025',
        nouveauMotDePasse: 'Nouveau-2026',
      );

      expect(espion.appel, 'PUT /account/change-password');
      final corps = espion.requete.data as Map<String, dynamic>;
      expect(corps['ancien_mot_de_passe'], 'Ancien-2025');
      expect(corps['nouveau_mot_de_passe'], 'Nouveau-2026');
      expect(corps['refresh_token'], 'jeton-renouvellement');
      expect(revoquees, 2);
    });

    test('ENREGISTRE le jeton neuf — sans quoi l’utilisateur se déconnecte lui-même',
        () async {
      espion.repond({
        'success': true,
        'data': {'accessToken': 'jeton-neuf', 'sessionsRevoquees': 0},
      });

      await source.changerMotDePasse(
        ancienMotDePasse: 'Ancien-2025',
        nouveauMotDePasse: 'Nouveau-2026',
      );

      verify(() => tokens.setToken('jeton-neuf')).called(1);
    });

    test('un jeton de renouvellement illisible n’empêche pas l’opération',
        () async {
      // Le stockage sécurisé peut échouer. Le serveur révoquera alors TOUTES
      // les sessions, celle-ci comprise : une reconnexion de trop vaut mieux
      // qu'une session volée laissée ouverte.
      when(tokens.getRefreshToken).thenAnswer((_) async => null);
      espion.repond({
        'success': true,
        'data': {'accessToken': 'jeton-neuf'},
      });

      await source.changerMotDePasse(
        ancienMotDePasse: 'Ancien-2025',
        nouveauMotDePasse: 'Nouveau-2026',
      );

      expect((espion.requete.data as Map<String, dynamic>).containsKey('refresh_token'),
          isFalse);
    });

    test('un serveur plus ancien, sans compteur, ne fait pas échouer le geste',
        () async {
      // Le mot de passe a bien changé ; seule la précision du message se
      // perd. Lever ici transformerait une réussite en erreur affichée.
      espion.repond({
        'success': true,
        'data': {'accessToken': 'jeton-neuf'},
      });

      final revoquees = await source.changerMotDePasse(
        ancienMotDePasse: 'a',
        nouveauMotDePasse: 'b',
      );

      expect(revoquees, 0);
    });
  });

  group('profil', () {
    test('un champ NON TOUCHÉ est omis', () async {
      espion.repond({
        'success': true,
        'data': {'utilisateur': utilisateurJson()},
      });

      await source.modifierProfil(nom: 'BEYE');

      final corps = espion.requete.data as Map<String, dynamic>;
      expect(corps['nom'], 'BEYE');
      expect(corps.containsKey('telephone'), isFalse);
      expect(corps.containsKey('fonction'), isFalse);
    });

    test('une chaîne VIDE est transmise : c’est ainsi qu’on efface', () async {
      // Le cas qui distingue « je ne touche pas » de « je supprime ». Les
      // confondre rendrait l'effacement impossible, sans message d'erreur.
      espion.repond({
        'success': true,
        'data': {'utilisateur': utilisateurJson()},
      });

      await source.modifierProfil(telephone: '');

      final corps = espion.requete.data as Map<String, dynamic>;
      expect(corps.containsKey('telephone'), isTrue);
      expect(corps['telephone'], '');
    });

    test('sans photo, l’envoi reste du JSON — pas du multipart', () async {
      // Un multipart pour une correction de nom serait plus lourd sans rien
      // apporter ; le serveur accepte les deux formes.
      espion.repond({
        'success': true,
        'data': {'utilisateur': utilisateurJson()},
      });

      await source.modifierProfil(nom: 'BEYE');

      expect(espion.requete.data, isA<Map<String, dynamic>>());
    });

    test('le changement de langue passe par la même route', () async {
      espion.repond({
        'success': true,
        'data': {'utilisateur': utilisateurJson()},
      });

      await source.changerLangue('en');

      expect(espion.appel, 'PUT /account/profil');
      expect((espion.requete.data as Map<String, dynamic>)['langue'], 'en');
    });
  });

  group('sécurité', () {
    test('le statut MFA est lu sur la fiche du compte', () async {
      espion.repond({
        'success': true,
        'data': {'utilisateur': utilisateurJson(mfa: true)},
      });

      expect(await source.getStatutMfa(), isTrue);
    });

    test('un compte sans champ MFA est considéré NON protégé', () async {
      // Le défaut prudent : afficher « protégé » à tort inviterait à ne rien
      // faire.
      espion.repond({
        'success': true,
        'data': {
          'utilisateur': {
            'id': 'u1',
            'nom': 'BEYE',
            'prenom': 'Balla',
            'email': 'balla@widjila.com',
            'role': 'ConducteurTravaux',
            'statut': 'actif',
          },
        },
      });

      expect(await source.getStatutMfa(), isFalse);
    });

    test('révoquer UNE session la nomme, les révoquer TOUTES ne nomme rien',
        () async {
      espion.repond({'success': true, 'data': <String, dynamic>{}});
      await source.revokerSession('s1');
      expect(espion.appel, 'DELETE /account/sessions/s1');

      final second = DioEspion();
      final autre = AccountRemoteDataSourceImpl(
          dio: dioDeTest(second), tokenService: tokens);
      second.repond({'success': true, 'data': <String, dynamic>{}});
      await autre.revokerToutesSessions();
      expect(second.appel, 'DELETE /account/sessions');
    });

    test('l’historique de connexion demande une profondeur explicite', () async {
      espion.repond({
        'success': true,
        'data': {'connexions': <dynamic>[]},
      });

      await source.getConnexions();

      expect(espion.appel, 'GET /account/connexions');
      expect(espion.requete.queryParameters['limit'], 50);
    });
  });
}
