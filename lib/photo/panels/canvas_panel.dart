/// CanvasPanel of the Photo Editor (Master Plan Phase 7 split).
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

class CanvasPanel extends StatelessWidget {
  final PhotoEditorController host;
  const CanvasPanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ratio chunein — photo crop nahi hogi, canvas barh jayega '
          '(blur fill). Zoom se photo canvas ke andar chhoti/bari.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        host.ratioRail(
          selected: host.canvasRatio,
          onSelect: (r) => host.update(() => host.canvasRatio = r),
        ),
        PhotoSliderRow(
          label: 'Zoom',
          value: host.canvasZoom,
          min: 40,
          max: 100,
          onChanged: (v) => host.update(() => host.canvasZoom = v),
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: host.busy || host.canvasRatio.$2 == 0 ? null : host.applyCanvas,
            icon: const Icon(Icons.check),
            label: const Text('Apply canvas'),
          ),
        ),
      ],
    );
  }
}
