// v1.24.0 (G1) — Logo Clip integration proofs:
//
// * the checked core file's own suite lives in
//   logo_clip_gemini_test.dart (26 tests, byte-identical
//   file); here we prove the INTEGRATION: the Save panel
//   carries "Export Logo Clip", the clip view opens inside
//   the section seeded from the maker settings, Back returns
//   to the maker, and the panel's own Save still saves.
// * the export service renders real frames to disk
//   (streamed, counted, sized) and its encode step fails
//   CLEANLY (a StateError with the reason) where no FFmpeg
//   exists — never a silent or half-made clip.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/logo/logo_clip.dart';
import 'package:tj_pro/logo/logo_maker_section.dart';
import 'package:tj_pro/services/logo_clip_export_service.dart';

Future<ui.Image> _makeTestImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(8, 12, 24, 16),
    Paint()..color = const Color(0xFFCC6633),
  );
  canvas.drawRect(
    const Rect.fromLTWH(8, 12, 10, 16),
    Paint()..color = const Color(0xFF3366CC),
  );
  final picture = recorder.endRecording();
  return picture.toImage(40, 40);
}

void _mockPathProvider() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async => '/tmp/tj_pro_overflow_tmp',
  );
  // FFmpegKit subscribes to its event channel at first use;
  // unmocked, that subscription's MissingPluginException is
  // reported as an uncaught services error and fails the
  // test before the encode call itself can throw (which the
  // export service then converts to its StateError contract).
  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter.arthenica.com/ffmpeg_kit_event'),
    (MethodCall call) async => null,
  );
  // The method channel must FAIL FAST: a null result makes
  // the plugin wait for a session-completion event that
  // never arrives (the export would hang, not fail). A
  // PlatformException mirrors the unmocked missing-plugin
  // behaviour — the call throws, the service converts it.
  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter.arthenica.com/ffmpeg_kit'),
    (MethodCall call) async =>
        throw PlatformException(code: 'unavailable_in_tests'),
  );
}

Widget _harness(
  ui.Image image, {
  LogoMakerSettings? settings,
  void Function(LogoMakerSettings)? onSave,
}) {
  return MaterialApp(
    home: LogoMakerSection(
      logoImage: image,
      initialSettings: settings,
      onSave: onSave ?? (_) {},
      onSettingsChanged: (_) {},
      onClose: () {},
    ),
  );
}

Future<void> _openSavePanel(WidgetTester tester) async {
  // The dock's Save item (the top bar's Save is the FIRST
  // 'Save' text in the tree; the dock's is the last).
  final dockSave = find.text('Save').last;
  await tester.ensureVisible(dockSave);
  await tester.pump();
  await tester.tap(dockSave);
  await tester.pump();
}

