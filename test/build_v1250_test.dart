// v1.25.0 — Reveal export (G1) + Lighting/Camera (G2) proofs.
//
// G2 (Lighting/Camera, CHECK #6 integration):
//  - settings: the nested lightingCamera field defaults to
//    NEUTRAL, old payloads (no key) decode to the defaults,
//    corrupt values never throw, and the export gate's
//    default-payload → null parity foundation still holds.
//  - the frames cache key is byte-identical for neutral
//    lighting (historic key) and gains a suffix only when
//    non-neutral — cached unlit frames can never serve a lit
//    combination.
//  - the alpha-preserving lighting pass: the logo's own
//    pixels take the light (bright side toward the light),
//    the transparent surround STAYS transparent (no filled
//    square), the camera grows the silhouette, output is
//    deterministic.
//  - the section: a 6th dock tab "Light" (Spin → Light →
//    Reveal), the checked panel inside it, and a preset tap
//    writes lightingCamera through the one settings path.
//  - the Guide no longer calls the reveal preview-only.
//
// G1 (Reveal intro):
//  - the gate truth table (no settings / no style / unknown
//    style / chosen style);
//  - the frame-count formula (the style's own duration);
//  - the segment command golden (stillSegmentCommand's codec
//    discipline + silent stereo track);
//  - a rendered intro frame: backdrop at progress 0, the
//    settled logo at progress 1 (pixels);
//  - buildSegment fails SOFT without an encoder (null, no
//    throw, frames cleaned) — the export-without-intro path.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/logo/logo_lighting_camera.dart';
import 'package:tj_pro/logo/logo_lighting_pass.dart';
import 'package:tj_pro/logo/logo_maker_section.dart';
import 'package:tj_pro/logo/logo_reveal_backdrops.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/services/ffmpeg_service.dart';
import 'package:tj_pro/services/logo_maker_export_service.dart';
import 'package:tj_pro/services/logo_reveal_intro_service.dart';
import 'package:tj_pro/widgets/tool_guide.dart';

/// A mid-grey block on transparency, centred — grey so the
/// lighting direction is measurable on its own pixels.
Future<ui.Image> _makeGreyBlock() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(50, 50, 100, 100),
    ui.Paint()..color = const ui.Color(0xFF808080),
  );
  final picture = recorder.endRecording();
  return picture.toImage(200, 200);
}

Future<Uint8List> _rgba(ui.Image img) async {
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}

int _px(Uint8List rgba, int width, int x, int y) =>
    (y * width + x) * 4;

int _alphaAt(Uint8List rgba, int width, int x, int y) =>
    rgba[_px(rgba, width, x, y) + 3];

