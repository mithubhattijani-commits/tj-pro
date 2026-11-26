// v1.24.0 (G4) — RNNoise permanent-fix regression tests.
//
// The proven bug (RNNOISE-DIAGNOSIS-2026-11-26.md): cb.rnnn
// is the one pack file served text/plain, so dart:io
// negotiated gzip and decompressed silently while
// Content-Length kept the COMPRESSED count (109,908) — the
// downloaders' `received != contentLength` check failed a
// perfect 299,741-byte download every time. The fix, in both
// ModelPackService._download and AssetDownloadService
// .download: send `Accept-Encoding: identity`, and apply
// the length check only to unencoded responses.
//
// Test (a) FAILS on the old code (ensurePack returns false)
// and passes on the new; (b) proves the incomplete check
// still bites a genuinely truncated download; (c) proves
// the normal identity flow. Real async IO runs under
// tester.runAsync throughout (the asset-test precedent).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tj_pro/services/asset_download_service.dart';
import 'package:tj_pro/services/crash_reporter.dart';
import 'package:tj_pro/services/model_pack_service.dart';

/// The real cb.rnnn size — the verified pin.
const int _kCbSize = 299741;

/// The gzip Content-Length the diagnosis measured.
const int _kCbGzipLength = 109908;

List<int> _fixtureBytes(int length) =>
    List<int>.generate(length, (i) => (i * 31 + 7) % 256);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDir;

  setUp(() async {
    supportDir = await Directory.systemTemp.createTemp('tj_g4_support_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => supportDir.path,
    );
  });

  tearDown(() async {
    ModelPackService.instance.httpClientOverride = null;
    if (await supportDir.exists()) {
      await supportDir.delete(recursive: true);
    }
  });

  MockClient streamingClient({
    required List<int> body,
    required int contentLength,
    Map<String, String> headers = const {},
    void Function(http.BaseRequest request)? onRequest,
  }) {
    return MockClient.streaming((request, bodyStream) async {
      onRequest?.call(request);
      return http.StreamedResponse(
        Stream<List<int>>.fromIterable([body]),
        200,
        contentLength: contentLength,
        headers: headers,
      );
    });
  }

  testWidgets(
      '(a) gzip case: compressed Content-Length + decompressed '
      'body is a SUCCESS — the RNNoise regression', (tester) async {
    await tester.runAsync(() async {
      String? acceptEncoding;
      ModelPackService.instance.httpClientOverride = streamingClient(
        body: _fixtureBytes(_kCbSize),
        contentLength: _kCbGzipLength,
        headers: const {'content-encoding': 'gzip'},
        onRequest: (r) => acceptEncoding = r.headers['accept-encoding'],
      );
      final ok = await ModelPackService.instance
          .ensurePack('rnnoise_models');
      expect(ok, isTrue,
          reason: 'a perfect download behind a gzip header must pass');
      expect(ModelPackService.instance.lastFailure, isNull);
      // The request itself now asks for identity encoding.
      expect(acceptEncoding, 'identity');
      final file = File(
        '${supportDir.path}/model_packs/rnnoise_models/cb.rnnn',
      );
      expect(await file.exists(), isTrue);
      expect(await file.length(), _kCbSize);
      expect(
        await ModelPackService.instance.isReady('rnnoise_models'),
        isTrue,
      );
    });
  });

  testWidgets(
      '(b) a genuinely truncated identity download is STILL '
      'incomplete — the check was not weakened', (tester) async {
    await tester.runAsync(() async {
      ModelPackService.instance.httpClientOverride = streamingClient(
        body: _fixtureBytes(100000),
        contentLength: _kCbSize,
      );
      final ok = await ModelPackService.instance
          .ensurePack('rnnoise_models');
      expect(ok, isFalse);
      expect(
        ModelPackService.instance.lastFailure,
        PackFailure.incomplete,
      );
      final file = File(
        '${supportDir.path}/model_packs/rnnoise_models/cb.rnnn',
      );
      expect(await file.exists(), isFalse);
      expect(await File('${file.path}.part').exists(), isFalse);
    });
  });

  testWidgets('(c) identity exact-length download succeeds',
      (tester) async {
    await tester.runAsync(() async {
      ModelPackService.instance.httpClientOverride = streamingClient(
        body: _fixtureBytes(_kCbSize),
        contentLength: _kCbSize,
        headers: const {'content-encoding': 'identity'},
      );
      final ok = await ModelPackService.instance
          .ensurePack('rnnoise_models');
      expect(ok, isTrue);
      expect(ModelPackService.instance.lastFailure, isNull);
    });
  });

  testWidgets('AssetDownloadService: the same gzip case succeeds, '
      'and a truncated identity download still throws',
      (tester) async {
    await tester.runAsync(() async {
      final cacheDir =
          await Directory.systemTemp.createTemp('tj_g4_asset_');
      addTearDown(() async {
        if (await cacheDir.exists()) await cacheDir.delete(recursive: true);
      });
      final payload = _fixtureBytes(4096);
      String? acceptEncoding;
      final gzipService = AssetDownloadService(
        cacheDirOverride: cacheDir,
        httpClient: streamingClient(
          body: payload,
          contentLength: 1234,
          headers: const {'content-encoding': 'gzip'},
          onRequest: (r) => acceptEncoding = r.headers['accept-encoding'],
        ),
      );
      final file = await gzipService.download(
        url: 'https://example.com/text-asset.txt',
        fileName: 'text-asset.txt',
      );
      expect(await file.readAsBytes(), payload);
      expect(acceptEncoding, 'identity');

      final truncatedService = AssetDownloadService(
        cacheDirOverride: cacheDir,
        httpClient: streamingClient(
          body: _fixtureBytes(1000),
          contentLength: 4096,
        ),
      );
      var threw = false;
      try {
        await truncatedService.download(
          url: 'https://example.com/cut.bin',
          fileName: 'cut.bin',
        );
      } on AssetDownloadException {
        threw = true;
      }
      expect(threw, isTrue,
          reason: 'a short unencoded body must still be incomplete');
    });
  });

  test('Fix 3: a prep pack failure records through '
      'CrashReporter.enqueue with its typed reason', () async {
    CrashReporter.resetForTest();
    CrashReporter.prefsReader = (_) async => null;
    CrashReporter.prefsWriter = (_, _) async {};
    CrashReporter.sendOverride = (_) async => true;
    // The exact call shape FirstRunPrepService makes when a
    // pack item fails.
    CrashReporter.instance.enqueue(
      StateError(
        'Pack rnnoise_models failed during tools prep: incomplete',
      ),
      StackTrace.current,
      source: 'tools_prep.pack',
    );
    final rows = CrashReporter.instance.queuedReports;
    expect(rows, hasLength(1));
    expect(rows.single['source'], 'tools_prep.pack');
    expect(rows.single['error'], contains('rnnoise_models'));
    expect(rows.single['error'], contains('incomplete'));
    CrashReporter.resetForTest();
  });
}
