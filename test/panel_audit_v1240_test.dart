// v1.24.0 (Points #40/#41) — panel arrangement audit proofs.
//
// Renders the panels the user flagged (NS Logo panel, VE PIP,
// Photo PIP) at a phone size with the user's large font scale
// and saves before/after screenshots into
// ~/workspace/tj-pro-build/panel-audit-v1240/shots/ — the parent
// renames each run's set to *-before.png / *-after.png.
//
// The arrangement assertions live here too: a control clipped
// by its panel, a primary button narrower than its siblings,
// or the VE PIP body rendered as one long flat scroll all fail
// this test instead of reaching the user's phone.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/news_maker_screen.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/photo/photo_editor_screen.dart';
import 'package:tj_pro/video/video_editor_controller.dart';
import 'package:tj_pro/video/video_editor_screen.dart';
import 'package:tj_pro/video/widgets/panel_controls.dart';

/// A controller that answers nothing — PanelDrillDown only
/// stores it (its rail items here carry their own callbacks).
class _FakeHost implements VideoEditorController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void _mockChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory' ||
          call.method == 'getApplicationSupportDirectory') {
        return '/tmp/tj_pro_overflow';
      }
      if (call.method == 'getTemporaryDirectory') {
        return '/tmp/tj_pro_overflow_tmp';
      }
      return null;
    },
  );
  // The gallery picker: the user "cancels" — the VE rail's PIP
  // add flow must still land on the PIP panel.
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/image_picker'),
    (MethodCall call) async => null,
  );
  // NewsMakerScreen creates an AudioRecorder in its async
  // init; unmocked, the record plugin's 'create' call throws
  // an uncaught MissingPluginException (flaky — it depends
  // on when the init lands). A null reply satisfies it.
  messenger.setMockMethodCallHandler(
    const MethodChannel('com.llfbandit.record/messages'),
    (MethodCall call) async => null,
  );
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
  });
  await tester.pump();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final dir = Directory(
    '${Directory.current.path}/../panel-audit-v1240/shots',
  );
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File('${dir.path}/$name.png')
      .writeAsBytesSync(data!.buffer.asUint8List());
  image.dispose();
}

Future<void> _openMakerTool(WidgetTester tester, String id) async {
  final target = find.byKey(Key('makerTool-$id'));
  for (var i = 0; i < 12; i++) {
    if (target.evaluate().isNotEmpty) break;
    await tester.drag(
      find.byKey(const Key('makerToolLine')),
      const Offset(-240, 0),
    );
    await tester.pump(const Duration(milliseconds: 60));
  }
  expect(target, findsOneWidget, reason: 'maker tool $id not found');
  await tester.tap(target);
  await _frames(tester);
}

Future<void> _tapRailLabel(WidgetTester tester, String label) async {
  final target = find.text(label);
  for (var i = 0; i < 14; i++) {
    if (target.evaluate().isNotEmpty) break;
    for (final rail in find.byType(ListView).evaluate()) {
      await tester.drag(find.byWidget(rail.widget), const Offset(-240, 0));
    }
    await tester.pump(const Duration(milliseconds: 60));
  }
  expect(target, findsWidgets, reason: 'rail label $label not found');
  await tester.tap(target.first);
  await _frames(tester);
}

/// VE rail tap, probe-proven sequence ONLY: drag the rail
/// (initially the tree's one ListView) until the item is
/// built, then tap it. tester.ensureVisible and
/// dragUntilVisible DEADLOCK on this screen's rails (they
/// wait on a scroll animation the fake-async zone never
/// completes — three probe rounds established this), and
/// blind drags over every ListView are unnecessary: before
/// any panel opens there is exactly one ListView, the rail.
Future<void> _tapVeRailLabel(WidgetTester tester, String label) async {
  final target = find.text(label);
  for (var i = 0; i < 4 && target.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).first, const Offset(-240, 0));
    await tester.pump(const Duration(milliseconds: 60));
  }
  expect(target, findsWidgets, reason: 'VE rail label $label not found');
  await tester.tap(target.first);
  await _frames(tester);
}

