import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suivie_chantier_mobile/core/network/cache_reponses_get.dart';

/// Adaptateur qui compte les requêtes réellement parties sur le réseau.
///
/// C'est la seule mesure qui compte ici : un cache qui « fonctionne » mais
/// laisse quand même partir la requête n'accélère rien.
class _AdaptateurCompteur implements HttpClientAdapter {
  final List<String> appels = [];
  int statut = 200;
  String corps = '{"ok":true}';

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    appels.add('${options.method} ${options.uri}');
    return ResponseBody.fromString(
      corps,
      statut,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Cache mémoire des réponses `GET`.
///
/// ## Ce qu'il corrige
///
/// Chaque écran crée son cubit dans son `build` et le charge aussitôt. Changer
/// d'onglet détruit le cubit ; y revenir en crée un neuf, qui redemande au
/// serveur ce qu'il avait obtenu quelques secondes plus tôt. L'utilisateur voit
/// un squelette de chargement à chaque aller-retour, pour des données
/// inchangées.
///
/// ## Ce que ces tests protègent
///
/// Un cache est une source d'incohérences quand ses limites ne sont pas
/// tenues. Chacune est vérifiée ici, parce que chacune, si elle cédait,
/// donnerait un bug très difficile à relier à ce fichier : une liste qui ne
/// montre pas ce qu'on vient d'y ajouter, une pagination qui répète sa
/// première page, ou un mode hors ligne qui ne se déclenche plus.
void main() {
  late _AdaptateurCompteur adaptateur;
  late CacheReponsesGet cache;
  late Dio dio;

  void construire({Duration duree = const Duration(seconds: 30), int maxEntrees = 60}) {
    adaptateur = _AdaptateurCompteur();
    cache = CacheReponsesGet(duree: duree, maxEntrees: maxEntrees);
    dio = Dio(BaseOptions(baseUrl: 'https://api.exemple.test/api/v1'))
      ..httpClientAdapter = adaptateur
      ..interceptors.add(cache);
  }

  setUp(construire);

  group('le retour sur un écran ne repart pas au réseau', () {
    test('deux GET identiques ne déclenchent qu’un seul appel', () async {
      await dio.get('/reserves');
      await dio.get('/reserves');
      await dio.get('/reserves');

      expect(adaptateur.appels, hasLength(1));
    });

    test('la réponse servie depuis le cache porte les mêmes données', () async {
      final premiere = await dio.get('/reserves');
      final seconde = await dio.get('/reserves');

      expect(seconde.data, premiere.data);
      expect(seconde.statusCode, 200);
      expect(seconde.extra['depuisCache'], isTrue);
    });

    test('passé le délai, on retourne au serveur', () async {
      construire(duree: const Duration(milliseconds: 40));

      await dio.get('/reserves');
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await dio.get('/reserves');

      expect(adaptateur.appels, hasLength(2));
    });
  });

  group('la clé distingue ce qui doit l’être', () {
    test('deux pages différentes sont deux réponses différentes', () async {
      // Le piège : ignorer les paramètres aurait servi la page 1 à toutes les
      // suivantes — la pagination aurait cessé de paginer.
      await dio.get('/reserves', queryParameters: {'page': 1});
      await dio.get('/reserves', queryParameters: {'page': 2});

      expect(adaptateur.appels, hasLength(2));
    });

    test('deux chemins différents ne se confondent pas', () async {
      await dio.get('/reserves');
      await dio.get('/chantiers');

      expect(adaptateur.appels, hasLength(2));
    });
  });

  group('une écriture invalide tout', () {
    test('après un POST, la liste est redemandée', () async {
      await dio.get('/reserves');
      expect(adaptateur.appels, hasLength(1));

      // Sans cette purge, la réserve qu'on vient de créer n'apparaîtrait pas
      // dans la liste — le bug le plus visible qu'un cache puisse produire.
      await dio.post('/reserves', data: {'titre': 'Fissure'});
      await dio.get('/reserves');

      expect(adaptateur.appels, hasLength(3));
    });

    test('un PUT, un PATCH et un DELETE purgent aussi', () async {
      for (final envoyer in <Future<void> Function()>[
        () => dio.put('/reserves/r1', data: {}),
        () => dio.patch('/reserves/r1', data: {}),
        () => dio.delete('/reserves/r1'),
      ]) {
        cache.vider();
        adaptateur.appels.clear();

        await dio.get('/reserves');
        await envoyer();
        await dio.get('/reserves');

        expect(adaptateur.appels.where((a) => a.contains('GET')), hasLength(2));
      }
    });
  });

  group('ce qui ne doit jamais être mis en cache', () {
    test('/health — sinon le mode hors ligne ne se déclenche plus', () async {
      // Le détecteur de connexion sonde cette route pour savoir si le serveur
      // répond. Mémorisée, elle répondrait « en ligne » depuis un sous-sol.
      await dio.get('https://api.exemple.test/health');
      await dio.get('https://api.exemple.test/health');

      expect(adaptateur.appels, hasLength(2));
    });

    test('les routes d’authentification', () async {
      await dio.get('/auth/profil');
      await dio.get('/auth/profil');

      expect(adaptateur.appels, hasLength(2));
    });

    test('les réponses binaires — mégaoctets, et déjà mises en cache ailleurs', () async {
      await dio.get<List<int>>(
        '/uploads/plan.pdf',
        options: Options(responseType: ResponseType.bytes),
      );
      await dio.get<List<int>>(
        '/uploads/plan.pdf',
        options: Options(responseType: ResponseType.bytes),
      );

      expect(adaptateur.appels, hasLength(2));
      expect(cache.taille, 0);
    });

    test('une réponse en erreur', () async {
      adaptateur.statut = 500;
      try {
        await dio.get('/reserves');
      } catch (_) {/* attendu */}
      expect(cache.taille, 0, reason: 'mémoriser une panne la ferait durer');
    });
  });

  group('contournement explicite', () {
    test('`ignorerCache` va au réseau, et mémorise quand même la réponse', () async {
      await dio.get('/reserves');
      expect(adaptateur.appels, hasLength(1));

      await dio.get(
        '/reserves',
        options: Options(extra: {CacheReponsesGet.ignorerCache: true}),
      );
      expect(adaptateur.appels, hasLength(2), reason: 'le rafraîchissement manuel doit aboutir');
    });

    test('vider() oublie tout', () async {
      await dio.get('/reserves');
      cache.vider();
      await dio.get('/reserves');

      expect(adaptateur.appels, hasLength(2));
    });
  });

  group('bornes mémoire', () {
    test('au-delà du plafond, la plus ancienne entrée est évincée', () async {
      construire(maxEntrees: 3);

      for (var i = 0; i < 5; i++) {
        await dio.get('/r$i');
      }

      expect(cache.taille, lessThanOrEqualTo(3));
    });
  });

  test('le corps JSON reste exploitable après un passage par le cache', () async {
    adaptateur.corps = jsonEncode({
      'success': true,
      'data': {
        'items': [
          {'id': 'r1'}
        ]
      },
    });

    await dio.get('/reserves');
    final depuisCache = await dio.get('/reserves');

    expect(depuisCache.data['data']['items'][0]['id'], 'r1');
  });
}
