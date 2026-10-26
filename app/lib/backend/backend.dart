// The packaged app manages its own backend (bundled Node server, CLI, scheduler).
// On the web, or in `flutter run` without a bundle, the server is managed elsewhere.

import 'backend_stub.dart' if (dart.library.io) 'backend_io.dart' as impl;

class SetupParams {
  const SetupParams({
    required this.worklogDir,
    required this.reposRoot,
    required this.email,
    required this.dailyAt,
    this.disabledSources = const [],
  });
  final String worklogDir;
  final String reposRoot;
  final String email;
  final String dailyAt; // "18:30"
  final List<String> disabledSources;

  List<String> toArgs() => [
        'setup', '--yes', '--skip-refresh',
        '--worklog', worklogDir,
        '--repos', reposRoot,
        '--email', email,
        '--daily-at', dailyAt,
        for (final s in disabledSources) ...['--disable', s],
      ];
}

abstract class Backend {
  /// True when running from zaevis.app with the bundled server.
  bool get managed;

  /// Something that blocks running (e.g. app not moved to Applications), or null.
  String? get problem;

  String get home;

  bool get isConfigured;

  /// Default git e-mail from ~/.gitconfig (no git binary needed).
  String gitEmail();

  /// Runs `zaevis <args>` from the bundle, streaming output lines. Errors if it exits non-zero.
  Stream<String> run(List<String> args);

  /// Starts the background server if it isn't running.
  Future<void> ensureServer();

  /// Opens a URL or file with the OS.
  Future<void> open(String target);
}

Backend createBackend() => impl.createBackend();
