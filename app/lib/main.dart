import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'app_prefs.dart';
import 'backend/backend.dart';
import 'l10n/l10n.dart';
import 'screens/collect_screen.dart';
import 'screens/index_sheet.dart';
import 'screens/memory_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/projects_screen.dart' show openProject;
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/reports_screen.dart';
import 'shortcuts.dart';
import 'theme.dart';
import 'update.dart';
import 'recording/recorder.dart';
import 'widgets/input_dialogs.dart';
import 'widgets/record_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GlobalHotkey.prepare();
  runApp(ZaevisApp(api: WorklogApi(), backend: createBackend()));
}

class ZaevisApp extends StatefulWidget {
  const ZaevisApp({super.key, required this.api, this.backend, this.recorder, this.desktopIntegration = true, this.prefs});
  final WorklogApi api;

  /// null in tests / when the server is managed elsewhere.
  final Backend? backend;

  /// Microphone source; tests pass a fake, the app uses the platform plugin.
  final Recorder? recorder;

  /// Native menu bar and the system-wide hotkey (desktop builds only; tests turn it off).
  final bool desktopIntegration;

  /// Theme, text size and language; the app makes its own, tests may pass one.
  final AppPrefs? prefs;

  @override
  State<ZaevisApp> createState() => _ZaevisAppState();
}

class _ZaevisAppState extends State<ZaevisApp> {
  late final AppPrefs _prefs = widget.prefs ?? AppPrefs();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _prefs,
      builder: (context, _) => MaterialApp(
        title: 'zaevis',
        debugShowCheckedModeBanner: false,
        theme: ZaevisTheme.of(Brightness.light),
        darkTheme: ZaevisTheme.of(Brightness.dark),
        themeMode: _prefs.themeMode,
        locale: _prefs.materialLocale,
        supportedLocales: appLocales,
        localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        localeListResolutionCallback: (system, _) => resolveAppLocale('system', system ?? const []),
        builder: (context, child) {
          l10nNow = AppLocalizations.of(context)!;
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(_prefs.textScale)),
            child: child!,
          );
        },
        home: widget.backend == null
            ? HomeShell(api: widget.api, recorder: widget.recorder, desktopIntegration: widget.desktopIntegration, prefs: _prefs)
            : _BootGate(api: widget.api, backend: widget.backend!, recorder: widget.recorder, desktopIntegration: widget.desktopIntegration, prefs: _prefs),
      ),
    );
  }
}

/// Packaged app: first-run wizard, then make sure the bundled server is up.
class _BootGate extends StatefulWidget {
  const _BootGate({required this.api, required this.backend, required this.prefs, this.recorder, this.desktopIntegration = true});
  final WorklogApi api;
  final Backend backend;
  final AppPrefs prefs;
  final Recorder? recorder;
  final bool desktopIntegration;

  @override
  State<_BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<_BootGate> {
  late bool _configured = widget.backend.isConfigured;
  Future<void>? _starting;

  Future<void> _start() => _starting ??= widget.backend.ensureServer();

  @override
  Widget build(BuildContext context) {
    final b = widget.backend;
    if (!b.managed) return HomeShell(api: widget.api, backend: b, recorder: widget.recorder, desktopIntegration: widget.desktopIntegration, prefs: widget.prefs);
    if (!_configured) {
      return OnboardingScreen(backend: b, api: widget.api, onDone: () => setState(() => _configured = true));
    }
    return FutureBuilder<void>(
      future: _start(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(context.l10n.homeStarting),
          ])));
        }
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, size: 40),
                  const SizedBox(height: 12),
                  Text(context.l10n.homeStartFailed('${snap.error}'), textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(context.l10n.homeServerLog('~/.zaevis/server.log')),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: () => setState(() => _starting = null), child: Text(context.l10n.commonRetry)),
                ]),
              ),
            ),
          );
        }
        return HomeShell(api: widget.api, backend: b, recorder: widget.recorder, desktopIntegration: widget.desktopIntegration, prefs: widget.prefs);
      },
    );
  }
}

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon, this.hint);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final String hint;
}

List<_Dest> _dests(AppLocalizations l) => [
      _Dest(l.homeTabSearch, Icons.search, Icons.search, l.homeTabSearchHint),
      _Dest(l.homeTabMemory, Icons.memory_outlined, Icons.memory, l.homeTabMemoryHint),
      _Dest(l.homeTabReports, Icons.summarize_outlined, Icons.summarize, l.homeTabReportsHint),
      _Dest(l.homeTabConnect, Icons.hub_outlined, Icons.hub, l.homeTabConnectHint),
    ];

