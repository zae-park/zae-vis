import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Keyboard shortcuts, in one place so the menu, the settings page and the handlers agree.
///
/// In-app (⌘ on macOS/web, Ctrl elsewhere):  ⌘K 검색 · ⌘N 한 줄 기록 · ⌘⇧R 녹음 · ⌘1–5 탭 · ⌘, 설정
/// System-wide (desktop only):                ⌘⇧Space 빠른 기록 by default — brings the window up and
///                                            opens 한 줄 기록; changeable in 설정 (stored on the server
///                                            as a spec like "meta+shift+space").
class AppShortcuts {
  static bool get _mac => !kIsWeb && Platform.isMacOS;

  /// Desktop (not web, not tests): the global hotkey makes sense.
  static bool get desktop => !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// Flutter's PlatformMenuBar exists only on macOS; elsewhere the in-app shortcuts are the whole story.
  static bool get nativeMenu => _mac;

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
  ].map(mod).toList();

  /// For the settings page. [hotkey] is the stored global hotkey spec ("" = platform default).
  static List<(String, String)> describe({String hotkey = ''}) => [
        ('${modLabel}K', '검색으로 이동해 입력'),
        ('${modLabel}N', '한 줄 기록'),
        ('$modLabel⇧R', '녹음'),
        ('${modLabel}1 … ${modLabel}4', '검색 · 메모리 · 리포트 · 연결 탭'),
        ('$modLabel,', '설정'),
        if (desktop) (HotkeySpec.label(hotkey), '어디서든 창을 띄우고 한 줄 기록 (전역)'),
      ];
}

/// The global hotkey as text, the way the server stores it: lowercase modifier and key names joined
/// with "+", e.g. "meta+shift+space" or "control+alt+k". Platform-neutral so one settings file works
/// on a Mac and a Windows machine; "" means the platform default.
class HotkeySpec {
  HotkeySpec._();

  static const _mods = {'meta': HotKeyModifier.meta, 'control': HotKeyModifier.control, 'alt': HotKeyModifier.alt, 'shift': HotKeyModifier.shift};

  /// Key names → physical keys. Letters, digits, function keys, space and the common punctuation.
  static final Map<String, PhysicalKeyboardKey> _keys = {
    for (var c = 0; c < 26; c++) String.fromCharCode(97 + c): PhysicalKeyboardKey.findKeyByCode(0x00070004 + c)!,
    for (var d = 1; d <= 9; d++) '$d': PhysicalKeyboardKey.findKeyByCode(0x0007001e + d - 1)!,
    '0': PhysicalKeyboardKey.digit0,
    for (var f = 1; f <= 12; f++) 'f$f': PhysicalKeyboardKey.findKeyByCode(0x0007003a + f - 1)!,
    'space': PhysicalKeyboardKey.space,
    'enter': PhysicalKeyboardKey.enter,
    'tab': PhysicalKeyboardKey.tab,
    'escape': PhysicalKeyboardKey.escape,
    'backquote': PhysicalKeyboardKey.backquote,
    'minus': PhysicalKeyboardKey.minus,
    'equal': PhysicalKeyboardKey.equal,
    'bracketleft': PhysicalKeyboardKey.bracketLeft,
    'bracketright': PhysicalKeyboardKey.bracketRight,
    'semicolon': PhysicalKeyboardKey.semicolon,
    'quote': PhysicalKeyboardKey.quote,
    'comma': PhysicalKeyboardKey.comma,
    'period': PhysicalKeyboardKey.period,
    'slash': PhysicalKeyboardKey.slash,
    'backslash': PhysicalKeyboardKey.backslash,
    'arrowup': PhysicalKeyboardKey.arrowUp,
    'arrowdown': PhysicalKeyboardKey.arrowDown,
    'arrowleft': PhysicalKeyboardKey.arrowLeft,
    'arrowright': PhysicalKeyboardKey.arrowRight,
  };

  /// What the platform uses when nothing is stored: ⌘⇧Space on macOS, Ctrl+Shift+Space elsewhere
  /// (the Windows key is reserved by the OS).
  static String get platformDefault => AppShortcuts.nativeMenu ? 'meta+shift+space' : 'control+shift+space';

