/// The alpha-preserving lighting/camera pass (v1.25.0).
///
/// The checked [LogoLightingCameraPainter] paints its effect
/// over the WHOLE canvas: its directional shade and highlight
/// are full-canvas gradients. That is exactly right on an
/// opaque frame (the maker's preview box, a full video frame),
/// but the logo frames the exports overlay are TRANSPARENT
/// PNGs — painting the painter straight onto one would fill
/// the see-through surround with a semi-opaque gradient and
/// the overlay would show a visible square on the video.
///
/// This helper therefore composes AROUND the painter, using
/// nothing but the painter itself:
///
/// 1. The painter runs on the source image → the lit frame
///    (the painter's own output, untouched).
/// 2. A white silhouette of the source (its alpha, nothing
///    else) runs through the painter a second time with the
///    lighting switched off — the SAME camera transform moves
///    the silhouette exactly as it moved the logo.
/// 3. The lit frame is masked by that moved silhouette
///    (BlendMode.dstIn): the effect survives precisely where
///    the (transformed) logo is, and the surround stays fully
///    transparent.
///
/// The caller owns the input image; the returned image is a
/// fresh one the caller must dispose. Intermediate renders
/// are disposed here.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'logo_lighting_camera.dart';

/// Renders [image] through [settings]' lighting + camera,
/// preserving the image's own (camera-transformed) alpha.
/// [settings] must be non-neutral — the callers gate on
/// `settings.isNeutral` so the historic path never pays for
/// this pass at all.
Future<ui.Image> renderLogoLightingPass({
  required ui.Image image,
  required LogoLightingCameraSettings settings,
}) async {
  final size = Size(image.width.toDouble(), image.height.toDouble());

  Future<ui.Image> paintWith(
    ui.Image source,
    LogoLightingCameraSettings s,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    LogoLightingCameraPainter(
      logoImage: source,
      settings: s,
      background: Colors.transparent,
    ).paint(canvas, size);
    final picture = recorder.endRecording();
    final out = await picture.toImage(image.width, image.height);
    picture.dispose();
    return out;
  }

  // 1 — the lit frame, exactly as the painter defines it.
  final lit = await paintWith(image, settings);

  // 2 — the source's alpha as a white silhouette, moved by
  // the same camera (lighting off, so only the transform and
  // the plain draw remain).
  ui.Image? silhouette;
  ui.Image? movedSilhouette;
  try {
    silhouette = await _whiteSilhouette(image);
    movedSilhouette = await paintWith(
      silhouette,
      settings.copyWith(lightingOn: false),
    );
  } finally {
    silhouette?.dispose();
  }

  // 3 — mask the lit frame by the moved silhouette.
  try {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(lit, Offset.zero, Paint());
    canvas.drawImage(
      movedSilhouette,
      Offset.zero,
      Paint()..blendMode = BlendMode.dstIn,
    );
    final picture = recorder.endRecording();
    final out = await picture.toImage(image.width, image.height);
    picture.dispose();
    return out;
  } finally {
    lit.dispose();
    movedSilhouette.dispose();
  }
}

/// [image]'s alpha as a solid white image (the colour is
/// irrelevant — only the alpha channel is read, as a mask).
Future<ui.Image> _whiteSilhouette(ui.Image image) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImage(
    image,
    Offset.zero,
    Paint()
      ..colorFilter = const ColorFilter.mode(
        Colors.white,
        BlendMode.srcIn,
      ),
  );
  final picture = recorder.endRecording();
  final out = await picture.toImage(image.width, image.height);
  picture.dispose();
  return out;
}
