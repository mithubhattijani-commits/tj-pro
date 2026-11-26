/// Transport row of the Video Editor (Master Plan Phase 4 split).
///
/// Was `_transportRow` inside the editor State; now a real widget
/// in its own file. All editor state is reached through
/// [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../../theme.dart';
import '../video_editor_controller.dart';
import 'editor_stage.dart';

/// Play/pause, skip, time readout and the undo/redo/fullscreen
/// buttons under the stage.
class TransportRow extends StatelessWidget {
  final VideoEditorController host;
  const TransportRow(this.host, {super.key});

  /// v1.5.0 transport row — BELOW the preview (v1.4.0 overlaid it on
  /// the stage, hiding the frame's bottom, #10). Everything reads
  /// the ONE clock + timeline model: undo / redo, plain play/pause
  /// (no gold circle), current / total from [_globalPositionSec] /
  /// [_totalDurationSec], keyframe toggle, fullscreen. Rebuilds on
  /// every clock tick — the counter RUNS (#30).
  @override
  Widget build(BuildContext context) {
    String fmt(double sec) {
      final m = sec ~/ 60;
      final ss = (sec % 60).toStringAsFixed(1).padLeft(4, '0');
      return '$m:$ss';
    }

    return AnimatedBuilder(
      animation: host.clock,
      builder: (context, _) {
        final ctrl = host.controller;
        final ready = ctrl != null && ctrl.value.isInitialized;
        final playing = host.clock.isPlaying;
        return Container(
          height: 46,
          color: const Color(0xFF121212),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Undo',
                onPressed: host.undoStack.isEmpty ? null : host.undo,
                icon: const Icon(Icons.undo, color: Colors.white, size: 20),
              ),
              IconButton(
                tooltip: 'Redo',
                onPressed: host.redoStack.isEmpty ? null : host.redo,
                icon: const Icon(Icons.redo, color: Colors.white, size: 20),
              ),
              const Spacer(),
              // v1.14.0 T1 (A14): ±1-frame step buttons flank
              // play — frame-accurate cutting in one tap.
              IconButton(
                key: const Key('tpFrameBack'),
                tooltip: '1 frame back',
                onPressed: host.clips.isEmpty
                    ? null
                    : () => host.stepFrame(-1),
                icon: const Icon(Icons.chevron_left,
                    color: Colors.white, size: 22),
              ),
              IconButton(
                tooltip: playing ? 'Pause' : 'Play',
                onPressed: !ready
                    ? null
                    : () {
                        if (playing) {
                          ctrl.pause();
                        } else {
                          ctrl.play();
                        }
                      },
                icon: Icon(
                  playing ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              IconButton(
                key: const Key('tpFrameNext'),
                tooltip: '1 frame forward',
                onPressed: host.clips.isEmpty
                    ? null
                    : () => host.stepFrame(1),
                icon: const Icon(Icons.chevron_right,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 8),
              // v1.15.0 G1.6: the readout must NEVER truncate
              // ("0:2…" hid the exact position the user was about
              // to cut at). FittedBox scales the full text down a
              // touch on narrow screens instead of ellipsizing —
              // the whole "position / total" always stays visible.
              // v1.14.0 T1 (A14): Timecode mode (timeline header ka
              // TC chip) renders H:MM:SS:FF at the export fps;
              // plain mode keeps the old m:ss.s.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    host.timecodeOn
                        ? '${TimelineMath.formatTimecode(host.globalPositionSec, host.exportFps)} / ${TimelineMath.formatTimecode(host.totalDurationSec, host.exportFps)}'
                        : '${fmt(host.globalPositionSec)} / ${fmt(host.totalDurationSec)}',
                    key: const Key('tpTimeText'),
                    style:
                        const TextStyle(color: Colors.white, fontSize: 12),
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Keyframes on/off',
                onPressed: () {
                  host.update(() => host.proKeyframes = !host.proKeyframes);
                  host.setStatus(
                    host.proKeyframes ? 'Keyframes ON.' : 'Keyframes OFF.',
                  );
                },
                icon: Icon(
                  Icons.diamond,
                  color: host.proKeyframes ? TjProTheme.gold : Colors.white54,
                  size: 20,
                ),
              ),
              IconButton(
                tooltip: 'Fullscreen',
                onPressed: ready ? host.openFullscreen : null,
                icon: const Icon(
                  Icons.fullscreen,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
