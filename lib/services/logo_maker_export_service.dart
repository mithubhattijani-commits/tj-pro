/// Logo Maker EXPORT wiring (v1.20.0).
///
/// v1.19.0 wired the Logo Maker into News Studio as PREVIEW +
/// SAVE: its settings (preset / material / depth / bevel /
/// shadow / glow / flat spin) persist on the channel preset
/// (`ChannelPreset.logoMakerSettingsJson`) and style the
/// maker's own preview, but the News Studio export still
/// rendered the logo with the older cube / parts / GS / mov
/// engines. This service closes that gap:
///
/// * When the channel's maker settings EXIST and DIFFER from
///   the maker's defaults, the export logo IS the maker's
///   styled render — the depth painter's static look (depth,
///   material, bevel, shadow, glow) plus its flat spin at the
///   set speed — produced as a directory of square PNG frames
///   in the EXACT `frame_%02d.png` contract the generated cube
///   / parts loops already feed the export graphs with, or as
///   one styled still PNG when the maker's spin is off.
/// * The export services feed those through the SAME graph
///   slots (the parity graph's frames/still inputs, the logo
///   overlay pass's loop/still commands) — same place, same
///   size, same timing. No new graph code exists for this.
/// * Absent or default settings return null at every step, the
///   wiring blocks are skipped wholesale, and the historic logo
///   resolution runs untouched (pinned byte-identical by the
///   v1.20.0 parity tests).
///
/// The maker's spin has NO direction setting — the section's
/// preview turns one way only (its controller sweeps the angle
/// 0 → 2π), and the export frames sweep the same way, so
/// preview and export agree by construction.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

import '../logo/logo_lighting_pass.dart';
import '../logo/logo_maker_section.dart';
import '../news/channel_preset.dart';
import 'logo_loop_service.dart';

/// The maker settings that should steer an export, or null
/// when the export must keep the historic logo engines: the
/// preset carries no maker payload, the payload is corrupt, or
/// it decodes to EXACTLY the maker's defaults (a user who
/// opened the maker and saved without changing anything has
/// not asked for a different export logo).
LogoMakerSettings? logoMakerExportSettings(ChannelPreset preset) {
  final raw = preset.logoMakerSettingsJson.trim();
  if (raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      final settings = LogoMakerSettings.fromJson(decoded);
      return settings == const LogoMakerSettings() ? null : settings;
    }
  } catch (_) {
    // Corrupt payload — the historic logo stands.
  }
  return null;
}

/// Seconds for ONE full flat-spin revolution at [settings]'
/// speed — the section's own definition (its spin controller
/// runs 12000 ms per revolution at speed 1).
double logoMakerSpinPeriodSec(LogoMakerSettings settings) =>
    12.0 / settings.spinSpeed;

/// Frames in the export spin loop: one full revolution at the
/// graph's 12 fps input rate, clamped to the cube loop's own
/// 12–240 range (the same clamp `LogoLoopService` applies to
/// its speed-derived counts). Speed 3 → 48 frames (4 s);
/// speed 1 → 144 (12 s); speed 0.5 would need 288 and clamps
/// to 240 (a 20 s loop — the exported spin then turns a
/// little faster than the preview at the very slowest
/// settings; the Guide says so).
int logoMakerExportFrameCount(LogoMakerSettings settings) =>
    (logoMakerSpinPeriodSec(settings) * kLogoLoopFps)
        .round()
        .clamp(12, 240)
        .toInt();

/// The resolved maker logo for one export: exactly one of
/// [framesDir] (spin on) or [stillPath] (spin off, or the
/// frames render failed and the styled still took over).
class LogoMakerExportLogo {
  const LogoMakerExportLogo({this.framesDir, this.stillPath});

  final String? framesDir;
  final String? stillPath;
}

