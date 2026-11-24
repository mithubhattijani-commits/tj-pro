// Phase 6 unit tests: breaking templates render for real (PNG +
// geometry), Classic template, Templates Library model (categories,
// save-as-custom store), graphics package fields (category label,
// interview plate, PIP), ribbon-content rule enforcement, and the
// per-project template choice (NewsProject.breakingVariant).
//
// Plain unit tests in real async (no widget pumps): persistence is
// covered here with a mocked path_provider channel, like Phase 3/4.
// No proxy calls, no ffmpeg, no model downloads.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/live/news_template.dart';
import 'package:tj_pro/news/breaking_templates.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/news_project.dart';

void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return '/tmp/tj_pro_phase6_test';
      }
      return null;
    },
  );
}

bool _isPng(List<int> bytes) =>
    bytes.length > 4 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4E &&
    bytes[3] == 0x47;

/// Renders [templateKind] to a temp dir and returns the PNG file.
Future<File> _render({
  String templateKind = 'breaking',
  BreakingTemplate? breakingTemplate,
  ChannelPreset? preset,
  double tickerPx = 0,
  bool tickerAtStart = false,
}) async {
  final dir = await Directory.systemTemp.createTemp('tj_pro_phase6_');
  return renderLiveTemplateImage(
    template: NewsTemplate(),
    tickerPx: tickerPx,
    now: DateTime(2026, 11, 21, 12, 0),
    dir: dir,
    templateKind: templateKind,
    preset: preset,
    breakingTemplate: breakingTemplate,
    tickerAtStart: tickerAtStart,
  );
}

