// Phase 8 widget tests: Templates Library shows a real card in
// every category (incl. the previously empty Sports / Technology /
// Weather / Documentary / Interview), the save-custom settings
// summary + empty-name guard, Use applies a category template to a
// project, the Channel Branding screen's controls actually change
// state, the watermark mark shows in previews, and Channel Branding
// is reachable from Template & Studio.
//
// Build-only + synchronous-interaction tests: persistence round-trips
// are covered by the plain unit tests in
// news_studio_phase8_test.dart (widget-test pumps never flush real
// dart:io work — Phase 4 note). No tester.runAsync +
// Future.delayed. No pumpAndSettle: the previews embed the repeating
// ticker animation — use bounded pumps.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/news/breaking_templates.dart';
import 'package:tj_pro/news/category_templates.dart';
import 'package:tj_pro/news/channel_branding_screen.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/news/templates_library_screen.dart';
import 'package:tj_pro/news/widgets/nigraan_final_preview.dart';

void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return '/tmp/tj_pro_phase8_widget';
      }
      if (call.method == 'getTemporaryDirectory') {
        return '/tmp/tj_pro_phase8_widget_tmp';
      }
      return null;
    },
  );
}

/// Drags [listKey]'s ListView down until [target] is actually
/// VISIBLE (its centre inside the 800x600 test viewport), not just
/// built — ListViews build items up to the cache extent beyond the
/// viewport, and a tap on an off-screen centre misses. Small drag
/// steps so the target cannot overshoot past the top edge.
Future<void> _scrollTo(
  WidgetTester tester,
  Key listKey,
  Finder target, {
  int maxDrags = 40,
}) async {
  for (var i = 0; i < maxDrags; i++) {
    if (target.evaluate().isNotEmpty) {
      final rect = tester.getRect(target);
      if (rect.center.dx >= 0 &&
          rect.center.dx <= 800 &&
          rect.center.dy >= 0 &&
          rect.center.dy <= 600) {
        return;
      }
    }
    await tester.drag(find.byKey(listKey), const Offset(0, -300));
    await tester.pump();
  }
}

/// Bounded pumps for screens with the repeating ticker animation
/// (pumpAndSettle never settles on them).
Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

/// Drags the horizontal category chip row left until [target] is
/// actually VISIBLE (its centre inside the 800x600 test viewport).
/// The row builds lazily AND with a cache extent, so an off-screen
/// chip can exist without being tappable — `ensureVisible` cannot
/// find it at all, and a tap on its off-screen centre misses.
Future<void> _scrollRowTo(
  WidgetTester tester,
  Finder target, {
  int maxDrags = 20,
}) async {
  for (var i = 0; i < maxDrags; i++) {
    if (target.evaluate().isNotEmpty) {
      final rect = tester.getRect(target);
      if (rect.center.dx >= 0 &&
          rect.center.dx <= 800 &&
          rect.center.dy >= 0 &&
          rect.center.dy <= 600) {
        return;
      }
    }
    await tester.drag(
      find.byKey(const Key('templateCategoryRow')),
      const Offset(-300, 0),
    );
    await tester.pump();
  }
}

/// Scrolls the category row to [categoryId]'s chip and taps it.
Future<void> _tapCategoryChip(
  WidgetTester tester,
  String categoryId,
) async {
  final chip = find.byKey(Key('categoryChip-$categoryId'));
  await _scrollRowTo(tester, chip);
  await tester.tap(chip);
  await _pumpFrames(tester);
}

Widget _library({NewsProject? project}) {
  return MaterialApp(
    home: TemplatesLibraryScreen(
      initialPreset: ChannelPreset.nigraanTv(),
      initialProject: project,
      initialTemplates: BreakingTemplate.defaults(),
      initialCategoryTemplates: CategoryTemplate.defaults(),
    ),
  );
}

