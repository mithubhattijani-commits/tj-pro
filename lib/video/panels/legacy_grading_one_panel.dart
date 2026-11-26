/// LegacyGradingOnePanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../../services/pro_editor.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'gradingOne' panel.
class LegacyGradingOnePanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyGradingOnePanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        // v1.3.0 (§5A Colour › Adjust): the LUT dropdown stays on
        // top; below it ONE grade slider at a time, picked by
        // chips (same state as the old all-sliders list).
        return [
          SectionTitle('Adjust — ek waqt mein ek slider'),
          const SizedBox(height: 8),
          const Text('LUT look'),
          const SizedBox(height: 4),
          iconChoiceRail(host, [
            for (final e in proLuts)
              iconChoiceItem(host, 
                icon: (e['name'] ?? '').isEmpty
                    ? Icons.block
                    : Icons.photo_filter,
                label: (e['name'] ?? '').isEmpty ? 'None' : e['name']!,
                selected: host.proLut == (e['name'] ?? ''),
                onTap: () => host.update(() => host.proLut = e['name'] ?? ''),
              ),
          ]),
          const SizedBox(height: 8),
          iconChoiceRail(host, [
            for (final e in const [
              ('Temperature', Icons.thermostat),
              ('Tint', Icons.colorize),
              ('Saturation', Icons.palette),
              ('Vibrance', Icons.color_lens),
              ('Contrast', Icons.contrast),
              ('Shadows', Icons.dark_mode),
              ('Highlights', Icons.light_mode),
              ('Brightness', Icons.brightness_6),
              ('Exposure', Icons.exposure),
            ])
              iconChoiceItem(host, 
                icon: e.$2,
                label: e.$1,
                selected: host.gradeSlider == e.$1,
                onTap: () => host.update(() => host.gradeSlider = e.$1),
              ),
          ]),
          const SizedBox(height: 8),
          gradeSliderWidget(host),
          const Divider(height: 32),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
