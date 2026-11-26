/// LegacyBeatsPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'beats' panel.
class LegacyBeatsPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyBeatsPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        return [
// Beat sync.
              SectionTitle('Beat sync'),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (host.detectingBeats || host.busy || host.clips.isEmpty)
                          ? null
                          : host.runBeatDetection,
                      icon: const Icon(Icons.graphic_eq),
                      label: Text(
                        host.detectingBeats ? 'Detecting…' : 'Detect beats',
                      ),
                    ),
                  ),
                ],
              ),
              if (host.beats.isNotEmpty)
                Text(
                  '${host.beats.length} beats — '
                  '${host.beats.take(5).map((b) => '${b.toStringAsFixed(1)}s').join(', ')}'
                  '${host.beats.length > 5 ? ', …' : ''}',
                ),
              SwitchListTile(
                title: const Text('Beat auto-cut'),
                subtitle: const Text(
                  'Single clip ko beat boundaries par kaatkar jorega.',
                ),
                value: host.beatAutoCut,
                onChanged: (v) => host.update(() => host.beatAutoCut = v),
              ),
              if (host.beatAutoCut && host.clips.length > 1)
                const Text(
                  'Note: in multi-clip, beat auto-cut does not apply — only '
                  'markers will show; the cut happens only on a single clip. '
                  'If Auto-cut is OFF, even on a single clip only '
                  'only markers remain.',
                  style: TextStyle(color: Colors.grey),
                ),
              const Divider(height: 32),
              // A1 (v1.12): manual timeline markers.
              SectionTitle('Timeline markers'),
              const SizedBox(height: 4),
              const Text(
                'Beats and markers show on the timeline — the playhead, '
                'Split and trim snap to them.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: host.clips.isEmpty
                          ? null
                          : host.addMarkerAtPlayhead,
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('Playhead par marker'),
                    ),
                  ),
                ],
              ),
              if (host.markers.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final m in host.markers)
                  Row(
                    children: [
                      const Icon(
                        Icons.bookmark,
                        size: 14,
                        color: Color(0xFFFFD60A),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('Marker — ${m.toStringAsFixed(1)}s'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        tooltip: 'Remove marker',
                        onPressed: () => host.removeMarker(m),
                      ),
                    ],
                  ),
              ],
              const Divider(height: 32),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
