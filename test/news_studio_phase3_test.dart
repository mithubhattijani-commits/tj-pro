// Phase 3 unit + widget tests: the Nigraan final 3-ribbon template
// renderer (ribbon-toggle reflow, content-kind defaults, ticker text
// handling, includeLogo split), the chroma preset fields, the rotating
// logo swing. (The Template & Studio widget smoke tests left
// with that screen in Build 5 — see the note at the file's end.)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tj_pro/live/news_template.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/widgets/rotating_logo.dart';

bool _isPng(List<int> bytes) =>
    bytes.length > 4 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4E &&
    bytes[3] == 0x47;

Future<File> _renderFinal({
  required ChannelPreset preset,
  bool includeLogo = true,
  bool fontReady = false,
  bool tickerAtStart = false,
  double tickerPx = 0,
}) async {
  final dir = await Directory.systemTemp.createTemp('tj_pro_phase3_');
  return renderLiveTemplateImage(
    template: NewsTemplate(),
    tickerPx: tickerPx,
    now: DateTime(2026, 11, 20, 20, 35),
    dir: dir,
    templateKind: 'nigraanFinal',
    preset: preset,
    tickerAtStart: tickerAtStart,
    includeLogo: includeLogo,
    fontReady: fontReady,
  );
}

void main() {
  group('NigraanFinalLayout — reflow', () {
    test('all ribbons on: ticker top, English half-thickness at bottom',
        () {
      final layout = NigraanFinalLayout.compute(
        preset: ChannelPreset.nigraanTv(),
        width: 720,
        height: 1280,
      );
      expect(layout.tickerStrip, isNotNull);
      expect(layout.tickerStrip!.top, 0);
      expect(layout.tickerStrip!.height, 1280 * 0.055);
      expect(layout.englishStrip, isNotNull);
      expect(layout.englishStrip!.bottom, 1280);
      // Bottom English ribbon is exactly half the ticker thickness.
      expect(layout.englishHeight, layout.tickerHeight / 2);
      expect(layout.urduStrip, isNotNull);
      expect(layout.urduStrip!.bottom,
          lessThan(layout.englishStrip!.top));
      // Logo top-right below the ticker; capsule under it, same width.
      expect(layout.logoRect.left + layout.logoRect.width, 720 - 20);
      expect(layout.logoRect.top, layout.tickerHeight + 16);
      expect(layout.capsuleRect.top, layout.logoRect.bottom + 6);
      expect(layout.capsuleRect.width, layout.logoRect.width);
      expect(layout.capsuleRect.left, layout.logoRect.left);
      // Intro marker present when showIntro is on (default true).
      expect(layout.introMarker, isNotNull);
      expect(layout.introMarker!.left, 16);
    });

    test('chips: ticker red label, Urdu black label, English label', () {
      expect(NigraanFinalLayout.tickerChipText, 'تازہ ترین');
      expect(NigraanFinalLayout.urduChipText, 'بریکنگ نیوز');
      expect(NigraanFinalLayout.englishChipText, 'HEADLINES');
      final layout = NigraanFinalLayout.compute(
        preset: ChannelPreset.nigraanTv(),
        width: 720,
        height: 1280,
      );
      expect(layout.tickerChip, isNotNull);
      expect(layout.urduChip, isNotNull);
      expect(layout.englishChip, isNotNull);
    });

    test('middle ribbon off: Urdu strip gone, lower third reflows', () {
      final preset = ChannelPreset.nigraanTv()
        ..urduRibbon.enabled = false
        ..lowerThirdTitle = 'Rai Ghulam Jilani Bhatti'
        ..lowerThirdSubtitle = 'Sheikhupura';
      final layout = NigraanFinalLayout.compute(
        preset: preset,
        width: 720,
        height: 1280,
      );
      expect(layout.urduStrip, isNull);
      expect(layout.urduChip, isNull);
      expect(layout.englishStrip, isNotNull);
      expect(layout.lowerThird, isNotNull);
      // Lower third now sits above the English ribbon (no gap left
      // where the Urdu ribbon was).
      expect(layout.lowerThird!.bottom,
          lessThanOrEqualTo(layout.englishStrip!.top));
    });

    test('all ribbons off: no strips, logo + capsule still placed', () {
      final preset = ChannelPreset.nigraanTv()
        ..topRibbon.enabled = false
        ..urduRibbon.enabled = false
        ..englishRibbon.enabled = false;
      final layout = NigraanFinalLayout.compute(
        preset: preset,
        width: 720,
        height: 1280,
      );
      expect(layout.tickerStrip, isNull);
      expect(layout.urduStrip, isNull);
      expect(layout.englishStrip, isNull);
      expect(layout.lowerThird, isNull);
      // Logo reflows to the very top when the ticker is gone.
      expect(layout.logoRect.top, 16);
      expect(layout.capsuleRect.top, layout.logoRect.bottom + 6);
    });

    test('breaking banner off hides the Urdu chip, not the ribbon', () {
      final preset = ChannelPreset.nigraanTv()..showBreakingBanner = false;
      final layout = NigraanFinalLayout.compute(
        preset: preset,
        width: 720,
        height: 1280,
      );
      expect(layout.urduStrip, isNotNull);
      expect(layout.urduChip, isNull);
    });

    test('intro off hides the intro marker', () {
      final preset = ChannelPreset.nigraanTv()..showIntro = false;
      final layout = NigraanFinalLayout.compute(
        preset: preset,
        width: 720,
        height: 1280,
      );
      expect(layout.introMarker, isNull);
    });

    test('ribbon font size clamps inside its strip', () {
      expect(
        NigraanFinalLayout.ribbonFontSize(
          RibbonConfig(fontSize: 100),
          70,
        ),
        70 * 0.62,
      );
      expect(
        NigraanFinalLayout.ribbonFontSize(
          RibbonConfig(fontSize: 1),
          70,
        ),
        // 1 is below the 0.30x lower bound, so it clamps UP to 21.
        70 * 0.30,
      );
      expect(
        NigraanFinalLayout.ribbonFontSize(
          RibbonConfig(fontSize: 25),
          70,
        ),
        25,
      );
    });
  });

  group('nigraanFinal renderer', () {
    test('renders a valid PNG to its own file', () async {
      final file = await _renderFinal(preset: ChannelPreset.nigraanTv());
      expect(file.path.endsWith('nigraan_final_template.png'), isTrue);
      final bytes = await file.readAsBytes();
      expect(bytes, isNotEmpty);
      expect(_isPng(bytes), isTrue);
    });

    test('includeLogo split: both paths render without crashing', () async {
      final withLogo = await _renderFinal(
        preset: ChannelPreset.nigraanTv(),
        includeLogo: true,
      );
      expect(_isPng(await withLogo.readAsBytes()), isTrue);
      final withoutLogo = await _renderFinal(
        preset: ChannelPreset.nigraanTv(),
        includeLogo: false,
      );
      expect(_isPng(await withoutLogo.readAsBytes()), isTrue);
    });

    test('bad logo path falls back, never crashes', () async {
      final preset = ChannelPreset.nigraanTv()
        ..logoPath = '/tmp/does-not-exist-logo.png';
      final file = await _renderFinal(preset: preset);
      expect(_isPng(await file.readAsBytes()), isTrue);
    });

    test('ticker text handling: empty, long Urdu, LTR, pinned start',
        () async {
      final empty = ChannelPreset.nigraanTv();
      expect(_isPng(await (await _renderFinal(preset: empty)).readAsBytes()),
          isTrue);

      final long = ChannelPreset.nigraanTv()
        ..topRibbon.text = 'یہ ایک بہت لمبی خبر ہے۔ ' * 20;
      expect(_isPng(await (await _renderFinal(preset: long)).readAsBytes()),
          isTrue);
      expect(
        _isPng(
          await (await _renderFinal(
            preset: long,
            tickerPx: 500,
          )).readAsBytes(),
        ),
        isTrue,
      );

      final ltr = ChannelPreset.nigraanTv()
        ..topRibbon.text = 'Breaking news from Lahore right now'
        ..topRibbon.direction = RibbonDirection.ltr;
      expect(_isPng(await (await _renderFinal(preset: ltr)).readAsBytes()),
          isTrue);

      final pinned = ChannelPreset.nigraanTv()
        ..topRibbon.text = 'تازہ ترین خبر';
      expect(
        _isPng(
          await (await _renderFinal(
            preset: pinned,
            tickerAtStart: true,
          )).readAsBytes(),
        ),
        isTrue,
      );
    });

    test('fontReady true/false both render (fallback, never crash)',
        () async {
      final preset = ChannelPreset.nigraanTv()
        ..topRibbon.text = 'تازہ ترین خبر'
        ..urduRibbon.text = 'قومی خبریں';
      expect(
        _isPng(
          await (await _renderFinal(preset: preset, fontReady: false))
              .readAsBytes(),
        ),
        isTrue,
      );
      expect(
        _isPng(
          await (await _renderFinal(preset: preset, fontReady: true))
              .readAsBytes(),
        ),
        isTrue,
      );
    });

    test('live template branch is untouched (own output file)', () async {
      final dir = await Directory.systemTemp.createTemp('tj_pro_phase3_');
      final file = await renderLiveTemplateImage(
        template: NewsTemplate()
          ..breakingHeadline = 'Test'
          ..tickerText = 'Ticker',
        tickerPx: 0,
        now: DateTime(2026, 11, 20, 20, 35),
        dir: dir,
      );
      expect(file.path.endsWith('live_template.png'), isTrue);
      expect(_isPng(await file.readAsBytes()), isTrue);
    });
  });

  group('ChannelPreset — chroma fields', () {
    test('chroma defaults: off, Newsroom, 0.35', () {
      final preset = ChannelPreset.nigraanTv();
      expect(preset.chromaEnabled, isFalse);
      expect(preset.chromaBackground, ChromaBackgroundKind.newsroom);
      expect(preset.chromaBackgroundPath, isNull);
      expect(preset.chromaSensitivity, 0.35);
    });

    test('chroma JSON round-trip preserves every field', () {
      final preset = ChannelPreset.nigraanTv()
        ..chromaEnabled = true
        ..chromaBackground = ChromaBackgroundKind.gallery
        ..chromaBackgroundPath = '/tmp/bg.jpg'
        ..chromaSensitivity = 0.6;
      final restored = ChannelPreset.fromJson(preset.toJson());
      expect(restored.chromaEnabled, isTrue);
      expect(restored.chromaBackground, ChromaBackgroundKind.gallery);
      expect(restored.chromaBackgroundPath, '/tmp/bg.jpg');
      expect(restored.chromaSensitivity, 0.6);
    });

    test('ChromaBackgroundKind.fromId falls back to Newsroom', () {
      expect(ChromaBackgroundKind.fromId('studioDesk'),
          ChromaBackgroundKind.studioDesk);
      expect(ChromaBackgroundKind.fromId('nope'),
          ChromaBackgroundKind.newsroom);
      expect(ChromaBackgroundKind.fromId(null),
          ChromaBackgroundKind.newsroom);
      expect(ChromaBackgroundKind.newsroom.assetPath,
          'assets/backgrounds/newsroom.jpg');
      expect(ChromaBackgroundKind.gallery.assetPath, isNull);
    });

    test('old saved JSON without chroma fields still loads', () {
      final json = ChannelPreset.nigraanTv().toJson()
        ..remove('chromaEnabled')
        ..remove('chromaBackground')
        ..remove('chromaBackgroundPath')
        ..remove('chromaSensitivity');
      final restored = ChannelPreset.fromJson(json);
      expect(restored.chromaEnabled, isFalse);
      expect(restored.chromaBackground, ChromaBackgroundKind.newsroom);
      expect(restored.chromaSensitivity, 0.35);
    });
  });

  group('RotatingLogo swing', () {
    test('yoyo angle: -0.7 at start, 0 at middle, +0.7 at the turn', () {
      expect(logoSwingAngle(0), -0.7);
      expect(logoSwingAngle(0.5), 0);
      expect(logoSwingAngle(1), 0.7);
    });

    test('swing never reaches the mirror point', () {
      expect(logoSwingNeverMirrors, isTrue);
      expect(logoSwingMaxRadians, lessThan(3.14159265 / 2));
    });
  });

  // Build 5 (v1.5.7): the TemplateStudioScreen widget group was
  // removed with the screen itself (approved removal — the screen
  // is retired; its controls live in the News Maker's Template +
  // Ribbons panels, covered by test/build5_regressions_test.dart
  // and test/panel_overflow_test.dart).
}
