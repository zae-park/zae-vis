import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../api.dart';
import '../backend/backend.dart';
import '../l10n/l10n.dart';
import '../models.dart';
import '../recording_trail.dart';
import '../widgets/task_dialog.dart';
import '../widgets/common.dart';
import '../recording/recorder.dart';
import '../widgets/input_dialogs.dart';
import '../widgets/record_dialog.dart';
import '../widgets/recording_trail_strip.dart';
import 'file_screen.dart';

String _ago(AppLocalizations l, DateTime? t) {
  if (t == null) return l.collectNeverCollected;
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return l.collectJustNow;
  if (d.inHours < 1) return l.collectMinutesAgo(d.inMinutes);
  if (d.inDays < 1) return l.collectHoursAgo(d.inHours);
  return l.collectDaysAgo(d.inDays);
}

String _size(int b) => b >= 1 << 20 ? '${(b / (1 << 20)).toStringAsFixed(1)}MB' : '${(b / 1024).ceil()}KB';

/// Data sources (batch) + inbox and real-time input.
enum _ConnectPane { now, daily, outside }

class CollectScreen extends StatefulWidget {
  const CollectScreen({super.key, required this.api, this.recorder, this.backend});
  final WorklogApi api;
  final Recorder? recorder;

  /// The bundled server manager; lets a card install a connector's CLI with one click. Null on the web.
  final Backend? backend;

  @override
  State<CollectScreen> createState() => _CollectScreenState();
}

class _CollectScreenState extends State<CollectScreen> {
  SourcesState? _sources;
  Inbox? _inbox;
  IndexStatus? _index;
  DatasourcesState? _external;
  Object? _error;
  Timer? _poll;
  _ConnectPane _pane = _ConnectPane.now;

