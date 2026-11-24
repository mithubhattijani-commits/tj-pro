/// LegacyNewsTemplatePanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../video_editor_panels.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'newsTemplate' panel.
class LegacyNewsTemplatePanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyNewsTemplatePanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        // v1.3.0 (§5A News › Template): the master switch + the
        // Live Studio entry (the old 'live' panel body).
        return [
          const Text('News — template',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('News Template (Live Studio wala)'),
            subtitle: const Text(
              'Breaking banner, lower-third, ticker, clock, logo — '
              'export par bhi lagega.',
            ),
            value: host.newsEnabled,
            onChanged: (v) => host.update(() => host.newsEnabled = v),
          ),
          if (host.projectTemplateKind == 'nigraanFinal')
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Ye project Final template (nigraanFinal) hai: is ka '
                'export ANIMATED lagega — Final 3-Ribbon design '
                '(neeche English ticker hamesha scroll, Urdu '
                'ribbons lambi text par scroll), ghoomta logo aur '
                'us ke neeche date capsule (bilkul asal Nigraan '
                'video jaisa). Classic 2-Ribbon design Template '
                'Studio se select ho sakta hai.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          const Divider(height: 32),
          ...panelBody(host, context, 'live'),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
