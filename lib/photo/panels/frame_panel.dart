/// FramePanel of the Photo Editor (Master Plan Phase 7 split).
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

class FramePanel extends StatelessWidget {
  final PhotoEditorController host;
  const FramePanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        host.swatchRow(
          value: host.frameColor,
          onChanged: (c) => host.update(() => host.frameColor = c),
        ),
        PhotoSliderRow(
          label: 'Width %',
          value: host.frameWidthPct,
          min: 1,
          max: 15,
          onChanged: (v) => host.update(() => host.frameWidthPct = v),
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: host.busy ? null : host.applyFrame,
            icon: const Icon(Icons.border_outer),
            label: const Text('Apply frame'),
          ),
        ),
      ],
    );
  }
}