  /// Connector just added from the dialog: its card opens so the first collect's result is visible.
  String? _justAdded;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await widget.api.sources();
      final i = await widget.api.inbox();
      final x = await widget.api.datasources();
      IndexStatus? index;
      try {
        index = await widget.api.indexStatus();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _sources = s;
        _inbox = i;
        _index = index;
        _external = x;
        _error = null;
      });
      _poll?.cancel();
      if (s.collecting || i.transcribing || x.syncing) _poll = Timer(Duration(seconds: s.collecting ? 1 : 3), _load);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _cancelTranscription(String file) async {
    try {
      await widget.api.cancelTranscription(file);
      if (mounted) toast(context, context.l10n.collectTranscriptionCancelled);
    } on ApiException catch (e) {
      if (e.status != 404 && mounted) toast(context, e.message, error: true);
    }
    await _load();
  }

  Future<void> _act(Future<void> Function() f, {String? done}) async {
    try {
      await f();
      if (mounted && done != null) toast(context, done);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    await _load();
  }

  /// zsh only keeps a time per command with EXTENDED_HISTORY. This edits the user's own ~/.zshrc,
  /// so it asks first; returns the note the card shows afterwards, or null when cancelled.
  Future<String?> _enableTimestamps() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.collectTimestampsTitle),
        content: Text(context.l10n.collectTimestampsBody('\$ZDOTDIR', 'setopt EXTENDED_HISTORY  # zaevis')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.l10n.commonAdd)),
        ],
      ),
    );
    if (ok != true || !mounted) return null;
    final l = context.l10n;
    try {
      final r = await widget.api.enableShellTimestamps();
      final note = r.changed ? l.collectTimestampsAdded(r.file) : l.collectTimestampsAlready(r.file);
      if (mounted) toast(context, note);
      return note;
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorPane(error: _error!, onRetry: _load);
    final s = _sources;
    final inbox = _inbox;
    if (s == null || inbox == null) return const Center(child: CircularProgressIndicator());

    final l = context.l10n;
    final trails = recordingTrails(inbox: inbox, index: _index, collectLine: s.progress?.currentLine);
    return Readable(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        RecordingTrailStrip(
          items: trails,
          onOpen: (item) {
            if (item.watch) {
              showRecordDialog(context, widget.api, recorder: widget.recorder, watch: item.file);
              return;
            }
            final path = item.openPath;
            if (path != null) FileScreen.open(context, widget.api, path);
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<_ConnectPane>(
              segments: [
                ButtonSegment(value: _ConnectPane.now, label: Text(l.collectPaneNow), icon: const Icon(Icons.inbox_outlined, size: 18)),
                ButtonSegment(value: _ConnectPane.daily, label: Text(l.collectPaneDaily), icon: const Icon(Icons.event_repeat, size: 18)),
                ButtonSegment(value: _ConnectPane.outside, label: Text(l.collectPaneOutside), icon: const Icon(Icons.hub_outlined, size: 18)),
              ],
              selected: {_pane},
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              onSelectionChanged: (v) => setState(() => _pane = v.first),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
          if (_pane == _ConnectPane.now) ...[
          // ── real-time input ─────────────────────────────────────────────
          SectionHeader(l.collectQuickTitle, subtitle: l.collectQuickHint),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: () async {
                if (await showAddLogDialog(context, widget.api) && context.mounted) toast(context, l.collectAddedToLog);
              },
              icon: const Icon(Icons.edit_note),
              label: Text(l.collectOneLine),
            ),
            FilledButton.tonalIcon(
              onPressed: () async {
                final f = await showPasteTranscriptDialog(context, widget.api);
                if (f != null && context.mounted) toast(context, l.collectSavedToInbox(f));
                await _load();
              },
              icon: const Icon(Icons.content_paste),
              label: Text(l.collectPasteTranscript),
            ),
            FilledButton.tonalIcon(
              onPressed: () async {
                await recordAndNotify(context, widget.api, recorder: widget.recorder);
                await _load();
              },
              icon: const Icon(Icons.mic),
              label: Text(l.collectRecord),
            ),
            FilledButton.tonalIcon(
              onPressed: () async {
                final n = await pickAndUploadAudio(context, widget.api);
                if (n > 0 && context.mounted) toast(context, l.collectQueuedRecordings(n));
                await _load();
              },
              icon: const Icon(Icons.mic_none),
              label: Text(l.collectUploadRecordings),
            ),
          ]),
          const SizedBox(height: 16),
          _InboxCard(inbox: inbox, onCancel: _cancelTranscription),
          ],
          if (_pane == _ConnectPane.daily) ...[
          const SizedBox(height: 8),

          // ── batch sources ────────────────────────────────────────────────
          SectionHeader(
            l.collectSourcesTitle,
            subtitle: l.collectSourcesHint,
            trailing: FilledButton.icon(
              onPressed: s.collecting ? null : () => _act(() => widget.api.collect(), done: l.collectStarted),
              icon: s.collecting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync),
              label: Text(s.collecting ? l.collectCollecting : l.collectNow),
            ),
          ),
          if (s.collecting) _CollectLive(progress: s.progress, onCancel: _cancelTranscription),
          if (s.lastCollectError != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(s.lastCollectError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 8),
          for (final src in s.sources)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SourceCard(
                key: ValueKey(src.name),
                source: src,
                busy: s.collecting,
                live: s.progress?.steps.where((e) => e.name == src.name && e.state == 'running').map((e) => e.line ?? l.collectSourceCollecting(src.title)).firstOrNull,
                initiallyExpanded: src.name == _justAdded,
                onToggle: (on) => _act(() => widget.api.setSourceEnabled(src.name, on)),
                onCollect: () => _act(() => widget.api.collect(only: [src.name]), done: l.collectSourceStarted(src.title)),
                onSave: (settings) => _act(() => widget.api.saveSourceSettings(src.name, settings), done: l.commonSaved),
                onRemove: src.builtin ? null : () => _act(() => widget.api.removeSource(src.name), done: l.collectDeleted),
                onEnableTimestamps: src.name == 'shell-history' ? _enableTimestamps : null,
              ),
            ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () async {
              final name = await showAddSourceDialog(context, widget.api);
              if (name == null) return;
              setState(() {
                _justAdded = name;
                _pane = _ConnectPane.daily;
              });
              // collect right away so the user sees whether the command works, on the card below
              await _act(() => widget.api.collect(only: [name]), done: l.collectConnectorAdded(name));
            },
            icon: const Icon(Icons.add),
            label: Text(l.collectAddConnector),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(l.collectAnyCommand,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          ],

          // ── external AutoRAG datasources ─────────────────────────────────
          if (_pane == _ConnectPane.outside && _external != null && _external!.datasources.isNotEmpty) ...[
            const SizedBox(height: 28),
            SectionHeader(
              l.collectExternalTitle,
              subtitle: l.collectExternalHint,
              trailing: _external!.syncing
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 8),
                      Text(l.collectSyncing),
                    ])
                  : null,
            ),
            const SizedBox(height: 8),
            for (final d in _external!.datasources)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ExternalCard(
                  key: ValueKey('ext-${d.name}'),
                  source: d,
                  syncing: _external!.syncing,
                  onInstall: widget.backend?.managed == true && d.installKind != null && d.cliBin != null
                      ? () async {
                          final ok = await runBackendTask(context, widget.backend!, l.collectInstallTask(d.title, d.cliBin!), ['ext', 'install', d.cliBin!]);
                          if (ok && context.mounted) toast(context, l.collectInstalled(d.cliBin!));
                          await _load();
                        }
                      : null,
                  onToggle: (on) => _act(() => widget.api.saveDatasource(d.name, enabled: on), done: on ? l.collectExtOn(d.title) : l.collectExtOff(d.title)),
                  onSave: (connector, note, secrets) => _act(() => widget.api.saveDatasource(d.name, enabled: true, connector: connector, description: note, secrets: secrets),
                      done: d.configured ? l.collectSavedSyncing : l.collectExtConnected(d.title)),
                  onSync: () => _act(() => widget.api.syncDatasources(d.name), done: l.collectExtSyncStarted),
                  onRemove: () => _act(() => widget.api.removeDatasource(d.name), done: l.collectExtRemoved(d.title)),
                ),
              ),
            ],
          if (_pane == _ConnectPane.outside && (_external == null || _external!.datasources.isEmpty))
            Text(l.collectNoExternal, style: Theme.of(context).textTheme.bodySmall),
        ]),
          ),
        ),
      ]),
    );
  }
}

