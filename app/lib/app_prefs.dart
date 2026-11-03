import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';

/// Theme and text size, shared by every screen. Stored by the server (`appearance` in GET/PUT /api/settings) so the
/// app and the web page look the same; until the settings arrive the app follows the system.
class AppPrefs extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.system;
  double textScale = 1;

  /// The sizes offered, as a factor of the default (server/src/config.ts TEXT_SCALES).
  static const scales = <(double, String)>[(0.9, '작게'), (1, '기본'), (1.1, '조금 크게'), (1.2, '크게'), (1.3, '아주 크게')];

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
    if (mode == themeMode && s.textScale == textScale) return;
    themeMode = mode;
    textScale = s.textScale;
    notifyListeners();
  }

  Future<void> load(WorklogApi api) async {
    try {
      apply(await api.settings());
    } catch (_) {}
  }

  /// Changes at once, then saves; a failed save puts the old values back and rethrows.
  Future<void> save(WorklogApi api, {ThemeMode? mode, double? scale}) async {
    final (oldMode, oldScale) = (themeMode, textScale);
    themeMode = mode ?? themeMode;
    textScale = scale ?? textScale;
    notifyListeners();
    try {
      await api.updateSettings(appearance: {'theme': nameOf(themeMode), 'textScale': textScale});
    } catch (_) {
      themeMode = oldMode;
      textScale = oldScale;
      notifyListeners();
      rethrow;
    }
  }
}
