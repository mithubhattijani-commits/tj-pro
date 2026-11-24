/// StickerPanel of the Photo Editor (Master Plan Phase 7 split).
///
/// Was a method of `_PhotoEditorScreenState` in
/// photo_editor_screen.dart; now a real widget in its own file.
/// All editor state is reached through [PhotoEditorController] —
/// behaviour unchanged.
library;


import 'package:flutter/material.dart';

import '../photo_editor_controller.dart';
import '../photo_models.dart';
import '../widgets/panel_helpers.dart';

class StickerPanel extends StatelessWidget {
  final PhotoEditorController host;
  const StickerPanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final g in kPhotoStickerGlyphs)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => host.addSticker(g),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFF232323),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(g, style: const TextStyle(fontSize: 24)),
                  ),
                ),
              ),
          ],
        ),
        const Divider(height: 20),
        host.overlayControls(),
      ],
    );
  }
}
