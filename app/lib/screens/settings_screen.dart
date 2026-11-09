import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../app_prefs.dart';
import '../languages.dart';
import '../backend/backend.dart';
import '../l10n/l10n.dart';
import '../models.dart';
import '../shortcuts.dart';
import '../theme.dart';
import '../update.dart';
import '../widgets/agent_rail.dart';
import '../widgets/common.dart';
import '../widgets/input_dialogs.dart';
import '../widgets/task_dialog.dart';
import 'review_screen.dart';

/// Settings as a modal over the dimmed app: sections on the left, grouped rows on the right. On a narrow window the
/// modal fills the screen and the sections become a row of tabs.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api, required this.onServerChanged, this.backend, this.prefs, this.updates, this.initial = SettingsSection.general});
  final WorklogApi api;
  final Backend? backend;
  final VoidCallback onServerChanged;

  /// Theme and text size (the 일반 section); a screen built on its own gets a fresh one.
  final AppPrefs? prefs;

  /// The update check the corner card uses; null hides the update row's button.
  final UpdateController? updates;
  final SettingsSection initial;

  static Future<void> show(BuildContext context,
      {required WorklogApi api, required VoidCallback onServerChanged, Backend? backend, AppPrefs? prefs, UpdateController? updates, SettingsSection initial = SettingsSection.general}) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => SettingsScreen(api: api, backend: backend, prefs: prefs, updates: updates, onServerChanged: onServerChanged, initial: initial),
    );
  }

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

enum SettingsSection {
  general(Icons.tune),
  recording(Icons.mic_none),
  digest(Icons.auto_awesome_outlined),
  search(Icons.search),
  collect(Icons.schedule),
  shortcuts(Icons.keyboard_outlined),
  advanced(Icons.build_outlined);

  const SettingsSection(this.icon);
  final IconData icon;

