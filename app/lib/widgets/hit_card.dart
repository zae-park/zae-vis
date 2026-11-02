import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'markdown_view.dart';

/// One search hit: number, source labels, the best passage, the path. Tap opens the original; the icon saves it.
class HitCard extends StatelessWidget {
  const HitCard({super.key, required this.hit, required this.onOpen, this.onDownload, this.maxLines = 8});
  final SearchHit hit;
  final VoidCallback onOpen;
  final VoidCallback? onDownload;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ctx = hit.context;
    final labels = ctx?.labels ?? [hit.title];
    return Opacity(
      opacity: hit.weak ? 0.55 : 1,
      child: Card.outlined(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: hit.path.isEmpty ? null : onOpen,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 12, child: Text('${hit.number}', style: t.labelSmall)),
                const SizedBox(width: 10),
                Expanded(
                  child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    for (var i = 0; i < labels.length; i++)
                      Text(labels[i], style: i == 0 ? t.titleSmall : t.bodyMedium?.copyWith(color: i == labels.length - 1 && ctx?.author != null ? scheme.tertiary : null)),
                    if (hit.weak) Chip(label: const Text('약한 일치'), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, labelStyle: t.labelSmall),
                  ]),
                ),
                if (onDownload != null && hit.path.isNotEmpty)
                  IconButton(tooltip: '파일 내려받기', icon: const Icon(Icons.download_outlined, size: 20), visualDensity: VisualDensity.compact, onPressed: onDownload),
              ]),
              if (hit.snippet.isNotEmpty) ...[
                const SizedBox(height: 8),
                // minLines matters: without it SelectableText reserves the full maxLines height
                SelectableText.rich(inlineSpan(context, hit.snippet, base: t.bodyMedium, highlight: ctx?.matched ?? const []), minLines: 1, maxLines: maxLines),
              ],
              if (hit.path.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(hit.path, style: ZaevisTheme.mono.copyWith(fontSize: 11.5, color: scheme.outline)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
