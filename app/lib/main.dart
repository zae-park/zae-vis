import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/collect_screen.dart';
import 'screens/index_sheet.dart';
import 'screens/log_screen.dart';
import 'screens/projects_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/summaries_screen.dart';
import 'widgets/input_dialogs.dart';

void main() => runApp(ZaevisApp(api: WorklogApi()));

class ZaevisApp extends StatelessWidget {
  const ZaevisApp({super.key, required this.api});
  final WorklogApi api;

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
      home: HomeShell(api: api),
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
  const HomeShell({super.key, required this.api});
  final WorklogApi api;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _generation = 0; // bumped when the server address changes, to reload every screen

  WorklogApi get api => widget.api;

  void _openProject(String slug) => openProject(context, api, slug);

  void _openSettings() => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(api: api, onServerChanged: () => setState(() => _generation++)),
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
        _ => CollectScreen(api: api),
      };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final body = KeyedSubtree(key: ValueKey('$_index/$_generation'), child: _screen());
    final actions = [
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
