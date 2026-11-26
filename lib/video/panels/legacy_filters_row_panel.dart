/// LegacyFiltersRowPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'filtersRow' panel.
class LegacyFiltersRowPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyFiltersRowPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        // v1.3.0 (§5A Colour › Filters): chip row instead of the
        // dropdown (same _filter state) + the §6.1 intensity
        // slider. The stage preview updates LIVE via the colour
        // matrix; the export scales the same ffmpeg filter.
        return [
          SectionTitle('Filters — LIVE preview stage par'),
          const SizedBox(height: 8),
          iconChoiceRail(host, [
            for (final e in const [
              ('Normal', Icons.photo),
              ('Warm', Icons.wb_sunny),
              ('Cool', Icons.ac_unit),
              ('B&W', Icons.filter_b_and_w),
              ('Vivid', Icons.palette),
              ('Sepia', Icons.history),
            ])
              iconChoiceItem(host, 
                icon: e.$2,
                label: e.$1,
                selected: host.filter == e.$1,
                onTap: () => host.update(() => host.filter = e.$1),
              ),
          ]),
          ProSlider(
            label: 'Filter intensity',
            value: host.filterIntensity,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: (v) => host.update(() => host.filterIntensity = v),
          ),
          const Text(
            'Note: LUT looks sirf export mein lagte hain (file-based '
            'hain) — stage preview mein filter + Adjust ke values '
            'live dikhte hain.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const Divider(height: 32),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
