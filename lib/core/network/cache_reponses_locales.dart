import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../offline/base_locale.dart';
import '../offline/reponses_locales.dart';

/// Intercepteur « local d'abord » : mémorise sur disque les lectures réussies
/// et les resert quand le serveur est injoignable.
///
/// Voir [ReponsesLocales] pour le problème (plans, structure, corps d'état et
/// phases jamais conservés) et les garde-fous de stockage.
///
/// ## Quand il sert une copie
///
///  1. la détection de connexion sait DÉJÀ le serveur injoignable
///     ([serveurInjoignable]) : copie servie tout de suite, sans attendre un
///     délai de connexion de 15 s ;
///  2. sinon, la requête part, et une erreur de CONNEXION (coupure, délai) est
///     remplacée par la copie. Une réponse du serveur — même 401, 404 ou 500 —
///     n'est JAMAIS remplacée : le serveur a parlé, il fait foi.
///
/// ## Ce qu'il ne touche jamais
///
///  - les routes d'authentification, de synchronisation et de vivacité ;
///  - les réserves et les chantiers (liste et fiche) : leurs dépôts ont leur
///    propre base locale, avec réconciliation du travail en attente. Les servir
///    ici renverrait une version périmée qui masquerait ces modifications ;
///  - tout ce qui n'est pas un `GET`.
///
/// ## Marqueurs
///
/// Une réponse servie localement porte `extra['depuisCacheLocal'] = true`. Une
/// erreur « rien en copie » porte `extra['nonTelecharge'] = true` : le mappeur
/// d'erreurs en tire un message qui dit quoi faire, au lieu de « erreur
/// réseau ».
class CacheReponsesLocales extends Interceptor {
  static const marqueurServie = 'depuisCacheLocal';
  static const marqueurNonTelecharge = 'nonTelecharge';

  final ReponsesLocales _stock;
  final bool Function() _serveurInjoignable;

  CacheReponsesLocales({required ReponsesLocales stock, required bool Function() serveurInjoignable})
      : _stock = stock,
        _serveurInjoignable = serveurInjoignable;

  // ── Admissibilité ─────────────────────────────────────────────────────────

  static bool _estFichier(RequestOptions o) =>
      o.responseType == ResponseType.bytes && o.method.toUpperCase() == 'GET';

  static bool _estJson(RequestOptions o) =>
      (o.responseType == ResponseType.json || o.responseType == ResponseType.plain) &&
      o.method.toUpperCase() == 'GET';

  /// Chemin relatif à la base de l'API (`/api/v1` retiré).
  static String _relatif(RequestOptions o) {
    final base = Uri.tryParse(o.baseUrl)?.path ?? '';
    final chemin = o.uri.path;
    return base.isNotEmpty && base != '/' && chemin.startsWith(base) ? chemin.substring(base.length) : chemin;
  }

  static bool _versApi(RequestOptions o) {
    final hote = Uri.tryParse(o.baseUrl)?.host ?? '';
    return hote.isEmpty || o.uri.host == hote;
  }

  static final _refusees = <RegExp>[
    RegExp(r'^/auth(/|$)'),
    RegExp(r'^/sync(/|$)'),
    RegExp(r'^/health'),
    RegExp(r'^/account/me$'),
    // Dépôts dotés de leur propre base locale (voir la note de classe).
    RegExp(r'^/reserves(/[^/]+)?$'),
    RegExp(r'^/chantiers(/[^/]+)?$'),
    RegExp(r'^/chantiers/[^/]+/reserves$'),
  ];

  @visibleForTesting
  static bool jsonAdmissible(RequestOptions o) {
    if (!_estJson(o) || !_versApi(o)) return false;
    final chemin = _relatif(o);
    return !_refusees.any((r) => r.hasMatch(chemin));
  }

  @visibleForTesting
  static bool fichierAdmissible(RequestOptions o) {
    if (!_estFichier(o)) return false;
    final chemin = _relatif(o);
    return !RegExp(r'^/(auth|sync|health)').hasMatch(chemin);
  }

