// Replaces the running install with a downloaded release. macOS mounts the DMG and
// copies zaevis.app over this bundle. Windows starts the silent installer, which
// closes this process and opens the new one.

import 'dart:io';

import 'l10n/l10n.dart';

/// `…/zaevis.app/Contents/MacOS/zaevis` → `…/zaevis.app`. Null for a dev binary.
String? macAppBundle(String executable) {
  final sep = Platform.pathSeparator;
  final parts = executable.split(sep);
  final i = parts.lastIndexOf('Contents');
  if (i <= 0) return null;
  final bundle = parts.sublist(0, i).join(sep);
  return bundle.endsWith('.app') ? bundle : null;
}

/// The `.app` at the top of a mounted disk image.
Directory? appInMount(Directory mount) {
  if (!mount.existsSync()) return null;
  for (final entity in mount.listSync()) {
    if (entity is Directory && entity.path.endsWith('.app')) return entity;
  }
  return null;
}

typedef Proc = Future<ProcessResult> Function(String executable, List<String> args);

/// Copies `zaevis.app` out of [mount] onto [appBundle] and clears the download quarantine.
Future<void> replaceMacApp({
  required Directory mount,
  required String appBundle,
  Proc? run,
}) async {
  final runProc = run ?? Process.run;
  final src = appInMount(mount);
  if (src == null) throw Exception(l10nNow.updateAppNotInImage);
  final copied = await runProc('ditto', [src.path, appBundle]);
  if (copied.exitCode != 0) throw Exception('${l10nNow.updateReplaceFailed}\n${copied.stderr}'.trim());
  final cleared = await runProc('xattr', ['-dr', 'com.apple.quarantine', appBundle]);
  if (cleared.exitCode != 0) {
    throw Exception('${l10nNow.updateQuarantineFailed}\n${quarantineClearCommand(appBundle)}\n${cleared.stderr}'.trim());
  }
}

/// What to paste in Terminal when macOS says the downloaded app is damaged.
String quarantineClearCommand(String appBundle) {
  final quoted = appBundle.contains(' ') ? "'${appBundle.replaceAll("'", r"'\''")}'" : appBundle;
  return 'xattr -dr com.apple.quarantine $quoted';
}

/// Mounts [dmg], replaces [appBundle], then unmounts. [run] is the process runner (tests pass a fake).
Future<void> installMacDmg({
  required File dmg,
  required String appBundle,
  Proc? run,
}) async {
  final runProc = run ?? Process.run;
  final mount = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}zaevis-mount-${DateTime.now().millisecondsSinceEpoch}');
  mount.createSync(recursive: true);
  try {
    await runProc('xattr', ['-dr', 'com.apple.quarantine', dmg.path]);
    final attached = await runProc('hdiutil', ['attach', dmg.path, '-nobrowse', '-readonly', '-mountpoint', mount.path]);
    if (attached.exitCode != 0) throw Exception('${l10nNow.updateMountFailed}\n${attached.stderr}'.trim());
    await replaceMacApp(mount: mount, appBundle: appBundle, run: runProc);
  } finally {
    final detached = await runProc('hdiutil', ['detach', mount.path, '-quiet']);
    if (detached.exitCode == 0 && mount.existsSync()) {
      try {
        mount.deleteSync(recursive: true);
      } catch (_) {}
    }
  }
}

/// Inno Setup flags: no wizard, and the installer itself restarts zaevis after it replaces the files.
const windowsSilentArgs = ['/VERYSILENT', '/SUPPRESSMSGBOXES'];

/// Writes [url] to [dest], reporting 0..1 when the server sends a length.
Future<void> downloadTo(Uri url, File dest, void Function(double? progress) onProgress, {HttpClient? client}) async {
  final own = client == null;
  final http = client ?? HttpClient();
  try {
    final req = await http.getUrl(url);
    req.followRedirects = true;
    req.headers.set(HttpHeaders.userAgentHeader, 'zaevis');
    req.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
    final res = await req.close();
    if (res.statusCode != 200) throw Exception(l10nNow.updateDownloadFailed(res.statusCode));
    final total = res.contentLength;
    var got = 0;
    dest.parent.createSync(recursive: true);
    final sink = dest.openWrite();
    await for (final chunk in res) {
      got += chunk.length;
      sink.add(chunk);
      onProgress(total > 0 ? got / total : -1);
    }
    await sink.close();
  } finally {
    if (own) http.close(force: true);
  }
}
