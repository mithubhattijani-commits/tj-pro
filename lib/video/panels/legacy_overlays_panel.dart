/// LegacyOverlaysPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import '../../services/fx_pack.dart';
import '../video_editor_controller.dart';
import '../widgets/editor_stage.dart' show TimelineMath;
import '../widgets/panel_controls.dart';

/// Legacy 'overlays' panel.
class LegacyOverlaysPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyOverlaysPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        return [
          // v1.15.0 G2: section headers are SectionTitles so the
          // panel drill-down (Point #29) can split this body.
          SectionTitle('Overlay — PIP video'),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('PIP video overlay'),
            value: host.fxPip,
            onChanged: (bool v) {
              host.update(() {
                host.fxPip = v;
              });
              host.ensurePipPreview();
            },
          ),
          if (host.fxPip)
            ElevatedButton.icon(
              onPressed: () async {
                final XFile? picked =
                    await host.picker.pickVideo(source: ImageSource.gallery);
                if (picked != null && host.mounted) {
                  host.update(() {
                    host.fxPipVideo = picked.path;
                  });
                  host.ensurePipPreview();
                }
              },
              icon: const Icon(Icons.video_library),
              label: Text(host.fxPipVideo.isEmpty
                  ? 'Choose PIP video'
                  : p.basename(host.fxPipVideo)),
            ),
          if (host.fxPip) ...[
            const SizedBox(height: 8),
            SectionTitle('PIP position'),
            const SizedBox(height: 4),
            iconChoiceRail(host, [
              for (final pos in PipPosition.values)
                iconChoiceItem(host, 
                  icon: switch (pos) {
                    PipPosition.topLeft => Icons.north_west,
                    PipPosition.topRight => Icons.north_east,
                    PipPosition.bottomLeft => Icons.south_west,
                    PipPosition.bottomRight => Icons.south_east,
                  },
                  label: pos.name,
                  selected: host.pipPosition == pos,
                  onTap: () => host.update(() => host.pipPosition = pos),
                ),
            ]),
            const SizedBox(height: 8),
            SectionTitle('PIP size'),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    key: const Key('pipScaleSlider'),
                    value: host.pipScale,
                    min: 0.15,
                    max: 0.5,
                    divisions: 7,
                    label: '${(host.pipScale * 100).round()}%',
                    onChanged: (v) => host.update(() => host.pipScale = v),
                  ),
                ),
                Text('${(host.pipScale * 100).round()}%'),
              ],
            ),
            if (host.fxPipVideo.isEmpty)
              const Text(
                'Choose a PIP video — without an inset video, PIP will not be in the export.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            // v1.16.0 G2 (Motion M3): the PIP window — where on
            // the timeline the inset shows. The same window is
            // drawn as the PIP lane's segment (drag it there),
            // gated in the stage preview and in the export.
            const SizedBox(height: 8),
            SectionTitle('PIP timing'),
            const SizedBox(height: 4),
            Builder(builder: (context) {
              final total = host.totalDurationSec;
              final w = TimelineMath.pipWindowClamp(
                start: host.pipStartSec,
                end: host.pipEndSec,
                totalDur: total,
              );
              final full = TimelineMath.pipWindowIsFull(
                start: host.pipStartSec,
                end: host.pipEndSec,
                totalDur: total,
              );
              // v1.16.0 G3 (A3): the PIP lane lock disables
              // these controls (and the lane drag) — unlock from
              // the lock icon on the timeline's PIP lane.
              final locked = host.pipLaneLocked;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    total <= 0
                        ? 'Add clips first — the window is set on the timeline.'
                        : full
                            ? 'Shows on the whole timeline.'
                            : 'Shows from '
                                '${TimelineMath.formatTimecode(w.start, host.exportFps)} '
                                'to ${TimelineMath.formatTimecode(w.end, host.exportFps)}.',
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  if (locked)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'PIP lane is locked — unlock it from the lock icon on the timeline PIP lane to change the timing.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  if (total > 0)
                    Opacity(
                      opacity: locked ? 0.45 : 1,
                      child: IgnorePointer(
                        ignoring: locked,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                    ProSlider(
                      label: 'Start',
                      value: w.start,
                      min: 0,
                      max: total,
                      onChanged: (v) => host.update(() {
                        final c = TimelineMath.pipWindowClamp(
                          start: v,
                          end: host.pipEndSec,
                          totalDur: total,
                        );
                        host.pipStartSec = c.start;
                        host.pipEndSec =
                            host.pipEndSec < 0 ? -1 : c.end;
                      }),
                    ),
                    ProSlider(
                      label: 'End',
                      value: w.end,
                      min: 0,
                      max: total,
                      onChanged: (v) => host.update(() {
                        final c = TimelineMath.pipWindowClamp(
                          start: host.pipStartSec,
                          end: v,
                          totalDur: total,
                        );
                        host.pipStartSec = c.start;
                        host.pipEndSec =
                            v >= total - 0.001 ? -1 : c.end;
                      }),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => host.update(() {
                            final c = TimelineMath.pipWindowClamp(
                              start: host.globalPositionSec,
                              end: host.pipEndSec,
                              totalDur: total,
                            );
                            host.pipStartSec = c.start;
                            if (host.pipEndSec >= 0) {
                              host.pipEndSec = c.end;
                            }
                          }),
                          child: const Text('Start at playhead'),
                        ),
                        TextButton(
                          onPressed: () => host.update(() {
                            final c = TimelineMath.pipWindowClamp(
                              start: host.pipStartSec,
                              end: host.globalPositionSec,
                              totalDur: total,
                            );
                            host.pipStartSec = c.start;
                            host.pipEndSec = c.end >= total - 0.001
                                ? -1
                                : c.end;
                          }),
                          child: const Text('End at playhead'),
                        ),
                        TextButton(
                          onPressed: () => host.update(() {
                            host.pipStartSec = 0;
                            host.pipEndSec = -1;
                          }),
                          child: const Text('Full duration'),
                        ),
                      ],
                    ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            }),
          ],
          const Divider(height: 32),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
