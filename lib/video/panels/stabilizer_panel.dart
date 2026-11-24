/// StabilizerPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// StabilizerPanel.
class StabilizerPanel extends StatelessWidget {
  final VideoEditorController host;
  const StabilizerPanel(this.host, {super.key});

  /// Stabilizer panel (InShot [TUT10] shape): 4 level tiles. Ours
  /// applies at EXPORT (vidstab two-pass in the export chain) —
  /// the note says so; the level maps to shakiness/smoothing at
  /// the export call site.
  List<Widget> buildChildren(BuildContext context) {
    return [
      SectionTitle('Stabilizer'),
      iconChoiceRail(host, [
        for (final e in const [
          (0, 'Original', Icons.block),
          (1, 'Low', Icons.videocam),
          (2, 'Standard', Icons.video_stable),
          (3, 'Most Stable', Icons.video_stable),
        ])
          iconChoiceItem(host, 
            icon: e.$3,
            label: e.$2,
            selected: host.stabLevel == e.$1,
            onTap: () => host.update(() {
              host.stabLevel = e.$1;
              host.proStabilize = e.$1 > 0;
            }),
          ),
      ]),
      const SizedBox(height: 8),
      const Text(
        'Stabilization EXPORT par apply hoti hai (vidstab two-pass) '
        '— preview mein nahi dikhegi.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }
  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
