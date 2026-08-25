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
import 'core/services/locale_controller.dart';
import 'core/services/push_bootstrap.dart';
import 'core/services/verrou_biometrique.dart';
import 'core/widgets/garde_biometrique.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'injection_container.dart' as di;
import 'l10n/generated/app_localizations.dart';

/// Initialise Crashlytics et rebranche TOUS les canaux d'erreur Flutter/Dart
/// vers lui, pour que plus aucun crash en production ne reste invisible
/// (voir l'audit production de ce projet — c'était le point le plus grave
/// après la signature de release).
///
/// Idempotent et tolérant : sans `google-services.json` (voir
/// `push_service.dart` pour le même principe déjà établi pour le push),
/// `Firebase.initializeApp()` échoue et cette fonction renonce en silence —
/// l'app continue de fonctionner normalement, juste sans télémétrie de
/// crash. Jamais de plantage AU DÉMARRAGE à cause d'une config Firebase
/// absente.
///
/// `runZonedGuarded` encadre `runApp` : c'est le seul mécanisme qui capture
/// les erreurs asynchrones non gérées levées HORS du framework Flutter
/// (`Future`s orphelines, `Timer` callbacks…) — `FlutterError.onError` et
/// `PlatformDispatcher.instance.onError` ne couvrent, respectivement, que
/// les erreurs de construction/rendu du framework et les erreurs de
/// plateforme/isolat racine.
Future<void> _demarrerAvecSurveillanceCrash(Widget app) async {
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('[crashlytics] Firebase non configuré — suivi des crashs inactif ($e)');
    // Sans Firebase, on garde quand même un filet minimal en debug console —
    // mieux qu'un écran gris totalement muet pendant le développement local.
    FlutterError.onError = FlutterError.presentError;
    runApp(app);
    return;
  }

  // Erreurs de construction/rendu du framework Flutter (widgets, layout…).
  FlutterError.onError = (details) {
    FlutterError.presentError(details); // garde le rouge/gris habituel en debug
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };

  // Erreurs natives/plateforme et erreurs Dart hors framework (isolat racine).
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // Désactivé en debug : on veut voir les erreurs dans la console pendant le
  // développement, pas les envoyer à Crashlytics (bruit inutile, quotas).
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);

  runZonedGuarded(
    () => runApp(app),
    (error, stack) => FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
  );
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
  await _demarrerAvecSurveillanceCrash(const SuivieChantierApp());
}

class SuivieChantierApp extends StatelessWidget {
  const SuivieChantierApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuthBloc>(
      create: (_) => di.sl<AuthBloc>(),
      child: Builder(
        builder: (context) {
          final router = buildAppRouter(context);
          // `ValueListenableBuilder` plutôt qu'un `Provider` : même schéma que
          // `BandeauConnexion`/`SynchronisationService` déjà dans l'app — un
          // service `ValueNotifier` simple suffit, pas besoin d'un système de
          // state management dédié pour une seule valeur.
          return ValueListenableBuilder<Locale>(
            valueListenable: di.sl<LocaleController>(),
            builder: (context, locale, _) {
              return MaterialApp.router(
                title: 'Suivi Chantier',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                routerConfig: router,
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
          );
        },
      ),
    );
  }
}
