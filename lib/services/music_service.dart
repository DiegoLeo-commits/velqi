// ignore_for_file: constant_identifier_names

import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:get/get.dart' as getx;
import 'package:hive/hive.dart';
import 'package:ytmusicapi_dart/continuations.dart';
import 'package:ytmusicapi_dart/enums.dart' show SearchFilterType;
import 'package:ytmusicapi_dart/type_alias.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

import '/models/album.dart';
import '/models/artist.dart';
import '/models/playlist.dart';
import '/models/media_Item_builder.dart';
import 'innertube_extras.dart';
import 'stream_service.dart';
import 'ytmusic_mapper.dart';

enum AudioQuality {
  Low,
  High,
}

/// Browse / search / metadata client — now **pure Dart**.
///
/// This used to delegate to an embedded Python server (ytmusicapi over HTTP).
/// It now calls the `ytmusicapi_dart` package in-process: same library the
/// backend wrapped, same JSON shapes, but no server, no process lifecycle,
/// instant startup and full `flutter run` hot-reload.
class MusicServices extends getx.GetxService {
  String _hlCode = 'en';
  Future<YTMusic>? _ytFuture;
  Map<String, String>? _auth;
  Map<String, dynamic>? _accountInfo;
  String? _cookieHeader;

  final Map<String, _SearchState> _searchStates = {};
  final Map<String, _ShelfState> _shelfStates = {};
  int _searchSeq = 0;

  @override
  void onInit() {
    init();
    super.onInit();
  }

  Future<void> init() async {
    try {
      _hlCode = Hive.box('AppPrefs').get('contentLanguage') ?? 'en';
    } catch (_) {
      _hlCode = 'en';
    }
    // Restore the saved session before the first screen requests data, so
    // library calls do not race an anonymous client.
    try {
      final saved = Hive.box('AppPrefs').get('userCookiesContent') as String?;
      if (saved != null && saved.trim().isNotEmpty) {
        _installAuth(saved);
      }
    } catch (_) {
      // A corrupt preference must never prevent the app from starting.
    }
  }

  set hlCode(String code) {
    if (code == _hlCode) return;
    _hlCode = code;
    // Recreate the client with the new language, keeping the account session.
    _ytFuture = null;
    if (_auth != null) {
      _ytFuture = YTMusic.create(language: _hlCode, auth: _auth);
    }
  }

  String get hlCode => _hlCode;

  bool get isAuthenticated => _auth != null;

  /// Raw `Cookie` header of the active account, when signed in.
  String? get cookieHeader => _cookieHeader;

  Map<String, dynamic>? get accountInfo => _accountInfo;

  Future<YTMusic> get _yt =>
      _ytFuture ??= YTMusic.create(language: _hlCode);

  Future<InnerTubeExtras> get _extras async => InnerTubeExtras(await _yt);

  void _installAuth(String rawCookie) {
    final auth = InnerTubeExtras.authFromCookie(rawCookie);
    if (auth == null) {
      throw StateError('cookieMissingSapisid');
    }
    _auth = auth;
    _cookieHeader = auth['cookie'];
    StreamProvider.setCookie(_cookieHeader);
    _ytFuture = YTMusic.create(language: _hlCode, auth: auth);
  }

  /// Applies YouTube cookies (Netscape file, Cookie header or exported JSON)
  /// and validates them against the account endpoint.
  ///
  /// Returns the detected account so the settings dialog can show it.
  /// Throws when the cookie has no SAPISID or YouTube rejects the session.
  Future<Map<String, dynamic>?> postCookies(String cookieContent) async {
    final normalized = InnerTubeExtras.normalizeCookie(cookieContent);
    if (normalized.isEmpty) {
      await clearCookies();
      return null;
    }
    final previousAuth = _auth;
    final previousCookie = _cookieHeader;
    final previousInfo = _accountInfo;
    try {
      _installAuth(normalized);
      final info = await InnerTubeExtras(await _yt).accountInfo();
      if (info == null) {
        throw StateError('invalidCookies');
      }
      _accountInfo = info;
      return info;
    } catch (_) {
      _auth = previousAuth;
      _cookieHeader = previousCookie;
      _accountInfo = previousInfo;
      StreamProvider.setCookie(previousCookie);
      _ytFuture = previousAuth == null
          ? YTMusic.create(language: _hlCode)
          : YTMusic.create(language: _hlCode, auth: previousAuth);
      rethrow;
    }
  }

