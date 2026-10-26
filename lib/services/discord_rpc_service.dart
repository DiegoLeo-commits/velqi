import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:get/get.dart';

import '../utils/helper.dart';

/// Discord Rich Presence for Velqi — the Spotify-style integration.
///
/// While a song plays, the user's Discord profile shows "Listening to Velqi"
/// with the real album art, song title, artist, a live progress bar and the
/// Velqi logo. Implemented directly over Discord's local IPC pipe in pure
/// Dart — no native DLLs and no third-party transport quirks.
///
/// Design (fully live — "atado al segundo"):
///  * A 3-second heartbeat drives everything:
///    - Not connected  → probes the Discord pipe and connects (fast retry).
///    - Connected+song → re-sends the current presence verbatim (idempotent),
///      which doubles as a liveness probe.
///    - Connected+idle → re-sends `activity: null` (proper Discord clear).
///  * Any failed write marks the connection dead INSTANTLY (Discord closed →
///    the chip flips to "Sin Discord" within ≤3 s, never lies).
///  * Discord reappearing is detected within ≤3 s; if a song is loaded the
///    presence is pushed immediately.
///  * Connecting happens at app START, independent of playback — so with
///    Discord already running, Velqi is "linked" from second zero.
///
/// Notes:
///  * Desktop only. Discord's mobile clients do not expose the local RPC
///    pipe, so Android is unaffected (this service is a no-op there).
///  * The activity header ("Listening to Velqi") comes from the Discord
///    application registered with [kDiscordApplicationId].
class DiscordRpcService extends GetxService {
  _DiscordIpc? _ipc;
  bool _connecting = false;
  Timer? _heartbeatTimer;
  int _misses = 0; // consecutive "Discord absent" ticks (log throttling)

  /// Live connection state for the UI (mini player chip + Integrations page).
  final isLinked = false.obs;

  MediaItem? _song;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  /// Last activity JSON actually sent — re-sent verbatim by the heartbeat so
  /// the Discord progress bar never drifts (timestamps are absolute).
  Map<String, dynamic>? _lastPayload;

  /// Discord application id created in the Developer Portal
  /// (discord.com/developers/applications → "Velqi" → General Information).
  static const String kDiscordApplicationId = '1544148748584615987';

  /// Velqi logo shown as the small badge next to the album art.
  static const String _velqiLogoUrl = 'https://velqi.netlify.app/logo.png';

  /// Max lengths accepted by Discord for presence text fields.
  static const int _maxText = 100;

  static DiscordRpcService get instance {
    try {
      return Get.find<DiscordRpcService>();
    } catch (_) {
      return Get.put(DiscordRpcService(), permanent: true);
    }
  }

