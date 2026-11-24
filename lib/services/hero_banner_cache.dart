/// Build 7 (v1.5.9, FIX C) — on-device cache for the Home hero
/// banners.
///
/// The hero carousel's two slides can be pointed at remote
/// images from the remote config (tj-pro.json `hero_banner_1_url`
/// / `hero_banner_2_url`) so the banners change WITHOUT a new
/// app build. This cache is what makes that safe on a phone:
///
/// * [warm] is called at launch and on every config change. It
///   loads the previously downloaded copy from disk first (so
///   the slide shows the CACHED copy instantly) and downloads
///   the fresh copy in the background when the URL changed;
///   when the fresh copy lands, [revision] bumps and the slide
///   swaps to it.
/// * Downloads are validated by magic bytes (JPEG/PNG/GIF/WebP)
///   before they may replace the cache — a broken or wrong remote
///   file NEVER replaces a working banner, and the widgets fall
///   back to the bundled assets on any failure, so a slide can
///   never render blank or broken.
/// * Everything is fail-soft: failures are recorded via
///   CrashGuard (tag `home.banner`) and otherwise silent.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'crash_guard.dart';

class HeroBannerCache {
  HeroBannerCache._();

  static final HeroBannerCache instance = HeroBannerCache._();

  /// Cache slots (one per hero slide).
  static const String slot1 = 'hero_banner_1';
  static const String slot2 = 'hero_banner_2';

  /// Build 8 (v1.6.0): the SplashGate poster's cache slot — the
  /// gate reuses this exact proven pattern (cached copy first,
  /// magic-byte validation, bundled-asset fallback) so the
  /// poster can change via remote config without a build.
  static const String slotSplash = 'splash_poster';

  static const Duration downloadTimeout = Duration(seconds: 10);

  /// Test seam: directory override (tests point this at a temp
  /// dir instead of mocking path_provider).
  static Directory? overrideDirForTest;

  /// Test seam: downloader override — returns the bytes for a
  /// URL, or null on failure. Production uses a real HTTP GET.
  static Future<List<int>?> Function(String url)? downloaderForTest;

  /// Bumped whenever a slot's cached file is loaded or replaced,
  /// so the hero slides can swap to the fresh copy.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final Map<String, File?> _files = <String, File?>{};
  final Map<String, String> _urls = <String, String>{};
  final Set<String> _inFlight = <String>{};
  bool _diskLoaded = false;

  /// The cached file for [slot] when it was downloaded for
  /// exactly [url]; null when nothing usable is cached for this
  /// URL yet (the widget then streams the URL directly, with
  /// the bundled asset as its fallback).
  File? cachedFileFor(String slot, String url) {
    if (_urls[slot] != url) return null;
    return _files[slot];
  }

  /// Loads the on-disk cache (once) and downloads [url] when the
  /// cache does not already hold it. Never throws.
  Future<void> warm(String slot, String url) async {
    final String target = url.trim();
    if (target.isEmpty || target.startsWith('assets/')) return;
    await _loadFromDisk();
    if (cachedFileFor(slot, target) != null) {
      // The cached copy is already the one for this URL — make
      // sure listeners know it is available.
      revision.value = revision.value + 1;
      return;
    }
    await refresh(slot, target);
  }

  /// Downloads [url] for [slot] in the background (one download
  /// per slot at a time). A validated download replaces the
  /// cache and bumps [revision]; anything else keeps the old
  /// cache untouched. Never throws.
  Future<void> refresh(String slot, String url) async {
    if (_inFlight.contains(slot)) return;
    _inFlight.add(slot);
    try {
      final List<int>? bytes = await _download(url);
      if (bytes == null) return;
      await storeBytes(slot, url, bytes);
    } catch (e, s) {
      CrashGuard.captureHandled(e, s, source: 'home.banner');
    } finally {
      _inFlight.remove(slot);
    }
  }

  /// Validates and stores [bytes] as [slot]'s cached image for
  /// [url], then bumps [revision]. Returns false — keeping the
  /// old cache — when the bytes are not a real image or storage
  /// fails.
  Future<bool> storeBytes(String slot, String url, List<int> bytes) async {
    if (!looksLikeImage(bytes)) return false;
    try {
      final Directory dir = await _dir();
      final File file = File(p.join(dir.path, '$slot.img'));
      await file.writeAsBytes(bytes, flush: true);
      await File(p.join(dir.path, '$slot.url'))
          .writeAsString(url, flush: true);
      _files[slot] = file;
      _urls[slot] = url;
      revision.value = revision.value + 1;
      return true;
    } catch (e, s) {
      CrashGuard.captureHandled(e, s, source: 'home.banner');
      return false;
    }
  }

  Future<void> _loadFromDisk() async {
    if (_diskLoaded) return;
    _diskLoaded = true;
    for (final String slot in const <String>[slot1, slot2, slotSplash]) {
      try {
        final Directory dir = await _dir();
        final File urlFile = File(p.join(dir.path, '$slot.url'));
        final File imgFile = File(p.join(dir.path, '$slot.img'));
        if (await urlFile.exists() && await imgFile.exists()) {
          _urls[slot] = (await urlFile.readAsString()).trim();
          _files[slot] = imgFile;
        } else {
          _urls[slot] = '';
          _files[slot] = null;
        }
      } catch (_) {
        _urls[slot] = '';
        _files[slot] = null;
      }
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
    final Directory dir = Directory(p.join(docs.path, 'hero_banners'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<int>?> _download(String url) async {
    final Future<List<int>?> Function(String url)? override =
        downloaderForTest;
    if (override != null) return override(url);
    try {
      final http.Response response =
          await http.get(Uri.parse(url)).timeout(downloadTimeout);
      if (response.statusCode != HttpStatus.ok) return null;
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// Magic-byte sniff for the formats a banner can be:
  /// JPEG / PNG / GIF / WebP.
  static bool looksLikeImage(List<int> bytes) {
    if (bytes.length < 12) return false;
    // JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;
    // PNG
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }
    // GIF
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return true;
    }
    // WebP (RIFF....WEBP)
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    return false;
  }

  /// Test seam: forgets the in-memory state (disk untouched).
  static void resetForTest() {
    instance._files.clear();
    instance._urls.clear();
    instance._inFlight.clear();
    instance._diskLoaded = false;
  }
}
