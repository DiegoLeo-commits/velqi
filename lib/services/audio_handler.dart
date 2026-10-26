import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_service/audio_service.dart';
// ignore: depend_on_referenced_packages
import 'package:rxdart/rxdart.dart';

import '/models/album.dart';
import '../models/playlist.dart';
import '/services/discord_rpc_service.dart';
import '/services/equalizer.dart';
import '/services/stream_service.dart';
import '/models/hm_streaming_data.dart';
import '/ui/player/player_controller.dart';
import '../ui/screens/Home/home_screen_controller.dart';
import '/services/permission_service.dart';
import '../utils/helper.dart';
import '/models/media_Item_builder.dart';
import '/services/utils.dart';
import '../ui/screens/Settings/settings_screen_controller.dart';
import '../ui/screens/Library/library_controller.dart';

Future<AudioHandler> initAudioService() async {
  return await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationIcon: 'mipmap/velqi_notification',
      androidNotificationChannelId: 'com.velqi.app.audio',
      androidNotificationChannelName: 'Velqi Notification',
      androidNotificationOngoing: false,
      // Keep the service+notification in the foreground even while paused so
      // the media controls are always available (and avoid the Android 12+
      // stopForeground/startForeground flakiness that can hide the
      // notification). NOTE: audio_service asserts that these two flags must
      // stay consistent (ongoing only works when stopping on pause).
      androidStopForegroundOnPause: false,
    ),
  );
}

class MyAudioHandler extends BaseAudioHandler with GetxServiceMixin {
  // ignore: prefer_typing_uninitialized_variables
  late final _cacheDir;
  late AudioPlayer _player;

  /// Android audio session id of the ExoPlayer that is actually playing
  /// (registered once playback starts). The real visualizer binds to THIS
  /// session — session 0 (output mix) fails on emulators like BlueStacks.
  int? get androidAudioSessionId => _player.androidAudioSessionId;

  /// Emits the session id (with the latest value replayed) whenever ExoPlayer
  /// gets a session; null when there is none yet.
  Stream<int?> get androidAudioSessionIdStream =>
      _player.androidAudioSessionIdStream;
  late MediaLibrary _mediaLibrary;
  // ignore: prefer_typing_uninitialized_variables
  dynamic currentIndex;
  int currentShuffleIndex = 0;
  // NOT `late`: play() reads this before any song is loaded and a
  // LateInitializationError would silently kill the whole playback flow.
  String? currentSongUrl;

  /// File-based debug log: release builds on Windows detach stdout, so print()
  /// output is unreliable. This always lands on disk.
  /// NOTE: statics are per-isolate — when called from an Isolate.run closure
  /// [_dlogDir] is null there, so fall back to the system temp dir.
  static void dlog(String msg) {
    try {
      final base = _dlogDir ?? Directory.systemTemp.path;
      File('$base${Platform.pathSeparator}velqi_dart.log').writeAsStringSync(
          '[${DateTime.now().toIso8601String().substring(11, 19)}] $msg\n',
          mode: FileMode.append);
    } catch (_) {}
  }

  static String? _dlogDir;

  static Future<void> _initDlogDir() async {
    try {
      _dlogDir = (await getTemporaryDirectory()).path;
    } catch (_) {
      _dlogDir = null;
    }
  }
  bool isPlayingUsingLockCachingSource = false;
  bool loopModeEnabled = false;
  bool queueLoopModeEnabled = false;
  bool shuffleModeEnabled = false;
  bool loudnessNormalizationEnabled = false;
  // var networkErrorPause = false;
  bool isSongLoading = true;
  bool _notificationPromptShown = false;

  // Stored player-bound subscriptions so they can be re-attached to the
  // active player after a crossfade role-swap.
  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<SequenceState?>? _sequenceSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<int?>? _sessionIdSub;

  // Desktop-only: just_audio_windows (WMF) may not fire playbackEventStream
  // frequently enough for smooth seekbar updates. A polling timer fixes this.
  Timer? _desktopPositionTimer;

  // list of shuffled queue songs ids
  List<String> shuffledQueue = [];

  final _playList =
      ConcatenatingAudioSource(children: [], useLazyPreparation: false);
  // _activeList always points to _playList.
  ConcatenatingAudioSource get _activeList => _playList;

  /// Desktop (just_audio_windows): the WinRT player crashes natively on
  /// ConcatenatingAudioSource mutations (clear/insert/remove) while an item is
  /// loaded, so we swap a single source per song instead. Android keeps the
  /// concatenating playlist for gapless queue behaviour.
  bool get _usesSingleSource => GetPlatform.isDesktop;

  Future<void> _setPlaybackSource(AudioSource source) async {
    if (_usesSingleSource) {
      // media_kit/libmpv swaps sources natively — a plain setAudioSource is
      // all it takes (no WMF sourceNotSupported/00:00 pitfalls anymore).
      await _player.setAudioSource(source);
      dlog('[SRC] setAudioSource OK state=${_player.processingState}');
    } else {
      await _activeList.add(source);
    }
  }

  MyAudioHandler() {
    _initDlogDir();
    _invalidateLegacyUrlCache();

    // Desktop: use media_kit/libmpv as the playback engine instead of
    // just_audio_windows (Windows Media Foundation). libmpv plays YouTube's
    // googlevideo URLs directly (redirects, ranges, DASH all handled) — this
    // kills the whole family of WMF bugs (sourceNotSupported, second-song
    // stuck at 00:00, silent starts). Android keeps ExoPlayer untouched.
    if (GetPlatform.isDesktop) {
      try {
        JustAudioMediaKit.ensureInitialized();
        JustAudioMediaKit.title = 'Velqi';
        JustAudioMediaKit.protocolWhitelist = const ['http', 'https', 'file'];
        dlog('[MK] media_kit initialized for desktop');
      } catch (e) {
        dlog('[MK] media_kit init failed: $e');
      }
    }

    _mediaLibrary = MediaLibrary();
    _player = AudioPlayer(
        useProxyForRequestHeaders: !GetPlatform.isDesktop,
        audioLoadConfiguration: const AudioLoadConfiguration(
            androidLoadControl: AndroidLoadControl(
      minBufferDuration: Duration(seconds: 50),
      maxBufferDuration: Duration(seconds: 120),
      bufferForPlaybackDuration: Duration(milliseconds: 50),
      bufferForPlaybackAfterRebufferDuration: Duration(seconds: 2),
    )));
    _createCacheDir();
    _addEmptyList();
    // Debug: log every play/state transition so silence/hang bugs are visible
    // in release builds.
    _player.playerStateStream.listen((ps) {
      dlog('[STATE] playing=${ps.playing} state=${ps.processingState}');
      // Re-arm the auto-advance episode guard whenever the player leaves the
      // completed state (a new source is loading/ready). Without this, one
      // consumed EOF would block every future automatic advance.
      if (ps.processingState != ProcessingState.completed) {
        _autoAdvanceConsumed = false;
      }
      // Desktop (single-source mode) has NO native queue auto-advance: each
      // song is set individually, so EOF must trigger the next song here.
      // Previously only a positionStream near-end check existed, which media_kit
      // never satisfies (position jumps straight to completed/0 at EOF), so
      // songs ended and sat paused at 00:00 with the queue stuck.
      if (GetPlatform.isDesktop &&
          ps.processingState == ProcessingState.completed) {
        _onSongCompleted();
      }
    });
    final appPrefsBox = Hive.box("AppPrefs");
    _player
        .setSkipSilenceEnabled(appPrefsBox.get("skipSilenceEnabled") ?? false);
    loopModeEnabled = appPrefsBox.get("isLoopModeEnabled") ?? false;
    shuffleModeEnabled = appPrefsBox.get("isShuffleModeEnabled") ?? false;
    queueLoopModeEnabled =
        Hive.box("AppPrefs").get("queueLoopModeEnabled") ?? false;
    loudnessNormalizationEnabled =
        appPrefsBox.get("loudnessNormalizationEnabled") ?? false;
    _bindActivePlayerListeners();
  }

