import 'dart:convert';

import 'package:ytmusicapi_dart/continuations.dart';
import 'package:ytmusicapi_dart/helpers.dart';
import 'package:ytmusicapi_dart/navigation.dart';
import 'package:ytmusicapi_dart/parsers/browsing.dart';
import 'package:ytmusicapi_dart/parsers/library.dart';
import 'package:ytmusicapi_dart/parsers/playlists.dart';
import 'package:ytmusicapi_dart/parsers/watch.dart' as watch_parser;
import 'package:ytmusicapi_dart/type_alias.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

/// InnerTube features that `ytmusicapi_dart` does not implement yet (its
/// `LibraryMixin` is a TODO) or that need the raw continuation token.
///
/// Everything here talks to the same authenticated [YTMusic] client, so
/// cookies, language, visitor data and SAPISIDHASH stay in one session.
class InnerTubeExtras {
  InnerTubeExtras(this._yt);

  final YTMusic _yt;

  static const String origin = 'https://music.youtube.com';
  static const String cookiePrefKey = 'userCookiesContent';

  // ---------------------------------------------------------------------------
  // Cookie handling
  // ---------------------------------------------------------------------------

  /// Accepts a `Cookie:` header, the JSON exported by browser extensions and
  /// Netscape `cookies.txt` files (what yt-dlp/ytmusicapi use). Returns a
  /// single request header value, or an empty string when no cookie is found.
  static String normalizeCookie(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return '';

    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          final cookie = decoded['cookie'] ?? decoded['Cookie'];
          if (cookie is String && cookie.trim().isNotEmpty) {
            text = cookie.trim();
          } else {
            final pairs = <String>[];
            decoded.forEach((key, value) {
              if (value is String && value.isNotEmpty) {
                pairs.add('$key=$value');
              }
            });
            if (pairs.isNotEmpty) return pairs.join('; ');
          }
        }
      } catch (_) {
        // Not JSON: keep treating it as a cookie header/file.
      }
    }

    if (text.toLowerCase().startsWith('cookie:')) {
      text = text.substring(7).trim();
    }

    final lines = text.split(RegExp(r'\r?\n'));
    final looksNetscape = text.contains('# Netscape HTTP Cookie File') ||
        lines.any((line) => line.split('\t').length >= 7);
    if (looksNetscape) {
      final pairs = <String>[];
      final seen = <String>{};
      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty) continue;
        if (line.startsWith('#HttpOnly_')) {
          // The marker prefixes the domain, not a comment: keep the line.
          line = line.substring('#HttpOnly_'.length);
        } else if (line.startsWith('#')) {
          continue;
        }
        final parts = line.split('\t');
        if (parts.length < 7) continue;
        final domain = parts[0].toLowerCase();
        if (!domain.contains('youtube.com') && !domain.contains('google.com')) {
          continue;
        }
        final name = parts[5].trim();
        final value = parts[6].trim();
        if (name.isEmpty) continue;
        // Last write wins, matching how a browser resolves duplicate names.
        if (seen.add(name)) {
          pairs.add('$name=$value');
        } else {
          final index =
              pairs.indexWhere((pair) => pair.startsWith('$name='));
          if (index >= 0) pairs[index] = '$name=$value';
        }
      }
      return pairs.join('; ');
    }

    return text.replaceAll(RegExp(r'\s+'), ' ');
  }

  static String? cookieValue(String cookieHeader, String name) {
    for (final part in cookieHeader.split(';')) {
      final pair = part.trim();
      final index = pair.indexOf('=');
      if (index <= 0) continue;
      if (pair.substring(0, index).trim() == name) {
        return pair.substring(index + 1).trim();
      }
    }
    return null;
  }

  /// Builds the auth map expected by `YTMusic.create(auth: ...)`.
  ///
  /// Returns null when the cookie is empty or does not carry a SAPISID
  /// variant; YouTube would answer those requests as anonymous anyway.
  static Map<String, String>? authFromCookie(String rawCookie) {
    final cookie = normalizeCookie(rawCookie);
    if (cookie.isEmpty) return null;

    final sapisid = cookieValue(cookie, '__Secure-3PAPISID') ??
        cookieValue(cookie, 'SAPISID') ??
        cookieValue(cookie, '__Secure-1PAPISID');
    if (sapisid == null || sapisid.isEmpty) return null;

    return {
      'cookie': cookie,
      'origin': origin,
      'x-origin': origin,
      'authorization': getAuthorization('$sapisid $origin'),
    };
  }

  static bool hasSapisid(String rawCookie) =>
      authFromCookie(rawCookie) != null;

  // ---------------------------------------------------------------------------
  // Account
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> accountInfo() async {
    final response = await _yt.sendRequest('account/account_menu', {});
    final actions = response['actions'];
    if (actions is! List || actions.isEmpty) return null;

    dynamic account;
    for (final action in actions) {
      if (action is! Map) continue;
      final popup = action['openPopupAction']?['popup'];
      if (popup is! Map) continue;
      final menu = popup['multiPageMenuRenderer'] ?? popup['accountMenuRenderer'];
      if (menu is! Map) continue;
      account = menu['header']?['activeAccountHeaderRenderer'];
      if (account != null) break;
    }
    if (account is! Map) return null;

    String? runsText(dynamic node) {
      if (node is! Map) return null;
      final runs = node['runs'];
      if (runs is List && runs.isNotEmpty) {
        final first = runs.first;
        if (first is Map) {
          final text = first['text'];
          if (text is String && text.trim().isNotEmpty) return text.trim();
        }
      }
      final simple = node['simpleText'];
      if (simple is String && simple.trim().isNotEmpty) return simple.trim();
      return null;
    }

    final name = runsText(account['accountName']);
    if (name == null || name.isEmpty) return null;

    final photo = account['accountPhoto'];
    String? thumbnailUrl;
    if (photo is Map && photo['thumbnails'] is List) {
      final thumbs = List<Map>.from(photo['thumbnails'] as List);
      thumbnailUrl = thumbs.isEmpty ? null : thumbs.last['url']?.toString();
    }

    return {
      'name': name,
      'email': runsText(account['email']),
      'channelHandle': runsText(account['channelHandle']),
      'thumbnailUrl': thumbnailUrl,
    };
  }

  // ---------------------------------------------------------------------------
  // Library
  // ---------------------------------------------------------------------------

  Future<JsonMap> _browse(String browseId) =>
      _yt.sendRequest('browse', <String, dynamic>{'browseId': browseId});

  Future<JsonMap> _browseContinued(String browseId, String params) =>
      _yt.sendRequest('browse', <String, dynamic>{'browseId': browseId},
          additionalParams: params);

  /// Account playlists (the YouTube Music "Library > Playlists" tab).
  ///
  /// Returns raw playlist maps compatible with `Playlist.fromJson`.
  Future<List<JsonMap>> libraryPlaylists({int? limit}) async {
    const browseId = 'FEmusic_liked_playlists';
    final response = await _browse(browseId);
    final results = getLibraryContents(response, GRID);
    if (results == null) return [];

    List<JsonMap> parseItems(List<JsonMap> items) {
      final out = <JsonMap>[];
      for (final item in items) {
        final renderer = item['musicTwoRowItemRenderer'];
        if (renderer is! Map) continue;
        final browse = nav(renderer, [...TITLE, ...NAVIGATION_BROWSE_ID],
            nullIfAbsent: true);
        // The first tile can be "New playlist"; it has no VL browse id.
        if (browse is! String || !browse.startsWith('VL')) continue;
        try {
          final playlist = parsePlaylist({'musicTwoRowItemRenderer': renderer});
          final id = playlist['playlistId']?.toString() ?? '';
          if (id.isEmpty) continue;
          playlist['playlistId'] = id;
          playlist['title'] ??= 'Playlist';
          playlist['description'] ??= 'Playlist';
          playlist['isCloudPlaylist'] = true;
          playlist['itemCount'] = playlist['count'];
          final thumbs = playlist['thumbnails'];
          if (thumbs is! List || thumbs.isEmpty) {
            playlist['thumbnails'] = [
              {'url': ''}
            ];
          }
          out.add(playlist);
        } catch (_) {
          // Ignore unparseable tiles instead of taking down the library.
        }
      }
      return out;
    }

    final parsed =
        parseItems(List<JsonMap>.from((results['items'] as List?) ?? []));
    if (results.containsKey('continuations')) {
      final remaining = limit == null ? null : limit - parsed.length;
      final more = await getContinuations(
        results,
        'gridContinuation',
        remaining,
        (params) => _browseContinued(browseId, params),
        (contents) => parseItems(contents),
      );
      parsed.addAll(more.whereType<JsonMap>());
    }
    return parsed;
  }

  /// Liked songs. Returns the same shape as `getPlaylist`:
  /// `{tracks, playlistId: 'LM'}`.
  Future<JsonMap> librarySongs({int? limit}) async {
    const browseId = 'FEmusic_liked_videos';
    final response = await _browse(browseId);
    final results = getLibraryContents(response, MUSIC_SHELF);
    if (results == null) return {'tracks': <JsonMap>[], 'playlistId': 'LM'};

    // The first entry is the "Add songs" action, not a track.
    popSongsRandomMix(results);
    final tracks = parsePlaylistItems(
      List<JsonMap>.from((results['contents'] as List?) ?? []),
    );
    if (results.containsKey('continuations')) {
      final remaining = limit == null ? null : limit - tracks.length;
      tracks.addAll(
        List<JsonMap>.from(
          await getContinuations(
            results,
            'musicShelfContinuation',
            remaining,
            (params) => _browseContinued(browseId, params),
            (contents) => parsePlaylistItems(contents),
          ),
        ),
      );
    }
    return {'tracks': tracks, 'playlistId': 'LM'};
  }

  /// Saved albums. Raw maps compatible with `Album.fromJson`.
  Future<List<JsonMap>> libraryAlbums({int? limit}) async {
    const browseId = 'FEmusic_library_albums';
    final response = await _browse(browseId);
    final albums = await parseLibraryAlbums(
      response,
      (params) => _browseContinued(browseId, params),
      limit,
    );
    return [
      for (final album in albums)
        if (album is Map)
          {
            ...Map<String, dynamic>.from(album),
            'audioPlaylistId':
                album['audioPlaylistId'] ?? album['playlistId'],
          }
    ];
  }

  /// Subscribed artists and podcast authors.
  Future<List<JsonMap>> libraryArtists({int? limit}) =>
      _libraryArtists('FEmusic_library_artists', limit: limit);

  /// Channels the account is subscribed to (Meredith's "subscriptions").
  Future<List<JsonMap>> librarySubscriptions({int? limit}) =>
      _libraryArtists('FEmusic_library_subscriptions', limit: limit);

  Future<List<JsonMap>> _libraryArtists(String browseId,
      {int? limit}) async {
    final response = await _browse(browseId);
    final artists = await parseLibraryArtists(
      response,
      (params) => _browseContinued(browseId, params),
      limit,
    );
    return [
      for (final artist in artists)
        if (artist is Map) Map<String, dynamic>.from(artist)
    ];
  }

  /// Listening history, grouped by the shelves YouTube returns
  /// (Today, Yesterday, ...). Raw maps compatible with `MediaItemBuilder`.
  Future<List<JsonMap>> history() async {
    final response = await _browse('FEmusic_history');
    final sectionList = nav(
      response,
      [...SINGLE_COLUMN_TAB, ...SECTION_LIST],
      nullIfAbsent: true,
    );
    if (sectionList is! List) return [];

    final sections = <JsonMap>[];
    for (final section in sectionList) {
      if (section is! Map) continue;
      final shelf = section['musicShelfRenderer'];
      if (shelf is! Map) continue;
      final title = nav(shelf, TITLE_TEXT, nullIfAbsent: true);
      final tracks = parsePlaylistItems(
        List<JsonMap>.from((shelf['contents'] as List?) ?? []),
      );
      if (tracks.isEmpty) continue;
      sections.add({'title': title, 'contents': tracks});
    }
    return sections;
  }

  // ---------------------------------------------------------------------------
  // Account mutations
  // ---------------------------------------------------------------------------

  /// [rating] is `like`, `dislike` or `none`.
  Future<void> setRating(String videoId, String rating) async {
    final endpoint = switch (rating) {
      'like' => 'like/like',
      'dislike' => 'like/dislike',
      _ => 'like/removelike',
    };
    await _yt.sendRequest(endpoint, {
      'target': {'videoId': videoId}
    });
  }

  Future<void> subscribeChannel(String channelId, {bool subscribe = true}) async {
    final endpoint =
        subscribe ? 'subscription/subscribe' : 'subscription/unsubscribe';
    await _yt.sendRequest(endpoint, {
      'channelIds': [channelId]
    });
  }

  Future<String> createPlaylist(
    String title, {
    String description = '',
    String privacyStatus = 'PRIVATE',
    List<String>? videoIds,
  }) async {
    final result = await _yt.createPlaylist(
      title,
      description,
      privacyStatus: privacyStatus,
      videoIds: videoIds,
    );
    if (result is String) return result;
    throw StateError('YouTube rejected playlist creation: $result');
  }

  Future<void> renamePlaylist(String playlistId, String title) async {
    await _yt.editPlaylist(playlistId, title: title);
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _yt.deletePlaylist(playlistId);
  }

  Future<void> addSongToPlaylist(String playlistId, String videoId) async {
    await _yt.addPlaylistItems(playlistId, videoIds: [videoId], duplicates: true);
  }

  Future<void> removeSongFromPlaylist(
      String playlistId, List<JsonMap> items) async {
    await _yt.removePlaylistItems(playlistId, items);
  }

  // ---------------------------------------------------------------------------
  // Radio ("next") continuation
  // ---------------------------------------------------------------------------

  /// Initial watch/radio queue.
  ///
  /// We cannot use [YTMusic.getWatchPlaylist] here because it resolves all
  /// continuations internally and throws the token away, which is what made
  /// Velqi's radio stop at ~24 songs. This keeps the token and returns it as
  /// `additionalParamsForNext` for [nextPage].
  Future<JsonMap> watchPlaylist({
    String? videoId,
    String? playlistId,
    int limit = 25,
    bool radio = false,
    bool shuffle = false,
  }) async {
    final body = <String, dynamic>{
      'enablePersistentPlaylistPanel': true,
      'isAudioOnly': true,
      'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
    };
    if (videoId != null && videoId.isNotEmpty) {
      body['videoId'] = videoId;
      playlistId ??= 'RDAMVM$videoId';
      if (!radio && !shuffle) {
        body['watchEndpointMusicSupportedConfigs'] = {
          'watchEndpointMusicConfig': {
            'hasPersistentPlaylistPanel': true,
            'musicVideoType': 'MUSIC_VIDEO_TYPE_ATV',
          }
        };
      }
    }
    if (playlistId != null && playlistId.isNotEmpty) {
      final validated = playlistId.startsWith('VL')
          ? playlistId.substring(2)
          : playlistId;
      body['playlistId'] = validated;
    }
    if (shuffle) body['params'] = 'wAEB8gECKAE%3D';
    if (radio) body['params'] = 'wAEB';

    final response = await _yt.sendRequest('next', body);
    return _parseNext(response, body, limit);
  }

  /// Fetches the next page of a queue, preserving the radio token.
  Future<JsonMap> nextPage(String token, {int limit = 25}) async {
    final session = _nextSessions[token];
    if (session == null) {
      return {
        'tracks': <JsonMap>[],
        'additionalParamsForNext': null,
      };
    }
    final response = await _yt.sendRequest('next', session.body,
        additionalParams: token);
    final page = _parseNext(response, session.body, limit);
    _nextSessions.remove(token);
    return page;
  }

  static final Map<String, _NextSession> _nextSessions = {};

  JsonMap _parseNext(JsonMap response, JsonMap body, int limit) {
    Map? watchNext;
    List<JsonMap> contents;

    final continuation = response['continuationContents'];
    if (continuation is Map && continuation['playlistPanelContinuation'] is Map) {
      final panel =
          continuation['playlistPanelContinuation'] as Map<String, dynamic>;
      contents = List<JsonMap>.from((panel['contents'] as List?) ?? []);
      final token = _continuationToken(panel);
      if (token != null) _nextSessions[token] = _NextSession(body);
      return {
        'tracks': watch_parser.parseWatchPlaylist(contents).take(limit).toList(),
        'playlistId': body['playlistId'],
        'additionalParamsForNext': token,
      };
    }

    final renderer = response['contents']?['singleColumnMusicWatchNextResultsRenderer']
        ?['tabbedRenderer'];
    watchNext = renderer?['watchNextTabbedResultsRenderer'];
    if (watchNext is! Map) {
      return {
        'tracks': <JsonMap>[],
        'additionalParamsForNext': null,
      };
    }

    final tabs = watchNext['tabs'];
    final firstTab = tabs is List && tabs.isNotEmpty ? tabs.first : null;
    final panel = firstTab?['tabRenderer']?['content']?['musicQueueRenderer']
        ?['content'];
    final playlistPanel = panel?['playlistPanelRenderer'];
    if (playlistPanel is! Map) {
      return {
        'tracks': <JsonMap>[],
        'additionalParamsForNext': null,
      };
    }
    contents = List<JsonMap>.from((playlistPanel['contents'] as List?) ?? []);
    final token = _continuationToken(playlistPanel);
    if (token != null) _nextSessions[token] = _NextSession(body);

    final tabBrowseIds = watch_parser.getTabBrowseIds(
      Map<String, dynamic>.from(watchNext),
    );
    return {
      'tracks': watch_parser.parseWatchPlaylist(contents).take(limit).toList(),
      'playlistId': body['playlistId'],
      'lyrics': tabBrowseIds['MUSIC_PAGE_TYPE_TRACK_LYRICS'],
      'related': tabBrowseIds['MUSIC_PAGE_TYPE_TRACK_RELATED'],
      'additionalParamsForNext': token,
    };
  }

  String? _continuationToken(Map panel) {
    try {
      return getContinuationParams(Map<String, dynamic>.from(panel));
    } catch (_) {}
    // Radio queues use `nextRadioContinuationData`; playlists use
    // `nextContinuationData`. ytmusicapi only looks for the latter.
    final continuations = panel['continuations'];
    if (continuations is List && continuations.isNotEmpty) {
      final first = continuations.first;
      if (first is Map) {
        final data = first['nextRadioContinuationData'] ??
            first['nextContinuationData'];
        if (data is Map && data['continuation'] is String) {
          return getContinuationString(data['continuation'] as String);
        }
      }
    }
    return null;
  }
}

class _NextSession {
  _NextSession(this.body);
  final JsonMap body;
}
