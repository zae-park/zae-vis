import 'backend.dart';

class _WebBackend implements Backend {
  @override
  bool get managed => false;
  @override
  String? get buildVersion => null;
  @override
  String? get problem => null;
  @override
  String get home => '';
  @override
  bool get isConfigured => true;
  @override
  Stream<String> run(List<String> args) => Stream<String>.error(UnsupportedError('브라우저에서는 실행할 수 없습니다'));
  @override
  Future<void> ensureServer() async {}
  @override
  Future<void> open(String target) async {}
}

Backend createBackend() => _WebBackend();
