import 'package:flutter/material.dart';

import '../models.dart';

/// The order of subscribed CLIs (OpenRouter last, marked as metered) and what each one did:
/// waiting, writing, skipped for quota, or the one that wrote.
class AgentRail extends StatelessWidget {
  const AgentRail({super.key, required this.stops});
  final List<RailStop> stops;

  @override
  Widget build(BuildContext context) {
    if (stops.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final children = <Widget>[];
    for (var i = 0; i < stops.length; i++) {
      final prev = i > 0 ? stops[i - 1] : null;
      if (prev != null && prev.state != 'off' && stops[i].state != 'off') {
        children.add(Icon(Icons.arrow_forward, size: 14, color: scheme.outline));
      }
      children.add(_Stop(stop: stops[i]));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('서비스 순서', style: t.labelSmall?.copyWith(color: scheme.outline)),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: children),
      ]),
    );
  }
}

class _Stop extends StatelessWidget {
  const _Stop({required this.stop});
  final RailStop stop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final (Color bg, Color fg, String label) = switch (stop.state) {
      'running' => (scheme.primary, scheme.onPrimary, '${stop.title} · 작성 중'),
      'wrote' => (scheme.primaryContainer, scheme.onPrimaryContainer, '${stop.title} · 작성'),
      'quota' => (scheme.errorContainer, scheme.onErrorContainer, '${stop.title} · 할당량'),
      'error' => (scheme.errorContainer, scheme.onErrorContainer, '${stop.title} · 실패'),
      'login' => (scheme.errorContainer.withValues(alpha: 0.5), scheme.onErrorContainer, '${stop.title} · 로그인'),
      'off' => (scheme.surfaceContainerHighest, scheme.outline, stop.metered ? '${stop.title} · 사용량' : stop.title),
      _ => (scheme.surfaceContainerHighest, scheme.onSurface, stop.metered ? '${stop.title} · 사용량' : stop.title),
    };
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: t.labelSmall?.copyWith(color: fg)),
    );
    final tip = stop.reason;
    if (tip == null || tip.isEmpty) return Opacity(opacity: stop.state == 'off' ? 0.55 : 1, child: chip);
    return Opacity(
      opacity: stop.state == 'off' ? 0.55 : 1,
      child: Tooltip(message: tip, child: chip),
    );
  }
}
