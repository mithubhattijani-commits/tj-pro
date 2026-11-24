/// LegacyNewsLogoPanel of the Video Editor (Master Plan Phase 4 split).
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

/// Legacy 'newsLogo' panel.
class LegacyNewsLogoPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyNewsLogoPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        // v1.3.0 (§5A News › Logo): logo pick + position + rotation.
        return [
          const Text('News — logo',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (!host.newsEnabled)
            const Text(
              'Pehle Template tab mein News Template ON karein.',
              style: TextStyle(color: Colors.grey),
            )
          else ...[
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
              subtitle: const Text(
                'Live mein ghoomega; Final-template export mein '
                'logo asal template ki jagah par ghoomta hai, baqi '
                'exports mein static rehta hai.',
              ),
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
