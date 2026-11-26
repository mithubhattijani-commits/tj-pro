/// RemovePanel of the Photo Editor (Master Plan Phase 7 split).
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

class RemovePanel extends StatelessWidget {
  final PhotoEditorController host;
  const RemovePanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Paint with the brush over what you want to remove — '
          'Mi-GAN (ONNX pack) will fill the gap. For small things '
          '(wires, spots, date stamp) gives the cleanest result.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        PhotoSliderRow(
          label: 'Brush size',
          value: host.brushSize * 100,
          min: 2,
          max: 25,
          onChanged: (v) => host.update(() => host.brushSize = v / 100),
        ),
        Row(
          children: [
            host.photoIconChoiceItem(
              icon: Icons.brush,
              label: 'Brush',
              selected: !host.maskErase,
              onTap: () => host.update(() => host.maskErase = false),
            ),
            host.photoIconChoiceItem(
              icon: Icons.auto_fix_off,
              label: 'Eraser',
              selected: host.maskErase,
              onTap: () => host.update(() => host.maskErase = true),
            ),
            host.photoIconChoiceItem(
              icon: Icons.clear_all,
              label: 'Clear',
              selected: false,
              onTap: () => host.update(() => host.strokes.clear()),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: host.busy || host.strokes.isEmpty ? null : host.applyRemove,
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Remove object'),
          ),
        ),
      ],
    );
  }
}
