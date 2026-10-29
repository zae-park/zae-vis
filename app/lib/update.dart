import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'update_arch_stub.dart' if (dart.library.io) 'update_arch_io.dart';

const releaseApi = 'https://api.github.com/repos/zae-park/zae-vis/releases/latest';

class AppBuild {
  const AppBuild(this.semver, this.build);
  final List<int> semver;
  final int build;

  String get label => '${semver.join('.')}${build > 0 ? '+$build' : ''}';
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

/// Corner card for a newer release. The update button downloads and installs it.
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
  /// 0..1 while [phase] is [UpdatePhase.downloading].
  final double? progress;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final download = offer.downloadUrl != null;
    final busy = phase != UpdatePhase.idle;
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
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(Icons.notifications_none, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text('알림', style: t.labelMedium?.copyWith(color: scheme.primary)),
              const Spacer(),
              IconButton(
                tooltip: '나중에',
                visualDensity: VisualDensity.compact,
                onPressed: busy ? null : onLater,
                icon: const Icon(Icons.close, size: 18),
              ),
            ]),
            Text('새 버전이 있습니다', style: t.titleSmall),
            const SizedBox(height: 4),
            Text('설치된 버전 ${offer.local.label}\n최신 ${offer.remote.label}', style: t.bodySmall),
            if (error != null) ...[
              const SizedBox(height: 6),
              Text(error!, style: t.bodySmall?.copyWith(color: scheme.error)),
            ],
            const SizedBox(height: 10),
            if (phase == UpdatePhase.downloading)
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 4),
                Text('받는 중 ${((progress ?? 0) * 100).round()}%', style: t.bodySmall),
              ])
            else if (phase == UpdatePhase.installing)
              Text('설치하는 중… 끝나면 앱이 다시 열립니다.', style: t.bodySmall)
            else
              Align(
                alignment: Alignment.centerRight,
                child: download
                    ? FilledButton(onPressed: onUpdate, child: const Text('업데이트'))
                    : Text('이 기종용 설치 파일이 없습니다', style: t.bodySmall),
              ),
          ]),
        ),
      ),
    );
  }
}
