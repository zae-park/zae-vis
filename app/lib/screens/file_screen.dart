import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../recording_trail.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/markdown_view.dart';

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
      appBar: AppBar(title: Text(path.split('/').last), bottom: PreferredSize(
        preferredSize: const Size.fromHeight(20),
        child: Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(path, style: ZaevisTheme.mono.copyWith(fontSize: 11.5, color: t.bodySmall?.color))),
      )),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _FileStageLine(api: api, path: path),
        Expanded(
          child: AsyncView<WorklogFile>(
            load: () => api.file(path),
            builder: (context, f, _) => Readable(
              maxWidth: 1100,
              child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: MarkdownView(f.markdown)),
            ),
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
