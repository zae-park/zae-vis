import 'dart:io';

import 'package:file_picker/file_picker.dart';

import 'api.dart';

/// Asks where to save (starting in ~/Downloads), then writes the server's bytes there unchanged.
Future<String?> saveWorklogFile(WorklogApi api, String path) async {
  final name = path.split('/').last;
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  final downloads = home == null ? null : '$home${Platform.pathSeparator}Downloads';
  final dest = await FilePicker.platform.saveFile(
    dialogTitle: '파일 저장',
    fileName: name,
    initialDirectory: downloads != null && Directory(downloads).existsSync() ? downloads : null,
  );
  if (dest == null) return null;
  final bytes = await api.downloadBytes(path);
  await File(dest).writeAsBytes(bytes, flush: true);
  return dest;
}
