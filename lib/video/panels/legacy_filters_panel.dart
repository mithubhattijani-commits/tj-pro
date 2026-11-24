/// LegacyFiltersPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'filters' panel.
class LegacyFiltersPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyFiltersPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        return [
          const Text('Filters',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// Speed / filter / aspect
          const Text('Filter'),
          const SizedBox(height: 4),
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
          const SizedBox(height: 8),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
