/// Build 13 (v1.10.0) — News Studio widget proofs:
///
/// - point #19: the upgraded timeline (transport row, tabs,
///   A2 music lane, playhead) stays visible WITH a panel open;
///   the Logo panel's cube view/part controls write the
///   preset; the Ticker panel's loop switch writes the project.
/// - icons: the dock renders the user's image icons for the 8
///   supplied tools and Material icons for the rest; the Clips
///   tab carries his clips icon.
/// - point 5: the Audio panel's Auto Ducking switch writes the
///   project.
/// - point 4: the Reporter panel's Teleprompter button exists;
///   the Teleprompter screen renders fail-soft without a camera.
/// - point 6: the Logo Parts section renders per-part controls
///   and the save button; the Permanent Logo section shows the
///   manual-payment instructions.
/// - point 1: the Captions panel shows the timing-source status
///   and the "Asal timings" action.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/logo_parts.dart';
import 'package:tj_pro/news/news_analysis.dart';
import 'package:tj_pro/news/news_maker_screen.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/news/teleprompter_screen.dart';

void _mockPathProvider(String dir) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return dir;
      if (call.method == 'getTemporaryDirectory') return '${dir}_tmp';
      return null;
    },
  );
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _openTool(WidgetTester tester, String id) async {
  final target = find.byKey(Key('makerTool-$id'));
  for (var i = 0; i < 12; i++) {
    if (target.evaluate().isNotEmpty) {
      final rect = tester.getRect(target);
      if (rect.left >= 0 && rect.right <= 393) break;
    }
    await tester.drag(
      find.byKey(const Key('makerToolLine')),
      const Offset(-240, 0),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
  await tester.tap(target);
  await _frames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late File logoFile;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('tjpro_build13_panels');
    _mockPathProvider(tmp.path);
    // A tiny real PNG as the preset's logo.
    logoFile = File('${tmp.path}/logo.png');
    await logoFile.writeAsBytes(
      <int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00,
        0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
        0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
        0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63,
        0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60,
        0x82,
      ],
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<(ChannelPreset, NewsProject)> pumpMaker(
    WidgetTester tester, {
    NewsProject? project,
    ChannelPreset? preset,
  }) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final p = preset ?? (ChannelPreset.nigraanTv()..logoPath = logoFile.path);
    final proj = project ?? NewsProject.create(presetId: p.id);
    await tester.pumpWidget(
      MaterialApp(
        home: NewsMakerScreen(initialPreset: p, initialProject: proj),
      ),
    );
    await _frames(tester);
    return (p, proj);
  }

  testWidgets('timeline: transport, tabs, A2 lane, playhead — panel open',
      (tester) async {
    // SPEC CHANGE (Point #27, tools-fix wave P0-4): this test
    // used to pin the Build 13 arrangement — timeline fully
    // visible WITH a panel open. The user overruled that layout
    // (the timeline squeezed the preview to a strip): now the
    // timeline shows only in the no-tool state, opening a tool
    // collapses it, and closing the tool brings it back.
    final project = NewsProject.create()
      ..voiceoverPath = '/nonexistent/vo.wav'
      ..voiceoverDurationSec = 45;
    await pumpMaker(tester, project: project);
    // No-tool state: the full timeline is here.
    expect(find.byKey(const Key('tlPlayPause')), findsOneWidget);
    expect(find.byKey(const Key('tlStop')), findsOneWidget);
    expect(find.byKey(const Key('tlTimeText')), findsOneWidget);
    expect(find.text('0:00 / 0:45'), findsOneWidget);
    expect(find.byKey(const Key('tlPlayhead')), findsOneWidget);
    for (final tab in ['clips', 'voice', 'ticker', 'ribbons']) {
      expect(find.byKey(Key('tlTab-$tab')), findsOneWidget);
    }
    expect(find.byKey(const Key('tlTabIcon-clips')), findsOneWidget);
    expect(find.textContaining('koi music nahi'), findsOneWidget);
    // Open the Logo tool: the timeline collapses away.
    await _openTool(tester, 'logo');
    expect(find.byKey(const Key('makerPanel-logo')), findsOneWidget);
    expect(find.byKey(const Key('tlPlayPause')), findsNothing);
    expect(find.byKey(const Key('tlTab-clips')), findsNothing);
    // Close the tool (the panel's ✓): the timeline returns.
    await tester.tap(find.byKey(const Key('makerPanelDone')));
    await _frames(tester);
    expect(find.byKey(const Key('tlPlayPause')), findsOneWidget);
    expect(find.byKey(const Key('tlTab-clips')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dock icons: user images for 8 tools, Material for the rest',
      (tester) async {
    await pumpMaker(tester);
    // The dock is a lazy ListView: off-screen items are not
    // built at all, so reveal each tool by jumping the scroll
    // position to its slot (64dp item + 1dp separator).
    const order = [
      'template',
      'media',
      'elements',
      'tehreer',
      'ticker',
      'ribbons',
      'logo',
      'reporter',
      'audio',
      'voice',
      'captions',
      'export',
    ];
    Future<void> reveal(String id) async {
      final scrollable = find.descendant(
        of: find.byKey(const Key('makerToolLine')),
        matching: find.byType(Scrollable),
      );
      final state = tester.state<ScrollableState>(scrollable);
      final index = order.indexOf(id);
      final target = (index * 65.0 - 60).clamp(
        0.0,
        state.position.maxScrollExtent,
      );
      state.position.jumpTo(target);
      await tester.pump(const Duration(milliseconds: 80));
    }

    for (final id in [
      'template',
      'media',
      'elements',
      'tehreer',
      'ticker',
      'logo',
      'reporter',
      'captions',
    ]) {
      await reveal(id);
      expect(
        find.byKey(Key('makerToolIcon-$id')),
        findsOneWidget,
        reason: '$id must show the user icon',
      );
    }
    for (final id in ['ribbons', 'audio', 'voice', 'export']) {
      await reveal(id);
      expect(
        find.byKey(Key('makerToolIcon-$id')),
        findsNothing,
        reason: '$id keeps its Material icon',
      );
      expect(
        find.descendant(
          of: find.byKey(Key('makerTool-$id')),
          matching: find.byType(Icon),
        ),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('logo panel: cube view + face + parts + permanent sections',
      (tester) async {
    final preset = ChannelPreset.nigraanTv()
      ..logoPath = logoFile.path
      ..logoParts = [
        LogoPart(
          id: 'part0',
          name: 'Part 1',
          sourcePath: logoFile.path,
          box: const LogoBox(x: 0.1, y: 0.1, w: 0.5, h: 0.5),
        ),
      ]
      ..logoPartsSourcePath = logoFile.path;
    await pumpMaker(tester, preset: preset);
    await _openTool(tester, 'logo');
    // View presets write the preset.
    await tester.ensureVisible(find.byKey(const Key('logoView-upar')));
    await tester.tap(find.byKey(const Key('logoView-upar')));
    await _frames(tester);
    expect(preset.logoCubeTilt, 0.85);
    await tester.tap(find.byKey(const Key('logoView-samne')));
    await _frames(tester);
    expect(preset.logoCubeTilt, 0.0);
    // Direction + pedestal.
    await tester.ensureVisible(find.byKey(const Key('logoDir-ccw')));
    await tester.tap(find.byKey(const Key('logoDir-ccw')));
    await _frames(tester);
    expect(preset.logoCubeDirection, 'ccw');
    // Faces.
    expect(find.byKey(const Key('logoFace-front')), findsOneWidget);
    expect(find.byKey(const Key('logoFace-bottom')), findsOneWidget);
    // Parts controls (element model): the dock is in work
    // order; the rotate switch lives in the Ghumao tab and
    // acts on the selected (first) part.
    await tester.ensureVisible(find.byKey(const Key('logoPartsTab-ghumao')));
    await tester.tap(find.byKey(const Key('logoPartsTab-ghumao')));
    await _frames(tester);
    await tester.ensureVisible(find.byKey(const Key('logoPartRotate-0')));
    expect(find.byKey(const Key('logoPartRotate-0')), findsOneWidget);
    await tester.tap(find.byKey(const Key('logoPartRotate-0')));
    await _frames(tester);
    expect(preset.logoParts.single.rotate, isFalse);
    // The save button lives in the Save tab.
    await tester.ensureVisible(find.byKey(const Key('logoPartsTab-save')));
    await tester.tap(find.byKey(const Key('logoPartsTab-save')));
    await _frames(tester);
    expect(find.byKey(const Key('logoPartsSaveButton')), findsOneWidget);
    // Permanent Logo section (not entitled -> manual payment info).
    await tester.ensureVisible(
      find.byKey(const Key('permanentLogoRecheckButton')),
    );
    expect(
      find.byKey(const Key('permanentLogoRecheckButton')),
      findsOneWidget,
    );
    expect(find.textContaining('Rs 200'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ticker panel: loop switch writes the project',
      (tester) async {
    final (_, project) = await pumpMaker(tester);
    await _openTool(tester, 'ticker');
    await tester.ensureVisible(find.byKey(const Key('tickerLoopSwitch')));
    expect(project.tickerLoop, isTrue);
    await tester.tap(find.byKey(const Key('tickerLoopSwitch')));
    await _frames(tester);
    expect(project.tickerLoop, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('audio panel: ducking switch + user ducking icon',
      (tester) async {
    final (_, project) = await pumpMaker(tester);
    await _openTool(tester, 'audio');
    await tester.ensureVisible(find.byKey(const Key('audioDuckingSwitch')));
    expect(project.musicDucking, isTrue);
    await tester.tap(find.byKey(const Key('audioDuckingSwitch')));
    await _frames(tester);
    expect(project.musicDucking, isFalse);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName ==
                'assets/ns_icons/ducking.png',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reporter panel: teleprompter entry exists', (tester) async {
    await pumpMaker(tester);
    await _openTool(tester, 'reporter');
    expect(
      find.byKey(const Key('reporterTeleprompterButton')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName ==
                'assets/ns_icons/teleprompter.png',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('captions panel: timing status + Asal timings action',
      (tester) async {
    final project = NewsProject.create()
      ..voiceoverPath = logoFile.path
      ..voiceoverDurationSec = 10
      ..subtitles = [
        SubtitleLine(text: 'ایک خبر', startSec: 0, endSec: 5),
      ];
    await pumpMaker(tester, project: project);
    await _openTool(tester, 'captions');
    expect(find.byKey(const Key('captionTimingStatus')), findsOneWidget);
    expect(find.textContaining('ESTIMATE'), findsOneWidget);
    expect(find.byKey(const Key('captionsAlignButton')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('teleprompter screen renders fail-soft without a camera',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: TeleprompterScreen(scriptText: 'یہ میرا اسکرپٹ ہے'),
      ),
    );
    await _frames(tester);
    expect(find.byKey(const Key('prompterScriptBand')), findsOneWidget);
    expect(find.byKey(const Key('prompterSpeedSlider')), findsOneWidget);
    expect(
      find.byKey(const Key('prompterTextSizeSlider')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('prompterMirrorSwitch')), findsOneWidget);
    expect(find.byKey(const Key('prompterRecordButton')), findsOneWidget);
    expect(find.textContaining('یہ میرا اسکرپٹ ہے'), findsOneWidget);
    // Camera unavailable in the test host -> honest status, and
    // the record button stays disabled.
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('prompterRecordButton')),
    );
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
