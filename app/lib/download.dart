// Saving a worklog file as it is: a save dialog and a write on the desktop, a browser download on the web.

import 'api.dart';
import 'download_stub.dart' if (dart.library.io) 'download_io.dart' if (dart.library.js_interop) 'download_web.dart' as impl;

/// Saves the worklog file at [path] where the user chooses. Returns where it went, or null when cancelled.
typedef FileSaver = Future<String?> Function(WorklogApi api, String path);

class Downloads {
  /// Tests replace this; the app uses the platform's save.
  static FileSaver save = impl.saveWorklogFile;
}
