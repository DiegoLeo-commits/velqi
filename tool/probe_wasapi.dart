import 'dart:io';

import 'package:velqi/services/wasapi_loopback.dart';

/// Standalone probe: runs the WASAPI loopback capture for ~5 s and prints
/// what it hears on the REAL system output. Play ANY music while this runs.
Future<void> main() async {
  final cap = WasapiLoopback();
  var frames = 0;
  var beats = 0;
  double maxLevel = 0;

  cap.onError = (hr, msg) => stdout.writeln('[cap hr=$hr] $msg');
  cap.onFrame = (f) {
    frames++;
    if (f.isBeat) beats++;
    if (f.level > maxLevel) maxLevel = f.level;
    if (frames % 20 == 0) {
      stdout.writeln('frame#$frames rms=${f.level.toStringAsFixed(4)} beat=${f.isBeat}');
    }
  };

  await cap.start();
  stdout.writeln('capturing system output for 5 s — play something!…');
  await Future<void>.delayed(const Duration(seconds: 5));
  cap.stop();
  stdout.writeln(
      'RESULT frames=$frames beats=$beats maxRMS=${maxLevel.toStringAsFixed(4)}');
  exit(0);
}
