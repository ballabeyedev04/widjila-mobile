import 'dart:async';

import 'package:country_picker/country_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
// Le setter global `databaseFactory` vit dans `sqflite_common` (pas dans
// `sqflite`, qui n'exporte que l'implémentation native Android/iOS) ;
// `databaseFactoryFfiWeb` vient de `sqflite_common_ffi_web`.
import 'package:sqflite_common/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'core/offline/offline_bootstrap.dart';
import 'core/routes/app_router.dart';
import 'core/services/collecteur_erreurs.dart';
import 'core/services/locale_controller.dart';
import 'core/services/push_bootstrap.dart';
import 'core/services/verrou_biometrique.dart';
import 'core/widgets/garde_biometrique.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'injection_container.dart' as di;
import 'l10n/generated/app_localizations.dart';

/// Tampon des erreurs survenues avant que Crashlytics soit joignable.
final CollecteurErreurs _collecteur = CollecteurErreurs();

/// Branchement réel sur Crashlytics, une fois Firebase initialisé.
class _PuitsCrashlytics implements PuitsErreurs {
  const _PuitsCrashlytics();

  @override
  void erreurFlutter(FlutterErrorDetails details) =>
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);

  @override
  void erreur(Object erreur, StackTrace? pile) =>
      FirebaseCrashlytics.instance.recordError(erreur, pile, fatal: true);
}

/// Démarre l'application en surveillant TOUS les canaux d'erreur Flutter/Dart,
/// pour que plus aucun crash en production ne reste invisible (voir l'audit
/// production de ce projet — c'était le point le plus grave après la signature
/// de release).
///
/// ## Pourquoi cette fonction n'attend plus Firebase
///
/// Elle le faisait : `await Firebase.initializeApp()` puis
/// `await setCrashlyticsCollectionEnabled(...)` AVANT `runApp`. Deux allers
/// simples vers le natif que chaque utilisateur payait à chaque démarrage,
/// écran noir, pour couvrir une fenêtre où il ne se passe presque rien.
///
/// Firebase s'initialise désormais PENDANT que l'application s'affiche. Le
/// piège évident de cette inversion — perdre les erreurs de la fenêtre
/// d'initialisation, justement celles qui révèlent une config absente ou une
/// migration ratée — est désarmé par [CollecteurErreurs] : les gestionnaires
/// sont posés SYNCHRONEMENT ci-dessous, avant la première image, et tout ce
/// qu'ils captent est rejoué dès que Crashlytics répond.
///
/// ## Répartition des canaux
///
/// `runZonedGuarded` encadre `runApp` : c'est le seul mécanisme qui capture
/// les erreurs asynchrones non gérées levées HORS du framework Flutter
/// (`Future`s orphelines, `Timer` callbacks…) — `FlutterError.onError` et
/// `PlatformDispatcher.instance.onError` ne couvrent, respectivement, que
/// les erreurs de construction/rendu du framework et les erreurs de
/// plateforme/isolat racine.
///
/// ## Tolérance aux pannes
///
/// Sans `google-services.json` (voir `push_service.dart` pour le même principe
/// déjà établi pour le push), `Firebase.initializeApp()` échoue et le
/// collecteur renonce en silence — l'app fonctionne normalement, juste sans
/// télémétrie de crash. Jamais de plantage AU DÉMARRAGE à cause d'une config
/// Firebase absente.
void _demarrerAvecSurveillanceCrash(Widget app) {
  // Erreurs de construction/rendu du framework Flutter (widgets, layout…).
  FlutterError.onError = (details) {
    FlutterError.presentError(details); // garde le rouge/gris habituel en debug
    _collecteur.differer((puits) => puits.erreurFlutter(details));
  };

  // Erreurs natives/plateforme et erreurs Dart hors framework (isolat racine).
  PlatformDispatcher.instance.onError = (erreur, pile) {
    _signalerHorsFramework(erreur, pile);
    return true;
  };

  runZonedGuarded(
    () {
      runApp(app);
      // APRÈS `runApp` : la première image est construite et planifiée avant
      // que l'on sollicite le moindre canal de plateforme.
      unawaited(_brancherCrashlytics());
    },
    _signalerHorsFramework,
  );
}

void _signalerHorsFramework(Object erreur, StackTrace? pile) {
  // `PlatformDispatcher.onError` renvoie `true` (« gérée ») et `runZonedGuarded`
  // intercepte : sans cette trace, une erreur survenue avant le branchement —
  // ou sur une installation sans Firebase — disparaîtrait sans laisser le
  // moindre témoin.
  if (!_collecteur.estBranche) debugPrint('[erreur] $erreur\n$pile');
  _collecteur.differer((puits) => puits.erreur(erreur, pile));
}

