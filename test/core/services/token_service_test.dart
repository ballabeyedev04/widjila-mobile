import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/services/token_service.dart';

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

/// Génère un JWT factice (header.payload.signature en base64url, non signé
/// — TokenService ne vérifie jamais la signature côté client, seulement
/// `exp`, exactement comme le vrai token émis par le backend serait lu ici).
String _fakeJwt(Map<String, dynamic> payload) {
  String b64(Map<String, dynamic> map) {
    final json = map.entries.map((e) => '"${e.key}":${_encode(e.value)}').join(',');
    final bytes = '{$json}'.codeUnits;
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  return '${b64({'alg': 'HS256'})}.${b64(payload)}.signature';
}

String _encode(dynamic v) => v is String ? '"$v"' : '$v';

void main() {
  late MockSecureStorage storage;
  late TokenService service;

  setUp(() {
    storage = MockSecureStorage();
    service = TokenService(secureStorage: storage);
  });

  tearDown(() => service.dispose());

  group('TokenService — expiration', () {
    test('isAuthenticated est false si aucun token stocké', () async {
      when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) async => null);
      expect(await service.isAuthenticated, isFalse);
    });

    test('isAuthenticated est true pour un token non expiré', () async {
      final exp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
      final token = _fakeJwt({'id': 'u1', 'exp': exp});
      when(() => storage.read(key: 'sc_jwt_token')).thenAnswer((_) async => token);

      expect(await service.isAuthenticated, isTrue);
    });

    test('isAuthenticated est false pour un token expiré', () async {
      final exp = DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
      final token = _fakeJwt({'id': 'u1', 'exp': exp});
      when(() => storage.read(key: 'sc_jwt_token')).thenAnswer((_) async => token);

      expect(await service.isAuthenticated, isFalse);
    });

    test('un token qui expire dans 10 secondes est déjà considéré expiré (marge de 30s)', () async {
      final exp = DateTime.now().add(const Duration(seconds: 10)).millisecondsSinceEpoch ~/ 1000;
      final token = _fakeJwt({'id': 'u1', 'exp': exp});
      when(() => storage.read(key: 'sc_jwt_token')).thenAnswer((_) async => token);

      expect(await service.isAuthenticated, isFalse);
    });

    // Non-régression [C11] — l'ancien comportement effaçait le token dès que
    // l'HORLOGE LOCALE le jugeait expiré. Un téléphone dont l'heure avance
    // (mise à jour automatique désactivée, cas réel) considérait alors tout
    // token comme expiré et entrait dans une boucle de déconnexion, alors que
    // le SERVEUR aurait accepté ce même token sans problème.
    //
    // `getValidToken()` renvoie donc `null` sur un token jugé expiré
    // localement (pour épargner un aller-retour réseau manifestement inutile
    // dans le cas nominal), mais ne l'efface PLUS : seul un vrai 401 du
    // serveur, après échec du refresh, déclenche l'effacement — voir
    // `dio_client_factory.dart`.
    test('getValidToken renvoie null SANS effacer un token jugé expiré localement', () async {
      final exp = DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
      final token = _fakeJwt({'id': 'u1', 'exp': exp});
      when(() => storage.read(key: 'sc_jwt_token')).thenAnswer((_) async => token);

      final result = await service.getValidToken();

      expect(result, isNull);
      verifyNever(() => storage.delete(key: any(named: 'key')));
    });

    test('un token illisible (corrompu) est traité comme invalide', () async {
      when(() => storage.read(key: 'sc_jwt_token')).thenAnswer((_) async => 'pas-un-jwt-valide');
      expect(await service.isAuthenticated, isFalse);
    });

    test('getUserId extrait l\'id depuis un token valide', () async {
      final exp = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
      final token = _fakeJwt({'id': 'user-42', 'exp': exp});
      when(() => storage.read(key: 'sc_jwt_token')).thenAnswer((_) async => token);

      expect(await service.getUserId(), 'user-42');
    });
  });

  group('TokenService — écriture', () {
    test('setToken écrit en stockage sécurisé', () async {
      when(() => storage.write(key: any(named: 'key'), value: any(named: 'value'))).thenAnswer((_) async {});
      when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) async => null);

      await service.setToken('un-token');

      verify(() => storage.write(key: 'sc_jwt_token', value: 'un-token')).called(1);
    });

    test('setToken(null) supprime le token existant plutôt que d\'écrire une valeur vide', () async {
      when(() => storage.delete(key: any(named: 'key'))).thenAnswer((_) async {});
      when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) async => null);

      await service.setToken(null);

      verify(() => storage.delete(key: 'sc_jwt_token')).called(1);
    });

    test('clearToken supprime access ET refresh token', () async {
      when(() => storage.delete(key: any(named: 'key'))).thenAnswer((_) async {});

      await service.clearToken();

      verify(() => storage.delete(key: 'sc_jwt_token')).called(1);
      verify(() => storage.delete(key: 'sc_refresh_token')).called(1);
    });
  });
}
