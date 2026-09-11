import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../config/env.dart';
import '../errors/error_codes.dart';
import '../services/auth_event_bus.dart';
import '../services/token_service.dart';
import 'cache_reponses_get.dart';

/// Construit le client Dio central de l'app : base URL, timeouts, pinning de
/// certificat (best-effort), Bearer token automatique, refresh silencieux
/// sur 401 (avec file d'attente pour ne pas déclencher N refresh en
/// parallèle), retry réseau, et messages d'erreur compréhensibles.
///
/// Miroir du comportement de l'admin web (`admin/src/service/api.js`) :
/// même stratégie de refresh silencieux, mêmes routes exemptées
/// d'authentification.
class DioClientFactory {
  DioClientFactory._();

  /// Delai maximal accorde a la preparation du jeton, AVANT que la requete
  /// parte.
  ///
  /// Les `connectTimeout` / `receiveTimeout` de Dio ne courent qu'a partir du
  /// moment ou la requete est emise. Tout ce qui se passe avant — lecture du
  /// stockage securise, rafraichissement silencieux — se deroule donc hors de
  /// tout delai. Une lecture qui ne rend jamais la main n'echouait pas : elle
  /// ne se terminait tout simplement pas. La requete n'etait jamais emise,
  /// aucun timeout ne se declenchait, et l'ecran restait sur son indicateur de
  /// chargement indefiniment, sans erreur ni bouton pour reessayer.
  ///
  /// Cinq secondes : bien au-dela d'une lecture de trousseau normale (quelques
  /// millisecondes) et d'un rafraichissement de jeton, assez court pour que
  /// l'utilisateur recoive une erreur exploitable plutot qu'un ecran fige.
  static const delaiPreparationJeton = Duration(seconds: 5);

  static Future<Dio> create({
    required TokenService tokenService,
    required CacheReponsesGet cache,
    Duration delaiJeton = delaiPreparationJeton,
  }) async {
    final dio = Dio(
      BaseOptions(
        baseUrl: Env.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 30),
        contentType: 'application/json',
        headers: {'Accept': 'application/json'},
      ),
    );

    await _applyCertificatePinning(dio);

    // Le cache AVANT l'authentification : une réponse déjà connue se résout
    // sans même aller chercher le jeton. L'ordre compte — placé après, il
    // aurait quand même payé la lecture du jeton pour une requête qui ne part
    // jamais.
    dio.interceptors.add(cache);
    dio.interceptors.add(_buildAuthInterceptor(dio, tokenService, cache, delaiJeton));

