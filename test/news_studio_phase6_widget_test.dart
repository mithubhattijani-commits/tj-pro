// Phase 6 widget tests: Templates Library builds + filters + Use +
// Save-as-Custom (empty-name path), breaking/classic previews build
// for every variant, and the News Maker / AI News Maker / Template
// & Studio screens render the breaking + classic previews (no more
// "Phase 6" placeholder cards).
//
// Build-only + synchronous-interaction tests: persistence is covered
// by the plain unit tests in news_studio_phase6_test.dart (widget-test
// pumps never flush real dart:io work — Phase 4 note). No
// tester.runAsync + Future.delayed. No pumpAndSettle: the previews
// embed the repeating ticker animation — use bounded pumps.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/news/ai_news_maker_screen.dart';
import 'package:tj_pro/news/breaking_templates.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/news_maker_screen.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/news/template_studio_screen.dart';
import 'package:tj_pro/news/templates_library_screen.dart';
import 'package:tj_pro/news/widgets/breaking_preview.dart';

void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return '/tmp/tj_pro_phase6_widget';
      }
      if (call.method == 'getTemporaryDirectory') {
        return '/tmp/tj_pro_phase6_widget_tmp';
      }
      return null;
    },
  );
}

/// Drags [listKey]'s ListView down until [target] is built (or
/// [maxDrags] drags pass). ListViews build lazily, so below-fold
/// widgets do not exist until scrolled into view.
Future<void> _scrollTo(
  WidgetTester tester,
  Key listKey,
  Finder target, {
  int maxDrags = 20,
}) async {
  for (var i = 0; i < maxDrags; i++) {
    if (target.evaluate().isNotEmpty) return;
    await tester.drag(find.byKey(listKey), const Offset(0, -600));
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

void main() {
  setUpAll(() {
    _mockPathProvider();
    Directory('/tmp/tj_pro_phase6_widget').createSync(recursive: true);
    Directory('/tmp/tj_pro_phase6_widget_tmp')
        .createSync(recursive: true);
  });

  group('BreakingTemplatePreview builds for every variant', () {
    for (final template in BreakingTemplate.defaults()) {
      testWidgets('preview: ${template.variant.label}', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BreakingTemplatePreview(
                template: template,
                preset: ChannelPreset.nigraanTv(),
                height: 320,
              ),
            ),
          ),
        );
        await _pumpFrames(tester);
        expect(find.byKey(const Key('breaking-preview')), findsOneWidget);
        expect(find.byKey(const Key('breaking-banner')), findsOneWidget);
        if (template.variant == BreakingVariant.breakingTickerCombo) {
          expect(
            find.byKey(const Key('breaking-top-ticker')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('breaking-middle-ribbon')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('breaking-bottom-ribbon')),
            findsOneWidget,
          );
        } else {
          expect(find.byKey(const Key('breaking-ticker')), findsOneWidget);
        }
      });
    }

    testWidgets('preview shows interview plate + PIP when on',
        (tester) async {
      final template = BreakingTemplate.defaults()[0]
        ..showInterviewPlate = true
        ..interviewName = 'Ahmed Raza'
        ..interviewDesignation = 'Anchor'
        ..pipEnabled = true
        ..pipPosition = 'topLeft';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BreakingTemplatePreview(
              template: template,
              preset: ChannelPreset.nigraanTv(),
              height: 320,
            ),
          ),
        ),
      );
      await _pumpFrames(tester);
      expect(
        find.byKey(const Key('preview-interview-plate')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('preview-pip-inset')), findsOneWidget);
      expect(find.text('Ahmed Raza'), findsOneWidget);
    });

    testWidgets('ClassicPreview builds with top bar + ticker',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClassicPreview(
              preset: ChannelPreset.nigraanTv()
                ..topRibbon.text = 'Ticker text',
              height: 320,
            ),
          ),
        ),
      );
      await _pumpFrames(tester);
      expect(find.byKey(const Key('classic-preview')), findsOneWidget);
      expect(find.byKey(const Key('classic-top-bar')), findsOneWidget);
      expect(find.byKey(const Key('classic-ticker')), findsOneWidget);
      expect(find.text('Nigraan TV'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
    });
  });

  group('Templates Library screen', () {
    Future<void> pumpLibrary(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TemplatesLibraryScreen(
            initialPreset: ChannelPreset.nigraanTv(),
            initialTemplates: BreakingTemplate.defaults(),
          ),
        ),
      );
      await _pumpFrames(tester);
    }

    testWidgets('builds with categories + all six template cards',
        (tester) async {
      await pumpLibrary(tester);
      expect(find.text('Templates Library'), findsOneWidget);
      expect(
        find.byKey(const Key('categoryChip-breaking')),
        findsOneWidget,
      );
      expect(find.text('Breaking Red Banner'), findsOneWidget);
      await _scrollTo(
        tester,
        const Key('templatesLibraryList'),
        find.text('Latest News'),
      );
      expect(find.text('Latest News'), findsOneWidget);
      // Cost badges: the premium card on screen shows its price.
      expect(find.text('25 coins'), findsWidgets);
      await _scrollTo(
        tester,
        const Key('templatesLibraryList'),
        find.text('Top Headline Bar'),
      );
      expect(find.text('Top Headline Bar'), findsOneWidget);
      await _scrollTo(
        tester,
        const Key('templatesLibraryList'),
        find.text('Breaking + Ticker Combo'),
      );
      expect(find.text('Breaking + Ticker Combo'), findsOneWidget);
      await _scrollTo(
        tester,
        const Key('templatesLibraryList'),
        find.text('Final 3-Ribbon'),
      );
      expect(find.text('Final 3-Ribbon'), findsOneWidget);
      await _scrollTo(
        tester,
        const Key('templatesLibraryList'),
        find.text('Classic'),
      );
      expect(find.text('Classic'), findsOneWidget);
    });

    testWidgets(
        'category filter shows the Sports template (Phase 8: every '
        'category populated, no empty state)',
        (tester) async {
      await pumpLibrary(tester);
      // 'Sports' is the last chip — lazily un-built in the
      // horizontal category row, so scroll that row until it
      // appears, then tap it.
      await tester.scrollUntilVisible(
        find.byKey(const Key('categoryChip-sports')),
        300,
        scrollable: find.descendant(
          of: find.byKey(const Key('templateCategoryRow')),
          matching: find.byType(Scrollable),
        ),
      );
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('categoryChip-sports')));
      await _pumpFrames(tester);
      // Phase 8: Sports has a real template now — the empty state
      // is gone for it (it only remains for a filter that matches
      // nothing, which no category does any more).
      expect(find.byKey(const Key('emptyCategory')), findsNothing);
      expect(
        find.byKey(const Key('templateCard-category_sports')),
        findsOneWidget,
      );
      expect(find.text('Sports News'), findsWidgets);
      expect(find.text('Breaking Red Banner'), findsNothing);
    });

    testWidgets('editor panel opens on the selected card', (tester) async {
      await pumpLibrary(tester);
      // The default selected card is Final — select the breaking
      // card first (its editor has the headline field).
      await tester.tap(
        find.byKey(const Key('templateCardTap-breakingRedBanner')),
      );
      await _pumpFrames(tester);
      await _scrollTo(
        tester,
        const Key('templatesLibraryList'),
        find.byKey(const Key('editHeadlineField')),
      );
      expect(find.byKey(const Key('editHeadlineField')), findsOneWidget);
      expect(find.byKey(const Key('editTickerField')), findsOneWidget);
      expect(find.byKey(const Key('editCategoryField')), findsOneWidget);
      expect(find.byKey(const Key('editSpeedSlider')), findsOneWidget);
      // The Save button sits below the long editor panel — scroll.
      await _scrollTo(
        tester,
        const Key('templatesLibraryList'),
        find.byKey(const Key('saveCustomButton')),
      );
      expect(find.byKey(const Key('saveCustomButton')), findsOneWidget);
      // Ribbon content kinds are read-only info, never editable.
      await _scrollTo(
        tester,
        const Key('templatesLibraryList'),
        find.textContaining('Content kind kabhi change nahi hota'),
      );
      expect(
        find.textContaining('Content kind kabhi change nahi hota'),
        findsOneWidget,
      );
    });

    testWidgets('swatch tap changes the banner colour hex', (tester) async {
      await pumpLibrary(tester);
      await tester.tap(
        find.byKey(const Key('templateCardTap-breakingRedBanner')),
      );
      await _pumpFrames(tester);
      await _scrollTo(
        tester,
        const Key('templatesLibraryList'),
        find.byKey(const Key('editHeadlineField')),
      );
      // Breaking Red Banner starts red; tap the ticker-blue swatch
      // on the Banner row. The swatch is built but off-screen (the
      // editor panel is one tall Column), so ensureVisible first —
      // a bare tap on an off-screen widget misses.
      expect(find.text('#D50000'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(Key('swatch-Banner-${0xFF01B0FF}')),
      );
      await _pumpFrames(tester);
      await tester.tap(
        find.byKey(Key('swatch-Banner-${0xFF01B0FF}')),
      );
      await _pumpFrames(tester);
      expect(find.text('#01B0FF'), findsOneWidget);
    });

    testWidgets('Use applies the template (SnackBar, no fake button)',
        (tester) async {
      final preset = ChannelPreset.nigraanTv();
      await tester.pumpWidget(
        MaterialApp(
          home: TemplatesLibraryScreen(
            initialPreset: preset,
            initialTemplates: BreakingTemplate.defaults(),
          ),
        ),
      );
      await _pumpFrames(tester);
      await _scrollTo(
        tester,
        const Key('templatesLibraryList'),
        find.byKey(const Key('useTemplate-breakingRedBanner')),
      );
      await tester.tap(
        find.byKey(const Key('useTemplate-breakingRedBanner')),
      );
      await _pumpFrames(tester);
      expect(find.textContaining('Template apply ho gaya'), findsOneWidget);
      expect(preset.templateKind, 'breaking');
      expect(preset.breakingVariant, 'breakingRedBanner');
    });

    testWidgets('Save as Custom with an empty name asks for a name',
        (tester) async {
      await pumpLibrary(tester);
      await _scrollTo(
        tester,
        const Key('templatesLibraryList'),
        find.byKey(const Key('saveCustomButton')),
      );
      await tester.tap(find.byKey(const Key('saveCustomButton')));
      await _pumpFrames(tester);
      expect(
        find.text('Pehle template ka naam likhein.'),
        findsOneWidget,
      );
    });
  });

  group('Template & Studio renders breaking + classic', () {
    testWidgets('breaking preset shows the breaking preview + variants',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TemplateStudioScreen(
            initialPreset: ChannelPreset.nigraanTv()
              ..templateKind = 'breaking'
              ..breakingVariant = 'latestNews',
          ),
        ),
      );
      await _pumpFrames(tester);
      expect(
        find.byKey(const Key('templateStudioBreakingPreview')),
        findsOneWidget,
      );
      // Variant chips sit below the preview — scroll to them first.
      await _scrollTo(
        tester,
        const Key('templateStudioList'),
        find.byKey(const Key('breakingVariant-latestNews')),
      );
      expect(
        find.byKey(const Key('breakingVariant-latestNews')),
        findsOneWidget,
      );
      expect(find.text('Templates Library →'), findsOneWidget);
    });

    testWidgets('classic preset shows the classic preview', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TemplateStudioScreen(
            initialPreset: ChannelPreset.nigraanTv()
              ..templateKind = 'classic',
          ),
        ),
      );
      await _pumpFrames(tester);
      expect(
        find.byKey(const Key('templateStudioClassicPreview')),
        findsOneWidget,
      );
    });
  });

  group('News Maker template choice persists per project', () {
    testWidgets('breaking choice updates the project + preview',
        (tester) async {
      final project = NewsProject.create()
        ..templateKind = 'nigraanFinal'
        ..breakingVariant = 'breakingRedBanner';
      await tester.pumpWidget(
        MaterialApp(
          home: NewsMakerScreen(
            initialPreset: ChannelPreset.nigraanTv(),
            initialProject: project,
          ),
        ),
      );
      await _pumpFrames(tester);
      // v1.5.2: template choices live in the Template TOOL panel
      // as visual cards (the old inline choice row is gone).
      await tester.tap(find.byKey(const Key('makerTool-template')));
      await _pumpFrames(tester);
      await tester.tap(
        find.byKey(const Key('templateCard-breaking')),
      );
      await _pumpFrames(tester);
      expect(project.templateKind, 'breaking');
      expect(project.breaking, isTrue);
      expect(find.byKey(const Key('makerBreakingPreview')), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('makerBreakingVariant-latestNews')),
      );
      await _pumpFrames(tester);
      expect(project.breakingVariant, 'latestNews');
    });

    testWidgets('classic choice shows the classic preview', (tester) async {
      final project = NewsProject.create()..templateKind = 'classic';
      await tester.pumpWidget(
        MaterialApp(
          home: NewsMakerScreen(
            initialPreset: ChannelPreset.nigraanTv(),
            initialProject: project,
          ),
        ),
      );
      await _pumpFrames(tester);
      expect(find.byKey(const Key('makerClassicPreview')), findsOneWidget);
    });
  });

  group('AI News Maker breaking variant choice', () {
    testWidgets('graphics step shows variant chips when breaking',
        (tester) async {
      final project = NewsProject.create()
        ..templateKind = 'breaking'
        ..breakingVariant = 'breakingRedBanner';
      await tester.pumpWidget(
        MaterialApp(
          home: AiNewsMakerScreen(
            initialPreset: ChannelPreset.nigraanTv(),
            initialProject: project,
          ),
        ),
      );
      await _pumpFrames(tester);
      // The graphics step tile sits below the fold — scroll the
      // maker list to it (scrollUntilVisible fails here: the screen
      // has more than one Scrollable).
      await _scrollTo(
        tester,
        const Key('aiMakerList'),
        find.byKey(const Key('aiStep-graphics')),
      );
      await tester.tap(find.byKey(const Key('aiStep-graphics')));
      await _pumpFrames(tester);
      await _scrollTo(
        tester,
        const Key('aiMakerList'),
        find.byKey(const Key('aiBreakingVariant-topHeadlineBar')),
      );
      expect(
        find.byKey(const Key('aiBreakingVariant-topHeadlineBar')),
        findsOneWidget,
      );
      // v1.5.2: the graphics step grew (two template rows), so
      // the chip can be built yet below the fold — bring it fully
      // into view before tapping or the tap misses.
      await tester.ensureVisible(
        find.byKey(const Key('aiBreakingVariant-topHeadlineBar')),
      );
      await _pumpFrames(tester);
      await tester.tap(
        find.byKey(const Key('aiBreakingVariant-topHeadlineBar')),
      );
      await _pumpFrames(tester);
      expect(project.breakingVariant, 'topHeadlineBar');
    });
  });
}
