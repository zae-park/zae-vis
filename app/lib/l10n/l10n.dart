import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// The locales the app offers, in the order the language menu lists them; Korean is the default.
const appLocales = [Locale('ko'), Locale('en')];

/// The language for a saved choice ("system" | "ko" | "en") and the OS languages: Korean for Korean, otherwise English.
Locale resolveAppLocale(String choice, List<Locale> system) {
  if (choice == 'ko' || choice == 'en') return Locale(choice);
  for (final l in system) {
    if (l.languageCode == 'ko') return const Locale('ko');
    if (l.languageCode == 'en') return const Locale('en');
  }
  return system.isEmpty ? const Locale('ko') : const Locale('en');
}

AppLocalizations _now = lookupAppLocalizations(const Locale('ko'));

/// Strings for code without a BuildContext (models, controllers, the API client). ZaevisApp keeps it on the app's
/// language; it is Korean until then.
AppLocalizations get l10nNow => _now;
set l10nNow(AppLocalizations l) => _now = l;

extension L10nContext on BuildContext {
  /// The app's strings; outside a localized MaterialApp (some widget tests) it falls back to [l10nNow].
  AppLocalizations get l10n => Localizations.of<AppLocalizations>(this, AppLocalizations) ?? _now;
}
