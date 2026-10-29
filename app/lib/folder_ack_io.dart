import 'dart:io';

/// Marker written when the user accepts leaving macOS privacy folders out of the repo scan.
File _marker(String home) => File('$home${Platform.pathSeparator}.zaevis${Platform.pathSeparator}folder-access.ack');

bool folderSkipAcked(String home) => home.isNotEmpty && _marker(home).existsSync();

Future<void> ackFolderSkip(String home) async {
  if (home.isEmpty) return;
  final file = _marker(home);
  file.parent.createSync(recursive: true);
  await file.writeAsString('skipped\n');
}
