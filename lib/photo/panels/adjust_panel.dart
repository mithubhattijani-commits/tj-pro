/// AdjustPanel of the Photo Editor (Master Plan Phase 7 split).
///
/// Was a method of `_PhotoEditorScreenState` in
/// photo_editor_screen.dart; now a real widget in its own file.
/// All editor state is reached through [PhotoEditorController] —
/// behaviour unchanged.
library;

import 'dart:async';


import 'package:flutter/material.dart';

import '../photo_editor_controller.dart';
import '../widgets/panel_helpers.dart';
import '../widgets/photo_widgets.dart';

/// The InShot Adjust icon row: (key, label, icon). 'auto',
/// 'curve' and 'hsl' open their own sub-editors instead of the
/// shared slider.
const _adjControls = <(String, String, IconData)>[
  ('auto', 'Auto', Icons.auto_fix_high),
  ('lightness', 'Lightness', Icons.light_mode),
  // v1.5.0 (#3): Exposure lives in the icon row like every other
  // control — it used to ALSO render as an unconditional second
  // slider under the shared one (two sliders open at once).
  ('exposure', 'Exposure', Icons.exposure),
  ('contrast', 'Contrast', Icons.contrast),
  ('warmth', 'Warmth', Icons.thermostat),
  ('tint', 'Tint', Icons.format_color_fill),
  ('saturation', 'Saturation', Icons.water_drop),
  ('curve', 'Curve', Icons.show_chart),
  ('hsl', 'HSL', Icons.palette),
  ('fade', 'Fade', Icons.blur_on),
  ('highlight', 'Highlight', Icons.highlight),
  ('shadow', 'Shadow', Icons.dark_mode),
  ('color', 'Color', Icons.color_lens),
  ('hue', 'Hue', Icons.colorize),
  ('vignette', 'Vignette', Icons.vignette),
  ('sharpen', 'Sharpen', Icons.details),
  ('grain', 'Grain', Icons.grain),
];

class AdjustPanel extends StatelessWidget {
  final PhotoEditorController host;
  const AdjustPanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    final file = host.workingFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // v1.5.0 (#2): the hint is Expanded + ellipsis — as a
            // bare Text + Spacer it overflowed the row and painted
            // the yellow/black stripe.
            const Expanded(
              child: Text(
                'Ek control chunein — neeche ek hi shared slider hai.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () {
                host.update(() {
                  host.exposure = 0;
                  host.brightness = 0;
                  host.contrast = 1.0;
                  host.highlights = 0;
                  host.shadows = 0;
                  host.saturation = 1.0;
                  host.vibrance = 0;
                  host.temperature = 0;
                  host.tint = 0;
                  host.sharpenDetail = 0;
                  host.vignette = 0;
                  host.fade = 0;
                  host.hueShift = 0;
                  host.grain = 0;
                  host.curvePoints.updateAll(
                    (_, _) => [const Offset(0, 0), const Offset(1, 1)],
                  );
                });
                host.schedulePixelPreview();
              },
              child: const Text('Reset'),
            ),
          ],
        ),
        host.photoIconChoiceRail([
          for (final c in _adjControls)
            host.photoIconChoiceItem(
              icon: c.$3,
              label: c.$2,
              selected: host.adjSel == c.$1,
              onTap: () {
                if (c.$1 == 'auto') {
                  unawaited(host.autoEnhance());
                } else {
                  host.update(() => host.adjSel = c.$1);
                }
              },
            ),
        ]),
        const SizedBox(height: 6),
        if (host.adjSel == 'curve')
          host.curveEditor()
        else if (host.adjSel == 'hsl')
          host.hslEditor()
        else
          PhotoSliderRow(
            label: _adjControls.firstWhere((c) => c.$1 == host.adjSel).$2,
            value: host.adjValue(host.adjSel),
            min: host.adjRange(host.adjSel).$1,
            max: host.adjRange(host.adjSel).$2,
            onChanged: (v) => host.update(() => host.adjSet(host.adjSel, v)),
          ),
        if (file == null)
          const Text(
            'Pehle photo chunein.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
      ],
    );
  }
}