class _InboxCard extends StatelessWidget {
  const _InboxCard({required this.inbox, this.onCancel});
  final Inbox inbox;
  final void Function(String file)? onCancel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    Widget group(String title, List<InboxFile> files) => ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('$title (${files.length})', style: t.titleSmall),
          children: [
            if (files.isEmpty) Align(alignment: Alignment.centerLeft, child: Text(l.commonNone, style: t.bodySmall)),
            for (final f in files.take(20))
              ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(f.name), trailing: Text(_size(f.size), style: t.bodySmall)),
          ],
        );
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.collectInboxTitle, style: t.labelLarge)),
          for (final j in inbox.jobs.take(5))
            ListTile(
              dense: true,
              isThreeLine: j.state == 'running',
              contentPadding: EdgeInsets.zero,
              leading: switch (j.state) {
                'running' => const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                'failed' => Icon(Icons.error_outline, color: scheme.error),
                'done' => const Icon(Icons.check_circle_outline),
                'cancelled' => const Icon(Icons.stop_circle_outlined),
                _ => const Icon(Icons.schedule),
              },
              title: Text(j.file),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  j.error ?? j.line ?? j.result ?? switch (j.state) {
                    'queued' => l.collectTranscribeQueued,
                    'cancelled' => l.collectCancelled,
                    _ => l.collectTranscribing,
                  },
                  maxLines: 2,
                ),
                if (j.state == 'running') ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: j.fraction, minHeight: 4, borderRadius: BorderRadius.circular(2)),
                ],
              ]),
              trailing: (j.state == 'queued' || j.state == 'running') && onCancel != null
                  ? TextButton(onPressed: () => onCancel!(j.file), child: Text(l.commonCancel))
                  : null,
            ),
          group(l.collectTranscripts, inbox.transcripts),
          group(l.collectPendingAudio, inbox.audio),
          group(l.collectSessionNotes, inbox.sessions),
        ]),
      ),
    );
  }
}

/// Which source is running, how long it has been, and whether the server is still answering.
class _CollectLive extends StatefulWidget {
  const _CollectLive({required this.progress, this.onCancel});
  final CollectProgress? progress;
  final void Function(String file)? onCancel;

