// v1.20.0 — Logo Maker EXPORT wiring tests.
//
// (a) PARITY: with absent/default maker settings the export
//     graph is byte-identical to the v1.19.0 graph (goldens
//     captured from the pre-wiring builder), and the settings
//     gate returns null so the wiring blocks never run.
// (b) STYLED FRAMES: the maker's depth/material look is
//     provably inside the rendered export frames (pixels).
// (c) SPIN: spin-on frames change over time; spin-off yields
//     a styled still, not frames.
// (d) FULL PATH: ChannelPreset.logoMakerSettingsJson → gate →
//     base image → export frames/still.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/live/parity_template.dart';
import 'package:tj_pro/logo/logo_maker_section.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/services/logo_maker_export_service.dart';

import 'logo_maker_export_goldens.dart';

/// A blue block logo on transparency (asymmetric, non-square)
/// — blue so a GOLD material shift is detectable in pixels.
Future<ui.Image> _makeTestLogo() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(10, 20, 100, 40),
    ui.Paint()..color = const ui.Color(0xFF3366CC),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(10, 20, 30, 40),
    ui.Paint()..color = const ui.Color(0xFF99BBFF),
  );
  final picture = recorder.endRecording();
  return picture.toImage(120, 80);
}

Future<Uint8List> _rgba(ui.Image img) async {
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}

Future<Uint8List> _fileRgba(File f) async {
  final bytes = await f.readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final rgba = await _rgba(frame.image);
  frame.image.dispose();
  codec.dispose();
  return rgba;
}

int _opaqueCount(Uint8List px) {
  var n = 0;
  for (var i = 3; i < px.length; i += 4) {
    if (px[i] > 8) n++;
  }
  return n;
}

/// Warm gold-ish pixels: strong red, mid green, low blue.
int _warmCount(Uint8List px) {
  var n = 0;
  for (var i = 0; i < px.length; i += 4) {
    if (px[i + 3] > 200 && px[i] > 180 && px[i + 1] > 110 && px[i + 2] < 130) {
      n++;
    }
  }
  return n;
}

bool _bytesDiffer(Uint8List a, Uint8List b) {
  if (a.length != b.length) return true;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return true;
  }
  return false;
}

