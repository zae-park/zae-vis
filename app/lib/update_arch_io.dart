import 'dart:ffi';

String hostArch() {
  final abi = Abi.current();
  if (abi == Abi.macosArm64 || abi == Abi.linuxArm64) return 'arm64';
  return 'x64';
}
