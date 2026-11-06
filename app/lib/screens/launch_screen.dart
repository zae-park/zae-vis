import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n/l10n.dart';
import '../models.dart';

/// On a cold start of the installed app the server collects, indexes and runs the daily digest once
/// (POST /api/launch). This gate shows that as a splash over [child] (the home shell) and opens the
/// home when it is over. "바로 열기" opens it at once: the panel flies up into a small pill at the top
/// that keeps the progress (tap it for the steps) and fades out a few seconds after the run ends.
class LaunchGate extends StatefulWidget {
  const LaunchGate({
    super.key,
    required this.api,
    required this.child,
    this.enabled = true,
    this.poll = const Duration(seconds: 1),
    this.linger = const Duration(seconds: 4),
  });
  final WorklogApi api;
  final Widget child;

  /// false: straight to [child] (right after the first-run wizard, which has just collected).
  final bool enabled;
  final Duration poll;

  /// How long the finished pill stays before it fades out.
  final Duration linger;

  @override
  State<LaunchGate> createState() => _LaunchGateState();
}

enum _Mode { splash, background, leaving, gone }

const _fly = Duration(milliseconds: 450);

class _LaunchGateState extends State<LaunchGate> {
  late _Mode _mode = widget.enabled ? _Mode.splash : _Mode.gone;
  LaunchStatus? _status;
  Timer? _timer;
  Timer? _linger;
  bool _expanded = false;

  // A digest started later from this app (a button, the chat) gets the same pill at the top.
  DigestStatus? _digest;
  Timer? _watchTimer;
  Timer? _watchLinger;
  bool _watchShown = false;

  @override
  void initState() {
    super.initState();
    widget.api.digestStarted.addListener(_onDigestStarted);
    if (_mode != _Mode.gone) {
      _start();
    } else {
      _pollDigest(onlyIfRunning: true); // e.g. the wizard's first digest is already going
    }
  }

  void _onDigestStarted() {
    if (_mode != _Mode.gone || !mounted) return; // the launch pill is showing its own digest
    _watchLinger?.cancel();
    _watchLinger = null;
    _watchTimer?.cancel();
    setState(() => _watchShown = true);
    _pollDigest();
  }

  Future<void> _pollDigest({bool onlyIfRunning = false}) async {
    try {
      final d = await widget.api.digest();
      if (!mounted) return;
      if (onlyIfRunning && !d.running) return;
      setState(() {
        _digest = d;
        _watchShown = true;
      });
      if (d.running) {
        _watchTimer ??= Timer.periodic(widget.poll * 2, (_) => _pollDigest());
      } else {
        _watchTimer?.cancel();
        _watchTimer = null;
        _watchLinger ??= Timer(widget.linger, () {
          if (mounted) setState(() => _watchShown = false);
        });
      }
    } catch (_) {
      _watchTimer?.cancel();
      _watchTimer = null;
      if (mounted && !onlyIfRunning) setState(() => _watchShown = false);
    }
  }

  Future<void> _start() async {
    try {
      await widget.api.startLaunch();
    } catch (_) {
      return _leave(); // an older server, or none: open the app as before
    }
    await _refresh();
    if (_mode == _Mode.splash || _mode == _Mode.background) _timer = Timer.periodic(widget.poll, (_) => _refresh());
  }

  Future<void> _refresh() async {
    if (!mounted || _mode == _Mode.leaving || _mode == _Mode.gone) return;
    try {
      final s = await widget.api.launchStatus();
      if (!mounted) return;
      setState(() => _status = s);
      if (!s.done) return;
      _timer?.cancel();
      if (_mode == _Mode.splash) {
        _leave();
      } else {
        _linger ??= Timer(widget.linger, _leave);
      }
    } catch (_) {
      _leave();
    }
  }

  /// "바로 열기": the home comes up and the panel becomes the pill at the top.
  void _background() {
    if (_mode != _Mode.splash) return;
    setState(() => _mode = _Mode.background);
    if (_status?.done ?? false) _linger ??= Timer(widget.linger, _leave);
  }

  /// Fade the overlay away, then drop it.
  void _leave() {
    if (!mounted || _mode == _Mode.leaving || _mode == _Mode.gone) return;
    _timer?.cancel();
    _linger?.cancel();
    setState(() => _mode = _Mode.leaving);
  }