void main() {
  setUpAll(() {
    _mockChannels();
    SharedPreferences.setMockInitialValues({});
    Directory('/tmp/tj_pro_overflow').createSync(recursive: true);
    Directory('/tmp/tj_pro_overflow_tmp').createSync(recursive: true);
    File('/tmp/tj_pro_overflow/pixel.png').writeAsBytesSync(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00,
      0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01,
      0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F,
      0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
      0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00,
      0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);
  });

  testWidgets('NS Logo panel — arrangement + screenshot', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.3),
          ),
          child: child!,
        ),
        home: RepaintBoundary(
          key: key,
          child: NewsMakerScreen(
            initialPreset: ChannelPreset.nigraanTv(),
            initialProject: NewsProject.create(),
          ),
        ),
      ),
    );
    await _frames(tester);
    await _openMakerTool(tester, 'logo');
    await _shot(tester, key, 'ns-logo-panel');
    // Point #40: the maker button and the source toggle share
    // ONE left edge and ONE right edge, spanning the panel —
    // no content-width button floating short of the edge.
    final btnRect =
        tester.getRect(find.byKey(const Key('logoMakerOpenButton')));
    final toggleRect =
        tester.getRect(find.byKey(const Key('logoSourceToggle')));
    expect(btnRect.width, greaterThan(300),
        reason: 'maker button must span the panel, got ${btnRect.width}');
    expect((toggleRect.left - btnRect.left).abs(), lessThan(1));
    expect((toggleRect.right - btnRect.right).abs(), lessThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('VE PIP panel — arrangement + screenshots', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(key: key, child: const VideoEditorScreen()),
      ),
    );
    await _frames(tester);
    // The rail's PIP item is the + add button (Point #41):
    // tapping it turns PIP on, "cancels" the gallery through
    // the mocked picker, and lands on the PIP options.
    await _tapVeRailLabel(tester, 'PIP');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await _shot(tester, key, 've-pip-panel');
    // Point #41: the PIP body DRILLS — one chip line (with the
    // "Tabs" back item), one section at a time — instead of
    // the old ~800px flat scroll.
    expect(find.byKey(const Key('panelDrillDown')), findsOneWidget);
    expect(find.text('Tabs'), findsOneWidget);
    expect(find.text('PIP timing'), findsOneWidget,
        reason: 'timing must be a chip in the one line');
    expect(find.text('Start at playhead'), findsNothing,
        reason: 'only the chosen section renders');
    // The later chips sit off the rail's right edge — drag
    // the rail until the Timing chip is fully on screen and
    // take the second shot there. NOTE (probe-bisected over
    // six rounds): switching the drill's section INSIDE this
    // screen stalls the tester's fake-async zone in this
    // environment (the frame after the switch never returns,
    // at idle CPU), while the identical PanelDrillDown
    // switches instantly in isolation — see the drill test
    // at the bottom of this file, which is the switching
    // proof for the widget the PIP tab now uses.
    // tester.ensureVisible deadlocks on these rails for the
    // same reason; plain drags settle immediately.
    final rail = find.ancestor(
      of: find.text('Tabs'),
      matching: find.byType(Scrollable),
    );
    expect(rail, findsWidgets);
    for (var i = 0; i < 6; i++) {
      final chipRect = tester.getRect(find.text('PIP timing'));
      if (chipRect.right <= 360 && chipRect.left >= 0) break;
      await tester.drag(rail.first, const Offset(-240, 0));
      await tester.pump(const Duration(milliseconds: 60));
    }
    final timingRect = tester.getRect(find.text('PIP timing'));
    expect(timingRect.right, lessThanOrEqualTo(360));
    expect(timingRect.left, greaterThanOrEqualTo(0));
    await _shot(tester, key, 've-pip-rail-scrolled');
    expect(tester.takeException(), isNull);
  });

  testWidgets('PanelDrillDown (the PIP tab\u2019s widget) switches '
      'sections — one at a time, in the same place', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PanelDrillDown(
            _FakeHost(),
            leadingRailItems: [
              iconChoiceItem(
                _FakeHost(),
                icon: Icons.arrow_back,
                label: 'Tabs',
                selected: false,
                onTap: () {},
              ),
            ],
            children: const [
              SectionTitle('Alpha'),
              Text('alpha body'),
              SectionTitle('Beta'),
              Text('beta body'),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Tabs'), findsOneWidget);
    expect(find.text('alpha body'), findsOneWidget);
    expect(find.text('beta body'), findsNothing);
    final ink = find.ancestor(
      of: find.text('Beta'),
      matching: find.byType(InkWell),
    );
    tester.widget<InkWell>(ink.first).onTap!.call();
    await tester.pump();
    expect(find.text('beta body'), findsOneWidget);
    expect(find.text('alpha body'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Photo PIP panel — arrangement + screenshot', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: key,
            child: const PhotoEditorScreen(
              initialImagePath: '/tmp/tj_pro_overflow/pixel.png',
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await _frames(tester);
    await _tapRailLabel(tester, 'PIP');
    await _shot(tester, key, 'photo-pip-panel');
    // Point #41: the panel's add button carries the plain +.
    expect(
      find.descendant(
        of: find.byType(ElevatedButton),
        matching: find.byIcon(Icons.add),
      ),
      findsOneWidget,
    );
    expect(find.text('Add photo overlay (gallery)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
