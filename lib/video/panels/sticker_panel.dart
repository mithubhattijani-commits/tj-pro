/// StickerPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../video_editor_panels.dart';
import '../widgets/panel_controls.dart';

/// StickerPanel.
class StickerPanel extends StatelessWidget {
  final VideoEditorController host;
  const StickerPanel(this.host, {super.key});

  /// Overlay › Sticker: the stickers body WITHOUT the keyframes
  /// block (that lives on its own sub-tab now).
  List<Widget> buildChildren(BuildContext context) {
    final body = panelBody(host, context, 'stickers');
    final kfIdx =
        anchorIndex(body, (w) => isTextStarting(w, 'Keyframes animate'));
    return kfIdx < 0 ? body : body.sublist(0, kfIdx);
  }
  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
