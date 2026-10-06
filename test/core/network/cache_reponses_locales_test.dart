import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:suivie_chantier_mobile/core/network/cache_reponses_locales.dart';
import 'package:suivie_chantier_mobile/core/offline/base_locale.dart';
import 'package:suivie_chantier_mobile/core/offline/reponses_locales.dart';

/// Adaptateur scriptable : répond, ou simule une coupure réseau.
class _Reseau implements HttpClientAdapter {
  bool coupe = false;
  int appels = 0;
  int statut = 200;
  final Map<String, Object> corps = {};

  /// Retient la réponse tant qu'il n'est pas complété (requête « en vol »).
  Completer<void>? porte;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    appels++;
    await porte?.future;
    if (coupe) {
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError, error: 'coupé');
    }
    final c = corps[options.uri.path] ?? <String, Object>{};
    if (c is List<int>) {
      return ResponseBody.fromBytes(c, statut, headers: {
        Headers.contentTypeHeader: ['application/pdf']
      });
    }
    return ResponseBody.fromString(jsonEncode(c), statut, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

/// La copie locale est ce qui permet d'ouvrir un plan, la structure et le
/// formulaire de réserve SANS réseau (guide hors connexion, §14).
void main() {
  late _Reseau reseau;
  late Dio dio;
  var injoignable = false;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    BaseLocale.surchargeNomFichier = 'test_reponses_locales.db';
  });

  setUp(() async {
    await BaseLocale.instance.fermer();
    await databaseFactory.deleteDatabase('${await getDatabasesPath()}/test_reponses_locales.db');
    injoignable = false;
    reseau = _Reseau();
    dio = Dio(BaseOptions(baseUrl: 'https://api.test/api/v1'))
      ..httpClientAdapter = reseau
      ..interceptors.add(CacheReponsesLocales(
        stock: ReponsesLocales(BaseLocale.instance),
        serveurInjoignable: () => injoignable,
      ));
  });

  tearDown(() => BaseLocale.instance.fermer());

  /// L'écriture est lancée sans attente (`unawaited`) : on laisse la main.
  Future<void> laisserEcrire() => Future<void>.delayed(const Duration(milliseconds: 150));

  test('une lecture réussie est rejouée telle quelle quand le réseau coupe', () async {
    reseau.corps['/api/v1/chantiers/c1/structure'] = {'batiments': ['A', 'B']};
    final enLigne = await dio.get<dynamic>('/chantiers/c1/structure');
    expect(enLigne.data['batiments'], ['A', 'B']);
    await laisserEcrire();

    reseau.coupe = true;
    final horsLigne = await dio.get<dynamic>('/chantiers/c1/structure');

    expect(horsLigne.data['batiments'], ['A', 'B']);
    expect(horsLigne.extra[CacheReponsesLocales.marqueurServie], isTrue);
  });

  test('serveur déjà connu injoignable : copie servie SANS tenter le réseau', () async {
    reseau.corps['/api/v1/corps-etat/actifs'] = {'data': ['Maçonnerie']};
    await dio.get<dynamic>('/corps-etat/actifs');
    await laisserEcrire();
    final avant = reseau.appels;

    injoignable = true;
    final r = await dio.get<dynamic>('/corps-etat/actifs');

    expect(r.data['data'], ['Maçonnerie']);
    expect(reseau.appels, avant, reason: 'aucune requête ne doit partir');
  });

  test('les fichiers (plans) sont conservés octet pour octet', () async {
    final pdf = List<int>.generate(2048, (i) => i % 251);
    reseau.corps['/api/v1/uploads/plans/p1.pdf'] = pdf;
    await dio.get<List<int>>('/uploads/plans/p1.pdf', options: Options(responseType: ResponseType.bytes));
    await laisserEcrire();

    reseau.coupe = true;
    final r = await dio.get<List<int>>('/uploads/plans/p1.pdf', options: Options(responseType: ResponseType.bytes));

    expect(r.data, pdf);
  });

  test('un refus du SERVEUR (404, 500) n\'est jamais remplacé par la copie', () async {
    reseau.corps['/api/v1/plans'] = {'ok': true};
    await dio.get<dynamic>('/plans');
    await laisserEcrire();

    reseau.statut = 500;
    await expectLater(dio.get<dynamic>('/plans'), throwsA(isA<DioException>()));
  });

  test('sans copie, l\'erreur est marquée « non téléchargé »', () async {
    reseau.coupe = true;
    try {
      await dio.get<dynamic>('/chantiers/c9/structure');
      fail('doit échouer');
    } on DioException catch (e) {
      expect(e.requestOptions.extra[CacheReponsesLocales.marqueurNonTelecharge], isTrue);
    }
  });

  group('ne touche jamais', () {
    RequestOptions get(String chemin) =>
        RequestOptions(path: chemin, baseUrl: 'https://api.test/api/v1', method: 'GET');

    test('les réserves et chantiers (dépôts à base locale propre)', () {
      for (final c in ['/reserves', '/reserves/r1', '/chantiers', '/chantiers/c1', '/chantiers/c1/reserves']) {
        expect(CacheReponsesLocales.jsonAdmissible(get(c)), isFalse, reason: c);
      }
    });

    test('authentification, synchronisation, vivacité, profil', () {
      for (final c in ['/auth/login', '/sync/reserves', '/health/live', '/account/me']) {
        expect(CacheReponsesLocales.jsonAdmissible(get(c)), isFalse, reason: c);
      }
    });

    test('les écritures', () {
      expect(CacheReponsesLocales.jsonAdmissible(RequestOptions(path: '/plans', baseUrl: 'https://api.test/api/v1', method: 'POST')),
          isFalse);
    });

    test('mais bien les plans, la structure et les référentiels', () {
      for (final c in ['/plans', '/plans/p1', '/chantiers/c1/plans', '/chantiers/c1/structure', '/corps-etat/actifs', '/phases']) {
        expect(CacheReponsesLocales.jsonAdmissible(get(c)), isTrue, reason: c);
      }
    });
  });

  test('l\'ordre des paramètres ne change pas la clé', () {
    final a = RequestOptions(path: '/plans', baseUrl: 'https://api.test/api/v1', queryParameters: {'a': 1, 'b': 2});
    final b = RequestOptions(path: '/plans', baseUrl: 'https://api.test/api/v1', queryParameters: {'b': 2, 'a': 1});
    expect(CacheReponsesLocales.cle(a), CacheReponsesLocales.cle(b));
  });

  test('une réponse qui arrive APRÈS un changement de compte n\'est pas écrite', () async {
    reseau.corps['/api/v1/plans'] = {'compteA': true};
    reseau.porte = Completer<void>();
    final enVol = dio.get<dynamic>('/plans');
    await Future<void>.delayed(const Duration(milliseconds: 50)); // la requête est partie
    BaseLocale.generationPurge++; // un autre compte a pris la main
    reseau.porte!.complete();
    await enVol;
    await laisserEcrire();

    reseau.coupe = true;
    try {
      await dio.get<dynamic>('/plans');
      fail('la copie du compte précédent ne doit pas exister');
    } on DioException catch (_) {}
  });

  test('viderTout supprime les copies (isolation entre comptes)', () async {
    reseau.corps['/api/v1/plans'] = {'x': 1};
    await dio.get<dynamic>('/plans');
    await laisserEcrire();
    await BaseLocale.instance.viderTout();

    reseau.coupe = true;
    try {
      await dio.get<dynamic>('/plans');
      fail('doit échouer');
    } on DioException catch (_) {}
  });
}
