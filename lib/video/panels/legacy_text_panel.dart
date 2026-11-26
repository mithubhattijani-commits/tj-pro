/// LegacyTextPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'text' panel (the legacy switch's default case).
class LegacyTextPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyTextPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        return [
          SectionTitle('Text overlay'),
          const SizedBox(height: 8),
// Text overlay
          TextField(
            decoration: const InputDecoration(
              labelText: 'Text overlay (single line)',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => host.update(() => host.text = v),
          ),
          const SizedBox(height: 12),
          const Divider(height: 32),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
