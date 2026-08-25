import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:suivie_chantier_mobile/l10n/generated/app_localizations.dart';

/// À ajouter aux `MaterialApp` de test qui pompent un widget lisant
/// `context.l10n` — sans ça, `AppLocalizations.of(context)` renvoie `null` et
/// le `!` de l'extension (`l10n_extension.dart`) plante au premier pump.
///
/// [testLocale] force le français explicitement : sans `locale:` fixé,
/// `flutter test` retombe sur la locale de la machine qui exécute les tests
/// (souvent `en_US`, parfois autre chose selon l'environnement) — les
/// assertions existantes, écrites en français, deviendraient alors instables
/// selon la machine. Le français est aussi la langue de démarrage réelle de
/// l'app (voir `LocaleController`), donc ce choix garde les tests fidèles au
/// comportement par défaut.
///
/// Usage :
/// ```dart
/// MaterialApp(
///   locale: testLocale,
///   localizationsDelegates: testLocalizationsDelegates,
///   supportedLocales: testSupportedLocales,
///   home: ...,
/// )
/// ```
const testLocale = Locale('fr');

const testLocalizationsDelegates = [
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

const testSupportedLocales = AppLocalizations.supportedLocales;
