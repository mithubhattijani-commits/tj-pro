/// Build 10 (v1.8.0) — Online Store audio previews (user
/// order 2026-11-25: "khareedne se pehle play karke check ho
/// sake").
///
/// Two pieces:
///
/// * [StoreAudioPreviewCache] — the [StorePreviewCache]
///   pattern for audio: disk-first, background download from
///   the item's Drive file, magic-byte sniff before anything
///   is cached (a Drive error page must never be cached as
///   "audio"). Preview downloads are a TRY-BEFORE-YOU-BUY
///   copy of the file in the app's private cache — buying
///   still goes through the normal purchase path.
///
/// * [StoreAudioPreviewPlayer] — the ONE player for the whole
///   store. Exactly one item can sound at a time: starting a
///   second item stops the first, and the store screen stops
///   the player when it is left. Playback uses `video_player`
///   — the dependency the app already carries (the voice
///   preview player's pattern) — never a new audio package.
///
/// Every risky step (file resolution, controller init, play)
/// runs through SafeOps (point #7C): one corrupt audio file
/// fails on its own card with a message; the store keeps
/// working.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'crash_guard.dart';
import 'safe_ops.dart';
import 'store_service.dart';

/// Disk-first cache for store audio preview files.
class StoreAudioPreviewCache {
  StoreAudioPreviewCache._();

  static final StoreAudioPreviewCache instance = StoreAudioPreviewCache._();

  static const Duration downloadTimeout = Duration(seconds: 20);

  /// Test seam: directory override.
  static Directory? overrideDirForTest;

  /// Test seam: downloader override — bytes for an item id,
  /// or null on failure.
  static Future<List<int>?> Function(String itemId)? downloaderForTest;

  final Map<String, File?> _files = <String, File?>{};
  final Set<String> _inFlight = <String>{};
  final Set<String> _diskChecked = <String>{};

  /// The cached preview file for [itemId] when one is already
  /// on disk / downloaded; null otherwise.
  File? cachedFileFor(String itemId) => _files[itemId];

  /// Returns the preview file for [item], downloading it
  /// first when needed. Null when the download or its
  /// validation failed — the caller shows the item's error
  /// state; nothing throws.
  Future<File?> fileFor(StoreItem item) async {
    await _loadFromDisk(item.id);
    final cached = _files[item.id];
    if (cached != null) return cached;
    if (_inFlight.contains(item.id)) return null;
    _inFlight.add(item.id);
    try {
      final bytes = await _download(item.id);
      if (bytes == null) return null;
      final ok = await storeBytes(item, bytes);
      return ok ? _files[item.id] : null;
    } catch (e, s) {
      CrashGuard.captureHandled(e, s, source: 'store.audio_preview');
      return null;
    } finally {
      _inFlight.remove(item.id);
    }
  }

  /// Validates [bytes] as real audio for [item]'s extension
  /// and stores them. Returns false — caching nothing — when
  /// the bytes do not sniff as that audio format.
  Future<bool> storeBytes(StoreItem item, List<int> bytes) async {
    if (!looksLikeAudio(bytes, item.extension)) return false;
    try {
      final dir = await _dir();
      final file = File(p.join(dir.path, '${item.id}.audio'));
      await file.writeAsBytes(bytes, flush: true);
      _files[item.id] = file;
      _diskChecked.add(item.id);
      return true;
    } catch (e, s) {
      CrashGuard.captureHandled(e, s, source: 'store.audio_preview');
      return false;
    }
  }

