import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

/// Accès court aux traductions — `context.l10n.xxx` plutôt que
/// `AppLocalizations.of(context).xxx` à chaque appel.
///
/// `nullable-getter: false` (voir l10n.yaml) : `AppLocalizations.of` est déjà
/// non-nullable — Flutter garantit sa présence pour tout `build()` sous
/// `MaterialApp` (voir `localizationsDelegates` dans main.dart), il n'y a donc
/// pas de `!` à poser ici.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