/// Cache key for the maker frames directory: the base image's
/// identity (file name + size + mtime, or the default tile)
/// plus every settings field that changes a rendered pixel —
/// the cube loop's cache-key discipline, so frames rendered
/// for one look are never reused for another.
String logoMakerExportCacheKey({
  required ChannelPreset preset,
  required LogoMakerSettings settings,
}) {
  var base = 'tile';
  final path = preset.logoMediaKind == 'video'
      ? preset.logoVideoStillPath
      : preset.logoPath;
  if (path != null) {
    try {
      final stat = File(path).statSync();
      final name = path
          .split('/')
          .last
          .replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
      base = '${name}_${stat.size}_${stat.modified.millisecondsSinceEpoch}';
    } catch (_) {
      // Unreadable file — the tile branch of resolveBaseImage
      // will stand in; the key only names a scratch directory.
    }
  }
  final s = settings;
  final baseKey = 'maker_${base}_p${s.presetId}_m${s.materialId}'
      '_d${s.depth}_b${s.bevel}'
      '_sh${s.shadowOn ? 1 : 0}_sb${s.shadowBlur}_so${s.shadowOpacity}'
      '_sp${s.spinOn ? 1 : 0}_ss${s.spinSpeed}'
      '_g${s.glowOn ? 1 : 0}_gi${s.glowIntensity}';
  // v1.25.0: the lighting/camera settings join the key ONLY
  // when they are non-neutral — a neutral combination keeps
  // the exact historic key, so existing cached frame dirs
  // stay valid and the parity story is untouched.
  final lc = s.lightingCamera;
  if (lc.isNeutral) return baseKey;
  return '${baseKey}_lc${lc.hashCode.toUnsigned(32).toRadixString(16)}';
}

class LogoMakerExportService {
  /// The maker's canvas image for [preset] — the SAME
  /// resolution `_openLogoMaker` opens the section with: the
  /// picked image file, or the video logo's still frame, or —
  /// when the channel still runs the default logo — the
  /// initial tile the preview and the generated loops render.
  /// Never null: an unreadable file falls back to the tile.
  static Future<ui.Image> resolveBaseImage(ChannelPreset preset) async {
    final String? stillOrLogo = preset.logoMediaKind == 'video'
        ? preset.logoVideoStillPath
        : preset.logoPath;
    if (stillOrLogo != null && await File(stillOrLogo).exists()) {
      try {
        final bytes = await File(stillOrLogo).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final image = frame.image;
        codec.dispose();
        return image;
      } catch (_) {
        // Undecodable — the tile below stands in, exactly as
        // the maker's own fail-soft open does.
      }
    }
    return LogoLoopService.renderLogoTileTexture(
      initial: preset.name,
      size: kLogoLoopFrameSize,
    );
  }

  /// One styled frame: the depth painter at [angle] on a
  /// square canvas of the cube loops' frame size, so the
  /// frame's geometry contract (square, centred content) is
  /// the one both export graphs already scale and place.
  /// [staticFront]/[staticBack] are the one-time static
  /// renders the spin loop reuses (the v1.19.0 G3 cache
  /// pieces); without them the painter runs its direct layer
  /// path — identical output, proven by the G3 parity tests.
  static Future<ui.Image> renderFrameImage({
    required ui.Image image,
    required LogoMakerSettings settings,
    required double angle,
    ui.Image? staticFront,
    ui.Image? staticBack,
  }) async {
    const size = kLogoLoopFrameSize;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    LogoDepthPainter(
      image: image,
      settings: settings,
      spinAngle: angle,
      staticFront: staticFront,
      staticBack: staticBack,
    ).paint(canvas, const ui.Size(size * 1.0, size * 1.0));
    final picture = recorder.endRecording();
    final frame = await picture.toImage(size, size);
    picture.dispose();
    return frame;
  }

  /// Renders the full spin loop for [settings] into [outDir]
  /// as `frame_%02d.png` files (the generated-loops contract).
  /// One revolution, angles sweeping 0 → 2π the same way the
  /// section's preview controller sweeps, so the loop point
  /// is seamless by construction. Cache-first like
  /// [LogoLoopService.generateFrames]: when every frame
  /// already exists in [outDir] nothing re-renders (the
  /// parity pass and the logo overlay pass of ONE export
  /// share the directory through the cache key).
  static Future<List<File>> generateFrames({
    required ui.Image image,
    required LogoMakerSettings settings,
    required Directory outDir,
  }) async {
    final frames = logoMakerExportFrameCount(settings);
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }
    final existing = <File>[];
    var allExist = true;
    for (var i = 0; i < frames; i++) {
      final f = File(
        p.join(outDir.path, 'frame_${i.toString().padLeft(2, '0')}.png'),
      );
      if (await f.exists()) {
        existing.add(f);
      } else {
        allExist = false;
        break;
      }
    }
    if (allExist) return existing;

