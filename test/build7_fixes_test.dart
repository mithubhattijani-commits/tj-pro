// Build 7 (v1.5.9) tests — FIX A (splash gate entry), FIX B
// (error funnels, last-5 diagnostics, tagged capture), FIX C
// (remote hero banners) and Phase 8 (design-system tokens,
// generic branding routing + preset-switch proof).
//
// The Phase 9 repairs of the 18 baseline failures live in their
// original files (see BUILD7-TOOL-TESTS.md for the ledger).

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tj_pro/app_config.dart';
import 'package:tj_pro/live/news_template.dart';
import 'package:tj_pro/main.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/services/asset_download_service.dart';
import 'package:tj_pro/services/crash_guard.dart';
import 'package:tj_pro/services/hero_banner_cache.dart';
import 'package:tj_pro/services/remote_config_service.dart';
import 'package:tj_pro/theme.dart';

/// The channel mocks the full-app pumps need (same set as
/// widget_test.dart: path_provider for the stores, the voice
/// recorder channel, platform views for the Home banner ad).
void _mockChannels() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return '/tmp/tj_pro_build7_test';
      }
      if (call.method == 'getApplicationSupportDirectory') {
        return '/tmp/tj_pro_build7_test';
      }
      if (call.method == 'getTemporaryDirectory') {
        return '/tmp/tj_pro_build7_test_tmp';
      }
      return null;
    },
  );
  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.llfbandit.record/messages'),
    (MethodCall call) async => null,
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter/platform_views'),
    (MethodCall call) async {
      if (call.method == 'create') return 1;
      return null;
    },
  );
}