  /// One-time wipe of the stream-URL cache: entries written by the old
  /// embedded-backend era (WEB-client or proxy URLs) are unplayable with the
  /// native extractor. A marker key makes the wipe happen exactly once.
  void _invalidateLegacyUrlCache() {
    try {
      final box = Hive.box('SongsUrlCache');
      if (box.get('velqiNativeV2') == true) return;
      box.clear();
      box.put('velqiNativeV2', true);
      dlog('[CACHE] cleared legacy stream-URL cache (new extractor)');
    } catch (_) {}
  }

  Future<void> _createCacheDir() async {
    _cacheDir = (await getTemporaryDirectory()).path;
    if (!Directory("$_cacheDir/cachedSongs/").existsSync()) {
      Directory("$_cacheDir/cachedSongs/").createSync(recursive: true);
    }
  }

  void _addEmptyList() {
    // Desktop (just_audio_windows): setting an EMPTY ConcatenatingAudioSource
    // as the initial source leaves the WinRT player stuck in ProcessingState.loading
    // forever, which deadlocks every later platform call (setVolume/play/...).
    // Skip it — _setPlaybackSource sets a real source per song on desktop.
    if (_usesSingleSource) {
      dlog('[INIT] desktop -> skip empty playlist source');
      return;
    }
    try {
      _player.setAudioSource(_playList);
    } catch (r) {
      printERROR(r.toString());
    }
  }

  void _listenSessionIdStream() {
    _sessionIdSub?.cancel();
    _sessionIdSub = _player.androidAudioSessionIdStream.listen((int? id) {
      if (id != null) {
        EqualizerService.initAudioEffect(id);
      }
    });
  }

  /// (Re)binds all player-output listeners to the currently active [_player].
  /// Called once at startup and again after each crossfade role-swap so the
  /// notification, UI position bar, and next-song trigger always follow the
  /// player that is actually producing sound.
  void _bindActivePlayerListeners() {
    _notifyAudioHandlerAboutPlaybackEvents();
    _listenToPlaybackForNextSong();
    _listenForSequenceStateChanges();
    _listenForDurationChanges();
    if (GetPlatform.isAndroid) {
      _listenSessionIdStream();
    }
    _startDesktopPositionPolling();
  }