  String label(AppLocalizations l) => switch (this) {
        general => l.settingsSectionGeneral,
        recording => l.settingsSectionRecording,
        digest => l.settingsSectionDigest,
        search => l.commonSearch,
        collect => l.settingsSectionCollect,
        shortcuts => l.settingsSectionShortcuts,
        advanced => l.settingsSectionAdvanced,
      };
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _server = TextEditingController(text: widget.api.baseUrl);
  late Future<AppSettings> _future = widget.api.settings();
  late SettingsSection _section = widget.initial;
  late final AppPrefs _prefs = widget.prefs ?? AppPrefs();

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
        _future = widget.api.settings();
      });

  bool get _managed => widget.backend?.managed == true;

  /// Runs `zaevis <args>` from the app bundle and shows its output live.
  Future<void> _runTask(String title, List<String> args, {List<String>? then}) async {
    await runBackendTask(context, widget.backend!, title, args, then: then);
    if (mounted) _reload();
  }

  /// Installs Kiwi through the bundle, then offers the rebuild from scratch the new tokenizer needs.
  Future<void> _installKiwi() async {
    final ok = await runBackendTask(context, widget.backend!, context.l10n.settingsKiwiInstallTask, const ['ext', 'install', 'kiwi']);
    if (!mounted) return;
    _reload();
    if (!ok) return;
    final rebuild = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsKiwiReindexTitle),
        content: Text(context.l10n.settingsKiwiReindexBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.settingsLater)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.l10n.settingsReindex)),
        ],
      ),
    );
    if (rebuild != true || !mounted) return;
    try {
      await widget.api.refreshIndex(force: true);
      if (mounted) toast(context, context.l10n.settingsReindexStarted);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) _reload();
  }

  Future<void> _update({String? dailyAt, bool? indexOnInject, bool? localEmbedding, bool? notifications, bool? speakers, String? transcribeSpeed, String? hotkey, List<String>? memoryPaths, String? language, String? transcribeLanguage}) async {
    try {
      await widget.api.updateSettings(dailyAt: dailyAt, indexOnInject: indexOnInject, localEmbedding: localEmbedding, notifications: notifications, speakers: speakers, transcribeSpeed: transcribeSpeed, hotkey: hotkey, memoryPaths: memoryPaths, language: language, transcribeLanguage: transcribeLanguage);
      if (hotkey != null) await GlobalHotkey.update(hotkey);
      if (mounted) toast(context, memoryPaths != null ? context.l10n.settingsMemoryAdded : context.l10n.commonSaved);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) _reload();
  }

  Future<void> _appearance({ThemeMode? mode, double? scale, String? locale}) async {
    try {
      await _prefs.save(widget.api, mode: mode, scale: scale, locale: locale);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _addMemory(AppSettings s) async {
    final path = await showDialog<String>(
      context: context,
      builder: (context) {
        final c = TextEditingController();
        return AlertDialog(
          title: Text(context.l10n.settingsMemoryDialogTitle),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: InputDecoration(labelText: context.l10n.settingsMemoryPathLabel, hintText: '/Users/…/worklog'),
            onSubmitted: (v) => Navigator.pop(context, v.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.commonCancel)),
            FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: Text(context.l10n.commonAdd)),
          ],
        );
      },
    );
    if (path == null || path.isEmpty) return;
    await _update(memoryPaths: [...s.memoryPaths, path]);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final full = size.width < 700 || size.height < 520;
    final scheme = Theme.of(context).colorScheme;
    final body = ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: scheme.surface,
        body: full ? _narrow(context) : _wide(context),
      ),
    );
    return Dialog(
      insetPadding: full ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      clipBehavior: Clip.antiAlias,
      shape: full ? const RoundedRectangleBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: full ? SizedBox(width: size.width, height: size.height, child: body) : ConstrainedBox(constraints: const BoxConstraints(maxWidth: 980, maxHeight: 720), child: SizedBox(width: 980, height: 720, child: body)),
    );
  }

  Widget _wide(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        width: 210,
        color: scheme.surfaceContainerLow,
        child: ListView(padding: const EdgeInsets.fromLTRB(10, 18, 10, 18), children: [
          Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 14), child: Text(context.l10n.commonSettings, style: t.titleLarge)),
          for (final sec in SettingsSection.values) _NavItem(section: sec, selected: sec == _section, onTap: () => setState(() => _section = sec)),
        ]),
      ),
      VerticalDivider(width: 1, thickness: 1, color: scheme.outlineVariant),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 14, 12, 4),
            child: Row(children: [
              Expanded(child: Text(_section.label(context.l10n), style: t.headlineSmall)),
              IconButton(tooltip: context.l10n.commonClose, onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
            ]),
          ),
          Expanded(child: _content(context, const EdgeInsets.fromLTRB(28, 8, 28, 32))),
        ]),
      ),
    ]);
  }

  Widget _narrow(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
          child: Row(children: [
            Expanded(child: Text(context.l10n.commonSettings, style: t.titleLarge)),
            IconButton(tooltip: context.l10n.commonClose, onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
          ]),
        ),
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
            for (final sec in SettingsSection.values) _TabItem(section: sec, selected: sec == _section, onTap: () => setState(() => _section = sec)),
          ]),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        Expanded(child: _content(context, const EdgeInsets.fromLTRB(16, 16, 16, 32))),
      ]),
    );
  }

  Widget _content(BuildContext context, EdgeInsets padding) {
    return FutureBuilder<AppSettings>(
      future: _future,
      builder: (context, snap) {
        final List<Widget> children;
        if (_section == SettingsSection.advanced) {
          // the server address must stay reachable when the server is not
          children = _advanced(context, snap.data);
        } else if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        } else if (snap.hasError) {
          return ErrorPane(error: snap.error!, onRetry: _reload);
        } else {
          final s = snap.data!;
          children = switch (_section) {
            SettingsSection.general => _general(context, s),
            SettingsSection.recording => _recording(context, s),
            SettingsSection.digest => [_DigestSection(api: widget.api)],
            SettingsSection.search => _search(context, s),
            SettingsSection.collect => _collect(context, s),
            SettingsSection.shortcuts => _shortcuts(context, s),
            SettingsSection.advanced => const [],
          };
        }
        return KeyedSubtree(
          key: const ValueKey('settings-content'),
          child: ListView(
            key: PageStorageKey(_section),
            padding: padding,
            children: [for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 22), children[i]]],
          ),
        );
      },
    );
  }

  List<Widget> _general(BuildContext context, AppSettings s) {
    final t = Theme.of(context).textTheme;
    return [
      _Group(title: context.l10n.settingsAbout, children: [
        ..._about(context),
      ]),
      ListenableBuilder(
        listenable: _prefs,
        builder: (context, _) => _Group(title: context.l10n.settingsDisplay, children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.contrast),
            title: Text(context.l10n.settingsTheme),
            subtitle: Text(context.l10n.settingsThemeHint),
            trailing: _Choice<ThemeMode>(
              value: _prefs.themeMode,
              items: [(ThemeMode.system, context.l10n.settingsLanguageSystem), (ThemeMode.light, context.l10n.settingsThemeLight), (ThemeMode.dark, context.l10n.settingsThemeDark)],
              onChanged: (m) => _appearance(mode: m),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.format_size),
            title: Text(context.l10n.settingsTextScale),
            subtitle: Text(context.l10n.settingsTextScaleHint((_prefs.textScale * 100).round()), style: t.bodySmall),
            trailing: _Choice<double>(
              value: _prefs.textScale,
              items: AppPrefs.scales(context.l10n),
              onChanged: (v) => _appearance(scale: v),
            ),
          ),
        ]),
      ),
      ListenableBuilder(
        listenable: _prefs,
        builder: (context, _) => _Group(title: context.l10n.settingsGroupLanguage, children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.language),
            title: Text(context.l10n.settingsLanguage),
            subtitle: Text(context.l10n.settingsLanguageHint),
            trailing: _Choice<String>(
              value: _prefs.locale,
              items: AppPrefs.locales(context.l10n),
              onChanged: (v) => _appearance(locale: v),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.translate),
            title: Text(context.l10n.settingsUserLanguage),
            subtitle: Text(context.l10n.settingsUserLanguageHint),
            trailing: _Choice<String>(value: s.language, items: userLanguages, onChanged: (v) => _update(language: v)),
          ),
        ]),
      ),
      _Group(title: context.l10n.settingsNotifications, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.notifications_outlined),
          title: Text(context.l10n.settingsSystemNotifications),
          subtitle: Text(context.l10n.settingsSystemNotificationsHint),
          value: s.notifications,
          onChanged: (v) => _update(notifications: v),
        ),
      ]),
    ];
  }

  /// Version, install date and the update — always shown, whether or not an update is waiting.
  List<Widget> _about(BuildContext context) {
    final b = widget.backend;
    final local = b?.buildVersion == null ? null : parseBuild(b!.buildVersion!);
    final installed = b?.installedAt;
    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.info_outline),
        title: Text(context.l10n.settingsVersion),
        subtitle: Text(local == null
            ? (b == null || !b.managed ? context.l10n.settingsNotInstalledBuild : context.l10n.settingsNoVersionInfo)
            : [local.version, if (local.builtAt != null) context.l10n.settingsBuiltOn(_day(local.builtAt!))].join(' · ')),
        trailing: local == null ? null : SelectableText(local.label, style: ZaevisTheme.mono.copyWith(fontSize: 12)),
      ),
      if (installed != null)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_available_outlined),
          title: Text(context.l10n.settingsInstalledOn),
          subtitle: Text(context.l10n.settingsInstalledOnHint),
          trailing: Text(_dayTime(installed)),
        ),
      if (widget.updates != null && local != null) _UpdateRow(updates: widget.updates!),
    ];
  }

  List<Widget> _recording(BuildContext context, AppSettings s) {
    return [
      _Group(title: context.l10n.settingsTranscription, children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(s.whisperx ? Icons.check_circle_outline : Icons.extension_outlined),
          title: Text(context.l10n.settingsWhisperx),
          subtitle: Text(s.whisperx
              ? context.l10n.settingsInstalled
              : (_managed ? context.l10n.settingsWhisperxInstallHint : context.l10n.settingsWhisperxMissing)),
          trailing: !s.whisperx && _managed
              ? FilledButton.tonal(onPressed: () => _runTask(context.l10n.settingsWhisperxInstallTask, const ['ext', 'install', 'whisperx']), child: Text(context.l10n.settingsInstall))
              : null,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.translate),
          title: Text(context.l10n.settingsTranscribeLanguage),
          subtitle: Text(switch (s.transcribeLanguage) {
            'user' => context.l10n.settingsTranscribeUser(languageName(s.language)),
            'auto' => context.l10n.settingsTranscribeAuto,
            _ => context.l10n.settingsTranscribeFixed(languageName(s.transcribeLanguage)),
          }),
          trailing: _Choice<String>(
            value: s.transcribeLanguage,
            items: [('user', context.l10n.settingsTranscribeMine(languageName(s.language))), ('auto', context.l10n.settingsAutoDetect), ...userLanguages],
            onChanged: (v) => _update(transcribeLanguage: v),
          ),
        ),
        if (s.whisperx)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.speed),
            title: Text(context.l10n.settingsFastTranscribe),
            subtitle: Text(context.l10n.settingsFastTranscribeHint),
            value: s.transcribeSpeed == 'fast',
            onChanged: (v) => _update(transcribeSpeed: v ? 'fast' : 'quiet'),
          ),
      ]),
      _Group(title: context.l10n.settingsSpeakers, children: [
        if (s.speakers != null) _SpeakersTile(status: s.speakers!, whisperx: s.whisperx, onChanged: (v) => _update(speakers: v), onRefresh: _reload),
        _HfLogin(api: widget.api, backend: widget.backend),
      ]),
    ];
  }

  List<Widget> _search(BuildContext context, AppSettings s) {
    final t = Theme.of(context).textTheme;
    return [
      _Group(title: context.l10n.settingsIndex, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.bolt),
          title: Text(context.l10n.settingsIndexOnInject),
          subtitle: Text(context.l10n.settingsIndexOnInjectHint),
          value: s.indexOnInject,
          onChanged: (v) => _update(indexOnInject: v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.psychology_outlined),
          title: Text(context.l10n.settingsLocalEmbedding),
          subtitle: Text(context.l10n.settingsLocalEmbeddingHint),
          value: s.localEmbedding,
          onChanged: (v) => _update(localEmbedding: v),
        ),
        if (s.tokenizer != null) _KiwiTile(status: s.tokenizer!, managed: _managed, onInstall: _installKiwi),
      ]),
      _Group(
        title: context.l10n.settingsMemoryFolders,
        description: context.l10n.settingsMemoryFoldersHint,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_special_outlined),
            title: SelectableText(s.worklogDir, style: ZaevisTheme.mono, minLines: 1),
            subtitle: Text(context.l10n.settingsWorklogFolder, style: t.bodySmall),
          ),
          for (final p in s.memoryPaths)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.folder_outlined),
              title: Text(p, style: ZaevisTheme.mono, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: TextButton(onPressed: () => _update(memoryPaths: [for (final x in s.memoryPaths) if (x != p) x]), child: Text(context.l10n.settingsRemove)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(onPressed: () => _addMemory(s), icon: const Icon(Icons.create_new_folder_outlined), label: Text(context.l10n.settingsAddFolder)),
            ),
          ),
        ],
      ),
      if (s.rerank != null)
        _Group(title: context.l10n.settingsExternal, children: [
          _RerankSection(api: widget.api, status: s.rerank!, onChanged: _reload),
        ]),
    ];
  }

  List<Widget> _collect(BuildContext context, AppSettings s) {
    final schedule = !s.scheduleSupported
        ? (s.scheduleHint ?? context.l10n.settingsScheduleUnsupported)
        : !s.scheduleInstalled
            ? context.l10n.settingsScheduleNone
            : s.scheduleLoaded
                ? context.l10n.settingsScheduleRunning(s.dailyAt)
                : context.l10n.settingsScheduleNotLoaded;
    return [
      _Group(title: context.l10n.settingsDaily, children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule),
          title: Text(context.l10n.settingsDailyAt(s.dailyAt)),
          subtitle: Text(schedule),
          trailing: OutlinedButton(
            onPressed: () async {
              final parts = s.dailyAt.split(':');
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: int.tryParse(parts.first) ?? 18, minute: int.tryParse(parts.last) ?? 30),
              );
              if (picked == null) return;
              String two(int n) => n.toString().padLeft(2, '0');
              await _update(dailyAt: '${two(picked.hour)}:${two(picked.minute)}');
            },
            child: Text(context.l10n.commonChange),
          ),
        ),
        if (s.lastDaily != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: Text(context.l10n.settingsLastRun),
            trailing: Text(_dayTime(s.lastDaily!.toLocal())),
          ),
      ]),
    ];
  }

  List<Widget> _shortcuts(BuildContext context, AppSettings s) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return [
      _Group(children: [
        for (final (i, (keys, what)) in AppShortcuts.describe(hotkey: s.hotkey).indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Container(
                constraints: const BoxConstraints(minWidth: 110),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(6)),
                child: Text(keys, style: ZaevisTheme.mono.copyWith(fontSize: 12, color: scheme.onSurface), textAlign: TextAlign.center),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(what, style: t.bodyMedium)),
              if (i == AppShortcuts.describe(hotkey: s.hotkey).length - 1 && keys == HotkeySpec.label(s.hotkey)) ...[
                TextButton(
                  onPressed: () async {
                    final spec = await showHotkeyDialog(context, current: s.hotkey);
                    if (spec != null) await _update(hotkey: spec);
                  },
                  child: Text(context.l10n.commonChange),
                ),
                if (s.hotkey.isNotEmpty) TextButton(onPressed: () => _update(hotkey: ''), child: Text(context.l10n.settingsDefault)),
              ],
            ]),
          ),
      ]),
    ];
  }

  List<Widget> _advanced(BuildContext context, AppSettings? s) {
    return [
      _Group(title: context.l10n.settingsServer, description: context.l10n.settingsServerHint, children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Expanded(child: TextField(controller: _server, decoration: InputDecoration(labelText: context.l10n.settingsServerAddress, hintText: defaultDesktopBase))),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () {
                widget.api.baseUrl = _server.text.trim().isEmpty ? defaultBaseUrl() : _server.text.trim();
                widget.onServerChanged();
                _reload();
              },
              child: Text(context.l10n.settingsApply),
            ),
          ]),
        ),
      ]),
      if (_managed)
        _Group(title: context.l10n.settingsThisComputer, children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.open_in_browser),
            title: Text(context.l10n.settingsOpenInBrowser),
            subtitle: Text(widget.api.baseUrl),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => widget.backend!.open(widget.api.baseUrl),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.terminal),
            title: Text(context.l10n.settingsInstallCli),
            subtitle: Text(context.l10n.settingsInstallCliHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _runTask(context.l10n.settingsInstallCliTask, const ['install']),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.restart_alt),
            title: Text(context.l10n.settingsRestartServer),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _runTask(context.l10n.settingsRestartServer, const ['stop'], then: const ['start']),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: Text(context.l10n.settingsOpenLogs),
            subtitle: const Text('~/.zaevis'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => widget.backend!.open('${widget.backend!.home}/.zaevis'),
          ),
        ]),
    ];
  }
}

