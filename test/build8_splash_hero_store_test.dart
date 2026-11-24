// Build 8 (v1.6.0) — fix-list points #1 + #2 + #3.
//
// Point #1 (splash): the gate shows the WHOLE poster
// (BoxFit.contain, never cropped) on the poster's own sampled
// edge colour, and the poster source is the remote config's
// splash_poster_url with the hero banners' fallback chain
// (cached remote copy -> bundled canonical poster).
// Point #2 (hero): the carousel frame adapts to the active
// slide's image aspect — pure math pinned here, plus a widget
// check that the frame leaves the old fixed 178dp once the
// bundled banner's aspect (2.084:1) is known.
// Point #3 (store): preview files are never items, each item
// learns its preview's file id, card display names are cleaned
// of the technical markers, and pricing still reads the RAW
// file name exactly as before.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/main.dart';
import 'package:tj_pro/news/store_screen.dart';
import 'package:tj_pro/services/hero_banner_cache.dart';
import 'package:tj_pro/services/remote_config_service.dart';
import 'package:tj_pro/services/store_preview_cache.dart';
import 'package:tj_pro/services/store_service.dart';
import 'package:tj_pro/theme.dart';
import 'package:tj_pro/widgets/hero_aspect.dart';

/// Home hosts a Unity banner AndroidView and the store's entry
/// gate touches the Unity plugin; without a platform side their
/// create/dispose/init calls throw MissingPluginException into
/// whichever test happens to be running (including a LATER one,
/// when a leftover view is disposed). Mock the channels for the
/// whole file so the platform lifecycle is silent everywhere.
void mockPlatformChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final channel in const [
    'flutter/platform_views',
    'flutter/platform_views_2',
    'com.rebeloid.unity_ads',
  ]) {
    messenger.setMockMethodCallHandler(
      MethodChannel(channel),
      (MethodCall call) async => null,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(mockPlatformChannels);

  group('Point #1 — remote splash poster config', () {
    test('splash_poster_url parsed from JSON', () {
      final cfg = RemoteConfig.fromJson(const <String, dynamic>{
        'splash_poster_url': 'https://x.test/poster.jpg',
      });
      expect(cfg.splashPosterImageUrl, 'https://x.test/poster.jpg');
    });

    test('missing key -> hosted canonical poster default', () {
      final cfg = RemoteConfig.fromJson(const <String, dynamic>{});
      expect(
        cfg.splashPosterImageUrl,
        'https://nigraantv.xyz/apps/splash/poster.jpg',
      );
      expect(
        RemoteConfig.defaults.splashPosterImageUrl,
        RemoteConfig.splashPosterDefaultUrl,
      );
    });

    test('admin-banner override preserves the splash poster', () {
      final cfg = RemoteConfig.fromJson(const <String, dynamic>{
        'splash_poster_url': 'https://x.test/keep.jpg',
      });
      final overridden = cfg.withAdvertisingBanner(
        imageUrl: 'https://x.test/ad.jpg',
        linkUrl: '',
      );
      expect(overridden.splashPosterImageUrl, 'https://x.test/keep.jpg');
    });

    test('gate background is the sampled poster edge colour', () {
      // Sampled from the canonical poster (mean of its top and
      // bottom strip medians) — see theme.dart.
      expect(TjProTheme.splashBackground, const Color(0xFF030E3F));
    });
  });

  group('Point #1 — SplashGate fallback chain (widget)', () {
    late Directory tempDir;
    late List<int> posterBytes;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tj_b8_splash_');
      HeroBannerCache.overrideDirForTest = tempDir;
      HeroBannerCache.resetForTest();
      posterBytes = await File('assets/splash_poster.png').readAsBytes();
      // No network in tests: downloads fail soft to the bundle.
      HeroBannerCache.downloaderForTest = (_) async => null;
    });

    tearDown(() async {
      HeroBannerCache.downloaderForTest = null;
      HeroBannerCache.overrideDirForTest = null;
      HeroBannerCache.resetForTest();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('no cache: bundled poster, contain fit', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const PhotoVideoEditorApp());
      await tester.pump();

      final poster = tester.widget<Image>(
        find.descendant(
          of: find.byType(SplashGate),
          matching: find.byType(Image),
        ),
      );
      expect(
        (poster.image as AssetImage).assetName,
        'assets/splash_poster.png',
      );
      expect(poster.fit, BoxFit.contain);
      final scaffold = tester.widget<Scaffold>(
        find.descendant(
          of: find.byType(SplashGate),
          matching: find.byType(Scaffold),
        ),
      );
      expect(scaffold.backgroundColor, TjProTheme.splashBackground);

      // Let the gate swap so no timers outlive the test.
      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pump();
      expect(find.text('VIDEO EDITOR'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cached remote poster wins over the bundle',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      // Real file IO must run OUTSIDE the fake-async zone —
      // awaiting it directly in a testWidgets body deadlocks.
      final stored = await tester.runAsync(
        () => HeroBannerCache.instance.storeBytes(
          HeroBannerCache.slotSplash,
          RemoteConfig.splashPosterDefaultUrl,
          posterBytes,
        ),
      );
      expect(stored, isTrue);

      await tester.pumpWidget(const PhotoVideoEditorApp());
      await tester.pump();

      final poster = tester.widget<Image>(
        find.descendant(
          of: find.byType(SplashGate),
          matching: find.byType(Image),
        ),
      );
      expect(poster.image, isA<FileImage>());
      expect(poster.fit, BoxFit.contain);

      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('Point #2 — hero frame math', () {
    test('aspect from size, with guards', () {
      expect(heroAspectFromSize(1211, 881), closeTo(1.3746, 0.001));
      expect(heroAspectFromSize(0, 100), isNull);
      expect(heroAspectFromSize(100, 0), isNull);
      expect(heroAspectFromSize(-5, 100), isNull);
    });

    test('aspect clamping', () {
      expect(clampHeroAspect(1.3746), closeTo(1.3746, 0.0001));
      expect(clampHeroAspect(9.0), maxHeroAspect);
      expect(clampHeroAspect(0.4), minHeroAspect);
      expect(clampHeroAspect(double.nan), 2.21);
      expect(clampHeroAspect(0), 2.21);
    });

    test('unknown aspect keeps the historical 178dp frame', () {
      expect(
        heroFrameHeight(width: 393, aspect: null, maxHeight: 383),
        defaultHeroHeight,
      );
    });

    test('the user banner (1211x881) fits whole: no crop', () {
      // Old frame: 393/2.21 = 178dp -> cover would crop ~38% of
      // this banner's height. New frame follows the banner.
      final h = heroFrameHeight(
        width: 393,
        aspect: heroAspectFromSize(1211, 881),
        maxHeight: 383,
      );
      expect(h, closeTo(285.9, 0.5));
    });

    test('old bundled banner aspect reproduces ~the old frame', () {
      final h = heroFrameHeight(
        width: 393,
        aspect: 2.21,
        maxHeight: 383,
      );
      expect(h, closeTo(177.8, 0.5));
    });

    test('screen-height cap wins over a tall banner', () {
      expect(
        heroFrameHeight(width: 393, aspect: 1.15, maxHeight: 300),
        300,
      );
    });

    test('extreme aspects are clamped before fitting', () {
      final h = heroFrameHeight(
        width: 393,
        aspect: 10,
        maxHeight: 383,
      );
      expect(h, closeTo(393 / maxHeroAspect, 0.5));
    });
  });

  group('Point #2 — hero frame adapts in the app (widget)', () {
    testWidgets('frame leaves 178dp once the banner aspect lands',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const PhotoVideoEditorApp());
      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pump();
      expect(find.byType(PageView), findsOneWidget);

      // Let the bundled banner decode so its probe can report
      // the aspect and the frame can adapt. Poll (real time for
      // the decode, fake time for the 220 ms height animation)
      // because this machine's speed varies run to run.
      final Finder frame = find.ancestor(
        of: find.byType(PageView),
        matching: find.byType(AnimatedContainer),
      );
      double height = tester.getSize(frame).height;
      for (var attempt = 0; attempt < 12 && height <= 200; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        height = tester.getSize(frame).height;
      }
      // Default test surface is 800x600: the bundled banner is
      // 2.084:1, so the fitted height (~376) hits the 45% cap
      // (270) — far from the old fixed 178.
      expect(height, greaterThan(200));
      expect(tester.takeException(), isNull);
      // Flush the post-launch flow's pending timers (the update
      // check's 5 s network timeout) so none outlive the test.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
    });
  });

  group('Point #3 — store listing rules', () {
    StoreItem item(String name, String category, {String id = 'x'}) =>
        StoreItem(id: id, name: name, category: category);

    test('preview file names are detected', () {
      expect(
        StoreService.isPreviewFileName('Caption - X.preview.jpg'),
        isTrue,
      );
      expect(StoreService.isPreviewFileName('X.Preview.JPG'), isTrue);
      expect(StoreService.isPreviewFileName('Normal Item.mp4'), isFalse);
      expect(StoreService.isPreviewFileName('Preview Item.mp4'), isFalse);
    });

    test('preview base name matches the item title', () {
      const name = 'Caption - Chat Bubbles 3D Gradient (Transparent).png';
      const preview = 'Caption - Chat Bubbles 3D Gradient '
          '(Transparent).preview.jpg';
      expect(
        StoreService.previewBaseName(preview).toLowerCase(),
        item(name, 'Captions').title.toLowerCase(),
      );
    });

    test('listing: previews excluded + mapped (Music)', () {
      final listing = StoreService.buildCategoryListing('Music', [
        item('News Bed - X.mp3', 'Music', id: 'song1'),
        item('News Bed - X.preview.jpg', 'Music', id: 'prev1'),
        item('Notes.txt', 'Music', id: 'stray'),
        const StoreItem(
          id: 'zero',
          name: 'Empty.mp3',
          category: 'Music',
          sizeBytes: 0,
        ),
      ]);
      // The .jpg preview would fail Music's extension filter —
      // it must STILL be mapped, and never listed as an item.
      expect(listing.items.map((e) => e.id), ['song1']);
      expect(listing.previews, {'news bed - x': 'prev1'});
    });

    test('listing: previews excluded even where .jpg is an item '
        'extension (Backgrounds)', () {
      final listing = StoreService.buildCategoryListing('Backgrounds', [
        item('Space Background - A (Landscape).jpg', 'Backgrounds',
            id: 'bg1'),
        item('Space Background - A (Landscape).preview.jpg',
            'Backgrounds',
            id: 'prev1'),
      ]);
      expect(listing.items.map((e) => e.id), ['bg1']);
      expect(
        listing.previews,
        {'space background - a (landscape)': 'prev1'},
      );
    });

    test('display names are cleaned of technical markers', () {
      expect(
        item('Caption - Chat Bubbles 3D Gradient (Transparent).png',
                'Captions')
            .displayTitle,
        'Caption - Chat Bubbles 3D Gradient',
      );
      expect(
        item('Space Background - Hubble Star Cluster FREE '
                '(Landscape).jpg', 'Backgrounds')
            .displayTitle,
        'Space Background - Hubble Star Cluster FREE',
      );
      expect(
        item('Animation - Rotating Globe (Square).mp4', 'Animations')
            .displayTitle,
        'Animation - Rotating Globe',
      );
      expect(
        item('Caption - X (transparent).png', 'Captions').displayTitle,
        'Caption - X',
      );
      expect(
        item('Effect - Plain Name.mp4', 'Effects').displayTitle,
        'Effect - Plain Name',
      );
      // The raw title itself is untouched.
      expect(
        item('Animation - Rotating Globe (Square).mp4', 'Animations')
            .title,
        'Animation - Rotating Globe (Square)',
      );
    });

    test('priceFor still reads the RAW name (FREE + table)', () {
      final store = StoreService.instance;
      expect(
        store.priceFor(item('Weather Bed - Calm Morning FREE.mp3', 'Music')),
        0,
      );
      expect(store.priceFor(item('News Bed - X.mp3', 'Music')), 30);
      expect(
        store.priceFor(item('Template - Big.mp4', 'Templates')),
        50,
      );
      // FREE detection survives display cleaning: the marker is
      // stripped from what the user SEES, never from pricing.
      final free = item(
        'Space Background - Hubble FREE (Landscape).jpg',
        'Backgrounds',
      );
      expect(free.displayTitle, 'Space Background - Hubble FREE');
      expect(store.priceFor(free), 0);
    });
  });

  group('Point #3 — StorePreviewCache', () {
    late Directory tempDir;
    late List<int> jpegBytes;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tj_b8_store_');
      StorePreviewCache.overrideDirForTest = tempDir;
      StorePreviewCache.resetForTest();
      jpegBytes = await File('assets/hero_nigraan_banner.jpg').readAsBytes();
    });

    tearDown(() async {
      StorePreviewCache.downloaderForTest = null;
      StorePreviewCache.overrideDirForTest = null;
      StorePreviewCache.resetForTest();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('valid image bytes are stored and served', () async {
      final ok =
          await StorePreviewCache.instance.storeBytes('p1', jpegBytes);
      expect(ok, isTrue);
      expect(StorePreviewCache.instance.cachedFileFor('p1'), isNotNull);
    });

    test('non-image bytes are rejected, cache stays empty', () async {
      final ok = await StorePreviewCache.instance
          .storeBytes('p2', 'not an image at all'.codeUnits);
      expect(ok, isFalse);
      expect(StorePreviewCache.instance.cachedFileFor('p2'), isNull);
    });

    test('warm downloads via the seam and caches the preview',
        () async {
      StorePreviewCache.downloaderForTest = (_) async => jpegBytes;
      await StorePreviewCache.instance.warm('p3');
      expect(StorePreviewCache.instance.cachedFileFor('p3'), isNotNull);
    });

    test('warm with a failing download stays empty (icon fallback)',
        () async {
      StorePreviewCache.downloaderForTest = (_) async => null;
      await StorePreviewCache.instance.warm('p4');
      expect(StorePreviewCache.instance.cachedFileFor('p4'), isNull);
    });
  });

  group('Point #3 — store card (widget)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tj_b8_card_');
      StorePreviewCache.overrideDirForTest = tempDir;
      StorePreviewCache.resetForTest();
      final jpegBytes =
          await File('assets/hero_nigraan_banner.jpg').readAsBytes();
      StorePreviewCache.downloaderForTest = (_) async => jpegBytes;
    });

    tearDown(() async {
      StorePreviewCache.downloaderForTest = null;
      StorePreviewCache.overrideDirForTest = null;
      StorePreviewCache.resetForTest();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('card shows the preview image and the cleaned name',
        (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      const seedItem = StoreItem(
        id: 'anim1',
        name: 'Animation - Rotating Globe (Square).mp4',
        category: 'Animations',
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tjpro_store_listing_v1_Animations':
            jsonEncode([seedItem.toJson()]),
        'tjpro_store_previews_v1_Animations': jsonEncode(
          {'animation - rotating globe (square)': 'prev1'},
        ),
      });

      await tester.pumpWidget(
        const MaterialApp(home: StoreScreen()),
      );
      await tester.pump();
      // The preview chain (listing cache -> preview download ->
      // disk cache -> card swap) is real async work; poll for
      // the image because this machine's speed varies.
      for (var attempt = 0;
          attempt < 12 && find.byType(Image).evaluate().isEmpty;
          attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)),
        );
        await tester.pump();
      }

      // Cleaned name (no "(Square)"), preview image painted,
      // price from the raw name's category (Animations = 10).
      expect(find.text('Animation - Rotating Globe'), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
      expect(find.text('10'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Flush pending background timers before teardown (the
      // store entry gate's Unity init carries a 10 s timeout).
      await tester.pump(const Duration(seconds: 12));
      await tester.pump();
    });
  });
}
