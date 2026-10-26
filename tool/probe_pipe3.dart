import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Probe v3: decides HOW to read Discord replies safely.
/// Variant A: direct `read(4096)` after each write (NO length() polling).
/// All frames are activity:null clears — invisible on the Discord profile.
Uint8List frame(int op, Map<String, dynamic> payload) {
  final body = utf8.encode(json.encode(payload));
  final out = BytesBuilder();
  final b = ByteData(8)
    ..setUint32(0, op, Endian.little)
    ..setUint32(4, body.length, Endian.little);
  out.add(b.buffer.asUint8List());
  out.add(body);
  return out.toBytes();
}

Future<RandomAccessFile?> openPipe() async {
  for (var i = 0; i < 10; i++) {
    try {
      return await File('\\\\?\\pipe\\discord-ipc-$i').open(mode: FileMode.write);
    } catch (_) {}
  }
  return null;
}

Future<Map<String, dynamic>?> readFrame(RandomAccessFile raf) async {
  final data = await raf.read(4096);
  if (data.isEmpty) return null;
  final bd = ByteData.sublistView(data);
  final op = bd.getUint32(0, Endian.little);
  final len = bd.getUint32(4, Endian.little);
  final body =
      utf8.decode(data.sublist(8, (8 + len).clamp(8, data.length)), allowMalformed: true);
  print('   [read op=$op len=$len] ${body.substring(0, body.length.clamp(0, 90))}');
  try {
    return jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

Future<void> main() async {
  final raf = await openPipe();
  if (raf == null) {
    print('no pipe');
    exit(1);
  }
  print('pipe open');

  // 1) handshake
  try {
    raf.writeFromSync(frame(0, {'v': 1, 'client_id': '1544148748584615987'}));
    print('handshake write OK');
  } catch (e) {
    print('handshake write FAILED: $e');
    exit(1);
  }

  Map<String, dynamic>? reply;
  try {
    reply = await readFrame(raf);
  } catch (e) {
    print('handshake read FAILED: $e');
  }

  // 2) N clear cycles: write clear -> direct read
  var okWrites = 0, okReads = 0, failWrites = 0, failReads = 0;
  for (var i = 1; i <= 12; i++) {
    await Future.delayed(const Duration(milliseconds: 300));
    try {
      raf.writeFromSync(frame(1, {
        'cmd': 'SET_ACTIVITY',
        'args': {'pid': pid, 'activity': null},
        'nonce': 'n$i',
      }));
      okWrites++;
    } catch (e) {
      failWrites++;
      print('cycle $i: write FAILED (errno? ${e.toString().substring(0, e.toString().length.clamp(0, 80))})');
      break;
    }
    try {
      final r = await readFrame(raf);
      if (r != null) okReads++;
    } catch (e) {
      failReads++;
      print('cycle $i: read FAILED: ${e.toString().substring(0, e.toString().length.clamp(0, 80))}');
    }
  }
  print('RESULT writes ok=$okWrites fail=$failWrites | reads ok=$okReads fail=$failReads');
  try {
    raf.closeSync();
  } catch (_) {}
  exit(0);
}