bool _isAssetImage(Widget w, String name) =>
    w is Image &&
    w.image is AssetImage &&
    (w.image as AssetImage).assetName == name;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FIX A — splash gate is the app entry', () {
    setUp(_mockChannels);

    testWidgets(
        'first app-drawn screen is the full-screen poster; '
        'Home appears only after the gate interval', (tester) async {
      await tester.pumpWidget(const PhotoVideoEditorApp());
      await tester.pump();

      // The gate is up, Home is not, and the one image on screen
      // is the poster. Build 8 (v1.6.0, fix-list point #1b): the
      // fit is CONTAIN now, not cover — the user ordered the
      // WHOLE poster visible, never cropped. This assertion was
      // updated with that behaviour change.
      expect(find.byType(SplashGate), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      final poster = find.byWidgetPredicate(
        (w) => _isAssetImage(w, 'assets/splash_poster.png'),
      );
      expect(poster, findsOneWidget);
      expect(tester.widget<Image>(poster).fit, BoxFit.contain);

      // Just before the 1.8 s minimum: still the gate.
      await tester.pump(const Duration(milliseconds: 1700));
      expect(find.byType(HomeScreen), findsNothing);
      expect(poster, findsOneWidget);

      // Past the minimum: Home, and the poster never returns.
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(poster, findsNothing);
      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(poster, findsNothing);
    });
  });

  group('FIX B — CrashGuard funnels + diagnostics', () {
    setUp(() {
      CrashGuard.resetDiagnosticsForTest();
      CrashGuard.resetThrottleForTest();
      CrashGuard.diagnosticsWriter = null;
      CrashGuard.lastError.value = null;
      CrashGuard.appVersion = '';
      CrashGuard.currentRoute = null;
    });

    tearDown(() {
      CrashGuard.diagnosticsWriter = null;
      CrashGuard.resetDiagnosticsForTest();
    });

    test('install wires all funnels; platform + flutter funnels '
        'record with their source tags', () {
      // Swallow the framework handler BEFORE install so the
      // chained call in CrashGuard's handler cannot fail this
      // test (on a phone it is the console dump).
      FlutterError.onError = (FlutterErrorDetails details) {};
      CrashGuard.install();
      expect(FlutterError.onError, isNotNull);
      expect(ui.PlatformDispatcher.instance.onError, isNotNull);

      // Platform funnel: CrashGuard's handler records and
      // returns true (handled).
      final handled = ui.PlatformDispatcher.instance.onError!(
        StateError('funnel-platform'),
        StackTrace.current,
      );
      expect(handled, isTrue);
      expect(CrashGuard.lastDiagnostic.value, contains('funnel-platform'));
      expect(CrashGuard.lastDiagnostic.value, contains('source: platform'));

      // Flutter funnel: records with the flutter tag.
      FlutterError.onError!(
        FlutterErrorDetails(
          exception: StateError('funnel-flutter'),
          stack: StackTrace.current,
        ),
      );
      expect(CrashGuard.lastDiagnostic.value, contains('funnel-flutter'));
      expect(CrashGuard.lastDiagnostic.value, contains('source: flutter'));
    });

    test('zone funnel (the main() pattern) records with its tag',
        () async {
      String? written;
      CrashGuard.diagnosticsWriter = (text) async => written = text;
      // Exactly main()'s shape: fire-and-forget — the guarded
      // future is NOT awaited (awaiting it would re-deliver the
      // error into this test's own zone).
      runZonedGuarded(() async {
        throw StateError('funnel-zone');
      }, (Object e, StackTrace s) {
        CrashGuard.report(e, s, source: 'zone');
      });
      // The handler fires on a later turn; give it real time.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(written, isNotNull);
      expect(written, contains('funnel-zone'));
      expect(written, contains('source: zone'));
    });

    test('diagnostics keep the LAST FIVE records, newest first',
        () async {
      String? written;
      CrashGuard.diagnosticsWriter = (text) async => written = text;
      for (var i = 1; i <= 7; i++) {
        try {
          throw StateError('err-$i');
        } catch (e, s) {
          CrashGuard.report(e, s, source: 'unit-test');
        }
      }
      expect(CrashGuard.recentDiagnostics, hasLength(5));
      expect(CrashGuard.recentDiagnostics.first, contains('err-7'));
      expect(CrashGuard.recentDiagnostics.last, contains('err-3'));
      expect(written, isNotNull);
      expect(written, contains('err-7'));
      expect(written, contains('err-3'));
      expect(written, isNot(contains('err-2')));
      expect(written, isNot(contains('err-1')));
      expect(CrashGuard.lastDiagnostic.value, written);
    });

    test('captureHandled records with its tag and raises NO banner',
        () {
      String? written;
      CrashGuard.diagnosticsWriter = (text) async => written = text;
      try {
        throw StateError('handled-boom');
      } catch (e, s) {
        CrashGuard.captureHandled(e, s, source: 'maker.preview');
      }
      expect(written, isNotNull);
      expect(written, contains('handled-boom'));
      expect(written, contains('source: maker.preview'));
      // No banner machinery was touched: lastError stays null
      // (report() is the only path that sets it + shows the
      // SnackBar), so a handled error can never alarm the user.
      expect(CrashGuard.lastError.value, isNull);
    });

    test('records carry app version + route when known', () {
      CrashGuard.appVersion = '1.5.9 (23)';
      CrashGuard.currentRoute = '/test-screen';
      final text = CrashGuard.formatDiagnostic(
        StateError('ctx'),
        StackTrace.current,
        'unit-test',
        DateTime(2026, 11, 24),
        appVersion: CrashGuard.appVersion,
        route: CrashGuard.currentRoute,
      );
      expect(text, contains('app: 1.5.9 (23)'));
      expect(text, contains('route: /test-screen'));
      // And end-to-end through report():
      String? written;
      CrashGuard.diagnosticsWriter = (t) async => written = t;
      CrashGuard.report(StateError('ctx-e2e'), StackTrace.current,
          source: 'unit-test');
      expect(written, contains('app: 1.5.9 (23)'));
      expect(written, contains('route: /test-screen'));
    });

    testWidgets('route observer tracks the visible route',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [CrashGuard.routeObserver],
          home: const Scaffold(body: Text('root')),
          routes: {
            '/second': (context) =>
                const Scaffold(body: Text('second')),
          },
        ),
      );
      await tester.pump();
      expect(CrashGuard.currentRoute, isNotNull);
      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushNamed('/second');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(CrashGuard.currentRoute, '/second');
    });
  });

  group('FIX C — remote hero banners', () {
    test('config parsing: hero keys present', () {
      final cfg = RemoteConfig.fromJson(const <String, dynamic>{
        'hero_banner_1_url': 'https://x.test/b1.jpg',
        'hero_banner_1_link': 'https://x.test/landing',
        'hero_banner_2_url': 'https://x.test/b2.jpg',
        'hero_banner_2_link': 'https://x.test/ad',
      });
      expect(cfg.heroBanner1ImageUrl, 'https://x.test/b1.jpg');
      expect(cfg.heroBanner1TapUrl, 'https://x.test/landing');
      expect(cfg.heroBanner2ImageUrl, 'https://x.test/b2.jpg');
      expect(cfg.heroBanner2TapUrl, 'https://x.test/ad');
    });

    test('config parsing: hero keys missing → today\'s defaults', () {
      final cfg = RemoteConfig.fromJson(const <String, dynamic>{});
      // Slide 1: bundled asset (empty URL) + website tap.
      expect(cfg.heroBanner1ImageUrl, '');
      expect(cfg.heroBanner1TapUrl, 'https://nigraantv.xyz');
      // Slide 2: the existing advertising chain, untouched.
      expect(cfg.heroBanner2ImageUrl, AppConfig.advertisingBannerImageUrl);
      expect(cfg.heroBanner2TapUrl, '');
      // Existing keys still parse exactly as before.
      expect(cfg.kasheedaFontUrl, AppConfig.kasheedaFontUrl);
    });

    test('slide-2 mapping: hero-2 override wins; without it the '
        'Supabase advertising override still wins', () {
      final withHero2 = RemoteConfig.fromJson(const <String, dynamic>{
        'hero_banner_2_url': 'https://x.test/hero2.jpg',
        'hero_banner_2_link': 'https://x.test/hero2-link',
      });
      final overridden = withHero2.withAdvertisingBanner(
        imageUrl: 'https://x.test/supabase.jpg',
        linkUrl: 'https://x.test/supabase-link',
      );
      expect(overridden.heroBanner2ImageUrl, 'https://x.test/hero2.jpg');
      expect(overridden.heroBanner2TapUrl, 'https://x.test/hero2-link');

      const plain = RemoteConfig();
      final supa = plain.withAdvertisingBanner(
        imageUrl: 'https://x.test/supabase.jpg',
        linkUrl: 'https://x.test/supabase-link',
      );
      expect(supa.heroBanner2ImageUrl, 'https://x.test/supabase.jpg');
      expect(supa.heroBanner2TapUrl, 'https://x.test/supabase-link');
      // The override never disturbs unrelated fields.
      expect(supa.heroBanner1TapUrl, 'https://nigraantv.xyz');
    });

    group('HeroBannerCache', () {
      late Directory tempDir;
      late List<int> jpegBytes;

      setUp(() async {
        tempDir = await Directory.systemTemp.createTemp('tj_b7_hero_');
        HeroBannerCache.overrideDirForTest = tempDir;
        HeroBannerCache.resetForTest();
        jpegBytes = await File('assets/hero_nigraan_banner.jpg')
            .readAsBytes();
      });

      tearDown(() async {
        HeroBannerCache.downloaderForTest = null;
        HeroBannerCache.overrideDirForTest = null;
        HeroBannerCache.resetForTest();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      test('magic-byte validation rejects non-images', () async {
        expect(
          HeroBannerCache.looksLikeImage(jpegBytes),
          isTrue,
        );
        expect(
          HeroBannerCache.looksLikeImage(
            List<int>.filled(64, 7),
          ),
          isFalse,
        );
        final ok = await HeroBannerCache.instance.storeBytes(
          HeroBannerCache.slot1,
          'https://x.test/broken.jpg',
          List<int>.filled(64, 7),
        );
        expect(ok, isFalse);
        expect(
          HeroBannerCache.instance.cachedFileFor(
            HeroBannerCache.slot1,
            'https://x.test/broken.jpg',
          ),
          isNull,
        );
      });

      test('warm downloads, caches, and serves from disk after '
          'a memory reset', () async {
        var downloads = 0;
        HeroBannerCache.downloaderForTest = (url) async {
          downloads++;
          return jpegBytes;
        };
        await HeroBannerCache.instance
            .warm(HeroBannerCache.slot1, 'https://x.test/b1.jpg');
        expect(downloads, 1);
        final cached = HeroBannerCache.instance.cachedFileFor(
          HeroBannerCache.slot1,
          'https://x.test/b1.jpg',
        );
        expect(cached, isNotNull);
        expect(await cached!.readAsBytes(), jpegBytes);

        // Same URL again: no second download.
        await HeroBannerCache.instance
            .warm(HeroBannerCache.slot1, 'https://x.test/b1.jpg');
        expect(downloads, 1);

        // Memory forgotten + downloader now failing: the disk
        // copy still serves (cache-first across launches).
        HeroBannerCache.resetForTest();
        HeroBannerCache.downloaderForTest = (url) async => null;
        await HeroBannerCache.instance
            .warm(HeroBannerCache.slot1, 'https://x.test/b1.jpg');
        expect(
          HeroBannerCache.instance.cachedFileFor(
            HeroBannerCache.slot1,
            'https://x.test/b1.jpg',
          ),
          isNotNull,
        );

        // A URL change downloads the fresh copy.
        HeroBannerCache.downloaderForTest = (url) async {
          downloads++;
          return jpegBytes;
        };
        await HeroBannerCache.instance
            .warm(HeroBannerCache.slot1, 'https://x.test/b1-v2.jpg');
        expect(downloads, 2);
        expect(
          HeroBannerCache.instance.cachedFileFor(
            HeroBannerCache.slot1,
            'https://x.test/b1-v2.jpg',
          ),
          isNotNull,
        );
      });
    });

    group('Home wiring (widget)', () {
      setUp(() {
        _mockChannels();
        HeroBannerCache.overrideDirForTest =
            Directory('/tmp/tj_pro_build7_test');
        HeroBannerCache.resetForTest();
      });

      tearDown(() {
        remoteConfigService.notifier.value = RemoteConfig.defaults;
        HeroBannerCache.downloaderForTest = null;
        HeroBannerCache.overrideDirForTest = null;
        HeroBannerCache.resetForTest();
      });

      testWidgets(
          'remote slide-1 failure falls back to the bundled banner',
          (tester) async {
        remoteConfigService.notifier.value =
            RemoteConfig.fromJson(const <String, dynamic>{
          'hero_banner_1_url': 'https://example.invalid/b1.jpg',
        });
        await tester.pumpWidget(const PhotoVideoEditorApp());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1900));
        await tester.pump();
        // The hero slide exists and shows the bundled artwork —
        // never a blank/broken slide.
        expect(find.byKey(const Key('homeHeroBanner')), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (w) => _isAssetImage(w, 'assets/hero_nigraan_banner.jpg'),
          ),
          findsWidgets,
        );
      });

      testWidgets('slide 2 keeps BoxFit.contain with a remote URL',
          (tester) async {
        remoteConfigService.notifier.value =
            RemoteConfig.fromJson(const <String, dynamic>{
          'advertising_banner_enabled': true,
          'hero_banner_2_url': 'https://example.invalid/ad.jpg',
        });
        await tester.pumpWidget(const PhotoVideoEditorApp());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1900));
        await tester.pump();
        // Swipe the carousel to slide 2.
        await tester.fling(
          find.byType(PageView),
          const Offset(-300, 0),
          800,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        // The remote load fails in tests → the fallback is the
        // bundled house banner, contain-fit (never cropped).
        final fallback = find.byWidgetPredicate(
          (w) => _isAssetImage(w, AppConfig.advertisingBannerImageUrl),
        );
        expect(fallback, findsWidgets);
        for (final element in fallback.evaluate()) {
          final image = element.widget as Image;
          expect(image.fit, BoxFit.contain);
        }
      });
    });
  });

  group('Phase 8 — design system + generic branding', () {
    test('theme tokens: dark theme is the seed scheme; splash + '
        'Urdu rules single-sourced', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: TjProTheme.gold,
        brightness: Brightness.dark,
      );
      expect(TjProTheme.dark.colorScheme.primary, scheme.primary);
      // Build 8 (v1.6.0, fix-list point #1): the splash colour
      // is now the canonical poster's own sampled edge colour
      // (#030E3F), replacing the hand-picked #040F30 — this
      // assertion was updated with that change.
      expect(TjProTheme.splashBackground, const Color(0xFF030E3F));
      expect(
        TjProTheme.urduTextStyle(const TextStyle()).fontFamily,
        TjProTheme.kasheedaFamily,
      );
      expect(
        AssetDownloadService.kasheedaFamily,
        TjProTheme.kasheedaFamily,
      );
    });

    test('preset defaults route to the Nigraan assets; old JSON '
        'without the keys loads the same defaults', () {
      final preset = ChannelPreset.nigraanTv();
      expect(preset.introAssetPath, AssetDownloadService.introAssetPath);
      expect(
        preset.logoGsAssetPath,
        AssetDownloadService.logoGsAssetPath,
      );
      expect(
        preset.logoGsFrameAssetPath,
        AssetDownloadService.logoGsFrameAssetPath,
      );
      final json = preset.toJson()
        ..remove('introAssetPath')
        ..remove('logoGsAssetPath')
        ..remove('logoGsFrameAssetPath');
      final restored = ChannelPreset.fromJson(json);
      expect(restored.introAssetPath, preset.introAssetPath);
      expect(restored.logoGsAssetPath, preset.logoGsAssetPath);
      expect(
        restored.logoGsFrameAssetPath,
        preset.logoGsFrameAssetPath,
      );
    });

    test('switching presets changes branding; switching back is '
        'identical', () {
      final base = ChannelPreset.nigraanTv()
        ..finalVariant = kFinalVariantClassic2;
      final baseLayout = NigraanFinalLayout.compute(
        preset: base,
        width: 720,
        height: 1280,
      );
      final other = ChannelPreset.nigraanTv()
        ..finalVariant = kFinalVariantClassic2
        ..topRibbon.color = 0xFF2E7D32
        ..brandColor = 0xFF2E7D32
        ..introAssetPath = 'assets/templates/other_intro.mp4'
        ..logoGsAssetPath = 'assets/templates/other_logo_gs.mp4';
      final otherLayout = NigraanFinalLayout.compute(
        preset: other,
        width: 720,
        height: 1280,
      );
      // Branding actually flows: colours + media paths differ.
      expect(otherLayout.topColor, 0xFF2E7D32);
      expect(otherLayout.topColor, isNot(baseLayout.topColor));
      expect(other.introAssetPath, 'assets/templates/other_intro.mp4');
      // JSON round-trip preserves the custom branding.
      final restored = ChannelPreset.fromJson(other.toJson());
      expect(restored.introAssetPath, other.introAssetPath);
      expect(restored.logoGsAssetPath, other.logoGsAssetPath);
      // Switch back: the default preset's layout is identical.
      final backLayout = NigraanFinalLayout.compute(
        preset: ChannelPreset.nigraanTv()
          ..finalVariant = kFinalVariantClassic2,
        width: 720,
        height: 1280,
      );
      expect(backLayout.topColor, baseLayout.topColor);
      expect(backLayout.logoRect, baseLayout.logoRect);
      expect(backLayout.capsuleRect, baseLayout.capsuleRect);
      expect(backLayout.urduStrip, baseLayout.urduStrip);
    });

    test('AssetDownloadService honours the preset asset path',
        () async {
      final temp = await Directory.systemTemp.createTemp('tj_b7_ads_');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final service = AssetDownloadService(cacheDirOverride: temp);
      // Default: the Nigraan intro, under its cache name.
      final intro = await service.ensureIntroFile();
      expect(intro, isNotNull);
      expect(intro!.path, contains(AssetDownloadService.introFileName));
      // A preset pointing at another bundled file gets THAT
      // file, cached under its own name (never the Nigraan one).
      final other = await service.ensureIntroFile(
        assetPath: AssetDownloadService.logoGsAssetPath,
      );
      expect(other, isNotNull);
      expect(other!.path, contains('nigraan_logo_gs.mp4'));
      expect(other.path, isNot(intro.path));
      final gs = await service.ensureLogoGsFile(
        assetPath: AssetDownloadService.introAssetPath,
      );
      expect(gs, isNotNull);
      expect(gs!.path, contains('nigraan_intro.mp4'));
    });
  });
}