  Future<void> clearCookies() async {
    final old = _ytFuture;
    _auth = null;
    _cookieHeader = null;
    _accountInfo = null;
    StreamProvider.setCookie(null);
    _ytFuture = YTMusic.create(language: _hlCode);
    if (old != null) {
      old.then((client) => client.close()).catchError((_) {});
    }
  }

  Future<Map<String, dynamic>?> refreshAccountInfo() async {
    if (_auth == null) {
      _accountInfo = null;
      return null;
    }
    _accountInfo = await InnerTubeExtras(await _yt).accountInfo();
    return _accountInfo;
  }

  // ---------------------------------------------------------------------------
  // Account library
  // ---------------------------------------------------------------------------

  Future<List<Playlist>> getLibraryPlaylists({int? limit}) async {
    final rows = await (await _extras).libraryPlaylists(limit: limit);
    return rows.map(Playlist.fromJson).toList();
  }

  Future<List<MediaItem>> getLibrarySongs({int? limit}) async {
    final page = await (await _extras).librarySongs(limit: limit);
    final tracks = (page['tracks'] as List?) ?? const [];
    return tracks
        .map((track) => _build(YtMusicMapper.classify(track)))
        .whereType<MediaItem>()
        .toList();
  }

  Future<List<Album>> getLibraryAlbums({int? limit}) async {
    final rows = await (await _extras).libraryAlbums(limit: limit);
    final out = <Album>[];
    for (final row in rows) {
      try {
        final normalized = Map<String, dynamic>.from(row);
        final thumbs = normalized['thumbnails'];
        if (thumbs is! List || thumbs.isEmpty) {
          normalized['thumbnails'] = [
            {'url': ''}
          ];
        }
        out.add(Album.fromJson(normalized));
      } catch (_) {}
    }
    return out;
  }

  Future<List<Artist>> getLibraryArtists({int? limit}) async {
    final rows = await (await _extras).libraryArtists(limit: limit);
    return rows.map(_artistFromRaw).whereType<Artist>().toList();
  }

  Future<List<Artist>> getLibrarySubscriptions({int? limit}) async {
    final rows = await (await _extras).librarySubscriptions(limit: limit);
    return rows.map(_artistFromRaw).whereType<Artist>().toList();
  }

  Artist? _artistFromRaw(Map<String, dynamic> raw) {
    try {
      final normalized = Map<String, dynamic>.from(raw);
      normalized['artist'] ??= normalized['title'];
      final thumbs = normalized['thumbnails'];
      if (thumbs is! List || thumbs.isEmpty) {
        normalized['thumbnails'] = [
          {'url': ''}
        ];
      }
      return Artist.fromJson(normalized);
    } catch (_) {
      return null;
    }
  }

  /// Listening history grouped in shelves (Today, Yesterday, ...).
  Future<List<Map<String, dynamic>>> getHistorySections() async {
    final sections = await (await _extras).history();
    return sections
        .map((section) => {
              'title': section['title'] ?? '',
              'contents': _buildList(section['contents']),
            })
        .toList();
  }

  Future<void> rateSong(String videoId,
      {required bool liked, bool disliked = false}) async {
    final rating = disliked ? 'dislike' : (liked ? 'like' : 'none');
    await (await _extras).setRating(videoId, rating);
  }

  Future<void> subscribeArtist(String channelId,
      {bool subscribe = true}) async {
    await (await _extras).subscribeChannel(channelId, subscribe: subscribe);
  }

  Future<String> createAccountPlaylist(
    String title, {
    String description = '',
    String privacyStatus = 'PRIVATE',
    List<String>? videoIds,
  }) async =>
      (await _extras).createPlaylist(
        title,
        description: description,
        privacyStatus: privacyStatus,
        videoIds: videoIds,
      );

  Future<void> renameAccountPlaylist(String playlistId, String title) async {
    await (await _extras).renamePlaylist(playlistId, title);
  }

  Future<void> deleteAccountPlaylist(String playlistId) async {
    await (await _extras).deletePlaylist(playlistId);
  }

