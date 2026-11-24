/// CutoutPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../video_editor_panels.dart';
import '../widgets/panel_controls.dart';

/// CutoutPanel.
class CutoutPanel extends StatelessWidget {
  final VideoEditorController host;
  const CutoutPanel(this.host, {super.key});

  /// Cutout panel: two modes (InShot [TUT3/4]) — Cutout = the ML
  /// background remover section, Chroma = the chroma-key section,
  /// sliced out of the one legacy 'chroma' body at the BG-remover
  /// switch anchor (each section shows exactly once).
  List<Widget> buildChildren(BuildContext context) {
    final body = panelBody(host, context, 'chroma');
    final bgIdx = anchorIndex(
      body,
      (w) =>
          w is SwitchListTile &&
          w.title is Text &&
          ((w.title as Text).data ?? '').contains('background remover'),
    );
    final chromaPart = bgIdx < 0 ? body : body.sublist(0, bgIdx);
    final bgPart = bgIdx < 0 ? const <Widget>[] : body.sublist(bgIdx);
    return [
      iconChoiceRail(host, [
        iconChoiceItem(host, 
          icon: Icons.person_remove,
          label: 'Cutout',
          selected: host.cutoutMode == 'cutout',
          onTap: () => host.update(() => host.cutoutMode = 'cutout'),
        ),
        iconChoiceItem(host, 
          icon: Icons.format_color_fill,
          label: 'Chroma',
          selected: host.cutoutMode == 'chroma',
          onTap: () => host.update(() => host.cutoutMode = 'chroma'),
        ),
      ]),
      const SizedBox(height: 6),
      if (host.cutoutMode == 'chroma') ...chromaPart else ...bgPart,
    ];
  }
  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
