/// LegacyEffectsPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../../services/fx_pack.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'effects' panel.
class LegacyEffectsPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyEffectsPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        return [
          const Text('Effects',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Divider(height: 32),
          const Text('Shake effect',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Shake intensity'),
          const SizedBox(height: 4),
          iconChoiceRail(host, [
            for (final e in const [
              (ShakeFx.none, 'None', Icons.block),
              (ShakeFx.light, 'Light', Icons.air),
              (ShakeFx.medium, 'Medium', Icons.waves),
              (ShakeFx.strong, 'Strong', Icons.vibration),
            ])
              iconChoiceItem(host, 
                icon: e.$3,
                label: e.$2,
                selected: host.fxShake == e.$1,
                onTap: () => host.update(() => host.fxShake = e.$1),
              ),
          ]),
          const SizedBox(height: 8),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
