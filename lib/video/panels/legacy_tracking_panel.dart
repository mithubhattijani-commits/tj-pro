/// LegacyTrackingPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'tracking' panel.
class LegacyTrackingPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyTrackingPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        return [
// Motion tracking.
              const Text('Motion tracking (ML)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Text(
                'Preview video par object ko tap karein, phir Track '
                'dabayein. (Tap point ab asal video frame par exact '
                'map hota hai.)',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Tracked sticker text',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => host.update(() => host.trackSticker = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (host.trackStartX == null ||
                              host.tracking ||
                              host.busy)
                          ? null
                          : host.runObjectTracking,
                      icon: const Icon(Icons.my_location),
                      label: Text(host.tracking ? 'Tracking…' : 'Track object'),
                    ),
                  ),
                ],
              ),
              if (host.trackStartX != null)
                Text(
                  'Tapped: (${host.trackStartX!.toStringAsFixed(2)}, ${host.trackStartY!.toStringAsFixed(2)})',
                ),
              if (host.trackPoints.isNotEmpty)
                Text('${host.trackPoints.length} track points ready.'),
              const Divider(height: 32),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
