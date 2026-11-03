import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n/l10n.dart';
import 'models.dart';

/// Theme, text size and language, shared by every screen. Stored by the server (`appearance` in GET/PUT /api/settings) so the
/// app and the web page look the same; until the settings arrive the app follows the system.
class AppPrefs extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.system;
  double textScale = 1;

  /// "system" | "ko" | "en"; see [resolveAppLocale].
  String locale = 'system';

  /// The sizes offered, as a factor of the default (server/src/config.ts TEXT_SCALES).
  static List<(double, String)> scales(AppLocalizations l) => [
        (0.9, l.textScaleSmall),
        (1, l.textScaleDefault),
        (1.1, l.textScaleLarger),
        (1.2, l.textScaleLarge),
        (1.3, l.textScaleHuge),
      ];

  /// The language menu: the saved value and its label.
  static List<(String, String)> locales(AppLocalizations l) =>
      [('system', l.settingsLanguageSystem), ('ko', l.languageKorean), ('en', l.languageEnglish)];

  /// The locale MaterialApp should use: null follows the system (see ZaevisApp's localeListResolutionCallback).
  Locale? get materialLocale => locale == 'system' ? null : Locale(locale);

  static ThemeMode modeOf(String theme) => switch (theme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String nameOf(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  void apply(AppSettings s) {
    final mode = modeOf(s.theme);
    if (mode == themeMode && s.textScale == textScale && s.locale == locale) return;
    themeMode = mode;
    textScale = s.textScale;
    locale = s.locale;
    notifyListeners();
  }

  Future<void> load(WorklogApi api) async {
    try {
      apply(await api.settings());
    } catch (_) {}
  }

  /// Changes at once, then saves; a failed save puts the old values back and rethrows.
  Future<void> save(WorklogApi api, {ThemeMode? mode, double? scale, String? locale}) async {
    final (oldMode, oldScale, oldLocale) = (themeMode, textScale, this.locale);
    themeMode = mode ?? themeMode;
    textScale = scale ?? textScale;
    this.locale = locale ?? this.locale;
    notifyListeners();
    try {
      await api.updateSettings(appearance: {'theme': nameOf(themeMode), 'textScale': textScale, 'locale': this.locale});
    } catch (_) {
      themeMode = oldMode;
      textScale = oldScale;
      this.locale = oldLocale;
      notifyListeners();
      rethrow;
    }
  }
}