  @override
  State<_CollectLive> createState() => _CollectLiveState();
}

class _CollectLiveState extends State<_CollectLive> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  String? _runningFile(CollectProgress? p) {
    final line = p?.currentLine;
    if (line == null || !line.startsWith('전사 ')) return null;
    final parts = line.split(' · ');
    if (parts.length < 2) return null;
    final name = parts[1].trim();
    return name.isEmpty ? null : name;
  }

  String _span(AppLocalizations l, Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m >= 60) return l.collectSpanHourMin(m ~/ 60, m % 60);
    if (m >= 1) return l.collectSpanMinSec(m, s);
    return l.collectSpanSec(s);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    final p = widget.progress;
    final now = DateTime.now();
    if (p == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(l.collectStartedChecking, style: t.bodySmall),
      );
    }
    final beatAge = now.difference(p.beat);
    final quietAge = now.difference(p.outputAt);
    final stale = beatAge > const Duration(seconds: 20);
    final quiet = !stale && quietAge > const Duration(seconds: 20);
    final headline = stale
        ? l.collectNoResponse(_span(l, beatAge))
        : quiet
            ? l.collectQuiet(_span(l, quietAge), _span(l, now.difference(p.startedAt)))
            : l.collectRunning(_span(l, now.difference(p.startedAt)));
    final note = stale
        ? l.collectStaleNote
        : quiet
            ? l.collectQuietNote
            : '';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(headline, style: t.titleSmall?.copyWith(color: stale ? scheme.error : null)),
        if (p.fraction != null || (p.currentLine?.startsWith('전사 ') ?? false)) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(value: p.fraction, minHeight: 6, borderRadius: BorderRadius.circular(3)),
        ],
        if (p.currentLine != null) Text(p.currentLine!, style: t.bodySmall),
        if (_runningFile(p) case final file?)
          if (widget.onCancel != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => widget.onCancel!(file), child: Text(l.collectCancelTranscription)),
            ),
        if (note.isNotEmpty) Text(note, style: t.bodySmall),
        const SizedBox(height: 6),
        for (final step in p.steps)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(children: [
              Icon(
                switch (step.state) {
                  'done' => Icons.check_circle_outline,
                  'failed' => Icons.error_outline,
                  'running' => Icons.timelapse,
                  _ => Icons.radio_button_unchecked,
                },
                size: 16,
                color: step.state == 'failed' ? scheme.error : (step.state == 'running' ? scheme.primary : scheme.outline),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [
                    step.title,
                    if (step.state == 'running' && step.since != null) _span(l, now.difference(step.since!)),
                    if (step.state == 'running' && step.line != null) step.line!,
                  ].join(' · '),
                  style: t.bodySmall?.copyWith(color: step.state == 'running' ? scheme.primary : null),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _SourceCard extends StatefulWidget {
  const _SourceCard({super.key, required this.source, required this.busy, required this.onToggle, required this.onCollect, required this.onSave, this.live, this.onRemove, this.onEnableTimestamps, this.initiallyExpanded = false});
  final SourceInfo source;
  final bool busy;
  /// The line of the step running now, when this card is the current one.
  final String? live;
  final bool initiallyExpanded;
  final void Function(bool) onToggle;
  final VoidCallback onCollect;
  final void Function(Map<String, Object?>) onSave;
  final VoidCallback? onRemove;

  /// shell-history only: turns zsh timestamps on (after confirming) and resolves to the note to show.
  final Future<String?> Function()? onEnableTimestamps;

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  final Map<String, TextEditingController> _fields = {};
  String? _timestampsNote;

  TextEditingController _field(SourceOption o) =>
      _fields.putIfAbsent(o.key, () => TextEditingController(text: widget.source.optionText(o)));

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// bool options are kept here (they have no text controller); absent = on, the server's default.
  late final Map<String, bool> _bools = {
    for (final o in widget.source.options)
      if (o.kind == 'bool') o.key: widget.source.settings[o.key] != false,
  };

  Map<String, Object?> _values() => {
        for (final o in widget.source.options)
          o.key: switch (o.kind) {
            'bool' => _bools[o.key] ?? true,
            'paths' => _field(o).text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList(),
            'number' => num.tryParse(_field(o).text.trim()),
            _ => _field(o).text.trim(),
          },
      };

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    final status = widget.live ?? (s.lastOk == false ? (s.lastError ?? l.commonFailed) : [_ago(l, s.lastRun), if (s.lastNote != null) s.lastNote!].join(' · '));
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: widget.initiallyExpanded,
        leading: Row(mainAxisSize: MainAxisSize.min, children: [
          SourceIcon(s.name, dim: !s.enabled),
          const SizedBox(width: 8),
          Switch(value: s.enabled, onChanged: widget.onToggle),
        ]),
        title: Text(s.title, style: t.titleSmall),
        subtitle: Text(status, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: widget.live != null ? scheme.primary : (s.lastOk == false ? scheme.error : null))),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.description, style: t.bodySmall),
          const SizedBox(height: 8),
          if (widget.onEnableTimestamps != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 6, children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final note = await widget.onEnableTimestamps!();
                    if (note != null && mounted) setState(() => _timestampsNote = note);
                  },
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(l.collectTimestampsOn),
                ),
                Text(_timestampsNote ?? l.collectTimestampsHint, style: t.bodySmall?.copyWith(color: _timestampsNote == null ? null : scheme.primary)),
              ]),
            ),
          for (final o in s.options)
            if (o.kind == 'bool')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(o.label),
                subtitle: o.help == null ? null : Text(o.help!, style: t.bodySmall),
                value: _bools[o.key] ?? true,
                onChanged: (v) => setState(() => _bools[o.key] = v),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _field(o),
                  minLines: o.kind == 'paths' ? 2 : 1,
                  maxLines: o.kind == 'paths' ? 5 : 1,
                  keyboardType: o.kind == 'number' ? TextInputType.number : null,
                  decoration: InputDecoration(labelText: o.label, helperText: o.help ?? (o.kind == 'paths' ? l.collectOnePerLine : null), isDense: true),
                ),
              ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            FilledButton(onPressed: () => widget.onSave(_values()), child: Text(l.commonSave)),
            OutlinedButton(onPressed: widget.busy || !s.enabled ? null : widget.onCollect, child: Text(l.collectOnlyThis)),
            if (widget.onRemove != null)
              TextButton(onPressed: widget.onRemove, child: Text(l.commonDelete, style: TextStyle(color: scheme.error))),
          ]),
        ],
      ),
    );
  }
}

