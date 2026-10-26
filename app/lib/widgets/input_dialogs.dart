import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../api.dart';
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

class _AddLogDialog extends StatefulWidget {
  const _AddLogDialog({required this.api, required this.projects});
  final WorklogApi api;
  final List<String> projects;

  @override
  State<_AddLogDialog> createState() => _AddLogDialogState();
}

class _AddLogDialogState extends State<_AddLogDialog> {
  final _text = TextEditingController();
  final _project = TextEditingController();
  String? _tag; // optional: a plain line is fine; tags only help filtering and the monthly summary
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _project.dispose();
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
      await widget.api.addLog(_text.text, tags: [if (_tag != null) _tag!], projects: [if (p.isNotEmpty) p]);
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
      title: const Text('한 줄 기록'),
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
            decoration: const InputDecoration(labelText: '프로젝트 (선택)', hintText: 'roas-multihorizon'),
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
              TextField(controller: name, decoration: const InputDecoration(labelText: '제목', hintText: '주간 ROAS 회의')),
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