  /// Parses a spec. Returns null when it has no key, an unknown key, or no modifier
  /// (a bare key would swallow typing system-wide).
  static ({List<HotKeyModifier> modifiers, PhysicalKeyboardKey key, String name})? parse(String spec) {
    final parts = spec.toLowerCase().split('+').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    final mods = <HotKeyModifier>[];
    for (final p in parts.sublist(0, parts.length - 1)) {
      final m = _mods[p];
      if (m == null || mods.contains(m)) return null;
      mods.add(m);
    }
    final key = _keys[parts.last];
    if (key == null || mods.isEmpty) return null;
    return (modifiers: mods, key: key, name: parts.last);
  }

  static bool isValid(String spec) => parse(spec) != null;

  /// True for a modifier key on its own (⌘, Ctrl, …): not an error while recording, just not done yet.
  static bool isModifier(KeyEvent event) => HotKeyModifier.values.any((m) => m.physicalKeys.contains(event.physicalKey));

  /// A spec from a key event, or null when the event is a lone modifier or an unsupported key.
  static String? fromEvent(KeyEvent event) {
    final name = _keys.entries.where((e) => e.value == event.physicalKey).map((e) => e.key).firstOrNull;
    if (name == null) return null;
    final pressed = HardwareKeyboard.instance.physicalKeysPressed;
    final mods = [
      for (final e in _mods.entries)
        if (e.value.physicalKeys.any(pressed.contains)) e.key,
    ];
    if (mods.isEmpty) return null;
    return [...mods, name].join('+');
  }

  /// Human-readable: "⌘⇧Space" on macOS, "Ctrl+Shift+Space" elsewhere.
  static String label(String spec) {
    final p = parse(spec.isEmpty ? platformDefault : spec);
    if (p == null) return spec;
    final mac = AppShortcuts.nativeMenu;
    const macSym = {'meta': '⌘', 'control': '⌃', 'alt': '⌥', 'shift': '⇧'};
    const winSym = {'meta': 'Win', 'control': 'Ctrl', 'alt': 'Alt', 'shift': 'Shift'};
    final keyName = switch (p.name) {
      'space' => 'Space',
      'enter' => 'Enter',
      'tab' => 'Tab',
      'escape' => 'Esc',
      'backquote' => '`',
      'minus' => '-',
      'equal' => '=',
      'bracketleft' => '[',
      'bracketright' => ']',
      'semicolon' => ';',
      'quote' => "'",
      'comma' => ',',
      'period' => '.',
      'slash' => '/',
      'backslash' => r'\',
      'arrowup' => '↑',
      'arrowdown' => '↓',
      'arrowleft' => '←',
      'arrowright' => '→',
      final k => k.toUpperCase(),
    };
    final mods = p.modifiers.map((m) => (mac ? macSym : winSym)[m.name] ?? m.name);
    return mac ? '${mods.join()}$keyName' : [...mods, keyName].join('+');
  }
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
  static VoidCallback? _onCapture;

  /// The spec in effect ("" until [register] ran).
  static String current = '';

  static HotKey _hotKey(String spec) {
    final p = HotkeySpec.parse(spec) ?? HotkeySpec.parse(HotkeySpec.platformDefault)!;
    return HotKey(key: p.key, modifiers: p.modifiers, scope: HotKeyScope.system);
  }

  /// First-show size. The generated macOS window is 800×600, which clips the sidebar layout.
  static const launchSize = Size(1360, 860);
  static const minSize = Size(1120, 720);

  /// Call before runApp on desktop: clears stale registrations (hot reload) and prepares the window.
  static Future<void> prepare() async {
    if (!AppShortcuts.desktop) return;
    try {
      await windowManager.ensureInitialized();
      await hotKeyManager.unregisterAll();
      const options = WindowOptions(size: launchSize, minimumSize: minSize, center: true, title: 'zaevis');
      await windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (_) {
      // plugin missing (tests, unsupported build): the app still works without the hotkey
    }
  }

  /// Registers [spec] (or the platform default when empty / invalid).
  static Future<void> register(VoidCallback onCapture, {String spec = ''}) async {
    if (!AppShortcuts.desktop) return;
    _onCapture = onCapture;
    if (_registered != null) await unregister();
    final h = _hotKey(spec);
    try {
      await hotKeyManager.register(h, keyDownHandler: (_) async {
        try {
          await windowManager.show();
          await windowManager.focus();
        } catch (_) {}
        _onCapture?.call();
      });
      _registered = h;
      current = spec;
    } catch (_) {}
  }

  /// Re-registers with a new spec (after the user changed it in 설정).
  static Future<void> update(String spec) async {
    final cb = _onCapture;
    if (cb == null) return;
    await register(cb, spec: spec);
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
