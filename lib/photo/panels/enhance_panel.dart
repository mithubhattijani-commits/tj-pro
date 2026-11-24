/// EnhancePanel of the Photo Editor (Master Plan Phase 7 split).
///
/// Was a method of `_PhotoEditorScreenState` in
/// photo_editor_screen.dart; now a real widget in its own file.
/// All editor state is reached through [PhotoEditorController] —
/// behaviour unchanged.
library;


import '../../app_config.dart';
import 'package:flutter/material.dart';

import '../photo_editor_controller.dart';
import '../widgets/panel_helpers.dart';
import '../widgets/photo_widgets.dart';

class EnhancePanel extends StatelessWidget {
  final PhotoEditorController host;
  const EnhancePanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    final file = host.workingFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'One-tap photo improvements — on-device. AI Enhance HD '
          'ke ilawa sab FREE hain.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        PhotoSliderRow(
          label: 'Sharpen',
          value: host.sharpenAmount,
          min: 0,
          max: 100,
          onChanged: (v) => host.update(() => host.sharpenAmount = v),
        ),
        PhotoSliderRow(
          label: 'Denoise',
          value: host.denoiseAmount,
          min: 0,
          max: 100,
          onChanged: (v) => host.update(() => host.denoiseAmount = v),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            host.plainAction(
              label: 'Sharpen',
              icon: Icons.blur_off,
              onPressed: file == null || host.busy ? null : host.sharpen,
            ),
            host.plainAction(
              label: 'Denoise',
              icon: Icons.grain,
              onPressed: file == null || host.busy ? null : host.denoise,
            ),
            host.plainAction(
              label: 'Enlarge 2x',
              icon: Icons.zoom_out_map,
              onPressed: file == null || host.busy ? null : host.enlarge,
            ),
            host.plainAction(
              label: 'Color Fix',
              icon: Icons.color_lens,
              onPressed: file == null || host.busy ? null : host.colorFix,
            ),
            if (AppConfig.aiToolsEnabled)
              host.aiAction(
                label: 'Auto-enhance',
                icon: Icons.auto_fix_high,
                onPressed: file == null || host.busy ? null : host.autoEnhance,
              ),
            host.plainAction(
              label: 'AI Enhance HD',
              icon: Icons.high_quality,
              onPressed: file == null || host.busy ? null : host.aiEnhanceHd,
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Tip: Denoise pehle, phir Sharpen. AI Enhance HD '
          'Real-ESRGAN pack hai — photos ke liye best, text distort '
          'ho sakta hai.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }
}
