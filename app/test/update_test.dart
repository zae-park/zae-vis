import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaevis/update.dart';

void main() {
  test('a later build of the same version is newer, an older one is not', () {
    final local = parseBuild('0.1.0+20261029120000')!;
    expect(isNewer(local, parseBuild('0.1.0+20261029120000')!), isFalse);
    expect(isNewer(local, parseBuild('0.1.0+20261029130000')!), isTrue);
    expect(isNewer(local, parseBuild('0.1.0+20261029110000')!), isFalse);
    expect(isNewer(local, parseBuild('0.1.1+1')!), isTrue);
    expect(isNewer(parseBuild('0.1.1+1')!, local), isFalse);
  });

  test('release body version and the matching installer are offered', () {
    final offer = offerFromRelease('0.1.0+20261029120000', {
      'tag_name': 'v0.1.0',
      'body': 'version: 0.1.0+20261029140000\n',
      'assets': [
        {'name': 'zaevis-0.1.0-arm64.dmg', 'browser_download_url': 'https://example/arm.dmg'},
        {'name': 'zaevis-0.1.0-win-x64.zip', 'browser_download_url': 'https://example/win.zip'},
      ],
    }, os: 'macos', arch: 'arm64');
    expect(offer, isNotNull);
    expect(offer!.remote.label, '0.1.0+20261029140000');
    expect(offer.downloadUrl, 'https://example/arm.dmg');
  });

  test('windows offers the installer exe', () {
    final offer = offerFromRelease('0.1.0+1', {
      'tag_name': 'v0.1.0',
      'body': 'version: 0.1.0+2\n',
      'assets': [
        {'name': 'zaevis-0.1.0-win-x64.zip', 'browser_download_url': 'https://example/win.zip'},
        {'name': 'zaevis-0.1.0-win-x64.exe', 'browser_download_url': 'https://example/win.exe'},
      ],
    }, os: 'windows', arch: 'x64');
    expect(offer!.downloadUrl, 'https://example/win.exe');
  });

  test('the same build and the wrong OS installer are not offered', () {
    final same = offerFromRelease('0.1.0+20261029140000', {
      'tag_name': 'v0.1.0',
      'body': 'version: 0.1.0+20261029140000\n',
      'assets': [
        {'name': 'zaevis-0.1.0-arm64.dmg', 'browser_download_url': 'https://example/arm.dmg'},
      ],
    }, os: 'macos', arch: 'arm64');
    expect(same, isNull);

    final intel = offerFromRelease('0.1.0+1', {
      'tag_name': 'v0.1.0',
      'body': 'version: 0.1.0+2\n',
      'assets': [
        {'name': 'zaevis-0.1.0-arm64.dmg', 'browser_download_url': 'https://example/arm.dmg'},
      ],
    }, os: 'macos', arch: 'x64');
    expect(intel, isNotNull);
    expect(intel!.downloadUrl, isNull);
  });

  testWidgets('a newer release is a corner card the user can dismiss or update', (tester) async {
    var updated = false;
    var later = false;
    final offer = UpdateOffer(local: parseBuild('0.1.0+1')!, remote: parseBuild('0.1.0+2')!, downloadUrl: 'https://example/arm.dmg');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Align(alignment: Alignment.topRight, child: UpdateNotice(offer: offer, onLater: () => later = true, onUpdate: () => updated = true))),
    ));
    expect(find.text('알림'), findsOneWidget);
    expect(find.text('새 버전이 있습니다'), findsOneWidget);
    expect(find.textContaining('0.1.0+2'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.text('업데이트'));
    await tester.pump();
    expect(updated, isTrue);

    await tester.tap(find.byTooltip('나중에'));
    await tester.pump();
    expect(later, isTrue);
  });

  testWidgets('download progress replaces the update button', (tester) async {
    final offer = UpdateOffer(local: parseBuild('0.1.0+1')!, remote: parseBuild('0.1.0+2')!, downloadUrl: 'https://example/arm.dmg');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: UpdateNotice(offer: offer, phase: UpdatePhase.downloading, progress: 0.4, onLater: () {}, onUpdate: () {})),
    ));
    expect(find.text('받는 중 40%'), findsOneWidget);
    expect(find.text('업데이트'), findsNothing);
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
  });
}
