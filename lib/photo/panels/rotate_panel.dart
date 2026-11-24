/// RotatePanel of the Photo Editor (Master Plan Phase 7 split).
///
/// Was a method of `_PhotoEditorScreenState` in
/// photo_editor_screen.dart; now a real widget in its own file.
/// All editor state is reached through [PhotoEditorController] —
/// behaviour unchanged.
library;


import 'package:flutter/material.dart';

import '../photo_editor_controller.dart';
import '../widgets/photo_widgets.dart';

class RotatePanel extends StatelessWidget {
  final PhotoEditorController host;
  const RotatePanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    final file = host.workingFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: file == null || host.busy ? null : () => host.rotate(3),
                icon: const Icon(Icons.rotate_left),
                label: const Text('Rotate left'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: file == null || host.busy ? null : () => host.rotate(1),
                icon: const Icon(Icons.rotate_right),
                label: const Text('Rotate right'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: file == null || host.busy ? null : host.flipHorizontal,
                icon: const Icon(Icons.flip),
                label: const Text('Flip horizontal'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: file == null || host.busy ? null : host.flipVertical,
                icon: const Icon(Icons.swap_vert),
                label: const Text('Flip vertical'),
              ),
            ),
          ],
        ),
        const Divider(height: 22),
        const Text('Straighten', style: TextStyle(fontWeight: FontWeight.bold)),
        PhotoSliderRow(
          label: 'Angle',
          value: host.straighten,
          min: -45,
          max: 45,
          onChanged: (v) => host.update(() => host.straighten = v),
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: file == null || host.busy || host.straighten == 0
                ? null
                : host.applyStraighten,
            icon: const Icon(Icons.check),
            label: const Text('Apply straighten'),
          ),
        ),
      ],
    );
  }
}