  /// Desktop-only: poll player position at ~250ms intervals so the seekbar
  /// stays smooth even when playbackEventStream is infrequent. It also acts
  /// as the bulletproof completion net: if the player ever sits in
  /// `completed` (EOF hook missed it for any reason), advance the queue here.
  void _startDesktopPositionPolling() {
    _desktopPositionTimer?.cancel();
    if (!GetPlatform.isDesktop) return;
    _desktopPositionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      // Completion net: catches EOF even if no stream event fired.
      if (_player.processingState == ProcessingState.completed) {
        _autoAdvance();
        return;
      }
      if (!_player.playing) return;
      final pos = _player.position;
      final dur = _player.duration;
      if (dur == null || dur.inSeconds == 0) return;
      playbackState.add(playbackState.value.copyWith(
        updatePosition: pos,
        bufferedPosition: _player.bufferedPosition,
      ));
    });
  }

  void _notifyAudioHandlerAboutPlaybackEvents() {
    _playbackEventSub?.cancel();
    _playbackEventSub =
        _player.playbackEventStream.listen((PlaybackEvent event) {
      final playing = _player.playing;
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {
          MediaAction.seek,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: isSongLoading
            ? AudioProcessingState.loading
            : const {
                ProcessingState.idle: AudioProcessingState.idle,
                ProcessingState.loading: AudioProcessingState.loading,
                ProcessingState.buffering: AudioProcessingState.buffering,
                ProcessingState.ready: AudioProcessingState.ready,
                ProcessingState.completed: AudioProcessingState.completed,
              }[_player.processingState]!,
        repeatMode: const {
          LoopMode.off: AudioServiceRepeatMode.none,
          LoopMode.one: AudioServiceRepeatMode.one,
          LoopMode.all: AudioServiceRepeatMode.all,
        }[_player.loopMode]!,
        shuffleMode: (shuffleModeEnabled)
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: currentIndex,
      ));

      //print("set ${playbackState.value.queueIndex},${event.currentIndex}");
    },    onError: (Object e, StackTrace st) async {        dlog('[PLAYER ERROR] type=${e.runtimeType} $e');
        printINFO('PLAYER ERROR: $e');
      if (e is PlayerException) {
        dlog('Error code: ${e.code} msg: ${e.message}');
        printERROR('Error code: ${e.code}');
        printERROR('Error message: ${e.message}');
      } else {
        dlog('Player error: $e\n${st.toString().split("\n").take(5).join("\n")}');
        printERROR('An error occurred: $e');
        Duration curPos = _player.position;
        await _player.stop();

        if (isPlayingUsingLockCachingSource &&
            e.toString().contains("Connection closed while receiving data")) {
          await _player.seek(curPos, index: 0);
          if (!_userPaused) await _player.play();
          return;
        }

        // Safety valve for the retry chain: if the SAME song keeps failing to
        // start (e.g. "Source error" on a codec/decoder the device lacks, or
        // a persistent network block), stop re-resolving forever — that made
        // a silent infinite loop (error -> newUrl retry -> error ...). Two
        // consecutive failures on one index surface a REAL error instead.
        _consecutiveSourceErrors += 1;
        if (_consecutiveSourceErrors >= 2) {
          dlog('[PLAYER ERROR] 2 consecutive failures on index=$currentIndex — giving up');
          _consecutiveSourceErrors = 0;
          currentSongUrl = null;
          isSongLoading = false;
          Get.find<PlayerController>().notifyPlayError(
              'Could not play this song on this device');
          playbackState.add(playbackState.value.copyWith(
              processingState: AudioProcessingState.error,
              errorCode: 500,
              errorMessage: 'Could not play this song on this device'));
          return;
        }

        // If the user deliberately paused, do NOT auto-resume on an error —
        // the pause must always win.
        if (_userPaused) {
          dlog('[PLAYER ERROR] user paused — not auto-resuming');
          return;
        }

        // 1st strike: re-resolve a FRESH URL to rule out an expired stream,
        // and flip to the opposite format family (progressive <-> adaptive).
        // If YouTube 403s one family from this network/device, the other one
        // usually still plays — this is the "impossible to fail" path.
        printINFO('[TRACE] onError retry (strike $_consecutiveSourceErrors)');
        await customAction("playByIndex", {
          'index': currentIndex,
          'newUrl': true,
          'adaptive': _consecutiveSourceErrors >= 1,
        });
      }
    });
  }

  void _listenToPlaybackForNextSong() {
    _positionSub?.cancel();
    final playerDurationOffset = GetPlatform.isWindows
        ? 200
        : GetPlatform.isLinux
            ? 700
            : 0;
    _positionSub = _player.positionStream.listen((value) async {
      final dur = _player.duration;
      if (dur == null || dur.inSeconds == 0 || value == Duration.zero) return;
      
      // Only trigger completion if playback has made progress beyond initial setup
      if (value.inMilliseconds >= (dur.inMilliseconds - playerDurationOffset) &&
          value.inMilliseconds > 500) {
        await _autoAdvance();
      }
    });
  }

  /// Debounce for auto-advance. Every advance path converges through
  /// [_autoAdvance] so a single guard covers all of them (the old design
  /// guarded twice in the same call chain and blocked its own advance —
  // "song completed -> auto-advance" followed by "advance suppressed").
  /// Consecutive source-failure counter. Guards the onError retry chain
  /// against spinning forever on a song that can never start on this device
  /// (missing codec decoder, persistent network block, etc.).
  int _consecutiveSourceErrors = 0;

  /// Set by [pause()], cleared by explicit play requests. The Android
  /// start-retries in [_startPlaybackReliably] honor it so a user pause
  /// inside the retry window is never overridden.
  bool _userPaused = false;

  DateTime _lastAutoAdvanceAt =
      DateTime.now().subtract(const Duration(days: 1));

  /// True once an automatic advance has been accepted for the current EOF
  /// (see [_autoAdvanceGuarded]). Cleared when the player leaves `completed`.
  bool _autoAdvanceConsumed = false;

  bool _autoAdvanceGuarded() {
    final now = DateTime.now();
    if (now.difference(_lastAutoAdvanceAt).inMilliseconds < 1200) {
      dlog('[SEQ] advance suppressed (debounce)');
      return false;
    }
    // Episode guard: each EOF may advance the queue EXACTLY once. While the
    // next song is being resolved (checkNGetUrl can take seconds on a fresh
    // search queue) the player still reports `completed`, and the 250ms
    // desktop poller + position hook would re-trigger the advance as soon as
    // the time debounce expired — that was the "jumps 4 songs in a row"
    // bug. The flag is cleared when the player leaves `completed` (new
    // source loaded), so the NEXT real EOF can advance again.
    if (_autoAdvanceConsumed) {
      dlog('[SEQ] advance suppressed (already advanced this EOF)');
      return false;
    }
    _autoAdvanceConsumed = true;
    _lastAutoAdvanceAt = now;
    return true;
  }

  /// THE single entry point for automatic queue advancement. Every trigger
  /// (EOF stream hook, desktop poller, position near-end check) funnels
  /// through here: repeat-one restarts the current song, otherwise skip to
  /// the next queue item — wrapping to index 0 at the end of the queue.
  /// A user pause ALWAYS wins: if they paused (even right at the end of the
  /// song), the queue stays put until they act again.
  Future<void> _autoAdvance() async {
    if (_userPaused) {
      dlog('[SEQ] user paused — no auto-advance');
      return;
    }
    // Never advance while a play/resolve is already in flight — the in-flight
    // playByIndex owns the queue right now.
    if (isSongLoading) {
      dlog('[SEQ] advance suppressed (song loading)');
      return;
    }
    if (!_autoAdvanceGuarded()) return;
    if (loopModeEnabled) {
      await _player.seek(Duration.zero);
      if (!_player.playing && !_userPaused) {
        _player.play();
      }
      return;
    }
    dlog('[SEQ] auto-advance -> skipToNext');
    await skipToNext();
  }

  /// EOF hook for desktop: the song truly finished — move to the next queue
  /// item (or restart the queue when reaching the end, wrap-around behavior).
  /// A user pause always wins over auto-advance (the old bug: pausing near
  /// the end made the frozen position trigger the next song instantly).
  Future<void> _onSongCompleted() async {
    if (_userPaused) {
      dlog('[SEQ] user paused — no auto-advance');
      return;
    }
    await _autoAdvance();
  }




  void _listenForSequenceStateChanges() {
    _sequenceSub?.cancel();
    _sequenceSub =
        _player.sequenceStateStream.listen((SequenceState? sequenceState) {
      final sequence = sequenceState?.effectiveSequence;
      if (sequence == null || sequence.isEmpty) return;
    });
  }

  void _listenForDurationChanges() {
    _durationSub?.cancel();
    _durationSub = _player.durationStream.listen((duration) async {
      final currQueue = queue.value;
      if (currentIndex == null || currQueue.isEmpty || duration == null) return;
      final currentSong = queue.value[currentIndex];
      if (currentSong.duration == null || currentIndex == 0) {
        final newMediaItem = currentSong.copyWith(duration: duration);
        mediaItem.add(newMediaItem);
      }
    });
  }

  @override
  Future<void> addQueueItems(List<MediaItem> mediaItems) async {
    // notify system
    final newQueue = queue.value..addAll(mediaItems);
    queue.add(newQueue);

    if (shuffleModeEnabled) {
      final mediaItemsIds = mediaItems.toList().map((item) => item.id).toList();
      final notPlayedshuffledQueue = shuffledQueue.isNotEmpty
          ? shuffledQueue.toList().sublist(currentShuffleIndex + 1)
          : shuffledQueue;
      notPlayedshuffledQueue.addAll(mediaItemsIds);
      notPlayedshuffledQueue.shuffle();
      shuffledQueue.replaceRange(
          currentShuffleIndex, shuffledQueue.length, notPlayedshuffledQueue);
    }
  }

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    final newQueue = this.queue.value
      ..replaceRange(0, this.queue.value.length, queue);
    this.queue.add(newQueue);
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    if (shuffleModeEnabled) {
      shuffledQueue.add(mediaItem.id);
    }

    // notify system
    final newQueue = queue.value..add(mediaItem);
    queue.add(newQueue);
  }

  AudioSource _createAudioSource(MediaItem mediaItem) {
    var url = mediaItem.extras!['url'] as String;
    // Offline songs store a bare filesystem path ("C:/.../song.m4a"). That
    // parses as scheme "c:" and mpv refuses to load it (protocolWhitelist).
    // Normalize to a proper file:// URI so downloaded-library songs play.
    if (!url.contains('://')) {
      try {
        url = Uri.file(url).toString();
        dlog('[SRC] normalized local path -> $url');
      } catch (_) {}
    }
    // Desktop stream URLs are progressive (itag 18) — libmpv plays them
    // directly. LockCachingAudioSource is experimental and broken under
    // just_audio_windows (player shows progress but renders no audio).
    // The local proxy already streams efficiently; use plain sources there.
    final useLockCache = !GetPlatform.isDesktop &&
        (url.contains('/cache') ||
            (Get.find<SettingsScreenController>().cacheSongs.isTrue &&
                url.contains("http")));
    dlog('[SRC] branch=${useLockCache ? 'LockCaching' : 'plain'} url=$url');
    if (useLockCache) {
      printINFO("Playing Using LockCaching");
      isPlayingUsingLockCachingSource = true;
      return LockCachingAudioSource(
        Uri.parse(url),
        cacheFile: File("$_cacheDir/cachedSongs/${mediaItem.id}.mp3"),
        tag: mediaItem,
      );
    }

    printINFO("Playing Using AudioSource.uri");
    isPlayingUsingLockCachingSource = false;
    return AudioSource.uri(
      Uri.tryParse(url)!,
      tag: mediaItem,
    );
  }

  @override
  // ignore: avoid_renaming_method_parameters
  Future<void> removeQueueItem(MediaItem mediaItem_) async {
    if (shuffleModeEnabled) {
      final id = mediaItem_.id;
      final itemIndex = shuffledQueue.indexOf(id);
      if (currentShuffleIndex > itemIndex) {
        currentShuffleIndex -= 1;
      }
      shuffledQueue.remove(id);
    }

    final currentQueue = queue.value;
    final currentSong = mediaItem.value;
    final itemIndex = currentQueue.indexOf(mediaItem_);
    if (currentIndex > itemIndex) {
      currentIndex -= 1;
    }
    currentQueue.remove(mediaItem_);
    queue.add(currentQueue);
    mediaItem.add(currentSong);
  }

  @override
  Future<void> play() async {
    // Android 13+: re-request notifications when playback starts so the
    // media-control notification is always visible while listening.
    printINFO('[TRACE] play() called');
    _userPaused = false;
    _ensureNotificationPermission();
    dlog('[PLAY] play() url=${currentSongUrl != null ? 'set' : 'null'} '
        'state=${_player.processingState} index=$currentIndex');
    // If no URL yet, or player has no source loaded (desktop media_kit),
    // re-resolve and set up the source before playing.
    if (currentSongUrl == null ||
        _player.processingState == ProcessingState.idle) {
      dlog('[PLAY] needs setup -> playByIndex');
      await customAction("playByIndex", {'index': currentIndex});
      return;
    }
    // After a song ends the player stays in `completed`, where plain play()/
    // seek() often refuses to resume (media_kit: playing stays false). A
    // clean restart of the CURRENT song via playByIndex always works — it
    // re-resolves (cache hit) and sets a fresh source.
    if (_player.processingState == ProcessingState.completed) {
      dlog('[PLAY] completed state -> restart current song');
      await customAction("playByIndex", {'index': currentIndex});
      return;
    }
    await _player.play();
    dlog('[PLAY] _player.play() done state=${_player.processingState} playing=${_player.playing}');
    _syncDiscordPresence(playing: true);
  }

  /// Desktop playback start: media_kit/libmpv plays direct googlevideo URLs
  /// natively — a plain play() is reliable (no WinRT prime-seek/retry hacks).
  /// Android keeps the retry loop as a safety net.
  Future<void> _startPlaybackReliably() async {
    if (GetPlatform.isDesktop) {
      // media_kit occasionally REFUSES a play() silently after rapid source
      // swaps (playing stays false, position 00:00) — that was the "queue
      // pauses by itself after a couple of songs" bug. Retry like Android;
      // a user pause always wins over the retries.
      for (int attempt = 0; attempt < 3; attempt++) {
        if (_userPaused) {
          dlog('[AUDIO] desktop retry cancelled — user paused');
          return;
        }
        await _player.play();
        await Future.delayed(const Duration(milliseconds: 250));
        if (_player.playing) {
          dlog('[AUDIO] play() (media_kit) playing=true');
          _syncDiscordPresence(playing: true);
          return;
        }
        dlog('[AUDIO] media_kit refused play(), retry #$attempt');
      }
      dlog('[AUDIO] desktop play() refused after 3 attempts');
      _syncDiscordPresence(playing: false);
      return;
    }
    for (int attempt = 0; attempt < 4; attempt++) {
      // The user's pause wins: if they pressed pause while these retries
      // were pending (e.g. right after the song started), do NOT re-play —
      // that was the "pauso y se despausa sola" bug.
      if (_userPaused) {
        dlog('[PLAY] retry cancelled — user paused');
        return;
      }
      await _player.play();
      await Future.delayed(const Duration(milliseconds: 350));
      if (_player.playing) return;
      dlog('[PLAY] playing=false after play(), retry #$attempt');
    }
    dlog('[PLAY] player refused to start after 4 attempts');
  }

  @override
  Future<void> pause() async {
    printINFO('[TRACE] pause() called');
    _userPaused = true;
    await _player.pause();
    _syncDiscordPresence(playing: false);
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    if (_player.playing) _syncDiscordPresence(playing: true);
  }

  /// Keeps Discord Rich Presence in sync with the player (Spotify-style
  /// "Listening to Velqi" card). No-op on Android.
  void _syncDiscordPresence({required bool playing}) {
    try {
      DiscordRpcService.instance.update(
        mediaItem.value,
        playing: playing,
        position: _player.position,
        duration: _player.duration,
      );
    } catch (_) {}
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    await customAction("playByIndex", {'index': index});
  }

  int _getNextSongIndex() {
    if (shuffleModeEnabled) {
      if (currentShuffleIndex + 1 >= shuffledQueue.length) {
        shuffledQueue.shuffle();
        currentShuffleIndex = 0;
      } else {
        currentShuffleIndex += 1;
      }
      return queue.value
          .indexWhere((item) => item.id == shuffledQueue[currentShuffleIndex]);
    }

    if (queue.value.length > currentIndex + 1) {
      return currentIndex + 1;
    } else {
      // End of the queue: wrap around to the first song so the queue never
      // dead-ends (the old behavior left the player paused at the last song).
      dlog('[SEQ] queue end reached -> wrap to index 0');
      return 0;
    }
  }

  int _getPrevSongIndex() {
    if (shuffleModeEnabled) {
      if (currentShuffleIndex - 1 < 0) {
        shuffledQueue.shuffle();
        currentShuffleIndex = shuffledQueue.length - 1;
      } else {
        currentShuffleIndex -= 1;
      }
      return queue.value
          .indexWhere((item) => item.id == shuffledQueue[currentShuffleIndex]);
    }

    if (currentIndex - 1 >= 0) {
      return currentIndex - 1;
    } else {
      return currentIndex;
    }
  }

  @override
  Future<void> skipToNext() async {
    final index = _getNextSongIndex();
    if (index != currentIndex) {
      if (_player.position != Duration.zero) _player.seek(Duration.zero);
      await customAction("playByIndex", {'index': index});
    } else {
      _player.seek(Duration.zero);
      _player.pause();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.position.inMilliseconds > 5000) {
      _player.seek(Duration.zero);
      return;
    }
    _player.seek(Duration.zero);
    final index = _getPrevSongIndex();
    if (index != currentIndex) {
      await customAction("playByIndex", {'index': index});
    }
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    if (repeatMode == AudioServiceRepeatMode.none) {
      loopModeEnabled = false;
    } else {
      loopModeEnabled = true;
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    if (shuffleMode == AudioServiceShuffleMode.none) {
      shuffleModeEnabled = false;
      shuffledQueue.clear();
    } else {
      _shuffleCmd(currentIndex);
      shuffleModeEnabled = true;
    }
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {

      case 'prefetchSong':
        final songId = extras?['songId'];
        if (songId != null) {
          checkNGetUrl(songId);
        }
        break;

      case 'resetFinishedQueue':
        // "Queue ended" cleanup fired by the UI state listener — NOT a user
        // pause.
        //
        // Desktop: NO-OP, and this is critical. The auto-advance system owns
        // EOF entirely (wrap-around included). This cleanup used to seek(0)+
        // pause() at the exact moment the advance swapped sources — the
        // interleaved seek+load DEADLOCKED media_kit: the whole app froze
        // while mpv (separate process) kept replaying the ended song.
        if (GetPlatform.isDesktop) break;
        // Android: legacy "queue ended" reset (concat queue really finished).
        // Give the EOF auto-advance a grace window to claim the event first,
        // then only touch the player if no advance/load is in flight.
        Future.delayed(const Duration(milliseconds: 50), () async {
          if (isSongLoading || _autoAdvanceConsumed) return;
          try {
            await _player.seek(Duration.zero);
            await _player.pause();
            _syncDiscordPresence(playing: false);
          } catch (_) {}
        });
        break;

      case 'dispose':
        _desktopPositionTimer?.cancel();
        _desktopPositionTimer = null;
        await _player.dispose();
        super.stop();
        break;

      case 'playByIndex':
        _ensureNotificationPermission();
        final songIndex = extras!['index'];
        final playStartedAt = DateTime.now();
        // A FRESH play request (no newUrl flag) resets the consecutive-failure
        // guard so it only trips after two real failures on this attempt.
        // The internal onError retry (newUrl: true) must NOT reset it, or the
        // 2-strike guard would never fire and the loop would be infinite.
        if ((extras?['newUrl'] ?? false) != true) {
          _consecutiveSourceErrors = 0;
          // An explicit user play request overrides a standing pause.
          _userPaused = false;
        }
        dlog('[PLAY] playByIndex index=$songIndex queueLen=${queue.value.length}');
        currentIndex = songIndex;
        final isNewUrlReq = extras['newUrl'] ?? false;
        final useAdaptive = extras['adaptive'] ?? false;
        final currentSong = queue.value[currentIndex];
        dlog('[PLAY] fetching URL for ${currentSong.id}...');
        final futureStreamInfo = checkNGetUrl(currentSong.id,
            generateNewUrl: isNewUrlReq, adaptiveFallback: useAdaptive);
        final bool restoreSession = extras['restoreSession'] ?? false;
        isSongLoading = true;
        try {
          await _player.setVolume(1.0).timeout(const Duration(seconds: 5),
              onTimeout: () => dlog('[PLAY] setVolume TIMED OUT'));
        } catch (e) {
          dlog('[PLAY] setVolume threw: $e');
        }
        playbackState.add(playbackState.value
            .copyWith(processingState: AudioProcessingState.loading));
        if (!_usesSingleSource && _activeList.children.isNotEmpty) {
          await _activeList.clear();
        }

        mediaItem.add(currentSong);
        HMStreamingData streamInfo;
        try {
          streamInfo = await futureStreamInfo;
        } catch (e, st) {
          dlog('[PLAY] fetch THREW after '
              '${DateTime.now().difference(playStartedAt).inMilliseconds}ms: $e');
          print('[PLAY] stack: ${st.toString().split("\n").take(4).join(" | ")}');
          currentSongUrl = null;
          isSongLoading = false;
          Get.find<PlayerController>().notifyPlayError(e.toString());
          playbackState.add(playbackState.value.copyWith(
              processingState: AudioProcessingState.error,
              errorCode: 500,
              errorMessage: e.toString()));
          return;
        }
        dlog('[PLAY] streamInfo (${DateTime.now().difference(playStartedAt).inMilliseconds}ms): '
            'playable=${streamInfo.playable} msg=${streamInfo.statusMSG} url=${streamInfo.audio?.url}');
        if (songIndex != currentIndex) {
          dlog('[PLAY] index changed, aborting');
          return;
        } else if (!streamInfo.playable) {
          dlog('[PLAY] NOT PLAYABLE: ${streamInfo.statusMSG}');
          currentSongUrl = null;
          isSongLoading = false;
          Get.find<PlayerController>().notifyPlayError(streamInfo.statusMSG);
          playbackState.add(playbackState.value.copyWith(
              processingState: AudioProcessingState.error,
              errorCode: 404,
              errorMessage: streamInfo.statusMSG));
          return;
        }
        currentSongUrl = currentSong.extras!['url'] = streamInfo.audio!.url;
        printINFO("playing itag=${streamInfo.audio?.itag} "
            'quality=${streamInfo.qualityIndex}' );
        dlog('[PLAY] URL set: $currentSongUrl');
        playbackState
            .add(playbackState.value.copyWith(queueIndex: currentIndex));
        await _setPlaybackSource(_createAudioSource(currentSong));
        dlog('[PLAY] source set OK state=${_player.processingState}');
        isSongLoading = false;

        if (loudnessNormalizationEnabled && GetPlatform.isAndroid) {
          _normalizeVolume(streamInfo.audio!.loudnessDb);
        }

        if (restoreSession) {
          if (!GetPlatform.isDesktop) {
            final position = extras['position'];
            await _player.load();
            await _player.seek(
              Duration(
                milliseconds: position,
              ),
            );
            await _player.seek(
              Duration(
                milliseconds: position,
              ),
            );
          }
        } else {
          // Ensure position is always zero for a fresh start.
          // Android: seek WITH index 0 — after the concat-list clear+add
          // swap, just_audio can keep the previous player position, making
          // a replayed song resume where it was left. Pinning BOTH the
          // child index and the position guarantees a true 0:00 start.
          dlog('[PLAY] seek zero + play()');
          try {
            await (GetPlatform.isAndroid
                ? _player.seek(Duration.zero, index: 0)
                : _player.seek(Duration.zero));
            await _startPlaybackReliably();
            dlog('[PLAY] play OK state=${_player.processingState} playing=${_player.playing} dur=${_player.duration}');
          } catch (e) {
            dlog('[PLAY] play FAILED: $e');
          }
        }
        break;

      case 'checkWithCacheDb':
        if (isPlayingUsingLockCachingSource) {
          final song = extras!['mediaItem'] as MediaItem;
          final songsCacheBox = Hive.box("SongsCache");
          if (!songsCacheBox.containsKey(song.id) &&
              await File("$_cacheDir/cachedSongs/${song.id}.mp3").exists()) {
            song.extras!['url'] = currentSongUrl;
            song.extras!['date'] = DateTime.now().millisecondsSinceEpoch;
            final dbStreamData = Hive.box("SongsUrlCache").get(song.id);
            final jsonData = MediaItemBuilder.toJson(song);
            jsonData['duration'] = _player.duration!.inSeconds;
            // playbility status and info
            jsonData['streamInfo'] = dbStreamData != null
                ? [
                    true,
                    dbStreamData[
                        Hive.box('AppPrefs').get('streamingQuality') == 0
                            ? 'lowQualityAudio'
                            : "highQualityAudio"]
                  ]
                : null;
            songsCacheBox.put(song.id, jsonData);
            LibrarySongsController librarySongsController =
                Get.find<LibrarySongsController>();
            if (!librarySongsController.isClosed) {
              librarySongsController.librarySongsList.value =
                  librarySongsController.librarySongsList.toList() + [song];
            }
          }
        }
        break;

      case 'setSourceNPlay':
        // Fresh play request from search/related — reset the failure guard.
        _consecutiveSourceErrors = 0;
        _ensureNotificationPermission();
        final currMed = (extras!['mediaItem'] as MediaItem);
        dlog('[SNP] setSourceNPlay for ${currMed.id} state=${_player.processingState}');
        HMStreamingData streamInfo;
        try {
          streamInfo = await checkNGetUrl(currMed.id);
        } catch (e, st) {
          dlog('[SNP] fetch THREW: $e\n${st.toString().split("\n").take(5).join("\n")}');
          currentSongUrl = null;
          isSongLoading = false;
          Get.find<PlayerController>().notifyPlayError(e.toString());
          playbackState.add(playbackState.value.copyWith(
              processingState: AudioProcessingState.error,
              errorCode: 500,
              errorMessage: e.toString()));
          return;
        }
        isSongLoading = true;
        currentIndex = 0;
        try {
          await _player.setVolume(1.0).timeout(const Duration(seconds: 5),
              onTimeout: () => dlog('[SNP] setVolume TIMED OUT'));
          dlog('[SNP] volume=${_player.volume}');
        } catch (e) {
          dlog('[SNP] setVolume threw: $e');
        }
        if (!_usesSingleSource) {
          await _activeList.clear();
        }
        mediaItem.add(currMed);
        // Do NOT replace the whole queue with [currMed]: pushSongToQueue
        // populates the queue asynchronously (related/radio tracks) while
        // setSourceNPlay resolves the stream URL. Overwriting here raced
        // against updateQueue() and on desktop the URL usually resolved LAST,
        // leaving a 1-song queue (no related songs). Merge instead: replace
        // only the slot of this song if it is already queued.
        final existingIdx =
            queue.value.indexWhere((m) => m.id == currMed.id);
        if (existingIdx >= 0) {
          // Seed already queued (updateQueue won the race): keep the related
          // tracks, just refresh this slot AND pin the seed at index 0 so the
          // unconditional `currentIndex = 0` below stays consistent.
          final merged = List<MediaItem>.from(queue.value)
            ..removeAt(existingIdx)
            ..insert(0, currMed);
          queue.add(merged);
        } else {
          queue.add([currMed]);
        }
        dlog('[SNP] resolved playable=${streamInfo.playable} msg=${streamInfo.statusMSG}');
        if (!streamInfo.playable) {
          currentSongUrl = null;
          isSongLoading = false;
          Get.find<PlayerController>().notifyPlayError(streamInfo.statusMSG);
          playbackState.add(playbackState.value
              .copyWith(processingState: AudioProcessingState.error));
          return;
        }
        currentSongUrl = currMed.extras!['url'] = streamInfo.audio!.url;
        dlog('[SNP] URL set: $currentSongUrl');

        await _setPlaybackSource(_createAudioSource(currMed));
        dlog('[SNP] source set OK state=${_player.processingState}');
        isSongLoading = false;

        // Normalize audio
        if (loudnessNormalizationEnabled && GetPlatform.isAndroid) {
          _normalizeVolume(streamInfo.audio!.loudnessDb);
        }

        try {
          await _startPlaybackReliably();
          dlog('[SNP] play() done state=${_player.processingState} playing=${_player.playing} dur=${_player.duration}');
        } catch (e) {
          dlog('[SNP] play() FAILED: $e');
        }
        break;

      case 'toggleSkipSilence':
        final enable = (extras!['enable'] as bool);
        await _player.setSkipSilenceEnabled(enable);
        break;

      case 'toggleLoudnessNormalization':
        loudnessNormalizationEnabled = (extras!['enable'] as bool);
        if (!loudnessNormalizationEnabled) {
          _player.setVolume(1.0);
          return;
        }

        if (loudnessNormalizationEnabled) {
          try {
            final currentSongId = (queue.value[currentIndex]).id;
            if (Hive.box("SongsUrlCache").containsKey(currentSongId)) {
              final songJson = Hive.box("SongsUrlCache").get(currentSongId);
              _normalizeVolume((songJson)["highQualityAudio"]["loudnessDb"]);
              return;
            }

            if (Hive.box("SongDownloads").containsKey(currentSongId)) {
              final streamInfo =
                  (Hive.box("SongDownloads").get(currentSongId))["streamInfo"];

              _normalizeVolume(
                  streamInfo == null ? 0 : streamInfo[1]["loudnessDb"]);
            }
          } catch (e) {
            printERROR(e);
          }
        }
        break;

      case 'shuffleQueue':
        final currentQueue = queue.value;
        final currentItem = currentQueue[currentIndex];
        currentQueue.remove(currentItem);
        currentQueue.shuffle();
        currentQueue.insert(0, currentItem);
        queue.add(currentQueue);
        mediaItem.add(currentItem);
        currentIndex = 0;
        break;

      case 'reorderQueue':
        final oldIndex = extras!['oldIndex'];
        int newIndex = extras['newIndex'];

        if (oldIndex < newIndex) {
          newIndex--;
        }

        final currentQueue = queue.value;
        final currentItem = currentQueue[currentIndex];
        final item = currentQueue.removeAt(
          oldIndex,
        );
        currentQueue.insert(newIndex, item);
        currentIndex = currentQueue.indexOf(currentItem);
        queue.add(currentQueue);
        mediaItem.add(currentItem);
        break;

      case 'openEqualizer':
        EqualizerService.openEqualizer(_player.androidAudioSessionId!);
        break;

      case 'saveSession':
        await saveSessionData();
        break;

      case 'setVolume':
        _player.setVolume(extras!['value'] / 100);
        break;

      case 'shuffleCmd':
        final songIndex = extras!['index'];
        _shuffleCmd(songIndex);
        break;

      case 'upadateMediaItemInAudioService':
        //added to update media item from player controller
        final songIndex = extras!['index'];
        currentIndex = songIndex;
        mediaItem.add(queue.value[currentIndex]);
        break;

      case 'toggleQueueLoopMode':
        queueLoopModeEnabled = extras!['enable'];
        break;

      case 'clearQueue':
        customAction("reorderQueue", {'oldIndex': currentIndex, 'newIndex': 0});
        final newQueue = queue.value;
        newQueue.removeRange(1, newQueue.length);
        queue.add(newQueue);
        if (shuffleModeEnabled) {
          shuffledQueue.clear();
          shuffledQueue.add(newQueue[0].id);
          currentShuffleIndex = 0;
        }
        break;

      case 'stopPlayback':
        _desktopPositionTimer?.cancel();
        _desktopPositionTimer = null;
        // Kill the AUDIO FIRST — everything after this is bookkeeping. If a
        // later step ever hangs, the song must already be dead (the old
        // seek-before-stop raced media_kit and could leave the song playing
        // behind a closed UI).
        try {
          await _player.stop();
        } catch (e) {
          dlog('[STOP] player.stop threw: $e');
        }
        try {
          await _player.setVolume(1.0);
        } catch (_) {}
        if (!_usesSingleSource) {
          try {
            await _activeList.clear();
          } catch (_) {}
        }
        queue.add([]);
        mediaItem.add(null);
        currentSongUrl = null;
        currentIndex = null;
        shuffledQueue.clear();
        currentShuffleIndex = 0;
        isSongLoading = false;
        queueLoopModeEnabled = false;
        if (shuffleModeEnabled) {
          shuffledQueue.clear();
        }
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.idle,
          playing: false,
          queueIndex: null,
        ));
        await super.stop();
        break;
      default:
        break;
    }
  }

  /// Android 13+: makes sure POST_NOTIFICATIONS is granted so the
  /// media-control notification shows while listening. If the permission was
  /// permanently denied, shows a one-time prompt with a button that opens the
  /// app settings (where the user can re-enable notifications).
  Future<void> _ensureNotificationPermission() async {
    if (!GetPlatform.isAndroid) return;
    final granted = await PermissionService.getNotificationPermission();
    printINFO(
        "Notification permission granted: $granted (permanently denied: "
        "${await PermissionService.isNotificationPermanentlyDenied()})");
    if (granted || _notificationPromptShown) return;
    if (await PermissionService.isNotificationPermanentlyDenied()) {
      _notificationPromptShown = true;
      try {
        final ctx = Get.context;
        if (ctx != null && ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content: const Text(
                'Habilita las notificaciones para ver los controles de música'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Abrir ajustes',
              onPressed: () => PermissionService.openNotificationSettings(),
            ),
          ));
        }
      } catch (_) {
        // UI may not be ready (background service) — skip the prompt.
      }
    }
  }

  void _shuffleCmd(int index) {
    final queueIds = queue.value.toList().map((item) => item.id).toList();
    final currentSongId = queueIds.removeAt(index);
    queueIds.shuffle();
    queueIds.insert(0, currentSongId);
    shuffledQueue.replaceRange(0, shuffledQueue.length, queueIds);
    currentShuffleIndex = 0;
  }

  void _normalizeVolume(double currentLoudnessDb) {
    double loudnessDifference = -5 - currentLoudnessDb;

    // Converted loudness difference to a volume multiplier
    // We use a factor to convert dB difference to a linear scale
    // 10^(difference / 20) converts dB difference to a linear volume factor
    final volumeAdjustment = pow(10.0, loudnessDifference / 20.0);
    printINFO(
        "loudness:$currentLoudnessDb Normalized volume: $volumeAdjustment");
    _player.setVolume(volumeAdjustment.toDouble().clamp(0, 1.0));
  }

  Future<void> saveSessionData() async {
    if (Get.find<SettingsScreenController>().restorePlaybackSession.isFalse) {
      return;
    }
    final currQueue = queue.value;
    if (currQueue.isNotEmpty) {
      final queueData =
          currQueue.map((e) => MediaItemBuilder.toJson(e)).toList();
      final currIndex = currentIndex ?? 0;
      final position = _player.position.inMilliseconds;
      final prevSessionData = await Hive.openBox("prevSessionData");
      await prevSessionData.clear();
      await prevSessionData.putAll(
          {"queue": queueData, "position": position, "index": currIndex});
      await prevSessionData.close();
      printINFO("Saved session data");
    }
  }

  /// Android Auto
  @override
  Future<List<MediaItem>> getChildren(String parentMediaId,
      [Map<String, dynamic>? options]) async {
    return _mediaLibrary.getByRootId(parentMediaId);
  }

  @override
  ValueStream<Map<String, dynamic>> subscribeToChildren(String parentMediaId) {
    return Stream.fromFuture(
            _mediaLibrary.getByRootId(parentMediaId).then((items) => items))
        .map((_) => <String, dynamic>{})
        .shareValue();
  }

  // only for Android Auto
  @override
  Future<void> playFromMediaId(String mediaId,
      [Map<String, dynamic>? extras]) async {
    customEvent.add({
      'eventType': 'playFromMediaId',
      'songId': mediaId,
      'libraryId': extras!['libraryId'],
    });
  }

  @override
  Future<void> onTaskRemoved() async {
    final stopForegroundService =
        Get.find<SettingsScreenController>().stopPlyabackOnSwipeAway.value;
    if (stopForegroundService) {
      await Get.find<HomeScreenController>().cachedHomeScreenData();
      await saveSessionData();
      await stop();
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    try {
      DiscordRpcService.instance.clear();
    } catch (_) {}
    return super.stop();
  }

// Work around used [useNewInstanceOfExplode = false] to Fix Connection closed before full header was received issue
  Future<HMStreamingData> checkNGetUrl(String songId,
      {bool generateNewUrl = false,
      bool offlineReplacementUrl = false,
      bool adaptiveFallback = false}) async {
    dlog('[URL] checkNGetUrl $songId genNew=$generateNewUrl offRepl=$offlineReplacementUrl');
    printINFO("Requested id : $songId");
    // Safety net: any box accessed here must exist. If something closed a
    // global box elsewhere, reopen it instead of killing the playback with
    // "Box not found".
    for (final name in kGlobalHiveBoxes) {
      if (!Hive.isBoxOpen(name)) {
        dlog('[URL] box "$name" was closed — reopening');
        await Hive.openBox(name);
      }
    }
    final songDownloadsBox = Hive.box("SongDownloads");
    final songsCacheBox = Hive.box("SongsCache");
    if (!offlineReplacementUrl && songsCacheBox.containsKey(songId)) {
      dlog('[URL] branch: SongsCache hit');
      printINFO("Got Song from cachedbox ($songId)");
      // if contains stream Info
      final streamInfo = songsCacheBox.get(songId)["streamInfo"];
      Audio? cacheAudioPlaceholder;
      if (streamInfo != null && streamInfo.isNotEmpty) {
        streamInfo[1]['url'] = "file://$_cacheDir/cachedSongs/$songId.mp3";
        cacheAudioPlaceholder = Audio.fromJson(streamInfo[1]);
      } else {
        cacheAudioPlaceholder = Audio(
            audioCodec: Codec.mp4a,
            bitrate: 0,
            loudnessDb: 0,
            duration: 0,
            size: 0,
            url: "file://$_cacheDir/cachedSongs/$songId.mp3",
            itag: 0);
      }

      return HMStreamingData(
          playable: true,
          statusMSG: "OK",
          lowQualityAudio: cacheAudioPlaceholder,
          highQualityAudio: cacheAudioPlaceholder);
    } else if (!offlineReplacementUrl && songDownloadsBox.containsKey(songId)) {
      dlog('[URL] branch: SongDownloads hit');
      final song = songDownloadsBox.get(songId);
      final streamInfoJson = song["streamInfo"];
      Audio? audio;
      final path = song['url'];
      if (streamInfoJson != null && streamInfoJson.isNotEmpty) {
        audio = Audio.fromJson(streamInfoJson[1]);
      } else {
        audio = Audio(
            itag: 140,
            audioCodec: Codec.mp4a,
            bitrate: 0,
            duration: 0,
            loudnessDb: 0,
            url: path,
            size: 0);
      }

      final streamInfo = HMStreamingData(
          playable: true,
          statusMSG: "OK",
          highQualityAudio: audio,
          lowQualityAudio: audio);

      if (path.contains(
          "${Get.find<SettingsScreenController>().supportDirPath}/Music")) {
        return streamInfo;
      }
      //check file access and if file exist in storage
      final status = await PermissionService.getExtStoragePermission();
      dlog('[URL] perm=$status');
      if (status && await File(path).exists()) {
        dlog('[URL] local file exists -> return');
        return streamInfo;
      }
      dlog('[URL] local file MISSING -> online fallback');
      //in case file doesnot found in storage, song will be played online
      return checkNGetUrl(songId, offlineReplacementUrl: true);
    } else {
      //check if song stream url is cached and allocate url accordingly
      final songsUrlCacheBox = Hive.box("SongsUrlCache");
      final qualityIndex = Hive.box('AppPrefs').get('streamingQuality') ?? 1;
      HMStreamingData? streamInfo;
      if (songsUrlCacheBox.containsKey(songId) && !generateNewUrl) {
        dlog('[URL] url-cache entry exists for $songId');
        final streamInfoJson = songsUrlCacheBox.get(songId);
        final lowCached = streamInfoJson['lowQualityAudio']?['url'];
        final highCached = streamInfoJson['highQualityAudio']?['url'];
        final cachedExpired =
            (lowCached is String && isExpired(url: lowCached)) ||
                (highCached is String && isExpired(url: highCached));
        final pointsToDeadProxy =
            (highCached ?? '').toString().contains('127.0.0.1') ||
                (lowCached ?? '').toString().contains('127.0.0.1');
        final cachedItag =
            (streamInfoJson['highQualityAudio']?['itag'] ?? 0) as int;
        if (streamInfoJson.runtimeType.toString().contains("Map") &&
            streamInfoJson['playable'] != false &&
            !cachedExpired &&
            !pointsToDeadProxy &&
            cachedItag == 18) {
          // Only itag 18 is reusable for direct ExoPlayer playback: googlevideo
          // rejects its open-ended Range requests for adaptive formats with
          // 403. Older cache entries with 140/251 are re-resolved.
          printINFO("Got cached Url ($songId)");
          dlog('[URL] using cached url (itag $cachedItag)');
          streamInfo = HMStreamingData.fromJson(streamInfoJson);
        } else if (streamInfoJson.runtimeType.toString().contains("Map") &&
            cachedItag != 18) {
          dlog('[URL] cached itag=$cachedItag is not directly playable; '
              're-resolving');
        }
      }

      if (streamInfo == null) {
        // "Modo Rápido": resolve the stream with short client timeouts
        // so skipping songs never hangs on slow connections.
        final fast = Get.find<SettingsScreenController>().fastMode.isTrue;
        final platform = GetPlatform.isDesktop ? 'desktop' : null;
        var fetchId = songId;
        if (fetchId.length > 4 && fetchId.substring(0, 4) == 'MPED') {
          fetchId = fetchId.substring(4);
        }
        dlog('[FETCH] resolving stream (fast=$fast platform=$platform '
            'adaptiveOnly=$adaptiveFallback)');
        final playerResponse = await StreamProvider.fetch(fetchId,
            fast: fast,
            platform: platform,
            adaptiveOnly: adaptiveFallback);
        dlog(
            '[FETCH] done playable=${playerResponse.playable} msg=${playerResponse.statusMSG} formats=${playerResponse.audioFormats?.length}');
        final streamInfoJson = playerResponse.hmStreamingData;
        streamInfo = HMStreamingData.fromJson(streamInfoJson);
        dlog('[URL] fresh resolve done playable=${streamInfo.playable}');
        if (streamInfo.playable) songsUrlCacheBox.put(songId, streamInfoJson);
      }

      streamInfo.setQualityIndex(qualityIndex as int);
      return streamInfo;
    }
  }
}

