/// PipPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// PipPanel.
class PipPanel extends StatelessWidget {
  final VideoEditorController host;
  const PipPanel(this.host, {super.key});

  /// The PIP style slice of [_pipExtras] (opacity + blend) — the
  /// Opacity panel's element half.
  /// Where the Mask section starts inside [extrasChildren] —
  /// the anchor is the 'Mask' SectionTitle (v1.15.0 G2 made the
  /// section headers SectionTitles for the drill-down).
  static int _maskAnchor(List<Widget> extras) => anchorIndex(
        extras,
        (w) =>
            isTextStarting(w, 'Mask') ||
            (w is SectionTitle && w.title.startsWith('Mask')),
      );

  List<Widget> styleChildren(BuildContext context) {
    final extras = extrasChildren(context);
    final maskIdx = _maskAnchor(extras);
    return maskIdx < 0 ? extras : extras.sublist(0, maskIdx);
  }

  /// The PIP mask slice of [_pipExtras] — the Mask panel's content.
  List<Widget> maskChildren(BuildContext context) {
    final extras = extrasChildren(context);
    final maskIdx = _maskAnchor(extras);
    if (maskIdx < 0) return const [];
    // The anchor IS the Mask SectionTitle now — keep it as the
    // slice's own header (before v1.15 a fresh 'Mask — PIP
    // element' title was added above the plain label; same
    // result, one title).
    return extras.sublist(maskIdx);
  }

  /// Overlay › PIP extras (§6.11 + completion fix, user order
  /// 22 Nov 2026): opacity, blend mode, mask shape, feather,
  /// invert — every choice an icon+label rail (global UI rule).
  /// The blend keys ARE ffmpeg's blend mode names; 'normal' takes
  /// the plain overlay path. The mask keys map 1:1 onto the
  /// generated mask PNG (preview + export share it).
  List<Widget> extrasChildren(BuildContext context) {
    if (!host.fxPip) return const [];
    return [
      SectionTitle('PIP style'),
      ProSlider(
        label: 'PIP opacity',
        value: host.pipOpacity,
        min: 0.1,
        max: 1,
        divisions: 18,
        onChanged: (v) => host.update(() => host.pipOpacity = v),
      ),
      SectionTitle('Blend mode'),
      const SizedBox(height: 4),
      iconChoiceRail(host, [
        for (final e in const [
          ('normal', 'Normal', Icons.picture_in_picture_alt),
          ('multiply', 'Multiply', Icons.layers),
          ('screen', 'Screen', Icons.light_mode),
          ('overlay', 'Overlay', Icons.contrast),
          ('softlight', 'Soft Light', Icons.blur_on),
          ('hardlight', 'Hard Light', Icons.flash_on),
          ('darken', 'Darken', Icons.dark_mode),
          ('lighten', 'Lighten', Icons.brightness_high),
          ('difference', 'Difference', Icons.compare_arrows),
          ('dodge', 'Color Dodge', Icons.wb_sunny),
          ('burn', 'Color Burn', Icons.local_fire_department),
        ])
          iconChoiceItem(host, 
            icon: e.$3,
            label: e.$2,
            selected: host.pipBlend == e.$1,
            onTap: () => host.update(() => host.pipBlend = e.$1),
          ),
      ]),
      const SizedBox(height: 8),
      SectionTitle('Mask'),
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
            selected: host.pipMask == e.$1,
            onTap: () => host.update(() => host.pipMask = e.$1),
          ),
      ]),
      if (host.pipMask != 'none') ...[
        ProSlider(
          label: 'Mask feather (soft edge)',
          value: host.pipMaskFeather,
          min: 0,
          max: 1,
          divisions: 20,
          onChanged: (v) => host.update(() => host.pipMaskFeather = v),
        ),
        Row(
          children: [
            const Text('Mask invert'),
            const SizedBox(width: 10),
            iconChoiceItem(host, 
              icon: Icons.invert_colors,
              label: 'Invert',
              selected: host.pipMaskInvert,
              onTap: () => host.update(() => host.pipMaskInvert = !host.pipMaskInvert),
            ),
          ],
        ),
      ],
      const Text(
        'The blend mode applies inside the inset only — the frame outside '
        'stays original. Mask, feather and blend show live in the stage preview, '
        'show live, and the same result comes in the export.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }
  @override
  Widget build(BuildContext context) =>
      panelDrillOrColumn(host, styleChildren(context));
}
