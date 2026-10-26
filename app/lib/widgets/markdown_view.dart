import 'package:flutter/material.dart';

import '../theme.dart';

/// A small Markdown renderer for worklog files: headings, bullet / numbered / task lists,
/// fenced code, quotes, and inline **bold**, *italic*, `code`, $math$, [[links]] and #tags.
/// It intentionally avoids a third-party package; worklog files use a narrow subset.
class MarkdownView extends StatelessWidget {
  const MarkdownView(this.markdown, {super.key, this.onLink});

  final String markdown;
  final void Function(String slug)? onLink;

  @override
  Widget build(BuildContext context) {
    final blocks = parseBlocks(markdown);
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final b in blocks) _BlockWidget(b, onLink: onLink)],
      ),
    );
  }
}

enum BlockKind { heading, bullet, numbered, task, code, quote, paragraph }

class MdBlock {
  const MdBlock(this.kind, this.text, {this.level = 0, this.checked = false, this.marker = ''});
  final BlockKind kind;
  final String text;
  final int level; // heading level, or list indent level
  final bool checked;
  final String marker; // "1." for numbered lists
}

final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
final _task = RegExp(r'^(\s*)[-*]\s+\[( |x|X)\]\s+(.*)$');
final _bullet = RegExp(r'^(\s*)[-*]\s+(.*)$');
final _numbered = RegExp(r'^(\s*)(\d+\.)\s+(.*)$');

List<MdBlock> parseBlocks(String md) {
  final out = <MdBlock>[];
  final lines = md.replaceAll('\r\n', '\n').split('\n');
  final para = <String>[];
  void flush() {
    if (para.isNotEmpty) {
      out.add(MdBlock(BlockKind.paragraph, para.join(' ')));
      para.clear();
    }
  }

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('```')) {
      flush();
      final code = <String>[];
      i++;
      while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
        code.add(lines[i]);
        i++;
      }
      out.add(MdBlock(BlockKind.code, code.join('\n')));
      continue;
    }
    if (line.trim().isEmpty) {
      flush();
      continue;
    }
    RegExpMatch? m;
    if ((m = _heading.firstMatch(line)) != null) {
      flush();
      out.add(MdBlock(BlockKind.heading, m!.group(2)!, level: m.group(1)!.length));
    } else if ((m = _task.firstMatch(line)) != null) {
      flush();
      out.add(MdBlock(BlockKind.task, m!.group(3)!,
          level: m.group(1)!.length ~/ 2, checked: m.group(2)!.toLowerCase() == 'x'));
    } else if ((m = _bullet.firstMatch(line)) != null) {
      flush();
      out.add(MdBlock(BlockKind.bullet, m!.group(2)!, level: m.group(1)!.length ~/ 2));
    } else if ((m = _numbered.firstMatch(line)) != null) {
      flush();
      out.add(MdBlock(BlockKind.numbered, m!.group(3)!, level: m.group(1)!.length ~/ 2, marker: m.group(2)!));
    } else if (line.startsWith('>')) {
      flush();
      out.add(MdBlock(BlockKind.quote, line.replaceFirst(RegExp(r'^>\s?'), '')));
    } else {
      para.add(line.trim());
    }
  }
  flush();
  return out;
}

enum InlineKind { text, bold, italic, code, math, link, tag }

class MdInline {
  const MdInline(this.kind, this.text);
  final InlineKind kind;
  final String text;
}

// **bold** · *italic* · `code` · $math$ · [[link]] · #tag
final _inline = RegExp(
  // math needs no space right inside the dollars, so "$5 and $7" stays text
  r'\*\*(.+?)\*\*|(?<![\w*])\*([^*\n]+?)\*(?![\w*])|`([^`\n]+)`|\$(?!\s)([^$\n]+?)(?<!\s)\$|\[\[([^\]|]+)(?:\|[^\]]*)?\]\]|(?<=^|\s)#([\p{L}\p{N}_-]+)',
  unicode: true,
);

List<MdInline> parseInline(String text) {
  final out = <MdInline>[];
  var last = 0;
  for (final m in _inline.allMatches(text)) {
    if (m.start > last) out.add(MdInline(InlineKind.text, text.substring(last, m.start)));
    if (m.group(1) != null) {
      out.add(MdInline(InlineKind.bold, m.group(1)!));
    } else if (m.group(2) != null) {
      out.add(MdInline(InlineKind.italic, m.group(2)!));
    } else if (m.group(3) != null) {
      out.add(MdInline(InlineKind.code, m.group(3)!));
    } else if (m.group(4) != null) {
      out.add(MdInline(InlineKind.math, m.group(4)!.trim()));
    } else if (m.group(5) != null) {
      out.add(MdInline(InlineKind.link, m.group(5)!.trim()));
    } else {
      out.add(MdInline(InlineKind.tag, m.group(6)!));
    }
    last = m.end;
  }
  if (last < text.length) out.add(MdInline(InlineKind.text, text.substring(last)));
  return out;
}

