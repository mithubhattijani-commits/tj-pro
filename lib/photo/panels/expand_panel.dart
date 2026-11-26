/// ExpandPanel of the Photo Editor (Master Plan Phase 7 split).
///
/// Was a method of `_PhotoEditorScreenState` in
/// photo_editor_screen.dart; now a real widget in its own file.
/// All editor state is reached through [PhotoEditorController] —
/// behaviour unchanged.
library;


import 'package:flutter/material.dart';

import '../photo_editor_controller.dart';
import '../widgets/panel_helpers.dart';

class ExpandPanel extends StatelessWidget {
  final PhotoEditorController host;
  const ExpandPanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Expand the canvas to the new ratio — the edges fill with blur or '
          'fill with mirror. This is NOT AI outpainting, '
          'it is simple compositing.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        host.ratioRail(
          selected: host.expandRatio,
          includeOriginal: false,
          onSelect: (r) => host.update(() => host.expandRatio = r),
        ),
        const SizedBox(height: 6),
        host.photoIconChoiceRail([
          host.photoIconChoiceItem(
            icon: Icons.blur_on,
            label: 'Blur fill',
            selected: host.expandFill == 'blur',
            onTap: () => host.update(() => host.expandFill = 'blur'),
          ),
          host.photoIconChoiceItem(
            icon: Icons.flip,
            label: 'Mirror fill',
            selected: host.expandFill == 'mirror',
            onTap: () => host.update(() => host.expandFill = 'mirror'),
          ),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: host.busy ? null : host.applyExpand,
            icon: const Icon(Icons.open_in_full),
            label: const Text('Expand canvas'),
          ),
        ),
      ],
    );
  }
}