  /// Magic-byte sniff per format: MP3 (ID3 tag or frame
  /// sync), WAV (RIFF/WAVE), M4A (ftyp box), OGG (OggS).
  static bool looksLikeAudio(List<int> bytes, String extension) {
    if (bytes.length < 12) return false;
    bool riff() =>
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46;
    switch (extension.toLowerCase()) {
      case '.mp3':
        // "ID3" tag, or an MPEG frame sync (0xFF 0xEx).
        if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) {
          return true;
        }
        return bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0;
      case '.wav':
        return riff() &&
            bytes[8] == 0x57 &&
            bytes[9] == 0x41 &&
            bytes[10] == 0x56 &&
            bytes[11] == 0x45;
      case '.m4a':
        // ISO BMFF: bytes 4..8 are the box type "ftyp".
        return bytes[4] == 0x66 &&
            bytes[5] == 0x74 &&
            bytes[6] == 0x79 &&
            bytes[7] == 0x70;
      case '.ogg':
        return bytes[0] == 0x4F &&
            bytes[1] == 0x67 &&
            bytes[2] == 0x67 &&
            bytes[3] == 0x53;
      default:
        return false;
    }
  }

  /// 7E: forgets the in-memory file map (disk copies stay and
  /// re-warm on demand). Called on memory pressure.
  void evictMemory() {
    _files.clear();
    _diskChecked.clear();
  }

  Future<void> _loadFromDisk(String itemId) async {
    if (_diskChecked.contains(itemId)) return;
    _diskChecked.add(itemId);
    try {
      final dir = await _dir();
      final file = File(p.join(dir.path, '$itemId.audio'));
      if (await file.exists() && await file.length() > 0) {
        _files[itemId] = file;
      }
    } catch (_) {
      // Cache is best-effort.
    }
  }

  Future<Directory> _dir() async {
    final override = overrideDirForTest;
    if (override != null) {
      if (!await override.exists()) await override.create(recursive: true);
      return override;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'store_audio_previews'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<int>?> _download(String itemId) async {
    final override = downloaderForTest;
    if (override != null) return override(itemId);
    try {
      final response = await http
          .get(Uri.parse(StoreConfig.downloadUrl(itemId)))
          .timeout(downloadTimeout);
      if (response.statusCode != HttpStatus.ok) return null;
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// Test seam: forgets the in-memory state (disk untouched).
  static void resetForTest() {
    instance._files.clear();
    instance._inFlight.clear();
    instance._diskChecked.clear();
  }
}

/// The playback backend seam: production wraps a
/// [VideoPlayerController]; tests substitute a fake so the
/// one-at-a-time state machine is testable without platform
/// channels.
abstract class StoreAudioBackend {
  Future<void> load(File file);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  bool get isPlaying;
  bool get isCompleted;

  /// Fires each time playback reaches the end of the file.
  Stream<void> get completions;

  Future<void> dispose();
}

/// `video_player`-backed [StoreAudioBackend] — the existing
/// dependency, the voice preview player's proven pattern.
class VideoPlayerAudioBackend implements StoreAudioBackend {
  VideoPlayerController? _controller;
  final StreamController<void> _completions =
      StreamController<void>.broadcast();
  bool _endNotified = false;

  @override
  Future<void> load(File file) async {
    final controller = VideoPlayerController.file(file);
    _controller = controller;
    await controller.initialize();
    controller.addListener(_onUpdate);
  }

  void _onUpdate() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    final atEnd = v.duration > Duration.zero &&
        v.position >= v.duration &&
        !v.isPlaying;
    if (atEnd && !_endNotified) {
      _endNotified = true;
      _completions.add(null);
    } else if (!atEnd) {
      _endNotified = false;
    }
  }

  @override
  Future<void> play() async {
    final c = _controller;
    if (c == null) return;
    if (isCompleted) await c.seekTo(Duration.zero);
    await c.play();
  }

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> stop() async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.pause();
    } catch (_) {
      // Release matters more than the pause succeeding.
    }
  }

  @override
  bool get isPlaying => _controller?.value.isPlaying ?? false;

  @override
  bool get isCompleted {
    final v = _controller?.value;
    if (v == null || v.duration <= Duration.zero) return false;
    return v.position >= v.duration && !v.isPlaying;
  }

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Future<void> dispose() async {
    final c = _controller;
    _controller = null;
    if (c != null) {
      c.removeListener(_onUpdate);
      await c.dispose();
    }
    await _completions.close();
  }
}

/// Playback phases for one store card's play button.
enum StoreAudioPhase { idle, loading, playing, paused, error }

/// The player's observable state: which item, which phase,
/// and (on error) the message to show once.
class StoreAudioPreviewState {
  const StoreAudioPreviewState({
    this.itemId,
    this.phase = StoreAudioPhase.idle,
    this.message,
  });

  final String? itemId;
  final StoreAudioPhase phase;
  final String? message;
}

/// The store's single audio preview player: one item sounds
/// at a time, starting another stops the first, [stop] runs
/// when the store screen goes away.
class StoreAudioPreviewPlayer {
  StoreAudioPreviewPlayer._();

  static final StoreAudioPreviewPlayer instance = StoreAudioPreviewPlayer._();

  /// Test seam: backend factory (production: video_player).
  static StoreAudioBackend Function()? backendFactoryForTest;

  /// Test seam: file resolver override — production resolves
  /// owned-file-first, then the preview cache.
  static Future<File?> Function(StoreItem item)? fileResolverForTest;

  final ValueNotifier<StoreAudioPreviewState> state =
      ValueNotifier<StoreAudioPreviewState>(
    const StoreAudioPreviewState(),
  );

  StoreAudioBackend? _backend;
  StreamSubscription<void>? _completionSub;

  String? get currentItemId => state.value.itemId;

  bool isPlayingItem(String itemId) =>
      state.value.itemId == itemId &&
      state.value.phase == StoreAudioPhase.playing;