void main() {
  setUpAll(() {
    _mockPathProvider();
    Directory('/tmp/tj_pro_overflow_tmp').createSync(recursive: true);
  });

  testWidgets('the Save panel carries Save logo + Export Logo Clip, '
      'and its Save still fires onSave', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final image = await _makeTestImage();
    LogoMakerSettings? saved;
    await tester.pumpWidget(_harness(image, onSave: (s) => saved = s));
    await tester.pump();
    await _openSavePanel(tester);
    expect(find.byKey(const Key('logoMakerPanelSaveButton')), findsOneWidget);
    expect(find.byKey(const Key('logoMakerExportClipButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('logoMakerPanelSaveButton')));
    await tester.pump();
    expect(saved, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Export Logo Clip opens the clip view inside the '
      'section, seeded from the maker settings', (tester) async {
    // 390 wide (a common real phone): the checked preview's
    // Spin row ('Spin after reveal' + switch) overflows by
    // ~21px at 360 in the TEST font, whose glyphs are a full
    // em wide; in the device font that row is ~130px of text
    // with ~85px of headroom at 360. The checked file stays
    // byte-identical, so the proof runs at 390.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final image = await _makeTestImage();
    await tester.pumpWidget(
      _harness(
        image,
        settings: const LogoMakerSettings(
          revealStyleId: 'bounce_in',
          backdropId: 'neon_grid',
          backdropGlow: 0.9,
        ),
      ),
    );
    await tester.pump();
    await _openSavePanel(tester);
    final clipButton = find.byKey(const Key('logoMakerExportClipButton'));
    await tester.ensureVisible(clipButton);
    await tester.pump();
    await tester.tap(clipButton);
    // The styled static renders async, then the preview lands.
    for (var i = 0; i < 20 && find.byType(LogoClipPreview).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(LogoClipPreview), findsOneWidget);
    // Seeded chips: the maker's reveal + backdrop are the
    // clip's starting selection.
    expect(find.text('Bounce In'), findsWidgets);
    expect(find.text('Neon Grid'), findsWidgets);
    expect(find.byKey(const Key('logoMakerClipExportButton')), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Back returns to the maker, Save panel still open.
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    expect(find.byType(LogoClipPreview), findsNothing);
    expect(find.byKey(const Key('logoMakerExportClipButton')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('generateClipFrames streams real frames to disk; '
      'exportClip fails cleanly without an encoder', (tester) async {
    // EVERYTHING runs inside runAsync: awaiting dart:io
    // futures in the testWidgets body (a fake-async zone)
    // deadlocks — the real event loop never gets to complete
    // them.
    await tester.runAsync(() async {
      final image = await _makeTestImage();
      const settings = LogoClipSettings(
        durationSec: 3,
        aspectId: 'square',
        revealStyleId: 'fade_zoom',
      );
      final dir = await Directory.systemTemp.createTemp('logo_clip_test_');
      try {
        await _framesProof(image, settings, dir);
      } finally {
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });
  });
}

Future<void> _framesProof(
  ui.Image image,
  LogoClipSettings settings,
  Directory dir,
) async {
      final framesDir = Directory('${dir.path}/frames');
      var lastProgress = 0.0;
      final files = await LogoClipExportService.generateClipFrames(
        logoImage: image,
        settings: settings,
        outDir: framesDir,
        framesPerSecond: 10,
        onProgress: (f) => lastProgress = f,
      );
      // 3s at 10fps = 30 frames, numbered in order.
      expect(files.length, 30);
      expect(lastProgress, 1.0);
      for (var i = 0; i < files.length; i++) {
        expect(await files[i].exists(), isTrue);
        expect(await files[i].length(), greaterThan(1000));
        expect(
          files[i].path.endsWith('frame_${i.toString().padLeft(3, '0')}.png'),
          isTrue,
        );
      }
      // Frames are the settings' output size (the PNG header
      // carries it at bytes 16-24), and the reveal actually
      // animates: the first frame (logo still revealing)
      // differs from the last (settled logo).
      final firstBytes = await files.first.readAsBytes();
      final pngWidth =
          (firstBytes[16] << 24) | (firstBytes[17] << 16) |
              (firstBytes[18] << 8) | firstBytes[19];
      final pngHeight =
          (firstBytes[20] << 24) | (firstBytes[21] << 16) |
              (firstBytes[22] << 8) | firstBytes[23];
      expect(pngWidth, 1080);
      expect(pngHeight, 1080);
      final lastBytes = await files.last.readAsBytes();
      expect(firstBytes, isNot(equals(lastBytes)));

      // No FFmpegKit exists in the test environment: the
      // encode must surface as a StateError, and the frames
      // directory must be cleaned up either way. (Caught
      // manually — expectLater inside runAsync deadlocks.)
      Object? exportError;
      try {
        await LogoClipExportService.exportClip(
          logoImage: image,
          settings: settings,
          workDir: Directory('${dir.path}/export'),
        );
      } catch (e) {
        exportError = e;
      }
      expect(exportError, isA<StateError>());
      expect(await Directory('${dir.path}/export/frames').exists(), isFalse);
}
