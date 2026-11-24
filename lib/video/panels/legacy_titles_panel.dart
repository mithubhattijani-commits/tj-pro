/// LegacyTitlesPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'titles' panel.
class LegacyTitlesPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyTitlesPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        return [
          const Text('Motion titles',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// Motion titles + sticker.
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Motion title (PNG render, Urdu-safe)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => host.update(() => host.proTitle = v),
              ),
              const SizedBox(height: 8),
              const Text('Title preset'),
              const SizedBox(height: 4),
              iconChoiceRail(host, [
                for (final e in const [
                  ('fadeIn', Icons.gradient),
                  ('slideLeft', Icons.arrow_back),
                  ('slideRight', Icons.arrow_forward),
                  ('slideUp', Icons.arrow_upward),
                  ('zoomPop', Icons.zoom_in),
                ])
                  iconChoiceItem(host, 
                    icon: e.$2,
                    label: e.$1,
                    selected: host.proTitlePreset == e.$1,
                    onTap: () => host.update(() => host.proTitlePreset = e.$1),
                  ),
              ]),
              const SizedBox(height: 8),
              const Text('Title position'),
              const SizedBox(height: 4),
              iconChoiceRail(host, [
                for (final e in const [
                  ('topCenter', 'Top', Icons.vertical_align_top),
                  ('center', 'Center', Icons.vertical_align_center),
                  ('bottomCenter', 'Bottom', Icons.vertical_align_bottom),
                ])
                  iconChoiceItem(host, 
                    icon: e.$3,
                    label: e.$2,
                    selected: host.proTitlePosition == e.$1,
                    onTap: () => host.update(() => host.proTitlePosition = e.$1),
                  ),
              ]),
              const SizedBox(height: 8),
          const Divider(height: 32),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
