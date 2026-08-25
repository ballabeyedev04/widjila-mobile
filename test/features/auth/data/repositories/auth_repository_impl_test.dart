import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/config/user_role.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/core/errors/failure.dart';
import 'package:suivie_chantier_mobile/core/offline/session_locale.dart';
import 'package:suivie_chantier_mobile/core/services/token_service.dart';
import 'package:suivie_chantier_mobile/core/services/user_cache.dart';
import 'package:suivie_chantier_mobile/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/auth/data/models/user_model.dart';
import 'package:suivie_chantier_mobile/features/auth/data/repositories/auth_repository_impl.dart';

class MockAuthRemoteDataSource extends Mock implements AuthRemoteDataSource {}

class MockTokenService extends Mock implements TokenService {}

class MockUserCache extends Mock implements UserCache {}

class MockSessionLocale extends Mock implements SessionLocale {}

final tUserModel = UserModel(
  id: 'u1',
  nom: 'Beye',
  prenom: 'Balla',
  email: 'balla@widjila.com',
  role: UserRole.chefProjet,
  statut: 'actif',
);

void main() {
  late MockAuthRemoteDataSource remoteDataSource;
  late MockTokenService tokenService;
  late MockUserCache userCache;
  late MockSessionLocale sessionLocale;
  late AuthRepositoryImpl repository;

  setUp(() {
    remoteDataSource = MockAuthRemoteDataSource();
    tokenService = MockTokenService();
    userCache = MockUserCache();
    sessionLocale = MockSessionLocale();
    repository = AuthRepositoryImpl(
      remoteDataSource: remoteDataSource,
      tokenService: tokenService,
      userCache: userCache,
      sessionLocale: sessionLocale,
    );

    when(() => tokenService.setToken(any())).thenAnswer((_) async {});
    when(() => tokenService.setRefreshToken(any())).thenAnswer((_) async {});
    when(() => userCache.saveJson(any())).thenAnswer((_) async {});
    when(() => sessionLocale.adopterUtilisateur(any())).thenAnswer((_) async {});
    when(() => sessionLocale.purger()).thenAnswer((_) async {});
  });

  group('login', () {
    test('stocke access token ET refresh token quand le MFA n\'est pas requis', () async {
      when(() => remoteDataSource.login(identifiant: any(named: 'identifiant'), motDePasse: any(named: 'motDePasse')))
          .thenAnswer((_) async => AuthResponseModel(
                token: 'access-123',
                refreshToken: 'refresh-456',
                mfaRequise: false,
                utilisateur: tUserModel,
              ));

      final result = await repository.login(identifiant: 'x', motDePasse: 'y');

      expect(result, isA<Right>());
      verify(() => tokenService.setToken('access-123')).called(1);
      verify(() => tokenService.setRefreshToken('refresh-456')).called(1);
      verify(() => userCache.saveJson(any())).called(1);
    });

    test('ne stocke AUCUN token quand le MFA est requis (pas encore authentifié)', () async {
      when(() => remoteDataSource.login(identifiant: any(named: 'identifiant'), motDePasse: any(named: 'motDePasse')))
          .thenAnswer((_) async => AuthResponseModel(
                token: null,
                refreshToken: null,
                mfaRequise: true,
                utilisateur: tUserModel,
              ));

      final result = await repository.login(identifiant: 'x', motDePasse: 'y');

      expect(result, isA<Right>());
      final loginResult = (result as Right).value;
      expect(loginResult.mfaRequise, isTrue);
      verifyNever(() => tokenService.setToken(any()));
      verifyNever(() => tokenService.setRefreshToken(any()));
    });

    test('convertit UnauthorizedException en AuthFailure', () async {
      when(() => remoteDataSource.login(identifiant: any(named: 'identifiant'), motDePasse: any(named: 'motDePasse')))
          .thenThrow(const UnauthorizedException(message: 'Identifiants invalides'));

      final result = await repository.login(identifiant: 'x', motDePasse: 'y');

      expect(result, const Left(AuthFailure(errorMessage: 'Identifiants invalides')));
    });
  });

  group('logout', () {
    test('vide le stockage local MÊME si la révocation réseau échoue', () async {
      when(() => remoteDataSource.logout()).thenThrow(Exception('réseau down'));
      when(() => tokenService.clearToken()).thenAnswer((_) async {});
      when(() => userCache.clear()).thenAnswer((_) async {});

      await repository.logout();

      verify(() => tokenService.clearToken()).called(1);
      verify(() => userCache.clear()).called(1);
    });

    // Non-régression [C2] — la purge des données hors ligne doit précéder
    // l'effacement du jeton. Ordre inverse : un process tué entre les deux
    // laissait chantiers, réserves ET file d'attente du compte précédent
    // lisibles et synchronisables par le compte suivant.
    test('purge les données hors ligne AVANT d\'effacer le jeton', () async {
      when(() => remoteDataSource.logout()).thenAnswer((_) async {});
      when(() => tokenService.clearToken()).thenAnswer((_) async {});
      when(() => userCache.clear()).thenAnswer((_) async {});

      await repository.logout();

      verifyInOrder([
        () => sessionLocale.purger(),
        () => tokenService.clearToken(),
      ]);
    });
  });

  group('restaurerSession', () {
    test('renvoie null sans appeler le backend si aucun refresh token n\'existe', () async {
      when(() => tokenService.getRefreshToken()).thenAnswer((_) async => null);

      final result = await repository.restaurerSession();

      expect(result, isNull);
      verifyNever(() => remoteDataSource.getMe());
    });

    test('renvoie l\'utilisateur et le met en cache si le refresh token existe', () async {
      when(() => tokenService.getRefreshToken()).thenAnswer((_) async => 'refresh-456');
      when(() => remoteDataSource.getMe()).thenAnswer((_) async => tUserModel);

      final result = await repository.restaurerSession();

      expect(result, tUserModel);
      verify(() => userCache.saveJson(any())).called(1);
    });

    test('vide tokens+cache et renvoie null si /account/me échoue', () async {
      when(() => tokenService.getRefreshToken()).thenAnswer((_) async => 'refresh-456');
      when(() => remoteDataSource.getMe()).thenThrow(const UnauthorizedException());
      when(() => tokenService.clearToken()).thenAnswer((_) async {});
      when(() => userCache.clear()).thenAnswer((_) async {});

      final result = await repository.restaurerSession();

      expect(result, isNull);
      verify(() => tokenService.clearToken()).called(1);
      verify(() => userCache.clear()).called(1);
    });

    // Non-régression [C3] — une session non restaurable (jeton révoqué,
    // réseau absent au démarrage) ne doit JAMAIS purger les données locales :
    // elles contiennent le travail hors ligne que le même utilisateur vient
    // récupérer en se reconnectant. Une version précédente les effaçait,
    // détruisant sans un mot des heures de relevés.
    test('ne purge PAS les données hors ligne quand la session est irrécupérable', () async {
      when(() => tokenService.getRefreshToken()).thenAnswer((_) async => 'refresh-456');
      when(() => remoteDataSource.getMe()).thenThrow(const UnauthorizedException());
      when(() => tokenService.clearToken()).thenAnswer((_) async {});
      when(() => userCache.clear()).thenAnswer((_) async {});

      await repository.restaurerSession();

      verifyNever(() => sessionLocale.purger());
    });

    // Non-régression [C2] — le contrôle de propriétaire s'exécute à CHAQUE
    // authentification réussie, y compris la restauration au démarrage :
    // c'est ce qui rattrape une déconnexion précédente interrompue par un
    // kill, seul chemin qu'une purge au logout ne peut pas garantir.
    test('déclare le propriétaire des données locales à la restauration', () async {
      when(() => tokenService.getRefreshToken()).thenAnswer((_) async => 'refresh-456');
      when(() => remoteDataSource.getMe()).thenAnswer((_) async => tUserModel);

      await repository.restaurerSession();

      verify(() => sessionLocale.adopterUtilisateur(tUserModel.id)).called(1);
    });
  });
}