Future<void> _brancherCrashlytics() async {
  try {
    // `Firebase.apps` : `PushService` initialise Firebase de son côté, et un
    // second `initializeApp()` sur l'app par défaut lèverait une erreur.
    if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    // Désactivé en debug : on veut voir les erreurs dans la console pendant le
    // développement, pas les envoyer à Crashlytics (bruit inutile, quotas).
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
  } catch (e) {
    debugPrint('[crashlytics] Firebase non configuré — suivi des crashs inactif ($e)');
    _collecteur.abandonner();
    return;
  }
  _collecteur.brancher(const _PuitsCrashlytics());
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // `sqflite` natif (Android/iOS) n'a pas d'équivalent sur le web — un
  // navigateur n'a pas de système de fichiers SQLite. `BaseLocale` (voir
  // core/offline/) appelle l'API globale `openDatabase`/`getDatabasesPath`
  // sans savoir si elle tourne dans un navigateur ; c'est ICI, au tout début
  // du programme et AVANT tout accès à la base (`di.init()` inclus), qu'on
  // bascule sa fabrique sur l'implémentation IndexedDB. Uniquement utile pour
  // `flutter run -d chrome` en développement (pas de device/émulateur
  // disponible) — l'app cible réellement Android/iOS, jamais le web en
  // production.
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }

  await di.init();
  _demarrerAvecSurveillanceCrash(const SuivieChantierApp());
}

class SuivieChantierApp extends StatefulWidget {
  const SuivieChantierApp({super.key});

  @override
  State<SuivieChantierApp> createState() => _SuivieChantierAppState();
}

class _SuivieChantierAppState extends State<SuivieChantierApp> {
  /// Le routeur est construit UNE FOIS, hors de `build`.
  ///
  /// Il ne l'était pas : `buildAppRouter(context)` était appelé depuis un
  /// `Builder`, donc à CHAQUE reconstruction de ce sous-arbre. Or
  /// `AppRouter(...).router` fabrique un GoRouter neuf — avec sa `StatefulShellRoute`,
  /// le `GlobalKey<NavigatorState>` de celle-ci et un `GoRouterRefreshStream`
  /// abonné au flux d'`AuthBloc`. Trois conséquences, toutes observées :
  ///
  ///  - **écrans relancés sans fin** : la pile de navigation repartait de
  ///    zéro, les `BlocProvider(create: … ..charger())` des pages rejouaient
  ///    leur chargement, et le jeton anti-course de chaque cubit invalidait la
  ///    requête précédente. L'onglet Réserves n'atteignait donc jamais son
  ///    état final : six rectangles gris, indéfiniment ;
  ///  - **fuite par reconstruction** : l'abonnement au flux du routeur
  ///    précédent n'était jamais résilié, et autant d'anciens routeurs
  ///    continuaient d'évaluer leurs redirections dans le vide ;
  ///  - **deux navigateurs dans l'arbre** : go_router keye le sien par
  ///    `GlobalObjectKey(navigatorKey.hashCode)`. Deux routeurs vivants, c'est
  ///    deux navigateurs porteurs d'une clé GLOBALE au même instant — le
  ///    terrain exact du « Duplicate GlobalKey » signalé sur
  ///    `flutter run -d chrome`. Je n'ai pas pu reproduire cette erreur pour
  ///    en confirmer le mécanisme précis ; les deux points ci-dessus, eux,
  ///    sont établis et vérifiés par `test/core/routes/`.
  ///
  /// `late final` : construit à la première lecture, jamais reconstruit.
  late final AuthBloc _authBloc = di.sl<AuthBloc>();
  late final _router = AppRouter(_authBloc).router;

  @override
  Widget build(BuildContext context) {
    // `.value` et non `create:` : l'`AuthBloc` est un singleton du conteneur
    // d'injection, qui en garde la propriété. Le fermer à la disparition de ce
    // widget laisserait un bloc clos dans le conteneur, prêt à lever une
    // `StateError` au prochain `sl<AuthBloc>()`.
    return BlocProvider<AuthBloc>.value(
      value: _authBloc,
      // `ValueListenableBuilder` plutôt qu'un `Provider` : même schéma que
      // `BandeauConnexion`/`SynchronisationService` déjà dans l'app — un
      // service `ValueNotifier` simple suffit, pas besoin d'un système de
      // state management dédié pour une seule valeur.
      child: ValueListenableBuilder<Locale>(
        valueListenable: di.sl<LocaleController>(),
        builder: (context, locale, _) {
          return MaterialApp.router(
            title: 'Suivi Chantier',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            routerConfig: _router,
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              // Sélecteur de pays (inscription) — sans lui,
              // `Country.getTranslatedName(context)` renvoie toujours
              // `null` et le sélecteur retombe sur les noms anglais.
              CountryLocalizations.delegate,
            ],
            // `builder`, et non un widget englobant `MaterialApp.router` :
            // c'est le seul point où le contexte a accès à la fois à
            // `AuthBloc` (fourni au-dessus) et au `GoRouter` (fourni par
            // `routerConfig` juste ici), dont `PushBootstrap` a besoin pour
            // synchroniser le jeton d'appareil et naviguer au tap d'une
            // alerte.
            //
            // `OfflineBootstrap` englobe `PushBootstrap` : le bandeau réseau
            // doit rester visible même par-dessus un écran ouvert depuis une
            // notification push.
            // `GardeBiometrique` est le plus EXTÉRIEUR : le voile doit
            // couvrir jusqu'au bandeau réseau, et un écran ouvert depuis
            // une notification push ne doit pas être un chemin de
            // contournement du verrou.
            builder: (context, child) => GardeBiometrique(
              verrou: di.sl<VerrouBiometrique>(),
              child: OfflineBootstrap(
                child: PushBootstrap(child: child!),
              ),
            ),
          );
        },
      ),
    );
  }
}
