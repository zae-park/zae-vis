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
import 'recording/recorder.dart';
import 'widgets/input_dialogs.dart';
import 'widgets/record_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ZaevisApp(api: WorklogApi(), backend: createBackend()));
}

class ZaevisApp extends StatelessWidget {
  const ZaevisApp({super.key, required this.api, this.backend, this.recorder});
  final WorklogApi api;

  /// null in tests / when the server is managed elsewhere.
  final Backend? backend;

  /// Microphone source; tests pass a fake, the app uses the platform plugin.
  final Recorder? recorder;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F6E8C), brightness: b),
          visualDensity: VisualDensity.standard,
        );
    return MaterialApp(
      title: 'zaevis',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: backend == null ? HomeShell(api: api, recorder: recorder) : _BootGate(api: api, backend: backend!, recorder: recorder),
    );
  }
}

/// Packaged app: first-run wizard, then make sure the bundled server is up.
class _BootGate extends StatefulWidget {
  const _BootGate({required this.api, required this.backend, this.recorder});
  final WorklogApi api;
  final Backend backend;
  final Recorder? recorder;

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
    if (!b.managed) return HomeShell(api: widget.api, backend: b, recorder: widget.recorder);
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
        return HomeShell(api: widget.api, backend: b, recorder: widget.recorder);
      },
    );
  }
}

class _Dest {
  const _Dest(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _dests = [
  _Dest('검색', Icons.search, Icons.search),
  _Dest('로그', Icons.list_alt_outlined, Icons.list_alt),
  _Dest('프로젝트', Icons.folder_outlined, Icons.folder),
  _Dest('월간 정리', Icons.calendar_month_outlined, Icons.calendar_month),
  _Dest('수집', Icons.input_outlined, Icons.input),
];

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.api, this.backend, this.recorder});
  final WorklogApi api;
  final Backend? backend;
  final Recorder? recorder;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _generation = 0; // bumped when the server address changes, to reload every screen

  WorklogApi get api => widget.api;

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
        0 => SearchScreen(api: api, onOpenIndex: () => IndexSheet.show(context, api)),
        1 => LogScreen(api: api, onOpenProject: _openProject),
        2 => ProjectsScreen(api: api),
        3 => SummariesScreen(api: api, onOpenProject: _openProject),
        _ => CollectScreen(api: api, recorder: widget.recorder),
      };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final body = KeyedSubtree(key: ValueKey('$_index/$_generation'), child: _screen());
    final actions = [
      IconButton(
        tooltip: '녹음',
        icon: const Icon(Icons.mic_none),
        onPressed: () async {
          await recordAndNotify(context, api, recorder: widget.recorder);
          if (mounted) setState(() => _generation++);
        },
      ),
      IconButton(
        tooltip: '검색 색인',
        icon: const Icon(Icons.storage_outlined),
        onPressed: () => IndexSheet.show(context, api),
      ),
      IconButton(tooltip: '설정', icon: const Icon(Icons.settings_outlined), onPressed: _openSettings),
    ];
    final fab = _index == 1
        ? FloatingActionButton.extended(onPressed: _addLog, icon: const Icon(Icons.edit_note), label: const Text('한 줄 기록'))
        : null;

    if (wide) {
      return Scaffold(
        appBar: AppBar(title: Text(_dests[_index].label), actions: actions),
        floatingActionButton: fab,
        body: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final d in _dests)
                NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: Text(d.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(_dests[_index].label), actions: actions),
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
