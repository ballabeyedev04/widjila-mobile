import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/network/cache_reponses_get.dart';
import 'package:suivie_chantier_mobile/core/offline/session_locale.dart';
import 'package:suivie_chantier_mobile/core/services/token_service.dart';
import 'package:suivie_chantier_mobile/core/services/user_cache.dart';
import 'package:suivie_chantier_mobile/core/services/verificateur_hors_ligne.dart';
import 'package:suivie_chantier_mobile/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/auth/data/models/user_model.dart';
import 'package:suivie_chantier_mobile/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:suivie_chantier_mobile/features/auth/domain/entities/login_result.dart';

class _Remote extends Mock implements AuthRemoteDataSource {}

class _Tokens extends Mock implements TokenService {}

class _Cache extends Mock implements UserCache {}

class _Session extends Mock implements SessionLocale {}

class _Verif extends Mock implements VerificateurHorsLigne {}

final _user = UserModel(
  id: 'u1',
  nom: 'Beye',
  prenom: 'Balla',
  email: 'balla@widjila.com',
  role: UserRole.chefProjet,
  statut: 'actif',
);

/// Connexion SANS réseau : ne doit s'ouvrir que pour un compte déjà
/// authentifié par le serveur, et jamais en cas de refus du serveur.
void main() {
  late _Remote remote;
  late _Tokens tokens;
  late _Cache cache;
  late _Session session;
  late _Verif verif;

  AuthRepositoryImpl construire({bool injoignable = false}) => AuthRepositoryImpl(
        remoteDataSource: remote,
        tokenService: tokens,
        userCache: cache,
        sessionLocale: session,
        cacheHttp: CacheReponsesGet(),
        verificateur: verif,
        serveurInjoignable: () => injoignable,
      );

  void reseauCoupe() => when(() => remote.login(identifiant: any(named: 'identifiant'), motDePasse: any(named: 'motDePasse')))
      .thenThrow(const NetworkException());

  void verdict(ResultatVerification r) =>
      when(() => verif.verifier(identifiant: any(named: 'identifiant'), motDePasse: any(named: 'motDePasse')))
          .thenAnswer((_) async => r);

  setUp(() {
    remote = _Remote();
    tokens = _Tokens();
    cache = _Cache();
    session = _Session();
    verif = _Verif();
    when(() => verif.effacer()).thenAnswer((_) async {});
    when(() => cache.readJson()).thenAnswer((_) async => _user.toJson());
    when(() => session.estCompatible(any())).thenAnswer((_) async => true);
    when(() => session.adopterUtilisateur(any())).thenAnswer((_) async {});
  });

  test('sans réseau + compte connu + bons identifiants → session hors ligne SANS jeton', () async {
    reseauCoupe();
    verdict(const ResultatVerification.accepte('u1'));

    final r = await construire().login(identifiant: 'balla@widjila.com', motDePasse: 'x');

    final res = r.getOrElse(() => throw 'attendu Right');
    expect(res.horsLigne, isTrue);
    expect(res.utilisateur.id, 'u1');
    verifyNever(() => tokens.setToken(any()));
    verifyNever(() => tokens.setRefreshToken(any()));
  });

  test('sans réseau + aucun compte connu → connexion Internet requise', () async {
    reseauCoupe();
    verdict(const ResultatVerification.refuse(RefusHorsLigne.aucunCompte));

    final r = await construire().login(identifiant: 'x', motDePasse: 'y');

    r.fold((f) {
      expect(f, isA<NetworkFailure>());
      expect(f.errorMessage, contains('Internet'));
    }, (_) => fail('ne doit pas s\'ouvrir'));
  });

  test('sans réseau + mauvais mot de passe → refus', () async {
    reseauCoupe();
    verdict(const ResultatVerification.refuse(RefusHorsLigne.identifiantsInvalides));
    final r = await construire().login(identifiant: 'x', motDePasse: 'y');
    expect(r.isLeft(), isTrue);
  });

  test('un refus du SERVEUR n\'ouvre jamais l\'accès local', () async {
    when(() => remote.login(identifiant: any(named: 'identifiant'), motDePasse: any(named: 'motDePasse')))
        .thenThrow(const UnauthorizedException(message: 'Identifiants invalides'));
    verdict(const ResultatVerification.accepte('u1')); // même si le local dirait oui

    final r = await construire().login(identifiant: 'x', motDePasse: 'y');

    expect(r.isLeft(), isTrue);
    verifyNever(() => verif.verifier(identifiant: any(named: 'identifiant'), motDePasse: any(named: 'motDePasse')));
  });

  test('compte désactivé (403) → l\'accès local est retiré', () async {
    when(() => remote.login(identifiant: any(named: 'identifiant'), motDePasse: any(named: 'motDePasse')))
        .thenThrow(const ServerException(message: 'Compte désactivé', statusCode: 403));
    final r = await construire().login(identifiant: 'x', motDePasse: 'y');
    expect(r.isLeft(), isTrue);
    verify(() => verif.effacer()).called(1);
  });

  test('profil en cache d\'un AUTRE compte → refus', () async {
    reseauCoupe();
    verdict(const ResultatVerification.accepte('u2'));
    final r = await construire().login(identifiant: 'x', motDePasse: 'y');
    expect(r.isLeft(), isTrue);
  });

  test('données locales d\'un autre compte → refus, SANS purge', () async {
    reseauCoupe();
    verdict(const ResultatVerification.accepte('u1'));
    when(() => session.estCompatible('u1')).thenAnswer((_) async => false);

    final r = await construire().login(identifiant: 'x', motDePasse: 'y');

    expect(r.isLeft(), isTrue);
    verifyNever(() => session.adopterUtilisateur(any()));
    verifyNever(() => session.purger());
  });

  test('profil local désactivé → refus', () async {
    reseauCoupe();
    verdict(const ResultatVerification.accepte('u1'));
    when(() => cache.readJson()).thenAnswer((_) async => {..._user.toJson(), 'statut': 'suspendu'});
    expect((await construire().login(identifiant: 'x', motDePasse: 'y')).isLeft(), isTrue);
  });

  test('serveur déjà connu injoignable : accès local direct, sans appel réseau', () async {
    verdict(const ResultatVerification.accepte('u1'));
    final r = await construire(injoignable: true).login(identifiant: 'x', motDePasse: 'y');
    expect(r.getOrElse(() => throw 'attendu Right').horsLigne, isTrue);
    verifyNever(() => remote.login(identifiant: any(named: 'identifiant'), motDePasse: any(named: 'motDePasse')));
  });

  test('sonde « hors ligne » mais serveur joignable → connexion en ligne normale', () async {
    verdict(const ResultatVerification.refuse(RefusHorsLigne.aucunCompte));
    when(() => remote.login(identifiant: any(named: 'identifiant'), motDePasse: any(named: 'motDePasse')))
        .thenAnswer((_) async => AuthResponseModel(token: 't', refreshToken: 'r', mfaRequise: false, utilisateur: _user));
    when(() => tokens.setToken(any())).thenAnswer((_) async {});
    when(() => tokens.setRefreshToken(any())).thenAnswer((_) async {});
    when(() => cache.saveJson(any())).thenAnswer((_) async {});
    when(() => verif.enregistrer(
          utilisateurId: any(named: 'utilisateurId'),
          identifiants: any(named: 'identifiants'),
          motDePasse: any(named: 'motDePasse'),
        )).thenAnswer((_) async {});

    final r = await construire(injoignable: true).login(identifiant: 'x', motDePasse: 'y');

    expect(r.getOrElse(() => throw 'attendu Right').horsLigne, isFalse);
    verify(() => verif.enregistrer(
          utilisateurId: 'u1',
          identifiants: any(named: 'identifiants'),
          motDePasse: 'y',
        )).called(1);
  });

  test('connexion en ligne avec MFA → aucun accès hors ligne, enregistrement effacé', () async {
    when(() => remote.login(identifiant: any(named: 'identifiant'), motDePasse: any(named: 'motDePasse')))
        .thenAnswer((_) async => AuthResponseModel(token: null, refreshToken: null, mfaRequise: true, utilisateur: _user));

    final r = await construire().login(identifiant: 'x', motDePasse: 'y');

    expect(r.getOrElse(() => throw 'attendu Right'), isA<LoginResult>());
    verify(() => verif.effacer()).called(1);
    verifyNever(() => verif.enregistrer(
          utilisateurId: any(named: 'utilisateurId'),
          identifiants: any(named: 'identifiants'),
          motDePasse: any(named: 'motDePasse'),
        ));
  });
}
