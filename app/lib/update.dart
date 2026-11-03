import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'update_arch_stub.dart' if (dart.library.io) 'update_arch_io.dart';

export 'folder_ack_stub.dart' if (dart.library.io) 'folder_ack_io.dart';

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
    return Material(
      color: scheme.surfaceContainerLowest,
      elevation: 3,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.system_update_alt, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Flexible(child: Tooltip(message: '${offer.local.label} → ${offer.remote.label}', child: Text('새 버전이 있습니다', style: t.bodyMedium))),
              const SizedBox(width: 8),
              if (download && !busy)
                FilledButton(
                  onPressed: onUpdate,
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 12)),
                  child: const Text('업데이트'),
                ),
              IconButton(
                tooltip: '나중에',
                visualDensity: VisualDensity.compact,
                onPressed: busy ? null : onLater,
                icon: const Icon(Icons.close, size: 18),
              ),
            ]),
            if (phase == UpdatePhase.downloading) ...[
              LinearProgressIndicator(value: known ? progress : null),
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 2),
                child: Text(known ? '받는 중 ${(progress! * 100).round()}%' : '받는 중', style: t.bodySmall),
              ),
            ] else if (phase == UpdatePhase.installing)
              Text('설치하고 다시 여는 중…', style: t.bodySmall)
            else if (!download)
              Text('이 기종용 설치 파일이 없습니다', style: t.bodySmall),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 2),
                child: SelectableText(error!, style: t.bodySmall?.copyWith(color: scheme.error), minLines: 1),
              ),
          ]),
        ),
      ),
    );
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
              Text('알림', style: t.labelMedium?.copyWith(color: scheme.primary)),
            ]),
            const SizedBox(height: 6),
            Text('매일 18:30에 폴더 접근을 묻습니다', style: t.titleSmall),
            const SizedBox(height: 4),
            Text('데스크탑, 문서, 다운로드, 사진, 음악, 보관함을 저장소 탐색이 하나씩 열고 있습니다. 커밋을 모으는 데는 필요 없습니다.', style: t.bodySmall),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: onApply, child: const Text('한 번에 빼기')),
            ),
          ]),
        ),
      ),
    );
  }
}
