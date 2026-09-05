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

  /// Le stockage sécurisé n'est lu QU'UNE FOIS par session.
  ///
  /// ## Ce que ça coûtait
  ///
  /// L'intercepteur Dio demande le jeton avant CHAQUE requête. Chaque appel
  /// descendait au trousseau : aller-retour de canal de plateforme, plus un
  /// déchiffrement — et sur Android, l'initialisation du magasin de clés au
  /// premier accès. Un écran qui lance quatre requêtes payait quatre fois ce
  /// prix avant que la moindre n'atteigne le réseau.
  ///
  /// Ces tests décrivent le contrat qui rend le raccourci sûr : la mémoire
  /// suit TOUTE écriture, et le stockage reste la source de vérité.
  group('TokenService — lectures du stockage', () {
    test('ne lit le stockage qu’une seule fois, quel que soit le nombre d’appels', () async {
      final jeton = _fakeJwt({
        'id': 'u1',
        'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
      });
      when(() => storage.read(key: 'sc_jwt_token')).thenAnswer((_) async => jeton);

      for (var i = 0; i < 10; i++) {
        expect(await service.getValidToken(), jeton);
      }

      verify(() => storage.read(key: 'sc_jwt_token')).called(1);
    });

    test('une session SANS jeton ne relit pas non plus le stockage', () async {
      // Le piège : distinguer « pas encore lu » de « lu, et vide ». Sans ce
      // soin, un utilisateur déconnecté rouvrait le trousseau à chaque appel.
      when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) async => null);

      for (var i = 0; i < 5; i++) {
        expect(await service.getValidToken(), isNull);
      }

      verify(() => storage.read(key: 'sc_jwt_token')).called(1);
    });

    test('setToken met la copie mémoire à jour, sans relire le stockage', () async {
      when(() => storage.write(key: any(named: 'key'), value: any(named: 'value')))
          .thenAnswer((_) async {});

      final nouveau = _fakeJwt({
        'id': 'u2',
        'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
      });
      await service.setToken(nouveau);

      expect(await service.getValidToken(), nouveau);
      verifyNever(() => storage.read(key: 'sc_jwt_token'));
    });

    test('clearToken oublie le jeton — sans quoi la déconnexion ne déconnecterait rien', () async {
      final jeton = _fakeJwt({
        'id': 'u1',
        'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
      });
      when(() => storage.read(key: 'sc_jwt_token')).thenAnswer((_) async => jeton);
      when(() => storage.delete(key: any(named: 'key'))).thenAnswer((_) async {});

      expect(await service.getValidToken(), jeton);
      await service.clearToken();

      expect(await service.getValidToken(), isNull,
          reason: 'la copie mémoire doit suivre l’effacement');
    });

    test('le refresh token suit la même règle', () async {
      when(() => storage.read(key: 'sc_refresh_token')).thenAnswer((_) async => 'r-1');

      expect(await service.getRefreshToken(), 'r-1');
      expect(await service.getRefreshToken(), 'r-1');

      verify(() => storage.read(key: 'sc_refresh_token')).called(1);
    });

    test('setRefreshToken remplace la copie mémoire', () async {
      when(() => storage.write(key: any(named: 'key'), value: any(named: 'value')))
          .thenAnswer((_) async {});

      await service.setRefreshToken('r-2');

      expect(await service.getRefreshToken(), 'r-2');
      verifyNever(() => storage.read(key: 'sc_refresh_token'));
    });
  });
}
