/// Motion Graphics Studio — Build M1 frame proofs.
///
/// Renders every seed template through the EXPORT path
/// (renderMotionFramePng — the shared evaluator + painter) at
/// three scene times and proves, from the actual pixels:
///   * frames are real pictures (many colours, mostly opaque),
///   * the animation actually MOVES (early and late frames of
///     the same template differ),
/// and writes the PNGs to
/// ~/workspace/tj-pro-build/tool-tests/motion-m1/ for the M1
/// report. The live preview uses the identical painter, so
/// these frames ARE the preview's frames (parity by
/// construction — the Logo Cube rule).
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/motion/motion_render.dart';
import 'package:tj_pro/motion/motion_templates.dart';

const _outDir = '/home/hatch/workspace/tj-pro-build/tool-tests/motion-m1';

Future<({int distinct, int opaque})> _pixelStats(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final img = frame.image;
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  final colors = <int>{};
  var opaque = 0;
  // Sample every 8th pixel — plenty for a liveliness proof.
  for (var i = 0; i + 3 < bytes.length; i += 32) {
    final a = bytes[i + 3];
    if (a > 200) opaque++;
    colors.add(
      (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2],
    );
  }
  img.dispose();
  return (distinct: colors.length, opaque: opaque);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Directory(_outDir).create(recursive: true);
  });

  for (final t in MotionTemplates.all) {
    test('frame proof: ${t.id} renders + animates', () async {
      final d = t.durationSec;
      final times = [0.15 * d, 0.5 * d, 0.9 * d];
      final frames = <Uint8List>[];
      for (final time in times) {
        frames.add(await renderMotionFramePng(
          t.scene,
          time,
          width: 640,
          height: 360,
        ));
      }
      for (var i = 0; i < frames.length; i++) {
        expect(frames[i].length, greaterThan(1500),
            reason: '${t.id} frame $i suspiciously small');
        final stats = await _pixelStats(frames[i]);
        expect(stats.distinct, greaterThan(8),
            reason: '${t.id} frame $i looks blank/flat');
        expect(stats.opaque, greaterThan(5000),
            reason: '${t.id} frame $i mostly transparent');
      }
      // The scene must visibly change across its life.
      expect(frames[0], isNot(equals(frames[2])),
          reason: '${t.id} does not animate');
      // Keep the evidence: all three times for the news intro,
      // the middle frame for everything else.
      await File('$_outDir/${t.id}_mid.png').writeAsBytes(frames[1]);
      if (t.id == 'breaking_news_intro') {
        await File('$_outDir/${t.id}_early.png').writeAsBytes(frames[0]);
        await File('$_outDir/${t.id}_late.png').writeAsBytes(frames[2]);
      }
    });
  }

  test('frame proof: full-size 1280x720 render (parity size)', () async {
    final png = await renderMotionFramePng(
      MotionTemplates.breakingNewsIntro.scene,
      3.0,
      width: 1280,
      height: 720,
    );
    final stats = await _pixelStats(png);
    expect(stats.distinct, greaterThan(20));
    await File('$_outDir/breaking_news_intro_720p.png')
        .writeAsBytes(png);
  });
}