String _two(int n) => n.toString().padLeft(2, '0');
String _day(DateTime d) => l10nNow.settingsDate(d.year, d.month, d.day);
String _dayTime(DateTime d) => '${_day(d)} ${_two(d.hour)}:${_two(d.minute)}';

/// One left-hand section entry: a flat row, tinted when selected.
class _NavItem extends StatelessWidget {
  const _NavItem({required this.section, required this.selected, required this.onTap});
  final SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? scheme.primary.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              Icon(section.icon, size: 19, color: selected ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Flexible(
                child: Text(section.label(context.l10n), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: selected ? scheme.primary : scheme.onSurface, fontWeight: selected ? FontWeight.w600 : null)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A section as a text tab with an underline (narrow windows).
class _TabItem extends StatelessWidget {
  const _TabItem({required this.section, required this.selected, required this.onTap});
  final SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: selected ? scheme.primary : Colors.transparent, width: 2))),
        child: Text(section.label(context.l10n), style: TextStyle(color: selected ? scheme.primary : scheme.onSurfaceVariant, fontWeight: selected ? FontWeight.w600 : null)),
      ),
    );
  }
}

/// A titled card of rows separated by hairlines, with an optional note under it.
class _Group extends StatelessWidget {
  const _Group({this.title, this.description, required this.children});
  final String? title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (final c in children) {
      if (rows.isNotEmpty) rows.add(Divider(height: 1, thickness: 1, color: scheme.outlineVariant.withValues(alpha: 0.6)));
      rows.add(Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2), child: c));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (title != null) Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text(title!, style: t.titleSmall?.copyWith(color: scheme.onSurfaceVariant))),
      if (description != null) Padding(padding: const EdgeInsets.only(left: 4, bottom: 8), child: Text(description!, style: t.bodySmall?.copyWith(color: scheme.outline))),
      // a Material, not a coloured box: ListTiles paint their ink on the nearest Material, and Flutter 3.4x asserts
      // when a coloured DecoratedBox sits between them
      Material(
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.outlineVariant)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
      ),
    ]);
  }
}

