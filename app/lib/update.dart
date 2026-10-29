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
    return names.entries.where((e) => e.key.endsWith('.zip')).map((e) => e.value).firstOrNull;
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

Future<bool> showUpdateDialog(BuildContext context, UpdateOffer offer) async {
  final download = offer.downloadUrl != null;
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('새 버전이 있습니다'),
      content: Text('설치된 버전은 ${offer.local.label}이고, 최신은 ${offer.remote.label}입니다.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('나중에')),
        if (download) FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('받기')),
      ],
    ),
  );
  return go ?? false;
}
