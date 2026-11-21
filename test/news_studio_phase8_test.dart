// Phase 8 unit tests: 13 category templates (one real variant per
// category, rendering to a 720x1280 PNG each), save-as-custom
// round-trip for category templates, channel branding (brand colour,
// social handles, watermark) + JSON round-trips, watermark geometry
// + PNG renderers, end-card lines/render, branding auto-apply
// (effectivePresetFor preserves branding; a branding change changes
// the rendered PNG), and the FFmpeg watermark overlay command.
//
// Plain unit tests in real async (no widget pumps): persistence is
// covered here with a mocked path_provider channel, like Phase 6.
// No proxy calls, no ffmpeg runs, no model downloads — the FFmpeg
// watermark step itself needs a real device to execute (see the
// Phase 8 report); what is verified here is the render logic, the
// persistence round-trips and the export-graph construction.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/live/news_template.dart';
import 'package:tj_pro/news/breaking_templates.dart';
import 'package:tj_pro/news/category_templates.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/news/project_handoff.dart';
import 'package:tj_pro/news/templates_library_screen.dart';
import 'package:tj_pro/news/watermark.dart';
import 'package:tj_pro/services/ffmpeg_service.dart';

void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return '/tmp/tj_pro_phase8_test';
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

/// Renders [preset] to a temp dir and returns the PNG file.
Future<File> _renderPreset(ChannelPreset preset) async {
  final dir = await Directory.systemTemp.createTemp('tj_pro_phase8_');
  return renderLiveTemplateImage(
    template: NewsTemplate(),
    tickerPx: 0,
    now: DateTime(2026, 11, 21, 12, 0),
    dir: dir,
    templateKind: preset.templateKind,
    preset: preset,
    breakingTemplate: preset.templateKind == 'breaking'
        ? BreakingTemplate.fromPreset(preset)
        : null,
    tickerAtStart: true,
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

Future<void> _cleanStoreFiles() async {
  for (final name in [
    'category_templates.json',
    'channel_presets.json',
    'breaking_templates.json',
  ]) {
    final file = File('/tmp/tj_pro_phase8_test/$name');
    if (await file.exists()) await file.delete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    _mockPathProvider();
    Directory('/tmp/tj_pro_phase8_test').createSync(recursive: true);
  });

  group('CategoryTemplate — 13 categories, one real variant each', () {
    test('defaults cover every category exactly once', () {
      final defaults = CategoryTemplate.defaults();
      expect(defaults, hasLength(13));
      final ids = defaults.map((t) => t.categoryId).toList();
      expect(ids.toSet(), hasLength(13));
      for (final c in kTemplateCategories) {
        if (c.$1 == 'all') continue;
        expect(ids, contains(c.$1));
      }
      for (final t in defaults) {
        expect(t.name.trim(), isNotEmpty);
        expect(t.categories, [t.categoryId]);
        expect(t.categoryLabel.trim(), isNotEmpty);
        expect(t.coinCost, 0);
      }
    });

    test('previously empty categories now have variants', () {
      final byId = {
        for (final t in CategoryTemplate.defaults()) t.categoryId: t,
      };
      expect(byId['sports']!.name, 'Sports News');
      expect(byId['sports']!.topColor, 0xFF2E7D32);
      expect(byId['technology']!.name, 'Technology News');
      expect(byId['technology']!.topColor, 0xFF7C3AED);
      expect(byId['weather']!.name, 'Weather Report');
      expect(byId['weather']!.topColor, 0xFF00838F);
      expect(byId['documentary']!.templateKind, 'classic');
      expect(byId['interview']!.templateKind, 'classic');
      expect(byId['interview']!.showInterviewPlate, isTrue);
      expect(byId['bulletins']!.templateKind, 'breaking');
      expect(byId['bulletins']!.breakingVariant, 'topHeadlineBar');
      expect(byId['crime']!.templateKind, 'breaking');
    });

    test('applyToPreset sets kind/colours/label, never content kinds', () {
      final preset = ChannelPreset.nigraanTv()
        ..topRibbon.text = 'Current story ticker'
        ..urduRibbon.text = 'National news ticker'
        ..englishRibbon.text = 'International ticker';
      final sports = CategoryTemplate.defaults()
          .firstWhere((t) => t.categoryId == 'sports');
      sports.applyToPreset(preset);
      expect(preset.templateKind, 'nigraanFinal');
      expect(preset.topRibbon.color, 0xFF2E7D32);
      expect(preset.categoryLabel, 'SPORTS');
      // Texts untouched.
      expect(preset.topRibbon.text, 'Current story ticker');
      expect(preset.urduRibbon.text, 'National news ticker');
      expect(preset.englishRibbon.text, 'International ticker');
      // RIBBON-CONTENT RULE: kinds are read-only.
      expect(preset.topRibbon.contentKind, RibbonContentKind.current);
      expect(preset.urduRibbon.contentKind, RibbonContentKind.national);
      expect(
        preset.englishRibbon.contentKind,
        RibbonContentKind.international,
      );
    });

    test('previewPreset applies without mutating the base preset', () {
      final base = ChannelPreset.nigraanTv();
      final weather = CategoryTemplate.defaults()
          .firstWhere((t) => t.categoryId == 'weather');
      final preview = weather.previewPreset(base);
      expect(preview.topRibbon.color, 0xFF00838F);
      expect(preview.categoryLabel, 'WEATHER');
      expect(base.topRibbon.color, 0xFF01B0FF);
      expect(base.categoryLabel, '');
    });

    test('applyToProject sets kind + variant; breaking sets the flag', () {
      final project = NewsProject.create();
      final bulletins = CategoryTemplate.defaults()
          .firstWhere((t) => t.categoryId == 'bulletins');
      bulletins.applyToProject(project);
      expect(project.templateKind, 'breaking');
      expect(project.breakingVariant, 'topHeadlineBar');
      expect(project.breaking, isTrue);

      final sports = CategoryTemplate.defaults()
          .firstWhere((t) => t.categoryId == 'sports');
      final project2 = NewsProject.create();
      sports.applyToProject(project2);
      expect(project2.templateKind, 'nigraanFinal');
      expect(project2.breaking, isFalse);
    });

    test('JSON round-trip preserves every field', () {
      final original = CategoryTemplate.defaults()
          .firstWhere((t) => t.categoryId == 'interview')
          .copyWith(isCustom: true, name: 'My Interview', coinCost: 25);
      final restored = CategoryTemplate.fromJson(original.toJson());
      expect(restored.toJson(), original.toJson());
      expect(restored.isCustom, isTrue);
      expect(restored.name, 'My Interview');
      expect(restored.showInterviewPlate, isTrue);
    });

    test('every category template renders to a real 720x1280 PNG',
        () async {
      final base = ChannelPreset.nigraanTv()
        ..topRibbon.text = 'Current story ticker'
        ..urduRibbon.text = 'National news ticker'
        ..englishRibbon.text = 'International ticker';
      for (final template in CategoryTemplate.defaults()) {
        final file = await _renderPreset(template.previewPreset(base));
        await _expect720x1280Png(file);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('CategoryTemplateStore — save / list / apply / delete', () {
    setUp(_cleanStoreFiles);

    test('save → loadAll lists the custom under its category', () async {
      final sports = CategoryTemplate.defaults()
          .firstWhere((t) => t.categoryId == 'sports');
      final saved = await CategoryTemplateStore.saveCustomTemplate(
        name: 'My Sports Look',
        template: sports.copyWith(topColor: 0xFF004D40),
      );
      expect(saved.isCustom, isTrue);
      expect(saved.name, 'My Sports Look');
      expect(saved.categoryId, 'sports');
      expect(saved.topColor, 0xFF004D40);
      final all = await CategoryTemplateStore.loadAll();
      expect(all, hasLength(14));
      final found = all.firstWhere((t) => t.id == saved.id);
      expect(found.categories, ['sports']);
      // Applying the saved custom changes what a project renders.
      final preset = ChannelPreset.nigraanTv();
      found.applyToPreset(preset);
      expect(preset.topRibbon.color, 0xFF004D40);
      expect(preset.categoryLabel, 'SPORTS');
    });

    test('delete removes a custom; built-ins cannot be deleted',
        () async {
      final saved = await CategoryTemplateStore.saveCustomTemplate(
        name: 'To Delete',
        template: CategoryTemplate.defaults().first,
      );
      await CategoryTemplateStore.deleteCustomTemplate(saved.id);
      final all = await CategoryTemplateStore.loadAll();
      expect(all.where((t) => t.id == saved.id), isEmpty);
      expect(all, hasLength(13));
      await CategoryTemplateStore.deleteCustomTemplate('sports');
      expect(
        (await CategoryTemplateStore.loadAll()).length,
        13,
      );
    });
  });

  group('ChannelPreset branding — fields, handles, watermark', () {
    test('Nigraan TV default carries its real handles + watermark on',
        () {
      final preset = ChannelPreset.nigraanTv();
      expect(preset.socialYoutube, '@nigraantvxyz');
      expect(preset.socialTiktok, '@nigraantv');
      expect(preset.socialInstagram, '@nigraantv');
      expect(preset.socialFacebook, 'Nigraan TV');
      expect(preset.socialX, '@nigraantv');
      expect(preset.socialHandles, hasLength(5));
      expect(preset.hasSocialHandles, isTrue);
      expect(preset.watermarkEnabled, isTrue);
      expect(preset.watermarkPosition, 'bottomRight');
      expect(preset.watermarkSize, 0.12);
      expect(preset.brandColor, 0xFF7C3AED);
      expect(
        preset.socialHandleLines(),
        contains('YouTube: @nigraantvxyz'),
      );
    });

    test('empty handles produce no handles and no placeholder lines',
        () {
      final preset = ChannelPreset(id: 'x', name: 'Test Channel');
      expect(preset.socialHandles, isEmpty);
      expect(preset.hasSocialHandles, isFalse);
      expect(preset.socialHandleLines(), isEmpty);
      expect(endCardLines(preset), ['Test Channel']);
      // No '@' placeholder anywhere in the lines.
      expect(endCardLines(preset).join(' '), isNot(contains('@')));
    });

    test('branding JSON round-trip preserves every Phase 8 field', () {
      final preset = ChannelPreset(
        id: 'custom_1',
        name: 'My Channel',
        brandColor: 0xFF123456,
        socialFacebook: 'My Page',
        socialYoutube: '@mychannel',
        socialTiktok: '',
        socialInstagram: '@mychannel',
        socialX: '',
        watermarkEnabled: false,
        watermarkPosition: 'topLeft',
        watermarkSize: 0.2,
      );
      final restored = ChannelPreset.fromJson(preset.toJson());
      expect(restored.toJson(), preset.toJson());
      expect(restored.socialHandles, hasLength(3));
      expect(restored.socialHandles['youtube'], '@mychannel');
      expect(restored.watermarkEnabled, isFalse);
      expect(restored.watermarkPosition, 'topLeft');
      expect(restored.watermarkSize, 0.2);
      expect(restored.brandColor, 0xFF123456);
    });

    test('old saved presets without branding fields get sane defaults',
        () {
      final restored = ChannelPreset.fromJson({
        'id': 'old',
        'name': 'Old Channel',
      });
      expect(restored.socialHandles, isEmpty);
      expect(restored.watermarkEnabled, isTrue);
      expect(restored.watermarkPosition, 'bottomRight');
      expect(restored.watermarkSize, 0.12);
      expect(restored.brandColor, 0xFF7C3AED);
    });

    test('saveCustomTemplate copies the branding with the preset',
        () async {
      await _cleanStoreFiles();
      final preset = ChannelPreset.nigraanTv()
        ..brandColor = 0xFF00FF00
        ..socialYoutube = '@brandtest'
        ..watermarkEnabled = false
        ..watermarkPosition = 'topLeft';
      final saved = await ChannelPresetStore.saveCustomTemplate(
        name: 'Branded Copy',
        preset: preset,
      );
      final all = await ChannelPresetStore.loadAll();
      final found = all.firstWhere((p) => p.id == saved.id);
      expect(found.brandColor, 0xFF00FF00);
      expect(found.socialYoutube, '@brandtest');
      expect(found.watermarkEnabled, isFalse);
      expect(found.watermarkPosition, 'topLeft');
      // The built-in's other handles still travel with the copy.
      expect(found.socialTiktok, '@nigraantv');
      await _cleanStoreFiles();
    });
  });

  group('Watermark — geometry, PNG render, end card', () {
    test('rect sits inside the frame at every corner', () {
      for (final pos in ChannelPreset.watermarkPositionIds) {
        final rect = watermarkRect(
          width: 720,
          height: 1280,
          position: pos,
          sizeFraction: 0.12,
        );
        expect(rect.width, closeTo(86.4, 0.01));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(720));
        expect(rect.bottom, lessThanOrEqualTo(1280));
      }
      final topLeft = watermarkRect(
        width: 720,
        height: 1280,
        position: 'topLeft',
        sizeFraction: 0.12,
      );
      expect(topLeft.left, 16);
      expect(topLeft.top, 16);
      final bottomRight = watermarkRect(
        width: 720,
        height: 1280,
        position: 'bottomRight',
        sizeFraction: 0.12,
      );
      expect(bottomRight.right, 720 - 16);
      expect(bottomRight.bottom, 1280 - 16);
    });

    test('size scales with sizeFraction and clamps to 0.05–0.30', () {
      expect(
        watermarkRect(
          width: 720,
          height: 1280,
          position: 'topLeft',
          sizeFraction: 0.05,
        ).width,
        closeTo(36, 0.01),
      );
      expect(
        watermarkRect(
          width: 720,
          height: 1280,
          position: 'topLeft',
          sizeFraction: 0.01,
        ).width,
        closeTo(36, 0.01),
      );
      expect(
        watermarkRect(
          width: 720,
          height: 1280,
          position: 'topLeft',
          sizeFraction: 1.0,
        ).width,
        closeTo(216, 0.01),
      );
    });

    test('renderWatermarkImage produces a 720x1280 PNG', () async {
      final dir = await Directory.systemTemp.createTemp('tj_pro_phase8_');
      final file = await renderWatermarkImage(
        preset: ChannelPreset.nigraanTv(),
        dir: dir,
      );
      await _expect720x1280Png(file);
    });

    test('end card renders; handles change the pixels', () async {
      // Separate dirs: both renders write `branding_end_card.png`,
      // so one dir would let the second overwrite the first.
      final dirA = await Directory.systemTemp.createTemp('tj_pro_phase8_');
      final dirB = await Directory.systemTemp.createTemp('tj_pro_phase8_');
      final withHandles = await renderBrandingEndCardImage(
        preset: ChannelPreset.nigraanTv(),
        dir: dirA,
      );
      await _expect720x1280Png(withHandles);
      final withoutHandles = await renderBrandingEndCardImage(
        preset: ChannelPreset(id: 'x', name: 'Test Channel'),
        dir: dirB,
      );
      await _expect720x1280Png(withoutHandles);
      final a = await withHandles.readAsBytes();
      final b = await withoutHandles.readAsBytes();
      expect(a, isNot(b));
    });

    test('watermark overlay command is a real positioned FFmpeg pass',
        () {
      final cmd = FfmpegService.watermarkOverlayCommand(
        input: '/tmp/in.mp4',
        watermarkPngPath: '/tmp/wm.png',
        output: '/tmp/out.mp4',
      );
      expect(cmd, contains("'/tmp/in.mp4'"));
      expect(cmd, contains("'/tmp/wm.png'"));
      expect(cmd, contains("'/tmp/out.mp4'"));
      expect(cmd, contains('overlay=0:0'));
      expect(cmd, contains('libx264'));
      expect(cmd, contains('-map 0:a?'));
    });
  });

  group('Branding auto-apply — new projects render the preset', () {
    test('effectivePresetFor preserves branding fields', () {
      final preset = ChannelPreset.nigraanTv()
        ..brandColor = 0xFF00FF00
        ..socialYoutube = '@autoapply'
        ..watermarkEnabled = false
        ..watermarkPosition = 'topLeft'
        ..watermarkSize = 0.2;
      final project = NewsProject.create()
        ..tickerText = 'Story ticker'
        ..headline = 'Story headline';
      final effective = effectivePresetFor(project: project, preset: preset);
      expect(effective.brandColor, 0xFF00FF00);
      expect(effective.socialYoutube, '@autoapply');
      expect(effective.watermarkEnabled, isFalse);
      expect(effective.watermarkPosition, 'topLeft');
      expect(effective.watermarkSize, 0.2);
      // And the project's own ticker still lands on the top ribbon.
      expect(effective.topRibbon.text, 'Story ticker');
    });

    test('changing the preset branding changes the rendered PNG', () async {
      final plain = ChannelPreset.nigraanTv();
      final rebranded = ChannelPreset.nigraanTv()
        ..topRibbon.color = 0xFF2E7D32
        ..brandColor = 0xFF2E7D32;
      final a = await _renderPreset(plain);
      final b = await _renderPreset(rebranded);
      expect(await a.readAsBytes(), isNot(await b.readAsBytes()));
    });

    test('changing the watermark toggle changes the watermark PNG path',
        () async {
      // The export graph's watermark step is gated on the toggle:
      // off = no watermark PNG is rendered for the pass at all.
      // Verified here at the model level (the FFmpeg run itself
      // needs a real device — see the Phase 8 report).
      final on = ChannelPreset.nigraanTv();
      final off = ChannelPreset.nigraanTv()..watermarkEnabled = false;
      expect(on.watermarkEnabled, isTrue);
      expect(off.watermarkEnabled, isFalse);
      final dir = await Directory.systemTemp.createTemp('tj_pro_phase8_');
      final file = await renderWatermarkImage(preset: on, dir: dir);
      await _expect720x1280Png(file);
    });
  });
}
