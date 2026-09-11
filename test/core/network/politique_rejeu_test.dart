import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:suivie_chantier_mobile/core/network/cache_reponses_get.dart';
import 'package:suivie_chantier_mobile/core/network/dio_client_factory.dart';
import 'package:suivie_chantier_mobile/core/services/auth_event_bus.dart';
import 'package:suivie_chantier_mobile/core/services/token_service.dart';

class _MockTokenService extends Mock implements TokenService {}

/// Adaptateur scénarisé : note chaque requête RÉELLEMENT émise et répond selon
/// le scénario du test.
class _Adaptateur implements HttpClientAdapter {
  final FutureOr<ResponseBody> Function(RequestOptions options, int rang) repondre;
  final List<String> appels = [];

  _Adaptateur(this.repondre);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) async {
    // Consommer le corps, comme le ferait un vrai client : c'est ce qui rend
    // un FormData non rejouable s'il n'est pas cloné.
    if (requestStream != null) await requestStream.drain<void>();
    appels.add('${options.method} ${options.path}');
    return repondre(options, appels.length);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int statut, Map<String, dynamic> corps) => ResponseBody.fromString(
      jsonEncode(corps),
      statut,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );

/// Audit synchronisation — politique de rejeu de l'intercepteur Dio.
///
/// Défauts reproduits avant correction :
///
///  1. un POST (commentaire, affectation, envoi de rapport) était REJOUÉ sur
///     `receiveTimeout` / `connectionError` : le serveur avait souvent déjà
///     écrit, d'où des doublons ;
///  2. après un rafraîchissement de jeton RÉUSSI, n'importe quel échec du
///     rejeu (panne 500, coupure) DÉCONNECTAIT l'utilisateur et remontait le
///     401 d'origine au lieu de la vraie erreur ;
///  3. un serveur qui répondait 401 à chaque requête malgré un
///     rafraîchissement réussi (compte désactivé, horloge) faisait boucler
///     rafraîchissement + rejeu indéfiniment.
void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  late _MockTokenService jetons;
  late int deconnexions;
  late StreamSubscription<void> abonnement;

  setUp(() {
    jetons = _MockTokenService();
    when(() => jetons.getValidToken()).thenAnswer((_) async => 'jeton');
    when(() => jetons.getRefreshToken()).thenAnswer((_) async => 'refresh-1');
    when(() => jetons.setToken(any())).thenAnswer((_) async {});
    when(() => jetons.setRefreshToken(any())).thenAnswer((_) async {});
    when(() => jetons.clearToken()).thenAnswer((_) async {});
    deconnexions = 0;
    abonnement = AuthEventBus.instance.onForcedLogout.listen((_) => deconnexions++);
  });

  tearDown(() async => abonnement.cancel());

  Future<Dio> construire(_Adaptateur adaptateur) async {
    final dio = await DioClientFactory.create(tokenService: jetons, cache: CacheReponsesGet());
    dio.httpClientAdapter = adaptateur;
    return dio;
  }

  group('Rejeu réseau', () {
    test('un POST n’est PAS rejoué après un délai de réponse dépassé', () async {
      final adaptateur = _Adaptateur((o, _) => throw DioException(
            requestOptions: o,
            type: DioExceptionType.receiveTimeout,
          ));
      final dio = await construire(adaptateur);

      await expectLater(
        dio.post('/reserves/r1/commentaires', data: {'message': 'fissure'}),
        throwsA(isA<DioException>()),
      );
      expect(adaptateur.appels, hasLength(1), reason: 'le serveur a pu écrire : rejouer crée un doublon');
    });

    test('un GET reste rejoué (lecture sans effet de bord)', () async {
      final adaptateur = _Adaptateur((o, rang) {
        if (rang < 3) throw DioException(requestOptions: o, type: DioExceptionType.receiveTimeout);
        return _json(200, {'success': true});
      });
      final dio = await construire(adaptateur);

      final reponse = await dio.get('/reserves');

      expect(reponse.statusCode, 200);
      expect(adaptateur.appels, hasLength(3));
    }, timeout: const Timeout(Duration(seconds: 20)));
  });

  group('Rafraîchissement de session', () {
    test('rafraîchissement réussi puis panne du rejeu : PAS de déconnexion, vraie erreur remontée', () async {
      final adaptateur = _Adaptateur((o, rang) {
        if (o.path.endsWith('/auth/refresh')) {
          return _json(200, {'data': {'token': 'jeton-neuf', 'refreshToken': 'refresh-2'}});
        }
        if (rang == 1) return _json(401, {'success': false, 'message': 'Token expiré'});
        return _json(500, {'success': false, 'message': 'Panne serveur'});
      });
      final dio = await construire(adaptateur);

      try {
        await dio.patch('/reserves/r1/statut', data: {'statut': 'corrigee'});
        fail('la requête aurait dû échouer');
      } on DioException catch (e) {
        expect(e.response?.statusCode, 500, reason: 'c’est la panne qu’il faut remonter, pas le 401 d’origine');
      }
      verifyNever(() => jetons.clearToken());
      expect(deconnexions, 0, reason: 'la session est valide : une panne serveur ne doit pas déconnecter');
    });

    test('un 401 persistant après rafraîchissement déconnecte UNE fois, sans boucler', () async {
      final adaptateur = _Adaptateur((o, _) {
        if (o.path.endsWith('/auth/refresh')) {
          return _json(200, {'data': {'token': 'jeton-neuf', 'refreshToken': 'refresh-2'}});
        }
        return _json(401, {'success': false, 'message': 'Compte désactivé'});
      });
      final dio = await construire(adaptateur);

      await expectLater(
        dio.get('/reserves').timeout(const Duration(seconds: 5)),
        throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'statut', 401)),
      );
      final rafraichissements = adaptateur.appels.where((a) => a.endsWith('/auth/refresh')).length;
      expect(rafraichissements, 1, reason: 'un seul rafraîchissement par requête, jamais une boucle');
      verify(() => jetons.clearToken()).called(1);
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}