  /// Clé stable : paramètres triés pour que `?a=1&b=2` et `?b=2&a=1` se
  /// recoupent. Les FICHIERS ignorent la requête : une URL signée ou datée
  /// désigne le même document.
  @visibleForTesting
  static String cle(RequestOptions o) {
    if (_estFichier(o)) return 'fichier:${o.uri.host}${o.uri.path}';
    final params = o.uri.queryParameters.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final requete = params.map((e) => '${e.key}=${e.value}').join('&');
    return 'json:${o.uri.path}${requete.isEmpty ? '' : '?$requete'}';
  }

  static bool _coupure(DioException e) =>
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout;

  // ── Cycle de vie ──────────────────────────────────────────────────────────

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final json = jsonAdmissible(options);
    final fichier = fichierAdmissible(options);
    if (!json && !fichier) return handler.next(options);

    // Purge de comptes en vol : voir BaseLocale.generationPurge.
    options.extra['_generation'] = BaseLocale.generationPurge;

    if (_serveurInjoignable()) {
      final copie = await _servir(options, json: json);
      if (copie != null) return handler.resolve(copie);
      // Rien en copie. La sonde a pu se tromper : on tente quand même, mais
      // vite — délai court et aucune relance — pour que l'absence se sache
      // en quelques secondes plutôt qu'en une minute.
      options.connectTimeout = const Duration(seconds: 4);
      options.extra['retryCount'] = 2;
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final o = response.requestOptions;
    if (response.statusCode == 200 && response.extra[marqueurServie] != true) {
      if (jsonAdmissible(o)) {
        unawaited(_memoriserJson(o, response.data));
      } else if (fichierAdmissible(o)) {
        unawaited(_memoriserFichier(o, response.data));
      }
    }
    handler.next(response);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final o = err.requestOptions;
    final json = jsonAdmissible(o);
    final fichier = fichierAdmissible(o);
    if ((!json && !fichier) || !_coupure(err)) return handler.next(err);

    final copie = await _servir(o, json: json);
    if (copie != null) return handler.resolve(copie);

    // Pas de copie : l'erreur reste une erreur réseau, mais marquée, pour que
    // l'utilisateur apprenne CE QU'IL DOIT FAIRE (voir `mapDioException`).
    o.extra[marqueurNonTelecharge] = true;
    handler.next(err);
  }

  // ── Lecture / écriture ────────────────────────────────────────────────────

  Future<Response<dynamic>?> _servir(RequestOptions o, {required bool json}) async {
    try {
      if (json) {
        final corps = await _stock.lireJson(cle(o));
        if (corps == null) return null;
        return Response<dynamic>(
          requestOptions: o,
          statusCode: 200,
          data: o.responseType == ResponseType.plain ? corps : jsonDecode(corps),
          extra: {marqueurServie: true},
        );
      }
      final octets = await _stock.lireFichier(cle(o));
      if (octets == null) return null;
      return Response<dynamic>(
        requestOptions: o,
        statusCode: 200,
        data: octets,
        extra: {marqueurServie: true},
      );
    } catch (e) {
      debugPrint('[hors-ligne] Copie locale illisible (${cle(o)}) : $e');
      return null;
    }
  }

  /// Une réponse reçue APRÈS un changement de compte ne doit pas être écrite :
  /// elle appartient au compte précédent (voir [BaseLocale.generationPurge]).
  bool _perimee(RequestOptions o) => o.extra['_generation'] != BaseLocale.generationPurge;

  Future<void> _memoriserJson(RequestOptions o, Object? donnees) async {
    if (donnees == null || _perimee(o)) return;
    try {
      final corps = donnees is String ? donnees : jsonEncode(donnees);
      await _stock.ecrireJson(cle(o), corps);
    } catch (e) {
      debugPrint('[hors-ligne] Copie locale non écrite (${cle(o)}) : $e');
    }
  }

  Future<void> _memoriserFichier(RequestOptions o, Object? donnees) async {
    if (_perimee(o)) return;
    try {
      final octets = switch (donnees) {
        final Uint8List u => u,
        final List<int> l => l,
        _ => null,
      };
      if (octets == null || octets.isEmpty) return;
      await _stock.ecrireFichier(cle(o), octets);
    } catch (e) {
      debugPrint('[hors-ligne] Fichier local non écrit (${cle(o)}) : $e');
    }
  }
}
