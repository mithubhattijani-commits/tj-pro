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
              const Text('Beat sync',
                  style: TextStyle(fontWeight: FontWeight.bold)),
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
                  'Note: multi-clip me beat auto-cut nahi lagta — sirf '
                  'markers dikhenge; cut sirf single clip par hota hai. '
                  'Auto-cut OFF rakhein to single clip par bhi sirf '
                  'markers rehte hain.',
                  style: TextStyle(color: Colors.grey),
                ),
              const Divider(height: 32),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