const _destCount = 4;

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.api, this.backend, this.recorder, this.desktopIntegration = true, this.prefs});
  final WorklogApi api;
  final Backend? backend;
  final Recorder? recorder;
  final bool desktopIntegration;

  /// Theme and text size from the app root; a shell built on its own (tests) makes one.
  final AppPrefs? prefs;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _generation = 0; // bumped when the server address changes, to reload every screen
  final _searchFocus = FocusNode();
  late final UpdateController _updates = UpdateController(localVersion: widget.backend?.buildVersion, install: widget.backend?.installUpdate);
  late final AppPrefs _prefs = widget.prefs ?? AppPrefs();
  bool _folderNotice = false;

  WorklogApi get api => widget.api;

  bool get _native => widget.desktopIntegration && AppShortcuts.desktop;

  @override
  void initState() {
    super.initState();
    if (_native) _registerHotkey();
    final backend = widget.backend;
    final local = backend?.buildVersion;
    _prefs.load(api);
    if (local != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updates.check());
      if (!folderSkipAcked(backend!.home)) _folderNotice = true;
    }
  }

  Future<void> _skipGuardedFolders() async {
    final home = widget.backend?.home;
    if (home != null) await ackFolderSkip(home);
    if (mounted) setState(() => _folderNotice = false);
  }

  /// The stored spec when the server answers, the platform default otherwise.
  Future<void> _registerHotkey() async {
    var spec = '';
    try {
      spec = (await api.settings()).hotkey;
    } catch (_) {}
    if (mounted) await GlobalHotkey.register(_quickCapture, spec: spec);
  }

  @override
  void dispose() {
    if (_native) GlobalHotkey.unregister();
    _updates.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// ⌘K: the search tab with the field focused and its text selected.
  void _focusSearch() {
    setState(() => _index = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  /// Global hotkey: the window is already in front; open 한 줄 기록 unless a dialog is up.
  void _quickCapture() {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    _addLog();
  }

  void _selectTab(int i) {
    if (i >= 0 && i < _destCount) setState(() => _index = i);
  }

  void _openProject(String slug) => openProject(context, api, slug);

  void _openSettings([SettingsSection initial = SettingsSection.general]) => SettingsScreen.show(context,
      api: api, backend: widget.backend, prefs: _prefs, updates: _updates, initial: initial, onServerChanged: () => setState(() => _generation++));

  Future<void> _addLog() async {
    List<String> projects = const [];
    try {
      projects = (await api.projects()).map((p) => p.slug).toList();
    } catch (_) {}
    if (!mounted) return;
    if (await showAddLogDialog(context, api, projects: projects)) {
      if (!mounted) return;
      toast(context, context.l10n.homeLogAdded);
      setState(() => _generation++);
    }
  }

  Widget _screen() => switch (_index) {
        0 => SearchScreen(api: api, onOpenIndex: () => IndexSheet.show(context, api, backend: widget.backend), onOpenSettings: () => _openSettings(SettingsSection.digest), focusNode: _searchFocus, recorder: widget.recorder),
        1 => MemoryScreen(api: api, onOpenProject: _openProject),
        2 => ReportsScreen(api: api, onOpenProject: _openProject),
        _ => CollectScreen(api: api, recorder: widget.recorder, backend: widget.backend),
      };

  Future<void> _record() async {
    await recordAndNotify(context, api, recorder: widget.recorder);
    if (mounted) setState(() => _generation++);
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShortcutScope(
      onSearch: _focusSearch,
      onNewLog: _addLog,
      onRecord: _record,
      onSettings: _openSettings,
      onTab: _selectTab,
      child: _layout(context),
    );
    if (!_native || !AppShortcuts.nativeMenu) return shell;
    // macOS menu bar: the same actions, discoverable with their shortcuts (Windows/Linux: shortcuts only)
    final l = context.l10n;
    final dests = _dests(l);
    return PlatformMenuBar(
      menus: [
        PlatformMenu(label: 'zaevis', menus: [
          PlatformMenuItem(label: l.homeMenuSettings, shortcut: AppShortcuts.settings, onSelected: _openSettings),
          const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
          const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
        ]),
        PlatformMenu(label: l.homeMenuLog, menus: [
          PlatformMenuItem(label: l.homeNewLog, shortcut: AppShortcuts.newLog, onSelected: _addLog),
          PlatformMenuItem(label: l.homeRecord, shortcut: AppShortcuts.record, onSelected: _record),
        ]),
        PlatformMenu(label: l.homeMenuView, menus: [
          PlatformMenuItem(label: l.commonSearch, shortcut: AppShortcuts.search, onSelected: _focusSearch),
          PlatformMenuItemGroup(members: [
            for (var i = 0; i < dests.length; i++)
              PlatformMenuItem(label: dests[i].label, shortcut: AppShortcuts.tabs[i], onSelected: () => _selectTab(i)),
          ]),
        ]),
      ],
      child: shell,
    );
  }

  Widget _layout(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final body = KeyedSubtree(key: ValueKey('$_index/$_generation'), child: _screen());
    final fab = _index == 1
        ? FloatingActionButton.extended(onPressed: _addLog, icon: const Icon(Icons.edit_note), label: Text(context.l10n.homeNewLog))
        : null;
    final scaffold = wide ? _wideScaffold(context, body, fab) : _narrowScaffold(context, body, fab);
    return ListenableBuilder(
      listenable: _updates,
      builder: (context, _) {
        final u = _updates;
        final card = u.offer != null && !u.dismissed;
        return Stack(children: [
          Positioned.fill(child: scaffold),
          if (card || _folderNotice)
            Positioned(
              top: 12,
              right: 16,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (card)
                  UpdateNotice(
                    offer: u.offer!,
                    phase: u.phase,
                    progress: u.progress,
                    error: u.error,
                    onLater: u.dismiss,
                    onUpdate: u.apply,
                  ),
                if (card && _folderNotice) const SizedBox(height: 8),
                if (_folderNotice) AccessNotice(onApply: _skipGuardedFolders),
              ]),
            ),
        ]);
      },
    );
  }

  Widget _wideScaffold(BuildContext context, Widget body, Widget? fab) {
    return Scaffold(
        floatingActionButton: fab,
        body: Row(children: [
          _Sidebar(
            index: _index,
            onSelect: (i) => setState(() => _index = i),
            onRecord: _record,
            onIndex: () => IndexSheet.show(context, api, backend: widget.backend),
            onSettings: _openSettings,
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _PageHeader(dest: _dests(context.l10n)[_index]),
              Expanded(child: body),
            ]),
          ),
        ]),
    );
  }

  Widget _narrowScaffold(BuildContext context, Widget body, Widget? fab) {
    final l = context.l10n;
    final dests = _dests(l);
    return Scaffold(
      appBar: AppBar(
        title: Text(dests[_index].label),
        actions: [
          IconButton(tooltip: l.homeRecord, icon: const Icon(Icons.mic_none), onPressed: _record),
          IconButton(tooltip: l.homeSearchIndex, icon: const Icon(Icons.storage_outlined), onPressed: () => IndexSheet.show(context, api, backend: widget.backend)),
          IconButton(tooltip: l.commonSettings, icon: const Icon(Icons.settings_outlined), onPressed: _openSettings),
        ],
      ),
      floatingActionButton: fab,
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in dests)
            NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
        ],
      ),
    );
  }
}

