import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';

/// REAL system-audio capture on Windows via WASAPI loopback (dart:ffi).
///
/// Taps the default render endpoint's loopback — the actual mix the user is
/// hearing right now. The capture isolate downmixes the float32 stream,
/// computes an RMS per ~11.6 ms window (512 frames) and runs energy-flux
/// beat detection on the REAL energy. Batches ship to the main isolate every
/// ~40 ms.
///
/// Zero extra bandwidth (no re-download, no second decoder): it reads the
/// endpoint loopback. Device changes / invalidation trigger a clean re-init.
class WasapiLoopback {
  Isolate? _isolate;
  ReceivePort? _rx;
  bool _starting = false;
  bool _disposed = false;

  late void Function(WasapiFrame frame) onFrame;
  late void Function(int hresult, String message) onError;

  Future<void> start() async {
    if (_starting || _disposed) return;
    _starting = true;
    try {
      _rx = ReceivePort();
      _isolate = await Isolate.spawn(
        _captureEntry,
        _rx!.sendPort,
        debugName: 'wasapi-loopback',
      );
      _rx!.listen((msg) {
        if (msg is! List || msg.isEmpty) return;
        switch (msg[0] as String) {
          case 'frames':
            final rmsList = (msg[1] as List).cast<double>();
            final beatList = (msg[2] as List).cast<int>();
            for (var i = 0; i < rmsList.length; i++) {
              onFrame(WasapiFrame(rmsList[i], beatList[i] == 1));
            }
            break;
          case 'ready':
            onError(0, 'loopback capture ready: ${msg[1]} Hz, ${msg[2]} ch');
            break;
          case 'error':
            onError(msg[1] as int, msg[2] as String);
            break;
          case 'log':
            onError(0, msg[1] as String);
            break;
        }
      });
    } catch (e) {
      onError(-1, 'spawn failed: $e');
    } finally {
      _starting = false;
    }
  }

  void stop() {
    _disposed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _rx?.close();
    _rx = null;
  }
}

class WasapiFrame {
  WasapiFrame(this.level, this.isBeat);
  final double level; // linear RMS of the real output mix
  final bool isBeat;
}

// ═══════════════════════════════════════════════════════════════════════════
// Capture isolate — pure dart:ffi COM against ole32 + WASAPI.
// ═══════════════════════════════════════════════════════════════════════════

final class _Guid extends Struct {
  @Uint32()
  external int data1;
  @Uint16()
  external int data2;
  @Uint16()
  external int data3;
  @Array(8)
  external Array<Uint8> data4;
}

Pointer<_Guid> _makeGuid(String hex) {
  final g = calloc<_Guid>();
  final p = hex.replaceAll('-', '');
  g.ref.data1 = int.parse(p.substring(0, 8), radix: 16);
  g.ref.data2 = int.parse(p.substring(8, 12), radix: 16);
  g.ref.data3 = int.parse(p.substring(12, 16), radix: 16);
  for (var i = 0; i < 8; i++) {
    g.ref.data4[i] = int.parse(p.substring(16 + i * 2, 18 + i * 2), radix: 16);
  }
  return g;
}

const _clsidMMDeviceEnumerator = 'BCDE0395-E52F-467C-8E3D-C4579291692E';
const _iidIMMDeviceEnumerator = 'A95664D2-9614-4F35-A746-DE8DB63617E6';
const _iidIAudioClient = '1CB9AD4C-DBFA-4C32-B178-C2F568A703B2';
const _iidIAudioCaptureClient = 'C8ADBD64-E71E-48A0-A4DE-185C395CD317';
const _audclntEInvalidated = 0x88890004; // device changed → recapture

// ── Native signatures ────────────────────────────────────────────────────────
typedef _CoInitializeExN = Int32 Function(Pointer, Uint32);
typedef _CoInitializeExD = int Function(Pointer, int);

typedef _CoCreateInstanceN = Int32 Function(
    Pointer, Pointer, Uint32, Pointer, Pointer<Pointer<Void>>);
typedef _CoCreateInstanceD = int Function(
    Pointer, Pointer, int, Pointer, Pointer<Pointer<Void>>);

// vtable call shapes (self is always the first arg).
typedef _Hr0N = Int32 Function(Pointer);
typedef _Hr0D = int Function(Pointer);
typedef _Hr1PN = Int32 Function(Pointer, Pointer);
typedef _Hr1PD = int Function(Pointer, Pointer);
typedef _Hr2PN = Int32 Function(Pointer, Pointer, Pointer);
typedef _Hr2PD = int Function(Pointer, Pointer, Pointer);
typedef _GetDefaultEPN = Int32 Function(Pointer, Int32, Int32, Pointer);
typedef _GetDefaultEPD = int Function(Pointer, int, int, Pointer);
typedef _ActivateN = Int32 Function(
    Pointer, Pointer, Uint32, Pointer, Pointer<Pointer<Void>>);
typedef _ActivateD = int Function(
    Pointer, Pointer, int, Pointer, Pointer<Pointer<Void>>);