  @override
  void onInit() {
    super.onInit();
    if (!GetPlatform.isDesktop) return;
    // Background detection from app start — no song required. With Discord
    // already open, Velqi shows "linked" immediately.
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _heartbeat();
    });
    _heartbeat();
    printINFO('[DISCORD] service started — live detection every 3 s');
  }

  /// Pushes the current playback snapshot to Discord.
  ///
  /// Call on every play/pause/seek/song-change. [playing=false] keeps the
  /// card but drops the progress bar (Spotify behaves the same while paused).
  /// While Discord is absent the snapshot is queued and pushed automatically
  /// as soon as the connection is re-established.
  void update(MediaItem? song,
      {required bool playing,
      required Duration position,
      required Duration? duration}) {
    if (!GetPlatform.isDesktop) return;
    _song = song;
    _playing = playing;
    _position = position;
    _duration = duration ?? Duration.zero;

    if (song == null) {
      _lastPayload = null;
      _safeSendClear();
      return;
    }
    _lastPayload = _buildActivityJson();
    if (_ipc != null) _safeSendActivity(_lastPayload!);
    // Not connected yet → the heartbeat pushes it right after connecting.
  }

  /// Playback stopped entirely: clears the presence but KEEPS the Discord
  /// connection alive (the chip keeps telling the truth: still linked).
  void clear() {
    if (!GetPlatform.isDesktop) return;
    _song = null;
    _playing = false;
    _lastPayload = null;
    _safeSendClear();
  }

  // ── Heartbeat ──────────────────────────────────────────────────────────────

  Future<void> _heartbeat() async {
    if (!GetPlatform.isDesktop) return;
    if (_ipc == null) {
      await _tryConnect();
      return;
    }
    if (_song != null) {
      // Re-send the last payload verbatim: liveness probe + keeps Discord's
      // card fresh without touching the progress bar.
      final ok = await _safeSendActivity(_lastPayload ?? _buildActivityJson());
      if (!ok) _markDead();
    } else {
      // Idle: keep Discord's presence cleared (proper null-activity clear).
      final ok = await _safeSendClear();
      if (!ok) _markDead();
    }
  }

  Future<void> _tryConnect() async {
    if (_connecting) return;
    _connecting = true;
    try {
      final ipc = _DiscordIpc(kDiscordApplicationId);
      final opened = await ipc.open(); // fails fast when Discord is absent
      if (opened) {
        _ipc = ipc;
        _misses = 0;
        isLinked.value = true;
        printINFO('[DISCORD] connected (live detection)');
        // Push the current state right away.
        if (_song != null) {
          _lastPayload = _buildActivityJson();
          await _safeSendActivity(_lastPayload!);
        } else {
          await _safeSendClear();
        }
      } else {
        isLinked.value = false;
        _misses++;
        // Throttled log so the dlog doesn't fill with "absent" spam.
        if (_misses == 1 || _misses % 10 == 0) {
          printINFO('[DISCORD] Discord not detected yet — retrying…');
        }
      }
    } catch (e) {
      isLinked.value = false;
    } finally {
      _connecting = false;
    }
  }

  void _markDead() {
    try {
      _ipc?.close();
    } catch (_) {}
    _ipc = null;
    isLinked.value = false;
    printINFO('[DISCORD] connection lost — re-detecting…');
  }

  // ── Sends ──────────────────────────────────────────────────────────────────

  Future<bool> _safeSendActivity(Map<String, dynamic> activity) async {
    final ipc = _ipc;
    if (ipc == null) return false;
    try {
      ipc.sendFrame(1, <String, dynamic>{
        'cmd': 'SET_ACTIVITY',
        'args': <String, dynamic>{'pid': pid, 'activity': activity},
        'nonce': _nextNonce(),
      });
      await ipc.drainReplies();
      if (ipc.dead) return false;
      return true;
    } catch (e) {
      printINFO('[DISCORD] send failed: $e');
      return false;
    }
  }

  Future<bool> _safeSendClear() async {
    final ipc = _ipc;
    if (ipc == null) return false;
    try {
      ipc.sendFrame(1, <String, dynamic>{
        'cmd': 'SET_ACTIVITY',
        'args': <String, dynamic>{'pid': pid, 'activity': null},
        'nonce': _nextNonce(),
      });
      await ipc.drainReplies();
      if (ipc.dead) return false;
      return true;
    } catch (e) {
      printINFO('[DISCORD] clear failed: $e');
      return false;
    }
  }

  int _nonceCounter = 0;
  String _nextNonce() => 'velqi-${DateTime.now().microsecondsSinceEpoch}-${_nonceCounter++}';

  // ── Payload ────────────────────────────────────────────────────────────────

  Map<String, dynamic> _buildActivityJson() {
    final song = _song!;
    final title = _clamp(song.title);
    final artist = _clamp(song.artist ?? '');
    final artUrl = song.artUri?.toString();

    Map<String, dynamic>? timestamps;
    if (_playing && _duration.inMilliseconds > 0) {
      final start = DateTime.now().subtract(_position);
      timestamps = <String, dynamic>{
        'start': start.millisecondsSinceEpoch,
        'end': start.add(_duration).millisecondsSinceEpoch,
      };
    }

    return <String, dynamic>{
      'name': 'Velqi',
      'type': 2, // LISTENING — shows "Listening to Velqi", never "Playing".
      'details': title,
      'state': artist,
      if (timestamps != null) 'timestamps': timestamps,
      'assets': <String, dynamic>{
        // Real cover art of the current song (external URL — Discord proxies it).
        'large_image': artUrl ?? _velqiLogoUrl,
        'large_text': title,
        // Velqi logo badge.
        'small_image': _velqiLogoUrl,
        'small_text': 'Velqi',
      },
    };
  }

  /// Called on app shutdown so Discord drops the activity immediately.
  Future<void> shutdown() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _safeSendClear();
    try {
      _ipc?.close();
    } catch (_) {}
    _ipc = null;
    isLinked.value = false;
    printINFO('[DISCORD] shutdown — presence cleared');
  }

  String _clamp(String? text) {
    if (text == null || text.isEmpty) return '';
    return text.length <= _maxText ? text : text.substring(0, _maxText);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Minimal Discord IPC client (named pipe, protocol validated with probes).
//
// Frame layout: op (u32 LE) + length (u32 LE) + UTF-8 JSON payload.
//   op 0 = handshake {"v":1,"client_id":...}   op 1 = frame (commands)
//   op 2 = close                               op 3/4 = ping/pong (unused here)
// ═════════════════════════════════════════════════════════════════════════════

class _DiscordIpc {
  _DiscordIpc(this.clientId);

  final String clientId;
  RandomAccessFile? _raf;
  final List<int> _pending = [];
  bool dead = false;

  bool get isOpen => _raf != null && !dead;

  /// Opens the first available Discord pipe and performs the handshake.
  /// Throws/fails fast when the Discord desktop client is not running.
  Future<bool> open() async {
    for (var i = 0; i < 10; i++) {
      try {
        final raf = await File('\\\\?\\pipe\\discord-ipc-$i')
            .open(mode: FileMode.write);
        _raf = raf;
        dead = false;
        _pending.clear();
        raf.writeFromSync(_encode(0, <String, dynamic>{
          'v': 1,
          'client_id': clientId,
        }));
        return true;
      } catch (_) {
        _raf = null;
      }
    }
    return false;
  }

  void sendFrame(int op, Map<String, dynamic> payload) {
    final raf = _raf;
    if (raf == null) throw StateError('pipe closed');
    raf.writeFromSync(_encode(op, payload));
  }

  /// Reply drain: reads DIRECTLY (no length() polling — polling poisons the
  /// pipe handle and kills the next write with errno 232, proven by probe).
  /// Every successful SET_ACTIVITY/handshake write is guaranteed exactly one
  /// reply, so a direct read returns within milliseconds.
  Future<void> drainReplies() async {
    final raf = _raf;
    if (raf == null) return;
    try {
      final data =
          await raf.read(4096).timeout(const Duration(seconds: 5), onTimeout: () => Uint8List(0));
      if (data.isNotEmpty) _pending.addAll(data);
    } catch (_) {
      // Read error → the pipe is gone.
      dead = true;
      return;
    }
    _consumeFrames();
  }

  void _consumeFrames() {
    while (_pending.length >= 8) {
      final bd = ByteData.sublistView(Uint8List.fromList(_pending));
      final op = bd.getUint32(0, Endian.little);
      final len = bd.getUint32(4, Endian.little);
      if (_pending.length < 8 + len) break;
      final body = utf8.decode(_pending.sublist(8, 8 + len),
          allowMalformed: true);
      _pending.removeRange(0, 8 + len);

      if (op == 2) {
        // Discord closed the pipe (client quit / protocol error).
        dead = true;
        printINFO('[DISCORD] Discord closed the pipe');
        return;
      }
      if (op == 1) {
        try {
          final json = jsonDecode(body) as Map<String, dynamic>;
          if (json['evt'] == 'READY') {
            printINFO('[DISCORD] handshake READY');
          } else if (json['code'] != null) {
            printINFO(
                '[DISCORD] Discord error ${json['code']}: ${json['message']}');
            if (json['code'] == 4000 || json['code'] == 4001) {
              dead = true; // invalid client / auth — nothing to do but retry
            }
          }
        } catch (_) {
          // Non-JSON or partial frame — ignore.
        }
      }
    }
  }

  void close() {
    try {
      _raf?.closeSync();
    } catch (_) {}
    _raf = null;
    dead = true;
  }

  Uint8List _encode(int op, Map<String, dynamic> payload) {
    final body = utf8.encode(json.encode(payload));
    final out = BytesBuilder();
    final header = ByteData(8)
      ..setUint32(0, op, Endian.little)
      ..setUint32(4, body.length, Endian.little);
    out.add(header.buffer.asUint8List());
    out.add(body);
    return out.toBytes();
  }
}
