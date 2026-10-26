import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'backend.dart';

class IoBackend implements Backend {
  IoBackend(this.payload);

  /// <app>/Contents/Resources/zaevis, or ZAEVIS_ROOT for development; null when not bundled.
  final String? payload;

  static IoBackend detect() {
    final env = Platform.environment;
    final exe = File(Platform.resolvedExecutable);
    final candidates = <String>[
      if (env['ZAEVIS_ROOT'] != null) env['ZAEVIS_ROOT']!,
      '${exe.parent.parent.path}/Resources/zaevis', // macOS .app layout
    ];
    for (final c in candidates) {
      if (File('$c/bin/zaevis').existsSync()) return IoBackend(c);
    }
    return IoBackend(null);
  }

  @override
  bool get managed => payload != null;

  @override
  String get home => Platform.environment['HOME'] ?? '';

  String get _stateDir => Platform.environment['ZAEVIS_HOME'] ?? '$home/.zaevis';

  @override
  bool get isConfigured => File('$_stateDir/config.json').existsSync();

  @override
  String? get problem {
    if (Platform.resolvedExecutable.contains('/AppTranslocation/')) {
      return 'zaevis를 Applications 폴더로 옮긴 뒤 다시 여세요. (지금은 다운로드한 위치에서 임시로 실행 중이라 매일 수집 예약을 만들 수 없습니다)';
    }
    return null;
  }

  Map<String, String> get _env {
    final p = payload!;
    final path = Platform.environment['PATH'] ?? '';
    return {
      ...Platform.environment,
      // Finder-launched apps get a minimal PATH; put the bundled runtime first.
      'PATH': '$p/node/bin:$p/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$path',
      'NO_COLOR': '1',
    };
  }

  @override
  Stream<String> run(List<String> args) {
    if (payload == null) return Stream<String>.error(StateError('앱 설치본이 아닙니다'));
    final out = StreamController<String>();
    () async {
      try {
        // via bash so a lost exec bit on the script can't break the app
        final proc = await Process.start('/bin/bash', ['$payload/bin/zaevis', ...args], environment: _env, workingDirectory: home);
        unawaited(proc.stdin.close());
        final done = <Future<void>>[
          for (final s in [proc.stdout, proc.stderr])
            s.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).forEach(out.add),
        ];
        final code = (await Future.wait<Object?>([proc.exitCode, ...done])).first! as int;
        if (code != 0) out.addError(ProcessException('zaevis', args, '종료 코드 $code', code));
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
}

Backend createBackend() => IoBackend.detect();