typedef _InitializeN = Int32 Function(
    Pointer, Int32, Uint32, Uint64, Uint64, Pointer, Pointer);
typedef _InitializeD = int Function(
    Pointer, int, int, int, int, Pointer, Pointer);
typedef _GetBufferN = Int32 Function(Pointer, Pointer<Pointer<Uint8>>,
    Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint64>, Pointer<Uint64>);
typedef _GetBufferD = int Function(Pointer, Pointer<Pointer<Uint8>>,
    Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint64>, Pointer<Uint64>);
typedef _ReleaseBufferN = Int32 Function(Pointer, Uint32);
typedef _ReleaseBufferD = int Function(Pointer, int);

/// vtable slot pointer for a COM interface (index = method ordinal - 3,
/// after the three IUnknown methods). A COM object's FIRST 8 bytes are a
/// pointer TO its vtable — dereference that, then index the vtable array.
Pointer<NativeFunction<T>> _slot<T extends Function>(Pointer<Void> obj, int index) {
  final vtable = obj.cast<Pointer<Pointer<NativeFunction<T>>>>().value;
  return vtable[index];
}

Future<void> _captureEntry(SendPort out) async {
  final ole32 = DynamicLibrary.open('ole32.dll');
  final coInitialize =
      ole32.lookupFunction<_CoInitializeExN, _CoInitializeExD>('CoInitializeEx');
  final coCreate =
      ole32.lookupFunction<_CoCreateInstanceN, _CoCreateInstanceD>('CoCreateInstance');

  final hrInit = coInitialize(nullptr, 0); // COINIT_MULTITHREADED
  if (hrInit != 0 && hrInit != 1 && hrInit != 0x80010106) {
    out.send(['error', hrInit, 'CoInitializeEx failed']);
    return;
  }

  var attempt = 0;
  while (attempt < 8) {
    attempt++;
    final ok = await _captureSession(out, coCreate);
    if (ok) attempt = 0;
    out.send(['log', 'capture session ended — restarting in 2.5 s']);
    await Future<void>.delayed(const Duration(milliseconds: 2500));
  }
  out.send(['error', -1, 'capture gave up after repeated failures']);
}

