/// LegacyNewsTextPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'newsText' panel.
class LegacyNewsTextPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyNewsTextPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        // v1.3.0 (§5A News › Text): the four template text fields
        // + the clock toggle (same _news state as before).
        return [
          const Text('News — text fields',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (!host.newsEnabled)
            const Text(
              'Pehle Template tab mein News Template ON karein.',
              style: TextStyle(color: Colors.grey),
            )
          else ...[
            TextFormField(
              initialValue: host.news.breakingHeadline,
              decoration: const InputDecoration(
                labelText: 'Breaking headline (surkh patti)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                host.news.breakingHeadline = v;
                unawaited(host.news.save());
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: host.news.lowerTitle,
              decoration: const InputDecoration(
                labelText: 'Lower-third title (naam)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                host.news.lowerTitle = v;
                unawaited(host.news.save());
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: host.news.lowerSubtitle,
              decoration: const InputDecoration(
                labelText: 'Lower-third subtitle (ohda / jagah)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                host.news.lowerSubtitle = v;
                unawaited(host.news.save());
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: host.news.tickerText,
              decoration: const InputDecoration(
                labelText: 'Ticker text (neeche chalta hua)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                host.news.tickerText = v;
                unawaited(host.news.save());
              },
            ),
            SwitchListTile(
              title: const Text('Live clock / date dikhayein'),
              value: host.news.showClock,
              onChanged: (v) {
                host.update(() => host.news.showClock = v);
                unawaited(host.news.save());
              },
            ),
          ],
          const Divider(height: 32),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
