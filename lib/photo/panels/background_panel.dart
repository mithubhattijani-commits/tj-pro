/// BackgroundPanel of the Photo Editor (Master Plan Phase 7 split).
///
/// Was a method of `_PhotoEditorScreenState` in
/// photo_editor_screen.dart; now a real widget in its own file.
/// All editor state is reached through [PhotoEditorController] —
/// behaviour unchanged.
library;


import '../../app_config.dart';
import 'package:flutter/material.dart';

import '../photo_editor_controller.dart';
import '../widgets/panel_helpers.dart';

class BackgroundPanel extends StatelessWidget {
  final PhotoEditorController host;
  const BackgroundPanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    final file = host.workingFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (AppConfig.aiToolsEnabled) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              host.aiAction(
                label: 'Blur background',
                icon: Icons.blur_on,
                onPressed: file == null || host.busy ? null : host.blurBackground,
              ),
              host.aiAction(
                label: 'Replace with image',
                icon: Icons.image,
                onPressed: file == null || host.busy
                    ? null
                    : host.replaceBackgroundImage,
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        const Text(
          'Replace with colour',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        host.swatchRow(
          value: host.replaceBgColor,
          onChanged: (c) => host.update(() => host.replaceBgColor = c),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (AppConfig.aiToolsEnabled)
              host.aiAction(
                label: 'Replace (subject)',
                icon: Icons.format_color_fill,
                onPressed: file == null || host.busy
                    ? null
                    : host.replaceBackgroundColor,
              ),
            if (host.hasTransparency)
              host.plainAction(
                label: 'Flatten on colour',
                icon: Icons.layers,
                onPressed: file == null || host.busy ? null : host.flattenOnColor,
              ),
          ],
        ),
        if (!host.hasTransparency && AppConfig.aiToolsEnabled)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Cutout ke baad "Flatten on colour" se transparent '
              'photo kisi bhi rang par rakhi ja sakti hai.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
