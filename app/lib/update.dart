import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'l10n/l10n.dart';
import 'update_arch_stub.dart' if (dart.library.io) 'update_arch_io.dart';

export 'folder_ack_stub.dart' if (dart.library.io) 'folder_ack_io.dart';

const releaseApi = 'https://api.github.com/repos/zae-park/zae-vis/releases/latest';

class AppBuild {
  const AppBuild(this.semver, this.build);
  final List<int> semver;
  final int build;

  String get label => '${semver.join('.')}${build > 0 ? '+$build' : ''}';

  /// "0.1.0"
  String get version => semver.join('.');

  /// The build number is the CI build time, `yyyyMMddHHmmss` in UTC. Null for a plain version.
  DateTime? get builtAt {
    final b = build.toString();
    if (b.length != 14) return null;
    int at(int i, int n) => int.parse(b.substring(i, i + n));
    return DateTime.utc(at(0, 4), at(4, 2), at(6, 2), at(8, 2), at(10, 2), at(12, 2)).toLocal();
  }
}

class UpdateOffer {
  const UpdateOffer({required this.local, required this.remote, this.downloadUrl});
  final AppBuild local;
  final AppBuild remote;
  final String? downloadUrl;
}

/// `0.1.0` or `0.1.0+20261029120000`. Null when the text is not a version.
AppBuild? parseBuild(String raw) {
  final m = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$').firstMatch(raw.trim());
  if (m == null) return null;
  return AppBuild(
    [int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)],
    m[4] == null ? 0 : int.parse(m[4]!),
  );
}

/// True when [remote] is a later semver, or the same semver with a later build time.
bool isNewer(AppBuild local, AppBuild remote) {
  for (var i = 0; i < 3; i++) {
    if (remote.semver[i] != local.semver[i]) return remote.semver[i] > local.semver[i];
  }
  return remote.build > local.build;
}

/// Installer URL for this OS from a GitHub release payload, plus the version line in its body.
UpdateOffer? offerFromRelease(String localVersion, Map<String, dynamic> release, {required String os, required String arch}) {
  final local = parseBuild(localVersion);
  if (local == null) return null;
  final body = release['body'];
  final fromBody = body is String ? RegExp(r'version:\s*(\d+\.\d+\.\d+\+\d+)').firstMatch(body)?.group(1) : null;
  final tag = release['tag_name'];
  final remoteRaw = fromBody ?? (tag is String ? tag.replaceFirst(RegExp(r'^v'), '') : '');
  final remote = parseBuild(remoteRaw);
  if (remote == null || !isNewer(local, remote)) return null;
  return UpdateOffer(local: local, remote: remote, downloadUrl: assetUrl(release['assets'], os: os, arch: arch));
}

String? assetUrl(Object? assets, {required String os, required String arch}) {
  if (assets is! List) return null;
  final names = <String, String>{};
  for (final item in assets) {
    if (item is! Map) continue;
    final name = item['name'];
    final url = item['browser_download_url'];
    if (name is String && url is String) names[name] = url;
  }
  if (os == 'windows') {
    final exe = names.entries.where((e) => e.key.endsWith('.exe')).map((e) => e.value).firstOrNull;
    return exe ?? names.entries.where((e) => e.key.endsWith('.zip')).map((e) => e.value).firstOrNull;
  }
  if (os == 'macos') {
    final marker = arch == 'arm64' ? 'arm64' : 'x86_64';
    return names.entries.where((e) => e.key.endsWith('.dmg') && e.key.contains(marker)).map((e) => e.value).firstOrNull;
  }
  return null;
}

String hostOs() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.linux => 'linux',
    _ => 'other',
  };
}

/// Like [lookForUpdate] but throws when GitHub cannot be asked, so "up to date" and "could not check" differ.
Future<UpdateOffer?> fetchUpdate(String localVersion, {http.Client? client}) async {
  final own = client == null;
  final http.Client c = client ?? http.Client();
  try {
    final res = await c.get(Uri.parse(releaseApi), headers: const {'user-agent': 'zaevis', 'accept': 'application/vnd.github+json'});
    if (res.statusCode != 200) throw StateError(l10nNow.updateGithubStatus(res.statusCode));
    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) throw StateError(l10nNow.updateBadRelease);
    return offerFromRelease(localVersion, body, os: hostOs(), arch: hostArch());
  } finally {
    if (own) c.close();
  }
}

/// Update state shared by the corner card and the settings page: one check, one download.
class UpdateController extends ChangeNotifier {
  UpdateController({this.localVersion, this.install, Future<UpdateOffer?> Function(String local)? fetch}) : _fetch = fetch ?? ((v) => fetchUpdate(v));

  /// The bundled VERSION; null in development and on the web, where nothing is checked.
  final String? localVersion;

  /// Downloads and installs (Backend.installUpdate); null where the app cannot replace itself.
  final Future<void> Function(String url, void Function(double? progress) onProgress)? install;
  final Future<UpdateOffer?> Function(String local) _fetch;

  AppBuild? get local => localVersion == null ? null : parseBuild(localVersion!);
  UpdateOffer? offer;
  UpdatePhase phase = UpdatePhase.idle;
  double? progress;
  String? error;
  String? checkError;
  bool checking = false;
  DateTime? checkedAt;

