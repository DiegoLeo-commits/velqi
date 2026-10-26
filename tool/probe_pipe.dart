import 'dart:io';

/// Raw probe: open the Discord named pipe and try sequential writes the way
/// the package does, printing the exact OS error for each step.
Future<void> main() async {
  String? pipePath;
  RandomAccessFile? raf;
  for (var i = 0; i < 10; i++) {
    final p = '\\\\?\\pipe\\discord-ipc-$i';
    try {
      raf = await File(p).open(mode: FileMode.write);
      pipePath = p;
      break;
    } catch (_) {}
  }
  print('pipe: $pipePath');
  if (pipePath == null || raf == null) exit(1);

  try {
    raf.writeFromSync([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    print('write1 ok');
  } catch (e) {
    print('write1 FAILED: $e');
  }
  try {
    final pos = await raf.position().catchError((e) => -1);
    print('position after write1: $pos');
    raf.writeFromSync([11, 12, 13, 14, 15]);
    print('write2 ok');
  } catch (e) {
    print('write2 FAILED: $e');
  }
  try {
    print('length: ${await raf.length().catchError((e) => -1)}');
  } catch (e) {
    print('length FAILED: $e');
  }
  await raf.close();
  print('done');
  exit(0);
}