/// One AutoRAG datasource template: install hint when its CLI is missing, a connect form otherwise,
/// and on/off · sync · delete once connected.
class _ExternalCard extends StatefulWidget {
  const _ExternalCard({super.key, required this.source, required this.syncing, required this.onToggle, required this.onSave, required this.onSync, required this.onRemove, this.onInstall});
  final ExternalDatasource source;
  final bool syncing;
  final void Function(bool) onToggle;
  final void Function(Map<String, Object?> connector, String note, Map<String, String> secrets) onSave;

  /// One-click install of the connector's CLI (null on the web or when only a terminal can do it).
  final Future<void> Function()? onInstall;
  final VoidCallback onSync;
  final VoidCallback onRemove;

  @override
  State<_ExternalCard> createState() => _ExternalCardState();
}

class _ExternalCardState extends State<_ExternalCard> {
  final Map<String, TextEditingController> _fields = {};
  /// Token values typed for `env` fields, by field key; sent once and never shown again.
  final Map<String, TextEditingController> _tokens = {};
  late final TextEditingController _note = TextEditingController(text: widget.source.note ?? '');

  TextEditingController _field(DatasourceField f) => _fields.putIfAbsent(f.key, () => TextEditingController(text: widget.source.fieldText(f)));

  @override
  void dispose() {
    for (final c in [..._fields.values, ..._tokens.values]) {
      c.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  TextEditingController _token(DatasourceField f) => _tokens.putIfAbsent(f.key, TextEditingController.new);

  /// env-var name → token value, for every env field where the user typed one.
  Map<String, String> _secrets() => {
        for (final f in widget.source.fields)
          if (f.kind == 'env' && _token(f).text.trim().isNotEmpty && (_field(f).text.trim().isNotEmpty || f.defaultValue != null))
            (_field(f).text.trim().isEmpty ? f.defaultValue! : _field(f).text.trim()): _token(f).text.trim(),
      };

  Map<String, Object?> _connector() => {
        for (final f in widget.source.fields)
          f.key: f.kind == 'list' ? _field(f).text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList() : _field(f).text.trim(),
      };

  String _envName(DatasourceField f) => _field(f).text.trim().isEmpty ? (f.defaultValue ?? '') : _field(f).text.trim();

  String _envStatus(AppLocalizations l, ExternalDatasource d, DatasourceField f) {
    final e = d.env.where((x) => x.name == _envName(f)).firstOrNull;
    if (e == null) return l.collectEnvNone;
    if (e.stored) return l.collectEnvStored;
    return e.set ? l.collectEnvInServer : l.collectEnvNone;
  }

  String _status(AppLocalizations l, ExternalDatasource d) {
    if (d.unavailable != null) return d.unavailable!;
    if (d.needsInstall) return l.collectNotInstalled('${d.cliBin}');
    if (!d.configured) return l.collectNotConnected;
    if (!d.enabled) return l.collectOff;
    if (d.lastOk == false) return d.lastError ?? l.collectSyncFailed;
    final parts = <String>[l.collectConnected];
    if (d.lastSync != null) parts.add(l.collectSyncedAgo(_ago(l, d.lastSync)));
    if (d.chunks != null) parts.add(l.collectChunks(d.chunks!));
    if (d.autoragStatus == null && d.lastSync == null) parts.add(l.collectNeverSynced);
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.source;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    final failed = d.lastOk == false && d.enabled;
    final mono = TextStyle(fontFamily: 'monospace', fontSize: 13, color: scheme.onSurface);
    final Widget leading = Row(mainAxisSize: MainAxisSize.min, children: [
      SourceIcon(d.template, dim: d.configured && !d.enabled),
      const SizedBox(width: 8),
      if (d.configured)
        Switch(value: d.enabled, onChanged: d.unavailable != null ? null : widget.onToggle)
      else
        Icon(d.unavailable != null ? Icons.block : d.needsInstall ? Icons.download_outlined : Icons.add_link, color: scheme.outline),
    ]);
    return Card.outlined(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: leading,
        title: Text(d.title, style: t.titleSmall),
        subtitle: Text(_status(l, d), maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: failed ? scheme.error : null)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.description, style: t.bodySmall),
          if (d.external != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(l.collectOutbound('${d.external}'), style: t.bodySmall?.copyWith(color: scheme.outline))),
          if (d.auth != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(l.collectAuth('${d.auth}'), style: t.bodySmall?.copyWith(color: scheme.outline))),
          if (d.needsInstall) ...[
            const SizedBox(height: 10),
            if (widget.onInstall != null) ...[
              Text(l.collectNeedsTool('${d.cliBin}'), style: t.bodySmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                FilledButton.icon(onPressed: widget.onInstall, icon: const Icon(Icons.download, size: 18), label: Text(l.collectInstallBin('${d.cliBin}'))),
                Text(d.install ?? '', style: mono.copyWith(fontSize: 11.5, color: scheme.outline)),
              ]),
            ] else ...[
              Text(l.collectInstallFirst, style: t.bodySmall),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
                child: SelectableText(d.install ?? '', style: mono, minLines: 1, maxLines: 3),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: d.install ?? ''));
                  if (context.mounted) toast(context, l.collectInstallCopied);
                },
                icon: const Icon(Icons.copy, size: 18),
                label: Text(l.collectCopyInstall),
              ),
            ],
            if (d.homepage != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(d.homepage!, style: t.bodySmall?.copyWith(color: scheme.outline))),
          ] else if (d.unavailable == null) ...[
            if (d.archive == false)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(l.collectNoArchive('${d.cliBin}'), style: t.bodySmall?.copyWith(color: scheme.error)),
              ),
            for (final f in d.fields) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _field(f),
                  minLines: f.kind == 'list' ? 2 : 1,
                  maxLines: f.kind == 'list' ? 6 : 1,
                  style: f.kind == 'list' || f.kind == 'env' ? mono : null,
                  decoration: InputDecoration(
                    labelText: f.required ? '${f.label} *' : f.label,
                    hintText: f.placeholder,
                    helperText: f.help ?? (f.kind == 'list' ? l.collectOnePerLine : f.kind == 'env' ? l.collectEnvHelper : null),
                    helperMaxLines: 2,
                    isDense: true,
                  ),
                ),
              ),
              // a token for an env field: the app has no shell env to inherit, so the value is kept in
              // secrets.json (0600) under that name and handed to the search process
              if (f.kind == 'env')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    controller: _token(f),
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: l.collectTokenLabel(_envName(f)),
                      hintText: _envStatus(l, d, f),
                      helperText: l.collectTokenHelper,
                      helperMaxLines: 2,
                      isDense: true,
                      prefixIcon: const Icon(Icons.key_outlined),
                    ),
                  ),
                ),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextField(controller: _note, decoration: InputDecoration(labelText: l.collectNoteLabel, helperText: l.collectNoteHelper, isDense: true)),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              FilledButton(onPressed: () => widget.onSave(_connector(), _note.text.trim(), _secrets()), child: Text(d.configured ? l.commonSave : l.collectConnect)),
              if (d.configured) OutlinedButton(onPressed: widget.syncing || !d.enabled ? null : widget.onSync, child: Text(l.collectSyncNow)),
              if (d.configured) TextButton(onPressed: widget.onRemove, child: Text(l.collectRemoveConnection, style: TextStyle(color: scheme.error))),
            ]),
          ],
        ],
      ),
    );
  }
}

