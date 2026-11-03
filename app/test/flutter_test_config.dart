import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

/// Every test runs with a Korean system language, so "system" resolves to Korean and the tests can find Korean text.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  binding.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
  binding.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
  await testMain();
}
