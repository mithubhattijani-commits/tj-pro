/// AdjustPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../../services/pro_editor.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// AdjustPanel.
class AdjustPanel extends StatelessWidget {
  final VideoEditorController host;
  const AdjustPanel(this.host, {super.key});

  /// v1.4.0 Colour › Adjust (brief: tabs Filters | Adjust — the
  /// tabs live in [_panelTabs]; here: the LUT rail, ONE circular
  /// icon row of adjust items, ONE shared slider, Reset + ✓ (the
  /// panel header's Done is the ✓). 'Auto adjust' is a toggle in
  /// the row (ffmpeg normalize at export). HSL is not offered:
  /// the bundled ffmpeg has no per-hue-range HSL filter, and a
  /// fake slider is worse than none (see _adjustExtraFilter).
  List<Widget> buildChildren(BuildContext context) {
    return [
      const Text('Adjust — ek waqt mein ek slider',
          style: TextStyle(fontWeight: FontWeight.bold)),
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
        iconChoiceItem(host, 
          icon: Icons.auto_fix_high,
          label: 'Auto adjust',
          selected: host.adjAuto,
          onTap: () => host.update(() => host.adjAuto = !host.adjAuto),
        ),
        for (final e in const [
          ('Brightness', Icons.brightness_6),
          ('Contrast', Icons.contrast),
          ('Saturation', Icons.palette),
          ('Brilliance', Icons.lightbulb_outline),
          ('Sharpen', Icons.details),
          ('Clarity', Icons.filter_drama_outlined),
          ('Highlights', Icons.light_mode),
          ('Shadows', Icons.dark_mode),
          ('Whites', Icons.wb_sunny),
          ('Blacks', Icons.nightlight_round),
          ('Temperature', Icons.thermostat),
          ('Tint', Icons.colorize),
          ('Vibrance', Icons.color_lens),
          ('Exposure', Icons.exposure),
          ('Hue', Icons.gradient),
          ('Fade', Icons.waves),
          ('Vignette', Icons.vignette),
          ('Grain', Icons.grain),
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
      const SizedBox(height: 4),
      Row(
        children: [
          TextButton.icon(
            onPressed: host.resetGrade,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Reset'),
          ),
          const Spacer(),
          const Text(
            'Har item per selected clip ke export par lagta hai.',
            style: TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
      const Divider(height: 32),
    ];
  }
  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
