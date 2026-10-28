import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import 'common.dart';

void toast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? Theme.of(context).colorScheme.error : null,
  ));
}

/// One log line: text + tag chips + project. Returns true when saved.
Future<bool> showAddLogDialog(BuildContext context, WorklogApi api, {List<String> projects = const []}) async {
  final saved = await showDialog<bool>(context: context, builder: (_) => _AddLogDialog(api: api, projects: projects));
  return saved == true;
}

/// Edits an existing line of log/<month>.md (text, tag, project, date). Returns true when saved.
Future<bool> showEditLogDialog(BuildContext context, WorklogApi api, {required String month, required LogEntry entry, List<String> projects = const []}) async {
  final saved = await showDialog<bool>(context: context, builder: (_) => _AddLogDialog(api: api, projects: projects, month: month, entry: entry));
  return saved == true;
}

class _AddLogDialog extends StatefulWidget {
  const _AddLogDialog({required this.api, required this.projects, this.month, this.entry});
  final WorklogApi api;
  final List<String> projects;

  /// Set together for edit mode: the month file and the line being edited.
  final String? month;
  final LogEntry? entry;

  bool get editing => entry != null;

  @override
  State<_AddLogDialog> createState() => _AddLogDialogState();
}

class _AddLogDialogState extends State<_AddLogDialog> {
  late final _text = TextEditingController(text: widget.entry?.text ?? '');
  late final _project = TextEditingController(text: widget.entry?.projects.firstOrNull ?? '');
  late final _date = TextEditingController(text: widget.entry?.date ?? '');
  late String? _tag = widget.entry?.tags.firstOrNull; // optional: a plain line is fine; tags only help filtering and the monthly summary
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _project.dispose();
    _date.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_text.text.trim().isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final p = _project.text.trim();
      if (widget.editing) {
        await widget.api.updateLog(widget.month!, widget.entry!.raw,
            text: _text.text, tags: [if (_tag != null) _tag!], projects: [if (p.isNotEmpty) p], date: _date.text.trim());
      } else {
        await widget.api.addLog(_text.text, tags: [if (_tag != null) _tag!], projects: [if (p.isNotEmpty) p]);
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.editing ? '줄 편집' : '한 줄 기록'),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _text,
            autofocus: true,
            maxLength: 500,
            decoration: const InputDecoration(hintText: '무엇을 했고, 왜 그렇게 했는지'),
            onSubmitted: (_) => _save(),
          ),
          if (widget.editing) ...[
            const SizedBox(height: 4),
            Row(children: [
              SizedBox(
                width: 120,
                child: TextField(controller: _date, decoration: const InputDecoration(labelText: '날짜', hintText: 'MM-DD')),
              ),
              if (widget.entry!.source != null) ...[
                const SizedBox(width: 12),
                Expanded(child: Text('정리가 쓴 줄입니다. 출처(${widget.entry!.source})는 그대로 남습니다.', style: Theme.of(context).textTheme.bodySmall)),
              ],
            ]),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final t in const ['done', 'decision', 'blocked', 'learned'])
              ChoiceChip(
                label: Text(tagLabel(t)),
                selected: _tag == t,
                onSelected: (on) => setState(() => _tag = on ? t : null),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _project,
            decoration: const InputDecoration(labelText: '프로젝트 (선택)', hintText: 'notes'),
          ),
          if (widget.projects.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final p in widget.projects.take(10))
                ActionChip(label: Text(p), visualDensity: VisualDensity.compact, onPressed: () => setState(() => _project.text = p)),
            ]),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('저장')),
      ],
    );
  }
}

/// Paste a transcript (from any tool) into the inbox.
Future<String?> showPasteTranscriptDialog(BuildContext context, WorklogApi api) async {
  final name = TextEditingController();
  final text = TextEditingController();
  final saved = await showDialog<String>(
    context: context,
    builder: (context) {
      String? error;
      bool saving = false;
      return StatefulBuilder(builder: (context, setLocal) {
        Future<void> save() async {
          setLocal(() => saving = true);
          try {
            final file = await api.pasteTranscript(name.text.trim().isEmpty ? '메모' : name.text.trim(), text.text);
            if (context.mounted) Navigator.pop(context, file);
          } on ApiException catch (e) {
            if (!context.mounted) return;
            setLocal(() {
              saving = false;
              error = e.message;
            });
          }
        }

        return AlertDialog(
          title: const Text('전사본 붙여넣기'),
          content: SizedBox(
            width: 640,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: '제목', hintText: '주간 정리 회의')),
              const SizedBox(height: 12),
              TextField(
                controller: text,
                minLines: 8,
                maxLines: 16,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '전사 서비스에서 복사한 내용을 붙여넣으세요'),
              ),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
            FilledButton(onPressed: saving ? null : save, child: const Text('저장')),
          ],
        );
      });
    },
  );
  return saved;
}

const audioExtensions = ['m4a', 'mp3', 'wav', 'aac', 'flac', 'ogg', 'opus', 'webm', 'mp4', 'mov', 'm4v'];

/// Pick recordings and upload them; the server transcribes them with whisperX in the background.
Future<int> pickAndUploadAudio(BuildContext context, WorklogApi api) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: audioExtensions,
    allowMultiple: true,
    withData: kIsWeb,
    withReadStream: !kIsWeb,
  );
  if (picked == null) return 0;
  var n = 0;
  for (final f in picked.files) {
    try {
      await api.uploadAudio(name: f.name, size: f.size, bytes: f.bytes, stream: f.readStream);
      n++;
    } on ApiException catch (e) {
      if (context.mounted) toast(context, '${f.name}: ${e.message}', error: true);
    }
  }
  return n;
}
