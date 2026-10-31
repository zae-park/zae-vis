import 'package:flutter/material.dart';

import '../recording_trail.dart';

/// The same one-line status for a recording, wherever the app shows it.
class RecordingTrailStrip extends StatelessWidget {
  const RecordingTrailStrip({super.key, required this.items, required this.onOpen});
  final List<RecordingTrail> items;
  final void Function(RecordingTrail item) onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final item in items)
          InkWell(
            onTap: item.watch || item.openPath != null ? () => onOpen(item) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Icon(_icon(item.stage), size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(item.sentence, style: t.bodySmall, maxLines: 2)),
                const SizedBox(width: 8),
                Flexible(child: Text(item.file, style: t.labelSmall?.copyWith(color: scheme.outline), overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
      ]),
    );
  }

  IconData _icon(RecordingStage stage) => switch (stage) {
        RecordingStage.running || RecordingStage.indexing => Icons.timelapse,
        RecordingStage.failed => Icons.error_outline,
        RecordingStage.queued => Icons.schedule,
        _ => Icons.article_outlined,
      };
}
