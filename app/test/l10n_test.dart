import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaevis/l10n/l10n.dart';

void main() {
  test('a chosen language wins; system follows the first Korean or English OS language, else English', () {
    expect(resolveAppLocale('en', const [Locale('ko', 'KR')]), const Locale('en'));
    expect(resolveAppLocale('ko', const [Locale('en', 'US')]), const Locale('ko'));
    expect(resolveAppLocale('system', const [Locale('ko', 'KR')]), const Locale('ko'));
    expect(resolveAppLocale('system', const [Locale('ja'), Locale('en', 'GB')]), const Locale('en'));
    expect(resolveAppLocale('system', const [Locale('ja')]), const Locale('en'));
    expect(resolveAppLocale('system', const []), const Locale('ko'));
  });

  test('both languages carry every key', () {
    final ko = lookupAppLocalizations(const Locale('ko'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(ko.settingsLanguage, '화면 언어');
    expect(en.settingsLanguage, 'Display language');
  });
}
