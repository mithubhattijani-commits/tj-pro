/// VolumePanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// VolumePanel.
class VolumePanel extends StatelessWidget {
  final VideoEditorController host;
  const VolumePanel(this.host, {super.key});

  /// v1.4.0 clip-selected row › Volume: the SELECTED clip's own
  /// gain + mute (materialised at export — see _exportInner) and
  /// its unlink state.
  /// v1.5.0 Volume panel (InShot [TUT9]): ONE % slider (max 200%
  /// — best-knowledge, InShot's max was never verified on video),
  /// Mute, Denoise (the op lives here, not in Voice Enhance) and
  /// Extract audio. The slider applies the gain to the LIVE
  /// preview as well as the export model.
  List<Widget> buildChildren(BuildContext context) {
    final clip = host.clips.isEmpty ? null : host.clips[host.selected];
    if (clip == null) {
      return const [
        Text(
          'Select a clip from the timeline first.',
          style: TextStyle(color: Colors.grey),
        ),
      ];
    }
    return [
      SectionTitle('Clip ${host.selected + 1} — volume'),
      ProSlider(
        label: 'Clip volume',
        value: clip.volume.clamp(0, 2),
        min: 0,
        max: 2,
        divisions: 40,
        onChanged: (v) {
          host.update(() => clip.volume = v);
          unawaited(
            host.controller?.setVolume(clip.muted ? 0 : v) ??
                Future<void>.value(),
          );
        },
      ),
      SwitchListTile(
        title: const Text('Mute clip'),
        subtitle: const Text('This clip\'s sound will not be in the export.'),
        value: clip.muted,
        onChanged: (v) {
          host.update(() => clip.muted = v);
          unawaited(
            host.controller?.setVolume(v ? 0 : clip.volume) ??
                Future<void>.value(),
          );
        },
      ),
      if (clip.detachedAudioPath != null)
        Text(
          'Audio is unlinked: ${p.basename(clip.detachedAudioPath!)} '
          '(is on a separate track).',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      const Text(
        'The volume applies to this clip only — the other clips\' sound '
        'stays in its place.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      SectionTitle('Audio ops'),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: host.busy
                  ? null
                  : () =>
                      unawaited(host.enhanceSelectedClipAudio(voice: false)),
              icon: const Icon(Icons.noise_control_off, size: 18),
              label: const Text('Denoise'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: host.busy ? null : host.extractClipAudio,
              icon: const Icon(Icons.audio_file, size: 18),
              label: const Text('Extract audio'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: host.busy ? null : host.unlinkSelectedClipAudio,
          icon: const Icon(Icons.link_off, size: 18),
          label: const Text('Unlink audio (alag track)'),
        ),
      ),
      const Divider(height: 32),
    ];
  }
  @override
  Widget build(BuildContext context) =>
      panelDrillOrColumn(host, buildChildren(context));
}
