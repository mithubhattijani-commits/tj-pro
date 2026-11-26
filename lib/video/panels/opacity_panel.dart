/// OpacityPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';
import 'pip_panel.dart';

/// OpacityPanel.
class OpacityPanel extends StatelessWidget {
  final VideoEditorController host;
  const OpacityPanel(this.host, {super.key});

  /// Opacity panel: PIP element → its opacity + blend (the PIP
  /// style slice); a plain clip → the transform opacity.
  List<Widget> buildChildren(BuildContext context) {
    if (host.fxPip) return PipPanel(host).styleChildren(context);
    return [
      SectionTitle('Opacity — clip'),
      ProSlider(
        label: 'Clip opacity',
        value: host.tfOpacity,
        min: 0,
        max: 1,
        divisions: 20,
        onChanged: (v) => host.update(() => host.tfOpacity = v),
      ),
      const Text(
        'The clip fades over its blurred backdrop (Transform '
        'pass) — applies on export.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }
  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