/// One capture session. Returns false when the device was invalidated / a
/// setup step failed (caller retries), true when stopped cleanly.
Future<bool> _captureSession(SendPort out, _CoCreateInstanceD coCreate) async {
  final clsidEnum = _makeGuid(_clsidMMDeviceEnumerator);
  final iidEnum = _makeGuid(_iidIMMDeviceEnumerator);
  final iidAudioClient = _makeGuid(_iidIAudioClient);
  final iidCapture = _makeGuid(_iidIAudioCaptureClient);

  final enumerator = calloc<Pointer<Void>>();
  var hr = coCreate(clsidEnum.cast(), nullptr, 0x17, iidEnum.cast(), enumerator);
  if (hr != 0) {
    out.send(['error', hr, 'CoCreateInstance(MMDeviceEnumerator) failed']);
    return false;
  }
  final devEnum = enumerator.value;

  // GetDefaultAudioEndpoint(eRender=0, eConsole=0)
  final device = calloc<Pointer<Void>>();
  hr = _slot<_GetDefaultEPN>(devEnum, 4).asFunction<_GetDefaultEPD>()(
      devEnum, 0, 0, device);
  if (hr != 0) {
    out.send(['error', hr, 'GetDefaultAudioEndpoint failed']);
    return false;
  }
  final immDevice = device.value;

  // IMMDevice::Activate(IID_IAudioClient, CLSCTX_ALL, NULL, &ac)
  final acPtr = calloc<Pointer<Void>>();
  hr = _slot<_ActivateN>(immDevice, 3).asFunction<_ActivateD>()(
      immDevice, iidAudioClient.cast(), 0x17, nullptr, acPtr);
  if (hr != 0) {
    out.send(['error', hr, 'IMMDevice::Activate failed']);
    return false;
  }
  final audioClient = acPtr.value;

  // GetMixFormat
  final fmtPtr = calloc<Pointer<Void>>();
  hr = _slot<_Hr1PN>(audioClient, 8).asFunction<_Hr1PD>()(audioClient, fmtPtr);
  if (hr != 0) {
    out.send(['error', hr, 'GetMixFormat failed']);
    return false;
  }
  final wfx = fmtPtr.value;
  final wfxBytes = wfx.cast<Uint8>().asTypedList(40);
  final channels = wfxBytes[2] | (wfxBytes[3] << 8);
  final rate = wfxBytes[4] |
      (wfxBytes[5] << 8) |
      (wfxBytes[6] << 16) |
      (wfxBytes[7] << 24);
  final bits = wfxBytes[14] | (wfxBytes[15] << 8);
  if (bits != 32) {
    out.send(['error', hr, 'mix format is ${bits}-bit (expected float32)']);
    return false;
  }
  out.send(['ready', rate, channels]);

  // Initialize(SHARED=0, LOOPBACK=0x00020000, 100 ms buffer, 0 periodicity)
  hr = _slot<_InitializeN>(audioClient, 3).asFunction<_InitializeD>()(
    audioClient,
    0, // AUDCLNT_SHAREMODE_SHARED
    0x00020000, // AUDCLNT_STREAMFLAGS_LOOPBACK
    1000000, // 100 ms in 100 ns units
    0, // periodicity
    wfx,
    nullptr, // session guid
  );
  if (hr != 0) {
    out.send(['error', hr, 'IAudioClient::Initialize failed']);
    return false;
  }

  // GetService(IID_IAudioCaptureClient)
  final ccPtr = calloc<Pointer<Void>>();
  hr = _slot<_Hr2PN>(audioClient, 14).asFunction<_Hr2PD>()(
      audioClient, iidCapture.cast(), ccPtr);
  if (hr != 0) {
    out.send(['error', hr, 'IAudioClient::GetService(CaptureClient) failed']);
    return false;
  }
  final capture = ccPtr.value;

  // Start
  hr = _slot<_Hr0N>(audioClient, 10).asFunction<_Hr0D>()(audioClient);
  if (hr != 0) {
    out.send(['error', hr, 'IAudioClient::Start failed']);
    return false;
  }

  // ── Capture loop ──────────────────────────────────────────────────────────
  final pktSize = calloc<Uint32>();
  final dataPtr = calloc<Pointer<Uint8>>();
  final frames = calloc<Uint32>();
  final flags = calloc<Uint32>();
  final devPos = calloc<Uint64>();
  final qpc = calloc<Uint64>();

  final List<double> batchRms = [];
  final List<int> batchBeat = [];
  var batchSince = DateTime.now();

  // Beat detector state (REAL energy flux).
  var avgEnergy = 0.0;
  var lastBeat = DateTime.fromMillisecondsSinceEpoch(0);
  const windowFrames = 512; // ≈11.6 ms @ 44.1 kHz
  var accCount = 0;
  var accSq = 0.0;

  void flushBatch() {
    if (batchRms.isEmpty) return;
    out.send(['frames', List<double>.of(batchRms), List<int>.of(batchBeat)]);
    batchRms.clear();
    batchBeat.clear();
    batchSince = DateTime.now();
  }

  while (true) {
    hr = _slot<_Hr1PN>(capture, 5).asFunction<_Hr1PD>()(capture, pktSize);
    if (hr != 0) break;

    if (pktSize.value == 0) {
      if (DateTime.now().difference(batchSince).inMilliseconds >= 40) {
        flushBatch();
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
      continue;
    }

    hr = _slot<_GetBufferN>(capture, 3).asFunction<_GetBufferD>()(
        capture, dataPtr, frames, flags, devPos, qpc);
    if (hr != 0) break;

    final nFrames = frames.value;
    final silent = (flags.value & 0x1) != 0; // AUDCLNT_BUFFERFLAGS_SILENT

    if (!silent && nFrames > 0) {
      final samples =
          dataPtr.value.cast<Float>().asTypedList(nFrames * channels);
      for (var f = 0; f < nFrames; f++) {
        var m = 0.0;
        for (var c = 0; c < channels; c++) {
          m += samples[f * channels + c];
        }
        m /= channels;
        accSq += m * m;
        accCount++;
        if (accCount >= windowFrames) {
          final rms = math.sqrt(accSq / accCount);
          // REAL beat: energy flux over running average — sensitive enough
          // to catch vocal onsets and softer hits, not just bass kicks.
          final e = rms * rms;
          avgEnergy = avgEnergy * 0.93 + e * 0.07;
          final flux = e - avgEnergy;
          final now = DateTime.now();
          final isBeat = flux > avgEnergy * 0.26 + 0.00035 &&
              now.difference(lastBeat).inMilliseconds > 140;
          if (isBeat) lastBeat = now;
          batchRms.add(rms.clamp(0.0, 1.0));
          batchBeat.add(isBeat ? 1 : 0);
          accCount = 0;
          accSq = 0.0;
        }
      }
    } else {
      // Silence packet: feed zero-energy frames to keep the detector honest.
      for (var f = 0; f < nFrames; f += windowFrames) {
        accCount = 0;
        accSq = 0.0;
        batchRms.add(0.0);
        batchBeat.add(0);
      }
      avgEnergy *= 0.97;
    }

    hr = _slot<_ReleaseBufferN>(capture, 4)
        .asFunction<_ReleaseBufferD>()(capture, nFrames);
    if (hr != 0) break;

    if (DateTime.now().difference(batchSince).inMilliseconds >= 40) {
      flushBatch();
    }
  }

  if (hr != _audclntEInvalidated) {
    out.send(['error', hr, 'capture loop ended (hr=0x${hr.toRadixString(16)}']);
  } else {
    out.send(['log', 'device invalidated — recapturing']);
  }
  flushBatch();
  return false;
}
