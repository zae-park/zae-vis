import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../recording_trail.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/markdown_view.dart';
import '../widgets/input_dialogs.dart';
import '../widgets/save_file.dart';

/// The original worklog file behind a search hit, rendered as markdown.
class FileScreen extends StatelessWidget {
  const FileScreen({super.key, required this.api, required this.path});
  final WorklogApi api;
  final String path;

  static Future<void> open(BuildContext context, WorklogApi api, String path) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => FileScreen(api: api, path: path)));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(path.split('/').last), actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextButton.icon(onPressed: () => saveWorklogFile(context, api, path), icon: const Icon(Icons.download_outlined), label: const Text('내려받기')),
        ),
      ], bottom: PreferredSize(
        preferredSize: const Size.fromHeight(20),
        child: Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(path, style: ZaevisTheme.mono.copyWith(fontSize: 11.5, color: t.bodySmall?.color))),
      )),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _FileStageLine(api: api, path: path),
        Expanded(
          child: AsyncView<WorklogFile>(
            load: () => api.file(path),
            builder: (context, f, reload) {
              final speakers = isTranscriptPath(path) ? transcriptSpeakers(f.markdown) : const <String>[];
              return Readable(
                maxWidth: 1100,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (speakers.isNotEmpty) _SpeakerBar(api: api, path: path, speakers: speakers, onRenamed: reload),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      // a .txt keeps its line breaks; markdown would join them into one paragraph
                      child: path.toLowerCase().endsWith('.txt') ? PlainTextView(f.markdown) : MarkdownView(f.markdown),
                    ),
                  ),
                ]),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _FileStageLine extends StatefulWidget {
  const _FileStageLine({required this.api, required this.path});
  final WorklogApi api;
  final String path;

  @override
  State<_FileStageLine> createState() => _FileStageLineState();
}

class _FileStageLineState extends State<_FileStageLine> {
  late final Future<String?> _sentence = _load();

  Future<String?> _load() async {
    if (!widget.path.contains('inbox/transcripts/') && !widget.path.contains('processed/transcripts/')) return null;
    if (widget.path.contains('processed/transcripts/')) return recordingSentenceForPath(widget.path);
    try {
      final inbox = await widget.api.inbox();
      final index = await widget.api.indexStatus();
      return recordingSentenceForPath(widget.path, inbox: inbox, index: index);
    } catch (_) {
      return recordingSentenceForPath(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _sentence,
      builder: (context, snap) {
        final text = snap.data;
        if (text == null || text.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        );
      },
    );
  }
}

/// A transcript the speaker names can be changed in.
bool isTranscriptPath(String path) => RegExp(r'^(inbox|processed)/transcripts/[^/]+\.txt$').hasMatch(path);

/// Speaker labels in a transcript ("[A] " at the start of a turn), in order of appearance.
List<String> transcriptSpeakers(String text) {
  final seen = <String>[];
  for (final m in RegExp(r'^\[([^\]\n]{1,24})\] ', multiLine: true).allMatches(text)) {
    final label = m.group(1)!;
    if (!seen.contains(label)) seen.add(label);
  }
  return seen;
}

/// Plain text with its line breaks; a speaker label at the start of a line ("[A] ") is set in bold.
class PlainTextView extends StatelessWidget {
  const PlainTextView(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final label = RegExp(r'^\[([^\]\n]{1,24})\] ');
    final spans = <InlineSpan>[];
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final m = label.firstMatch(line);
      if (m != null) {
        spans.add(TextSpan(text: m.group(0), style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)));
        spans.add(TextSpan(text: line.substring(m.end)));
      } else {
        spans.add(TextSpan(text: line));
      }
      if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
    }
    return SelectableText.rich(TextSpan(style: t.bodyLarge?.copyWith(height: 1.6), children: spans), minLines: 1);
  }
}

/// "화자 [A] [B]": tap one to give it a name; the file changes on the server and the view reloads.
class _SpeakerBar extends StatelessWidget {
  const _SpeakerBar({required this.api, required this.path, required this.speakers, required this.onRenamed});
  final WorklogApi api;
  final String path;
  final List<String> speakers;
  final VoidCallback onRenamed;

  Future<void> _rename(BuildContext context, String label) async {
    final controller = TextEditingController(text: label);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('[$label] 이름'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '예: 재박'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('바꾸기')),
        ],
      ),
    );
    final next = name?.trim() ?? '';
    if (next.isEmpty || next == label || !context.mounted) return;
    try {
      await api.renameSpeakers(path, {label: next});
      if (context.mounted) toast(context, '[$label]을 [$next](으)로 바꿨습니다');
      onRenamed();
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('화자', style: t.labelMedium?.copyWith(color: scheme.outline)),
        for (final s in speakers)
          ActionChip(
            avatar: const Icon(Icons.edit_outlined, size: 16),
            label: Text(s),
            tooltip: '이름 붙이기',
            onPressed: () => _rename(context, s),
          ),
        Text('누르면 이름을 붙입니다. 이 파일에 바로 반영됩니다.', style: t.bodySmall?.copyWith(color: scheme.outline)),
      ]),
    );
  }
}
