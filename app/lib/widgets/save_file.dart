import 'package:flutter/material.dart';

import '../api.dart';
import '../download.dart';
import '../l10n/l10n.dart';
import 'input_dialogs.dart';

/// Saves the worklog file at [path] (save dialog on the desktop, browser download on the web) and says where it went.
Future<void> saveWorklogFile(BuildContext context, WorklogApi api, String path) async {
  try {
    final dest = await Downloads.save(api, path);
    if (dest != null && context.mounted) toast(context, context.l10n.uiSavedTo(dest));
  } catch (e) {
    if (context.mounted) toast(context, context.l10n.uiSaveFailed('${e is ApiException ? e.message : e}'), error: true);
  }
}
