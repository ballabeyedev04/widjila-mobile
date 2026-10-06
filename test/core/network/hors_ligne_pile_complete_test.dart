import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:suivie_chantier_mobile/core/errors/exceptions.dart';
import 'package:suivie_chantier_mobile/core/network/cache_reponses_get.dart';
import 'package:suivie_chantier_mobile/core/network/cache_reponses_locales.dart';
import 'package:suivie_chantier_mobile/core/network/dio_client_factory.dart';
import 'package:suivie_chantier_mobile/core/offline/base_locale.dart';
import 'package:suivie_chantier_mobile/core/offline/reponses_locales.dart';
import 'package:suivie_chantier_mobile/core/services/token_service.dart';
import 'package:suivie_chantier_mobile/features/plan/data/datasources/plan_remote_datasource.dart';

class _Tokens extends Mock implements TokenService {}

class _Reseau implements HttpClientAdapter {
  bool coupe = false;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (coupe) {
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError, error: 'coupé');
    }
    return ResponseBody.fromString('{"success":true,"data":{"plans":[]}}', 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

/// La PILE RÉELLE (copie locale + cache mémoire + authentification + relances)
/// sans réseau : ce que l'utilisateur voit dans l'écran des plans.
void main() {
  late _Reseau reseau;
  late Dio dio;
  var injoignable = false;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    BaseLocale.surchargeNomFichier = 'test_pile_complete.db';
  });

  setUp(() async {
    await BaseLocale.instance.fermer();
    await databaseFactory.deleteDatabase('${await getDatabasesPath()}/test_pile_complete.db');
    injoignable = false;
    reseau = _Reseau();
    final tokens = _Tokens();
    when(() => tokens.getValidToken()).thenAnswer((_) async => 'jeton');
    dio = await DioClientFactory.create(
      tokenService: tokens,
      cache: CacheReponsesGet(),
      copieLocale: CacheReponsesLocales(
        stock: ReponsesLocales(BaseLocale.instance),
        serveurInjoignable: () => injoignable,
      ),
    );
    dio.options.baseUrl = 'https://api.test/api/v1';
    dio.httpClientAdapter = reseau;
  });

  tearDown(() => BaseLocale.instance.fermer());

  test('contenu jamais téléchargé, réseau coupé : le message dit quoi faire (pas « erreur réseau »)', () async {
    reseau.coupe = true;
    injoignable = true;
    final source = PlanRemoteDataSourceImpl(dio: dio);

    await expectLater(
      source.getPlansRacines('c1'),
      throwsA(isA<NetworkException>().having((e) => e.message, 'message', contains('disponible hors connexion'))),
    );
  });

  test('contenu déjà vu : servi sans réseau, aucune erreur', () async {
    final source = PlanRemoteDataSourceImpl(dio: dio);
    await source.getPlansRacines('c1');
    await Future<void>.delayed(const Duration(milliseconds: 200));

    reseau.coupe = true;
    injoignable = true;
    expect(await source.getPlansRacines('c1'), isEmpty);
  });

  test('même quand la détection se trompe (se croit en ligne) : la copie sert', () async {
    final source = PlanRemoteDataSourceImpl(dio: dio);
    await source.getPlansRacines('c1');
    await Future<void>.delayed(const Duration(milliseconds: 200));

    reseau.coupe = true;
    injoignable = false;
    expect(await source.getPlansRacines('c1'), isEmpty);
  });
}
