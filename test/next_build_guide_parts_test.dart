/// Next build (points #21 + #22 + #23) — functional tests.
///
/// #21: every inventoried tool id (the actual docks/panels —
/// Video Editor panel dispatch + rail, Photo Editor toolbar,
/// News Studio dock, Motion Gallery) has a non-empty guide
/// entry, and the guide sheet really opens with its content.
/// #22: a part row's live preview state follows that part's
/// own rotate switch / speed (the painter the row uses).
/// #23: the 3D rotation style renders measurably different
/// frames than Flat through the SHARED painter — including
/// through generatePartsFrames, the export path.
///
/// Redesign Build 1 (element model): a part is a BOX over a
/// shared master logo; payloads saved by the old slice model
/// (no box) load as NO parts.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/news/logo_parts.dart';
import 'package:tj_pro/news/widgets/rotating_logo.dart';
import 'package:tj_pro/services/logo_parts_service.dart';
import 'package:tj_pro/widgets/tool_guide.dart';

/// A 64×64 part texture: LEFT half opaque red, right half
/// transparent — asymmetric, so rotation (flat or 3D) is
/// plainly visible in the pixels. Centroid ≈ (0.25, 0.5).
Future<ui.Image> _partTexture() async {
  const s = 64;
  final rgba = Uint8List(s * s * 4);
  for (var y = 0; y < s; y++) {
    for (var x = 0; x < s ~/ 2; x++) {
      final o = (y * s + x) * 4;
      rgba[o] = 220;
      rgba[o + 3] = 255;
    }
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, s, s, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

Future<Uint8List> _rgbaOf(ui.Image img) async {
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bd!.buffer.asUint8List();
}

int _diffPixels(Uint8List a, Uint8List b) {
  var n = 0;
  final len = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < len; i += 4) {
    if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      n++;
    }
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('#21 — guide coverage (har tool, asal docks se)', () {
    // Video Editor panel keys — video_editor_panels.dart ki
    // toolPanelChildren dispatch ('clipVolume' Volume hi hai).
    const vePanelKeys = [
      'canvas', 'precut', 'speed', 'audio', 'text', 'colour',
      'effects', 'overlay', 'volume', 'clipVolume', 'aicut',
      'voiceenhance', 'edit', 'enhance', 'stabilizer', 'cutout',
      'mask', 'opacity', 'rotate', 'ease', 'transitions',
    ];
    // Video Editor rail ke instant ops + doors jin ki guide
    // long-press se khulti hai (tool_rows.dart _railGuideIds
    // ke targets).
    const veRailGuideIds = [
      've.canvas', 've.audio', 've.overlay', 've.text',
      've.effects', 've.colour', 've.precut', 've.split',
      've.delete', 've.volume', 've.speed', 've.aicut',
      've.voiceenhance', 've.edit', 've.switch', 've.enhance',
      've.stabilizer', 've.cutout', 've.mask', 've.templates',
      've.opacity', 've.replace', 've.duplicate', 've.rotate',
      've.freeze', 've.capture', 've.reverse', 've.ease',
      'motion',
    ];
    // Photo Editor toolbar keys — _toolbar ki asal list.
    const peKeys = [
      'canvas', 'filter', 'adjust', 'effect', 'background',
      'portrait', 'sticker', 'text', 'pip', 'remove', 'enhance',
      'cutout', 'doodle', 'makeup', 'crop', 'expand', 'frame',
      'rotate',
    ];
    // News Studio dock keys — _toolDefs ki asal list.
    const nsKeys = [
      'template', 'media', 'elements', 'tehreer', 'ticker',
      'ribbons', 'logo', 'reporter', 'audio', 'voice',
      'captions', 'export', 'motion',
    ];

    void expectEntry(String id) {
      final e = toolGuideFor(id);
      expect(e, isNotNull, reason: 'guide entry missing: $id');
      expect(e!.title.trim(), isNotEmpty, reason: '$id title');
      expect(e.what.trim().length, greaterThan(20), reason: '$id what');
      expect(e.steps.length, greaterThanOrEqualTo(2), reason: '$id steps');
      for (final s in e.steps) {
        expect(s.trim(), isNotEmpty, reason: '$id step khaali');
      }
    }

    test('VE panels + rail ops', () {
      for (final k in vePanelKeys) {
        expectEntry(vePanelGuideId(k));
      }
      for (final id in veRailGuideIds) {
        expectEntry(id);
      }
    });

    test('PE toolbar', () {
      for (final k in peKeys) {
        expectEntry('pe.$k');
      }
    });

    test('NS dock + Motion', () {
      for (final k in nsKeys) {
        expectEntry('ns.$k');
      }
      expectEntry('motion');
    });

    test('koi guide entry khaali nahi (poora map)', () {
      for (final id in kToolGuides.keys) {
        expectEntry(id);
      }
    });
  });

  group('#21 — guide sheet asal mein khulti hai', () {
    testWidgets('button se sheet, title + steps ke sath', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ToolGuideButton(guideId: 'ns.logo')),
        ),
      );
      expect(find.byKey(const Key('toolGuideButton-ns.logo')), findsOneWidget);
      await tester.tap(find.byKey(const Key('toolGuideButton-ns.logo')));
      await tester.pumpAndSettle();
      expect(find.text('Logo (Cube + Parts) — Guide'), findsOneWidget);
      expect(find.text('What this tool does'), findsOneWidget);
      expect(find.text('How to use — step by step'), findsOneWidget);
      // Naye (element-model) guide ka asal step — Auto tajweez.
      expect(
        find.textContaining('Suggest parts automatically'),
        findsOneWidget,
      );
    });

    testWidgets('namaloom id par button chhup jata hai', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ToolGuideButton(guideId: 'xx.nope')),
        ),
      );
      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('#22 — part row ka live preview state', () {
    LogoPart partWith({bool rotate = true, double speed = 2}) => LogoPart(
          id: 'p0',
          name: 'Part 1',
          sourcePath: '/nonexistent/logo.png',
          // Box centre (0.25, 0.5) — purana centroid wala point.
          box: const LogoBox(x: 0, y: 0, w: 0.5, h: 1),
          rotate: rotate,
          speedSec: speed,
        );

    test('painter ka angle part ki apni settings se banta hai', () {
      final fast = partWith(speed: 2);
      final slow = partWith(speed: 12);
      const t = 1.5;
      final aFast =
          LogoPartPreviewPainter(part: fast, texture: null, tSec: t).angle;
      final aSlow =
          LogoPartPreviewPainter(part: slow, texture: null, tSec: t).angle;
      expect(aFast, LogoPartsService.partAngleAt(fast, t));
      expect(aSlow, LogoPartsService.partAngleAt(slow, t));
      // Speed badalne se usi waqt ka angle badal jata hai.
      expect((aFast - aSlow).abs(), greaterThan(1.0));
      // Switch OFF → angle hamesha 0, kisi bhi waqt par.
      final off = partWith(rotate: false);
      expect(
        LogoPartPreviewPainter(part: off, texture: null, tSec: t).angle,
        0,
      );
      expect(
        LogoPartPreviewPainter(part: off, texture: null, tSec: 7.3).angle,
        0,
      );
    });

    testWidgets('widget: switch/speed badalte hi preview state badalta hai',
        (tester) async {
      Widget host(LogoPart p) => MaterialApp(
            home: Scaffold(body: LogoPartPreview(part: p, size: 64)),
          );
      LogoPartPreviewPainter painter() => tester
          .widget<CustomPaint>(
            find.byWidgetPredicate(
              (w) => w is CustomPaint && w.painter is LogoPartPreviewPainter,
            ),
          )
          .painter! as LogoPartPreviewPainter;

      await tester.pumpWidget(host(partWith(speed: 2)));
      await tester.pump(const Duration(milliseconds: 700));
      final a1 = painter().angle;
      expect(a1, greaterThan(0.5)); // ghumao chal raha hai

      // Speed 2 → 12: usi loop time par angle chhota ho jata hai.
      final tSecNow = painter().tSec;
      await tester.pumpWidget(host(partWith(speed: 12)));
      await tester.pump();
      final expected = LogoPartsService.partAngleAt(
        partWith(speed: 12),
        painter().tSec,
      );
      expect(painter().angle, closeTo(expected, 0.001));
      expect(painter().tSec, closeTo(tSecNow, 0.05));

      // Switch OFF: preview ruk jata hai — angle 0, harkat band.
      await tester.pumpWidget(host(partWith(rotate: false)));
      await tester.pump();
      expect(painter().angle, 0);
      final frozenT = painter().tSec;
      await tester.pump(const Duration(milliseconds: 500));
      expect(painter().tSec, frozenT); // ticker band — still hai
    });
  });

  group('#23 — 3D style: model + render parity', () {
    test('purana slice-model save khaali load hota hai; naya box save style rakhta hai', () {
      // Old payload: imagePath + centroid, koi box nahi — ye
      // element model mein map nahi ho sakta, parts khaali.
      final old = decodeLogoParts(
        '[{"id":"a","name":"A","imagePath":"/a.png","rotate":true,'
        '"direction":"cw","speedSec":6,"centreX":0.5,"centreY":0.5}]',
      );
      expect(old, isEmpty);
      // Naya round-trip style + box mehfooz rakhta hai.
      final p = LogoPart(
        id: 'b',
        name: 'B',
        sourcePath: '/logo.png',
        box: const LogoBox(x: 0.1, y: 0.1, w: 0.4, h: 0.4),
        rotationStyle: kLogoPartStyle3d,
      );
      final back = decodeLogoParts(encodeLogoParts([p])).single;
      expect(back.rotationStyle, kLogoPartStyle3d);
      expect(back.box, p.box);
      // Namaloom value bhi Flat par girti hai.
      expect(normalizeLogoPartStyle('ulta'), kLogoPartStyleFlat);
      expect(normalizeLogoPartStyle(null), kLogoPartStyleFlat);
      // Variant key style ko bhi gin'ti hai (cache parity).
      final flat = LogoPart(
        id: 'c',
        name: 'C',
        sourcePath: '/logo.png',
        box: const LogoBox(x: 0, y: 0, w: 0.5, h: 1),
      );
      final d3 = flat.copyWith(rotationStyle: kLogoPartStyle3d);
      expect(
        logoPartsVariantKey(sourceStamp: 's', parts: [flat]),
        isNot(logoPartsVariantKey(sourceStamp: 's', parts: [d3])),
      );
    });

    test('3D geometry: 60° par box patla, 0° par bilkul box', () {
      const size = Size(128, 128);
      const full = LogoBox(x: 0, y: 0, w: 1, h: 1);
      final rest = logoPart3DBoxCorners(size: size, box: full, angle: 0);
      expect(rest[0], const Offset(0, 0));
      expect(rest[2], const Offset(128, 128));
      final turned = logoPart3DBoxCorners(
        size: size,
        box: full,
        angle: 1.0471975511965976, // 60°
      );
      final width = turned[1].dx - turned[0].dx;
      expect(width, lessThan(90)); // cos60 ≈ 0.5 → ~64 + perspective
      expect(width, greaterThan(30));
      expect(logoPart3DBrightness(0), 1.0);
      expect(logoPart3DBrightness(1.5707963267948966), closeTo(0.42, 0.01));
    });

    test('render: Flat vs 3D frames pixelon mein mukhtalif', () async {
      final tex = await _partTexture();
      // Master = left-half-red image; the part's box is that
      // left half, so its centre is (0.25, 0.5).
      LogoPart mk(String style) => LogoPart(
            id: 'p0',
            name: 'P',
            sourcePath: '/x.png',
            box: const LogoBox(x: 0, y: 0, w: 0.5, h: 1),
            speedSec: 6,
            rotationStyle: style,
          );
      // t=1.0, speed 6 → 60°. Flat pahiya ghumta hai, 3D side
      // se patla hota hai — frames lazmi alag honge.
      final flatImg = await LogoPartsService.renderPartsFrame(
        parts: [mk(kLogoPartStyleFlat)],
        masterTexture: tex,
        size: 128,
        tSec: 1.0,
      );
      final d3Img = await LogoPartsService.renderPartsFrame(
        parts: [mk(kLogoPartStyle3d)],
        masterTexture: tex,
        size: 128,
        tSec: 1.0,
      );
      final flatPx = await _rgbaOf(flatImg);
      final d3Px = await _rgbaOf(d3Img);
      flatImg.dispose();
      d3Img.dispose();
      tex.dispose();
      expect(_diffPixels(flatPx, d3Px), greaterThan(300));
    });

    test('export path (generatePartsFrames) style parhti hai', () async {
      final tex = await _partTexture();
      final png = await tex.toByteData(format: ui.ImageByteFormat.png);
      tex.dispose();
      final dir = await Directory.systemTemp.createTemp('parts_frames_');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final partFile = File('${dir.path}/master.png');
      await partFile.writeAsBytes(png!.buffer.asUint8List(), flush: true);
      LogoPart mk(String style, String id) => LogoPart(
            id: id,
            name: 'P',
            sourcePath: partFile.path,
            box: const LogoBox(x: 0, y: 0, w: 0.5, h: 1),
            speedSec: 6,
            rotationStyle: style,
          );
      final flatDir = Directory('${dir.path}/flat');
      final d3Dir = Directory('${dir.path}/d3');
      await LogoPartsService.generatePartsFrames(
        parts: [mk(kLogoPartStyleFlat, 'pf')],
        outDir: flatDir,
        size: 64,
      );
      await LogoPartsService.generatePartsFrames(
        parts: [mk(kLogoPartStyle3d, 'pd')],
        outDir: d3Dir,
        size: 64,
      );
      // Poora 12s loop, 12 fps = 144 frames.
      expect(await flatDir.list().length, 144);
      expect(await d3Dir.list().length, 144);
      // Frame 12 = t 1.0s (60°) — export ke frames mein bhi
      // Flat aur 3D ka farq pixelon mein saaf hai.
      Future<Uint8List> framePx(Directory d) async {
        final bytes = await File('${d.path}/frame_12.png').readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final f = await codec.getNextFrame();
        final raw = await _rgbaOf(f.image);
        f.image.dispose();
        return raw;
      }

      final flatPx = await framePx(flatDir);
      final d3Px = await framePx(d3Dir);
      expect(_diffPixels(flatPx, d3Px), greaterThan(100));
    });
  });
}
