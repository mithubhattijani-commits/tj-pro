/// RotatePanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// RotatePanel.
class RotatePanel extends StatelessWidget {
  final VideoEditorController host;
  const RotatePanel(this.host, {super.key});

  /// Rotate panel (InShot [TUT9]): exactly ROTATE + FLIP.
  List<Widget> buildChildren(BuildContext context) {
    return [
      SectionTitle('Rotate'),
      Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: host.busy || host.clips.isEmpty
                  ? null
                  : () => unawaited(host.rotateSelectedClip(flip: false)),
              icon: const Icon(Icons.rotate_right),
              label: const Text('ROTATE 90°'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: host.busy || host.clips.isEmpty
                  ? null
                  : () => unawaited(host.rotateSelectedClip(flip: true)),
              icon: const Icon(Icons.flip),
              label: const Text('FLIP'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        'Dono selected clip ke trimmed range par bake hote hain '
        '(processed copy ban jati hai).',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }
  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
