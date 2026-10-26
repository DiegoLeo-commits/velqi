import 'dart:math' as math;

import 'package:media_kit/media_kit.dart';

/// Decisive probe: does the bundled mpv (v0.36.0-403) expose real audio
/// filter metadata through `af-metadata`? Loads a generated WAV with bass
/// kicks and prints every af-metadata event + direct reads.
Future<void> main() async {
  final dll = 'C:/Users/Usuario/Desktop/Projects/Velqi-Music-App/build/windows/x64/libmpv/libmpv-2.dll';
  MediaKit.ensureInitialized(libmpv: dll);

  final player = Player();
  final np = player.platform;
  if (np is! NativePlayer) {
    print('platform is not NativePlayer');
    return;
  }

  final version = await np.getProperty('mpv-version');
  print('mpv: $version');

  try {
    await np.setProperty(
      'af',
      'lavfi=[astats=metadata=1:reset=1:measure_perchannel=none]',
    );
    final afBack = await np.getProperty('af');
    print('AF property now = "$afBack"');
  } catch (e) {
    print('setProperty(af) FAILED: $e');
  }

  var n = 0;
  await np.observeProperty('af-metadata', (v) async {
    n++;
    if (n <= 10) {
      final s = v.length > 160 ? v.substring(0, 160) : v;
      print('AFMETA event #$n: "$s"');
    }
  });

  await player.open(
    Media('file:///C:/Users/Usuario/Desktop/Projects/Velqi-Music-App/test_beat.wav'),
    play: true,
  );
  await Future<void>.delayed(const Duration(seconds: 6));

  try {
    final direct = await np.getProperty('af-metadata');
    print('AFMETA direct read (${direct.length} chars): "${direct.substring(0, direct.length.clamp(0, 220))}"');
  } catch (e) {
    print('direct read failed: $e');
  }

  print('TOTAL events: $n');
  await player.dispose();
}