  Future<void> addSongToAccountPlaylist(
          String playlistId, String videoId) async {
    await (await _extras).addSongToPlaylist(playlistId, videoId);
  }

  Future<void> removeSongFromAccountPlaylist(
          String playlistId, JsonMap item) async {
    await (await _extras).removeSongFromPlaylist(playlistId, [item]);
  }

  /// Build the right model object from a `_type`-tagged item.
  dynamic _build(dynamic raw) {
    if (raw is! Map) return null;
    final item = Map<dynamic, dynamic>.from(raw);
    switch (item['_type']) {
      case 'song':
      case 'video':
        if (item['videoId'] == null) return null;
        return MediaItemBuilder.fromJson(item);
      case 'album':
        if (item['browseId'] == null) return null;
        return Album.fromJson(item);
      case 'playlist':
        if (item['playlistId'] == null) return null;
        return Playlist.fromJson(item);
      case 'artist':
        if (item['browseId'] == null) return null;
        return Artist.fromJson(item);
      default:
        return null;
    }
  }

  List _buildList(dynamic list) =>
      ((list as Iterable?) ?? const [])
          .map((e) => _build(e))
          .where((e) => e != null)
          .toList();

  /// Map a list of {title, contents:[...]} sections, building each item.
  List<Map<String, dynamic>> _buildSections(dynamic data) {
    final List sections = (data as List?) ?? [];
    return sections
        .whereType<Map>()
        .map<Map<String, dynamic>>((s) => {
              'title': s['title'] ?? '',
              'contents': _buildList(s['contents']),
            })
        .toList();
  }

  Future<dynamic> getHome({int limit = 4}) async {
    final yt = await _yt;
    final data = await yt.getHome(limit: limit);
    final sections = data
        .whereType<Map>()
        .map(YtMusicMapper.section)
        .where((s) => (s['contents'] as List).isNotEmpty)
        .toList();
    return _buildSections(sections);
  }

  Future<List<Map<String, dynamic>>> getCharts(String catogory,
      {String? countryCode}) async {
    final yt = await _yt;
    final data = await yt.getCharts(country: countryCode ?? 'ZZ');
    final out = <Map<String, dynamic>>[];

    List _items(String key) {
      final v = data[key];
      if (v is Map) return (v['items'] as List?) ?? [];
      return v is List ? v : [];
    }

    final videos = _items('videos').isNotEmpty
        ? _items('videos')
        : _items('trending').isNotEmpty
            ? _items('trending')
            : _items('songs');
    if (videos.isNotEmpty) {
      out.add({
        'title': 'Top Music Videos',
        'contents': _buildList(
            videos.take(24).map((v) => YtMusicMapper.classify(v)))
      });
    }
    for (final entry in [('daily', 'Daily Top'), ('weekly', 'Weekly Top')]) {
      final pls = _items(entry.$1);
      if (pls.isNotEmpty) {
        out.add({
          'title': entry.$2,
          'contents':
              _buildList(pls.take(24).map((p) => YtMusicMapper.classify(p)))
        });
      }
    }
    final genres = _items('genres');
    if (genres.isNotEmpty) {
      out.add({
        'title': 'Genres',
        'contents':
            _buildList(genres.take(24).map((g) => YtMusicMapper.classify(g)))
      });
    }
    final artists = _items('artists');
    if (artists.isNotEmpty) {
      out.add({
        'title': 'Top Artists',
        'contents':
            _buildList(artists.take(24).map((a) => YtMusicMapper.classify(a)))
      });
    }
    return out;
  }

