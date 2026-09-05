import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/core/network/cache_reponses_get.dart';
import 'package:suivie_chantier_mobile/core/offline/session_locale.dart';
import 'package:suivie_chantier_mobile/core/services/token_service.dart';
import 'package:suivie_chantier_mobile/core/services/user_cache.dart';
import 'package:suivie_chantier_mobile/features/auth/data/datasources/auth_remote_datasource.dart';
import 'package:suivie_chantier_mobile/features/auth/data/repositories/auth_repository_impl.dart';

class _MockRemote extends Mock implements AuthRemoteDataSource {}

class _MockTokens extends Mock implements TokenService {}

class _MockUserCache extends Mock implements UserCache {}

class _MockSession extends Mock implements SessionLocale {}

class _AdaptateurMuet implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    return ResponseBody.fromString('{"success":true,"data":{}}', 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

/// La deconnexion doit purger le cache memoire des reponses `GET`.
///
/// ## Ce qui s'etait casse
///
/// `CacheReponsesGet` se vide tout seul des qu'une ECRITURE part (POST, PUT,
/// PATCH, DELETE). Or la deconnexion est entierement LOCALE : purge SQLite,
/// effacement des jetons, vidage du cache utilisateur — aucune requete
/// reseau. Cette purge automatique ne s'executait donc jamais, et jusqu'a
/// soixante reponses du compte precedent (tableau de bord, reserves, liste
/// des membres) restaient servibles pendant trente secondes au compte
/// suivant.
///
/// Le code voisin purgeait deja les donnees SQLite et le cache utilisateur
/// « pour le compte suivant ». Ce cache-ci, ajoute plus tard, manquait a la
/// liste.
void main() {
  late _MockRemote remote;
  late _MockTokens tokens;
  late _MockUserCache userCache;
  late _MockSession session;
  late CacheReponsesGet cache;
  late Dio dio;

  setUp(() {
    remote = _MockRemote();
    tokens = _MockTokens();
    userCache = _MockUserCache();
    session = _MockSession();
    cache = CacheReponsesGet();

    when(() => tokens.clearToken()).thenAnswer((_) async {});
    when(() => userCache.clear()).thenAnswer((_) async {});
    when(() => session.purger()).thenAnswer((_) async {});

    dio = Dio(BaseOptions(baseUrl: 'https://exemple.test'))
      ..httpClientAdapter = _AdaptateurMuet()
      ..interceptors.add(cache);
  });

  AuthRepositoryImpl construire() => AuthRepositoryImpl(
        remoteDataSource: remote,
        tokenService: tokens,
        userCache: userCache,
        sessionLocale: session,
        cacheHttp: cache,
      );

  test('logout() vide le cache des reponses GET', () async {
    await dio.get('/dashboard');
    await dio.get('/reserves');
    expect(cache.taille, 2, reason: 'les deux reponses du compte A sont en cache');

    await construire().logout();

    expect(cache.taille, 0,
        reason: 'aucune reponse du compte precedent ne doit survivre a la deconnexion');
  });

  test('logout() purge AUSSI le reste — la correction n’a rien retire', () async {
    await construire().logout();

    verify(() => session.purger()).called(1);
    verify(() => tokens.clearToken()).called(1);
    verify(() => userCache.clear()).called(1);
  });

  test('une session non restaurable purge le cache elle aussi', () async {
    // Jeton revoque, compte desactive : meme exigence, le compte suivant ne
    // doit rien pouvoir lire de l'ancien.
    await dio.get('/dashboard');
    expect(cache.taille, 1);

    when(() => tokens.getRefreshToken()).thenAnswer((_) async => 'jeton-rafraichissement');
    when(() => remote.getMe()).thenThrow(Exception('session invalide'));

    final utilisateur = await construire().restaurerSession();

    expect(utilisateur, isNull);
    expect(cache.taille, 0);
  });

  group('demarrage SANS RESEAU', () {
    // `restaurerSession()` appelle `GET /account/me`. Sans reseau, l'echec
    // tombait dans le `catch (_)` unique et effacait les jetons : lancer
    // l'application hors couverture DECONNECTAIT l'utilisateur, et lui
    // retirait l'acces a ses reserves hors ligne et a sa file d'envoi.
    //
    // Le profil chiffre etait pourtant ecrit a chaque connexion — mais
    // `readJson()` n'avait aucun appelant dans tout le code.
    setUp(() {
      when(() => tokens.getRefreshToken()).thenAnswer((_) async => 'jeton-rafraichissement');
      when(() => remote.getMe()).thenThrow(const NetworkException(message: 'Pas de connexion'));
    });

    test('la session est restauree depuis le profil chiffre', () async {
      when(() => userCache.readJson()).thenAnswer((_) async => {
            'id': 'u1',
            'nom': 'BEYE',
            'prenom': 'Balla',
            'email': 'balla@widjila.com',
            'role': 'Entreprise',
            'statut': 'actif',
          });

      final utilisateur = await construire().restaurerSession();

      expect(utilisateur, isNotNull);
      expect(utilisateur!.email, 'balla@widjila.com');
    });

    test('les jetons ne sont PAS effaces — c’est le serveur qui juge, pas le repli', () async {
      when(() => userCache.readJson()).thenAnswer((_) async => {
            'id': 'u1', 'nom': 'BEYE', 'prenom': 'Balla',
            'email': 'balla@widjila.com', 'role': 'Entreprise', 'statut': 'actif',
          });

      await construire().restaurerSession();

      verifyNever(() => tokens.clearToken());
      verifyNever(() => userCache.clear());
    });

    test('sans profil en cache, on renonce SANS effacer les jetons', () async {
      when(() => userCache.readJson()).thenAnswer((_) async => null);

      expect(await construire().restaurerSession(), isNull);
      verifyNever(() => tokens.clearToken());
    });

    test('une session REELLEMENT invalide efface bien tout', () async {
      // Le contre-exemple : un jeton revoque n'est pas une panne reseau.
      when(() => remote.getMe()).thenThrow(Exception('401'));

      expect(await construire().restaurerSession(), isNull);
      verify(() => tokens.clearToken()).called(1);
      verify(() => userCache.clear()).called(1);
    });
  });
}