void main() {
  group('(a) parity: the export graph is byte-identical', () {
    ParityAssets assetsFor(ParityVariant variant) {
      final g = ParityGeometry(1080, 1920, variant: variant);
      return ParityAssets(
        geometry: g,
        ribbons: [
          for (var i = 0; i < 3; i++)
            ParityRibbonAssets(bg: File('/r$i.png'), y: i * 100.0),
        ],
        capBar: File('/capbar.png'),
        capDate: File('/capdate.png'),
        topRibbon: null,
      );
    }

    final start = DateTime(2026, 11, 26, 10, 30);
    final rebuilt = <String, String>{
      'final3_frames': buildParityTemplateCommand(
        input: '/in.mp4',
        output: '/out.mp4',
        assets: assetsFor(ParityVariant.final3),
        logoFramesDir: '/frames',
        clockFontFile: null,
        exportStart: start,
      ),
      'final3_still': buildParityTemplateCommand(
        input: '/in.mp4',
        output: '/out.mp4',
        assets: assetsFor(ParityVariant.final3),
        logoStillPng: '/logo.png',
        clockFontFile: null,
        exportStart: start,
      ),
      'final3_gs': buildParityTemplateCommand(
        input: '/in.mp4',
        output: '/out.mp4',
        assets: assetsFor(ParityVariant.final3),
        logoGsPath: '/gs.mov',
        clockFontFile: null,
        exportStart: start,
      ),
      'final3_pingpong': buildParityTemplateCommand(
        input: '/in.mp4',
        output: '/out.mp4',
        assets: assetsFor(ParityVariant.final3),
        logoPingPongPath: '/cycle.mov',
        clockFontFile: null,
        exportStart: start,
      ),
      'final3_nologo': buildParityTemplateCommand(
        input: '/in.mp4',
        output: '/out.mp4',
        assets: assetsFor(ParityVariant.final3),
        clockFontFile: null,
        exportStart: start,
      ),
      'final3_frames_clock_bitrate': buildParityTemplateCommand(
        input: '/in.mp4',
        output: '/out.mp4',
        assets: assetsFor(ParityVariant.final3),
        logoFramesDir: '/frames',
        clockFontFile: '/font.ttf',
        exportStart: start,
        videoBitrateKbps: 8000,
      ),
      'classic2_frames': buildParityTemplateCommand(
        input: '/in.mp4',
        output: '/out.mp4',
        assets: assetsFor(ParityVariant.classic2),
        logoFramesDir: '/frames',
        clockFontFile: null,
        exportStart: start,
      ),
    };

    for (final key in kParityGoldens.keys) {
      test('golden $key', () {
        expect(rebuilt[key], kParityGoldens[key]);
      });
    }
  });

  group('(a)+(d) the settings gate', () {
    test('empty payload → null (historic logo engines)', () {
      final preset = ChannelPreset.nigraanTv();
      preset.logoMakerSettingsJson = '';
      expect(logoMakerExportSettings(preset), isNull);
    });

    test('corrupt payload → null', () {
      final preset = ChannelPreset.nigraanTv();
      preset.logoMakerSettingsJson = '{not json';
      expect(logoMakerExportSettings(preset), isNull);
    });

    test('payload of EXACTLY the defaults → null', () {
      final preset = ChannelPreset.nigraanTv();
      preset.logoMakerSettingsJson =
          jsonEncode(const LogoMakerSettings().toJson());
      expect(logoMakerExportSettings(preset), isNull);
    });

    test('one changed field → the settings steer the export', () {
      const custom = LogoMakerSettings(depth: 30, materialId: 'chrome');
      final preset = ChannelPreset.nigraanTv();
      preset.logoMakerSettingsJson = jsonEncode(custom.toJson());
      expect(logoMakerExportSettings(preset), custom);
    });
  });

  group('frame count formula (the cube clamp convention)', () {
    test('speed 3 → 48 frames (4 s revolution)', () {
      expect(
        logoMakerExportFrameCount(const LogoMakerSettings(spinSpeed: 3)),
        48,
      );
    });

    test('speed 1 → 144 frames (12 s revolution)', () {
      expect(
        logoMakerExportFrameCount(const LogoMakerSettings(spinSpeed: 1)),
        144,
      );
    });

    test('speed 2 → 72 frames (6 s revolution)', () {
      expect(
        logoMakerExportFrameCount(const LogoMakerSettings(spinSpeed: 2)),
        72,
      );
    });

    test('speed 0.5 clamps to 240 frames (20 s loop cap)', () {
      expect(
        logoMakerExportFrameCount(const LogoMakerSettings(spinSpeed: 0.5)),
        240,
      );
    });
  });

  group('(b) styled renders carry the look (pixel proof)', () {
    late ui.Image logo;
    late Directory tmp;

    setUp(() async {
      logo = await _makeTestLogo();
      tmp = await Directory.systemTemp.createTemp('maker_export_b');
    });

    tearDown(() async {
      logo.dispose();
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    const plain = LogoMakerSettings(
      materialId: 'none',
      depth: 0,
      bevel: 0,
      shadowOn: false,
      glowOn: false,
    );

    test('depth 40 covers strictly more pixels than depth 0', () async {
      final flatFile = File('${tmp.path}/flat.png');
      final deepFile = File('${tmp.path}/deep.png');
      await LogoMakerExportService.renderStill(
        image: logo,
        settings: plain,
        outFile: flatFile,
      );
      await LogoMakerExportService.renderStill(
        image: logo,
        settings: plain.copyWith(depth: 40),
        outFile: deepFile,
      );
      final flat = _opaqueCount(await _fileRgba(flatFile));
      final deep = _opaqueCount(await _fileRgba(deepFile));
      expect(deep, greaterThan(flat));
    });

    test('gold material warms the pixels; none does not', () async {
      final noneFile = File('${tmp.path}/none.png');
      final goldFile = File('${tmp.path}/gold.png');
      await LogoMakerExportService.renderStill(
        image: logo,
        settings: plain,
        outFile: noneFile,
      );
      await LogoMakerExportService.renderStill(
        image: logo,
        settings: plain.copyWith(materialId: 'gold'),
        outFile: goldFile,
      );
      final nonePx = await _fileRgba(noneFile);
      final goldPx = await _fileRgba(goldFile);
      expect(_bytesDiffer(nonePx, goldPx), isTrue);
      expect(_warmCount(goldPx), greaterThan(_warmCount(nonePx)));
      expect(_warmCount(goldPx), greaterThan(50));
    });

    test('full styled look (depth+gold+shadow+glow) grows coverage',
        () async {
      final plainFile = File('${tmp.path}/p.png');
      final styledFile = File('${tmp.path}/s.png');
      await LogoMakerExportService.renderStill(
        image: logo,
        settings: plain,
        outFile: plainFile,
      );
      await LogoMakerExportService.renderStill(
        image: logo,
        settings: const LogoMakerSettings(
          materialId: 'gold',
          depth: 40,
          bevel: 12,
          shadowOn: true,
          shadowBlur: 20,
          glowOn: true,
          glowIntensity: 0.8,
        ),
        outFile: styledFile,
      );
      final p = _opaqueCount(await _fileRgba(plainFile));
      final s = _opaqueCount(await _fileRgba(styledFile));
      expect(s, greaterThan(p));
    });
  });

  group('(c) spin behaviour', () {
    late ui.Image logo;
    late Directory tmp;

    setUp(() async {
      logo = await _makeTestLogo();
      tmp = await Directory.systemTemp.createTemp('maker_export_c');
    });

    tearDown(() async {
      logo.dispose();
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('spin frames change over time (front → edge → back)', () async {
      const settings = LogoMakerSettings(spinSpeed: 3, depth: 24);
      final outDir = Directory('${tmp.path}/frames');
      final files = await LogoMakerExportService.generateFrames(
        image: logo,
        settings: settings,
        outDir: outDir,
      );
      expect(files, hasLength(48));
      expect(await File('${outDir.path}/frame_00.png').exists(), isTrue);
      expect(await File('${outDir.path}/frame_47.png').exists(), isTrue);

      final front = await _fileRgba(files[0]);
      final edge = await _fileRgba(files[12]); // quarter turn
      final back = await _fileRgba(files[24]); // half turn
      // The flat spin narrows the logo edge-on…
      expect(_opaqueCount(edge), lessThan(_opaqueCount(front) ~/ 2));
      // …and the back face renders differently from the front.
      expect(_bytesDiffer(front, back), isTrue);
      expect(_bytesDiffer(front, edge), isTrue);
    });

    test('frame generation is cache-first (no re-render)', () async {
      const settings = LogoMakerSettings(spinSpeed: 3);
      final outDir = Directory('${tmp.path}/frames2');
      await LogoMakerExportService.generateFrames(
        image: logo,
        settings: settings,
        outDir: outDir,
      );
      final first = File('${outDir.path}/frame_00.png');
      final mtime = await first.lastModified();
      await LogoMakerExportService.generateFrames(
        image: logo,
        settings: settings,
        outDir: outDir,
      );
      expect(await first.lastModified(), mtime);
    });
  });

  group('(d) full path: preset → gate → export logo', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('maker_export_d');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    Future<File> writeLogoFile() async {
      final img = await _makeTestLogo();
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      final f = File('${tmp.path}/channel_logo.png');
      await f.writeAsBytes(bytes!.buffer.asUint8List());
      return f;
    }

    test('spin on: preset settings produce the frames directory', () async {
      final logoFile = await writeLogoFile();
      const settings = LogoMakerSettings(spinSpeed: 3, depth: 30);
      final preset = ChannelPreset.nigraanTv()
        ..logoPath = logoFile.path
        ..logoMediaKind = 'image'
        ..logoMakerSettingsJson = jsonEncode(settings.toJson());

      final parsed = logoMakerExportSettings(preset);
      expect(parsed, settings);

      final resolved = await LogoMakerExportService.resolveForExport(
        preset: preset,
        settings: parsed!,
        dir: tmp,
        stamp: 42,
      );
      expect(resolved, isNotNull);
      expect(resolved!.framesDir, isNotNull);
      expect(resolved.stillPath, isNull);
      final frames = await Directory(resolved.framesDir!)
          .list()
          .where((e) => e.path.endsWith('.png'))
          .length;
      expect(frames, logoMakerExportFrameCount(settings));
    });

    test('spin off: preset settings produce a styled still', () async {
      final logoFile = await writeLogoFile();
      const settings = LogoMakerSettings(spinOn: false, depth: 30);
      final preset = ChannelPreset.nigraanTv()
        ..logoPath = logoFile.path
        ..logoMediaKind = 'image'
        ..logoMakerSettingsJson = jsonEncode(settings.toJson());

      final resolved = await LogoMakerExportService.resolveForExport(
        preset: preset,
        settings: logoMakerExportSettings(preset)!,
        dir: tmp,
        stamp: 43,
      );
      expect(resolved, isNotNull);
      expect(resolved!.stillPath, isNotNull);
      expect(resolved.framesDir, isNull);
      final still = File(resolved.stillPath!);
      expect(await still.exists(), isTrue);
      // The still is the 512×512 export frame with real content.
      final codec =
          await ui.instantiateImageCodec(await still.readAsBytes());
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 512);
      expect(frame.image.height, 512);
      expect(_opaqueCount(await _rgba(frame.image)), greaterThan(1000));
      frame.image.dispose();
      codec.dispose();
    });

    test('base image: picked logo decodes; no logo falls back to the tile',
        () async {
      final logoFile = await writeLogoFile();
      final preset = ChannelPreset.nigraanTv()
        ..logoPath = logoFile.path
        ..logoMediaKind = 'image';
      final fromFile =
          await LogoMakerExportService.resolveBaseImage(preset);
      expect(fromFile.width, 120);
      expect(fromFile.height, 80);
      fromFile.dispose();

      final bare = ChannelPreset.nigraanTv();
      final tile = await LogoMakerExportService.resolveBaseImage(bare);
      expect(tile.width, 512);
      expect(tile.height, 512);
      tile.dispose();
    });
  });
}
