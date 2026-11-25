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
    // Build 7 (v1.5.9) repair: this test asserted the ORIGINAL
    // Phase 3 geometry (frame-top ticker strip, English ribbon
    // at half the ticker thickness, logo under the ticker). The
    // user-declared FINAL design (demo v4, 22 Nov 2026) replaced
    // that geometry wholesale: no frame-top ticker, a 3-ribbon
    // bottom stack at 31:43:28 of frame width, and the capsule
    // ON the middle (red) ribbon with the logo above it. The
    // assertions below pin the CURRENT final geometry.
    test('all ribbons on: Final-3 bottom stack, capsule on red ribbon',
        () {
      final layout = NigraanFinalLayout.compute(
        preset: ChannelPreset.nigraanTv(),
        width: 720,
        height: 1280,
      );
      expect(layout.isFinal3, isTrue);
      // No frame-top ticker strip in the Final design.
      expect(layout.tickerStrip, isNull);
      // The bottom stack: English at the very bottom, Urdu flush
      // on it, the top (current-story) ribbon flush on that —
      // heights 28 / 43 / 31 at this width (31:43:28 of W=720,
      // i.e. W*31/720 etc. — see ParityGeometry).
      expect(layout.englishStrip, isNotNull);
      expect(layout.englishStrip!.bottom, 1280);
      expect(layout.englishStrip!.height, 28);
      expect(layout.englishHeight, layout.englishStrip!.height);
      expect(layout.urduStrip, isNotNull);
      expect(layout.urduStrip!.bottom, layout.englishStrip!.top);
      expect(layout.urduStrip!.height, 43);
      expect(layout.topStackStrip, isNotNull);
      expect(layout.topStackStrip!.bottom, layout.urduStrip!.top);
      expect(layout.topStackStrip!.height, 31);
      // Logo block at the right edge; the capsule has the same
      // width and sits directly UNDER the logo, ON the middle
      // (red) ribbon — its bottom edge inside the Urdu strip.
      expect(layout.logoRect.right, 720);
      expect(layout.capsuleRect.right, 720);
      expect(layout.capsuleRect.width, layout.logoRect.width);
      expect(layout.capsuleRect.left, layout.logoRect.left);
      expect(layout.logoRect.bottom, layout.capsuleRect.top);
      expect(layout.capsuleRect.bottom,
          lessThanOrEqualTo(layout.urduStrip!.bottom));
      expect(layout.capsuleRect.bottom,
          greaterThan(layout.urduStrip!.top));
      // Intro marker present when showIntro is on (default true),
      // top-left (no frame-top ticker to sit below in final3).
      expect(layout.introMarker, isNotNull);
      expect(layout.introMarker!.left, 16);
      expect(layout.introMarker!.top, 16);
    });

    // Build 7 repair: the chip TEXTS are unchanged, but final3
    // draws NO chips at all (the ribbons are full-width bars) —
    // chips live on in the classic2 variant, asserted below with
    // the placement this test originally pinned.
    test('chips: ticker red label, Urdu black label, English label', () {
      expect(NigraanFinalLayout.tickerChipText, 'تازہ ترین');
      expect(NigraanFinalLayout.urduChipText, 'بریکنگ نیوز');
      expect(NigraanFinalLayout.englishChipText, 'HEADLINES');
      final layout = NigraanFinalLayout.compute(
        preset: ChannelPreset.nigraanTv(),
        width: 720,
        height: 1280,
      );
      // final3 (the default design): no chips anywhere.
      expect(layout.tickerChip, isNull);
      expect(layout.urduChip, isNull);
      expect(layout.englishChip, isNull);
      // classic2: the chips exist, in their original spots.
      final classic = NigraanFinalLayout.compute(
        preset: ChannelPreset.nigraanTv()
          ..finalVariant = kFinalVariantClassic2,
        width: 720,
        height: 1280,
      );
      expect(classic.tickerChip, isNotNull);
      expect(classic.tickerChip!.top, 0);
      expect(classic.tickerChip!.left, 0);
      expect(classic.urduChip, isNotNull);
      expect(classic.urduChip!.right, 720);
      expect(classic.englishChip, isNotNull);
      expect(classic.englishChip!.bottom, 1280);
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

    // Build 7 repair: in the Final design the logo + capsule do
    // NOT reflow to the top with the ribbons off — they are
    // anchored to the full-stack parity geometry (the export
    // renders the same stack), so they stay exactly where the
    // all-on layout puts them. (The old test pinned the pre-Final
    // reflow-to-top behaviour.)
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
      expect(layout.topStackStrip, isNull);
      expect(layout.urduStrip, isNull);
      expect(layout.englishStrip, isNull);
      expect(layout.lowerThird, isNull);
      // Logo + capsule still placed — at the SAME anchor as the
      // all-ribbons-on layout (full-stack geometry).
      final allOn = NigraanFinalLayout.compute(
        preset: ChannelPreset.nigraanTv(),
        width: 720,
        height: 1280,
      );
      expect(layout.logoRect, allOn.logoRect);
      expect(layout.capsuleRect, allOn.capsuleRect);
      expect(layout.capsuleRect.top, layout.logoRect.bottom);
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

  // Build 12 (v1.9.0, point #12) — UPDATED IN PLACE: this
  // group used to pin the 20 Nov 2026 ±0.7 rad yoyo SWING
  // (logoSwingAngle / logoSwingNeverMirrors). The user's
  // direct order of 2026-11-25 SUPERSEDES that decision: the
  // logo now rotates CONTINUOUSLY through full 360° rounds as
  // a 3D cube, so the group pins the new full-rotation sweep
  // instead. (Reason recorded per the Build 12 brief: stale
  // assertions are updated in place, never deleted.)
  group('RotatingLogo full rotation (Build 12)', () {
    test('angle sweeps 0 → 2π linearly over one revolution', () {
      expect(logoRotationAngle(0), 0);
      expect(logoRotationAngle(0.5), closeTo(3.14159265, 1e-6));
      expect(logoRotationAngle(1), closeTo(2 * 3.14159265, 1e-6));
    });

    test('the sweep passes the old swing limit — full turn', () {
      // Half-way through the revolution the cube has turned
      // 180°: exactly what the superseded swing forbade.
      expect(logoRotationAngle(0.5), greaterThan(3.14159265 / 2));
      expect(logoRotationAngle(0.75), closeTo(1.5 * 3.14159265, 1e-6));
    });
  });

  // Build 5 (v1.5.7): the TemplateStudioScreen widget group was
  // removed with the screen itself (approved removal — the screen
  // is retired; its controls live in the News Maker's Template +
  // Ribbons panels, covered by test/build5_regressions_test.dart
  // and test/panel_overflow_test.dart).
}
