import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Keyboard shortcuts, in one place so the menu, the settings page and the handlers agree.
///
/// In-app (⌘ on macOS/web, Ctrl elsewhere):  ⌘K 검색 · ⌘N 한 줄 기록 · ⌘⇧R 녹음 · ⌘1–5 탭 · ⌘, 설정
/// System-wide (desktop only):                ⌘⇧Space 빠른 기록 — brings the window up and opens 한 줄 기록
class AppShortcuts {
  static bool get _mac => !kIsWeb && Platform.isMacOS;

  /// Desktop (not web, not tests): the global hotkey and the native menu make sense.
  static bool get desktop => !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  static String get modLabel => kIsWeb || _mac ? '⌘' : 'Ctrl+';

  static SingleActivator mod(LogicalKeyboardKey key, {bool shift = false}) =>
      SingleActivator(key, meta: kIsWeb || _mac, control: !(kIsWeb || _mac), shift: shift);

  static final search = mod(LogicalKeyboardKey.keyK);
  static final newLog = mod(LogicalKeyboardKey.keyN);
  static final record = mod(LogicalKeyboardKey.keyR, shift: true);
  static final settings = mod(LogicalKeyboardKey.comma);
  static final tabs = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
  ].map(mod).toList();

  /// For the settings page.
  static List<(String, String)> describe() => [
        ('${modLabel}K', '검색으로 이동해 입력'),
        ('${modLabel}N', '한 줄 기록'),
        ('$modLabel⇧R', '녹음'),
        ('${modLabel}1 … ${modLabel}5', '검색 · 로그 · 프로젝트 · 월간 정리 · 수집 탭'),
        ('$modLabel,', '설정'),
        if (desktop) ('$modLabel⇧Space', '어디서든 창을 띄우고 한 줄 기록 (전역)'),
      ];
}

/// Wires the in-app shortcuts around the home shell. Handlers run only when nothing else consumed
/// the key (text fields keep their own ⌘ shortcuts).
class ShortcutScope extends StatelessWidget {
  const ShortcutScope({
    super.key,
    required this.child,
    required this.onSearch,
    required this.onNewLog,
    required this.onRecord,
    required this.onSettings,
    required this.onTab,
  });
  final Widget child;
  final VoidCallback onSearch;
  final VoidCallback onNewLog;
  final VoidCallback onRecord;
  final VoidCallback onSettings;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        AppShortcuts.search: onSearch,
        AppShortcuts.newLog: onNewLog,
        AppShortcuts.record: onRecord,
        AppShortcuts.settings: onSettings,
        for (var i = 0; i < AppShortcuts.tabs.length; i++) AppShortcuts.tabs[i]: () => onTab(i),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}

/// The system-wide "quick capture" hotkey. Registered once per app run; a no-op on the web.
class GlobalHotkey {
  static HotKey? _registered;

  static final hotKey = HotKey(key: PhysicalKeyboardKey.space, modifiers: [HotKeyModifier.meta, HotKeyModifier.shift], scope: HotKeyScope.system);

  /// Call before runApp on desktop: clears stale registrations (hot reload) and prepares the window.
  static Future<void> prepare() async {
    if (!AppShortcuts.desktop) return;
    try {
      await windowManager.ensureInitialized();
      await hotKeyManager.unregisterAll();
    } catch (_) {
      // plugin missing (tests, unsupported build): the app still works without the hotkey
    }
  }

  static Future<void> register(VoidCallback onCapture) async {
    if (!AppShortcuts.desktop || _registered != null) return;
    try {
      await hotKeyManager.register(hotKey, keyDownHandler: (_) async {
        try {
          await windowManager.show();
          await windowManager.focus();
        } catch (_) {}
        onCapture();
      });
      _registered = hotKey;
    } catch (_) {}
  }

  static Future<void> unregister() async {
    final h = _registered;
    _registered = null;
    if (h == null) return;
    try {
      await hotKeyManager.unregister(h);
    } catch (_) {}
  }
}