int _opaqueCount(Uint8List rgba) {
  var n = 0;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] > 8) n++;
  }
  return n;
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  group('G2 settings: nested lightingCamera', () {
    test('defaults are the neutral lighting defaults', () {
      const s = LogoMakerSettings();
      expect(s.lightingCamera, LogoLightingCameraSettings.defaults);
      expect(s.lightingCamera.isNeutral, isTrue);
    });

    test('default payload round-trips to EXACTLY the defaults '
        '(the export parity gate foundation)', () {
      final decoded = LogoMakerSettings.fromJson(
        const LogoMakerSettings().toJson(),
      );
      expect(decoded, const LogoMakerSettings());
    });

    test('a pre-v1.25.0 payload (no lightingCamera key) loads '
        'neutral and otherwise untouched', () {
      final old = const LogoMakerSettings(depth: 30).toJson()
        ..remove('lightingCamera');
      final decoded = LogoMakerSettings.fromJson(old);
      expect(decoded, const LogoMakerSettings(depth: 30));
      expect(decoded.lightingCamera.isNeutral, isTrue);
    });

    test('a corrupt lightingCamera value loads the defaults, '
        'never throws', () {
      final payload = const LogoMakerSettings(depth: 30).toJson();
      payload['lightingCamera'] = 'junk';
      final decoded = LogoMakerSettings.fromJson(payload);
      expect(decoded.lightingCamera, LogoLightingCameraSettings.defaults);
      payload['lightingCamera'] = 42;
      expect(
        LogoMakerSettings.fromJson(payload).lightingCamera,
        LogoLightingCameraSettings.defaults,
      );
    });

    test('lighting values round-trip through the preset JSON', () {
      const lc = LogoLightingCameraSettings(
        lightingOn: true,
        lightAngleDeg: 25,
        rimGlow: 0.4,
        cameraZoom: 1.3,
      );
      const s = LogoMakerSettings(lightingCamera: lc);
      final preset = ChannelPreset.nigraanTv();
      preset.logoMakerSettingsJson = jsonEncode(s.toJson());
      expect(logoMakerExportSettings(preset), s);
    });

    test('the gate: a payload differing ONLY in lighting '
        'steers the export; the exact defaults still do not', () {
      final preset = ChannelPreset.nigraanTv();
      preset.logoMakerSettingsJson =
          jsonEncode(const LogoMakerSettings().toJson());
      expect(logoMakerExportSettings(preset), isNull);
      preset.logoMakerSettingsJson = jsonEncode(
        const LogoMakerSettings(
          lightingCamera: LogoLightingCameraSettings(lightingOn: true),
        ).toJson(),
      );
      expect(logoMakerExportSettings(preset), isNotNull);
      expect(
        logoMakerExportSettings(preset)!.lightingCamera.lightingOn,
        isTrue,
      );
    });
  });

  group('G2 cache key parity', () {
    test('neutral lighting keeps the historic key byte-for-byte',
        () {
      final preset = ChannelPreset.nigraanTv();
      final key = logoMakerExportCacheKey(
        preset: preset,
        settings: const LogoMakerSettings(),
      );
      expect(
        key,
        'maker_tile_pgold_spin_mgold_d18.0_b6.0_sh1_sb14.0'
        '_so0.45_sp1_ss1.0_g0_gi0.5',
      );
    });

    test('non-neutral lighting extends the key (unlit cached '
        'frames can never serve a lit combination)', () {
      final preset = ChannelPreset.nigraanTv();
      const neutral = LogoMakerSettings();
      const lit = LogoMakerSettings(
        lightingCamera: LogoLightingCameraSettings(lightingOn: true),
      );
      final neutralKey =
          logoMakerExportCacheKey(preset: preset, settings: neutral);
      final litKey =
          logoMakerExportCacheKey(preset: preset, settings: lit);
      expect(litKey, startsWith('${neutralKey}_lc'));
      expect(litKey, isNot(neutralKey));
    });
  });

  group('G2 the alpha-preserving lighting pass', () {
    test('light falls from the chosen side; the transparent '
        'surround stays transparent', () async {
      final img = await _makeGreyBlock();
      const lc = LogoLightingCameraSettings(
        lightingOn: true,
        lightAngleDeg: 0, // light from the RIGHT
        lightIntensity: 1.0,
        shadowDepth: 1.0,
        rimGlow: 0.0,
      );
      final out = await renderLogoLightingPass(image: img, settings: lc);
      final px = await _rgba(out);
      expect(out.width, 200);
      expect(out.height, 200);
      final right = px[_px(px, 200, 140, 100)];
      final left = px[_px(px, 200, 60, 100)];
      expect(right, greaterThan(left + 10),
          reason: 'the lit side must be brighter than the far side '
              '(the painter\u2019s spec\u2019d falloff over this block '
              'measures ~18 levels at these points)');
      // The corners were transparent in the source: the pass
      // must not fill them (no visible square on the video).
      expect(_alphaAt(px, 200, 4, 4), 0);
      expect(_alphaAt(px, 200, 195, 4), 0);
      expect(_alphaAt(px, 200, 4, 195), 0);
      expect(_alphaAt(px, 200, 195, 195), 0);
      img.dispose();
      out.dispose();
    });

    test('camera zoom grows the silhouette, corners stay '
        'transparent, output is deterministic', () async {
      final img = await _makeGreyBlock();
      const lc = LogoLightingCameraSettings(cameraZoom: 1.6);
      final a = await renderLogoLightingPass(image: img, settings: lc);
      final b = await renderLogoLightingPass(image: img, settings: lc);
      final pa = await _rgba(a);
      final pb = await _rgba(b);
      final src = await _rgba(img);
      expect(_opaqueCount(pa), greaterThan(_opaqueCount(src)));
      expect(_alphaAt(pa, 200, 4, 4), 0);
      expect(_bytesEqual(pa, pb), isTrue);
      img.dispose();
      a.dispose();
      b.dispose();
    });
  });

  group('G1 reveal intro gate + formulas', () {
    test('gate truth table', () {
      expect(LogoRevealIntroService.revealIntroApplies(null), isFalse);
      expect(
        LogoRevealIntroService.revealIntroApplies(
          const LogoMakerSettings(revealStyleId: ''),
        ),
        isFalse,
      );
      expect(
        LogoRevealIntroService.revealIntroApplies(
          const LogoMakerSettings(revealStyleId: 'bogus'),
        ),
        isFalse,
      );
      expect(
        LogoRevealIntroService.revealIntroApplies(
          const LogoMakerSettings(revealStyleId: 'spin_reveal'),
        ),
        isTrue,
      );
      expect(
        LogoRevealIntroService.revealIntroApplies(
          const LogoMakerSettings(),
        ),
        isTrue,
        reason: 'the maker default IS a chosen style (fade_zoom)',
      );
    });

    test('frame count follows the style duration', () {
      const fade = LogoRevealStyle(
        id: 'fade_zoom',
        name: 'Fade Zoom',
        durationMs: 1200,
      );
      const rise = LogoRevealStyle(
        id: 'rise_glow',
        name: 'Rise & Glow',
        durationMs: 1500,
      );
      expect(LogoRevealIntroService.frameCountFor(fade, 30), 36);
      expect(LogoRevealIntroService.frameCountFor(fade, 12), 14);
      expect(LogoRevealIntroService.frameCountFor(rise, 30), 45);
      expect(LogoRevealIntroService.frameCountFor(fade, 1), 2);
    });

    test('segment command golden (default rates)', () {
      final cmd = LogoRevealIntroService.segmentCommand(
        framesPattern: '/f/frame_%03d.png',
        fps: 30,
        durationSec: 1.2,
        output: '/o.mp4',
      );
      expect(
        cmd,
        '-y -framerate 30 -i \'/f/frame_%03d.png\' '
        '-f lavfi -t 1.2 -i anullsrc=channel_layout=stereo:sample_rate=48000 '
        '-vf "fps=30,format=yuv420p" '
        '-map 0:v -map 1:a -shortest '
        '-c:v libx264 -preset veryfast -crf 23 '
        '-c:a aac -ar 48000 -ac 2 \'/o.mp4\'',
      );
    });

    test('segment command golden (explicit bitrates)', () {
      final cmd = LogoRevealIntroService.segmentCommand(
        framesPattern: '/f/frame_%03d.png',
        fps: 30,
        durationSec: 1.5,
        output: '/o.mp4',
        videoBitrateKbps: 8000,
        audioBitrateKbps: 128,
      );
      expect(
        cmd,
        '-y -framerate 30 -i \'/f/frame_%03d.png\' '
        '-f lavfi -t 1.5 -i anullsrc=channel_layout=stereo:sample_rate=48000 '
        '-vf "fps=30,format=yuv420p" '
        '-map 0:v -map 1:a -shortest '
        '-c:v libx264 -preset veryfast -b:v 8000k '
        '-maxrate 12000k -bufsize 16000k '
        '-c:a aac -b:a 128k -ar 48000 -ac 2 \'/o.mp4\'',
      );
    });
  });

  group('G1 intro frames + fail-soft build', () {
    testWidgets('progress 0 shows only the backdrop; progress 1 '
        'shows the settled logo', (tester) async {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawRect(
          const ui.Rect.fromLTWH(0, 0, 100, 100),
          ui.Paint()..color = const ui.Color(0xFFFF0000),
        );
        final picture = recorder.endRecording();
        final logo = await picture.toImage(100, 100);
        picture.dispose();
        const settings = LogoMakerSettings(
          revealStyleId: 'fade_zoom',
          backdropId: 'plain_dark',
        );
        final backdrop = LogoBackdropPainter(
          backdropId: settings.backdropId,
          glowIntensity: settings.backdropGlow,
        );
        final f0 = await LogoRevealIntroService.renderIntroFrame(
          styledLogo: logo,
          settings: settings,
          backdrop: backdrop,
          progress: 0,
          width: 240,
          height: 240,
        );
        final f1 = await LogoRevealIntroService.renderIntroFrame(
          styledLogo: logo,
          settings: settings,
          backdrop: backdrop,
          progress: 1,
          width: 240,
          height: 240,
        );
        final p0 = await _rgba(f0);
        final p1 = await _rgba(f1);
        final centre0 = p0[_px(p0, 240, 120, 120)];
        final centre1 = p1[_px(p1, 240, 120, 120)];
        expect(centre0, lessThan(80),
            reason: 'at progress 0 the logo has not revealed yet');
        expect(centre1, greaterThan(150),
            reason: 'at progress 1 the settled logo fills the centre');
        expect(_alphaAt(p0, 240, 120, 120), 255,
            reason: 'the backdrop fills the frame (opaque intro)');
        logo.dispose();
        f0.dispose();
        f1.dispose();
      });
    });

    testWidgets('buildSegment: a failed encode is a clean null '
        '(export proceeds without the intro); a good encode '
        'returns the segment; frames cleaned either way',
        (tester) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('reveal_intro_');
        try {
          final preset = ChannelPreset.nigraanTv();
          const settings = LogoMakerSettings(revealStyleId: 'fade_zoom');

          // Failure branch (the no-encoder reality on a broken
          // device): null, no throw, frames gone.
          final failed = await LogoRevealIntroService.buildSegment(
            preset: preset,
            settings: settings,
            dir: dir,
            stamp: 7,
            width: 144,
            height: 256,
            fps: 12,
            runFfmpeg: (String command,
                {int? expectedMs,
                void Function(double)? onProgress}) async {
              return FfmpegResult(-1, 'no encoder');
            },
          );
          expect(failed, isNull);
          expect(
            await Directory('${dir.path}/reveal_intro_7').exists(),
            isFalse,
          );

          // Success branch: the encoder writes the segment —
          // it comes back, named for the assembly, and the
          // frames are still cleaned up.
          String? seenCommand;
          final built = await LogoRevealIntroService.buildSegment(
            preset: preset,
            settings: settings,
            dir: dir,
            stamp: 9,
            width: 144,
            height: 256,
            fps: 12,
            runFfmpeg: (String command,
                {int? expectedMs,
                void Function(double)? onProgress}) async {
              seenCommand = command;
              await File('${dir.path}/reel_reveal_intro_9.mp4')
                  .writeAsBytes(const [0, 1, 2, 3]);
              return FfmpegResult(0, '');
            },
          );
          expect(built, isNotNull);
          expect(built!.path, '${dir.path}/reel_reveal_intro_9.mp4');
          expect(seenCommand, contains('frame_%03d.png'));
          expect(seenCommand, contains('anullsrc'));
          expect(
            await Directory('${dir.path}/reveal_intro_9').exists(),
            isFalse,
          );
        } finally {
          if (await dir.exists()) await dir.delete(recursive: true);
        }
      });
    });
  });

  group('G2 section: the Light tab', () {
    testWidgets('dock order is Logo Style Spin Light Reveal Save; '
        'the Light panel writes lightingCamera', (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final img = await _makeGreyBlock();
      LogoMakerSettings? last;
      await tester.pumpWidget(
        MaterialApp(
          home: LogoMakerSection(
            logoImage: img,
            initialSettings: const LogoMakerSettings(spinOn: false),
            onSettingsChanged: (s) => last = s,
            onSave: (_) {},
            onClose: () {},
          ),
        ),
      );
      await tester.pump();

      // Dock order: the six labels appear in enum order. The
      // dock sits in the bottom band of the screen — pick, for
      // each label, the match with the greatest dy (the top
      // bar also carries a "Save" text, which must not count).
      final labels = ['Logo', 'Style', 'Spin', 'Light', 'Reveal', 'Save'];
      Offset dockPos(String label) {
        Offset? best;
        for (final e in find.text(label).evaluate()) {
          final o = tester.getTopLeft(find.byWidget(e.widget));
          if (best == null || o.dy > best.dy) best = o;
        }
        return best!;
      }

      var previousX = -1.0;
      for (final label in labels) {
        final pos = dockPos(label);
        expect(pos.dy, greaterThan(700),
            reason: '$label is in the bottom dock band');
        expect(pos.dx, greaterThan(previousX),
            reason: '$label sits after the previous dock item');
        previousX = pos.dx;
      }

      await tester.ensureVisible(find.text('Light'));
      await tester.pump();
      await tester.tap(find.text('Light'));
      await tester.pump();
      expect(find.text('Lighting Presets'), findsOneWidget);
      expect(find.text('Light Settings'), findsOneWidget);
      expect(find.text('Camera Controls'), findsOneWidget);

      // A preset tap writes the whole lighting settings object
      // through the section's one settings path.
      await tester.ensureVisible(find.text('Studio Soft'));
      await tester.pump();
      await tester.tap(find.text('Studio Soft'));
      await tester.pump();
      expect(last, isNotNull);
      expect(last!.lightingCamera.lightingOn, isTrue);
      expect(last!.lightingCamera.lightAngleDeg, -50);
      expect(last!.lightingCamera.rimGlow, 0.15);
      expect(tester.takeException(), isNull);
      img.dispose();
    });
  });

  group('guide honesty', () {
    test('ns.logo_maker no longer calls the reveal preview-only '
        'and documents the intro + the Light tab', () {
      final entry = kToolGuides['ns.logo_maker']!;
      final all = <String>[
        entry.what,
        ...entry.steps,
        ...entry.tips,
      ].join('\n');
      expect(all.contains('not drawn into the NEWS video export'),
          isFalse);
      expect(all.contains('preview-only'), isFalse);
      expect(all.contains('one-time intro'), isTrue);
      expect(all.contains('Light tab'), isTrue);
    });
  });
}
