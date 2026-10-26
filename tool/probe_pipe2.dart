import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Builds a Discord IPC frame: op(4 LE) + len(4 LE) + json payload.
Uint8List frame(int op, Map<String, dynamic> payload) {
  final body = utf8.encode(json.encode(payload));
  final out = BytesBuilder();
  final b = ByteData(8)..setUint32(0, op, Endian.little)..setUint32(4, body.length, Endian.little);
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

/// Reads whatever is pending (best effort, non-blocking-ish).
Future<int> drain(RandomAccessFile raf) async {
  try {
    final len = await raf.length();
    if (len > 0) {
      final data = await raf.read(len);
      print('   [read $len bytes: ${utf8.decode(data, allowMalformed: true).substring(0, len.clamp(0, 120))}...]');
      return len;
    }
  } catch (e) {
    print('   [read error: $e]');
  }
  return 0;
}

/// arg: 'noread' skips reading between writes; 'read' drains between writes.
Future<void> main(List<String> args) async {
  final mode = args.isNotEmpty ? args[0] : 'read';
  final raf = await openPipe();
  if (raf == null) {
    print('no pipe');
    exit(1);
  }
  print('pipe open (mode=$mode)');

  // Handshake: op 1 = HANDSHAKE... actually Discord: op0=frame? Spec:
  // op 0 = Frame, 1 = Close, 2 = Ping, 3 = Pong. Handshake payload is sent
  // with op 0? No — handshake is its own op... The package uses OPCodes:
  // let's mimic the package exactly: handshake sent with OPCodes.handshake.
  // From the package constants: handshake op = 0? We'll send what the package
  // sends: {'v': 1, 'client_id': ...} with op = 0 (frame) — the package's
  // OPCodes.handshake is 0 (checked below at runtime).
  try {
    raf.writeFromSync(frame(0, {'v': 1, 'client_id': '1544148748584615987'}));
    print('handshake write OK');
  } catch (e) {
    print('handshake write FAILED: $e');
    exit(1);
  }

  for (var i = 1; i <= 4; i++) {
    if (mode == 'read') await drain(raf);
    await Future.delayed(const Duration(milliseconds: 200));
    try {
      raf.writeFromSync(frame(1, {
        'cmd': 'SET_ACTIVITY',
        'args': {
          'pid': pid,
          'activity': {
            'name': 'Velqi',
            'details': 'Probe song $i',
            'state': 'Probe artist',
            'type': 2,
            'timestamps': {'start': DateTime.now().millisecondsSinceEpoch},
          }
        },
        'nonce': 'n$i',
      }));
      print('SET_ACTIVITY #$i write OK');
    } catch (e) {
      print('SET_ACTIVITY #$i write FAILED: $e');
      break;
    }
  }
  if (mode == 'read') await drain(raf);
  await raf.close();
  print('done');
  exit(0);
}
