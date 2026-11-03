import '../l10n/l10n.dart';
import 'backend.dart';

class _WebBackend implements Backend {
  @override
  bool get managed => false;
  @override
  String? get buildVersion => null;
  @override
  DateTime? get installedAt => null;
  @override
  String? get problem => null;
  @override
  String get home => '';
  @override
  bool get isConfigured => true;
  @override
  Stream<String> run(List<String> args) => Stream<String>.error(UnsupportedError(l10nNow.backendWebNoRun));
  @override
  Future<void> ensureServer() async {}
  @override
  Future<void> open(String target) async {}
  @override
  Future<void> installUpdate(String url, void Function(double? progress) onProgress) async {
    throw UnsupportedError(l10nNow.backendWebNoUpdate);
  }
}

Backend createBackend() => _WebBackend();