/// Decodes [file] and asserts it is a 720x1280 PNG.
Future<void> _expect720x1280Png(File file) async {
  expect(await file.exists(), isTrue);
  final bytes = await file.readAsBytes();
  expect(_isPng(bytes), isTrue);
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  expect(frame.image.width, 720);
  expect(frame.image.height, 1280);
  frame.image.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    _mockPathProvider();
    Directory('/tmp/tj_pro_phase6_test').createSync(recursive: true);
  });

  group('BreakingTemplate — Phase 6 fields + defaults', () {
    test('four defaults keep their variants, costs and combo colours', () {
      final defaults = BreakingTemplate.defaults();
      expect(defaults, hasLength(4));
      expect(defaults[0].variant, BreakingVariant.breakingRedBanner);
      expect(defaults[0].coinCost, 0);
      expect(defaults[3].variant, BreakingVariant.breakingTickerCombo);
      expect(defaults[3].coinCost, 25);
      // Combo colours are pinned by the Phase 2 tests too.
      expect(defaults[3].topColor, 0xFFD50000);
      expect(defaults[3].middleColor, 0xFF3D5AFE);
      expect(defaults[3].bottomColor, 0xFFEF0017);
    });

    test('ticker strip colours are the design constants', () {
      final defaults = BreakingTemplate.defaults();
      // Breaking Red Banner: black scrolling ticker bottom (§7).
      expect(defaults[0].bottomColor, 0xFF000000);
      // Latest News: white ticker strip (§7).
      expect(defaults[1].bottomColor, 0xFFFFFFFF);
      // Top Headline Bar: blue ticker strip (§7).
      expect(defaults[2].bottomColor, 0xFF01B0FF);
      // Combo: top ticker strip is house ticker blue.
      expect(defaults[3].tickerColor, 0xFF01B0FF);
    });

    test('new fields default empty/off', () {
      final t = BreakingTemplate.defaults()[0];
      expect(t.middleText, '');
      expect(t.bottomText, '');
      expect(t.categoryLabel, '');
      expect(t.interviewName, '');
      expect(t.interviewDesignation, '');
      expect(t.showInterviewPlate, isFalse);
      expect(t.pipEnabled, isFalse);
      expect(t.pipPosition, 'bottomRight');
      expect(t.pipScale, 0.3);
    });

    test('JSON round-trip preserves every Phase 6 field', () {
      final template = BreakingTemplate(
        variant: BreakingVariant.breakingTickerCombo,
        headline: 'Test headline',
        tickerText: 'Ticker',
        middleText: 'قومی خبر',
        bottomText: 'World news',
        categoryLabel: 'PAKISTAN',
        tickerColor: 0xFF00C853,
        interviewName: 'Ahmed Raza',
        interviewDesignation: 'Anchor',
        showInterviewPlate: true,
        pipEnabled: true,
        pipPosition: 'topLeft',
        pipScale: 0.4,
      );
      final restored = BreakingTemplate.fromJson(template.toJson());
      expect(restored.middleText, 'قومی خبر');
      expect(restored.bottomText, 'World news');
      expect(restored.categoryLabel, 'PAKISTAN');
      expect(restored.tickerColor, 0xFF00C853);
      expect(restored.interviewName, 'Ahmed Raza');
      expect(restored.interviewDesignation, 'Anchor');
      expect(restored.showInterviewPlate, isTrue);
      expect(restored.pipEnabled, isTrue);
      expect(restored.pipPosition, 'topLeft');
      expect(restored.pipScale, 0.4);
    });

    test('old saved JSON without Phase 6 fields still loads', () {
      final json = BreakingTemplate(
        variant: BreakingVariant.latestNews,
        headline: 'Old',
      ).toJson()
        ..remove('middleText')
        ..remove('bottomText')
        ..remove('categoryLabel')
        ..remove('tickerColor')
        ..remove('interviewName')
        ..remove('interviewDesignation')
        ..remove('showInterviewPlate')
        ..remove('pipEnabled')
        ..remove('pipPosition')
        ..remove('pipScale');
      final restored = BreakingTemplate.fromJson(json);
      expect(restored.middleText, '');
      expect(restored.categoryLabel, '');
      expect(restored.tickerColor, 0xFF01B0FF);
      expect(restored.showInterviewPlate, isFalse);
      expect(restored.pipEnabled, isFalse);
    });

    test('categories: every variant is Breaking News', () {
      for (final v in BreakingVariant.values) {
        expect(BreakingTemplate.categoriesFor(v), contains('breaking'));
      }
      expect(
        BreakingTemplate.categoriesFor(BreakingVariant.breakingTickerCombo),
        contains('bulletins'),
      );
      expect(
        BreakingTemplate.categoriesFor(BreakingVariant.breakingRedBanner),
        contains('crime'),
      );
    });
  });

  group('BreakingTemplate — preset / project bridge', () {
    test('fromPreset reads variant, colours, texts and kinds', () {
      final preset = ChannelPreset.nigraanTv()
        ..breakingVariant = 'latestNews'
        ..topRibbon.text = 'Current ticker'
        ..urduRibbon.text = 'قومی خبر'
        ..englishRibbon.text = 'World news'
        ..categoryLabel = 'SPORTS'
        ..lowerThirdTitle = 'Reporter'
        ..lowerThirdSubtitle = 'Lahore';
      final t = BreakingTemplate.fromPreset(preset);
      expect(t.variant, BreakingVariant.latestNews);
      expect(t.tickerText, 'Current ticker');
      expect(t.middleText, 'قومی خبر');
      expect(t.bottomText, 'World news');
      expect(t.categoryLabel, 'SPORTS');
      expect(t.lowerThirdTitle, 'Reporter');
      expect(t.topContentKind, RibbonContentKind.current);
      expect(t.middleContentKind, RibbonContentKind.national);
      expect(t.bottomContentKind, RibbonContentKind.international);
    });

    test('applyToPreset never reassigns ribbon content kinds', () {
      final preset = ChannelPreset.nigraanTv();
      final template = BreakingTemplate(
        variant: BreakingVariant.breakingTickerCombo,
        // A hostile template: kinds all 'current'.
        topContentKind: RibbonContentKind.current,
        middleContentKind: RibbonContentKind.current,
        bottomContentKind: RibbonContentKind.current,
        tickerText: 'Ticker',
        middleText: 'Middle',
        bottomText: 'Bottom',
      );
      template.applyToPreset(preset);
      // Colours + texts apply; kinds stay read-only.
      expect(preset.templateKind, 'breaking');
      expect(preset.breakingVariant, 'breakingTickerCombo');
      expect(preset.topRibbon.text, 'Ticker');
      expect(preset.urduRibbon.text, 'Middle');
      expect(preset.englishRibbon.text, 'Bottom');
      expect(preset.topRibbon.contentKind, RibbonContentKind.current);
      expect(preset.urduRibbon.contentKind, RibbonContentKind.national);
      expect(
        preset.englishRibbon.contentKind,
        RibbonContentKind.international,
      );
    });

    test('fromProject carries the project variant + headline + ticker', () {
      final project = NewsProject.create()
        ..templateKind = 'breaking'
        ..breakingVariant = 'topHeadlineBar'
        ..headline = 'Sheikhupura big news'
        ..tickerText = 'Ticker text';
      final t = BreakingTemplate.fromProject(
        project,
        ChannelPreset.nigraanTv(),
      );
      expect(t.variant, BreakingVariant.topHeadlineBar);
      expect(t.headline, 'Sheikhupura big news');
      expect(t.tickerText, 'Ticker text');
    });

    test('fromProject ticker override wins over the stored ticker', () {
      final project = NewsProject.create()
        ..breakingVariant = 'breakingRedBanner'
        ..tickerText = 'Stored ticker';
      final t = BreakingTemplate.fromProject(
        project,
        ChannelPreset.nigraanTv(),
        tickerText: 'Live field ticker',
      );
      expect(t.tickerText, 'Live field ticker');
    });

    test('applyToProject sets kind + variant + headline + ticker', () {
      final project = NewsProject.create();
      final template = BreakingTemplate(
        variant: BreakingVariant.latestNews,
        headline: 'H',
        tickerText: 'T',
      );
      template.applyToProject(project);
      expect(project.templateKind, 'breaking');
      expect(project.breakingVariant, 'latestNews');
      expect(project.breaking, isTrue);
      expect(project.headline, 'H');
      expect(project.tickerText, 'T');
    });
  });

  group('BreakingLayout — geometry', () {
    BreakingTemplate template(BreakingVariant v) =>
        BreakingTemplate.defaults().firstWhere((t) => t.variant == v);

    test('breakingRedBanner: banner top, ticker bottom, 24px margins', () {
      final layout = BreakingLayout.compute(
        template: template(BreakingVariant.breakingRedBanner),
        width: 720,
        height: 1280,
      );
      expect(layout.bannerRect.top, 0);
      expect(layout.bannerRect.height, closeTo(1280 * 0.10, 0.001));
      expect(layout.bannerChipRect, isNotNull);
      expect(layout.bannerChipRect!.left, 24);
      expect(layout.headlineRect.left,
          greaterThan(layout.bannerChipRect!.right));
      expect(layout.tickerStrip, isNotNull);
      expect(layout.tickerStrip!.bottom, 1280);
      expect(layout.tickerStrip!.height, closeTo(1280 * 0.055, 0.001));
      // No combo ribbons on this variant.
      expect(layout.topTickerStrip, isNull);
      expect(layout.middleStrip, isNull);
      expect(layout.bottomStrip, isNull);
      // Logo top-right below the banner, 24px from the right edge;
      // capsule under it, same width.
      expect(layout.logoRect.left + layout.logoRect.width, 720 - 24);
      expect(layout.logoRect.top, layout.bannerHeight + 16);
      expect(layout.capsuleRect.top, layout.logoRect.bottom + 6);
      expect(layout.capsuleRect.width, layout.logoRect.width);
      // Markers present (intro + outro both on by default).
      expect(layout.introMarker, isNotNull);
      expect(layout.outroMarker, isNotNull);
      expect(layout.outroMarker!.left, greaterThan(layout.introMarker!.right));
      // Category chip + interview plate off by default.
      expect(layout.categoryChip, isNull);
      expect(layout.interviewPlate, isNull);
    });

    test('latestNews: no red, blue bar + white ticker', () {
      final layout = BreakingLayout.compute(
        template: template(BreakingVariant.latestNews),
        width: 720,
        height: 1280,
      );
      expect(layout.bannerHeight, closeTo(1280 * 0.08, 0.001));
      expect(layout.bannerChipRect, isNotNull);
      expect(layout.tickerStrip, isNotNull);
      expect(layout.tickerStrip!.bottom, 1280);
    });

    test('topHeadlineBar: no banner chip, headline spans the bar', () {
      final layout = BreakingLayout.compute(
        template: template(BreakingVariant.topHeadlineBar),
        width: 720,
        height: 1280,
      );
      expect(layout.bannerChipRect, isNull);
      expect(layout.headlineRect.left, 24);
      expect(layout.headlineRect.width, 720 - 48);
      expect(layout.tickerStrip, isNotNull);
    });

    test('combo: banner + top ticker + Urdu + English half-thickness',
        () {
      final layout = BreakingLayout.compute(
        template: template(BreakingVariant.breakingTickerCombo),
        width: 720,
        height: 1280,
      );
      expect(layout.bannerHeight, closeTo(1280 * 0.062, 0.001));
      expect(layout.topTickerStrip, isNotNull);
      expect(layout.topTickerStrip!.top,
          closeTo(layout.bannerHeight, 0.001));
      expect(layout.topTickerChip, isNotNull);
      expect(layout.middleStrip, isNotNull);
      expect(layout.bottomStrip, isNotNull);
      expect(layout.bottomStrip!.bottom, 1280);
      // Bottom English ribbon is exactly half the ticker thickness
      // (Rect stores edges, so compare with a tolerance).
      expect(layout.englishHeight, layout.tickerHeight / 2);
      expect(layout.bottomStrip!.height,
          closeTo(layout.englishHeight, 0.001));
      expect(layout.middleStrip!.bottom,
          lessThan(layout.bottomStrip!.top));
      // No single-variant ticker strip on the combo.
      expect(layout.tickerStrip, isNull);
      // Logo sits below the top ticker strip, not below the banner.
      expect(layout.logoRect.top,
          layout.bannerHeight + layout.tickerHeight + 16);
    });

    test('disabled ribbons leave no gap (combo, middle off)', () {
      final t = template(BreakingVariant.breakingTickerCombo)
        ..showMiddle = false
        ..lowerThirdTitle = 'Reporter'
        ..lowerThirdSubtitle = 'Lahore';
      final layout = BreakingLayout.compute(
        template: t,
        width: 720,
        height: 1280,
      );
      expect(layout.middleStrip, isNull);
      expect(layout.lowerThird, isNotNull);
      expect(layout.lowerThird!.bottom,
          layout.bottomStrip!.top - 1280 * 0.008);
    });

    test('category chip appears only with a label, intro shifts down',
        () {
      final plain = BreakingLayout.compute(
        template: template(BreakingVariant.breakingRedBanner),
        width: 720,
        height: 1280,
      );
      final labelled = BreakingLayout.compute(
        template: template(BreakingVariant.breakingRedBanner)
          ..categoryLabel = 'PAKISTAN',
        width: 720,
        height: 1280,
      );
      expect(plain.categoryChip, isNull);
      expect(labelled.categoryChip, isNotNull);
      expect(labelled.categoryChip!.left, 24);
      expect(
        labelled.introMarker!.top,
        plain.introMarker!.top +
            labelled.categoryChip!.height +
            8,
      );
    });

    test('interview plate stacks above the lower third', () {
      final t = template(BreakingVariant.breakingRedBanner)
        ..showInterviewPlate = true
        ..interviewName = 'Ahmed Raza'
        ..interviewDesignation = 'Anchor'
        ..lowerThirdTitle = 'Reporter';
      final layout = BreakingLayout.compute(
        template: t,
        width: 720,
        height: 1280,
      );
      expect(layout.interviewPlate, isNotNull);
      expect(layout.interviewPlate!.bottom,
          layout.lowerThird!.top - 1280 * 0.008);
      expect(layout.interviewPlate!.width, 720 * 0.68);
    });

    test('font clamp: ribbon fonts stay ~0.52x the strip height', () {
      // fontSize 20 on a 70.4px strip clamps to the 0.30 floor.
      final layout = BreakingLayout.compute(
        template: template(BreakingVariant.breakingRedBanner),
        width: 720,
        height: 1280,
      );
      expect(layout.tickerTextSize, closeTo(1280 * 0.055 * 0.30, 0.001));
      expect(
        BreakingLayout.clampFontSize(100, 70.4),
        70.4 * 0.62,
      );
    });

    test('chip labels are the broadcast constants', () {
      expect(BreakingLayout.breakingChipText, 'BREAKING NEWS');
      expect(BreakingLayout.latestChipText, 'LATEST NEWS');
    });
  });

  group('ClassicLayout — geometry', () {
    test('top bar, LIVE chip, ticker bottom, logo below the bar', () {
      final layout = ClassicLayout.compute(
        preset: ChannelPreset.nigraanTv(),
        width: 720,
        height: 1280,
      );
      expect(layout.topBarRect.top, 0);
      expect(layout.topBarRect.height, 1280 * 0.07);
      expect(layout.liveChipRect.right, 720 - 24);
      expect(layout.channelNameRect.left, 24);
      expect(
        layout.channelNameRect.right,
        lessThanOrEqualTo(layout.liveChipRect.left),
      );
      expect(layout.tickerStrip, isNotNull);
      expect(layout.tickerStrip!.bottom, 1280);
      expect(layout.logoRect.top, layout.topBarHeight + 16);
      expect(layout.logoRect.left + layout.logoRect.width, 720 - 24);
      expect(layout.capsuleRect.width, layout.logoRect.width);
      expect(layout.categoryChip, isNull);
      expect(layout.interviewPlate, isNull);
    });

    test('ticker off hides the strip, lower third reflows to the bottom',
        () {
      final preset = ChannelPreset.nigraanTv()
        ..topRibbon.enabled = false
        ..lowerThirdTitle = 'Reporter';
      final layout = ClassicLayout.compute(
        preset: preset,
        width: 720,
        height: 1280,
      );
      expect(layout.tickerStrip, isNull);
      expect(layout.lowerThird, isNotNull);
      expect(layout.lowerThird!.bottom, 1280);
    });
  });

  group('NigraanFinalLayout — Phase 6 additions', () {
    test('category chip + outro marker off by default', () {
      final layout = NigraanFinalLayout.compute(
        preset: ChannelPreset.nigraanTv(),
        width: 720,
        height: 1280,
      );
      expect(layout.categoryChip, isNull);
      expect(layout.interviewPlate, isNull);
      // Build 7 (v1.5.9) repair: the old assertion ("outro is on
      // by default") predates the FINAL template ruling — the
      // reference has NO outro, so the built-in preset ships
      // showOutro = false and there is no marker by default.
      expect(layout.outroMarker, isNull);
      expect(layout.introMarker, isNotNull);
      // Switched ON, the outro marker sits right of the intro.
      final withOutro = NigraanFinalLayout.compute(
        preset: ChannelPreset.nigraanTv()..showOutro = true,
        width: 720,
        height: 1280,
      );
      expect(withOutro.outroMarker, isNotNull);
      expect(
        withOutro.outroMarker!.left,
        withOutro.introMarker!.right + 8,
      );
    });

    test('category label adds a chip, intro marker shifts down', () {
      final plain = NigraanFinalLayout.compute(
        preset: ChannelPreset.nigraanTv(),
        width: 720,
        height: 1280,
      );
      final labelled = NigraanFinalLayout.compute(
        preset: ChannelPreset.nigraanTv()..categoryLabel = 'SPORTS',
        width: 720,
        height: 1280,
      );
      expect(labelled.categoryChip, isNotNull);
      expect(labelled.categoryChip!.left, 16);
      expect(
        labelled.introMarker!.top,
        plain.introMarker!.top + labelled.categoryChip!.height + 8,
      );
      // Existing geometry is untouched by the new chip.
      expect(labelled.logoRect, plain.logoRect);
      expect(labelled.tickerStrip, plain.tickerStrip);
    });

    test('interview plate stacks above the lower third', () {
      final preset = ChannelPreset.nigraanTv()
        ..showInterviewPlate = true
        ..interviewName = 'Ahmed Raza'
        ..lowerThirdTitle = 'Reporter';
      final layout = NigraanFinalLayout.compute(
        preset: preset,
        width: 720,
        height: 1280,
      );
      expect(layout.interviewPlate, isNotNull);
      expect(layout.interviewPlate!.bottom,
          layout.lowerThird!.top - 1280 * 0.008);
    });
  });

  group('Breaking + Classic PNG renders', () {
    test('each breaking variant renders a 720x1280 PNG', () async {
      for (final t in BreakingTemplate.defaults()) {
        final file = await _render(breakingTemplate: t);
        expect(file.path.endsWith('breaking_template.png'), isTrue);
        await _expect720x1280Png(file);
      }
    });

    test('breaking render honours tickerAtStart + scrolling offset',
        () async {
      final t = BreakingTemplate.defaults()[0]
        ..headline = 'Big story'
        ..tickerText = 'Ticker text here';
      final still = await _render(
        breakingTemplate: t,
        tickerAtStart: true,
      );
      await _expect720x1280Png(still);
      final scrolled = await _render(
        breakingTemplate: t,
        tickerPx: 200,
      );
      await _expect720x1280Png(scrolled);
      // Different offsets produce different frames.
      expect(
        await still.readAsBytes(),
        isNot(await scrolled.readAsBytes()),
      );
    });

    test('combo renders with middle/bottom texts + interview plate',
        () async {
      final t = BreakingTemplate.defaults()[3]
        ..headline = 'Breaking story'
        ..tickerText = 'Current ticker'
        ..middleText = 'قومی خبر'
        ..bottomText = 'World news'
        ..categoryLabel = 'PAKISTAN'
        ..lowerThirdTitle = 'Reporter'
        ..lowerThirdSubtitle = 'Lahore'
        ..showInterviewPlate = true
        ..interviewName = 'Ahmed Raza'
        ..interviewDesignation = 'Anchor';
      final file = await _render(breakingTemplate: t, tickerAtStart: true);
      await _expect720x1280Png(file);
    });

    test('classic renders a 720x1280 PNG (own output file)', () async {
      final file = await _render(
        templateKind: 'classic',
        preset: ChannelPreset.nigraanTv()
          ..topRibbon.text = 'Ticker text'
          ..lowerThirdTitle = 'Reporter'
          ..categoryLabel = 'PAKISTAN',
        tickerAtStart: true,
      );
      expect(file.path.endsWith('classic_template.png'), isTrue);
      await _expect720x1280Png(file);
    });

    test('live + final branches are untouched (own output files)',
        () async {
      final live = await _render(templateKind: 'live');
      expect(live.path.endsWith('live_template.png'), isTrue);
      await _expect720x1280Png(live);
      final finalFile = await _render(templateKind: 'nigraanFinal');
      expect(finalFile.path.endsWith('nigraan_final_template.png'), isTrue);
      await _expect720x1280Png(finalFile);
    });
  });

  group('ChannelPreset + NewsProject — Phase 6 fields', () {
    test('preset JSON round-trip preserves Phase 6 fields', () {
      final preset = ChannelPreset.nigraanTv()
        ..breakingVariant = 'breakingTickerCombo'
        ..breakingTickerColor = 0xFF00C853
        ..categoryLabel = 'SPORTS'
        ..interviewName = 'Ahmed Raza'
        ..interviewDesignation = 'Anchor'
        ..showInterviewPlate = true
        ..pipEnabled = true
        ..pipPosition = 'topLeft'
        ..pipScale = 0.4;
      final restored = ChannelPreset.fromJson(preset.toJson());
      expect(restored.breakingVariant, 'breakingTickerCombo');
      expect(restored.breakingTickerColor, 0xFF00C853);
      expect(restored.categoryLabel, 'SPORTS');
      expect(restored.interviewName, 'Ahmed Raza');
      expect(restored.interviewDesignation, 'Anchor');
      expect(restored.showInterviewPlate, isTrue);
      expect(restored.pipEnabled, isTrue);
      expect(restored.pipPosition, 'topLeft');
      expect(restored.pipScale, 0.4);
    });

    test('old preset JSON without Phase 6 fields loads with defaults',
        () {
      final json = ChannelPreset.nigraanTv().toJson()
        ..remove('breakingVariant')
        ..remove('breakingTickerColor')
        ..remove('categoryLabel')
        ..remove('interviewName')
        ..remove('interviewDesignation')
        ..remove('showInterviewPlate')
        ..remove('pipEnabled')
        ..remove('pipPosition')
        ..remove('pipScale');
      final restored = ChannelPreset.fromJson(json);
      expect(restored.breakingVariant, 'breakingRedBanner');
      expect(restored.breakingTickerColor, 0xFF01B0FF);
      expect(restored.categoryLabel, '');
      expect(restored.showInterviewPlate, isFalse);
      expect(restored.pipEnabled, isFalse);
      expect(restored.pipPosition, 'bottomRight');
      expect(restored.pipScale, 0.3);
    });

    test('project JSON round-trip preserves breakingVariant', () {
      final project = NewsProject.create()
        ..templateKind = 'breaking'
        ..breakingVariant = 'latestNews';
      final restored = NewsProject.fromJson(project.toJson());
      expect(restored.templateKind, 'breaking');
      expect(restored.breakingVariant, 'latestNews');
    });

    test('old project JSON defaults breakingVariant', () {
      final json = NewsProject.create().toJson()..remove('breakingVariant');
      final restored = NewsProject.fromJson(json);
      expect(restored.breakingVariant, 'breakingRedBanner');
    });
  });

  group('BreakingTemplateStore — save as custom', () {
    test('saveCustom + loadCustom + deleteCustom round-trip', () async {
      // Start clean: delete any leftover customs from earlier runs.
      for (final t in await BreakingTemplateStore.loadCustom()) {
        await BreakingTemplateStore.deleteCustomTemplate(t.id);
      }
      final base = BreakingTemplate.defaults()[1]
        ..headline = 'My headline'
        ..tickerText = 'My ticker'
        ..topColor = 0xFF00C853;
      final saved = await BreakingTemplateStore.saveCustomTemplate(
        name: 'My Green Latest',
        template: base,
      );
      expect(saved.isCustom, isTrue);
      expect(saved.name, 'My Green Latest');
      expect(saved.id.startsWith('custom_'), isTrue);
      expect(saved.headline, 'My headline');
      expect(saved.topColor, 0xFF00C853);
      final customs = await BreakingTemplateStore.loadCustom();
      expect(customs.any((t) => t.id == saved.id), isTrue);
      final all = await BreakingTemplateStore.loadAll();
      expect(all.length, 5);
      await BreakingTemplateStore.deleteCustomTemplate(saved.id);
      expect(
        (await BreakingTemplateStore.loadCustom())
            .any((t) => t.id == saved.id),
        isFalse,
      );
      // Built-ins cannot be deleted.
      await BreakingTemplateStore.deleteCustomTemplate('latestNews');
      expect((await BreakingTemplateStore.loadAll()).length, 4);
    });

    test('saveCustomTemplate with an empty name falls back', () async {
      final saved = await BreakingTemplateStore.saveCustomTemplate(
        name: '   ',
        template: BreakingTemplate.defaults()[0],
      );
      expect(saved.name, 'Custom Template');
      await BreakingTemplateStore.deleteCustomTemplate(saved.id);
    });
  });

  group('ChannelPresetStore — custom template save + delete', () {
    test('saveCustomTemplate + deletePreset round-trip', () async {
      final saved = await ChannelPresetStore.saveCustomTemplate(
        name: 'My Channel Look',
        preset: ChannelPreset.nigraanTv()..categoryLabel = 'SPORTS',
      );
      expect(saved.id.startsWith('custom_'), isTrue);
      expect(saved.categoryLabel, 'SPORTS');
      final presets = await ChannelPresetStore.loadAll();
      expect(presets.any((p) => p.id == saved.id), isTrue);
      await ChannelPresetStore.deletePreset(saved.id);
      expect(
        (await ChannelPresetStore.loadAll())
            .any((p) => p.id == saved.id),
        isFalse,
      );
      // The built-in cannot be deleted.
      await ChannelPresetStore.deletePreset('nigraan-tv');
      expect(
        (await ChannelPresetStore.loadAll())
            .any((p) => p.id == 'nigraan-tv'),
        isTrue,
      );
    });
  });
}