  Future<Map<String, dynamic>> getWatchPlaylist(
      {String videoId = "",
      String? playlistId,
      int limit = 25,
      bool radio = false,
      bool shuffle = false,
      String? additionalParamsNext,
      bool onlyRelated = false}) async {
    if (videoId.isEmpty && playlistId == null) {
      throw Exception(
          "You must provide either a video id, a playlist id, or both");
    }
    final extras = await _extras;
    final Map data;
    if (!onlyRelated &&
        additionalParamsNext != null &&
        additionalParamsNext.isNotEmpty) {
      data = await extras.nextPage(additionalParamsNext, limit: limit);
    } else {
      data = await extras.watchPlaylist(
        videoId: videoId.isEmpty ? null : videoId,
        playlistId: playlistId,
        limit: limit,
        radio: radio,
        shuffle: shuffle,
      );
    }
    if (onlyRelated) {
      return {'lyrics': data['lyrics'], 'related': data['related']};
    }
    final tracks = (data['tracks'] as List?) ?? const [];
    return {
      'tracks': tracks
          .map((t) => _build(YtMusicMapper.classify(t)))
          .where((e) => e != null)
          .toList(),
      'playlistId': data['playlistId'] ?? playlistId,
      'lyrics': data['lyrics'],
      'related': data['related'],
      'additionalParamsForNext': data['additionalParamsForNext'],
    };
  }

  Future<String> getAlbumBrowseId(String audioPlaylistId) async {
    final yt = await _yt;
    final bid = await yt.getAlbumBrowseId(audioPlaylistId);
    return bid ?? audioPlaylistId;
  }

  dynamic getContentRelatedToSong(String videoId, String hlCode) async {
    final yt = await _yt;
    final wp = await yt.getWatchPlaylist(videoId: videoId, limit: 1);
    final related = wp['related'];
    if (related == null || related.toString().isEmpty) return [];
    final raw = await yt.getSongRelated(related.toString());
    final sections =
        raw.whereType<Map>().map(YtMusicMapper.section).toList();
    return _buildSections(
        sections.where((s) => (s['contents'] as List).isNotEmpty).toList());
  }

