import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:image/image.dart' as img;

/// A foreground-confidence mask for one photo.
///
/// [confidences] is a flat row-major list of values 0.0–1.0 (1.0 = subject).
/// Its length is always [width] * [height].
class MaskResult {
  const MaskResult({
    required this.confidences,
    required this.width,
    required this.height,
  });

  final List<double> confidences;
  final int width;
  final int height;
}

/// On-device ML Kit helpers. No network, no keys, no cloud.
///
/// Subject segmentation may fetch its model once through Google Play services
/// on first use (free); afterwards it works fully offline. Face detection is
/// bundled and works offline immediately.
class AiService {
  /// Segment the foreground subject of [imageFile].
  ///
  /// Tries ML Kit subject segmentation first (works on any subject), then
  /// selfie segmentation (people only). Throws if neither produces a usable
  /// mask — the caller must surface that error, never silently fake a result.
  static Future<MaskResult> segmentSubject(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final decoded = await compute(_decodeSize, bytes);
    final int w = decoded[0];
    final int h = decoded[1];
    if (w <= 0 || h <= 0) {
      throw Exception('Could not read this photo.');
    }

    // 1) Subject segmentation (any subject).
    final subjectSegmenter = SubjectSegmenter(
      options: SubjectSegmenterOptions(
        enableForegroundBitmap: false,
        enableForegroundConfidenceMask: true,
        enableMultipleSubjects: SubjectResultOptions(
          enableConfidenceMask: false,
          enableSubjectBitmap: false,
        ),
      ),
    );
    try {
      final result = await subjectSegmenter.processImage(
        InputImage.fromFilePath(imageFile.path),
      );
      final mask = result.foregroundConfidenceMask;
      // The Dart plugin does not expose the mask dimensions, so only trust a
      // mask whose length matches the image exactly.
      if (mask != null && mask.length == w * h) {
        return MaskResult(confidences: mask, width: w, height: h);
      }
    } catch (_) {
      // Fall through to selfie segmentation.
    } finally {
      await subjectSegmenter.close();
    }

    // 2) Selfie segmentation (people only). With enableRawSizeMask false the
    // native side rescales the mask to the input image size.
    final selfieSegmenter = SelfieSegmenter(mode: SegmenterMode.single);
    try {
      final mask = await selfieSegmenter.processImage(
        InputImage.fromFilePath(imageFile.path),
      );
      if (mask != null && mask.confidences.isNotEmpty) {
        return MaskResult(
          confidences: mask.confidences,
          width: mask.width,
          height: mask.height,
        );
      }
    } catch (_) {
      // Fall through to the error below.
    } finally {
      await selfieSegmenter.close();
    }

    throw Exception(
      'AI could not find a subject in this photo. '
      'Try a photo with a clearer subject.',
    );
  }

  /// Detect faces in [imageFile]. Returns bounding boxes in image pixel
  /// coordinates (origin = top-left). Empty list = no face found (not an
  /// error — the caller shows "No face found").
  static Future<List<ui.Rect>> detectFaces(File imageFile) async {
    final detector = FaceDetector(options: FaceDetectorOptions());
    try {
      final faces = await detector.processImage(
        InputImage.fromFilePath(imageFile.path),
      );
      return faces.map((f) => f.boundingBox).toList();
    } finally {
      await detector.close();
    }
  }
}

/// Top-level for compute(): returns [width, height] of an encoded image
/// (or [0, 0] if it cannot be decoded).
List<int> _decodeSize(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return [0, 0];
  return [decoded.width, decoded.height];
}
