/// CutoutPanel of the Photo Editor (Master Plan Phase 7 split).
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

class CutoutPanel extends StatelessWidget {
  final PhotoEditorController host;
  const CutoutPanel(this.host, {super.key});

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
                label: 'Cutout',
                icon: Icons.content_cut,
                onPressed: file == null || host.busy ? null : host.removeBackground,
              ),
            host.plainAction(
              label: 'HQ Cutout',
              icon: Icons.high_quality,
              onPressed: file == null || host.busy ? null : host.hqCutout,
            ),
            host.photoIconChoiceItem(
              icon: Icons.auto_fix_off,
              label: 'Eraser',
              selected: host.paintMode == 'erase',
              onTap: () => host.update(() {
                host.paintMode = host.paintMode == 'erase' ? null : 'erase';
                host.strokes.clear();
              }),
            ),
            host.photoIconChoiceItem(
              icon: Icons.image,
              label: 'Replace BG',
              selected: false,
              onTap: () => host.openTool('background'),
            ),
          ],
        ),
        if (host.paintMode == 'erase') ...[
          PhotoSliderRow(
            label: 'Eraser size',
            value: host.brushSize * 100,
            min: 2,
            max: 25,
            onChanged: (v) => host.update(() => host.brushSize = v / 100),
          ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: host.busy || host.strokes.isEmpty ? null : host.applyEraser,
              icon: const Icon(Icons.check),
              label: const Text('Apply eraser'),
            ),
          ),
        ],
        const Divider(height: 22),
        const Text('Outline', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        host.swatchRow(
          value: host.outlineColor,
          onChanged: (c) => host.update(() => host.outlineColor = c),
        ),
        PhotoSliderRow(
          label: 'Width',
          value: host.outlineWidth,
          min: 2,
          max: 30,
          onChanged: (v) => host.update(() => host.outlineWidth = v),
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: file == null || host.busy ? null : host.applyOutline,
            icon: const Icon(Icons.border_outer),
            label: const Text('Apply outline'),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Cutout = ML Kit (default). HQ Cutout = BiRefNet ONNX '
          'pack — kinare zyada saaf. Transparency preview mein '
          'checkerboard dikhta hai.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }
}
