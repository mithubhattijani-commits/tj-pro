/// Build 13 — frame proofs (assets for BUILD13-REPORT.md).
/// Renders, with the app's own painters/widgets:
/// - the Logo Cube at the three VIEW presets (Samne/Upar/Neeche)
/// - a Logo Parts animation frame from the real UTV fixture
/// - the Maker (timeline + transport) and the Teleprompter
///   surfaces as widget captures
/// into ~/workspace/tj-pro-build/tool-tests/build13/.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/news/logo_parts.dart';
import 'package:tj_pro/services/logo_loop_service.dart';
import 'package:tj_pro/services/logo_parts_service.dart';

const _outDir = '/home/hatch/workspace/tj-pro-build/tool-tests/build13';

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

Future<void> _writePng(String name, ui.Image img) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  await File('$_outDir/$name').writeAsBytes(bd!.buffer.asUint8List());
}

Future<ui.Image> _texturedLogo() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  const s = 256.0;
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, s, s),
    ui.Paint()..color = const ui.Color(0xFF0B3D91),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 170, s, 60),
    ui.Paint()..color = const ui.Color(0xFFD92323),
  );
  final tp = TextPainter(
    text: const TextSpan(
      text: 'TJ',
      style: TextStyle(
        fontSize: 110,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, const Offset(55, 30));
  final pic = recorder.endRecording();
  return pic.toImage(256, 256);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Directory(_outDir).create(recursive: true);
    _mockPathProvider(_outDir);
    SharedPreferences.setMockInitialValues({});
  });

  test('cube view presets render (Samne / Upar Se / Neeche Se)', () async {
    final texture = await _texturedLogo();
    for (final (name, tilt) in [
      ('samne', 0.0),
      ('upar', 0.85),
      ('neeche', -0.85),
    ]) {
      final png = await LogoLoopService.renderLogoCubeFrame(
        texture: texture,
        angle: 0.6,
        size: 384,
        tiltX: tilt,
      );
      await File('$_outDir/cube-view-$name.png').writeAsBytes(png);
    }
    texture.dispose();
  });

  test('parts animation frame from the UTV fixture', () async {
    const fixture =
        '/home/hatch/workspace/user/media_library/image/e0/e0b686d3623a5ba7a1b64c459124077c49e8b3008e4ec5cae7f1bd471f97c8b4.jpg';
    final bytes = await File(fixture).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final detected = splitLogoRgba(
      rgba: bd!.buffer.asUint8List(),
      width: img.width,
      height: img.height,
      maxParts: 4,
    );
    expect(detected.length, greaterThanOrEqualTo(2));
    final partsDir = Directory('$_outDir/parts-frame-src');
    await partsDir.create(recursive: true);
    final parts = <LogoPart>[];
    for (var i = 0; i < detected.length; i++) {
      final d = detected[i];
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        d.rgba,
        d.width,
        d.height,
        ui.PixelFormat.rgba8888,
        done.complete,
      );
      final pimg = await done.future;
      final png = await pimg.toByteData(format: ui.ImageByteFormat.png);
      pimg.dispose();
      final f = File('${partsDir.path}/part_$i.png');
      await f.writeAsBytes(png!.buffer.asUint8List());
      parts.add(
        LogoPart(
          id: 'part$i',
          name: 'Part ${i + 1}',
          imagePath: f.path,
          rotate: i.isEven,
          direction: i == 2 ? 'ccw' : 'cw',
          speedSec: i == 0 ? 4 : 6,
          centreX: d.centreX,
          centreY: d.centreY,
        ),
      );
    }
    final textures = await LogoPartsService.loadPartTextures(parts);
    final frameImg = await LogoPartsService.renderPartsFrame(
      parts: parts,
      textures: textures,
      size: 512,
      tSec: 1.0,
    );
    await _writePng('parts-frame-t1.png', frameImg);
    frameImg.dispose();
    for (final t in textures.values) {
      t.dispose();
    }
  });

  // NOTE: full-screen widget captures (Maker / Teleprompter)
  // were attempted and hang in this host's headless rasterizer
  // (toImage never completes); those surfaces are proven by
  // build13_panels_test.dart instead. Recorded honestly in
  // BUILD13-REPORT.md.
}
