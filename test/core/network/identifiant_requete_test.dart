import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/network/cache_reponses_get.dart';
import 'package:suivie_chantier_mobile/core/network/dio_client_factory.dart';
import 'package:suivie_chantier_mobile/core/network/identifiant_requete.dart';
import 'package:suivie_chantier_mobile/core/services/token_service.dart';

class _MockTokenService extends Mock implements TokenService {}

/// Adaptateur scénarisé : garde les en-têtes de chaque requête RÉELLEMENT émise.
class _Adaptateur implements HttpClientAdapter {
  final FutureOr<ResponseBody> Function(RequestOptions options, int rang) repondre;
  final List<Map<String, dynamic>> entetes = [];

  _Adaptateur(this.repondre);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    if (requestStream != null) await requestStream.drain<void>();
    entetes.add({...options.headers});
    return repondre(options, entetes.length);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _ok() => ResponseBody.fromString(
      jsonEncode({'success': true, 'data': <String, dynamic>{}}),
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );

final _uuidV4 = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

/// Audit observabilité — identifiant de corrélation `X-Request-Id`.
///
/// Avant : aucune requête du mobile ne portait d'identifiant. Une erreur vue
/// sur un téléphone ne pouvait pas être retrouvée dans les journaux serveur,
/// sinon en croisant l'heure et la route.
void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  group('identifiantRequete', () {
    test('hors synchronisation : un UUID v4 neuf à chaque appel', () {
      final a = identifiantRequete();
      final b = identifiantRequete();

      expect(a, matches(_uuidV4));
      expect(a, isNot(b));
    });

    test('dans une action de synchronisation : l’identifiant de l’action', () {
      const idAction = '0f3c9a2b-7d41-4e8a-9c55-2b1e6f0a9d13';

      final lu = runZoned(identifiantRequete, zoneValues: {cleZoneIdOperation: idAction});

      expect(lu, idAction);
    });

    test('un identifiant de zone hors format (le serveur le rejetterait) est remplacé', () {
      final lu = runZoned(identifiantRequete, zoneValues: {cleZoneIdOperation: 'pas valide'});

      expect(lu, matches(_uuidV4));
    });
  });

  group('intercepteur', () {
    late _MockTokenService jetons;

    setUp(() {
      jetons = _MockTokenService();
      when(() => jetons.getValidToken()).thenAnswer((_) async => 'jeton');
    });

    Future<Dio> construire(_Adaptateur adaptateur) async {
      final dio = await DioClientFactory.create(tokenService: jetons, cache: CacheReponsesGet());
      dio.httpClientAdapter = adaptateur;
      return dio;
    }

    test('chaque requête vers l’API porte un X-Request-Id', () async {
      final adaptateur = _Adaptateur((_, _) => _ok());
      final dio = await construire(adaptateur);

      await dio.get<dynamic>('/chantiers');

      expect(adaptateur.entetes.single['X-Request-Id'], matches(_uuidV4));
    });

    test('une requête de synchronisation porte l’identifiant de son action', () async {
      final adaptateur = _Adaptateur((_, _) => _ok());
      final dio = await construire(adaptateur);
      const idAction = 'a1b2c3d4-0000-4000-8000-000000000001';

      await runZoned(() => dio.post<dynamic>('/reserves', data: {'titre': 'x'}),
          zoneValues: {cleZoneIdOperation: idAction});

      expect(adaptateur.entetes.single['X-Request-Id'], idAction);
    });

    test('un rejeu (délai de connexion) garde le MÊME identifiant', () async {
      final adaptateur = _Adaptateur((o, rang) {
        if (rang == 1) throw DioException(requestOptions: o, type: DioExceptionType.connectionTimeout);
        return _ok();
      });
      final dio = await construire(adaptateur);

      await dio.get<dynamic>('/reserves');

      expect(adaptateur.entetes, hasLength(2));
      expect(adaptateur.entetes[1]['X-Request-Id'], adaptateur.entetes[0]['X-Request-Id']);
    });

    test('rien n’est envoyé à un autre hôte que l’API (CDN des photos)', () async {
      final adaptateur = _Adaptateur((_, _) => _ok());
      final dio = await construire(adaptateur);

      await dio.get<dynamic>('https://cdn.exemple.test/images/profils/a.png');

      expect(adaptateur.entetes.single.containsKey('X-Request-Id'), isFalse);
    });
  });
}
