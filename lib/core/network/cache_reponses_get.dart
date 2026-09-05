import 'dart:collection';

import 'package:dio/dio.dart';

/// Cache mémoire, à durée de vie courte, des réponses aux requêtes `GET`.
///
/// ## Le problème qu'il résout
///
/// Chaque écran fournit son cubit dans son `build` : `BlocProvider(create: (_)
/// => sl&lt;XCubit&gt;()..charger())`. Le cubit vit donc exactement le temps de
/// l'écran. Changer d'onglet le détruit ; y revenir en crée un neuf, qui
/// recharge tout. Aller au tableau de bord, passer aux réserves, revenir au
/// tableau de bord, c'est **six appels réseau** — dont quatre pour redemander
/// ce qu'on avait déjà cinq secondes plus tôt. Entre-temps l'écran affiche son
/// squelette : l'application paraît lente alors qu'elle ne fait que se répéter.
///
/// Ce cache rend le retour sur un écran INSTANTANÉ, sans toucher ni à
/// l'architecture des cubits ni au cycle de vie des écrans.
///
/// ## Pourquoi ce n'est pas dangereux
///
/// Trois garde-fous, et ils comptent tous les trois :
///
///  1. **[duree] est courte.** Passé ce délai l'entrée est jetée. On n'invente
///     pas un cache persistant : on absorbe l'aller-retour d'un utilisateur
///     qui navigue, rien de plus ;
///  2. **toute écriture vide le cache.** Un `POST`, `PUT`, `PATCH` ou `DELETE`
///     signifie que les données du serveur ont changé — on ne peut plus faire
///     confiance à ce qu'on a retenu. C'est ce qui garantit qu'après avoir créé
///     une réserve, la liste la montre ;
///  3. **le rafraîchissement manuel passe outre** (voir [ignorerCache]). Tirer
///     la liste vers le bas doit aller au réseau : c'est le geste par lequel on
///     demande explicitement des nouvelles.
///
/// ## Ce qui n'est jamais mis en cache
///
///  - **`/health`** : le détecteur de connexion s'en sert pour savoir si le
///    serveur répond. Une réponse mémorisée dirait « en ligne » depuis un
///    sous-sol — le mode hors ligne ne se déclencherait plus ;
///  - **les réponses binaires** (images, PDF) : elles pèsent des mégaoctets et
///    ont déjà leurs propres caches, dimensionnés pour elles
///    (`FichierImage`, `PlanVignette`) ;
///  - **les routes d'authentification** : connexion, inscription, refresh.
class CacheReponsesGet extends Interceptor {
  /// Marqueur à poser dans `Options.extra` pour ignorer le cache sur UNE
  /// requête — la réponse obtenue est alors mémorisée normalement.
  static const ignorerCache = 'ignorerCacheGet';

  /// Durée de vie d'une entrée.
  ///
  /// Trente secondes : assez pour couvrir un aller-retour entre onglets, qui
  /// se compte en secondes ; assez peu pour qu'un changement fait par un
  /// collègue n'attende jamais longtemps. Au-delà, on commencerait à montrer
  /// un passé que l'utilisateur n'a pas demandé.
  final Duration duree;

  /// Plafond d'entrées. La plus ancienne est évincée au-delà —
  /// [LinkedHashMap] conserve l'ordre d'insertion.
  ///
  /// Ce sont des réponses JSON de listes paginées : quelques dizaines de
  /// kilo-octets au plus. Soixante entrées bornent l'ensemble à un ordre de
  /// grandeur négligeable devant une seule photo de chantier.
  final int maxEntrees;

  CacheReponsesGet({
    this.duree = const Duration(seconds: 30),
    this.maxEntrees = 60,
  });

  final LinkedHashMap<String, _Entree> _entrees = LinkedHashMap<String, _Entree>();

  /// Nombre d'entrées retenues — pour les tests et le diagnostic.
  int get taille => _entrees.length;

  /// Oublie tout. Appelé par les écritures, la déconnexion et le
  /// rafraîchissement manuel.
  void vider() => _entrees.clear();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final methode = options.method.toUpperCase();

    // Une écriture change l'état du serveur : tout ce qu'on a retenu devient
    // suspect. On purge AVANT de laisser passer, pour qu'une réponse arrivant
    // pendant l'écriture ne repeuple pas le cache avec l'état d'avant.
    if (methode != 'GET') {
      vider();
      return handler.next(options);
    }

    if (!_cachable(options)) return handler.next(options);

    final entree = _entrees[_cle(options)];
    if (entree == null || entree.perimee(duree)) {
      if (entree != null) _entrees.remove(_cle(options));
      return handler.next(options);
    }

    // `false` : la réponse ne retraverse pas [onResponse], elle vient déjà
    // d'ici — la remémoriser rafraîchirait sa date et la rendrait éternelle.
    handler.resolve(
      Response(
        requestOptions: options,
        data: entree.donnees,
        statusCode: entree.statusCode,
        statusMessage: entree.statusMessage,
        headers: entree.entetes,
        extra: {...options.extra, 'depuisCache': true},
      ),
      false,
    );
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final options = response.requestOptions;
    final code = response.statusCode ?? 0;

    if (options.method.toUpperCase() == 'GET' && code >= 200 && code < 300 && _cachable(options)) {
      if (_entrees.length >= maxEntrees) _entrees.remove(_entrees.keys.first);
      _entrees[_cle(options)] = _Entree(
        donnees: response.data,
        statusCode: response.statusCode,
        statusMessage: response.statusMessage,
        entetes: response.headers,
        instant: DateTime.now(),
      );
    }

    handler.next(response);
  }

  /// Clé d'une requête : chemin ET paramètres.
  ///
  /// Les paramètres en font PARTIE — `?page=2` et `?page=3` sont deux
  /// réponses différentes. Les omettre aurait servi la première page à toutes
  /// les suivantes, ce qui aurait cassé la pagination au lieu de l'accélérer.
  static String _cle(RequestOptions options) {
    final requete = options.uri.query;
    return requete.isEmpty ? options.uri.path : '${options.uri.path}?$requete';
  }

  bool _cachable(RequestOptions options) {
    if (options.extra[ignorerCache] == true) return false;

    // Réponses binaires : mégaoctets, et déjà couvertes par des caches
    // dimensionnés pour elles.
    if (options.responseType == ResponseType.bytes ||
        options.responseType == ResponseType.stream) {
      return false;
    }

    final chemin = options.uri.path;

    // Sonde de vivacité du détecteur de connexion. En cache, elle répondrait
    // « en ligne » depuis un sous-sol et le mode hors ligne ne s'activerait
    // plus jamais.
    if (chemin.endsWith('/health')) return false;

    // Authentification : jamais. Un jeton ou un profil de connexion mémorisé
    // n'a aucun sens, et `refresh` doit toujours atteindre le serveur.
    if (chemin.contains('/auth/')) return false;

    return true;
  }
}

class _Entree {
  final dynamic donnees;
  final int? statusCode;
  final String? statusMessage;
  final Headers entetes;
  final DateTime instant;

  _Entree({
    required this.donnees,
    required this.statusCode,
    required this.statusMessage,
    required this.entetes,
    required this.instant,
  });

  bool perimee(Duration duree) => DateTime.now().difference(instant) > duree;
}
