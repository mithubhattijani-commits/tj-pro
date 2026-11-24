/// EnhancePanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// EnhancePanel.
class EnhancePanel extends StatelessWidget {
  final VideoEditorController host;
  const EnhancePanel(this.host, {super.key});

  /// Enhance panel (InShot [TUT11] shape): whole-clip target +
  /// one action. TJ Pro's Enhance is ON-DEVICE HD upscale (no
  /// sign-in gate — InShot's gate is a product fact we replace).
  List<Widget> buildChildren(BuildContext context) {
    final clip = host.clips.isEmpty ? null : host.clips[host.selected];
    return [
      SectionTitle('Enhance — HD (on-device)'),
      const Text(
        'Poori selected clip 2x upscale + sharpen hoti hai '
        '(ffmpeg lanczos + unsharp). Ye ESRGAN AI nahi hai — wo '
        'Photo Editor mein hai.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const SizedBox(height: 8),
      Text(
        clip == null
            ? 'Pehle clip select karein.'
            : 'Target: Clip ${host.selected + 1} '
                '(${clip.effectiveDuration.toStringAsFixed(1)}s — poori clip)',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: host.busy || clip == null ? null : host.enhanceSelectedClipHd,
          icon: const Icon(Icons.high_quality),
          label: const Text('Enhance karo'),
        ),
      ),
      const Divider(height: 32),
    ];
  }
  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
