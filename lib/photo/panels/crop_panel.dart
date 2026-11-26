/// CropPanel of the Photo Editor (Master Plan Phase 7 split).
///
/// Was a method of `_PhotoEditorScreenState` in
/// photo_editor_screen.dart; now a real widget in its own file.
/// All editor state is reached through [PhotoEditorController] —
/// behaviour unchanged.
library;

import 'dart:async';


import 'package:flutter/material.dart';

import '../photo_editor_controller.dart';
import '../widgets/panel_helpers.dart';
import '../widgets/photo_widgets.dart';

class CropPanel extends StatelessWidget {
  final PhotoEditorController host;
  const CropPanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    final file = host.workingFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: file == null || host.busy ? null : host.crop,
            icon: const Icon(Icons.crop),
            label: const Text('Crop (system)'),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Ratio presets — tap for an instant centre crop '
          '(Undo can bring it back):',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 6),
        host.photoIconChoiceRail([
          host.photoIconChoiceItem(
            icon: Icons.crop_free,
            label: 'Free',
            selected: false,
            onTap: file == null || host.busy
                ? null
                : () {
                    host.update(() => host.cropPreset = 'free');
                    unawaited(host.crop());
                  },
          ),
          for (final e in const [
            ('9:16', 9, 16, Icons.crop_portrait),
            ('1:1', 1, 1, Icons.crop_square),
            ('16:9', 16, 9, Icons.crop_landscape),
            ('4:5', 4, 5, Icons.crop_portrait),
            ('3:4', 3, 4, Icons.crop_portrait),
          ])
            host.photoIconChoiceItem(
              icon: e.$4,
              label: e.$1,
              selected: false,
              onTap: file == null || host.busy
                  ? null
                  : () => host.quickRatioCrop(e.$1, e.$2, e.$3),
            ),
        ]),
        const Divider(height: 22),
        const Text('Straighten', style: TextStyle(fontWeight: FontWeight.bold)),
        PhotoSliderRow(
          label: 'Angle',
          value: host.straighten,
          min: -45,
          max: 45,
          onChanged: (v) => host.update(() => host.straighten = v),
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: file == null || host.busy || host.straighten == 0
                ? null
                : host.applyStraighten,
            icon: const Icon(Icons.check),
            label: const Text('Apply straighten'),
          ),
        ),
      ],
    );
  }
}
