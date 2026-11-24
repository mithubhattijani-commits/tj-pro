/// LegacyLivePanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';
import '../../live/live_studio_screen.dart';

/// Legacy 'live' panel.
class LegacyLivePanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyLivePanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        return [
          const Text('Live Studio',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Facebook + YouTube par ek saath live — breaking news '
            'templates ke saath. Live Studio apni screen par khulta hai.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LiveStudioScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.live_tv),
              label: const Text('Open Live Studio'),
            ),
          ),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
