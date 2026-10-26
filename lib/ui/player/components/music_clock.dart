import 'dart:math' as math;

/// Music-clocked animation helpers.
///
/// Real FFT data isn't exposed by the audio engine, so the whole player
/// (pulse rings, bottom wave, mini equalizer) dances to a **music clock**
/// instead of the wall clock: the beat phase is derived from the ACTUAL
/// playback position, so:
///   * every song has its own stable tempo (hash of the song id → 88–128 BPM)
///   * pausing freezes the beat exactly where the music stopped
///   * seeking moves the beat with the song — it never drifts or runs free
class MusicClock {
  /// Stable pseudo-BPM for a song (88–128), derived from its id so the tempo
  /// is consistent across restarts and unique-ish per track.
  static int bpmFor(String? songId) {
    if (songId == null || songId.isEmpty) return 104;
    var h = 5381;
    for (final c in songId.codeUnits) {
      h = ((h << 5) + h + c) & 0x7fffffff;
    }
    return 88 + (h % 41); // 88..128 BPM
  }

  /// Beat phase in [0,1) at [positionSec] for [songId]. 0 = the instant the
  /// beat lands, 1 = just before the next one.
  static double beatPhase({
    required double positionSec,
    required String? songId,
  }) {
    final beats = positionSec * (bpmFor(songId) / 60.0);
    return beats % 1.0;
  }

  /// Smooth attack/decay envelope for one beat: 1.0 right on the beat,
  /// decaying exponentially through the beat span (kick-like).
  static double beatEnvelope(double phase, {double sharpness = 5}) =>
      math.exp(-sharpness * phase);
}

/// Frame-smooth playback position for 60 fps animations.
///
/// The player's position stream ticks coarsely (~every 100–200 ms); while
/// playing, [now] extrapolates linearly from the last stream sample so the
/// beat never stutters. When paused the position freezes.
class MusicTime {
  double _anchor = 0;
  DateTime _anchorAt = DateTime.now();

  /// Re-anchors to the latest position from the player stream.
  void sync(Duration position, bool playing) {
    _anchor = position.inMicroseconds / 1e6;
    _anchorAt = DateTime.now();
  }

  /// Current music time (seconds) — extrapolated while playing, frozen when
  /// paused.
  double now(bool playing) {
    if (!playing) return _anchor;
    return _anchor + DateTime.now().difference(_anchorAt).inMicroseconds / 1e6;
  }
}
