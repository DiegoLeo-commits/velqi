import 'dart:convert';

import 'package:dio/dio.dart';

/// Resolves playable audio URLs straight from YouTube's internal `player`
/// endpoint — pure Dart, no embedded server.
///
/// We impersonate the official Android app client (`ANDROID` / v20.01.35).
/// This client returns direct googlevideo URLs (no DASH segment chaining):
///   * the muxed **progressive** format (itag 18) answers a plain GET with
///     HTTP 200, which is exactly what Windows Media Foundation needs —
///     this is why desktop playback works without a proxy;
///   * audio-only adaptive formats (itag 139/140 m4a, 249/251 opus) answer
///     ranged GETs, which ExoPlayer on Android consumes natively.
///
/// Kept small on purpose: this is the single "extractor" of the app, mirroring
/// what yt-dlp's android extractor does, so YouTube changes land in one place.
class StreamProvider {
  final bool playable;
  final List<Audio>? audioFormats;
  final String statusMSG;
  StreamProvider(
      {required this.playable, this.audioFormats, this.statusMSG = ""});

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
  ));

  static const _playerUrl = 'https://www.youtube.com/youtubei/v1/player';

  static String? _cookie;
  static String? _visitorData;
  static DateTime? _visitorFetchedAt;

  /// Called by MusicServices whenever the account session changes, so
  /// account-only or region-restricted tracks resolve with the same cookie.
  static void setCookie(String? cookie) {
    _cookie = (cookie == null || cookie.isEmpty) ? null : cookie;
  }

  /// Native clients that currently return direct googlevideo URLs.
  static final List<Map<String, dynamic>> _clients = [
    {
      'client': {
        'clientName': 'ANDROID',
        'clientVersion': '20.01.35',
        'androidSdkVersion': 33,
        'hl': 'en',
        'gl': 'US',
      },
      'ua': 'com.google.android.youtube/20.01.35 (Linux; U; Android 13) gzip',
    },
    {
      'client': {
        'clientName': 'ANDROID_VR',
        'clientVersion': '1.62.27',
        'androidSdkVersion': 32,
        'deviceMake': 'Oculus',
        'deviceModel': 'Quest 3',
        'osName': 'Android',
        'osVersion': '12',
        'hl': 'en',
        'gl': 'US',
      },
      'ua': 'com.google.android.apps.youtube.vr.oculus/1.62.27 '
          '(Linux; U; Android 12; en_US; Quest 3 Build/SQ3A.220605.009.A1) gzip',
    },
    {
      'client': {
        'clientName': 'IOS',
        'clientVersion': '20.10.4',
        'deviceMake': 'Apple',
        'deviceModel': 'iPhone16,2',
        'osName': 'iPhone',
        'osVersion': '18.3.1.22D72',
        'hl': 'en',
        'gl': 'US',
      },
      'ua': 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_1 '
          'like Mac OS X;)',
    },
  ];

  /// Visitor id expected by InnerTube, cached for six hours. Without it a
  /// fresh session is more likely to be answered with "Sign in to confirm
  /// you're not a bot".
  static Future<String?> _ensureVisitorData() async {
    final fetchedAt = _visitorFetchedAt;
    if (_visitorData != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < const Duration(hours: 6)) {
      return _visitorData;
    }
    try {
      final response = await _dio.get(
        'https://music.youtube.com/',
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/126.0 Safari/537.36',
          },
          responseType: ResponseType.plain,
        ),
      );
      final text = response.data.toString();
      final matches =
          RegExp(r'ytcfg\.set\s*\(\s*(\{.+?\})\s*\)\s*;', dotAll: true)
              .allMatches(text);
      if (matches.isNotEmpty) {
        final config = jsonDecode(matches.first.group(1)!) as Map;
        final visitor = config['VISITOR_DATA'] ?? config['EOM_VISITOR_DATA'];
        if (visitor is String && visitor.isNotEmpty) {
          _visitorData = visitor;
          _visitorFetchedAt = DateTime.now();
        }
      }
    } catch (_) {
      // Anonymous player requests still work; the header is an improvement.
    }
    return _visitorData;
  }

  /// Resolves audio formats for [videoId].
  ///
  /// When [fast] is true ("Modo Rápido") the request gives up faster, so
  /// skipping songs on slow connections never hangs for tens of seconds.
  ///
  /// When [adaptiveOnly] is true, adaptive formats are preferred over
  /// progressive — used as the second strike of the playback fallback chain.
  static Future<StreamProvider> fetch(String videoId,
      {bool fast = false,
      String? platform,
      bool adaptiveOnly = false}) async {
    final visitor = await _ensureVisitorData();
    final attempts = fast ? 1 : 3;
    var lastMessage = 'networkError';

    for (int attempt = 0; attempt < attempts; attempt++) {
      for (final profile in _clients) {
        try {
          final res = await _dio.post(
            _playerUrl,
            data: {
              'context': {
                'client': profile['client'],
                'user': {'lockedSafetyMode': false},
              },
              'videoId': videoId,
              'contentCheckOk': true,
              'racyCheckOk': true,
            },
            options: Options(
              headers: {
                'User-Agent': profile['ua'],
                'Content-Type': 'application/json',
                if (_cookie != null) 'Cookie': _cookie!,
                if (visitor != null) 'X-Goog-Visitor-Id': visitor,
              },
              receiveTimeout: Duration(seconds: fast ? 12 : 20),
            ),
          );
          final data = res.data is String ? jsonDecode(res.data) : res.data;
          final playability = (data is Map ? data['playabilityStatus'] : null);
          final status = playability is Map
              ? (playability['status']?.toString() ?? '')
              : '';
          if (status != 'OK') {
            final reason = playability is Map
                ? (playability['reason']?.toString() ?? '')
                : '';
            lastMessage = reason.isNotEmpty ? reason : 'Song is unplayable';
            continue;
          }
          final sd = data is Map ? data['streamingData'] : null;
          if (sd is! Map) {
            lastMessage = 'Song is unplayable';
            continue;
          }
          final videoDetails = data['videoDetails'] is Map
              ? data['videoDetails'] as Map
              : const <String, dynamic>{};
          final durationSec = int.tryParse(
                  (videoDetails['lengthSeconds'] ?? '0').toString()) ??
              0;

          final formats = _parseFormats(sd['formats'], durationSec);
          final adaptive = _parseFormats(sd['adaptiveFormats'], durationSec);

          List<Audio> selected;
          if (platform == 'desktop') {
            // Windows Media Foundation / libmpv gets the muxed stream: it
            // accepts plain GETs and needs no Range handshake.
            selected = formats;
          } else if (adaptiveOnly) {
            selected = adaptive;
          } else {
            // Audio-only adaptive formats: higher quality, no video payload.
            selected = [...adaptive, ...formats];
          }
          if (selected.isEmpty) {
            lastMessage = platform == 'desktop'
                ? 'No progressive format available on this device'
                : 'No audio format available';
            continue;
          }
          return StreamProvider(
              playable: true, statusMSG: 'OK', audioFormats: selected);
        } on DioException catch (e) {
          final retriable = e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.connectionTimeout ||
              e.response?.statusCode == 429 ||
              (e.response?.statusCode ?? 0) >= 500;
          lastMessage = 'networkError';
          if (retriable && attempt < attempts - 1) {
            await Future.delayed(Duration(milliseconds: 800 * (attempt + 1)));
          }
        } catch (_) {
          lastMessage = 'Unknown error occurred';
        }
      }
      if (lastMessage == 'networkError' && attempt < attempts - 1) {
        await Future.delayed(Duration(milliseconds: 800 * (attempt + 1)));
      }
    }
    return StreamProvider(playable: false, statusMSG: lastMessage);
  }

  /// Maps raw `streamingData` format maps to the [Audio] model.
  static List<Audio> _parseFormats(dynamic raw, int durationSec) {
    if (raw is! List) return [];
    final out = <Audio>[];
    for (final f in raw) {
      if (f is! Map) continue;
      final mime = (f['mimeType'] ?? '').toString();
      final isAudio = mime.contains('audio') ||
          // Muxed progressive (itag 18) reports video/mp4 but carries an AAC
          // track — detect it through the codec list.
          mime.contains('mp4a');
      if (!isAudio) continue; // skip pure-video formats
      final url = (f['url'] ?? '').toString();
      if (url.isEmpty) continue;
      final itag = int.tryParse((f['itag'] ?? '').toString());
      if (itag == null) continue;
      out.add(Audio(
        itag: itag,
        // mp4a in audio mime, or the muxed progressive format (video/mp4 with
        // an AAC track, itag 18) — both are AAC and download as m4a.
        audioCodec: mime.contains('mp4') ? Codec.mp4a : Codec.opus,
        bitrate: int.tryParse((f['bitrate'] ?? '0').toString()) ?? 0,
        duration: int.tryParse(
                (f['approxDurationMs'] ?? '').toString()) ??
            durationSec * 1000,
        loudnessDb:
            double.tryParse((f['loudnessDb'] ?? '0').toString()) ?? 0,
        url: url,
        size: int.tryParse((f['contentLength'] ?? '0').toString()) ?? 0,
      ));
    }
    return out;
  }

  /// The muxed progressive stream (itag 18): accepts ANY request — plain GET
  /// (200), open ranges (206) and multi-MiB ranges — unlike adaptive formats
  /// which 403 on ranges above ~30 KB. Used for reliable downloads.
  Audio? get progressiveAudio {
    if (audioFormats == null) return null;
    for (final f in audioFormats!) {
      if (f.itag == 18) return f;
    }
    return null;
  }

  /// Best playable format.
  ///
  /// ExoPlayer asks googlevideo for `Range: bytes=0-` (open-ended). Adaptive
  /// streams (139/140/251) reject that with HTTP 403; they only answer small
  /// explicit ranges (~64 KB). The muxed progressive stream (18) accepts
  /// plain GET, open ranges and multi-MiB ranges, so it must be preferred on
  /// Android too. Adaptive formats remain available for future cached/proxied
  /// playback, but are not selected first.
  Audio? get highestQualityAudio {
    final fmts = audioFormats;
    if (fmts == null) return null;
    Audio? pick(int itag) {
      for (final f in fmts) {
        if (f.itag == itag) return f;
      }
      return null;
    }
    for (final itag in const [18, 140, 251, 141, 250, 139, 249]) {
      final f = pick(itag);
      if (f != null) return f;
    }
    Audio? best;
    for (final f in fmts) {
      if (best == null || f.bitrate > best.bitrate) best = f;
    }
    return best ?? (fmts.isEmpty ? null : fmts.first);
  }

  Audio? get highestBitrateMp4aAudio =>
      audioFormats?.lastWhere((item) => item.itag == 140 || item.itag == 139,
          orElse: () => audioFormats!.first);

  Audio? get highestBitrateOpusAudio =>
      audioFormats?.lastWhere((item) => item.itag == 251 || item.itag == 250,
          orElse: () => audioFormats!.first);

  /// Low-quality stream for the settings toggle and slow networks.
  Audio? get lowQualityAudio {
    final fmts = audioFormats;
    if (fmts == null) return null;
    Audio? pick(int itag) {
      for (final f in fmts) {
        if (f.itag == itag) return f;
      }
      return null;
    }
    for (final itag in const [18, 139, 249, 140, 251]) {
      final f = pick(itag);
      if (f != null) return f;
    }
    for (final f in fmts) {
      if (f.audioCodec == Codec.mp4a) return f;
    }
    return fmts.first;
  }

  Map<String, dynamic> get hmStreamingData {
    return {
      "playable": playable,
      "statusMSG": statusMSG,
      "lowQualityAudio": lowQualityAudio?.toJson(),
      "highQualityAudio": highestQualityAudio?.toJson()
    };
  }
}

class Audio {
  final int itag;
  final Codec audioCodec;
  final int bitrate;
  final int duration;
  final int size;
  final double loudnessDb;
  final String url;
  Audio(
      {required this.itag,
      required this.audioCodec,
      required this.bitrate,
      required this.duration,
      required this.loudnessDb,
      required this.url,
      required this.size});

  Map<String, dynamic> toJson() => {
        "itag": itag,
        "audioCodec": audioCodec.toString(),
        "bitrate": bitrate,
        "loudnessDb": loudnessDb,
        "url": url,
        "approxDurationMs": duration,
        "size": size
      };

  factory Audio.fromJson(json) => Audio(
      audioCodec: (json["audioCodec"] as String).contains("mp4a")
          ? Codec.mp4a
          : Codec.opus,
      itag: json['itag'],
      duration: json["approxDurationMs"] ?? 0,
      bitrate: json["bitrate"] ?? 0,
      loudnessDb: (json['loudnessDb'])?.toDouble() ?? 0.0,
      url: json['url'],
      size: json["size"] ?? 0);
}

enum Codec { mp4a, opus }
