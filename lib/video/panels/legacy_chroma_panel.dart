/// LegacyChromaPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'chroma' panel.
class LegacyChromaPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyChromaPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        return [
          const Text('Chromakey / BG remover',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// Chromakey.
              SwitchListTile(
                title: const Text('Chromakey'),
                subtitle: const Text(
                  'Green/blue background hatakar naya background lagayein.',
                ),
                value: host.proChroma,
                onChanged: (v) => host.update(() => host.proChroma = v),
              ),
              if (host.proChroma) ...[
                // v1.4.0 (brief): 'Drag to select color' — the
                // circular picker over the preview frame (the
                // eyedropper dialog samples the exact tapped pixel
                // and keys it live). Below it ONLY the two CapCut
                // sliders are primary: Intensity (= Similarity) and
                // Shadow (= Blend); Spill/Edge stay as the existing
                // advanced controls (nothing is removed).
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: host.eyedropperPick,
                    icon: const Icon(Icons.colorize),
                    label: const Text('Drag to select color'),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Intensity = Similarity slider, Shadow = Blend '
                  'slider (neeche) — rang select karte hi live '
                  'preview update hota hai.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 8),
                const Text('Key color — preset ya eyedropper se sample karein'),
                Row(
                  children: [
                    Expanded(
                      child: iconChoiceRail(host, [
                        iconChoiceItem(host, 
                          icon: Icons.circle,
                          iconColor: Colors.green,
                          label: 'Green',
                          selected: host.proChromaColor == 'green',
                          onTap: () {
                            host.update(() => host.proChromaColor = 'green');
                            host.scheduleChromaPreview();
                          },
                        ),
                        iconChoiceItem(host, 
                          icon: Icons.circle,
                          iconColor: Colors.blue,
                          label: 'Blue',
                          selected: host.proChromaColor == 'blue',
                          onTap: () {
                            host.update(() => host.proChromaColor = 'blue');
                            host.scheduleChromaPreview();
                          },
                        ),
                      ]),
                    ),
                    IconButton(
                      tooltip: 'Eyedropper — frame par tap karke rang chunein',
                      onPressed: host.eyedropperPick,
                      icon: const Icon(Icons.colorize),
                    ),
                  ],
                ),
                if (host.proChromaColor.startsWith('#'))
                  Text(
                    'Sampled color: ${host.proChromaColor}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ProSlider(
                  label: 'Similarity',
                  value: host.proChromaSimilarity,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) {
                    host.update(() => host.proChromaSimilarity = v);
                    host.scheduleChromaPreview();
                  },
                ),
                ProSlider(
                  label: 'Blend',
                  value: host.proChromaBlend,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) {
                    host.update(() => host.proChromaBlend = v);
                    host.scheduleChromaPreview();
                  },
                ),
                ProSlider(
                  label: 'Spill (sabz kinara saaf)',
                  value: host.proChromaSpill,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) {
                    host.update(() => host.proChromaSpill = v);
                    host.scheduleChromaPreview();
                  },
                ),
                ProSlider(
                  label: 'Edge (shrink - grow)',
                  value: host.proChromaEdge,
                  min: -1,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) {
                    host.update(() => host.proChromaEdge = v);
                    host.scheduleChromaPreview();
                  },
                ),
                const Text('Background kind'),
                const SizedBox(height: 4),
                iconChoiceRail(host, [
                  iconChoiceItem(host, 
                    icon: Icons.palette,
                    label: 'Color',
                    selected: host.proChromaBgKind == 'color',
                    onTap: () {
                      host.update(() => host.proChromaBgKind = 'color');
                      host.scheduleChromaPreview();
                    },
                  ),
                  iconChoiceItem(host, 
                    icon: Icons.image,
                    label: 'Image',
                    selected: host.proChromaBgKind == 'image',
                    onTap: () {
                      host.update(() => host.proChromaBgKind = 'image');
                      host.scheduleChromaPreview();
                    },
                  ),
                ]),
                if (host.proChromaBgKind == 'color') ...[
                  const Text('Background color'),
                  const SizedBox(height: 4),
                  iconChoiceRail(host, [
                    for (final e in const [
                      ('#00FF00', 'Green', Color(0xFF00FF00)),
                      ('#0000FF', 'Blue', Color(0xFF0000FF)),
                      ('#000000', 'Black', Color(0xFF000000)),
                      ('#FFFFFF', 'White', Color(0xFFFFFFFF)),
                    ])
                      iconChoiceItem(host, 
                        icon: Icons.circle,
                        iconColor: e.$3,
                        label: e.$2,
                        selected: host.proChromaBgColor == e.$1,
                        onTap: () {
                          host.update(() => host.proChromaBgColor = e.$1);
                          host.scheduleChromaPreview();
                        },
                      ),
                  ]),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Custom color (#RRGGBB)',
                      hintText: '#1A2B3C',
                    ),
                    onSubmitted: (v) {
                      final t = v.trim();
                      if (RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(t)) {
                        host.update(() => host.proChromaBgColor = t.toUpperCase());
                        host.scheduleChromaPreview();
                      } else {
                        host.setStatus('Rang #RRGGBB format mein likhein.');
                      }
                    },
                  ),
                ],
                if (host.proChromaBgKind == 'image')
                  ElevatedButton.icon(
                    onPressed: () => host.pickProImage(
                      (path) => host.proChromaBgImage = path,
                    ),
                    icon: const Icon(Icons.image),
                    label: Text(
                      host.proChromaBgImage == null
                          ? 'Background image chunein'
                          : p.basename(host.proChromaBgImage!),
                    ),
                  ),
              ],
                if (host.proChroma) ...[
                  const Divider(height: 32),
                  const Text('Backdrop shortcuts',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  iconChoiceRail(host, [
                    iconChoiceItem(host, 
                      icon: Icons.meeting_room,
                      label: 'Newsroom',
                      selected: false,
                      onTap: () => host.applyBackdropAsset(
                          'assets/backgrounds/newsroom.jpg'),
                    ),
                    iconChoiceItem(host, 
                      icon: Icons.desktop_windows,
                      label: 'Studio Desk',
                      selected: false,
                      onTap: () => host.applyBackdropAsset(
                          'assets/backgrounds/studio_desk.jpg'),
                    ),
                    iconChoiceItem(host, 
                      icon: Icons.tv,
                      label: 'News anchor preset',
                      selected: false,
                      onTap: host.applyNewsAnchorPreset,
                    ),
                  ]),
                  const SizedBox(height: 12),
                  const Text('Live preview (export jesa result)',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (host.chromaPreviewPath != null)
                    Image.file(
                      File(host.chromaPreviewPath!),
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.contain,
                    )
                  else
                    const Text(
                      'Slider badalte hi keyed frame yahan dikhega — '
                      'ya Preview button dabayein.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed:
                        host.chromaPreviewBusy ? null : host.refreshChromaPreview,
                    icon: const Icon(Icons.visibility),
                    label: Text(host.chromaPreviewBusy
                        ? 'Preview ban raha…'
                        : 'Preview dekhein'),
                  ),
                  if (host.proBgRemove)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Note: ML background remover bhi ON hai — '
                        'export mein wohi lagega, chromakey nahi '
                        '(dono ek saath nahi chalte).',
                        style:
                            TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                ],
              const Divider(height: 32),
// Video BG remover.
              SwitchListTile(
                title: const Text('Video background remover (ML)'),
                subtitle: const Text(
                  'Premium AI: 50 coins se unlock hoga (is session '
                  'ke liye). Export mein pehle MODNet HQ matte lagta '
                  'hai; live preview ML Kit segmentation se hai.',
                ),
                value: host.proBgRemove,
                onChanged: host.onBgRemoverChanged,
              ),
              if (host.proBgRemove) ...[
                const Text('Background kind'),
                const SizedBox(height: 4),
                iconChoiceRail(host, [
                  iconChoiceItem(host, 
                    icon: Icons.palette,
                    label: 'Color',
                    selected: host.proBgKind == 'color',
                    onTap: () => host.update(() => host.proBgKind = 'color'),
                  ),
                  iconChoiceItem(host, 
                    icon: Icons.image,
                    label: 'Image',
                    selected: host.proBgKind == 'image',
                    onTap: () => host.update(() => host.proBgKind = 'image'),
                  ),
                ]),
                if (host.proBgKind == 'color') ...[
                  const SizedBox(height: 6),
                  const Text('Background color'),
                  const SizedBox(height: 4),
                  iconChoiceRail(host, [
                    for (final e in const [
                      ('#00FF00', 'Green', Color(0xFF00FF00)),
                      ('#0000FF', 'Blue', Color(0xFF0000FF)),
                      ('#000000', 'Black', Color(0xFF000000)),
                      ('#FFFFFF', 'White', Color(0xFFFFFFFF)),
                    ])
                      iconChoiceItem(host, 
                        icon: Icons.circle,
                        iconColor: e.$3,
                        label: e.$2,
                        selected: host.proBgColor == e.$1,
                        onTap: () => host.update(() => host.proBgColor = e.$1),
                      ),
                  ]),
                ],
                if (host.proBgKind == 'image')
                  ElevatedButton.icon(
                    onPressed: () =>
                        host.pickProImage((path) => host.proBgImage = path),
                    icon: const Icon(Icons.image),
                    label: Text(
                      host.proBgImage == null
                          ? 'Background image chunein'
                          : p.basename(host.proBgImage!),
                    ),
                  ),
              ],
              const Text(
                'Note: lambi clips par minutes lag sakte hain; width '
                'capped hai; saaf subject wali video par behtareen '
                'result milta hai. Progress export status me dikhega.',
                style: TextStyle(color: Colors.grey),
              ),
              const Divider(height: 32),
        ];
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
