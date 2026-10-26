/// Maps raw `ytmusicapi_dart` items into the exact JSON contracts that Velqi's
/// model factories expect (`MediaItemBuilder.fromJson`, `Album.fromJson`,
/// `Playlist.fromJson`, `Artist.fromJson`) plus a `_type` tag per item.
///
/// This is a direct port of `python/ytmusic_backend.py`'s mappers, so the
/// browse/search layer keeps working with zero UI changes.
class YtMusicMapper {
  static List<Map<String, dynamic>> _thumbs(dynamic item,
      {List<Map<String, dynamic>>? fallback}) {
    if (item is! Map) {
      return fallback ?? [{'url': ''}];
    }
    final th = item['thumbnails'] ?? item['thumbnail'];
    if (th is List && th.isNotEmpty) {
      return th
          .whereType<Map>()
          .map((t) => {'url': t['url']?.toString() ?? ''})
          .toList();
    }
    return fallback ?? [{'url': ''}];
  }

  static List<Map<String, dynamic>>? _artists(dynamic arts) {
    if (arts is! List) return null;
    final out = <Map<String, dynamic>>[];
    for (final a in arts) {
      if (a is Map) {
        out.add({'name': a['name']?.toString() ?? '', 'id': a['id']});
      } else if (a is String) {
        out.add({'name': a, 'id': null});
      }
    }
    return out.isEmpty ? null : out;
  }

  static Map<String, dynamic>? _albumRef(dynamic alb) {
    if (alb is Map && alb['id'] != null) {
      return {'id': alb['id'], 'name': alb['name']?.toString() ?? ''};
    }
    return null;
  }

  static bool _isVideo(Map item) {
    final vt = (item['videoType'] ?? '').toString();
    return vt.startsWith('MUSIC_VIDEO_TYPE_UGC') ||
        item['resultType']?.toString() == 'video';
  }

  static Map<String, dynamic> _song(Map item,
      {List<Map<String, dynamic>>? fallbackThumbs}) {
    return {
      '_type': _isVideo(item) ? 'video' : 'song',
      'videoId': item['videoId'],
      'title': item['title'],
      'artists': _artists(item['artists']),
      'album': _albumRef(item['album']),
      'thumbnails': _thumbs(item, fallback: fallbackThumbs),
      // MediaItemBuilder uses 'duration' (int seconds) first, else parses 'length'
      'duration': item['duration_seconds'],
      'length': item['duration'] is String ? item['duration'] : null,
      'year': item['year'],
    };
  }

  static Map<String, dynamic> _album(Map item) {
    return {
      '_type': 'album',
      'title': item['title'],
      'browseId': item['browseId'] ?? item['audioPlaylistId'],
      'artists': _artists(item['artists']) ?? [
        {'name': ''}
      ],
      'year': item['year'],
      'audioPlaylistId': item['audioPlaylistId'] ?? item['playlistId'],
      'thumbnails': _thumbs(item),
      'description': item['type']?.toString() ?? 'Album',
    };
  }

  static Map<String, dynamic> _playlist(Map item) {
    final count = item['itemCount'] ?? item['count'];
    return {
      '_type': 'playlist',
      'title': item['title'],
      'playlistId': item['playlistId'] ?? item['browseId'],
      'thumbnails': _thumbs(item),
      'description': item['description']?.toString() ?? 'Playlist',
      'itemCount': count?.toString(),
      'isCloudPlaylist': true,
    };
  }

  static Map<String, dynamic> _artist(Map item) {
    return {
      '_type': 'artist',
      'artist': item['artist'] ?? item['title'] ?? item['name'],
      'browseId': item['browseId'],
      'radioId': item['radioId'] ?? item['shuffleId'],
      'subscribers': item['subscribers'],
      'thumbnails': _thumbs(item),
    };
  }

  /// Same as [classify] but passes a fallback thumbnail set (e.g. the album
  /// artwork) to songs that have no thumbnails of their own.
  static Map<String, dynamic>? classifyWithThumbs(
      dynamic item, List<Map<String, dynamic>> fallbackThumbs) {
    if (item is! Map) return null;
    if (item['videoId'] != null) {
      return _song(item, fallbackThumbs: fallbackThumbs);
    }
    return classify(item);
  }

  /// Best-effort: turn one home/related content item into a tagged model dict.
  static Map<String, dynamic>? classify(dynamic item) {
    if (item is! Map) return null;
    final bid = (item['browseId'] ?? '').toString();
    if (item['videoId'] != null) return _song(item);
    if (bid.startsWith('UC') ||
        (item['subscribers'] != null && item['playlistId'] == null)) {
      return _artist(item);
    }
    if (bid.startsWith('MPRE')) return _album(item);
    if (item['playlistId'] != null) return _playlist(item);
    if (bid.isNotEmpty) return _album(item);
    return null;
  }

  /// Map a {title, contents:[...]} section, classifying each item.
  static Map<String, dynamic> section(dynamic sec) {
    final contents = <dynamic>[];
    if (sec is Map) {
      for (final it in (sec['contents'] as List?) ?? []) {
        final m = classify(it);
        if (m == null) continue;
        final hasKey = (m['_type'] == 'song' || m['_type'] == 'video')
            ? m['videoId'] != null
            : m['_type'] == 'playlist'
                ? m['playlistId'] != null
                : m['browseId'] != null;
        if (hasKey) contents.add(m);
      }
    }
    return {'title': sec is Map ? (sec['title']?.toString() ?? '') : '', 'contents': contents};
  }
}