/// A plain drop-down for a short list of options (theme, text size).
class _Choice<T> extends StatelessWidget {
  const _Choice({required this.value, required this.items, required this.onChanged});
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: items.any((i) => i.$1 == value) ? value : items.first.$1,
        borderRadius: BorderRadius.circular(10),
        items: [for (final (v, label) in items) DropdownMenuItem(value: v, child: Text(label))],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// "업데이트": up to date, checking, a newer build with its button, the download, or why the check failed.
class _UpdateRow extends StatelessWidget {
  const _UpdateRow({required this.updates});
  final UpdateController updates;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final u = updates;
        final offer = u.offer;
        final String status;
        Widget? trailing;
        if (u.phase == UpdatePhase.downloading) {
          final p = u.progress;
          status = p != null && p >= 0 ? context.l10n.settingsUpdateDownloading((p * 100).round()) : context.l10n.uiDownloading;
        } else if (u.phase == UpdatePhase.installing) {
          status = context.l10n.settingsUpdateInstalling;
        } else if (u.checking) {
          status = context.l10n.settingsUpdateChecking;
          trailing = const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
        } else if (offer != null) {
          final built = offer.remote.builtAt;
          status = built == null ? context.l10n.settingsUpdateAvailable(offer.remote.version) : context.l10n.settingsUpdateAvailableBuilt(offer.remote.version, _day(built));
          trailing = offer.downloadUrl != null && u.install != null
              ? FilledButton(onPressed: u.apply, child: Text(context.l10n.settingsUpdate))
              : Text(context.l10n.settingsUpdateNoAsset, style: t.bodySmall);
        } else if (u.checkError != null) {
          status = context.l10n.settingsUpdateCheckFailed('${u.checkError}');
          trailing = TextButton(onPressed: u.check, child: Text(context.l10n.settingsCheckAgain));
        } else {
          status = u.checkedAt == null ? context.l10n.settingsUpdateNotChecked : context.l10n.settingsUpToDate('${_two(u.checkedAt!.hour)}:${_two(u.checkedAt!.minute)}');
          trailing = TextButton(onPressed: u.check, child: Text(context.l10n.settingsCheckUpdate));
        }
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(offer != null ? Icons.system_update_alt : Icons.verified_outlined, color: offer != null ? scheme.primary : null),
          title: Text(context.l10n.settingsUpdate),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(status, style: u.checkError != null ? t.bodySmall?.copyWith(color: scheme.error) : null),
            if (u.phase == UpdatePhase.downloading)
              Padding(padding: const EdgeInsets.only(top: 6), child: LinearProgressIndicator(value: (u.progress ?? -1) >= 0 ? u.progress : null)),
            if (u.error != null) Padding(padding: const EdgeInsets.only(top: 4), child: SelectableText(u.error!, style: t.bodySmall?.copyWith(color: scheme.error), minLines: 1)),
          ]),
          trailing: trailing,
        );
      },
    );
  }
}

