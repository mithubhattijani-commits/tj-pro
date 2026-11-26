/// TransitionsPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// TransitionsPanel.
class TransitionsPanel extends StatelessWidget {
  final VideoEditorController host;
  const TransitionsPanel(this.host, {super.key});

  /// Transitions panel REWRITE (#8): category rows of type chips +
  /// ONE duration slider. v1.4.0 had THREE duration controls
  /// (crossfade toggle + presets rail + slider) and a crossfade
  /// switch separate from the type — here picking a type IS the
  /// on-switch, 'None' is the off-switch, one slider sets the
  /// duration. (InShot's post-pick volume slider is skipped — no
  /// transition-SFX model exists; PARTIAL in the report.)
  List<Widget> buildChildren(BuildContext context) {
    Widget typeChip(String id, String label, IconData icon) {
      final selected = host.crossfade && host.proTransition == id;
      return iconChoiceItem(host, 
        icon: icon,
        label: label,
        selected: selected,
        onTap: () => host.update(() {
          host.proTransition = id;
          host.crossfade = true;
        }),
      );
    }

    return [
      SectionTitle('Transition — type'),
      const Text('Basic'),
      const SizedBox(height: 4),
      iconChoiceRail(host, [
        iconChoiceItem(host, 
          icon: Icons.block,
          label: 'None',
          selected: !host.crossfade,
          onTap: () => host.update(() => host.crossfade = false),
        ),
        typeChip('fade', 'Fade', Icons.blur_linear),
        typeChip('dissolve', 'Dissolve', Icons.grain),
        typeChip('pixelize', 'Pixelize', Icons.grid_on),
        typeChip('hblur', 'H-Blur', Icons.blur_on),
      ]),
      const SizedBox(height: 6),
      const Text('Slide'),
      const SizedBox(height: 4),
      iconChoiceRail(host, [
        typeChip('slideleft', 'Left', Icons.arrow_back),
        typeChip('slideright', 'Right', Icons.arrow_forward),
        typeChip('slideup', 'Up', Icons.arrow_upward),
        typeChip('slidedown', 'Down', Icons.arrow_downward),
        typeChip('smoothleft', 'Smooth L', Icons.keyboard_double_arrow_left),
        typeChip('smoothright', 'Smooth R', Icons.keyboard_double_arrow_right),
      ]),
      const SizedBox(height: 6),
      const Text('Wipe'),
      const SizedBox(height: 4),
      iconChoiceRail(host, [
        typeChip('wipeleft', 'Left', Icons.arrow_back),
        typeChip('wiperight', 'Right', Icons.arrow_forward),
        typeChip('wipeup', 'Up', Icons.arrow_upward),
        typeChip('wipedown', 'Down', Icons.arrow_downward),
      ]),
      const SizedBox(height: 6),
      const Text('Circle'),
      const SizedBox(height: 4),
      iconChoiceRail(host, [
        typeChip('circlecrop', 'Crop', Icons.circle_outlined),
        typeChip('circleopen', 'Open', Icons.radio_button_unchecked),
        typeChip('radial', 'Radial', Icons.radar),
        typeChip('rectcrop', 'Rect', Icons.crop_square),
      ]),
      SectionTitle('Duration'),
      ProSlider(
        label: 'Transition duration',
        value: host.proTransitionDur,
        min: 0.1,
        max: 2,
        divisions: 19,
        onChanged: (v) => host.update(() => host.proTransitionDur = v),
      ),
      const Text(
        'Duration har clip boundary par same lagti hai; type '
        'badalne se kul duration badal sakti hai (xfade overlap).',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }
  @override
  Widget build(BuildContext context) =>
      panelDrillOrColumn(host, buildChildren(context));
}