/// Ready-made connectors: pick one, adjust the folder/command, add. Everything is a shell command
/// that prints text, so the user can also start from scratch.
class ConnectorPreset {
  const ConnectorPreset({required this.id, required this.title, required this.description, required this.name, required this.command, this.requires});
  final String id;
  final String title;
  final String description;
  final String name;
  final String command;

  /// What has to be installed for the command to work, if anything.
  final String? requires;

  static List<ConnectorPreset> all(AppLocalizations l) => [
    ConnectorPreset(
      id: 'folder',
      title: l.collectPresetFolder,
      description: l.collectPresetFolderHint,
      name: 'notes',
      command: "find ~/Notes -type f \\( -name '*.md' -o -name '*.txt' \\) -newermt {fromDate} -exec sh -c 'echo \"## \$1\"; cat \"\$1\"; echo' _ {} \\;",
    ),
    ConnectorPreset(
      id: 'calendar',
      title: l.collectPresetCalendar,
      description: l.collectPresetCalendarHint,
      name: 'calendar',
      command: "icalBuddy -nc -nrd -b '- ' eventsFrom:{fromDate} to:{toDate}",
      requires: "brew install ical-buddy",
    ),
    ConnectorPreset(
      id: 'custom',
      title: l.collectPresetCustom,
      description: l.collectPresetCustomHint,
      name: '',
      command: '',
    ),
  ];
}

