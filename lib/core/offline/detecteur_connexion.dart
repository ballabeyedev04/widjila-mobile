import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/env.dart';

/// État réseau tel que l'application le comprend.
enum EtatReseau {
  /// Internet joignable : le serveur a répondu.
  enLigne,

  /// Aucune connexion utilisable — bandeau rouge, écriture différée.
  horsLigne,

  /// Avant la première vérification. L'interface n'affiche alors aucun bandeau
  /// plutôt qu'un « hors ligne » qui clignoterait au lancement.
  inconnu,
}

/// Détecte la disponibilité RÉELLE du serveur.
///
/// ## Pourquoi ne pas se fier à `connectivity_plus` seul
///
/// Ce paquet répond à « l'appareil est-il attaché à un réseau ? », pas à
/// « internet fonctionne-t-il ? ». Les deux divergent précisément dans le cas
/// qui nous occupe : au sous-sol, le téléphone reste accroché à une antenne
/// avec un signal inexploitable, ou à un wifi de chantier sans route vers
/// l'extérieur. `connectivity_plus` dirait « connecté » et l'application
/// tenterait des envois voués à expirer.
///
/// Il sert donc de DÉCLENCHEUR (changement d'interface réseau), et la vérité
/// vient d'un appel réel au serveur.
class DetecteurConnexion {
  final Dio _dio;
  final Connectivity _connectivity;

  DetecteurConnexion({required Dio dio, Connectivity? connectivity})
      // ignore: prefer_initializing_formals
      : _dio = dio,
        // Valeur par défaut fournie ici plutôt qu'en paramètre : `Connectivity()`
        // n'est pas une constante, elle ne peut pas figurer dans la signature.
        _connectivity = connectivity ?? Connectivity();


  final _controleur = StreamController<EtatReseau>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _abonnement;
  Timer? _sondagePeriodique;

  EtatReseau _etat = EtatReseau.inconnu;

  /// État courant, sans attendre le prochain changement.
  EtatReseau get etat => _etat;

  bool get estEnLigne => _etat == EtatReseau.enLigne;

  /// Émet à CHAQUE changement d'état. C'est ce flux qui déclenche la
  /// synchronisation automatique et le basculement du bandeau.
  Stream<EtatReseau> get flux => _controleur.stream;

  Future<void> demarrer() async {
    _abonnement = _connectivity.onConnectivityChanged.listen((_) {
      // Un changement d'interface ne prouve rien : on revérifie réellement.
      verifier();
    });

    // Filet de sécurité : au sous-sol, le signal peut revenir sans que l'OS
    // signale un changement d'interface (même antenne, simplement de nouveau
    // exploitable). Sans ce sondage, l'app resterait bloquée en « hors ligne »
    // jusqu'à une action de l'utilisateur.
    _sondagePeriodique = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_etat != EtatReseau.enLigne) verifier();
    });

    await verifier();
  }

  /// Vérifie la joignabilité du serveur et publie le résultat.
  Future<EtatReseau> verifier() async {
    final nouveau = await _tester();
    if (nouveau != _etat) {
      _etat = nouveau;
      if (!_controleur.isClosed) _controleur.add(nouveau);
    }
    return nouveau;
  }

  /// URL absolue du point de santé, déduite de la base API en retirant le
  /// suffixe de version (`/api/v1`).
  static String get _urlSante {
    final base = Uri.parse(Env.apiBaseUrl);
    return base.replace(path: '/health', query: '').toString();
  }

  Future<EtatReseau> _tester() async {
    // Court-circuit peu coûteux : si l'OS dit « aucune interface », inutile
    // d'attendre l'expiration d'une requête HTTP.
    final interfaces = await _connectivity.checkConnectivity();
    if (interfaces.isEmpty || interfaces.every((i) => i == ConnectivityResult.none)) {
      return EtatReseau.horsLigne;
    }

    try {
      // `/health` plutôt qu'un endpoint métier : pas d'authentification, pas
      // d'effet de bord, réponse minuscule. Le délai est court — au sous-sol,
      // il faut conclure « hors ligne » vite, pas figer l'interface.
      //
      // URL ABSOLUE : `/health` est monté à la RACINE du serveur
      // (`backend/src/app.js`), alors que `baseUrl` de Dio pointe sur
      // `/api/v1`. Une URL relative viserait `/api/v1/health`, qui n'existe
      // pas — le test conclurait alors à tort selon la réponse du serveur.
      await _dio.get<void>(
        _urlSante,
        options: Options(
          receiveTimeout: const Duration(seconds: 4),
          sendTimeout: const Duration(seconds: 4),
          // Toute réponse du serveur prouve qu'il est joignable, même un 401
          // ou un 404 : c'est la JOIGNABILITÉ qu'on teste, pas le droit
          // d'accès.
          validateStatus: (_) => true,
        ),
      );
      return EtatReseau.enLigne;
    } on DioException catch (e) {
      final coupure = e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout;
      return coupure ? EtatReseau.horsLigne : EtatReseau.enLigne;
    } catch (e) {
      debugPrint('[reseau] Test inattendu : $e');
      return EtatReseau.horsLigne;
    }
  }

  Future<void> arreter() async {
    await _abonnement?.cancel();
    _sondagePeriodique?.cancel();
    await _controleur.close();
  }
}
