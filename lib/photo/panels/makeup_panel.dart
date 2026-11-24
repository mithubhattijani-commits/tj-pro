/// MakeupPanel of the Photo Editor (Master Plan Phase 7 split).
///
/// Was a method of `_PhotoEditorScreenState` in
/// photo_editor_screen.dart; now a real widget in its own file.
/// All editor state is reached through [PhotoEditorController] —
/// behaviour unchanged.
library;


import 'package:flutter/material.dart';

import '../photo_editor_controller.dart';
import '../widgets/panel_helpers.dart';
import '../widgets/photo_widgets.dart';

class MakeupPanel extends StatelessWidget {
  final PhotoEditorController host;
  const MakeupPanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    final file = host.workingFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        host.photoIconChoiceRail([
          host.photoIconChoiceItem(
            icon: Icons.circle,
            iconColor: const Color(0xFFD81B60),
            label: 'Lips',
            selected: host.makeupMode == 'lips',
            onTap: () => host.update(() {
              host.makeupMode = 'lips';
              host.makeupColor = const Color(0xFFD81B60);
            }),
          ),
          host.photoIconChoiceItem(
            icon: Icons.face,
            iconColor: const Color(0xFFF48FB1),
            label: 'Blush',
            selected: host.makeupMode == 'blush',
            onTap: () => host.update(() {
              host.makeupMode = 'blush';
              host.makeupColor = const Color(0xFFF48FB1);
            }),
          ),
        ]),
        const SizedBox(height: 8),
        host.swatchRow(
          value: host.makeupColor,
          onChanged: (c) => host.update(() => host.makeupColor = c),
          colors: const [
            Color(0xFFD81B60),
            Color(0xFFC21807),
            Color(0xFFAD1457),
            Color(0xFFF48FB1),
            Color(0xFFFF8A65),
            Color(0xFF8E24AA),
            Color(0xFF6D4C41),
            Colors.white,
          ],
        ),
        PhotoSliderRow(
          label: 'Intensity',
          value: host.makeupIntensity,
          min: 0,
          max: 100,
          onChanged: (v) => host.update(() => host.makeupIntensity = v),
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: file == null || host.busy ? null : host.applyMakeup,
            icon: const Icon(Icons.check),
            label: const Text('Apply makeup'),
          ),
        ),
        const Text(
          'Face bounds se lips/cheeks ke oval regions par feathered '
          'tint lagta hai.',
          style: TextStyle(color: Colors.grey, fontSize: 11),
        ),
      ],
    );
  }
}
