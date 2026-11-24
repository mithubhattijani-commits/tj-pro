/// LegacyNewsPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../live/news_template.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'news' panel.
class LegacyNewsPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyNewsPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        return [
          const Text('News — template, ribbons, logo',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// News template (shared with Live Studio).
          SwitchListTile(
            title: const Text('News Template (Live Studio wala)'),
            subtitle: const Text(
              'Breaking banner, lower-third, ticker, clock, logo — '
              'export par bhi lagega.',
            ),
            value: host.newsEnabled,
            onChanged: (v) => host.update(() => host.newsEnabled = v),
          ),
          if (host.newsEnabled) ...[
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
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final picked = await host.picker.pickImage(
                        source: ImageSource.gallery,
                      );
                      if (picked == null) return;
                      // Phase 0 sweep: no setState after the picker
                      // await without a mounted check.
                      if (!host.mounted) return;
                      host.update(() => host.news.logoPath = picked.path);
                      await host.news.save();
                    },
                    icon: const Icon(Icons.image),
                    label: Text(
                      host.news.logoPath == null
                          ? 'Logo chunein'
                          : 'Logo badlein',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Logo jagah'),
            const SizedBox(height: 4),
            iconChoiceRail(host, [
              for (final pos in LogoPosition.values)
                iconChoiceItem(host, 
                  icon: switch (pos) {
                    LogoPosition.topLeft => Icons.north_west,
                    LogoPosition.topRight => Icons.north_east,
                    LogoPosition.bottomLeft => Icons.south_west,
                    LogoPosition.bottomRight => Icons.south_east,
                  },
                  label: pos.label,
                  selected: host.news.logoPosition == pos,
                  onTap: () {
                    host.update(() => host.news.logoPosition = pos);
                    unawaited(host.news.save());
                  },
                ),
            ]),
            SwitchListTile(
              title: const Text('Logo ahista ghoome (rotation)'),
              subtitle: const Text('Sirf live me ghoomega; export me static.'),
              value: host.news.logoRotate,
              onChanged: (v) {
                host.update(() => host.news.logoRotate = v);
                unawaited(host.news.save());
              },
            ),
            const Text(
              'Note: News Studio ke Final-template (nigraanFinal) '
              'project ka export ANIMATED hota hai — dono ribbons '
              'scroll karti hain, logo ghoomta hai, clock tick karta '
              'hai. Plain editor ke live design ka export ek still '
              'frame rehta hai. Yehi template Live Studio me bhi use '
              'hota hai.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
          const Divider(height: 32),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