  @override
  void dispose() {
    widget.api.digestStarted.removeListener(_onDigestStarted);
    _timer?.cancel();
    _linger?.cancel();
    _watchTimer?.cancel();
    _watchLinger?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final splash = _mode == _Mode.splash;
    return Stack(children: [
      // the home is built once the splash is out of the way, and kept (keyed) from then on
      if (!splash) KeyedSubtree(key: const ValueKey('launch-child'), child: widget.child),
      if (_mode != _Mode.gone) ...[
        IgnorePointer(
          key: const ValueKey('launch-scrim'),
          ignoring: !splash,
          child: AnimatedOpacity(
            opacity: splash ? 1 : 0,
            duration: _fly,
            curve: Curves.easeOut,
            child: Material(color: Theme.of(context).scaffoldBackgroundColor, child: const SizedBox.expand()),
          ),
        ),
        AnimatedOpacity(
          key: const ValueKey('launch-panel'),
          opacity: _mode == _Mode.leaving ? 0 : 1,
          duration: _fly,
          onEnd: () {
            if (_mode == _Mode.leaving && mounted) setState(() => _mode = _Mode.gone);
          },
          child: AnimatedAlign(
            alignment: splash ? Alignment.center : Alignment.topCenter,
            duration: _fly,
            curve: Curves.easeInOutCubic,
            child: Padding(
              padding: EdgeInsets.only(top: splash ? 0 : 10),
              child: IgnorePointer(ignoring: _mode == _Mode.leaving, child: _panel(context, splash)),
            ),
          ),
        ),
      ],
      if (_mode == _Mode.gone)
        Align(
          key: const ValueKey('digest-watch'),
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween(begin: const Offset(0, -0.6), end: Offset.zero).animate(a), child: child),
              ),
              child: _watchShown && _digest != null
                  ? DecoratedBox(
                      key: const ValueKey('digest-pill'),
                      decoration: _pillDecoration(Theme.of(context).colorScheme),
                      child: Material(type: MaterialType.transparency, child: _DigestPill(status: _digest!)),
                    )
                  : const SizedBox.shrink(key: ValueKey('digest-none')),
            ),
          ),
        ),
    ]);
  }

  Widget _panel(BuildContext context, bool splash) {
    final cs = Theme.of(context).colorScheme;
    final Widget content = splash
        ? _SplashPanel(key: const ValueKey('splash'), status: _status, onOpenNow: _background)
        : _expanded
            ? _StepsCard(key: const ValueKey('steps'), status: _status, onCollapse: () => setState(() => _expanded = false))
            : _Pill(key: const ValueKey('pill'), status: _status, onTap: () => setState(() => _expanded = true));
    return AnimatedContainer(
      duration: _fly,
      curve: Curves.easeInOutCubic,
      decoration: splash
          ? BoxDecoration(color: Colors.transparent, borderRadius: BorderRadius.zero, border: Border.all(color: Colors.transparent), boxShadow: const [])
          : _pillDecoration(cs),
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedSize(
          duration: _fly,
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, if (current != null) current]),
            child: content,
          ),
        ),
      ),
    );
  }
}

BoxDecoration _pillDecoration(ColorScheme cs) => BoxDecoration(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: cs.outlineVariant),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 4))],
    );

String _firstLine(String text) => text.split('\n').map((l) => l.trim()).firstWhere((l) => l.isNotEmpty, orElse: () => '');

/// "1분 12초" / "42초".
String _duration(BuildContext context, Duration d) {
  final l = context.l10n;
  final s = d.inSeconds;
  return s >= 60 ? l.launchMinutes(s ~/ 60, s % 60) : l.launchSeconds(s);
}

String _stepTitle(BuildContext context, String name) => switch (name) {
      'collect' => context.l10n.launchCollect,
      'index' => context.l10n.launchIndex,
      _ => context.l10n.launchDigest,
    };

class _SplashPanel extends StatelessWidget {
  const _SplashPanel({super.key, required this.status, required this.onOpenNow});
  final LaunchStatus? status;
  final VoidCallback onOpenNow;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final digestRunning = status?.step('digest')?.running ?? false;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('zaevis', style: t.headlineSmall?.copyWith(letterSpacing: -0.4)),
            const SizedBox(height: 6),
            Text(l.launchTitle, style: t.bodyMedium?.copyWith(color: muted)),
            const SizedBox(height: 24),
            _Steps(status: status),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: Text(digestRunning ? l.launchSkipDigestNote : l.launchSkipNote, style: t.bodySmall?.copyWith(color: muted))),
              const SizedBox(width: 12),
              TextButton(key: const ValueKey('launch-open-now'), onPressed: onOpenNow, child: Text(l.launchOpenNow)),
            ]),
          ],
        ),
      ),
    );
  }
}

