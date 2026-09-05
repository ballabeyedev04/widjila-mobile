import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/features/auth/data/datasources/auth_remote_datasource.dart';

import '../../../../helpers/dio_espion.dart';

/// L'API d'authentification.
///
/// ## Les noms de champs, ici, ne pardonnent pas
///
/// Le serveur attend `mot_de_passe` et `nouveau_mot_de_passe` — en
/// serpent, en français. Le mobile écrit `motDePasse` en Dart. La conversion
/// est faite à la main, une fois, dans ce datasource : si elle s'égare, le
/// serveur reçoit un corps sans mot de passe et répond « identifiants
/// incorrects ». L'utilisateur, lui, conclut que son mot de passe est faux et
/// le réinitialise — pour rien.
///
/// ## La déconnexion
///
/// `POST /auth/logout` porte `skipAuthInterceptor` : l'intercepteur ne doit
/// pas tenter de rafraîchir un jeton pour une requête dont le but est
/// justement de le périmer. Sans ce drapeau, un 401 sur la déconnexion
/// déclenche un rafraîchissement, qui réussit, et l'utilisateur reste
/// connecté après avoir demandé à partir.
void main() {
  late DioEspion espion;
  late AuthRemoteDataSourceImpl source;

  setUp(() {
    espion = DioEspion();
    source = AuthRemoteDataSourceImpl(dio: dioDeTest(espion));
  });

  Map<String, dynamic> utilisateurJson() => {
        'id': 'u1',
        'nom': 'BEYE',
        'prenom': 'Balla',
        'email': 'balla@widjila.com',
        'role': 'ConducteurTravaux',
        'statut': 'actif',
      };

  group('connexion', () {
    test('envoie le mot de passe sous le nom attendu par le serveur', () async {
      espion.repond({
        'success': true,
        'data': {
          'utilisateur': utilisateurJson(),
          'accessToken': 'jeton-acces',
          'refreshToken': 'jeton-renouvellement',
        },
      });

      await source.login(identifiant: 'balla@widjila.com', motDePasse: 'Secret-2026');

      expect(espion.appel, 'POST /auth/login');
      final corps = espion.requete.data as Map<String, dynamic>;
      expect(corps['identifiant'], 'balla@widjila.com');
      // `mot_de_passe`, et surtout PAS `motDePasse` : le serveur ignorerait
      // le second et répondrait « identifiants incorrects ».
      expect(corps['mot_de_passe'], 'Secret-2026');
      expect(corps.containsKey('motDePasse'), isFalse);
    });

    test('des identifiants refusés ressortent en refus D AUTORISATION', () async {
      // Un 401 n'est pas une panne de serveur, et la distinction n'est pas
      // cosmetique : l'intercepteur reagit a `UnauthorizedException` en
      // tentant un renouvellement de jeton, puis en fermant la session. Le
      // ranger avec les 500 laisserait un compte deconnecte se croire encore
      // connecte jusqu'a la requete suivante.
      espion.repondErreur(401, corps: {
        'success': false,
        'message': 'Identifiants incorrects.',
      });

      await expectLater(
        source.login(identifiant: 'x@y.z', motDePasse: 'faux'),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('une panne serveur, elle, reste une panne serveur', () async {
      espion.repondErreur(500, corps: {'success': false, 'message': 'Erreur interne'});

      await expectLater(
        source.login(identifiant: 'x@y.z', motDePasse: 'bon'),
        throwsA(isA<ServerException>()),
      );
    });
  });

  test('la vérification MFA n’envoie QUE le code', () async {
    // Le mot de passe a déjà été validé à l'étape précédente : le renvoyer
    // ici l'exposerait une seconde fois sans rien apporter.
    espion.repond({
      'success': true,
      'data': {
        'utilisateur': utilisateurJson(),
        'accessToken': 'jeton-acces',
        'refreshToken': 'jeton-renouvellement',
      },
    });

    await source.verifierMfa(code: '123456');

    expect(espion.appel, 'POST /auth/mfa-verify');
    final corps = espion.requete.data as Map<String, dynamic>;
    expect(corps['code'], '123456');
    expect(corps.keys, ['code']);
  });

  group('mot de passe oublié', () {
    test('la demande passe par le module compte, pas par auth', () async {
      // Deux modules distincts côté serveur. Viser `/auth/forgot-password`
      // donnerait un 404 sur le seul parcours de secours de l'application.
      espion.repond({'success': true, 'message': 'Code envoyé', 'data': <String, dynamic>{}});

      await source.forgotPassword(email: 'balla@widjila.com');

      expect(espion.appel, 'POST /account/forgot-password');
    });

    test('la réinitialisation nomme ses trois champs en serpent', () async {
      espion.repond({'success': true, 'message': 'Mot de passe modifié', 'data': <String, dynamic>{}});

      await source.resetPassword(
        email: 'balla@widjila.com',
        otp: '654321',
        nouveauMotDePasse: 'Nouveau-2026',
      );

      expect(espion.appel, 'POST /account/reset-password');
      final corps = espion.requete.data as Map<String, dynamic>;
      expect(corps['email'], 'balla@widjila.com');
      expect(corps['otp'], '654321');
      expect(corps['nouveau_mot_de_passe'], 'Nouveau-2026');
    });
  });

  test('la déconnexion neutralise l’intercepteur de renouvellement', () async {
    // Sans ce drapeau, un 401 sur la déconnexion déclencherait un
    // rafraîchissement de jeton — qui réussirait, laissant l'utilisateur
    // connecté après avoir demandé à partir.
    espion.repond({'success': true, 'data': <String, dynamic>{}});

    await source.logout();

    expect(espion.appel, 'POST /auth/logout');
    expect(espion.requete.extra['skipAuthInterceptor'], isTrue);
  });

  test('le profil courant est relu depuis l’enveloppe « utilisateur »', () async {
    espion.repond({
      'success': true,
      'data': {'utilisateur': utilisateurJson()},
    });

    final user = await source.getMe();

    expect(espion.appel, 'GET /account/me');
    expect(user.id, 'u1');
    expect(user.email, 'balla@widjila.com');
  });
}
