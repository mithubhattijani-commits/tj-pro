/// CanvasPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';
import 'trim_panel.dart';

/// CanvasPanel.
class CanvasPanel extends StatelessWidget {
  final VideoEditorController host;
  const CanvasPanel(this.host, {super.key});

  /// Canvas › Ratio: the Canvas section of the old Trim tab (the
  /// aspect rail), sliced at its section anchors.
  List<Widget> buildChildren(BuildContext context) {
    final body = TrimPanel(host).buildChildren(context);
    final canvasIdx = sectionAnchor(body, 'Canvas');
    if (canvasIdx < 0) return body;
    final fillIdx = anchorIndex(
      body,
      (w) => w is Text && w.data == 'Fill',
    );
    final end = fillIdx > canvasIdx ? fillIdx : body.length;
    return body.sublist(canvasIdx, end);
  }

  /// Canvas › Background: the SAME Canvas section's Fill part
  /// (Crop / Blur / Colour + fill colours). InShot's GRADIENT fill
  /// is not supported by the export's canvas fill — the note in
  /// the panel says so (PARTIAL, see the test report).
  List<Widget> backgroundChildren(BuildContext context) {
    final body = TrimPanel(host).buildChildren(context);
    final fillIdx = anchorIndex(
      body,
      (w) => w is Text && w.data == 'Fill',
    );
    final introIdx = sectionAnchor(body, 'Intro / outro');
    if (fillIdx < 0) return const [];
    final end = introIdx > fillIdx ? introIdx : body.length;
    return [
      SectionTitle('Canvas background'),
      ...body.sublist(fillIdx, end),
      const Text(
        'Gradient fill abhi supported nahi — Blur ya Colour chunein.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }
  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
