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

        if (!_isAuthExemptPath(options.path, options.extra)) {
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

        // 401 hors endpoints publics → tenter le refresh puis rejouer.
        if (e.response?.statusCode == 401 &&
            !_isAuthExemptPath(e.requestOptions.path, e.requestOptions.extra)) {
          final refreshed = await tryRefresh();
          if (refreshed) {
            final token = await tokenService.getValidToken();
            e.requestOptions.headers['Authorization'] = 'Bearer $token';
            try {
              final retryResponse = await dio.fetch(e.requestOptions);
              return handler.resolve(retryResponse);
            } catch (_) {
              // Le rejeu a aussi échoué — déconnexion ci-dessous.
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

        // Retry automatique sur erreurs réseau transitoires (max 2 tentatives).
        final isNetworkError = e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError;
        final retryCount = e.requestOptions.extra['retryCount'] as int? ?? 0;
        if (isNetworkError && retryCount < 2) {
          e.requestOptions.extra['retryCount'] = retryCount + 1;
          await Future.delayed(Duration(seconds: retryCount + 1));
          try {
            final response = await dio.fetch(e.requestOptions);
            return handler.resolve(response);
          } catch (_) {
            // Retry réseau échoué — erreur originale propagée ci-dessous.
          }
        }

        return handler.next(e);
      },
    );
  }
}