class UrlError extends Error {
  String message() => 'Unable to fetch url';
}


// for Android Auto
class MediaLibrary {
  static const albumsRootId = 'albums';
  static const songsRootId = 'songs';
  static const favoritesRootId = "LIBFAV";
  static const playlistsRootId = 'playlists';

  Future<List<MediaItem>> getByRootId(String id) async {
    switch (id) {
      case AudioService.browsableRootId:
        return Future.value(getRoot());
      case songsRootId:
        return getLibSongs("SongDownloads");
      case favoritesRootId:
        return getLibSongs("LIBFAV");
      case albumsRootId:
        return getAlbums();
      case playlistsRootId:
        return getPlaylists();
      case AudioService.recentRootId:
        return getLibSongs("LIBRP");
      default:
        return getLibSongs(id);
    }
  }

  List<MediaItem> getRoot() {
    return [
      MediaItem(
        id: songsRootId,
        title: "songs".tr,
        playable: false,
      ),
      MediaItem(
        id: favoritesRootId,
        title: "favorites".tr,
        playable: false,
      ),
      MediaItem(
        id: albumsRootId,
        title: "albums".tr,
        playable: false,
      ),
      MediaItem(
        id: playlistsRootId,
        title: "playlists".tr,
        playable: false,
      ),
    ];
  }

