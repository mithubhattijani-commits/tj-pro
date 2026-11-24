/// MaskPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';
import 'pip_panel.dart';

/// MaskPanel.
class MaskPanel extends StatelessWidget {
  final VideoEditorController host;
  const MaskPanel(this.host, {super.key});

  /// Mask panel: the PIP element's mask controls when a PIP is
  /// active; otherwise a pointer to add one (our mask model is the
  /// PIP mask — main clips have no mask track).
  List<Widget> buildChildren(BuildContext context) {
    return [
      // Build 3 (Phase 3): the mask now applies to the MAIN clip
      // too — same shape set, feather slider and invert toggle as
      // the PIP mask, driven by the same mask-PNG renderer.
      SectionTitle('Mask — main clip'),
      const Text('Mask shape'),
      const SizedBox(height: 4),
      iconChoiceRail(host, [
        for (final e in const [
          ('none', 'None', Icons.block),
          ('circle', 'Circle', Icons.circle_outlined),
          ('rect', 'Rectangle', Icons.crop_square),
          ('roundrect', 'Rounded', Icons.rounded_corner),
          ('heart', 'Heart', Icons.favorite),
          ('star', 'Star', Icons.star),
          ('linear', 'Linear', Icons.gradient),
          ('radial', 'Radial', Icons.radio_button_checked),
        ])
          iconChoiceItem(host, 
            icon: e.$3,
            label: e.$2,
            selected: host.mainMask == e.$1,
            onTap: () => host.update(() => host.mainMask = e.$1),
          ),
      ]),
      if (host.mainMask != 'none') ...[
        ProSlider(
          label: 'Mask feather (kinara soft)',
          value: host.mainMaskFeather,
          min: 0,
          max: 1,
          divisions: 20,
          onChanged: (v) => host.update(() => host.mainMaskFeather = v),
        ),
        Row(
          children: [
            const Text('Mask invert'),
            const SizedBox(width: 10),
            iconChoiceItem(host, 
              icon: Icons.invert_colors,
              label: 'Invert',
              selected: host.mainMaskInvert,
              onTap: () =>
                  host.update(() => host.mainMaskInvert = !host.mainMaskInvert),
            ),
          ],
        ),
        const Text(
          'Mask main video par lagta hai — mask se bahar ka hissa '
          'kala (stage ka rang) ho jata hai. Title aur PIP is ke '
          'upar rehte hain. Preview mein live dikhta hai.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
      const Divider(height: 32),
      // The long-standing PIP mask section, unchanged.
      if (!host.fxPip) ...[
        SectionTitle('Mask — PIP element'),
        const Text(
          'Mask PIP element par bhi lagta hai. Pehle PIP add '
          'karein — phir yahan us ki mask shape / feather / invert '
          'milega.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => host.openToolTab('overlay', 'pip'),
            icon: const Icon(Icons.picture_in_picture_alt),
            label: const Text('PIP add karein'),
          ),
        ),
        const Divider(height: 32),
      ] else
        ...PipPanel(host).maskChildren(context),
    ];
  }
  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
