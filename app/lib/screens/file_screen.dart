import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
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
      body: AsyncView<WorklogFile>(
        load: () => api.file(path),
        builder: (context, f, _) => Readable(
          maxWidth: 1100,
          child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: MarkdownView(f.markdown)),
        ),
      ),
    );
  }
}
