/// PrecutPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';
import 'trim_panel.dart';

/// PrecutPanel.
class PrecutPanel extends StatelessWidget {
  final VideoEditorController host;
  const PrecutPanel(this.host, {super.key});

  /// Precut › Trim: the old Trim tab's trim section (RangeSlider +
  /// fine sliders) + frame-step buttons + the timeline Zoom toggle
  /// (InShot's "Zoom Selection").
  List<Widget> buildChildren(BuildContext context) {
    final body = TrimPanel(host).buildChildren(context);
    final canvasIdx = sectionAnchor(body, 'Canvas');
    final trimPart = canvasIdx < 0 ? body : body.sublist(0, canvasIdx);
    return [
      ...trimPart,
      SectionTitle('Frame step'),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: host.busy
                  ? null
                  : () => unawaited(
                        host.seekToGlobalSec(host.globalPositionSec - 1 / 30),
                      ),
              icon: const Icon(Icons.skip_previous, size: 18),
              label: const Text('Previous Frame'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: host.busy
                  ? null
                  : () => unawaited(
                        host.seekToGlobalSec(host.globalPositionSec + 1 / 30),
                      ),
              icon: const Icon(Icons.skip_next, size: 18),
              label: const Text('Next Frame'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      iconChoiceRail(host, [
        iconChoiceItem(host, 
          icon: Icons.zoom_in,
          label: 'Zoom Selection (timeline 2x)',
          selected: host.tlPxPerSec > 50,
          onTap: () => host.update(() => host.tlPxPerSec = host.tlPxPerSec > 50 ? 42 : 84),
        ),
      ]),
      const Divider(height: 32),
    ];
  }
  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