    return dio;
  }

  /// Épingle le certificat CA du backend si `assets/certs/backend_ca.pem` est
  /// bundlé — sinon se replie silencieusement sur la validation système
  /// standard (jamais de crash au démarrage si le cert est absent/expiré).
  /// Désactivé en debug (facilite les proxys de dev type Charles/Proxyman).
  static Future<void> _applyCertificatePinning(Dio dio) async {
    if (kDebugMode) return;
    Uint8List? certBytes;
    try {
      final data = await rootBundle.load('assets/certs/backend_ca.pem');
      certBytes = data.buffer.asUint8List();
    } catch (_) {
      return; // Pas de cert bundlé — validation système standard.
    }
    final bytes = certBytes;
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        try {
          final context = SecurityContext(withTrustedRoots: false);
          context.setTrustedCertificatesBytes(bytes);
          return HttpClient(context: context);
        } catch (_) {
          return HttpClient();
        }
      },
    );
  }

  static bool _isAuthExemptPath(String rawPath, Map<String, dynamic> extra) {
    final path = rawPath.split('?').first.trim();
    return path.endsWith(Env.authLogin) ||
        path.endsWith(Env.authRegister) ||
        path.endsWith(Env.authRefresh) ||
        path.endsWith(Env.authLogout) ||
        path.endsWith(Env.authMfaVerify) ||
        extra['skipAuthInterceptor'] == true;
  }

  /// Vrai si la requête vise l'hôte de l'API (celui de `baseUrl`).
  ///
  /// Une URL absolue vers un autre hôte — CDN des photos de profil, par
  /// exemple — ne reçoit ni le jeton, ni de tentative de refresh sur 401.
  static bool _versApi(RequestOptions options) {
    final hoteApi = Uri.tryParse(options.baseUrl)?.host ?? '';
    if (hoteApi.isEmpty) return true; // pas de baseUrl : chemins relatifs uniquement
    return options.uri.host == hoteApi;
  }

  static InterceptorsWrapper _buildAuthInterceptor(
    Dio dio,
    TokenService tokenService,
    CacheReponsesGet cache,
    Duration delaiJeton,
  ) {
    // Sérialise les tentatives de refresh concurrentes : si 3 requêtes
    // échouent en 401 en même temps, une seule vraie tentative de refresh
    // est faite, les deux autres attendent son résultat puis rejouent.
    bool isRefreshing = false;
    final queue = <Completer<bool>>[];

    Future<bool> tryRefresh() async {
      if (isRefreshing) {
        final completer = Completer<bool>();
        queue.add(completer);
        return completer.future;
      }
      isRefreshing = true;
      bool success = false;
      try {
        final refreshToken = await tokenService.getRefreshToken();
        if (refreshToken == null || refreshToken.isEmpty) {
          success = false;
        } else {
          final response = await dio.post(
            Env.authRefresh,
            data: {'refreshToken': refreshToken},
            options: Options(extra: {'skipAuthInterceptor': true}),
          );
          final body = response.data is Map ? response.data['data'] as Map? : null;
          final newToken = body?['token'] as String?;
          final newRefresh = body?['refreshToken'] as String?;
          if (newToken != null && newToken.isNotEmpty) {
            await tokenService.setToken(newToken);
            if (newRefresh != null && newRefresh.isNotEmpty) {
              await tokenService.setRefreshToken(newRefresh);
            }
            success = true;
          }
        }
      } catch (_) {
        success = false;
      } finally {
        isRefreshing = false;
        for (final c in queue) {
          if (!c.isCompleted) c.complete(success);
        }
        queue.clear();
      }
      return success;
    }

    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (kDebugMode) debugPrint('🌐 [${options.method}] ${options.path}');

        // Le jeton ne part QUE vers l'API. Les photos de profil et logos ont
        // une URL absolue sur le CDN public (R2) : le client Dio partagé les
        // charge aussi, et y joignait le Bearer — un jeton d'accès envoyé à un
        // tiers, où il peut finir dans des journaux.
        if (!_isAuthExemptPath(options.path, options.extra) && _versApi(options)) {
          final String? token;
          try {
            token = await tokenService.getValidToken().timeout(delaiJeton);
          } on TimeoutException {
            // Rejet en `connectionTimeout` et NON en 401 : un blocage de la
            // preparation du jeton ne dit rien sur la validite de la session.
            // Le traiter comme une authentification refusee purgerait la
            // session et deconnecterait l'utilisateur pour un incident
            // passager. En erreur reseau, il retrouve « Reessayer » — et les
            // depots peuvent servir leur cache hors ligne.
            return handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionTimeout,
                error: 'Preparation du jeton interrompue',
              ),
              true,
            );
          }
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (DioException e, handler) async {
        if (kDebugMode) {
          debugPrint('❌ [${e.response?.statusCode}] ${e.requestOptions.path} — ${e.response?.data}');
        }

        // Copie REJOUABLE d'une requête. Un `FormData` ne se lit qu'une fois :
        // rejoué tel quel, il échouait toujours (« already finalized ») — un
        // envoi de photo retombait en erreur juste après un refresh réussi.
        // En-têtes et `extra` copiés : marquer le rejeu ne touche pas l'original.
        RequestOptions cloner(RequestOptions o) {
          final donnees = o.data;
          return o.copyWith(
            data: donnees is FormData ? donnees.clone() : donnees,
            headers: {...o.headers},
            extra: {...o.extra},
          );
        }

        // 401 hors endpoints publics → tenter le refresh puis rejouer.
        // `authRejoue` : la requête rejouée repasse par cet intercepteur. Sans
        // marque, un nouveau 401 relançait un refresh, puis un rejeu, et ainsi
        // de suite — chaque tour faisant tourner le refresh token.
        if (e.response?.statusCode == 401 &&
            !_isAuthExemptPath(e.requestOptions.path, e.requestOptions.extra) &&
            _versApi(e.requestOptions) &&
            e.requestOptions.extra['authRejoue'] != true) {
          final refreshed = await tryRefresh();
          final token = refreshed ? await tokenService.getValidToken() : null;
          // `token == null` malgré un refresh réussi (horloge du téléphone en
          // avance) : ne pas rejouer avec un littéral « Bearer null ».
          if (refreshed && token != null) {
            final rejeu = cloner(e.requestOptions)
              ..headers['Authorization'] = 'Bearer $token'
              ..extra['authRejoue'] = true;
            try {
              return handler.resolve(await dio.fetch(rejeu));
            } on DioException catch (erreurRejeu) {
              // CORRECTIF (audit synchronisation) — la SESSION est valide : le
              // refresh vient de réussir. Un échec du rejeu autre qu'un 401
              // (panne 500, coupure, refus métier) est celui de la requête
              // elle-même : il remonte TEL QUEL. L'ancienne version déconnectait
              // l'utilisateur sur n'importe quel échec du rejeu, et remontait le
              // 401 d'origine au lieu de la vraie cause.
              if (erreurRejeu.response?.statusCode != 401) return handler.next(erreurRejeu);
              // Nouveau 401 malgré un jeton neuf : la session est bien finie.
              e = erreurRejeu;
            }
          }
          await tokenService.clearToken();
          // La session tombe : plus rien de ce qui a été retenu n'appartient
          // à qui se connectera ensuite. Une purge de sécurité, pas de
          // performance.
          cache.vider();
          AuthEventBus.instance.emitLogout();
        }

        // Marqueurs différenciés pour les codes que le backend ne documente
        // pas toujours avec un `message` exploitable — traduits par
        // `AppAlert` (seul point d'affichage d'erreur de toute l'app), JAMAIS
        // de texte en dur ici : cette couche n'a pas accès à `BuildContext`/
        // `AppLocalizations`, donc pas moyen de choisir la bonne langue.
        final statusCode = e.response?.statusCode;
        final data = e.response?.data;
        final hasBackendMessage = data is Map && (data['message'] != null);
        if (!hasBackendMessage && (statusCode == 403 || statusCode == 429 || statusCode == 503)) {
          final marqueur = switch (statusCode) {
            403 => ErrCodes.forbidden,
            429 => ErrCodes.rateLimit,
            503 => ErrCodes.serviceUnavailable,
            _ => ErrCodes.generic,
          };
          e = DioException(
            requestOptions: e.requestOptions,
            response: e.response,
            type: e.type,
            error: e.error,
            message: marqueur,
          );
        }

        // Retry automatique sur erreurs réseau transitoires (max 2 tentatives),
        // pour les SEULES requêtes qu'on peut rejouer sans risque de doublon.
        //
        // CORRECTIF (audit synchronisation) — tout était rejoué, POST compris.
        // Or un `receiveTimeout` ou une connexion coupée en pleine réponse ne
        // disent pas que le serveur n'a rien fait : il a souvent DÉJÀ écrit.
        // Rejouer un POST produisait un commentaire en double, une affectation
        // en double, un rapport ENVOYÉ deux fois. Restent rejouables :
        //  - toute requête qui n'a jamais atteint le serveur (délai de
        //    CONNEXION dépassé — la requête n'est pas partie) ;
        //  - les lectures et remplacements sans effet cumulatif (GET, HEAD,
        //    OPTIONS, PUT). DELETE en est exclu : rejoué après un succès dont
        //    la réponse s'est perdue, il répondrait « introuvable » et ferait
        //    croire à un échec.
        // Les écritures métier hors ligne ont, elles, leur propre rejeu
        // idempotent : la file d'attente (voir `SynchronisationService`).
        const methodesRejouables = {'GET', 'HEAD', 'OPTIONS', 'PUT'};
        final jamaisPartie = e.type == DioExceptionType.connectionTimeout;
        final transitoire =
            e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.connectionError;
        final rejouable =
            jamaisPartie || (transitoire && methodesRejouables.contains(e.requestOptions.method.toUpperCase()));
        final retryCount = e.requestOptions.extra['retryCount'] as int? ?? 0;
        if (rejouable && retryCount < 2) {
          final rejeu = cloner(e.requestOptions)..extra['retryCount'] = retryCount + 1;
          await Future<void>.delayed(Duration(seconds: retryCount + 1));
          try {
            return handler.resolve(await dio.fetch(rejeu));
          } on DioException catch (erreurRejeu) {
            // Le DERNIER échec décrit l'état actuel du réseau : c'est lui qui
            // remonte (il a lui-même épuisé les tentatives restantes).
            return handler.next(erreurRejeu);
          }
        }

        return handler.next(e);
      },
    );
  }
}
