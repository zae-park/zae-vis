import 'package:flutter/material.dart';

import '../api.dart';

/// Loads a value and shows spinner / error-with-retry / content.
class AsyncView<T> extends StatefulWidget {
  const AsyncView({super.key, required this.load, required this.builder});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T value, VoidCallback reload) builder;

  @override
  State<AsyncView<T>> createState() => _AsyncViewState<T>();
}

class _AsyncViewState<T> extends State<AsyncView<T>> {
  late Future<T> _future = widget.load();

  void _reload() => setState(() {
        _future = widget.load(); // block body: an arrow would hand setState the Future
      });

  @override
  void didUpdateWidget(covariant AsyncView<T> old) {
    super.didUpdateWidget(old);
    if (old.load != widget.load) _future = widget.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorPane(error: snap.error!, onRetry: _reload);
        }
        return widget.builder(context, snap.data as T, _reload);
      },
    );
  }
}

class ErrorPane extends StatelessWidget {
  const ErrorPane({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = error is ApiException && (error as ApiException).status == 0;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(offline ? Icons.cloud_off : Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text('$error', textAlign: TextAlign.center),
            if (offline) ...[
              const SizedBox(height: 8),
              Text('server 폴더에서 `npm start`로 서버를 실행했는지 확인하세요.',
                  style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: onRetry, child: const Text('다시 시도')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Empty state: the first line of [message] is the title, the rest is the hint.
class EmptyPane extends StatelessWidget {
  const EmptyPane(this.message, {super.key, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final nl = message.indexOf('\n');
    final title = nl < 0 ? message : message.substring(0, nl);
    final hint = nl < 0 ? null : message.substring(nl + 1).trim();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: Icon(icon, size: 28, color: scheme.primary),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: t.titleMedium),
            if (hint != null && hint.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(hint, textAlign: TextAlign.center, style: t.bodySmall),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Small section label ("매일 수집 · 색인") with an optional trailing widget.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.titleMedium),
            if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, style: t.bodySmall)),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// A bordered panel that groups related rows (settings, lists). Children are divided by hairlines.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.children, this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 4), this.divided = true});
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && divided) rows.add(Divider(color: scheme.outlineVariant));
      rows.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: padding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }
}

/// Colour per log tag, shared by the log list and search.
Color tagColor(ColorScheme s, String tag) => switch (tag) {
      'done' => Colors.green.shade600,
      'decision' => s.primary,
      'blocked' => s.error,
      'learned' => Colors.orange.shade700,
      _ => s.outline,
    };

String tagLabel(String tag) => switch (tag) {
      'done' => '완료',
      'decision' => '결정',
      'blocked' => '막힘',
      'learned' => '배움',
      _ => '#$tag',
    };

/// Fills the window width (with a gutter) so a maximised window is used; a screen that is mostly
/// prose passes [maxWidth] to keep its lines readable. Left-aligned under the page header on wide
/// windows (12px extra gutter), centred when the window is narrow.
class Readable extends StatelessWidget {
  const Readable({super.key, required this.child, this.maxWidth});
  final Widget child;

  /// Cap for text-heavy screens; null = use the whole width minus a right gutter.
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 760;
    return Align(
      alignment: wide ? Alignment.topLeft : Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(left: wide ? 12 : 0, right: wide ? 16 : 0),
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity), child: child),
      ),
    );
  }
}