void main() {
  setUpAll(() {
    _mockPathProvider();
    Directory('/tmp/tj_pro_phase8_widget').createSync(recursive: true);
    Directory('/tmp/tj_pro_phase8_widget_tmp')
        .createSync(recursive: true);
  });

  group('Templates Library — every category has a real card', () {
    for (final entry in {
      'sports': 'Sports News',
      'technology': 'Technology News',
      'weather': 'Weather Report',
      'documentary': 'Documentary Report',
      'interview': 'Interview',
    }.entries) {
      testWidgets('category ${entry.key} shows its template card',
          (tester) async {
        await tester.pumpWidget(_library());
        await _pumpFrames(tester);
        await _tapCategoryChip(tester, entry.key);
        expect(
          find.byKey(Key('templateCard-category_${entry.key}')),
          findsOneWidget,
        );
        expect(find.text(entry.value), findsWidgets);
      });
    }

    testWidgets('sports card renders the final preview + handles footer',
        (tester) async {
      await tester.pumpWidget(_library());
      await _pumpFrames(tester);
      await _tapCategoryChip(tester, 'sports');
      await _scrollTo(
        tester,
        const Key('templatesLibraryList'),
        find.byKey(const Key('templateCard-category_sports')),
      );
      await _pumpFrames(tester);
      expect(find.byType(NigraanFinalPreview), findsWidgets);
      // Nigraan TV's real handles show on the card — no placeholders.
      expect(find.byKey(const Key('templateCardHandles')), findsWidgets);
      expect(find.text('YouTube: @nigraantvxyz'), findsWidgets);
    });

    testWidgets('Use applies a category template to the project',
        (tester) async {
      final project = NewsProject.create();
      await tester.pumpWidget(_library(project: project));
      await _pumpFrames(tester);
      await _tapCategoryChip(tester, 'sports');
      await _scrollTo(
        tester,
        const Key('templatesLibraryList'),
        find.byKey(const Key('useTemplate-category_sports')),
      );
      await tester.tap(find.byKey(const Key('useTemplate-category_sports')));
      await _pumpFrames(tester);
      expect(find.text('Template applied — Sports News.'),
          findsOneWidget);
      expect(project.templateKind, 'nigraanFinal');
    });
  });

  group('Templates Library — save-as-custom UI', () {
    testWidgets('summary shows the selected template settings',
        (tester) async {
      await tester.pumpWidget(_library());
      await _pumpFrames(tester);
      await _tapCategoryChip(tester, 'sports');
      // A chip tap only filters — the card itself must be tapped
      // to select it (that is what the summary describes).
      await _scrollTo(
        tester,
        const Key('templatesLibraryList'),
        find.byKey(const Key('templateCardTap-category_sports')),
      );
      await tester.tap(
        find.byKey(const Key('templateCardTap-category_sports')),
      );
      await _pumpFrames(tester);
      await _scrollTo(
        tester,
        const Key('templatesLibraryList'),
        find.byKey(const Key('saveCustomSummary')),
      );
      await _pumpFrames(tester);
      expect(find.byKey(const Key('saveCustomSummary')), findsOneWidget);
      expect(find.textContaining('SPORTS'), findsWidgets);
      expect(find.textContaining('Final 3-Ribbon'), findsWidgets);
      expect(find.textContaining('#2E7D32'), findsWidgets);
    });

    testWidgets('editing the category label updates the summary',
        (tester) async {
      await tester.pumpWidget(_library());
      await _pumpFrames(tester);
      await _tapCategoryChip(tester, 'weather');
      await _scrollTo(
        tester,
        const Key('templatesLibraryList'),
        find.byKey(const Key('templateCardTap-category_weather')),
      );
      await tester.tap(
        find.byKey(const Key('templateCardTap-category_weather')),
      );
      await _pumpFrames(tester);
      await _scrollTo(
        tester,
        const Key('templatesLibraryList'),
        find.byKey(const Key('editCategoryField')),
      );
      await tester.enterText(
        find.byKey(const Key('editCategoryField')),
        'WEATHER NOW',
      );
      await _pumpFrames(tester);
      await _scrollTo(
        tester,
        const Key('templatesLibraryList'),
        find.byKey(const Key('saveCustomSummary')),
      );
      expect(find.textContaining('WEATHER NOW'), findsWidgets);
    });

    testWidgets('save with an empty name is refused, not a silent no-op',
        (tester) async {
      await tester.pumpWidget(_library());
      await _pumpFrames(tester);
      await _scrollTo(
        tester,
        const Key('templatesLibraryList'),
        find.byKey(const Key('saveCustomButton')),
      );
      await tester.tap(find.byKey(const Key('saveCustomButton')));
      await _pumpFrames(tester);
      expect(find.text('Write the template name first.'), findsOneWidget);
    });
  });

  group('Channel Branding screen', () {
    testWidgets('shows name, handles, watermark switch + end-card lines',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelBrandingScreen(
            initialPreset: ChannelPreset.nigraanTv(),
          ),
        ),
      );
      await _pumpFrames(tester);
      expect(find.byKey(const Key('brandingNameField')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const Key('brandingNameField')),
            )
            .controller
            ?.text,
        'Nigraan TV',
      );
      await _scrollTo(
        tester,
        const Key('channelBrandingList'),
        find.byKey(const Key('brandingWatermarkSwitch')),
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('brandingWatermarkSwitch')),
            )
            .value,
        isTrue,
      );
      await _scrollTo(
        tester,
        const Key('channelBrandingList'),
        find.byKey(const Key('brandingHandlesPreview')),
      );
      expect(find.text('YouTube: @nigraantvxyz'), findsWidgets);
    });

    testWidgets('swatch, handle edit + watermark switch change state',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelBrandingScreen(
            initialPreset: ChannelPreset.nigraanTv(),
          ),
        ),
      );
      await _pumpFrames(tester);
      // Brand swatch tap changes the shown brand hex (row is near
      // the top — scroll to it first, then assert while visible).
      await _scrollTo(
        tester,
        const Key('channelBrandingList'),
        find.byKey(
          const Key('brandingBrandColor-${0xFFD50000}'),
        ),
      );
      await tester.tap(
        find.byKey(const Key('brandingBrandColor-${0xFFD50000}')),
      );
      await _pumpFrames(tester);
      expect(find.text('#D50000'), findsWidgets);
      // Handle edit updates the end-card preview live (scroll to
      // the preview card before asserting — it builds lazily).
      await _scrollTo(
        tester,
        const Key('channelBrandingList'),
        find.byKey(const Key('brandingHandle-youtube')),
      );
      await tester.enterText(
        find.byKey(const Key('brandingHandle-youtube')),
        '@newhandle',
      );
      await _pumpFrames(tester);
      await _scrollTo(
        tester,
        const Key('channelBrandingList'),
        find.byKey(const Key('brandingHandlesPreview')),
      );
      expect(find.text('YouTube: @newhandle'), findsWidgets);
      // Watermark off.
      await _scrollTo(
        tester,
        const Key('channelBrandingList'),
        find.byKey(const Key('brandingWatermarkSwitch')),
      );
      await tester.tap(find.byKey(const Key('brandingWatermarkSwitch')));
      await _pumpFrames(tester);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('brandingWatermarkSwitch')),
            )
            .value,
        isFalse,
      );
    });

    testWidgets('save branding confirms', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChannelBrandingScreen(
            initialPreset: ChannelPreset.nigraanTv(),
          ),
        ),
      );
      await _pumpFrames(tester);
      await _scrollTo(
        tester,
        const Key('channelBrandingList'),
        find.byKey(const Key('brandingSaveButton')),
      );
      await tester.tap(find.byKey(const Key('brandingSaveButton')));
      await _pumpFrames(tester);
      expect(
        find.text('Branding saved — it will apply to new projects.'),
        findsOneWidget,
      );
    });
  });

  group('Watermark mark in previews', () {
    testWidgets('NigraanFinalPreview shows the mark when watermark is on',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NigraanFinalPreview(
              preset: ChannelPreset.nigraanTv(),
              height: 320,
            ),
          ),
        ),
      );
      await _pumpFrames(tester);
      expect(find.byKey(const Key('preview-watermark')), findsOneWidget);
    });

    testWidgets('no mark when the preset watermark is off',
        (tester) async {
      final preset = ChannelPreset.nigraanTv()..watermarkEnabled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NigraanFinalPreview(preset: preset, height: 320),
          ),
        ),
      );
      await _pumpFrames(tester);
      expect(find.byKey(const Key('preview-watermark')), findsNothing);
    });
  });

  // Build 5 (v1.5.7): 'Channel Branding is reachable from
  // Template & Studio' was removed with the retired screen
  // (approved removal). Branding is now reached from the News
  // Maker project-bar menu — covered in
  // test/build5_regressions_test.dart.
}
