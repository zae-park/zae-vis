import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../backend/backend.dart';
import '../l10n/l10n.dart';
import '../languages.dart';
import '../widgets/input_dialogs.dart' show toast;
import '../models.dart';
import '../theme.dart';

/// First run of the packaged app: pick folders and sources, then setup + start + first collect.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.backend, required this.api, required this.onDone});
  final Backend backend;
  final WorklogApi api;
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

List<(String, String, String)> _sources(AppLocalizations l) => [
      ('git', l.onboardingSourceGit, l.onboardingSourceGitHint),
      ('agent-sessions', l.onboardingSourceAgents, l.onboardingSourceAgentsHint),
      ('shell-history', l.onboardingSourceShell, l.onboardingSourceShellHint),
      ('transcripts', l.onboardingSourceTranscripts, l.onboardingSourceTranscriptsHint),
    ];

/// Shown on the last step, once the first collect has started.
List<(String, String)> nextSteps(AppLocalizations l) => [
      (l.onboardingNextConnect, l.onboardingNextConnectHint),
      (l.onboardingNextMemory, l.onboardingNextMemoryHint),
      (l.onboardingNextReports, l.onboardingNextReportsHint),
    ];

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final _worklog = TextEditingController(text: '${widget.backend.home}/worklog');
  late final _repos = TextEditingController(text: widget.backend.home);
  final Set<String> _enabled = {for (final s in _sources(l10nNow)) s.$1};
  TimeOfDay _dailyAt = const TimeOfDay(hour: 18, minute: 30);

  /// The one thing asked about the user: the language they speak, for transcription. Starts from the system's.
  String _language = systemLanguage();

  /// Korean morphological tokenizer for keyword search, installed before the first index so it never needs a rebuild.
  bool _kiwi = true;

  bool _running = false;
  bool _done = false;
  String? _error;
  final List<String> _log = [];
  final _scroll = ScrollController();

  @override
  void dispose() {
    _worklog.dispose();
    _repos.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pick(TextEditingController c) async {
    final dir = await FilePicker.platform.getDirectoryPath(initialDirectory: c.text);
    if (dir != null && mounted) setState(() => c.text = dir);
  }

  void _append(String line) {
    if (!mounted) return;
    setState(() => _log.add(line));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _start() async {
    final l = context.l10n;
    String two(int n) => n.toString().padLeft(2, '0');
    final params = SetupParams(
      worklogDir: _worklog.text.trim(),
      reposRoot: _repos.text.trim(),
      dailyAt: '${two(_dailyAt.hour)}:${two(_dailyAt.minute)}',
      disabledSources: [for (final s in _sources(l)) if (!_enabled.contains(s.$1)) s.$1],
      language: _language,
    );
    setState(() {
      _running = true;
      _error = null;
      _log.clear();
    });
    try {
      await widget.backend.run(params.toArgs()).forEach(_append);
      if (_kiwi) {
        _append('› ${l.onboardingLogKiwi}');
        try {
          await widget.backend.run(const ['ext', 'install', 'kiwi']).forEach(_append);
        } catch (e) {
          _append('! ${l.onboardingLogKiwiFailed('$e')}');
        }
      }
      _append('› ${l.onboardingLogServer}');
      await widget.backend.ensureServer();
      _append('› ${l.onboardingLogCollect}');
      await widget.api.collect();
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _running = false;
          _error = '$e';
        });
      }
    }
  }

  Widget _folder(String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(child: TextField(controller: c, enabled: !_running, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: label))),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _running ? null : () => _pick(c), child: Text(context.l10n.onboardingPick)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    final problem = widget.backend.problem;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(28), shrinkWrap: true, children: [
            Text(_done ? l.onboardingReady : l.onboardingTitle, style: t.headlineMedium),
            const SizedBox(height: 6),
            Text(
              _done
                  ? l.onboardingReadyBody
                  : l.onboardingIntro,
              style: t.bodyMedium,
            ),
            if (_done) ...[
              const SizedBox(height: 20),
              Text(l.onboardingNext, style: t.titleMedium),
              for (final (i, step) in nextSteps(l).indexed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(radius: 14, backgroundColor: scheme.primary, foregroundColor: scheme.onPrimary, child: Text('${i + 1}')),
                  title: Text(step.$1),
                  subtitle: Text(step.$2),
                ),
              const SizedBox(height: 12),
              _FirstDigest(api: widget.api),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: widget.onDone, icon: const Icon(Icons.arrow_forward), label: Text(l.onboardingOpenApp)),
            ],
            if (problem != null) ...[
              const SizedBox(height: 16),
              Card(
                color: scheme.errorContainer,
                child: Padding(padding: const EdgeInsets.all(14), child: Text(problem, style: TextStyle(color: scheme.onErrorContainer))),
              ),
            ],
            if (!_done) ...[
              const SizedBox(height: 24),
              _folder(l.onboardingWorklogFolder, _worklog),
              _folder(l.onboardingReposFolder, _repos),
              const SizedBox(height: 20),
              Text(l.onboardingSources, style: t.titleMedium),
              Text(l.onboardingSourcesHint, style: t.bodySmall),
              for (final s in _sources(l))
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _enabled.contains(s.$1),
                  onChanged: _running ? null : (v) => setState(() => v == true ? _enabled.add(s.$1) : _enabled.remove(s.$1)),
                  title: Text(s.$2),
                  subtitle: Text(s.$3),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.translate),
                title: Text(l.onboardingLanguage),
                subtitle: Text(l.onboardingLanguageHint),
                trailing: DropdownButton<String>(
                  value: _language,
                  underline: const SizedBox.shrink(),
                  items: [for (final (code, name) in userLanguages) DropdownMenuItem(value: code, child: Text(name))],
                  onChanged: _running ? null : (v) => setState(() => _language = v ?? _language),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: Text(l.onboardingDaily(_dailyAt.format(context))),
                trailing: TextButton(
                  onPressed: _running
                      ? null
                      : () async {
                          final picked = await showTimePicker(context: context, initialTime: _dailyAt);
                          if (picked != null && mounted) setState(() => _dailyAt = picked);
                        },
                  child: Text(l.commonChange),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _kiwi,
                onChanged: _running ? null : (v) => setState(() => _kiwi = v == true),
                title: Text(l.indexKiwiInstallTitle),
                subtitle: Text(l.onboardingKiwiHint),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _running || problem != null || _worklog.text.trim().isEmpty ? null : _start,
                icon: _running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow),
                label: Text(_running ? l.onboardingSettingUp : l.onboardingStart),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(l.onboardingFailed('$_error'), style: TextStyle(color: scheme.error)),
            ],
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                height: 200,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                child: ListView.builder(
                  controller: _scroll,
                  itemCount: _log.length,
                  itemBuilder: (_, i) => Text(_log[i], style: ZaevisTheme.mono.copyWith(fontSize: 12)),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// "첫 정리 해 보기": without it the first digest waits for Monday and the memory stays empty until then. Starts the
/// digest on what the first collection gathered; the app's knowledge panel shows it running and then the review.
class _FirstDigest extends StatefulWidget {
  const _FirstDigest({required this.api});
  final WorklogApi api;

  @override
  State<_FirstDigest> createState() => _FirstDigestState();
}

class _FirstDigestState extends State<_FirstDigest> {
  late final Future<DigestStatus> _status = widget.api.digest();
  bool _starting = false;
  bool _started = false;

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      await widget.api.runDigest();
      if (mounted) setState(() => _started = true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<DigestStatus>(
      future: _status,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
        final s = snap.data;
        final agent = s == null ? null : s.agents.where((a) => a.id == s.chosen).firstOrNull;
        final Widget body;
        if (_started) {
          body = Row(children: [
            Icon(Icons.check_circle_outline, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(l.onbFirstDigestStarted, style: t.bodyMedium)),
          ]);
        } else if (agent == null) {
          body = Text(l.onbFirstDigestNoAgent, style: t.bodyMedium?.copyWith(color: scheme.outline));
        } else {
          body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.onbFirstDigestTitle, style: t.titleSmall),
            const SizedBox(height: 4),
            Text(l.onbFirstDigestBody(agent.title), style: t.bodyMedium),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _starting ? null : _start,
              icon: _starting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome),
              label: Text(l.onbFirstDigestButton),
            ),
          ]);
        }
        return Material(
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.outlineVariant)),
          child: Padding(padding: const EdgeInsets.all(14), child: body),
        );
      },
    );
  }
}