  /// Play/pause toggle for [item]'s card.
  Future<void> toggle(StoreItem item) async {
    final current = state.value;
    // Same item: pause / resume on the live backend.
    if (current.itemId == item.id && _backend != null) {
      if (current.phase == StoreAudioPhase.playing) {
        await SafeOps.guard('store.audio.pause', () => _backend!.pause());
        if (state.value.itemId == item.id) {
          state.value = StoreAudioPreviewState(
            itemId: item.id,
            phase: StoreAudioPhase.paused,
          );
        }
        return;
      }
      if (current.phase == StoreAudioPhase.paused) {
        final res = await SafeOps.run<bool>(
          'store.audio.resume',
          () async {
            await _backend!.play();
            return true;
          },
        );
        state.value = res.ok
            ? StoreAudioPreviewState(
                itemId: item.id,
                phase: StoreAudioPhase.playing,
              )
            : StoreAudioPreviewState(
                itemId: item.id,
                phase: StoreAudioPhase.error,
                message: 'Audio did not play — try again.',
              );
        return;
      }
      if (current.phase == StoreAudioPhase.loading) return;
      // error / idle with a live backend: fall through to a
      // fresh start below.
    }

    // Fresh start (also the "second item stops the first"
    // path): release whatever was sounding first.
    await _releaseBackend();
    state.value = StoreAudioPreviewState(
      itemId: item.id,
      phase: StoreAudioPhase.loading,
    );

    final fileResult = await SafeOps.run<File?>(
      'store.audio.resolve',
      () => _resolveFile(item),
    );
    final file = fileResult.value;
    if (file == null) {
      if (state.value.itemId == item.id) {
        state.value = StoreAudioPreviewState(
          itemId: item.id,
          phase: StoreAudioPhase.error,
          message: 'Preview did not download — check the net and try again.',
        );
      }
      return;
    }

    final backend = (backendFactoryForTest ?? VideoPlayerAudioBackend.new)();
    final loadResult = await SafeOps.run<bool>(
      'store.audio.load',
      () async {
        await backend.load(file);
        await backend.play();
        return true;
      },
    );
    if (!loadResult.ok) {
      await SafeOps.guard('store.audio.dispose', backend.dispose);
      if (state.value.itemId == item.id) {
        state.value = StoreAudioPreviewState(
          itemId: item.id,
          phase: StoreAudioPhase.error,
          message: 'This audio file could not be played.',
        );
      }
      return;
    }
    // A newer toggle may have superseded this one while the
    // file loaded — only adopt the backend if we are still
    // the current request.
    if (state.value.itemId != item.id ||
        state.value.phase != StoreAudioPhase.loading) {
      await SafeOps.guard('store.audio.dispose', backend.dispose);
      return;
    }
    _backend = backend;
    _completionSub = backend.completions.listen((_) {
      if (state.value.itemId == item.id &&
          state.value.phase == StoreAudioPhase.playing) {
        state.value = StoreAudioPreviewState(
          itemId: item.id,
          phase: StoreAudioPhase.paused,
        );
      }
    });
    state.value = StoreAudioPreviewState(
      itemId: item.id,
      phase: StoreAudioPhase.playing,
    );
  }

  /// Stops playback and releases the player (store screen
  /// dispose / category change). Never throws.
  Future<void> stop() async {
    await _releaseBackend();
    state.value = const StoreAudioPreviewState();
  }

  Future<void> _releaseBackend() async {
    final backend = _backend;
    _backend = null;
    // The completion subscription is discarded, not awaited:
    // its listener re-checks the live state before acting, so
    // nothing depends on the cancel landing first — and a
    // track switch never waits on stream plumbing.
    final sub = _completionSub;
    _completionSub = null;
    if (sub != null) unawaited(sub.cancel());
    if (backend != null) {
      await SafeOps.guard('store.audio.stop', () async {
        await backend.stop();
        await backend.dispose();
      });
    }
  }

  /// Owned items play their purchased local file; everything
  /// else plays the preview cache's copy.
  Future<File?> _resolveFile(StoreItem item) async {
    final override = fileResolverForTest;
    if (override != null) return override(item);
    final owned = await StoreService.instance.ownedRecord(item.id);
    if (owned != null) {
      final file = File(owned.localPath);
      if (await file.exists()) return file;
    }
    return StoreAudioPreviewCache.instance.fileFor(item);
  }

  /// Test seam: full reset between tests.
  static Future<void> resetForTest() async {
    await instance._releaseBackend();
    instance.state.value = const StoreAudioPreviewState();
    backendFactoryForTest = null;
    fileResolverForTest = null;
  }
}

/// True when [item] is an audio file the store can preview
/// (sound effects + background music live in Music, but the
/// extension is the honest test — audio can sit in any
/// category the Drive folders allow it in).
bool storeItemIsAudio(StoreItem item) {
  switch (item.extension) {
    case '.mp3':
    case '.m4a':
    case '.wav':
    case '.ogg':
      return true;
    default:
      return false;
  }
}
