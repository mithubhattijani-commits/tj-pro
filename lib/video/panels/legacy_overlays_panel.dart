/// LegacyOverlaysPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import '../../services/fx_pack.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'overlays' panel.
class LegacyOverlaysPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyOverlaysPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        return [
          // v1.15.0 G2: section headers are SectionTitles so the
          // panel drill-down (Point #29) can split this body.
          SectionTitle('Overlay — PIP video'),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('PIP video overlay'),
            value: host.fxPip,
            onChanged: (bool v) {
              host.update(() {
                host.fxPip = v;
              });
              host.ensurePipPreview();
            },
          ),
          if (host.fxPip)
            ElevatedButton.icon(
              onPressed: () async {
                final XFile? picked =
                    await host.picker.pickVideo(source: ImageSource.gallery);
                if (picked != null && host.mounted) {
                  host.update(() {
                    host.fxPipVideo = picked.path;
                  });
                  host.ensurePipPreview();
                }
              },
              icon: const Icon(Icons.video_library),
              label: Text(host.fxPipVideo.isEmpty
                  ? 'Choose PIP video'
                  : p.basename(host.fxPipVideo)),
            ),
          if (host.fxPip) ...[
            const SizedBox(height: 8),
            SectionTitle('PIP position'),
            const SizedBox(height: 4),
            iconChoiceRail(host, [
              for (final pos in PipPosition.values)
                iconChoiceItem(host, 
                  icon: switch (pos) {
                    PipPosition.topLeft => Icons.north_west,
                    PipPosition.topRight => Icons.north_east,
                    PipPosition.bottomLeft => Icons.south_west,
                    PipPosition.bottomRight => Icons.south_east,
                  },
                  label: pos.name,
                  selected: host.pipPosition == pos,
                  onTap: () => host.update(() => host.pipPosition = pos),
                ),
            ]),
            const SizedBox(height: 8),
            SectionTitle('PIP size'),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    key: const Key('pipScaleSlider'),
                    value: host.pipScale,
                    min: 0.15,
                    max: 0.5,
                    divisions: 7,
                    label: '${(host.pipScale * 100).round()}%',
                    onChanged: (v) => host.update(() => host.pipScale = v),
                  ),
                ),
                Text('${(host.pipScale * 100).round()}%'),
              ],
            ),
            if (host.fxPipVideo.isEmpty)
              const Text(
                'PIP video chunein — bina inset video ke PIP export mein nahi lagega.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
          ],
          const Divider(height: 32),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
