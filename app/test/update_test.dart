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
}
