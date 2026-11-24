/// Video Editor data models (Master Plan Phase 4, step 1).
///
/// [VideoClip] and [TimelineClock] moved here VERBATIM from
/// `video_editor_screen.dart` — same fields, same logic, same
/// defaults. The screen library re-exports this file, so every
/// existing import of the screen keeps working unchanged.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

class VideoClip {
  VideoClip(this.file, this.duration, this.aspectRatio);
  final File file;
  final Duration duration;
  final double aspectRatio; // width / height, from the real video stream
  double trimStart = 0;
  double trimEnd = -1; // -1 = full duration
  double get effectiveEnd =>
      trimEnd < 0 ? duration.inMilliseconds / 1000 : trimEnd;
  double get effectiveDuration => effectiveEnd - trimStart;

  // v1.3.0 (§6.1): a still PHOTO can sit on the timeline as a clip.
  // It is materialised to a real video segment at export
  // (photoClipCommand); [kenBurns] adds the slow zoom.
  bool isPhoto = false;
  bool kenBurns = true;
  bool kbZoomIn = true;

  // v1.4.0 (clip-selected row): per-clip audio state. [volume] is
  // the clip's own gain (1.0 = unchanged) and [muted] silences the
  // clip entirely; both are materialised onto a processed copy of
  // the clip file at export (see _exportInner), the same pattern
  // the reverse / silence-remove passes already use.
  double volume = 1;
  bool muted = false;
  // v1.4.0 Unlink audio: the clip's audio, extracted to its own
  // file; the clip itself is muted and the detached file becomes
  // the music track (when none is picked) so it stays editable.
  String? detachedAudioPath;

  /// A full copy of this clip (same file + every editable field) —
  /// the Duplicate op on the clip-selected row.
  VideoClip copy() {
    final c = VideoClip(file, duration, aspectRatio);
    c.trimStart = trimStart;
    c.trimEnd = trimEnd;
    c.isPhoto = isPhoto;
    c.kenBurns = kenBurns;
    c.kbZoomIn = kbZoomIn;
    c.volume = volume;
    c.muted = muted;
    c.detachedAudioPath = detachedAudioPath;
    return c;
  }
}

/// v1.5.0 (#5/#29/#30): THE one playback clock for the editor.
///
/// v1.4.0 read `controller.value.position` once per build() — with
/// nothing ever listening, the counter froze and three different
/// duration readouts drifted apart. This clock attaches to the
/// selected clip's controller (see _loadPreview) and notifies on
/// every position/playing change; the transport row, the timeline
/// playhead and every total derive from it + the ONE timeline
/// model on the State (clip effective durations summed in order).
class TimelineClock extends ChangeNotifier {
  VideoPlayerController? _controller;

  /// The controller currently driving the clock (null for a photo
  /// clip / no clips).
  VideoPlayerController? get controller => _controller;

  void attach(VideoPlayerController? controller) {
    if (_controller == controller) return;
    _controller?.removeListener(_tick);
    _controller = controller;
    _controller?.addListener(_tick);
    notifyListeners();
  }

  void _tick() => notifyListeners();

  bool get isInitialized => _controller?.value.isInitialized ?? false;

  bool get isPlaying => _controller?.value.isPlaying ?? false;

  /// Raw position inside the selected clip's FILE (seconds).
  double get filePositionSec =>
      (_controller?.value.position.inMilliseconds ?? 0) / 1000.0;

  @override
  void dispose() {
    _controller?.removeListener(_tick);
    _controller = null;
    super.dispose();
  }
}
