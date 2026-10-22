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

  void _reload() => setState(() => _future = widget.load());

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

class EmptyPane extends StatelessWidget {
  const EmptyPane(this.message, {super.key, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ]),
        ),
      );
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

/// Reads at most [maxWidth] wide, centred, so long lines stay readable on desktop.
class Readable extends StatelessWidget {
  const Readable({super.key, required this.child, this.maxWidth = 860});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}
