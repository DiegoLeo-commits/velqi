// Probe: replicate the app's chunked download with dio.
// Run: dart run tool/probe_download.dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:velqi/services/stream_service.dart';

const _chunkSize = 2 * 1024 * 1024;
const _ua =
    'com.google.android.youtube/20.01.35 (Linux; U; Android 13) gzip';

Future<void> main() async {
  final dio = Dio();
  // Download path: fetch WITHOUT platform (android-style list: adaptive first)
  final r = await StreamProvider.fetch('1ywXRvrxll4');
  print('playable=${r.playable} formats=${r.audioFormats?.length}');
  final chosen = r.highestBitrateMp4aAudio ?? r.highestQualityAudio;
  print('chosen itag=${chosen?.itag} codec=${chosen?.audioCodec} '
      'size=${chosen?.size} urlLen=${chosen?.url.length}');

  final file = File('chunk_test.bin');
  if (await file.exists()) await file.delete();
  final raf = await file.open(mode: FileMode.writeOnlyAppend);
  var downloaded = 0;
  try {
    while (true) {
      final end = downloaded + _chunkSize - 1;
      print('GET Range: bytes=$downloaded-$end');
      final res = await dio.get<List<int>>(
        chosen!.url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Range': 'bytes=$downloaded-$end', 'User-Agent': _ua},
        ),
      );
      final data = res.data ?? const <int>[];
      print('  status=${res.statusCode} bytes=${data.length} '
          'content-range=${res.headers.value('content-range')} '
          'content-length=${res.headers.value('content-length')}');
      if (data.isEmpty) break;
      await raf.writeFrom(data);
      downloaded += data.length;
      if (data.length < _chunkSize) break;
      if (downloaded > 6 * 1024 * 1024) break; // safety cap for probe
    }
    print('TOTAL downloaded=$downloaded');
  } catch (e) {
    print('DOWNLOAD ERROR: $e');
  } finally {
    await raf.close();
  }
  await file.delete();
  dio.close();
}
