/// PortraitPanel of the Photo Editor (Master Plan Phase 7 split).
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

class PortraitPanel extends StatelessWidget {
  final PhotoEditorController host;
  const PortraitPanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    final file = host.workingFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (AppConfig.aiToolsEnabled)
              host.aiAction(
                label: 'AI Retouch',
                icon: Icons.face_retouching_natural,
                onPressed: file == null || host.busy ? null : host.beautify,
              ),
            host.plainAction(
              label: 'Bokeh',
              icon: Icons.blur_circular,
              onPressed: file == null || host.busy ? null : host.portraitBokeh,
            ),
            host.plainAction(
              label: 'Light fix',
              icon: Icons.light_mode,
              onPressed: file == null || host.busy ? null : host.lightFix,
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'AI Retouch = face smoothing (ML Kit). Bokeh = Depth '
          'Anything ONNX pack se depth-guided blur. Light fix = '
          'auto levels.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }
}
