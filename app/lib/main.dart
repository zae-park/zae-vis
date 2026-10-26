import 'package:flutter/material.dart';

import 'api.dart';
import 'backend/backend.dart';
import 'screens/collect_screen.dart';
import 'screens/index_sheet.dart';
import 'screens/log_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/projects_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/summaries_screen.dart';
import 'shortcuts.dart';
import 'theme.dart';
import 'recording/recorder.dart';
import 'widgets/input_dialogs.dart';
import 'widgets/record_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await GlobalHotkey.prepare();
  runApp(ZaevisApp(api: WorklogApi(), backend: createBackend()));
}

class ZaevisApp extends StatelessWidget {
  const ZaevisApp({super.key, required this.api, this.backend, this.recorder, this.desktopIntegration = true});
  final WorklogApi api;

  /// null in tests / when the server is managed elsewhere.
  final Backend? backend;

  /// Microphone source; tests pass a fake, the app uses the platform plugin.
  final Recorder? recorder;

  /// Native menu bar and the system-wide hotkey (desktop builds only; tests turn it off).
  final bool desktopIntegration;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'zaevis',
      debugShowCheckedModeBanner: false,
      theme: ZaevisTheme.of(Brightness.light),
      darkTheme: ZaevisTheme.of(Brightness.dark),
      home: backend == null
          ? HomeShell(api: api, recorder: recorder, desktopIntegration: desktopIntegration)
          : _BootGate(api: api, backend: backend!, recorder: recorder, desktopIntegration: desktopIntegration),
    );
  }
}

/// Packaged app: first-run wizard, then make sure the bundled server is up.
class _BootGate extends StatefulWidget {
  const _BootGate({required this.api, required this.backend, this.recorder, this.desktopIntegration = true});
  final WorklogApi api;
  final Backend backend;
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
    if (!b.managed) return HomeShell(api: widget.api, backend: b, recorder: widget.recorder, desktopIntegration: widget.desktopIntegration);
    if (!_configured) {
      return OnboardingScreen(backend: b, api: widget.api, onDone: () => setState(() => _configured = true));
    }
    return FutureBuilder<void>(
      future: _start(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('zaevis 준비 중…'),
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
                  Text('서버를 시작하지 못했습니다.\n${snap.error}', textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text('로그: ~/.zaevis/server.log'),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: () => setState(() => _starting = null), child: const Text('다시 시도')),
                ]),
              ),
            ),
          );
        }
        return HomeShell(api: widget.api, backend: b, recorder: widget.recorder, desktopIntegration: widget.desktopIntegration);
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

