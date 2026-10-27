import 'package:flutter/material.dart';

import '../backend/backend.dart';
import '../theme.dart';

/// Runs `zaevis <args>` from the app bundle and shows its output live in a dialog. Resolves to true
/// when every command exited 0. [then] runs after [args] in the same dialog.
Future<bool> runBackendTask(BuildContext context, Backend backend, String title, List<String> args, {List<String>? then}) async {
  final lines = ValueNotifier<List<String>>(const []);
  final done = ValueNotifier<String?>(null);
  var ok = false;
  void add(String l) => lines.value = [...lines.value, l];
  () async {
    try {
      await backend.run(args).forEach(add);
      if (then != null) await backend.run(then).forEach(add);
      ok = true;
      done.value = '완료';
    } catch (e) {
      done.value = '실패: $e';
    }
  }();
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 600,
        height: 320,
        child: ValueListenableBuilder<List<String>>(
          valueListenable: lines,
          builder: (_, l, __) => ListView(reverse: true, children: [
            for (final line in l.reversed) Text(line, style: ZaevisTheme.mono.copyWith(fontSize: 12)),
          ]),
        ),
      ),
      actions: [
        ValueListenableBuilder<String?>(
          valueListenable: done,
          builder: (context, d, _) => d == null
              ? const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              : TextButton(onPressed: () => Navigator.pop(context), child: Text('$d · 닫기')),
        ),
      ],
    ),
  );
  return ok;
}
