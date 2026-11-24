/// MusicPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// MusicPanel.
class MusicPanel extends StatelessWidget {
  final VideoEditorController host;
  const MusicPanel(this.host, {super.key});

  /// Audio › Music extras (§6.8 ducking + §6.9 volume keyframes).
  List<Widget> buildChildren(BuildContext context) {
    final posSec = host.controller != null && host.controller!.value.isInitialized
        ? host.controller!.value.position.inMilliseconds / 1000
        : 0.0;
    return [
      const Divider(height: 32),
      SwitchListTile(
        title: const Text('Auto ducking'),
        subtitle: const Text(
          'Music clip ki awaz ke neeche khud dab jayega (sidechain) '
          '— export mein alag pass mein lagta hai.',
        ),
        value: host.autoDuck,
        onChanged: (v) => host.update(() => host.autoDuck = v),
      ),
      if (host.musicPath != null) ...[
        SectionTitle('Volume keyframes'),
        if (host.volumePoints.isEmpty)
          const Text(
            'Koi point nahi — music seedha Music volume par chalega.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        for (var i = 0; i < host.volumePoints.length; i++)
          Row(
            children: [
              Expanded(
                child: Text(
                  '${host.volumePoints[i].$1.toStringAsFixed(1)}s → '
                  'gain ${host.volumePoints[i].$2.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () =>
                    host.update(() => host.volumePoints.removeAt(i)),
              ),
            ],
          ),
        ElevatedButton.icon(
          onPressed: () {
            host.update(() {
              host.volumePoints.add((posSec, host.musicVolume));
              host.volumePoints.sort((a, b) => a.$1.compareTo(b.$1));
            });
          },
          icon: const Icon(Icons.add_location_alt_outlined),
          label: Text(
            'Point add karein — playhead ${posSec.toStringAsFixed(1)}s, '
            'gain ${host.musicVolume.toStringAsFixed(2)}',
          ),
        ),
      ],
    ];
  }
  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
