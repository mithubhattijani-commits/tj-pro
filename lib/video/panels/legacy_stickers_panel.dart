/// LegacyStickersPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'stickers' panel.
class LegacyStickersPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyStickersPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        return [
          const Text('Stickers / emoji overlay',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
TextField(
                decoration: const InputDecoration(
                  labelText: 'Sticker / emoji overlay',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => host.update(() => host.proSticker = v),
              ),
              const SizedBox(height: 8),
              const Text('Sticker preset'),
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
                    selected: host.proStickerPreset == e.$1,
                    onTap: () =>
                        host.update(() => host.proStickerPreset = e.$1),
                  ),
              ]),
              const Divider(height: 32),
          const SizedBox(height: 12),
          const Text(
            'Keyframes animate the title/sticker overlay from start to end.',
            style: TextStyle(color: Colors.grey),
          ),
// Keyframes.
              SwitchListTile(
                title: const Text('Keyframes (motion title/sticker)'),
                subtitle: const Text(
                  'Start se end tak overlay move/scale/fade/rotate hoga.',
                ),
                value: host.proKeyframes,
                onChanged: (v) => host.update(() => host.proKeyframes = v),
              ),
              if (host.proKeyframes &&
                  host.proTitle.trim().isEmpty &&
                  host.proSticker.trim().isEmpty)
                const Text(
                  'Pehle motion title ya sticker likhein — keyframes usi '
                  'overlay par lagenge.',
                  style: TextStyle(color: Colors.grey),
                ),
              if (host.proKeyframes &&
                  (host.proTitle.trim().isNotEmpty ||
                      host.proSticker.trim().isNotEmpty)) ...[
                // v1.3.0: the easing DROPDOWN is replaced by chips
                // + a curve graph at the top of the Keyframes
                // sub-tab (same _kfEasing state — presentation only).
                const SizedBox(height: 8),
                const Text('Start keyframe',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ProSlider(
                  label: 'Start X',
                  value: host.kfStartX,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => host.update(() => host.kfStartX = v),
                ),
                ProSlider(
                  label: 'Start Y',
                  value: host.kfStartY,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => host.update(() => host.kfStartY = v),
                ),
                ProSlider(
                  label: 'Start scale',
                  value: host.kfStartScale,
                  min: 0.5,
                  max: 2,
                  divisions: 30,
                  onChanged: (v) => host.update(() => host.kfStartScale = v),
                ),
                ProSlider(
                  label: 'Start opacity',
                  value: host.kfStartOpacity,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => host.update(() => host.kfStartOpacity = v),
                ),
                ProSlider(
                  label: 'Start rotation',
                  value: host.kfStartRotation,
                  min: -180,
                  max: 180,
                  divisions: 72,
                  digits: 0,
                  onChanged: (v) => host.update(() => host.kfStartRotation = v),
                ),
                const Text('End keyframe',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ProSlider(
                  label: 'End X',
                  value: host.kfEndX,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => host.update(() => host.kfEndX = v),
                ),
                ProSlider(
                  label: 'End Y',
                  value: host.kfEndY,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => host.update(() => host.kfEndY = v),
                ),
                ProSlider(
                  label: 'End scale',
                  value: host.kfEndScale,
                  min: 0.5,
                  max: 2,
                  divisions: 30,
                  onChanged: (v) => host.update(() => host.kfEndScale = v),
                ),
                ProSlider(
                  label: 'End opacity',
                  value: host.kfEndOpacity,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => host.update(() => host.kfEndOpacity = v),
                ),
                ProSlider(
                  label: 'End rotation',
                  value: host.kfEndRotation,
                  min: -180,
                  max: 180,
                  divisions: 72,
                  digits: 0,
                  onChanged: (v) => host.update(() => host.kfEndRotation = v),
                ),
              ],
              const Divider(height: 32),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
