/// LegacyStabilizationPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'stabilization' panel.
class LegacyStabilizationPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyStabilizationPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        return [
// Stabilization.
              SwitchListTile(
                title: const Text('Stabilization'),
                subtitle: const Text(
                  'Vidstab when available, otherwise the deshake engine will be used.',
                ),
                value: host.proStabilize,
                onChanged: (v) => host.update(() => host.proStabilize = v),
              ),
              const Divider(height: 32),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