/// Returns the new connector's name, or null when cancelled.
Future<String?> showAddSourceDialog(BuildContext context, WorklogApi api) async {
  final name = TextEditingController();
  final command = TextEditingController();
  final desc = TextEditingController();
  String? chosen;
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      String? error;
      bool busy = false;
      return StatefulBuilder(builder: (context, setLocal) {
        final t = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;
        final l = context.l10n;
        void pick(ConnectorPreset p) => setLocal(() {
              chosen = p.id;
              name.text = p.name;
              command.text = p.command;
              desc.text = p.id == 'custom' ? '' : p.title;
              error = null;
            });
        return AlertDialog(
          title: Text(l.collectAddConnector),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.collectStep1, style: t.labelLarge),
                const SizedBox(height: 6),
                for (final p in ConnectorPreset.all(l))
                  Card.outlined(
                    margin: const EdgeInsets.only(bottom: 6),
                    color: chosen == p.id ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
                    child: ListTile(
                      dense: true,
                      leading: Icon(chosen == p.id ? Icons.radio_button_checked : Icons.radio_button_off, color: chosen == p.id ? scheme.primary : scheme.outline),
                      title: Text(p.title),
                      subtitle: Text([p.description, if (p.requires != null) l.collectRequires(p.requires!)].join('\n'), style: t.bodySmall),
                      onTap: () => pick(p),
                    ),
                  ),
                if (chosen != null) ...[
                  const SizedBox(height: 10),
                  Text(l.collectStep2, style: t.labelLarge),
                  TextField(controller: name, decoration: InputDecoration(labelText: l.collectNameLabel, hintText: 'my-notes')),
                  TextField(
                    controller: command,
                    minLines: 1,
                    maxLines: 4,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      labelText: l.collectCommandLabel,
                      hintText: 'python3 ~/bin/export.py --since {from}',
                      helperText: chosen == 'folder' ? l.collectNotesFolderHelper : null,
                    ),
                  ),
                  TextField(controller: desc, decoration: InputDecoration(labelText: l.collectDescLabel)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      l.collectPlaceholderHelp('{fromDate} {toDate}', '{from} {to}', '<!-- zaevis:date 2026-10-23 -->'),
                      style: t.bodySmall,
                    ),
                  ),
                ],
                if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: scheme.error))),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l.commonCancel)),
            FilledButton(
              onPressed: chosen == null || busy
                  ? null
                  : () async {
                      final n = name.text.trim();
                      final c = command.text.trim();
                      if (n.isEmpty || c.isEmpty) {
                        setLocal(() => error = l.collectNeedNameCommand);
                        return;
                      }
                      setLocal(() => busy = true);
                      try {
                        await api.addSource(n, c, description: desc.text.trim().isEmpty ? null : desc.text.trim());
                        if (context.mounted) Navigator.pop(context, n);
                      } on ApiException catch (e) {
                        if (!context.mounted) return;
                        setLocal(() {
                          error = e.message;
                          busy = false;
                        });
                      }
                    },
              child: Text(l.collectAddAndCollect),
            ),
          ],
        );
      });
    },
  );
  return result;
}

