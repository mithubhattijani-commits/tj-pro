/// DoodlePanel of the Photo Editor (Master Plan Phase 7 split).
///
/// Was a method of `_PhotoEditorScreenState` in
/// photo_editor_screen.dart; now a real widget in its own file.
/// All editor state is reached through [PhotoEditorController] —
/// behaviour unchanged.
library;


import 'package:flutter/material.dart';

import '../photo_editor_controller.dart';
import '../widgets/panel_helpers.dart';
import '../widgets/photo_widgets.dart';

class DoodlePanel extends StatelessWidget {
  final PhotoEditorController host;
  const DoodlePanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Preview par ungli se draw karein — Apply par photo mein '
          'bake ho jayega (Undo maujood hai).',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        host.swatchRow(
          value: host.doodleColor,
          onChanged: (c) => host.update(() => host.doodleColor = c),
        ),
        PhotoSliderRow(
          label: 'Brush size',
          value: host.brushSize * 100,
          min: 1,
          max: 20,
          onChanged: (v) => host.update(() => host.brushSize = v / 100),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => host.update(() => host.strokes.clear()),
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: host.busy || host.strokes.isEmpty ? null : host.applyDoodle,
                icon: const Icon(Icons.check),
                label: const Text('Apply doodle'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