/// Optional OpenRouter re-ranking: the only place a search leaves this machine. Off until the user
/// turns it on and saves a key; the key is sent to the server once and only its last 4 chars come back.
/// "한국어 형태소 분석 (Kiwi)": what the keyword index tokenizes with, and the one-click install when it is missing.
class _KiwiTile extends StatelessWidget {
  const _KiwiTile({required this.status, required this.managed, required this.onInstall});
  final TokenizerStatus status;
  final bool managed;
  final Future<void> Function() onInstall;

  @override
  Widget build(BuildContext context) {
    final k = status.kiwi;
    final String subtitle;
    if (k.installed) {
      subtitle = '${status.label}${k.source == 'zaevis' ? '' : ' · ${k.source == 'env' ? 'KIWI_LIBRARY_PATH·KIWI_MODEL_PATH' : k.library}'}';
    } else if (!k.installable) {
      subtitle = context.l10n.settingsKiwiNoRelease('~/.local/kiwi/{lib,models}');
    } else if (managed) {
      subtitle = context.l10n.settingsKiwiInstallHint(k.downloadMb);
    } else {
      subtitle = context.l10n.settingsKiwiMissing;
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(k.installed ? (status.needsReindex ? Icons.sync_problem_outlined : Icons.check_circle_outline) : Icons.translate_outlined),
      title: Text(context.l10n.settingsKiwiTitle),
      subtitle: Text(subtitle),
      trailing: !k.installed && k.installable && managed ? FilledButton.tonal(onPressed: onInstall, child: Text(context.l10n.settingsInstall)) : null,
    );
  }
}

class _RerankSection extends StatefulWidget {
  const _RerankSection({required this.api, required this.status, required this.onChanged});
  final WorklogApi api;
  final RerankStatus status;
  final VoidCallback onChanged;

  @override
  State<_RerankSection> createState() => _RerankSectionState();
}

class _RerankSectionState extends State<_RerankSection> {
  final _key = TextEditingController();
  bool _busy = false;
  String? _check;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() task) async {
    setState(() {
      _busy = true;
      _check = null;
    });
    try {
      final msg = await task();
      if (mounted && msg != null) toast(context, msg);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final s = widget.status;
    final l = context.l10n;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(Icons.cloud_outlined),
        title: Text(context.l10n.settingsRerankTitle),
        subtitle: Text(s.hasKey
            ? context.l10n.settingsRerankOn(s.model)
            : context.l10n.settingsRerankNoKey),
        value: s.enabled,
        onChanged: _busy ? null : (v) => _run(() async => (await widget.api.updateRerank(enabled: v)).active ? l.settingsRerankEnabled : (v ? l.settingsRerankNoKeySent : l.settingsRerankDisabled)),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 56, bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _key,
                obscureText: true,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: context.l10n.settingsRerankKey,
                  hintText: s.hasKey ? context.l10n.settingsRerankKeySaved('${s.keyHint}') : 'sk-or-v1-…',
                  helperText: s.hasKey ? context.l10n.settingsRerankKeyHelper : null,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _busy || _key.text.trim().isEmpty
                  ? null
                  : () => _run(() async {
                        await widget.api.updateRerank(apiKey: _key.text.trim());
                        _key.clear();
                        return l.settingsKeySaved;
                      }),
              child: Text(context.l10n.commonSave),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _busy || (!s.hasKey && _key.text.trim().isEmpty)
                  ? null
                  : () => _run(() async {
                        final r = await widget.api.testRerankKey(_key.text.trim().isEmpty ? null : _key.text.trim());
                        setState(() => _check = r.message);
                        return null;
                      }),
              child: Text(context.l10n.settingsTestConnection),
            ),
            if (s.hasKey)
              TextButton(
                onPressed: _busy ? null : () => _run(() async => (await widget.api.updateRerank(apiKey: '')).hasKey ? null : l.settingsKeyCleared),
                child: Text(context.l10n.settingsDeleteKey),
              ),
          ]),
          if (_check != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_check!, style: t.bodySmall)),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(context.l10n.settingsRerankExternal('${s.external}'), style: t.bodySmall?.copyWith(color: s.active ? scheme.error : scheme.outline)),
          ),
        ]),
      ),
    ]);
  }
}

/// Weekly digest ("지식화"): which agent on this Mac turns inbox + sources into log lines, project
/// updates and monthly summaries. Runs with what the user already has — an installed agent CLI on
/// their own subscription, or the saved OpenRouter key — and never asks for a new account.
class _DigestSection extends StatefulWidget {
  const _DigestSection({required this.api});
  final WorklogApi api;

  @override
  State<_DigestSection> createState() => _DigestSectionState();
}

class _DigestSectionState extends State<_DigestSection> {
  late Future<DigestStatus> _future = widget.api.digest();
  late Future<List<ProposalSummary>> _proposals = _fetchProposals();

