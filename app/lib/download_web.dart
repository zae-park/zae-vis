import 'package:web/web.dart' as web;

import 'api.dart';

/// The server sends the file as an attachment; a link click hands it to the browser's downloads.
Future<String?> saveWorklogFile(WorklogApi api, String path) async {
  final name = path.split('/').last;
  final a = web.HTMLAnchorElement()
    ..href = api.downloadUri(path).toString()
    ..download = name;
  web.document.body?.append(a);
  a.click();
  a.remove();
  return name;
}