/// The small progress at the top after "바로 열기": the step running and the time so far.
class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.status, required this.onTap});
  final LaunchStatus? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = status;
    final done = s?.done ?? false;
    final failed = s?.steps.any((x) => x.state == 'failed') ?? false;
    final digest = s?.step('digest');
    final String label;
    if (done) {
      final note = digest?.state == 'done' ? digest?.note : null;
      label = note == null ? l.launchPillDone : l.launchPillDoneWith(note);
    } else {
      final cur = s?.current;
      final since = s?.startedAt;
      final elapsed = since == null ? '' : ' · ${_duration(context, DateTime.now().difference(since))}';
      label = '${l.launchPillRunning(_stepTitle(context, cur?.name ?? 'collect'))}$elapsed';
    }
    return _PillBody(key: const ValueKey('launch-pill'), label: label, done: done, failed: failed, onTap: onTap);
  }
}

/// A digest started from the app after the launch: its scope and time so far, then how it ended.
class _DigestPill extends StatelessWidget {
  const _DigestPill({required this.status});
  final DigestStatus status;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final d = status;
    if (d.running) {
      final since = d.startedAt;
      final elapsed = since == null ? '' : ' · ${_duration(context, DateTime.now().difference(since))}';
      return _PillBody(label: '${l.launchPillRunning(d.runningWeekly ? l.launchWeekly : l.launchDigest)}$elapsed', done: false, failed: false);
    }
    final last = d.last;
    final note = last == null ? '' : _firstLine(last.report);
    final failed = last != null && !last.ok;
    final label = note.isEmpty ? l.launchPillDone : failed ? l.launchPillFailedWith(note) : l.launchPillDoneWith(note);
    return _PillBody(label: label, done: true, failed: failed);
  }
}

class _PillBody extends StatelessWidget {
  const _PillBody({super.key, required this.label, required this.done, required this.failed, this.onTap});
  final String label;
  final bool done;
  final bool failed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (done)
            Icon(failed ? Icons.error_outline : Icons.check_circle, size: 16, color: failed ? cs.error : cs.primary)
          else
            const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Icon(Icons.expand_more, size: 16, color: cs.onSurfaceVariant),
          ],
        ]),
      ),
    );
  }
}

/// The pill opened: the three steps, and a way back to the pill.
class _StepsCard extends StatelessWidget {
  const _StepsCard({super.key, required this.status, required this.onCollapse});
  final LaunchStatus? status;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SizedBox(
      width: 380,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(l.launchTitle, style: Theme.of(context).textTheme.titleSmall)),
            IconButton(key: const ValueKey('launch-collapse'), tooltip: l.launchCollapse, icon: const Icon(Icons.expand_less), onPressed: onCollapse),
          ]),
          Padding(padding: const EdgeInsets.only(right: 8), child: _Steps(status: status)),
        ]),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.status});
  final LaunchStatus? status;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _StepRow(step: status?.step('collect'), title: l.launchCollect, typical: l.launchCollectTypical),
      _StepRow(step: status?.step('index'), title: l.launchIndex, typical: l.launchIndexTypical),
      _StepRow(step: status?.step('digest'), title: l.launchDigest, typical: l.launchDigestTypical),
    ]);
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.title, required this.typical});
  final LaunchStep? step;
  final String title;
  final String typical;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final st = step?.state ?? 'pending';
    final Widget icon = switch (st) {
      'running' => const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      'done' => Icon(Icons.check_circle, size: 20, color: cs.primary),
      'failed' => Icon(Icons.error_outline, size: 20, color: cs.error),
      'skipped' => Icon(Icons.remove_circle_outline, size: 20, color: cs.outline),
      _ => Icon(Icons.radio_button_unchecked, size: 20, color: cs.outlineVariant),
    };
    final elapsed = step?.elapsed(DateTime.now());
    final detail = switch (st) {
      'pending' || 'running' => step?.note ?? typical,
      'skipped' => step?.note ?? l.launchSkipped,
      _ => step?.note ?? '',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 24, child: Padding(padding: const EdgeInsets.only(top: 1), child: icon)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.bodyLarge?.copyWith(color: st == 'pending' ? cs.onSurfaceVariant : null)),
            if (detail.isNotEmpty)
              Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: st == 'failed' ? cs.error : cs.onSurfaceVariant)),
          ]),
        ),
        if (elapsed != null && st != 'skipped')
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 2),
            child: Text(_duration(context, elapsed), style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
          ),
      ]),
    );
  }
}
