import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zaevis/update_apply.dart';

import '../l10n/l10n.dart';
import 'backend.dart';

/// The packaged app's own backend: a Node runtime, the server and the CLI shipped next to the app.
///
/// Layout: macOS `zaevis.app/Contents/Resources/zaevis/`, Windows and Linux `<folder of zaevis.exe>/zaevis/`.
/// Inside: `node/` (runtime), `server/`, `bin/`, `kit/`, `web/`, `VERSION`. Commands run as
/// `node server/src/zaevis.ts <args>` — no shell involved, so the same code serves every platform.
class IoBackend implements Backend {
  IoBackend(this.payload);

  /// Payload folder, or ZAEVIS_ROOT for development; null when not bundled.
  final String? payload;

  static IoBackend detect() {
    final env = Platform.environment;
    final exeDir = File(Platform.resolvedExecutable).parent;
    final candidates = <String>[
      if (env['ZAEVIS_ROOT'] != null) env['ZAEVIS_ROOT']!,
      if (Platform.isMacOS) '${exeDir.parent.path}/Resources/zaevis',
      '${exeDir.path}${Platform.pathSeparator}zaevis',
    ];
    for (final c in candidates) {
      if (File('$c${Platform.pathSeparator}server${Platform.pathSeparator}src${Platform.pathSeparator}zaevis.ts').existsSync()) return IoBackend(c);
    }
    return IoBackend(null);
  }

  @override
  bool get managed => payload != null;

  @override
  String? get buildVersion {
    final p = payload;
    if (p == null) return null;
    final f = File('$p${Platform.pathSeparator}VERSION');
    if (!f.existsSync()) return null;
    final text = f.readAsStringSync().trim();
    return text.isEmpty ? null : text;
  }

  DateTime? _installedAt;
  bool _installedRead = false;

  /// `$ZAEVIS_HOME/app-installed.json` keeps `{version, at}` of the build first opened; a new VERSION starts a new date.
  @override
  DateTime? get installedAt {
    if (_installedRead) return _installedAt;
    _installedRead = true;
    final version = buildVersion;
    if (version == null) return null;
    final f = File('$_stateDir${Platform.pathSeparator}app-installed.json');
    try {
      final j = jsonDecode(f.readAsStringSync());
      if (j is Map && j['version'] == version && j['at'] is String) return _installedAt = DateTime.tryParse(j['at'] as String)?.toLocal();
    } catch (_) {}
    final now = DateTime.now();
    try {
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(jsonEncode({'version': version, 'at': now.toUtc().toIso8601String()}));
    } catch (_) {}
    return _installedAt = now;
  }

  @override
  String get home => Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

  String get _stateDir => Platform.environment['ZAEVIS_HOME'] ?? '$home${Platform.pathSeparator}.zaevis';

  @override
  bool get isConfigured => File('$_stateDir${Platform.pathSeparator}config.json').existsSync();

  @override
  String? get problem {
    if (Platform.isMacOS && Platform.resolvedExecutable.contains('/AppTranslocation/')) {
      return l10nNow.backendTranslocated;
    }
    return null;
  }

  /// The bundled Node, falling back to one on PATH during development (ZAEVIS_ROOT).
  String get _node {
    final p = payload!;
    final bundled = Platform.isWindows ? '$p\\node\\node.exe' : '$p/node/bin/node';
    return File(bundled).existsSync() ? bundled : 'node';
  }

  Map<String, String> get _env {
    final p = payload!;
    final sep = Platform.isWindows ? ';' : ':';
    final path = Platform.environment['PATH'] ?? '';
    final nodeDir = Platform.isWindows ? '$p\\node' : '$p/node/bin';
    final binDir = '$p${Platform.pathSeparator}bin';
    // Finder/Explorer-launched apps get a minimal PATH; put the bundled runtime first.
    final extra = Platform.isMacOS ? ['/opt/homebrew/bin', '/usr/local/bin', '/usr/bin', '/bin', '/usr/sbin', '/sbin'] : const <String>[];
    return {
      ...Platform.environment,
      'PATH': [nodeDir, binDir, ...extra, path].join(sep),
      'NO_COLOR': '1',
    };
  }

  @override
  Stream<String> run(List<String> args) {
    if (payload == null) return Stream<String>.error(StateError(l10nNow.backendNotInstalled));
    final out = StreamController<String>();
    () async {
      try {
        final proc = await Process.start(_node, ['$payload${Platform.pathSeparator}server${Platform.pathSeparator}src${Platform.pathSeparator}zaevis.ts', ...args],
            environment: _env, workingDirectory: home.isEmpty ? null : home);
        unawaited(proc.stdin.close());
        final done = <Future<void>>[
          for (final s in [proc.stdout, proc.stderr])
            s.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).forEach(out.add),
        ];
        final code = (await Future.wait<Object?>([proc.exitCode, ...done])).first! as int;
        if (code != 0) out.addError(ProcessException('zaevis', args, l10nNow.backendExitCode(code), code));
      } catch (e) {
        out.addError(e);
      } finally {
        await out.close();
      }
    }();
    return out.stream;
  }

  @override
  Future<void> ensureServer() async {
    if (payload == null) return;
    await run(const ['start']).drain<void>();
  }

  @override
  Future<void> open(String target) async {
    if (Platform.isMacOS) {
      await Process.run('open', [target]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [target]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', target]);
    }
  }

  @override
  Future<void> installUpdate(String url, void Function(double? progress) onProgress) async {
    final blocked = problem;
    if (blocked != null) throw StateError(blocked);
    if (payload == null) throw StateError(l10nNow.backendUpdateInstalledOnly);
    final dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}zaevis-update');
    dir.createSync(recursive: true);
    if (Platform.isMacOS) {
      final bundle = macAppBundle(Platform.resolvedExecutable);
      if (bundle == null) throw StateError(l10nNow.backendUpdateInstalledOnly);
      final dmg = File('${dir.path}${Platform.pathSeparator}zaevis.dmg');
      await downloadTo(Uri.parse(url), dmg, onProgress);
      onProgress(null);
      try {
        await run(const ['stop']).drain<void>();
      } catch (_) {}
      try {
        await installMacDmg(dmg: dmg, appBundle: bundle);
      } catch (e) {
        try {
          await run(const ['start']).drain<void>();
        } catch (_) {}
        rethrow;
      }
      await Process.start('open', [bundle], mode: ProcessStartMode.detached);
      exit(0);
    }
    if (Platform.isWindows) {
      final exe = File('${dir.path}\\zaevis-setup.exe');
      await downloadTo(Uri.parse(url), exe, onProgress);
      onProgress(null);
      // Inno closes this process and starts the new app (CloseApplications=force).
      await Process.start(exe.path, windowsSilentArgs, mode: ProcessStartMode.detached);
      return;
    }
    throw StateError(l10nNow.backendUpdateUnsupportedOs);
  }
}

Backend createBackend() => IoBackend.detect();