  Future<List<ProposalSummary>> _fetchProposals() => widget.api.proposals().catchError((_) => <ProposalSummary>[]);
  Timer? _poll;
  late final _model = TextEditingController();

  @override
  void dispose() {
    _poll?.cancel();
    _model.dispose();
    super.dispose();
  }

  void _reload() => setState(() {
        _future = widget.api.digest();
        _proposals = _fetchProposals();
      });

  Future<void> _review(String id) async {
    if (await ReviewScreen.open(context, widget.api, id)) _reload();
  }

  void _watch(DigestStatus s) {
    _poll?.cancel();
    if (s.running) _poll = Timer(const Duration(seconds: 4), _reload);
  }

  Future<void> _update({String? agent, String? model, bool? weekly, bool? daily, bool? review, List<String>? order, List<String>? skip}) async {
    try {
      await widget.api.updateDigest(agent: agent, model: model, weekly: weekly, daily: daily, review: review, order: order, skip: skip);
      if (mounted) toast(context, context.l10n.commonSaved);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    _reload();
  }

  Future<void> _run({bool weekly = false}) async {
    try {
      await widget.api.runDigest(weekly: weekly);
      if (mounted) toast(context, weekly ? context.l10n.settingsWeeklyStarted : context.l10n.settingsDigestStarted);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    _reload();
  }

  static const _names = {'claude': 'Claude Code', 'codex': 'Codex CLI', 'cursor': 'Cursor', 'gemini': 'Gemini CLI', 'openrouter': 'OpenRouter API'};

  String? _label(String? id) => id == 'auto' ? context.l10n.settingsAgentAuto : _names[id];

  String _quotaNote(List<RailStop> rail) {
    final names = rail.where((s) => s.state == 'quota').map((s) => s.title).toList();
    return names.isEmpty ? '' : ' · ${context.l10n.settingsQuotaSkipped(names.join(', '))}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<DigestStatus>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator());
        if (snap.hasError) return ErrorPane(error: snap.error!, onRetry: _reload);
        final s = snap.data!;
        _watch(s);
        if (_model.text.isEmpty && s.model.isNotEmpty) _model.text = s.model;
        final chosen = s.agents.where((a) => a.id == s.chosen).firstOrNull;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Group(
            title: context.l10n.settingsAgentOrder,
            description: context.l10n.settingsAgentOrderHint,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (s.rail.isNotEmpty) AgentRail(stops: s.rail),
                  _AgentOrder(
                    agents: s.agents,
                    skip: s.skip,
                    chosen: s.chosen,
                    enabled: !s.running,
                    onReorder: (order) => _update(agent: 'auto', order: order, skip: s.skip),
                    onSkip: (skip) => _update(agent: 'auto', order: [for (final a in s.agents) a.id], skip: skip),
                  ),
                  if (!s.skip.contains('openrouter') && (s.chosen == 'openrouter' || s.agents.any((a) => a.id == 'openrouter' && a.available))) ...[
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: TextField(
                        controller: _model,
                        decoration: InputDecoration(labelText: context.l10n.settingsOpenRouterModel, hintText: 'anthropic/claude-sonnet-4.5'),
                        onSubmitted: (v) => _update(model: v.trim()),
                      ),
                    ),
                  ],
                ]),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _Group(title: context.l10n.settingsRun, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.today),
              title: Text(context.l10n.settingsDailyDigest),
              subtitle: Text(s.daily ? context.l10n.settingsDailyOn : context.l10n.settingsDailyOff),
              value: s.daily,
              onChanged: s.running ? null : (v) => _update(daily: v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.rule),
              title: Text(context.l10n.settingsReviewFirst),
              subtitle: Text(s.review
                  ? context.l10n.settingsReviewOn
                  : context.l10n.settingsReviewOff),
              value: s.review,
              onChanged: s.running ? null : (v) => _update(review: v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.event_repeat),
              title: Text(context.l10n.settingsWeekly),
              subtitle: Text(s.weekly ? context.l10n.settingsWeeklyNext(s.nextWeekly ?? context.l10n.settingsNextMonday) : context.l10n.settingsWeeklyOff),
              value: s.weekly,
              onChanged: s.running ? null : (v) => _update(weekly: v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_awesome),
              title: Text(s.running ? context.l10n.settingsDigestRunning('${_label(s.runningAgent) ?? s.runningAgent}') : context.l10n.settingsDigestNow),
              subtitle: chosen == null
                  ? Text(context.l10n.settingsNoAgent,
                      style: t.bodySmall?.copyWith(color: scheme.error))
                  : Text(context.l10n.settingsDigestBy(chosen.title)),
              trailing: s.running
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      TextButton(onPressed: chosen == null ? null : () => _run(weekly: true), child: Text(context.l10n.settingsWeeklyNow)),
                      const SizedBox(width: 6),
                      FilledButton(onPressed: chosen == null ? null : _run, child: Text(context.l10n.settingsRun)),
                    ]),
            ),
          ]),
          FutureBuilder<List<ProposalSummary>>(
            future: _proposals,
            builder: (context, ps) {
              final pending = (ps.data ?? const <ProposalSummary>[]).where((p) => p.pending).toList();
              if (pending.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 22),
                child: _Group(title: context.l10n.settingsPendingReviews(pending.length), children: [
                  for (final p in pending)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.rule),
                      title: Text('${p.createdAt?.toLocal().toString().split('.').first ?? p.id} · ${_label(p.agent) ?? p.agent}'),
                      subtitle: Text(context.l10n.settingsProposalCounts(p.lines, p.projects, p.summaries, p.processed)),
                      trailing: FilledButton.tonal(onPressed: () => _review(p.id), child: Text(context.l10n.settingsReview)),
                    ),
                ]),
              );
            },
          ),
          if (s.last != null) ...[
            const SizedBox(height: 22),
            _Group(title: context.l10n.settingsLastDigest, children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('${s.last!.ok ? (s.last!.proposalId != null ? context.l10n.settingsStatusPendingReview : context.l10n.commonDone) : context.l10n.commonFailed} · ${_label(s.last!.agent) ?? s.last!.agent}${_quotaNote(s.last!.rail)} · ${s.last!.at?.toLocal().toString().split('.').first ?? ''}',
                      style: t.bodySmall?.copyWith(color: s.last!.ok ? null : scheme.error)),
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
                    child: SelectableText(s.last!.report.length > 1200 ? '…${s.last!.report.substring(s.last!.report.length - 1200)}' : s.last!.report,
                        style: ZaevisTheme.mono.copyWith(fontSize: 12), minLines: 1, maxLines: 14),
                  ),
                ]),
              ),
            ]),
          ],
        ]);
      },
    );
  }
}

