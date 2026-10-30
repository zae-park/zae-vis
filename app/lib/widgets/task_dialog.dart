import 'dart:async';

import 'package:flutter/material.dart';

import '../backend/backend.dart';
import '../theme.dart';

/// Runs `zaevis <args>` from the app bundle. The log floats at the bottom right and can be dragged,
/// so a model download does not take the screen. Resolves to true when every command exited 0 and
/// the panel is closed. [then] runs after [args] in the same panel. A second call while one is open
/// waits on that same run.
Completer<bool>? _taskOpen;

Future<bool> runBackendTask(BuildContext context, Backend backend, String title, List<String> args, {List<String>? then}) {
  final pending = _taskOpen;
  if (pending != null) return pending.future;
  final completer = Completer<bool>();
  _taskOpen = completer;
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _TaskFloater(
      backend: backend,
      title: title,
      args: args,
      then: then,
      onDone: (ok) {
        entry.remove();
        _taskOpen = null;
        if (!completer.isCompleted) completer.complete(ok);
      },
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

class _TaskFloater extends StatefulWidget {
  const _TaskFloater({required this.backend, required this.title, required this.args, required this.onDone, this.then});
  final Backend backend;
  final String title;
  final List<String> args;
  final List<String>? then;
  final void Function(bool ok) onDone;

  @override
  State<_TaskFloater> createState() => _TaskFloaterState();
}

class _TaskFloaterState extends State<_TaskFloater> {
  final _lines = <String>[];
  final _stackKey = GlobalKey();
  final _cardKey = GlobalKey();
  String? _done;
  var _ok = false;
  bool _moved = false;
  Offset _topLeft = Offset.zero;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      await widget.backend.run(widget.args).forEach(_add);
      if (widget.then != null) await widget.backend.run(widget.then!).forEach(_add);
      _ok = true;
      if (mounted) setState(() => _done = '완료');
    } catch (e) {
      if (mounted) setState(() => _done = '실패: $e');
    }
  }

  void _add(String line) {
    if (mounted) setState(() => _lines.add(line));
  }

  void _drag(DragUpdateDetails details) {
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final card = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || card == null) return;
    if (!_moved) {
      _topLeft = stack.globalToLocal(card.localToGlobal(Offset.zero));
      _moved = true;
    }
    final size = stack.size;
    setState(() {
      final next = _topLeft + details.delta;
      _topLeft = Offset(next.dx.clamp(8, size.width - 368), next.dy.clamp(8, size.height - 80));
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final running = _done == null;
    return SizedBox.expand(
      key: _stackKey,
      child: Stack(children: [
        Positioned(
          left: _moved ? _topLeft.dx : null,
          top: _moved ? _topLeft.dy : null,
          right: _moved ? null : 20,
          bottom: _moved ? null : 24,
          width: 360,
          child: Material(
            key: _cardKey,
            elevation: 6,
            color: scheme.surfaceContainerLowest,
            shadowColor: Colors.black26,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.outlineVariant)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  GestureDetector(
                    onPanUpdate: _drag,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.drag_indicator, size: 18),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                      ),
                    ]),
                  ),
                  const Spacer(),
                  if (running)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                ]),
                SizedBox(
                  height: 120,
                  child: ListView(
                    reverse: true,
                    children: [
                      for (final line in _lines.reversed) Text(line, style: ZaevisTheme.mono.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: running ? null : () => widget.onDone(_ok),
                    child: Text(running ? '받는 중' : '${_done!} · 닫기'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