  dynamic getLyrics(String browseId) async {
    try {
      final yt = await _yt;
      final res = await yt.getLyrics(browseId, timestamps: false);
      if (res != null && res.containsKey('lyrics')) return res['lyrics'];
      return res;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>> getPlaylistOrAlbumSongs(
      {String? playlistId,
      String? albumId,
      int limit = 3000,
      bool related = false,
      int suggestionsLimit = 0}) async {
    final yt = await _yt;
    if (albumId != null) {
      final data = await yt.getAlbum(albumId);
      final map = Map<String, dynamic>.from(data);
      final thumbs = _thumbsOf(data);
      map['tracks'] = _buildList((data['tracks'] as List?)?.map((t) =>
          YtMusicMapper.classifyWithThumbs(t, thumbs)));
      map['duration_seconds'] = _sumDuration(map['tracks']);
      return map;
    }
    final data = await yt.getPlaylist(playlistId!, limit: limit);
    final map = Map<String, dynamic>.from(data);
    final thumbs = _thumbsOf(data);
    map['tracks'] = _buildList((data['tracks'] as List?)?.map((t) =>
        YtMusicMapper.classifyWithThumbs(t, thumbs)));
    map['duration_seconds'] = _sumDuration(map['tracks']);
    return map;
  }

  List<Map<String, dynamic>> _thumbsOf(Map data) {
    final th = data['thumbnails'];
    if (th is List && th.isNotEmpty) {
      return th.whereType<Map>().map((t) => {'url': t['url'] ?? ''}).toList();
    }
    return [{'url': ''}];
  }

  int _sumDuration(List tracks) {
    int total = 0;
    for (final t in tracks) {
      try {
        total += (t.duration?.inSeconds as int?) ?? 0;
      } catch (_) {}
    }
    return total;
  }

  Future<List<String>> getSearchSuggestion(String queryStr) async {
    final yt = await _yt;
    final res = await yt.getSearchSuggestions(queryStr, detailedRuns: false);
    if (res is List) {
      return res
          .map((e) => e is Map ? (e['text']?.toString() ?? '') : e.toString())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return [];
  }

  /// Specially created for deep-links.
  Future<List> getSongWithId(String songId) async {
    try {
      final yt = await _yt;
      final info = await yt.getSong(songId);
      final details = info['videoDetails'] is Map
          ? info['videoDetails'] as Map
          : const <String, dynamic>{};
      final isMusic = details.containsKey('musicVideoType');
      final wp = await yt.getWatchPlaylist(videoId: songId, limit: 25);
      final tracks = ((wp['tracks'] as List?) ?? [])
          .map((t) => _build(YtMusicMapper.classify(t)))
          .where((e) => e != null)
          .toList();
      return [isMusic, tracks];
    } catch (_) {
      return [false, null];
    }
  }

  Future<Map<String, dynamic>> search(String query,
      {String? filter,
      String? scope,
      int limit = 30,
      bool ignoreSpelling = false,
      String? filterParams}) async {
    final yt = await _yt;
    final SearchFilterType? filterType;
    switch (filter) {
      case 'songs':
        filterType = SearchFilterType.songs;
        break;
      case 'videos':
        filterType = SearchFilterType.videos;
        break;
      case 'albums':
        filterType = SearchFilterType.albums;
        break;
      case 'artists':
        filterType = SearchFilterType.artists;
        break;
      case 'playlists':
      case 'community_playlists':
        filterType = SearchFilterType.community_playlists;
        break;
      case 'featured_playlists':
        filterType = SearchFilterType.featured_playlists;
        break;
      default:
        filterType = null;
    }

    final raw = await yt.search(query,
        filter: filterType, scope: scope, limit: limit,
        ignoreSpelling: ignoreSpelling);

    final buckets = <String, List>{
      "Songs": [],
      "Videos": [],
      "Albums": [],
      "Artists": [],
      "Community playlists": [],
      "Featured playlists": [],
    };
    for (final it in raw) {
      if (it is! Map) continue;
      final rt = it['resultType']?.toString();
      final mapped = YtMusicMapper.classify(it);
      if (mapped == null) continue;
      switch (rt) {
        case 'song':
          buckets["Songs"]!.add(mapped);
          break;
        case 'video':
          buckets["Videos"]!.add(mapped);
          break;
        case 'album':
          buckets["Albums"]!.add(mapped);
          break;
        case 'artist':
          buckets["Artists"]!.add(mapped);
          break;
        case 'playlist':
          // A 'playlist' result MUST build a Playlist object. classify() can
          // mis-tag community playlists as albums (MPRE browseId wins first,
          // or the non-MPRE catch-all branch), which crashed this tab with
          // "type 'Album' is not a subtype of type 'Playlist?'" and opened
          // the album screen with "Invalid album browseId provided".
          // Stripping browseId forces classification by playlistId; entries
          // without a playlistId are dropped (unopenable anyway).
          if (it['playlistId'] != null) {
            final forced = Map<dynamic, dynamic>.from(it);
            forced['browseId'] = null;
            final playlistModel = YtMusicMapper.classify(forced);
            if (playlistModel != null) {
              buckets["Community playlists"]!.add(playlistModel);
            }
          }
          break;
      }
    }

    if (filterType != null) {
      // Filtered call: return a single display-named bucket + no-more marker.
      final name = _filterToDisplay(filter);
      var items = buckets[name] ?? [];
      if (items.isEmpty) {
        for (final b in buckets.values) {
          items.addAll(b);
        }
      }
      final token = 'velqi_search_${_searchSeq++}';
      _searchStates[token] = _SearchState(
        query: query,
        filter: filter,
        display: name,
        fetched: items.length,
      );
      // Keep the cache bounded; old scroll sessions are not resumable anyway.
      while (_searchStates.length > 24) {
        _searchStates.remove(_searchStates.keys.first);
      }
      return {
        name: _buildList(items),
        'params': {
          'additionalParams': '&ctoken=$token&continuation=$token',
          'continuation': token,
          'category': name,
        },
      };
    }

    // Unfiltered: build searchEndpoint chips for the tabs that have results.
    final out = <String, dynamic>{'searchEndpoint': <String, dynamic>{}};
    for (final entry in buckets.entries) {
      if (entry.value.isNotEmpty) {
        out[entry.key] = _buildList(entry.value);
        (out['searchEndpoint'] as Map)[entry.key] = entry.key;
      }
    }
    return out;
  }

  String _filterToDisplay(String? filter) {
    switch (filter) {
      case 'songs':
        return 'Songs';
      case 'videos':
        return 'Videos';
      case 'albums':
        return 'Albums';
      case 'artists':
        return 'Artists';
      case 'playlists':
      case 'community_playlists':
        return 'Community playlists';
      case 'featured_playlists':
        return 'Featured playlists';
      default:
        return filter ?? '';
    }
  }

  /// Next page for a search tab.
  ///
  /// `ytmusicapi_dart` resolves continuations internally and does not expose
  /// the token, so the first filtered search leaves a state handle here and
  /// this method re-queries with a larger limit, returning only the new rows.
  /// The UI still gets genuine endless scrolling and never duplicates items.
  Future<Map<String, dynamic>> getSearchContinuation(Map additionalParamsNext,
      {int limit = 25}) async {
    final category = additionalParamsNext['category']?.toString();
    final params = additionalParamsNext['additionalParams']?.toString() ?? '';
    final token = _tokenFromParams(params);
    final state = _searchStates[token];
    final noMore = <String, dynamic>{
      'additionalParams': '&ctoken=null&continuation=null',
    };

    if (state == null) {
      return {
        if (category != null) category: [],
        'params': noMore,
      };
    }

    final yt = await _yt;
    final filterType = _filterType(state.filter);
    final all = await yt.search(
      state.query,
      filter: filterType,
      limit: state.fetched + limit,
      ignoreSpelling: true,
    );
    final requested = state.fetched + limit;
    final fresh = all.skip(state.fetched).take(limit).toList();
    final exhausted = fresh.isEmpty || all.length < requested;
    state.fetched = all.length;

    final mapped = _buildList(
      fresh.map(YtMusicMapper.classify),
    );
    if (!exhausted) {
      // Keep the state for the next scroll; otherwise drop it.
    } else {
      _searchStates.remove(token);
    }

    return {
      if (category != null) category: mapped,
      'params': {
        'additionalParams':
            exhausted ? noMore['additionalParams'] : params,
        'category': state.display,
      },
    };
  }

  String? _tokenFromParams(String params) {
    final match = RegExp(r'[?&]ctoken=([^&]+)').firstMatch(params);
    if (match == null) return null;
    final token = Uri.decodeComponent(match.group(1)!);
    return token == 'null' ? null : token;
  }

  SearchFilterType? _filterType(String? filter) {
    switch (filter) {
      case 'songs':
        return SearchFilterType.songs;
      case 'videos':
        return SearchFilterType.videos;
      case 'albums':
        return SearchFilterType.albums;
      case 'artists':
        return SearchFilterType.artists;
      case 'playlists':
      case 'community_playlists':
        return SearchFilterType.community_playlists;
      case 'featured_playlists':
        return SearchFilterType.featured_playlists;
      default:
        return null;
    }
  }

  Future<Map<String, dynamic>> getArtist(String channelId) async {
    final yt = await _yt;
    final data = await yt.getArtist(channelId);
    final map = Map<String, dynamic>.from(data);

    Map<String, dynamic> _sec(String key) {
      final block = data[key];
      if (block is! Map) {
        return {
          'browseId': null,
          'params': null,
          'content': <dynamic>[],
        };
      }
      final results = (block['results'] as List?) ?? [];
      return {
        'browseId': block['browseId'],
        'params': block['params'],
        'content': _buildList(results.map(YtMusicMapper.classify)),
      };
    }

    return {
      ...map,
      'Songs': _sec('songs'),
      'Videos': _sec('videos'),
      'Albums': _sec('albums'),
      'Singles': _sec('singles'),
    };
  }

  /// "View all" sections of an artist page.
  ///
  /// Albums/Singles are fetched through `getArtistAlbums`, which paginates
  /// internally. Songs/Videos keep the raw shelf token so the scroll in the
  /// existing Material 2 artist screen can actually load the next page.
  Future<Map<String, dynamic>> getArtistRealtedContent(
      Map<String, dynamic> browseEndpoint, String category,
      {String additionalParams = ""}) async {
    final yt = await _yt;
    final channelId = (browseEndpoint['browseId'] ?? '').toString();
    final params = (browseEndpoint['params'] ?? '').toString();
    if (channelId.isEmpty) {
      return {'results': <dynamic>[], 'additionalParams': null};
    }

    if (category == 'Albums' || category == 'Singles') {
      final albums = await yt.getArtistAlbums(channelId, params, limit: 100);
      return {
        'results': _buildList(albums.map(YtMusicMapper.classify)),
        'additionalParams': null,
      };
    }

    if (additionalParams.isNotEmpty) {
      final token = _tokenFromParams(additionalParams);
      final state = _shelfStates[token];
      if (state == null) {
        return {'results': <dynamic>[], 'additionalParams': null};
      }
      final response = await yt.sendRequest(
        'browse',
        {'browseId': state.browseId, 'params': state.params},
        additionalParams: token!,
      );
      final contents = _continuationContents(response);
      final next = _continuationToken(contents, response);
      if (next == null) {
        _shelfStates.remove(token);
      } else {
        _shelfStates[next] = _ShelfState(state.browseId, state.params, next);
      }
      return {
        'results': _buildList(contents.map(YtMusicMapper.classify)),
        'additionalParams': next == null
            ? null
            : '&ctoken=$next&continuation=$next',
      };
    }

    final response = await yt.sendRequest(
      'browse',
      {'browseId': channelId, 'params': params},
    );
    final shelf = _findMusicShelf(response);
    if (shelf == null) {
      return {'results': <dynamic>[], 'additionalParams': null};
    }
    final contents = List<JsonMap>.from((shelf['contents'] as List?) ?? [])
        .where((item) => item['musicResponsiveListItemRenderer'] != null)
        .toList();
    final token = _continuationToken(contents, shelf);
    if (token != null) {
      _shelfStates[token] = _ShelfState(channelId, params, token);
    }
    return {
      'results': _buildList(contents.map(YtMusicMapper.classify)),
      'additionalParams':
          token == null ? null : '&ctoken=$token&continuation=$token',
    };
  }

  List<JsonMap> _continuationContents(JsonMap response) {
    final cont = response['continuationContents'];
    if (cont is Map && cont['musicShelfContinuation'] is Map) {
      final shelf = cont['musicShelfContinuation'] as Map;
      return List<JsonMap>.from((shelf['contents'] as List?) ?? [])
          .where((item) => item['musicResponsiveListItemRenderer'] != null)
          .toList();
    }
    final actions = response['onResponseReceivedActions'];
    if (actions is List) {
      for (final action in actions) {
        if (action is! Map) continue;
        final items =
            action['appendContinuationItemsAction']?['continuationItems'];
        if (items is List) {
          return List<JsonMap>.from(items)
              .where((item) => item['musicResponsiveListItemRenderer'] != null)
              .toList();
        }
      }
    }
    return const [];
  }

  String? _continuationToken(List<JsonMap> contents, JsonMap parent) {
    try {
      return getContinuationParams(parent);
    } catch (_) {}
    if (contents.isNotEmpty) {
      final token = getContinuationToken(List<JsonMap>.from(contents));
      if (token != null) return token;
    }
    final raw = parent['contents'];
    if (raw is List) {
      try {
        return getContinuationToken(List<JsonMap>.from(raw));
      } catch (_) {}
    }
    return null;
  }

  JsonMap? _findMusicShelf(dynamic node) {
    if (node is Map) {
      final shelf = node['musicShelfRenderer'];
      if (shelf is Map &&
          shelf['contents'] is List &&
          (shelf['contents'] as List).any(
              (item) => item is Map && item['musicResponsiveListItemRenderer'] != null)) {
        return Map<String, dynamic>.from(shelf);
      }
      for (final value in node.values) {
        final found = _findMusicShelf(value);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = _findMusicShelf(value);
        if (found != null) return found;
      }
    }
    return null;
  }

  Future<String?> getSongYear(String songId) async {
    try {
      final info = await (await _yt).getSong(songId);
      final micro = info['microformat']?['microformatRenderer'];
      final date = micro?['publishDate'] ?? micro?['uploadDate'];
      if (date is String && date.length >= 4) return date.substring(0, 4);
    } catch (_) {}
    return null;
  }

  @override
  void onClose() {
    final yt = _ytFuture;
    if (yt != null) {
      yt.then((v) => v.close()).catchError((_) {});
    }
    super.onClose();
  }
}

class NetworkError extends Error {
  final message = "Network Error !";
}


class _SearchState {
  _SearchState({
    required this.query,
    required this.filter,
    required this.display,
    required this.fetched,
  });

  final String query;
  final String? filter;
  final String display;
  int fetched;
}

class _ShelfState {
  _ShelfState(this.browseId, this.params, this.token);

  final String browseId;
  final String params;
  final String token;
}
