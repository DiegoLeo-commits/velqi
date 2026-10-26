// Validates the new native extraction exactly as the app calls it.
// Run: dart run tool/probe_stream.dart
import 'package:velqi/services/stream_service.dart';

Future<void> main() async {
  print('--- StreamProvider.fetch (desktop) ---');
  final r = await StreamProvider.fetch('U-u_5mmBd9Y', platform: 'desktop');
  print('playable=${r.playable} msg=${r.statusMSG}');
  for (final f in r.audioFormats ?? []) {
    print('  itag=${f.itag} codec=${f.audioCodec} bitrate=${f.bitrate} '
        'size=${f.size} urlLen=${f.url.length}');
  }
  print('  high=${r.highestQualityAudio?.itag} '
      'mp4a=${r.highestBitrateMp4aAudio?.itag} '
      'low=${r.lowQualityAudio?.itag}');
  print('  hmStreamingData=${r.hmStreamingData}');

  print('--- StreamProvider.fetch (android) ---');
  final ra = await StreamProvider.fetch('U-u_5mmBd9Y');
  print('playable=${ra.playable} formats=${ra.audioFormats?.length} '
      'high=${ra.highestQualityAudio?.itag} '
      'opus=${ra.highestBitrateOpusAudio?.itag}');
}
