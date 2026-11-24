/// LegacyTransitionsPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../../app_config.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'transitions' panel.
class LegacyTransitionsPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyTransitionsPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        return [
          const Text('Transitions',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
if (AppConfig.crossfadeEnabled)
            SwitchListTile(
              title: const Text('Crossfade between clips'),
            subtitle: const Text('Simple fade transition when merging'),
            value: host.crossfade,
            onChanged: (v) => host.update(() => host.crossfade = v),
          ),
          const Divider(height: 32),
          // ---- PRO tools (v2.1.0) ----
// Transitions.
              const Text('Transitions',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Transition'),
              const SizedBox(height: 4),
              iconChoiceRail(host, [
                for (final e in const [
                  ('fade', Icons.gradient),
                  ('slideleft', Icons.arrow_back),
                  ('slideright', Icons.arrow_forward),
                  ('slideup', Icons.arrow_upward),
                  ('slidedown', Icons.arrow_downward),
                  ('wipeleft', Icons.keyboard_arrow_left),
                  ('wiperight', Icons.keyboard_arrow_right),
                  ('wipeup', Icons.keyboard_arrow_up),
                  ('wipedown', Icons.keyboard_arrow_down),
                  ('circlecrop', Icons.circle_outlined),
                  ('dissolve', Icons.blur_on),
                  ('pixelize', Icons.grid_on),
                  ('smoothleft', Icons.keyboard_double_arrow_left),
                  ('smoothright', Icons.keyboard_double_arrow_right),
                  ('radial', Icons.radio_button_checked),
                  ('rectcrop', Icons.crop_square),
                  ('hblur', Icons.blur_linear),
                  ('circleopen', Icons.radio_button_unchecked),
                ])
                  iconChoiceItem(host, 
                    icon: e.$2,
                    label: e.$1,
                    selected: host.proTransition == e.$1,
                    onTap: () => host.update(() => host.proTransition = e.$1),
                  ),
              ]),
              ProSlider(
                label: 'Transition duration (s)',
                value: host.proTransitionDur,
                min: 0.3,
                max: 2.0,
                divisions: 17,
                onChanged: (v) => host.update(() => host.proTransitionDur = v),
              ),
              const Text(
                'Sirf tab lagega jab Crossfade between clips ON ho; '
                'OFF par aaj ki tarah hard cuts rahenge.',
                style: TextStyle(color: Colors.grey),
              ),
              const Divider(height: 32),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
