/// EasePanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../../services/pro_editor.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// EasePanel.
class EasePanel extends StatelessWidget {
  final VideoEditorController host;
  const EasePanel(this.host, {super.key});

  /// Ease panel (InShot curve-preset variant — the documented
  /// superset): the 4 REAL easing curves of the keyframe system,
  /// as chips + the live curve graph.
  List<Widget> buildChildren(BuildContext context) {
    return [
      SectionTitle('Ease — keyframe motion'),
      iconChoiceRail(host, [
        for (final e in KeyframeEasing.values)
          iconChoiceItem(host, 
            icon: switch (e) {
              KeyframeEasing.linear => Icons.trending_flat,
              KeyframeEasing.easeIn => Icons.trending_up,
              KeyframeEasing.easeOut => Icons.trending_down,
              KeyframeEasing.easeInOut => Icons.show_chart,
            },
            label: keyframeEasingLabel(e).split(' (').first,
            selected: host.kfEasing == e,
            onTap: () => host.update(() => host.kfEasing = e),
          ),
      ]),
      Container(
        height: 56,
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1B1B),
          borderRadius: BorderRadius.circular(8),
        ),
        child: CustomPaint(
          painter: EasingCurvePainter(host.kfEasing),
          child: const SizedBox.expand(),
        ),
      ),
      const Text(
        'This easing applies to the Animation (keyframes) motion.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }
  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