const _dests = [
  _Dest('검색', Icons.search, Icons.search, '기록 전체를 뜻과 단어로 찾습니다'),
  _Dest('로그', Icons.list_alt_outlined, Icons.list_alt, '날짜순 한 줄 기록 — 내가 쓴 줄과 정리가 쓴 줄'),
  _Dest('프로젝트', Icons.folder_outlined, Icons.folder, '프로젝트별 현재 상태 · 결정 · 열린 문제'),
  _Dest('월간 정리', Icons.calendar_month_outlined, Icons.calendar_month, '달마다 정리된 요약'),
  _Dest('수집', Icons.input_outlined, Icons.input, '데이터소스와 inbox, 바로 넣기'),
];

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.api, this.backend, this.recorder, this.desktopIntegration = true});
  final WorklogApi api;
  final Backend? backend;
  final Recorder? recorder;
  final bool desktopIntegration;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _generation = 0; // bumped when the server address changes, to reload every screen
  final _searchFocus = FocusNode();

  WorklogApi get api => widget.api;

  bool get _native => widget.desktopIntegration && AppShortcuts.desktop;

  @override
  void initState() {
    super.initState();
    if (_native) GlobalHotkey.register(_quickCapture);
  }

  @override
  void dispose() {
    if (_native) GlobalHotkey.unregister();
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
    if (i >= 0 && i < _dests.length) setState(() => _index = i);
  }

  void _openProject(String slug) => openProject(context, api, slug);

  void _openSettings() => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(api: api, backend: widget.backend, onServerChanged: () => setState(() => _generation++)),
      ));

  Future<void> _addLog() async {
    List<String> projects = const [];
    try {
      projects = (await api.projects()).map((p) => p.slug).toList();
    } catch (_) {}
    if (!mounted) return;
    if (await showAddLogDialog(context, api, projects: projects)) {
      if (!mounted) return;
      toast(context, '로그에 추가했습니다');
      setState(() => _generation++);
    }
  }

  Widget _screen() => switch (_index) {
        0 => SearchScreen(api: api, onOpenIndex: () => IndexSheet.show(context, api), focusNode: _searchFocus),
        1 => LogScreen(api: api, onOpenProject: _openProject),
        2 => ProjectsScreen(api: api),
        3 => SummariesScreen(api: api, onOpenProject: _openProject),
        _ => CollectScreen(api: api, recorder: widget.recorder),
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
    return PlatformMenuBar(
      menus: [
        PlatformMenu(label: 'zaevis', menus: [
          PlatformMenuItem(label: '설정…', shortcut: AppShortcuts.settings, onSelected: _openSettings),
          const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
          const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
        ]),
        PlatformMenu(label: '기록', menus: [
          PlatformMenuItem(label: '한 줄 기록', shortcut: AppShortcuts.newLog, onSelected: _addLog),
          PlatformMenuItem(label: '녹음', shortcut: AppShortcuts.record, onSelected: _record),
        ]),
        PlatformMenu(label: '보기', menus: [
          PlatformMenuItem(label: '검색', shortcut: AppShortcuts.search, onSelected: _focusSearch),
          PlatformMenuItemGroup(members: [
            for (var i = 0; i < _dests.length; i++)
              PlatformMenuItem(label: _dests[i].label, shortcut: AppShortcuts.tabs[i], onSelected: () => _selectTab(i)),
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
        ? FloatingActionButton.extended(onPressed: _addLog, icon: const Icon(Icons.edit_note), label: const Text('한 줄 기록'))
        : null;

    if (wide) {
      return Scaffold(
        floatingActionButton: fab,
        body: Row(children: [
          _Sidebar(
            index: _index,
            onSelect: (i) => setState(() => _index = i),
            onRecord: _record,
            onIndex: () => IndexSheet.show(context, api),
            onSettings: _openSettings,
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _PageHeader(dest: _dests[_index]),
              Expanded(child: body),
            ]),
          ),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_dests[_index].label),
        actions: [
          IconButton(tooltip: '녹음', icon: const Icon(Icons.mic_none), onPressed: _record),
          IconButton(tooltip: '검색 색인', icon: const Icon(Icons.storage_outlined), onPressed: () => IndexSheet.show(context, api)),
          IconButton(tooltip: '설정', icon: const Icon(Icons.settings_outlined), onPressed: _openSettings),
        ],
      ),
      floatingActionButton: fab,
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in _dests)
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
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('zaevis', style: t.titleMedium?.copyWith(letterSpacing: -0.3, height: 1.1)),
              Text('작업 기록 · 지식', style: t.labelSmall),
            ]),
          ]),
        ),
        for (var i = 0; i < _dests.length; i++) _NavItem(dest: _dests[i], selected: i == index, onTap: () => onSelect(i)),
        const Spacer(),
        Tooltip(message: '녹음', child: FilledButton.tonalIcon(onPressed: onRecord, icon: const Icon(Icons.mic, size: 18), label: const Text('녹음'))),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _SmallAction(icon: Icons.storage_outlined, label: '색인', onTap: onIndex)),
          const SizedBox(width: 6),
          Expanded(child: _SmallAction(icon: Icons.settings_outlined, label: '설정', onTap: onSettings)),
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
              Text(label, style: t.labelMedium),
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