    const size = ui.Size(
      kLogoLoopFrameSize * 1.0,
      kLogoLoopFrameSize * 1.0,
    );
    // The expensive layer stack runs ONCE per facing; every
    // frame is then a single transformed draw of a static
    // (the v1.19.0 G3 design), so even the 240-frame slowest
    // loop stays a cheap sweep.
    final front = await renderLogoDepthStatic(
      image: image,
      settings: settings,
      backFacing: false,
      size: size,
    );
    final back = await renderLogoDepthStatic(
      image: image,
      settings: settings,
      backFacing: true,
      size: size,
    );
    try {
      final made = <File>[];
      for (var i = 0; i < frames; i++) {
        var frame = await renderFrameImage(
          image: image,
          settings: settings,
          angle: 2 * math.pi * i / frames,
          staticFront: front,
          staticBack: back,
        );
        // v1.25.0 (G2): the lighting/camera post-pass — the
        // FINAL pass of every frame (depth → spin → lighting,
        // the integration note's order; never baked into the
        // depth statics above). PARITY GATE: a neutral
        // lighting setting skips the pass entirely, so the
        // frame is the historic render bit for bit.
        if (!settings.lightingCamera.isNeutral) {
          final lit = await renderLogoLightingPass(
            image: frame,
            settings: settings.lightingCamera,
          );
          frame.dispose();
          frame = lit;
        }
        try {
          final bytes =
              await frame.toByteData(format: ui.ImageByteFormat.png);
          if (bytes == null) {
            throw StateError('Maker frame render produced no bytes.');
          }
          final file = File(
            p.join(
              outDir.path,
              'frame_${i.toString().padLeft(2, '0')}.png',
            ),
          );
          await file.writeAsBytes(bytes.buffer.asUint8List());
          made.add(file);
        } finally {
          frame.dispose();
        }
      }
      return made;
    } finally {
      front.dispose();
      back.dispose();
    }
  }

  /// The styled still (spin off): the painter at angle 0,
  /// written to [outFile].
  static Future<File> renderStill({
    required ui.Image image,
    required LogoMakerSettings settings,
    required File outFile,
  }) async {
    var frame = await renderFrameImage(
      image: image,
      settings: settings,
      angle: 0,
    );
    // v1.25.0 (G2): the same gated lighting/camera post-pass
    // as the spin frames (see generateFrames).
    if (!settings.lightingCamera.isNeutral) {
      final lit = await renderLogoLightingPass(
        image: frame,
        settings: settings.lightingCamera,
      );
      frame.dispose();
      frame = lit;
    }
    try {
      final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        throw StateError('Maker still render produced no bytes.');
      }
      await outFile.writeAsBytes(bytes.buffer.asUint8List());
      return outFile;
    } finally {
      frame.dispose();
    }
  }

  /// The one-call entry both export logo paths use. Spin on →
  /// the frames directory; the frames render failing falls
  /// back to the styled still (never a failed export); spin
  /// off → the styled still. Returns null only when even the
  /// still could not be rendered — the caller then runs its
  /// historic logo resolution and notes the substitution.
  static Future<LogoMakerExportLogo?> resolveForExport({
    required ChannelPreset preset,
    required LogoMakerSettings settings,
    required Directory dir,
    required int stamp,
  }) async {
    ui.Image? base;
    try {
      base = await resolveBaseImage(preset);
      if (settings.spinOn) {
        try {
          final key = logoMakerExportCacheKey(
            preset: preset,
            settings: settings,
          );
          final framesDir = Directory(p.join(dir.path, 'logo_$key'));
          await generateFrames(
            image: base,
            settings: settings,
            outDir: framesDir,
          );
          return LogoMakerExportLogo(framesDir: framesDir.path);
        } catch (_) {
          // Fall through to the styled still.
        }
      }
      final stillFile = File(p.join(dir.path, 'reel_logo_maker_$stamp.png'));
      await renderStill(image: base, settings: settings, outFile: stillFile);
      return LogoMakerExportLogo(stillPath: stillFile.path);
    } catch (_) {
      return null;
    } finally {
      base?.dispose();
    }
  }
}