/// A round, brand-coloured icon for a source or connector (no bundled logos: Material icons on the
/// service's colour). Unknown names get a neutral plug icon.
class SourceIcon extends StatelessWidget {
  const SourceIcon(this.id, {super.key, this.dim = false, this.size = 32});
  final String id;
  final bool dim;
  final double size;

  static const _spec = <String, (IconData, int)>{
    // built-in sources
    'git': (Icons.commit, 0xFFF05032),
    'agent-sessions': (Icons.smart_toy_outlined, 0xFFD97757),
    'shell-history': (Icons.terminal, 0xFF2F3E46),
    'transcripts': (Icons.record_voice_over_outlined, 0xFF5B7DB1),
    // AutoRAG templates
    'obsidian': (Icons.auto_stories_outlined, 0xFF7C3AED),
    'slack': (Icons.tag, 0xFF4A154B),
    'notion': (Icons.article_outlined, 0xFF1F1F1F),
    'discord': (Icons.forum_outlined, 0xFF5865F2),
    'kakao': (Icons.chat_bubble_outline, 0xFFC9A400),
    'whatsapp': (Icons.chat_outlined, 0xFF25D366),
    'telegram': (Icons.send_outlined, 0xFF229ED9),
    'mailcrawl': (Icons.mail_outline, 0xFFC5221F),
    'mail-export': (Icons.drafts_outlined, 0xFF8E6E53),
    'github': (Icons.merge_type, 0xFF24292F),
    'github-gist': (Icons.code, 0xFF24292F),
    'cloud-drive': (Icons.cloud_outlined, 0xFF1A73E8),
    'rss': (Icons.rss_feed, 0xFFF26522),
    'spotlight': (Icons.manage_search, 0xFF6E6E73),
    'clawgallery': (Icons.photo_library_outlined, 0xFF00897B),
    'hister': (Icons.history, 0xFF0E7490),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, rgb) = _spec[id] ?? (Icons.power_outlined, 0xFF607D8B);
    final color = Color(rgb);
    return Opacity(
      opacity: dim ? 0.4 : 1,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(size * 0.3)),
        alignment: Alignment.center,
        child: Icon(icon, size: size * 0.58, color: Colors.white),
      ),
    );
  }
}