/// Fallback order as blocks. Drag to reorder. The switch keeps a service in the line without a checkbox list.
class _AgentOrder extends StatelessWidget {
  const _AgentOrder({required this.agents, required this.skip, required this.chosen, required this.enabled, required this.onReorder, required this.onSkip});
  final List<AgentInfo> agents;
  final List<String> skip;
  final String? chosen;
  final bool enabled;
  final ValueChanged<List<String>> onReorder;
  final ValueChanged<List<String>> onSkip;

  @override
  Widget build(BuildContext context) {
    if (agents.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 168,
      child: ReorderableListView(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.symmetric(vertical: 4),
        // onReorderItem hands over the index after the moved block is taken out (no newIndex - 1).
        onReorderItem: (oldIndex, newIndex) {
          if (!enabled) return;
          final ids = [for (final a in agents) a.id];
          final moved = ids.removeAt(oldIndex);
          ids.insert(newIndex, moved);
          onReorder(ids);
        },
        children: [
          for (var i = 0; i < agents.length; i++)
            _AgentBlock(
              key: ValueKey(agents[i].id),
              agent: agents[i],
              index: i + 1,
              dragIndex: i,
              included: !skip.contains(agents[i].id),
              chosen: chosen == agents[i].id,
              enabled: enabled,
              onIncluded: (v) {
                final next = [for (final id in skip) id];
                if (v) {
                  next.remove(agents[i].id);
                } else if (!next.contains(agents[i].id)) {
                  next.add(agents[i].id);
                }
                onSkip(next);
              },
            ),
        ],
      ),
    );
  }
}

class _AgentBlock extends StatelessWidget {
  const _AgentBlock({super.key, required this.agent, required this.index, required this.dragIndex, required this.included, required this.chosen, required this.enabled, required this.onIncluded});
  final AgentInfo agent;
  final int index;
  final int dragIndex;
  final bool included;
  final bool chosen;
  final bool enabled;
  final ValueChanged<bool> onIncluded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final note = agent.needsLogin ? agent.loginNote : agent.detail;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: SizedBox(
        width: 210,
        child: Material(
          color: included ? scheme.surfaceContainerLow : scheme.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: chosen ? scheme.primary : scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                ReorderableDragStartListener(
                  index: dragIndex,
                  enabled: enabled,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('$index', style: t.labelLarge?.copyWith(color: scheme.primary)),
                    const SizedBox(width: 6),
                    Icon(Icons.drag_indicator, size: 16, color: scheme.outline),
                  ]),
                ),
                const Spacer(),
                if (chosen) Chip(label: Text(context.l10n.settingsInUse), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ]),
              const SizedBox(height: 6),
              Text(agent.title, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(note, style: t.bodySmall?.copyWith(color: agent.needsLogin ? scheme.error : scheme.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
              const Spacer(),
              Row(children: [
                Text(included ? context.l10n.settingsIncluded : context.l10n.settingsSkipped, style: t.labelSmall),
                const Spacer(),
                Switch(value: included, onChanged: enabled ? onIncluded : null),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Records a new global hotkey: the user presses the combination, the dialog shows it and saves the
/// spec ("meta+shift+space"). A key without a modifier is refused — it would swallow typing everywhere.
Future<String?> showHotkeyDialog(BuildContext context, {required String current}) {
  return showDialog<String>(
    context: context,
    builder: (context) {
      String? spec = current.isEmpty ? null : current;
      String? warning;
      final focus = FocusNode();
      return StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(context.l10n.settingsHotkeyTitle),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.l10n.settingsHotkeyHint),
              const SizedBox(height: 16),
              Focus(
                focusNode: focus,
                autofocus: true,
                onKeyEvent: (_, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final got = HotkeySpec.fromEvent(event);
                  setLocal(() {
                    if (got == null) {
                      warning = HotkeySpec.isModifier(event) ? null : context.l10n.settingsHotkeyNeedsModifier;
                    } else {
                      spec = got;
                      warning = null;
                    }
                  });
                  return KeyEventResult.handled;
                },
                child: Builder(
                  builder: (context) {
                    final scheme = Theme.of(context).colorScheme;
                    final focused = Focus.of(context).hasFocus;
                    return InkWell(
                      onTap: () => focus.requestFocus(),
                      child: Container(
                        key: const ValueKey('hotkey-recorder'),
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: focused ? scheme.primary : scheme.outlineVariant, width: focused ? 2 : 1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(spec == null ? context.l10n.settingsHotkeyPress : HotkeySpec.label(spec!),
                            style: spec == null ? TextStyle(color: scheme.outline) : ZaevisTheme.mono.copyWith(fontSize: 18)),
                      ),
                    );
                  },
                ),
              ),
              if (warning != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(warning!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(context.l10n.settingsHotkeyDefault(HotkeySpec.label('')), style: Theme.of(context).textTheme.bodySmall)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.commonCancel)),
            FilledButton(onPressed: spec == null || !HotkeySpec.isValid(spec!) ? null : () => Navigator.pop(context, spec), child: Text(context.l10n.commonSave)),
          ],
        ),
      );
    },
  );
}

/// Who spoke: on by default and without an account (sherpa-onnx on this Mac). While the models arrive,
/// the tile re-reads the settings every 2 seconds.
class _SpeakersTile extends StatefulWidget {
  const _SpeakersTile({required this.status, required this.whisperx, required this.onChanged, required this.onRefresh});
  final SpeakersStatus status;
  final bool whisperx;
  final ValueChanged<bool> onChanged;
  final VoidCallback onRefresh;

  @override
  State<_SpeakersTile> createState() => _SpeakersTileState();
}

class _SpeakersTileState extends State<_SpeakersTile> {
  Timer? _poll;

  @override
  void didUpdateWidget(_SpeakersTile old) {
    super.didUpdateWidget(old);
    _schedule();
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _poll?.cancel();
    if (widget.status.state == 'installing') _poll = Timer(const Duration(seconds: 2), widget.onRefresh);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.status;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    final after = l.settingsSpeakersAfter;
    final String subtitle;
    if (!widget.whisperx) {
      subtitle = l.settingsSpeakersNeedWhisperx;
    } else if (!st.enabled) {
      subtitle = l.settingsSpeakersOff;
    } else if (st.hfReady) {
      subtitle = l.settingsSpeakersHf(after);
    } else {
      subtitle = switch (st.state) {
        'ready' => l.settingsSpeakersReady(after),
        'installing' => l.settingsSpeakersInstalling(st.downloadMb),
        'failed' => l.settingsSpeakersFailed(st.error ?? l.settingsUnknownError),
        _ => l.settingsSpeakersIdle(st.downloadMb),
      };
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: st.state == 'installing' && st.enabled
            ? const SizedBox(width: 24, height: 24, child: Padding(padding: EdgeInsets.all(3), child: CircularProgressIndicator(strokeWidth: 2)))
            : const Icon(Icons.record_voice_over_outlined),
        title: Text(context.l10n.settingsSpeakerLabel),
        subtitle: Text(subtitle, style: st.state == 'failed' && st.enabled ? t.bodySmall?.copyWith(color: scheme.error) : null),
        value: st.enabled && widget.whisperx,
        onChanged: widget.whisperx ? widget.onChanged : null,
      ),
      if (st.enabled && st.state == 'failed')
        Padding(
          padding: const EdgeInsets.only(left: 56),
          child: TextButton(onPressed: () => widget.onChanged(true), child: Text(context.l10n.settingsPrepareAgain)),
        ),
    ]);
  }
}

