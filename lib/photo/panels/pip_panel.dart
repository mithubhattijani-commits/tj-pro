/// PipPanel of the Photo Editor (Master Plan Phase 7 split).
///
/// Was a method of `_PhotoEditorScreenState` in
/// photo_editor_screen.dart; now a real widget in its own file.
/// All editor state is reached through [PhotoEditorController] —
/// behaviour unchanged.
library;


import 'package:flutter/material.dart';

import '../photo_editor_controller.dart';
import '../widgets/panel_helpers.dart';

class PipPanel extends StatelessWidget {
  final PhotoEditorController host;
  const PipPanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    final file = host.workingFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: file == null || host.busy ? null : host.addPipOverlay,
            icon: const Icon(Icons.photo_library),
            label: const Text('Add photo overlay (gallery)'),
          ),
        ),
        const SizedBox(height: 8),
        host.overlayControls(),
      ],
    );
  }
}