  /// The corner card was closed; the settings page still offers the update.
  bool dismissed = false;

  Future<void> check() async {
    final v = localVersion;
    if (v == null || checking) return;
    checking = true;
    checkError = null;
    notifyListeners();
    try {
      offer = await _fetch(v);
    } catch (e) {
      checkError = e.toString().replaceFirst(RegExp(r'^(StateError|Exception|ClientException): ?'), '');
    } finally {
      checking = false;
      checkedAt = DateTime.now();
      notifyListeners();
    }
  }

  void dismiss() {
    dismissed = true;
    notifyListeners();
  }

  Future<void> apply() async {
    final url = offer?.downloadUrl;
    final run = install;
    if (url == null || run == null || phase != UpdatePhase.idle) return;
    phase = UpdatePhase.downloading;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      await run(url, (p) {
        if (p == null) {
          phase = UpdatePhase.installing;
          progress = null;
        } else {
          progress = p;
        }
        notifyListeners();
      });
    } catch (e) {
      phase = UpdatePhase.idle;
      error = e.toString().replaceFirst(RegExp(r'^(StateError|Exception): '), '');
      notifyListeners();
    }
  }
}

Future<UpdateOffer?> lookForUpdate(String localVersion, {http.Client? client}) async {
  final own = client == null;
  final http.Client c = client ?? http.Client();
  try {
    final res = await c.get(Uri.parse(releaseApi), headers: const {'user-agent': 'zaevis', 'accept': 'application/vnd.github+json'});
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) return null;
    return offerFromRelease(localVersion, body, os: hostOs(), arch: hostArch());
  } catch (_) {
    return null;
  } finally {
    if (own) c.close();
  }
}

/// Idle, receiving the installer, or replacing the app.
enum UpdatePhase { idle, downloading, installing }

/// Corner card for a newer release: one line with the update button. Small, since the user may not update.
/// The in-app install clears the macOS quarantine itself, so there is no "damaged app" guide here; if that
/// step fails, the error says what to run.
class UpdateNotice extends StatelessWidget {
  const UpdateNotice({
    super.key,
    required this.offer,
    required this.onLater,
    required this.onUpdate,
    this.phase = UpdatePhase.idle,
    this.progress,
    this.error,
  });
  final UpdateOffer offer;
  final VoidCallback onLater;
  final VoidCallback onUpdate;
  final UpdatePhase phase;
  /// 0..1 while [phase] is [UpdatePhase.downloading]. Negative means the length is unknown.
  final double? progress;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final download = offer.downloadUrl != null;
    final busy = phase != UpdatePhase.idle;
    final known = progress != null && progress! >= 0;
    final l = context.l10n;
    final card = Material(
      color: scheme.surfaceContainerLowest,
      elevation: 3,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        // as wide as its line, not the 300 the progress and error lines may take
        child: IntrinsicWidth(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.system_update_alt, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Flexible(child: Tooltip(message: '${offer.local.label} → ${offer.remote.label}', child: Text(l.updateAvailable, style: t.bodyMedium))),
                if (download && !busy) ...[
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: onUpdate,
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)),
                    child: Text(l.updateButton),
                  ),
                ] else
                  const SizedBox(width: 6),
              ]),
              if (phase == UpdatePhase.downloading) ...[
                const SizedBox(height: 4),
                LinearProgressIndicator(value: known ? progress : null),
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 2),
                  child: Text(known ? l.updateDownloadingPercent((progress! * 100).round()) : l.updateDownloading, style: t.bodySmall),
                ),
              ] else if (phase == UpdatePhase.installing)
                Text(l.updateInstalling, style: t.bodySmall)
              else if (!download)
                Text(l.updateNoInstaller, style: t.bodySmall),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 2),
                  child: SelectableText(error!, style: t.bodySmall?.copyWith(color: scheme.error), minLines: 1),
                ),
            ]),
          ),
        ),
      ),
    );
    if (busy) return card;
    // the close button sits on the card's corner, outside the content; the padding keeps it inside the hit area
    return Stack(clipBehavior: Clip.none, children: [
      Padding(padding: const EdgeInsets.only(top: 8, right: 8), child: card),
      Positioned(
        top: 0,
        right: 0,
        child: Tooltip(
          message: l.updateLater,
          child: Material(
            color: scheme.surfaceContainerLowest,
            shape: CircleBorder(side: BorderSide(color: scheme.outlineVariant)),
            elevation: 2,
            shadowColor: Colors.black26,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onLater,
              child: SizedBox(width: 20, height: 20, child: Icon(Icons.close, size: 12, color: scheme.onSurfaceVariant)),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Corner card for the macOS folder prompts the 18:30 scan used to raise one by one.
class AccessNotice extends StatelessWidget {
  const AccessNotice({super.key, required this.onApply});
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final l = context.l10n;
    return Material(
      color: scheme.surfaceContainerLowest,
      elevation: 3,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(Icons.notifications_none, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text(l.updateNotice, style: t.labelMedium?.copyWith(color: scheme.primary)),
            ]),
            const SizedBox(height: 6),
            Text(l.updateFolderTitle, style: t.titleSmall),
            const SizedBox(height: 4),
            Text(l.updateFolderBody, style: t.bodySmall),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: onApply, child: Text(l.updateFolderApply)),
            ),
          ]),
        ),
      ),
    );
  }
}
