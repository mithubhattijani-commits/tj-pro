/// VoiceEnhancePanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// VoiceEnhancePanel.
class VoiceEnhancePanel extends StatelessWidget {
  final VideoEditorController host;
  const VoiceEnhancePanel(this.host, {super.key});

  /// Voice Enhance panel: the enhance-voice op (AudioEnhanceService
  /// voice chain). Denoise is NOT duplicated here — it lives in
  /// Volume, per InShot [TUT9].
  List<Widget> buildChildren(BuildContext context) {
    return [
      SectionTitle('Voice Enhance'),
      const Text(
        'Selected clip ki awaz saaf + wazeh: noise kam, voice '
        'band EQ, compression aur loudness normalise — on-device '
        '(AudioEnhanceService).',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: host.busy || host.clips.isEmpty
              ? null
              : () => unawaited(host.enhanceSelectedClipAudio(voice: true)),
          icon: const Icon(Icons.record_voice_over),
          label: const Text('Voice Enhance lagayein'),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Sirf denoise chahiye to Volume panel ka Denoise use karein.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }
  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
