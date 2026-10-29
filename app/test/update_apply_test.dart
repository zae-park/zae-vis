import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zaevis/update_apply.dart';

void main() {
  test('the running macOS bundle is the .app above Contents', () {
    final sep = Platform.pathSeparator;
    expect(macAppBundle(['', 'Applications', 'zaevis.app', 'Contents', 'MacOS', 'zaevis'].join(sep)), '${sep}Applications${sep}zaevis.app');
    expect(macAppBundle(['', 'tmp', 'flutter'].join(sep)), isNull);
  });

  test('a mounted image yields its app bundle', () {
    final root = Directory.systemTemp.createTempSync('zv-mount-');
    Directory('${root.path}${Platform.pathSeparator}zaevis.app').createSync();
    expect(appInMount(root)?.path, endsWith('zaevis.app'));
    root.deleteSync(recursive: true);
  });

  test('mac update copies the app out of the image and clears quarantine', () async {
    final root = Directory.systemTemp.createTempSync('zv-upd-');
    final dmg = File('${root.path}${Platform.pathSeparator}a.dmg')..writeAsStringSync('x');
    final bundle = '${root.path}${Platform.pathSeparator}zaevis.app';
    Directory(bundle).createSync();
    final calls = <String>[];
    await installMacDmg(
      dmg: dmg,
      appBundle: bundle,
      run: (exe, args) async {
        calls.add('$exe ${args.join(' ')}');
        if (exe == 'hdiutil' && args.first == 'attach') {
          Directory('${args.last}${Platform.pathSeparator}zaevis.app').createSync();
        }
        return ProcessResult(0, 0, '', '');
      },
    );
    expect(calls.any((c) => c.startsWith('ditto ') && c.endsWith(bundle)), isTrue);
    expect(calls.any((c) => c.contains('com.apple.quarantine') && c.endsWith(bundle)), isTrue);
    expect(calls.last, startsWith('hdiutil detach '));
    root.deleteSync(recursive: true);
  });
}
