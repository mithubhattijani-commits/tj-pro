/// TransformPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../editor_models.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// TransformPanel.
class TransformPanel extends StatelessWidget {
  final VideoEditorController host;
  const TransformPanel(this.host, {super.key});

  /// Edit › Transform (§6.7) + the selected photo clip's Ken Burns
  /// controls (§6.1).
  List<Widget> buildChildren(BuildContext context) {
    final clip = host.clips.isEmpty ? null : host.clips[host.selected];
    return [
      SectionTitle('Transform — main clip'),
      ProSlider(
        label: 'Scale',
        value: host.tfScale,
        min: 0.5,
        max: 2,
        divisions: 30,
        onChanged: (v) => host.update(() => host.tfScale = v),
      ),
      ProSlider(
        label: 'Position X',
        value: host.tfX,
        min: -0.5,
        max: 0.5,
        divisions: 20,
        onChanged: (v) => host.update(() => host.tfX = v),
      ),
      ProSlider(
        label: 'Position Y',
        value: host.tfY,
        min: -0.5,
        max: 0.5,
        divisions: 20,
        onChanged: (v) => host.update(() => host.tfY = v),
      ),
      ProSlider(
        label: 'Rotation (deg)',
        value: host.tfRot,
        min: -45,
        max: 45,
        divisions: 90,
        digits: 0,
        onChanged: (v) => host.update(() => host.tfRot = v),
      ),
      ProSlider(
        label: 'Opacity',
        value: host.tfOpacity,
        min: 0.1,
        max: 1,
        divisions: 18,
        onChanged: (v) => host.update(() => host.tfOpacity = v),
      ),
      TextButton(
        onPressed: () => host.update(() {
          host.tfScale = 1;
          host.tfX = 0;
          host.tfY = 0;
          host.tfRot = 0;
          host.tfOpacity = 1;
        }),
        child: const Text('Transform reset'),
      ),
      const Text(
        'Transform export mein blurred backdrop par lagta hai — '
        'kaale kinare kabhi nahi aate.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      if (clip != null && clip.isPhoto) ...[
        SectionTitle('Photo clip — Ken Burns'),
        SwitchListTile(
          title: const Text('Ken Burns (slow zoom)'),
          value: clip.kenBurns,
          onChanged: (v) => host.update(() => clip.kenBurns = v),
        ),
        const Text('Zoom'),
        const SizedBox(height: 4),
        iconChoiceRail(host, [
          iconChoiceItem(host, 
            icon: Icons.zoom_in,
            label: 'Zoom in',
            selected: clip.kbZoomIn,
            onTap: () => host.update(() => clip.kbZoomIn = true),
          ),
          iconChoiceItem(host, 
            icon: Icons.zoom_out,
            label: 'Zoom out',
            selected: !clip.kbZoomIn,
            onTap: () => host.update(() => clip.kbZoomIn = false),
          ),
        ]),
        ProSlider(
          label: 'Photo duration (s)',
          value: clip.duration.inMilliseconds / 1000,
          min: 1,
          max: 10,
          divisions: 18,
          digits: 1,
          onChanged: (v) {
            host.update(() {
              final old = clip;
              final nc = VideoClip(
                old.file,
                Duration(milliseconds: (v * 1000).round()),
                old.aspectRatio,
              );
              nc.isPhoto = true;
              nc.kenBurns = old.kenBurns;
              nc.kbZoomIn = old.kbZoomIn;
              host.clips[host.selected] = nc;
            });
          },
        ),
      ],
      const Divider(height: 32),
    ];
  }
  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
