/// Build 8 (v1.6.0, fix-list point #3) — on-device cache for
/// Online Store item previews.
///
/// Every store item can carry a preview image next to it in its
/// Drive folder (`<item base name>.preview.jpg` — see
/// [StoreService.buildCategoryListing]). This cache gives the
/// store cards the hero banners' proven behaviour:
///
/// * The previously downloaded copy paints instantly from disk;
///   a fresh copy downloads in the background and swaps in when
///   it lands ([revision] bumps).
/// * Downloads are validated by magic bytes before they may
///   replace the cache — a broken remote file never replaces a
///   working preview, and on ANY failure the card falls back to
///   its category icon, exactly as before Build 8.
/// * Nothing here throws to the UI; failures are recorded via
///   CrashGuard (tag `store.preview`) and otherwise silent.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'crash_guard.dart';
import 'hero_banner_cache.dart';
import 'store_service.dart';

class StorePreviewCache {
  StorePreviewCache._();

  static final StorePreviewCache instance = StorePreviewCache._();

  static const Duration downloadTimeout = Duration(seconds: 10);

  /// Test seam: directory override (tests point this at a temp
  /// dir instead of mocking path_provider).
  static Directory? overrideDirForTest;

  /// Test seam: downloader override — returns the bytes for a
  /// preview file id, or null on failure. Production downloads
  /// the file from Drive via [StoreConfig.downloadUrl].
  static Future<List<int>?> Function(String previewId)? downloaderForTest;

  /// Bumped whenever a preview file is loaded or replaced, so
  /// visible cards can swap to the fresh copy.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final Map<String, File?> _files = <String, File?>{};
  final Set<String> _inFlight = <String>{};
  final Set<String> _diskChecked = <String>{};

  /// The cached preview file for [previewId] when one has been
  /// loaded from disk or downloaded; null otherwise (the card
  /// then shows its category icon while [warm] works).
  File? cachedFileFor(String previewId) => _files[previewId];

  /// Loads the on-disk copy for [previewId] (once) and downloads
  /// it when nothing usable is cached. Never throws.
  Future<void> warm(String previewId) async {
    if (previewId.isEmpty) return;
    await _loadFromDisk(previewId);
    if (_files[previewId] != null) {
      revision.value = revision.value + 1;
      return;
    }
    await refresh(previewId);
  }

  /// Downloads [previewId] in the background (one download per
  /// preview at a time). A validated download replaces the cache
  /// and bumps [revision]; anything else keeps the old state.
  /// Never throws.
  Future<void> refresh(String previewId) async {
    if (_inFlight.contains(previewId)) return;
    _inFlight.add(previewId);
    try {
      final List<int>? bytes = await _download(previewId);
      if (bytes == null) return;
      await storeBytes(previewId, bytes);
    } catch (e, s) {
      CrashGuard.captureHandled(e, s, source: 'store.preview');
    } finally {
      _inFlight.remove(previewId);
    }
  }

  /// Validates and stores [bytes] as [previewId]'s cached
  /// preview, then bumps [revision]. Returns false — keeping the
  /// old cache — when the bytes are not a real image or storage
  /// fails.
  Future<bool> storeBytes(String previewId, List<int> bytes) async {
    if (!HeroBannerCache.looksLikeImage(bytes)) return false;
    try {
      final Directory dir = await _dir();
      final File file = File(p.join(dir.path, '$previewId.img'));
      await file.writeAsBytes(bytes, flush: true);
      _files[previewId] = file;
      _diskChecked.add(previewId);
      revision.value = revision.value + 1;
      return true;
    } catch (e, s) {
      CrashGuard.captureHandled(e, s, source: 'store.preview');
      return false;
    }
  }

  Future<void> _loadFromDisk(String previewId) async {
    if (_diskChecked.contains(previewId)) return;
    _diskChecked.add(previewId);
    try {
      final Directory dir = await _dir();
      final File imgFile = File(p.join(dir.path, '$previewId.img'));
      if (await imgFile.exists() && await imgFile.length() > 0) {
        _files[previewId] = imgFile;
      }
    } catch (_) {
      // Cache is best-effort.
    }
  }

  Future<Directory> _dir() async {
    final Directory? override = overrideDirForTest;
    if (override != null) {
      if (!await override.exists()) {
        await override.create(recursive: true);
      }
      return override;
    }
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory(p.join(docs.path, 'store_previews'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<int>?> _download(String previewId) async {
    final Future<List<int>?> Function(String previewId)? override =
        downloaderForTest;
    if (override != null) return override(previewId);
    try {
      final http.Response response = await http
          .get(Uri.parse(StoreConfig.downloadUrl(previewId)))
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
