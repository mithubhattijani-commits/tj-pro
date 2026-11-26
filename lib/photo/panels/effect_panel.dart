/// EffectPanel of the Photo Editor (Master Plan Phase 7 split).
///
/// Was a method of `_PhotoEditorScreenState` in
/// photo_editor_screen.dart; now a real widget in its own file.
/// All editor state is reached through [PhotoEditorController] —
/// behaviour unchanged.
library;

import 'dart:async';


import 'package:flutter/material.dart';

import '../photo_editor_controller.dart';
import '../../services/photo_pipeline.dart';
import '../widgets/panel_helpers.dart';
import '../widgets/photo_widgets.dart';

const _classicEffects = <(String, String, IconData)>[
  ('glitch', 'Glitch', Icons.bolt),
  ('rgb', 'RGB', Icons.looks),
  ('noise', 'Noise', Icons.grain),
  ('tv', 'TV', Icons.tv),
  ('ghost', 'Ghost', Icons.copy),
  ('strobe', 'Strobe', Icons.flash_on),
  ('tilt', 'Tilt', Icons.blur_linear),
  ('warp', 'Warp', Icons.waves),
];

class EffectPanel extends StatelessWidget {
  final PhotoEditorController host;
  const EffectPanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    final file = host.workingFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose an effect — the preview is live, on Apply the full '
          'quality is baked.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        host.photoIconChoiceRail([
          host.photoIconChoiceItem(
            icon: Icons.block,
            label: 'None',
            selected: host.effectSel == null,
            onTap: () {
              host.update(() => host.effectSel = null);
              host.schedulePixelPreview();
            },
          ),
          for (final e in _classicEffects)
            host.photoIconChoiceItem(
              icon: e.$3,
              label: e.$2,
              selected: host.effectSel == e.$1,
              onTap: () {
                host.update(() => host.effectSel = e.$1);
                host.schedulePixelPreview();
              },
            ),
        ]),
        PhotoSliderRow(
          label: 'Value',
          value: host.effectValue,
          min: 0,
          max: 100,
          onChanged: (v) {
            host.update(() => host.effectValue = v);
            host.schedulePixelPreview();
          },
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: file == null || host.busy || host.effectSel == null
                ? null
                : host.applyEffect,
            icon: const Icon(Icons.check),
            label: const Text('Apply effect'),
          ),
        ),
        const Divider(height: 24),
        const Text(
          'Artistic Styles',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'ONNX painterly styles (the pack downloads, then '
          'offline).',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final s in const [
                ('fns_udnie', 'Udnie'),
                ('fns_mosaic', 'Mosaic'),
                ('fns_rain', 'Rain Princess'),
              ])
                host.lookThumb(
                  label: s.$2,
                  selected: false,
                  thumb: host.filterThumbs[PhotoFilter.normal],
                  onTap: () {
                    if (file != null && !host.busy) {
                      unawaited(host.applyArtisticStyle(s.$1, s.$2));
                    }
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