/// Optional: Hugging Face browser login so pyannote's own models label speakers. The token stays on the server.
class _HfLogin extends StatefulWidget {
  const _HfLogin({required this.api, this.backend});
  final WorklogApi api;
  final Backend? backend;

  @override
  State<_HfLogin> createState() => _HfLoginState();
}

class _HfLoginState extends State<_HfLogin> {
  HfStatus? _hf;
  var _hidden = false;
  Timer? _poll;

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
      final hf = await widget.api.hfStatus();
      if (!mounted) return;
      setState(() {
        _hf = hf;
        _hidden = hf == null;
      });
      _watch(hf);
    } on ApiException {
      if (mounted) setState(() => _hidden = true);
    }
  }

  void _watch(HfStatus? hf) {
    _poll?.cancel();
    if (hf?.loginState != 'pending') return;
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final next = await widget.api.hfStatus();
        if (!mounted) return;
        setState(() => _hf = next);
        if (next == null || next.loginState != 'pending') _poll?.cancel();
      } catch (_) {}
    });
  }

  Future<void> _login() async {
    try {
      final hf = await widget.api.hfLogin();
      if (!mounted) return;
      setState(() => _hf = hf);
      final url = hf.verificationUri;
      if (url != null) await widget.backend?.open(url);
      _watch(hf);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _openAccept() async {
    final hf = _hf;
    if (hf == null) return;
    for (final id in hf.accept) {
      await widget.backend?.open('https://huggingface.co/$id');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final hf = _hf;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final pending = hf?.loginState == 'pending';
    final String subtitle;
    if (hf == null) {
      subtitle = context.l10n.settingsHfChecking;
    } else if (pending && hf.userCode != null) {
      subtitle = context.l10n.settingsHfCode(hf.userCode!);
    } else if (hf.loginError != null) {
      subtitle = hf.loginError!;
    } else if (hf.loggedIn && hf.accept.isNotEmpty) {
      subtitle = context.l10n.settingsHfNeedsAccept(hf.username ?? context.l10n.settingsHfAccount);
    } else if (hf.loggedIn) {
      subtitle = context.l10n.settingsHfConnected(hf.username ?? context.l10n.settingsHfAccount);
    } else {
      subtitle = context.l10n.settingsHfHint;
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(hf?.loggedIn == true ? Icons.check_circle_outline : Icons.record_voice_over_outlined),
      title: Text(context.l10n.settingsHfTitle),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(subtitle, style: hf?.loginError != null ? t.bodySmall?.copyWith(color: scheme.error) : null),
        if (hf != null && hf.accept.isNotEmpty)
          Wrap(spacing: 4, children: [
            TextButton(onPressed: _openAccept, child: Text(context.l10n.settingsHfAcceptPage)),
            TextButton(
              onPressed: () async {
                final next = await widget.api.hfCheck();
                if (mounted) setState(() => _hf = next);
              },
              child: Text(context.l10n.settingsCheckAgain),
            ),
          ]),
      ]),
      trailing: pending
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : hf?.loggedIn == true
              ? TextButton(
                  onPressed: () async {
                    final next = await widget.api.hfLogout();
                    if (mounted) setState(() => _hf = next);
                  },
                  child: Text(context.l10n.settingsDisconnect),
                )
              : FilledButton.tonal(onPressed: hf == null ? null : _login, child: Text(context.l10n.settingsLogin)),
    );
  }
}
