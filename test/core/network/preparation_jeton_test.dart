import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/network/cache_reponses_get.dart';
import 'package:suivie_chantier_mobile/core/network/dio_client_factory.dart';
import 'package:suivie_chantier_mobile/core/services/token_service.dart';

class _MockTokenService extends Mock implements TokenService {}

/// Adaptateur qui compte les requetes REELLEMENT emises.
class _AdaptateurCompteur implements HttpClientAdapter {
  int appels = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    appels++;
    return ResponseBody.fromString('{}', 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

/// La preparation du jeton se deroule AVANT l'emission de la requete, donc
/// hors des `connectTimeout` / `receiveTimeout` de Dio.
///
/// ## Ce qui s'etait casse
///
/// Une lecture du stockage securise qui ne rendait jamais la main n'echouait
/// pas — elle ne se terminait pas. `handler.next()` n'etait jamais appele, la
/// requete jamais emise, donc aucun delai Dio ne pouvait courir. Le cubit
/// restait sur `chargement` indefiniment : un ecran de squelette gris sans
/// erreur, sans bouton « Reessayer », et sans rien pour comprendre.
void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  late _MockTokenService jetons;
  late _AdaptateurCompteur adaptateur;

  Future<Dio> construire() async {
    final dio = await DioClientFactory.create(
      tokenService: jetons,
      cache: CacheReponsesGet(),
      delaiJeton: const Duration(milliseconds: 80),
    );
    dio.httpClientAdapter = adaptateur;
    return dio;
  }

  setUp(() {
    jetons = _MockTokenService();
    adaptateur = _AdaptateurCompteur();
  });

  test('une lecture de jeton qui ne rend JAMAIS la main echoue au lieu de figer', () async {
    when(() => jetons.getValidToken())
        .thenAnswer((_) => Completer<String?>().future);

    final dio = await construire();

    await expectLater(
      dio.get('/reserves'),
      throwsA(isA<DioException>().having(
        (e) => e.type,
        'type',
        DioExceptionType.connectionTimeout,
      )),
    );
    expect(adaptateur.appels, 0, reason: 'la requete n’a jamais pu partir');
  });

  test('le rejet est une erreur RESEAU, pas un 401 — la session n’est pas purgee', () async {
    // Un blocage de la preparation ne dit rien sur la validite de la session.
    // La traiter comme refusee deconnecterait l'utilisateur pour un incident
    // passager.
    when(() => jetons.getValidToken())
        .thenAnswer((_) => Completer<String?>().future);

    final dio = await construire();

    try {
      await dio.get('/reserves');
      fail('la requete aurait du echouer');
    } on DioException catch (e) {
      expect(e.response?.statusCode, isNot(401));
      expect(e.type, DioExceptionType.connectionTimeout);
    }
    verifyNever(() => jetons.clearToken());
  });

  test('un jeton normal passe sans entrave et porte l’en-tete Authorization', () async {
    when(() => jetons.getValidToken()).thenAnswer((_) async => 'jeton-valide');

    final dio = await construire();
    final reponse = await dio.get('/reserves');

    expect(reponse.statusCode, 200);
    expect(adaptateur.appels, 1);
    expect(
      reponse.requestOptions.headers['Authorization'],
      'Bearer jeton-valide',
    );
  });
}
