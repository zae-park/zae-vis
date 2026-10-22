import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/index_sheet.dart';
import 'screens/log_screen.dart';
import 'screens/projects_screen.dart';
import 'screens/search_screen.dart';
import 'screens/summaries_screen.dart';

void main() => runApp(WorklogApp(api: WorklogApi()));

class WorklogApp extends StatelessWidget {
  const WorklogApp({super.key, required this.api});
  final WorklogApi api;

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F6E8C), brightness: b),
          visualDensity: VisualDensity.standard,
        );
    return MaterialApp(
      title: 'worklog',
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

  Future<void> _editServer() async {
    final controller = TextEditingController(text: api.baseUrl);
    final next = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('서버 주소'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: defaultDesktopBase),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('저장')),
        ],
      ),
    );
    // Not disposed here: the dialog's TextField still uses it during the close animation.
    if (next == null || next.trim().isEmpty) return;
    setState(() {
      api.baseUrl = next.trim();
      _generation++;
    });
  }

  Widget _screen() => switch (_index) {
        0 => SearchScreen(api: api, onOpenIndex: () => IndexSheet.show(context, api)),
        1 => LogScreen(api: api, onOpenProject: _openProject),
        2 => ProjectsScreen(api: api),
        _ => SummariesScreen(api: api, onOpenProject: _openProject),
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
      IconButton(tooltip: '서버 주소', icon: const Icon(Icons.settings_outlined), onPressed: _editServer),
    ];

    if (wide) {
      return Scaffold(
        appBar: AppBar(title: Text(_dests[_index].label), actions: actions),
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