/// Wide layout: a labelled sidebar with the wordmark on top and the global actions at the bottom.
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.index, required this.onSelect, required this.onRecord, required this.onIndex, required this.onSettings});
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onRecord;
  final VoidCallback onIndex;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final l = context.l10n;
    final dests = _dests(l);
    return Container(
      width: 212,
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, border: Border(right: BorderSide(color: scheme.outlineVariant))),
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 8, 18),
          child: Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(8)),
              alignment: Alignment.center,
              child: Text('z', style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 17, height: 1)),
            ),
            const SizedBox(width: 10),
            // a larger text size (설정 → 일반) must not push the wordmark past the sidebar
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('zaevis', style: t.titleMedium?.copyWith(letterSpacing: -0.3, height: 1.1), maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
                Text(l.homeTagline, style: t.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
        for (var i = 0; i < dests.length; i++) _NavItem(dest: dests[i], selected: i == index, onTap: () => onSelect(i)),
        const Spacer(),
        Tooltip(message: l.homeRecord, child: FilledButton.tonalIcon(onPressed: onRecord, icon: const Icon(Icons.mic, size: 18), label: Text(l.homeRecord))),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _SmallAction(icon: Icons.storage_outlined, label: l.homeIndex, onTap: onIndex)),
          const SizedBox(width: 6),
          Expanded(child: _SmallAction(icon: Icons.settings_outlined, label: l.commonSettings, onTap: onSettings)),
        ]),
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.dest, required this.selected, required this.onTap});
  final _Dest dest;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? scheme.primary.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              Icon(selected ? dest.selectedIcon : dest.icon, size: 20, color: selected ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 10),
              Text(dest.label, style: t.bodyMedium?.copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? scheme.primary : scheme.onSurface)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SmallAction extends StatelessWidget {
  const _SmallAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Tooltip(
          message: label,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelMedium)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Title line of each page on the wide layout: the tab name plus what the page is for.
class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.dest});
  final _Dest dest;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(dest.label, style: t.headlineSmall),
        const SizedBox(width: 12),
        Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(dest.hint, style: t.bodySmall, overflow: TextOverflow.ellipsis))),
      ]),
    );
  }
}
