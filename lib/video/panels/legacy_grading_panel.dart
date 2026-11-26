/// LegacyGradingPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../../services/pro_editor.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'grading' panel.
class LegacyGradingPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyGradingPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        return [
// Grading.
              SectionTitle('Grading'),
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
              ProSlider(
                label: 'Temperature',
                value: host.proTemperature,
                min: -100,
                max: 100,
                divisions: 40,
                digits: 0,
                onChanged: (v) => host.update(() => host.proTemperature = v),
              ),
              ProSlider(
                label: 'Tint',
                value: host.proTint,
                min: -100,
                max: 100,
                divisions: 40,
                digits: 0,
                onChanged: (v) => host.update(() => host.proTint = v),
              ),
              ProSlider(
                label: 'Saturation',
                value: host.proSaturation,
                min: 0,
                max: 2,
                divisions: 40,
                onChanged: (v) => host.update(() => host.proSaturation = v),
              ),
              ProSlider(
                label: 'Vibrance',
                value: host.proVibrance,
                min: 0,
                max: 2,
                divisions: 40,
                onChanged: (v) => host.update(() => host.proVibrance = v),
              ),
              ProSlider(
                label: 'Contrast',
                value: host.proContrast,
                min: 0,
                max: 2,
                divisions: 40,
                onChanged: (v) => host.update(() => host.proContrast = v),
              ),
              ProSlider(
                label: 'Shadows',
                value: host.proShadows,
                min: -100,
                max: 100,
                divisions: 40,
                digits: 0,
                onChanged: (v) => host.update(() => host.proShadows = v),
              ),
              ProSlider(
                label: 'Highlights',
                value: host.proHighlights,
                min: -100,
                max: 100,
                divisions: 40,
                digits: 0,
                onChanged: (v) => host.update(() => host.proHighlights = v),
              ),
              ProSlider(
                label: 'Brightness',
                value: host.proBrightness,
                min: -100,
                max: 100,
                divisions: 40,
                digits: 0,
                onChanged: (v) => host.update(() => host.proBrightness = v),
              ),
              ProSlider(
                label: 'Exposure',
                value: host.proExposure,
                min: -100,
                max: 100,
                divisions: 40,
                digits: 0,
                onChanged: (v) => host.update(() => host.proExposure = v),
              ),
              const Divider(height: 32),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
