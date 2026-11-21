// Phase 2 tests for AssetDownloadService (on-demand assets):
// download + cache + progress with an injected MockClient (the
// flutter_test binding replaces the dart:io HttpClient with a mock that
// answers 400 to every request, so no real socket — external or
// loopback — can be tested in a widget test), the empty-URL guard, and
// FontLoader loading the staged Kasheeda TTF from its local file path.
//
// NOTE: real async I/O inside testWidgets must run under
// tester.runAsync — the testWidgets fake-async zone otherwise never
// lets socket/file events or Future.timeouts fire, and the test hangs.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tj_pro/services/asset_download_service.dart';

void main() {
  testWidgets('download caches a file and reports progress', (tester) async {
    await tester.runAsync(() async {
      final temp = await Directory.systemTemp.createTemp('tj_pro_asset_test');
      final payload = List<int>.generate(4096, (i) => i % 256);
      var requests = 0;
      final mockClient = MockClient((http.Request request) async {
        requests++;
        return http.Response.bytes(
          payload,
          200,
          headers: {'content-length': payload.length.toString()},
        );
      });
      final service = AssetDownloadService(
        cacheDirOverride: temp,
        httpClient: mockClient,
      );

      var lastProgress = 0.0;
      var progressCalls = 0;
      final file = await service.download(
        url: 'https://example.com/probe.bin',
        fileName: 'probe.bin',
        onProgress: (p) {
          lastProgress = p;
          progressCalls++;
        },
      );
      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), payload);
      expect(requests, 1);
      expect(progressCalls, greaterThan(0));
      expect(lastProgress, 1.0);

      // Second call returns the cached file (same path, no re-download).
      final again = await service.download(
        url: 'https://example.com/probe.bin',
        fileName: 'probe.bin',
      );
      expect(again.path, file.path);
      expect(requests, 1);
    });
  });

  testWidgets('empty URL throws instead of downloading garbage',
      (tester) async {
    await tester.runAsync(() async {
      final temp = await Directory.systemTemp.createTemp('tj_pro_asset_test');
      final service = AssetDownloadService(cacheDirOverride: temp);
      var threwDownload = false;
      try {
        await service.download(url: '', fileName: 'nothing.bin');
      } on AssetDownloadException {
        threwDownload = true;
      }
      expect(threwDownload, isTrue);
      var threwFont = false;
      try {
        await service.loadKasheedaFont(url: '');
      } on AssetDownloadException {
        threwFont = true;
      }
      expect(threwFont, isTrue);
    });
  });

  // Plain test() — NOT testWidgets: FontLoader.load() awaits the
  // engine's font registration, which never completes inside the
  // testWidgets fake-async zone (even under runAsync it hung here).
  // A plain test runs in real async, so the load completes.
  test('Kasheeda font loads from the staged TTF file', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final home = Platform.environment['HOME'];
    expect(home, isNotNull, reason: 'HOME must be set on the test host');
    final staged = File(
      '$home/workspace/tj-pro-news-maker/assets-staging/'
      'Jameel Noori Nastaleeq Kasheeda/'
      'Jameel Noori Nastaleeq Kasheeda.ttf',
    );
    expect(await staged.exists(), isTrue,
        reason: 'staged Kasheeda TTF must exist');
    await AssetDownloadService.loadKasheedaFontFromFile(staged);
  });

  testWidgets('Kasheeda font renders Urdu text', (tester) async {
    // Runs after the plain test above in the same isolate, so the font
    // is already registered (guarded by _kasheedaLoaded).
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Text(
            'نگران ٹی وی',
            style: TextStyle(
              fontFamily: AssetDownloadService.kasheedaFamily,
            ),
          ),
        ),
      ),
    );
    expect(find.text('نگران ٹی وی'), findsOneWidget);
  });
}
