/// On-demand asset downloads for News Studio (v1).
///
/// APP SIZE (user order 20 Nov 2026): heavy assets are NOT bundled in
/// the APK — they are downloaded on first use and cached in the app
/// documents directory:
///
///   - Kasheeda font (12.6 MB TTF) — Urdu (Nastaleeq) rendering for
///     ribbons/tickers. Loaded via FontLoader from the cached file
///     ([loadKasheedaFont]); the template renderer must call it before
///     drawing Urdu (Phase 3), because the font is no longer a pubspec
///     asset. FFmpeg drawtext cannot shape Urdu, so the renderer draws
///     PNG overlays with this font.
///   - Nigraan intro (10s, 854x480 LANDSCAPE, 10.005s) — downloaded on
///     first use ([getIntroVideo]); portrait export needs scale/crop
///     (scale to 720 wide + centre-crop to 720x1280).
///
/// URLs come from [AppConfig.kasheedaFontUrl] / [AppConfig.nigraanIntroUrl]
/// (remote-config overridable). They are EMPTY until the files are hosted
/// at release time — never a hardcoded fake URL; an empty URL throws a
/// clear error instead of downloading garbage.
///
/// Only SMALL things are bundled (the two chroma backgrounds, ~318 KB
/// total). R8/shrinking: the CI build is DEBUG, where R8 does not run —
/// nothing is done about shrinking here; the release switch is a
/// separate decision.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Thrown when an on-demand asset cannot be obtained.
class AssetDownloadException implements Exception {
  AssetDownloadException(this.message);
  final String message;
  @override
  String toString() => 'AssetDownloadException: $message';
}

class AssetDownloadService {
  /// [cacheDirOverride] is for tests only: when set, downloads cache
  /// there instead of the app documents directory (no path_provider
  /// channel needed in widget tests).
  ///
  /// [httpClient] is for tests only: when set, downloads use it instead
  /// of a fresh `http.Client()`. The flutter_test binding replaces the
  /// dart:io HttpClient with a mock that answers 400 to every request,
  /// so a real download can never be tested in a widget test — inject a
  /// `MockClient` (package:http/testing.dart) instead.
  const AssetDownloadService({this.cacheDirOverride, this.httpClient});

  final Directory? cacheDirOverride;
  final http.Client? httpClient;

  static const _cacheDirName = 'downloaded_assets';

  /// File name the Kasheeda font is cached under.
  static const kasheedaFileName = 'JameelNooriNastaleeqKasheeda.ttf';

  /// File name the Nigraan intro is cached under.
  static const introFileName = 'nigraan_intro_10s.mp4';

  /// File name the pre-rendered rotating-logo loop is cached under
  /// (Phase 7 — `logo-rotating-alpha.mov`, ProRes 4444 with alpha).
  static const logoMovFileName = 'logo-rotating-alpha.mov';

  /// Font family the Kasheeda font is registered under (same name the
  /// old pubspec font registration used, so renderer code does not change).
  static const kasheedaFamily = 'JameelNooriNastaleeqKasheeda';