/// Splits [text] into plain / highlighted spans wherever one of [terms] occurs (case-insensitive).
List<TextSpan> highlightSpans(String text, List<String> terms, TextStyle mark, [TextStyle? style]) {
  final ts = terms.where((x) => x.isNotEmpty).toList()..sort((a, b) => b.length.compareTo(a.length));
  if (ts.isEmpty) return [TextSpan(text: text, style: style)];
  final lower = text.toLowerCase();
  final out = <TextSpan>[];
  var i = 0;
  while (i < text.length) {
    var hit = 0;
    for (final term in ts) {
      if (lower.startsWith(term, i)) {
        hit = term.length;
        break;
      }
    }
    if (hit > 0) {
      out.add(TextSpan(text: text.substring(i, i + hit), style: (style ?? const TextStyle()).merge(mark)));
      i += hit;
    } else {
      var j = i + 1;
      while (j < text.length && !ts.any((term) => lower.startsWith(term, j))) {
        j++;
      }
      out.add(TextSpan(text: text.substring(i, j), style: style));
      i = j;
    }
  }
  return out;
}

/// One line of worklog text as rich spans: `code` in a monospace chip, $x^2$ in a serif italic
/// formula style, **bold**, *italic*, [[links]], #tags — and, when [highlight] is given, the query
/// terms marked inside plain and bold runs.
TextSpan inlineSpan(BuildContext context, String text, {TextStyle? base, void Function(String)? onLink, List<String> highlight = const []}) {
  final scheme = Theme.of(context).colorScheme;
  final mono = ZaevisTheme.mono.copyWith(backgroundColor: scheme.surfaceContainerHigh, color: scheme.onSurface, fontSize: (base?.fontSize ?? 14) - 1);
  final math = ZaevisTheme.math.copyWith(color: scheme.onSurface, fontSize: (base?.fontSize ?? 14) + 1);
  final mark = TextStyle(fontWeight: FontWeight.w700, color: scheme.primary);
  return TextSpan(
    style: base,
    children: [
      for (final s in parseInline(text))
        switch (s.kind) {
          InlineKind.text => TextSpan(children: highlightSpans(s.text, highlight, mark)),
          InlineKind.bold => TextSpan(children: highlightSpans(s.text, highlight, mark, const TextStyle(fontWeight: FontWeight.w600))),
          InlineKind.italic => TextSpan(text: s.text, style: const TextStyle(fontStyle: FontStyle.italic)),
          InlineKind.code => TextSpan(text: ' ${s.text} ', style: mono),
          InlineKind.math => TextSpan(text: s.text, style: math),
          InlineKind.tag => TextSpan(text: '#${s.text}', style: TextStyle(color: scheme.tertiary)),
          InlineKind.link => WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: InkWell(
                onTap: onLink == null ? null : () => onLink(s.text),
                child: Text(s.text,
                    style: TextStyle(color: scheme.primary, decoration: TextDecoration.underline)),
              ),
            ),
        },
    ],
  );
}

class _BlockWidget extends StatelessWidget {
  const _BlockWidget(this.block, {this.onLink});
  final MdBlock block;
  final void Function(String)? onLink;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    Widget rich(String s, [TextStyle? st]) => Text.rich(inlineSpan(context, s, base: st, onLink: onLink));

    switch (block.kind) {
      case BlockKind.heading:
        final style = switch (block.level) { 1 => t.headlineSmall, 2 => t.titleLarge, _ => t.titleMedium };
        return Padding(
          padding: EdgeInsets.only(top: block.level == 1 ? 4 : 16, bottom: 8),
          child: rich(block.text, style),
        );
      case BlockKind.code:
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(block.text, style: ZaevisTheme.mono.copyWith(color: scheme.onSurface)),
          ),
        );
      case BlockKind.quote:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: scheme.outlineVariant, width: 3))),
          child: rich(block.text, t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        );
      case BlockKind.bullet:
      case BlockKind.numbered:
      case BlockKind.task:
        final Widget lead = switch (block.kind) {
          BlockKind.task => Icon(block.checked ? Icons.check_box : Icons.check_box_outline_blank, size: 18),
          BlockKind.numbered => Text(block.marker, style: t.bodyMedium),
          _ => const Text('•'),
        };
        return Padding(
          padding: EdgeInsets.only(left: 4.0 + block.level * 20, top: 2, bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 24, child: lead),
              Expanded(child: rich(block.text, t.bodyMedium)),
            ],
          ),
        );
      case BlockKind.paragraph:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: rich(block.text, t.bodyMedium),
        );
    }
  }
}