  Future<List<MediaItem>> getAlbums() async {
    final box = await Hive.openBox("LibraryAlbums");
    final albums =
        box.values.map((item) => Album.fromJson(item).toMediaItem()).toList();
    await box.close();
    return albums;
  }

  Future<List<MediaItem>> getPlaylists() async {
    final box = await Hive.openBox("LibraryPlaylists");
    final playlists = [
      ...LibraryPlaylistsController.initPlst.map((e) => e.toMediaItem()),
      ...(box.values
          .map((item) => Playlist.fromJson(item).toMediaItem())
          .toList())
    ];
    await box.close();
    return playlists;
  }

  Future<List<MediaItem>> getLibSongs(String libId) async {
    Box<dynamic> box;
    try {
      box = await Hive.openBox(libId);
    } catch (e) {
      printERROR("Failed to open box $libId: $e");
      return [];
    }
    final songs = box.values.toList().map((e) {
      final song = MediaItemBuilder.fromJson(e);
      return MediaItem(
        id: song.id,
        title: song.title,
        artist: song.artist,
        artUri: song.artUri,
        extras: {"libraryId": libId},
        playable: true,
      );
    }).toList();

    // Never close the app-wide boxes — closing them breaks all playback.
    if (!kGlobalHiveBoxes.contains(libId)) {
      await box.close();
    }

    if (libId == "LIBRP") {
      return songs.reversed.toList();
    }

    return songs;
  }
}
