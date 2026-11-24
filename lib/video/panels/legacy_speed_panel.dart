/// LegacySpeedPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'speed' panel.
class LegacySpeedPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacySpeedPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        return [
          const Text('Speed — fixed speed + speed ramps',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// Speed / filter / aspect
          const Text('Speed'),
          const SizedBox(height: 4),
          iconChoiceRail(host, [
            for (final e in const [
              (0.5, Icons.slow_motion_video),
              (0.75, Icons.speed),
              (1.0, Icons.play_arrow),
              (1.5, Icons.fast_forward),
              (2.0, Icons.double_arrow),
            ])
              iconChoiceItem(host, 
                icon: e.$2,
                label: '${e.$1}x',
                selected: host.speed == e.$1,
                // Build 3: the preview plays at the picked speed
                // immediately (live preview, point 19).
                onTap: () {
                  host.update(() => host.speed = e.$1);
                  host.applyPreviewSpeed(e.$1);
                },
              ),
          ]),
// Speed ramp.
              const Text('Speed ramp',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Ramp preset'),
              const SizedBox(height: 4),
              iconChoiceRail(host, [
                for (final e in const [
                  ('None', Icons.block),
                  ('slowMiddle', Icons.compress),
                  ('slowStart', Icons.trending_down),
                  ('slowEnd', Icons.trending_up),
                  ('pulse', Icons.show_chart),
                  ('Custom', Icons.tune),
                ])
                  iconChoiceItem(host, 
                    icon: e.$2,
                    label: e.$1,
                    selected: host.proRamp == e.$1,
                    onTap: () => host.update(() => host.proRamp = e.$1),
                  ),
              ]),
              const Text(
                'Note: ramp on ho to fixed Speed dropdown ignore ho jata hai.',
                style: TextStyle(color: Colors.grey),
              ),
              const Divider(height: 32),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