  Future<Directory> _cacheDir() async {
    if (cacheDirOverride != null) {
      final dir = cacheDirOverride!;
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _cacheDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Returns the cached file for [fileName], or null when not cached yet.
  Future<File?> cachedFile(String fileName) async {
    final file = File(p.join((await _cacheDir()).path, fileName));
    return await file.exists() ? file : null;
  }

  /// Downloads [url] to the cache as [fileName] and returns the file.
  ///
  /// Cache-first: when the file is already cached it is returned
  /// immediately with 0 network use ([onProgress] is not called).
  /// [onProgress] reports 0..1 while downloading (only when the server
  /// sends a Content-Length; otherwise progress stays unknown and the
  /// callback is not called). Throws [AssetDownloadException] on an
  /// empty URL, a non-200 status, or a network failure.
  Future<File> download({
    required String url,
    required String fileName,
    void Function(double progress)? onProgress,
  }) async {
    if (url.trim().isEmpty) {
      throw AssetDownloadException(
        'No download URL configured for $fileName — the file is not '
        'hosted yet (set AppConfig / remote config first).',
      );
    }
    final dir = await _cacheDir();
    final file = File(p.join(dir.path, fileName));
    if (await file.exists()) return file;

    final client = httpClient ?? http.Client();
    final ownsClient = httpClient == null;
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 120));
      if (response.statusCode != 200) {
        throw AssetDownloadException(
          'Download failed for $fileName: HTTP ${response.statusCode}',
        );
      }
      final total = response.contentLength ?? -1;
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          received += chunk.length;
          sink.add(chunk);
          if (onProgress != null && total > 0) {
            onProgress((received / total).clamp(0.0, 1.0));
          }
        }
      } finally {
        await sink.close();
      }
      if (total > 0 && received != total) {
        await file.delete().catchError((_) => file);
        throw AssetDownloadException(
          'Download incomplete for $fileName: got $received of $total bytes.',
        );
      }
      return file;
    } on AssetDownloadException {
      rethrow;
    } catch (e) {
      await file.delete().catchError((_) => file);
      throw AssetDownloadException('Download failed for $fileName: $e');
    } finally {
      if (ownsClient) client.close();
    }
  }

  /// Downloads (or reuses the cached) Kasheeda font from [url] and
  /// registers it with [FontLoader] under [kasheedaFamily], so Urdu
  /// text renders in Jameel Noori Nastaleeq Kasheeda. Safe to call more
  /// than once — a process-level guard skips the re-register (a second
  /// load of the same family would otherwise throw).
  Future<void> loadKasheedaFont({required String url}) async {
    final file = await download(url: url, fileName: kasheedaFileName);
    await loadKasheedaFontFromFile(file);
  }

  /// True once the Kasheeda family has been registered in this process.
  static bool _kasheedaLoaded = false;

  /// Registers the Kasheeda font from a local [file] (downloaded cache
  /// file, or a staged file in tests). Split out from [loadKasheedaFont]
  /// so tests can verify the FontLoader step without a network download.
  /// NOTE: in this Flutter version FontLoader lives in
  /// `package:flutter/services.dart`, not `dart:ui`.
  static Future<void> loadKasheedaFontFromFile(File file) async {
    if (_kasheedaLoaded) return;
    final bytes = await file.readAsBytes();
    final loader = FontLoader(kasheedaFamily);
    loader.addFont(
      Future.value(
        ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
    await loader.load();
    _kasheedaLoaded = true;
  }

  /// Returns the Nigraan intro video file, downloading it from [url] on
  /// first use and reusing the cache afterwards.
  Future<File> getIntroVideo({required String url}) {
    return download(url: url, fileName: introFileName);
  }

  /// Returns the pre-rendered rotating-logo loop file, downloading it
  /// from [url] on first use and reusing the cache afterwards
  /// (Phase 7 — see rotation-decision.md). Throws
  /// [AssetDownloadException] when [url] is empty (not hosted yet);
  /// callers fall back to a generated rotating loop instead.
  Future<File> getLogoMov({required String url}) {
    return download(url: url, fileName: logoMovFileName);
  }

  /// The cached rotating-logo loop, or null when it has never been
  /// downloaded. Never throws.
  Future<File?> cachedLogoMov() => cachedFile(logoMovFileName);

  // ------------------------------------------------------------------
  // v1.3.0 (§9 parity) — bundled-asset extraction.
  //
  // The Final template needs three files GUARANTEED on the device:
  // the Kasheeda font (Urdu must never fall back silently in export),
  // the real 10 s channel intro, and a DejaVu Sans Bold TTF for the
  // FFmpeg drawtext clock. Each is looked for as a bundled asset
  // first and extracted into this cache; the download URLs remain a
  // fallback/override. A missing bundle is NOT an error here — the
  // callers decide (the Final-template export blocks with a clear
  // message when the font truly cannot be obtained).
  // ------------------------------------------------------------------

  /// Bundled asset path of the Kasheeda font (when a build bundles it).
  static const kasheedaAssetPath =
      'assets/fonts/JameelNooriNastaleeqKasheeda.ttf';

  /// Bundled asset path of the real channel intro (v1.3.0, pubspec).
  static const introAssetPath = 'assets/templates/nigraan_intro.mp4';

  /// Bundled asset path + cache name of the user's green-screen
  /// rotating-cube logo VIDEO (final3 default, demo v4, 22 Nov
  /// 2026): chromakeyed into the Final template's logo block in
  /// export. A missing bundle is NOT an error — callers fall back
  /// to the existing logo path (generated frames / .mov / still).
  static const logoGsAssetPath = 'assets/templates/nigraan_logo_gs.mp4';
  static const logoGsFileName = 'nigraan_logo_gs.mp4';

  /// Bundled asset path + cache name of the DejaVu Sans Bold font
  /// (the reference template's Latin font — ribbons' Latin runs are
  /// drawn by the PNG renderer, the ticking clock by drawtext, which
  /// needs a real font FILE).
  static const dejaVuAssetPath = 'assets/fonts/DejaVuSans-Bold.ttf';
  static const dejaVuFileName = 'DejaVuSans-Bold.ttf';

  /// Extracts a bundled asset into the cache as [fileName]. Returns
  /// the cached file, the already-cached file, or null when the asset
  /// is not part of this build. Never throws.
  Future<File?> extractBundledAsset(
    String assetPath,
    String fileName,
  ) async {
    try {
      final cached = await cachedFile(fileName);
      if (cached != null) return cached;
      final data = await rootBundle.load(assetPath);
      final dir = await _cacheDir();
      final file = File(p.join(dir.path, fileName));
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Makes the Kasheeda font ready, in order: already-loaded →
  /// cache → bundled asset → download from [url] (skipped when the
  /// URL is empty). Returns true when the family is registered.
  Future<bool> ensureKasheedaFontReady({String url = ''}) async {
    try {
      if (_kasheedaLoaded) return true;
      final cached = await cachedFile(kasheedaFileName);
      if (cached != null) {
        await loadKasheedaFontFromFile(cached);
        return true;
      }
      final bundled =
          await extractBundledAsset(kasheedaAssetPath, kasheedaFileName);
      if (bundled != null) {
        await loadKasheedaFontFromFile(bundled);
        return true;
      }
      if (url.trim().isNotEmpty) {
        await loadKasheedaFont(url: url);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// The channel intro file: cache → bundled asset (v1.3.0) → null
  /// (the caller may then try [getIntroVideo] with a URL). Never
  /// throws.
  Future<File?> ensureIntroFile() async {
    try {
      final cached = await cachedFile(introFileName);
      if (cached != null) return cached;
      return extractBundledAsset(introAssetPath, introFileName);
    } catch (_) {
      return null;
    }
  }

  /// A DejaVu Sans Bold font FILE for FFmpeg drawtext (the ticking
  /// capsule clock): cache → bundled asset → null (the caller falls
  /// back to a system font). Never throws.
  Future<File?> ensureDejaVuFile() async {
    try {
      final cached = await cachedFile(dejaVuFileName);
      if (cached != null) return cached;
      return extractBundledAsset(dejaVuAssetPath, dejaVuFileName);
    } catch (_) {
      return null;
    }
  }

  /// The green-screen logo video file: cache → bundled asset →
  /// null (the caller falls back to the existing logo path).
  /// Never throws.
  Future<File?> ensureLogoGsFile() async {
    try {
      final cached = await cachedFile(logoGsFileName);
      if (cached != null) return cached;
      return extractBundledAsset(logoGsAssetPath, logoGsFileName);
    } catch (_) {
      return null;
    }
  }

  /// Clears all downloaded assets (frees disk; next use re-downloads).
  Future<void> clearCache() async {
    try {
      final dir = await _cacheDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}
