/// TrimPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// TrimPanel.
class TrimPanel extends StatelessWidget {
  final VideoEditorController host;
  const TrimPanel(this.host, {super.key});

  /// Edit › Trim (§5A): fine trim + the action row (Split / Frame /
  /// Freeze / Extract / Delete — moved here from the old timeline
  /// header) + Canvas chips + fill + intro/outro attach slots.
  List<Widget> buildChildren(BuildContext context) {
    final clip = host.clips.isEmpty ? null : host.clips[host.selected];
    final dur = clip != null ? clip.duration.inMilliseconds / 1000 : 0.0;
    return [
      SectionTitle('Trim selected clip'),
      if (clip == null)
        const Text(
          'Pehle timeline se clip add karein (+ tile).',
          style: TextStyle(color: Colors.grey),
        )
      else ...[
        Text(
          'Trim: ${clip.trimStart.toStringAsFixed(1)}s – '
          '${clip.effectiveEnd.toStringAsFixed(1)}s '
          '(kul ${dur.toStringAsFixed(1)}s)',
        ),
        RangeSlider(
          values: RangeValues(clip.trimStart, clip.effectiveEnd),
          min: 0,
          max: dur,
          divisions: (clip.duration.inMilliseconds / 100).round().clamp(1, 1000),
          labels: RangeLabels(
            '${clip.trimStart.toStringAsFixed(1)}s',
            '${clip.effectiveEnd.toStringAsFixed(1)}s',
          ),
          onChangeStart: (_) => host.pushHistory(),
          onChanged: (v) {
            if (v.end - v.start < 0.5) return;
            host.update(() {
              clip.trimStart = v.start;
              clip.trimEnd = v.end;
            });
          },
        ),
        Row(
          children: [
            const Text('Start (fine)'),
            Expanded(
              child: Slider(
                value: clip.trimStart.clamp(0, dur),
                min: 0,
                max: dur,
                onChangeStart: (_) => host.pushHistory(),
                onChanged: (v) {
                  if (clip.effectiveEnd - v < 0.5) return;
                  host.update(() => clip.trimStart = v);
                },
              ),
            ),
            Text('${clip.trimStart.toStringAsFixed(1)}s'),
          ],
        ),
        Row(
          children: [
            const Text('End (fine)'),
            Expanded(
              child: Slider(
                value: clip.effectiveEnd.clamp(0, dur),
                min: 0,
                max: dur,
                onChangeStart: (_) => host.pushHistory(),
                onChanged: (v) {
                  if (v - clip.trimStart < 0.5) return;
                  host.update(() => clip.trimEnd = v);
                },
              ),
            ),
            Text('${clip.effectiveEnd.toStringAsFixed(1)}s'),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            TextButton.icon(
              onPressed: host.splitSelectedClip,
              icon: const Icon(Icons.content_cut, size: 18),
              label: const Text('Split'),
            ),
            TextButton.icon(
              onPressed: host.busy ? null : host.saveFrameSnapshot,
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('Frame'),
            ),
            TextButton.icon(
              onPressed: host.busy ? null : host.freezeFrameInsert,
              icon: const Icon(Icons.ac_unit, size: 18),
              label: const Text('Freeze'),
            ),
            TextButton.icon(
              onPressed: host.busy ? null : host.extractClipAudio,
              icon: const Icon(Icons.audio_file_outlined, size: 18),
              label: const Text('Extract audio'),
            ),
            TextButton.icon(
              onPressed: host.busy ? null : host.deleteSelectedClip,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
            ),
          ],
        ),
      ],
      SectionTitle('Canvas'),
      iconChoiceRail(host, [
        for (final a in const [
          ('Original', Icons.photo_size_select_actual),
          ('9:16', Icons.crop_portrait),
          ('16:9', Icons.crop_landscape),
          ('1:1', Icons.crop_square),
          // Phase 1 (Build 2): 4:5 completes the chain — the
          // stage frame and the export dims both honour it now.
          ('4:5', Icons.crop_portrait),
        ])
          iconChoiceItem(host, 
            icon: a.$2,
            label: a.$1,
            selected: host.aspect == a.$1,
            onTap: () => host.update(() => host.aspect = a.$1),
          ),
      ]),
      // Phase 1 (Build 2): stage guides + the interactive-canvas
      // hint. The switch mirrors the stage's corner toggle.
      Row(
        children: [
          const Icon(Icons.grid_on, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          const Expanded(child: Text('Grid + safe zones (stage par)')),
          Switch(
            value: host.showGrid,
            onChanged: (v) => host.update(() => host.showGrid = v),
          ),
        ],
      ),
      const Text(
        'Stage par do unglion se pinch karke zoom, aik ungli se '
        'ghuma kar pan, do unglion se rotate karein — double tap '
        'reset. Yehi transform export mein bhi lagta hai.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const SizedBox(height: 6),
      const Text('Fill'),
      const SizedBox(height: 4),
      iconChoiceRail(host, [
        for (final e in const [
          ('none', 'Crop', Icons.crop),
          ('blur', 'Blur', Icons.blur_on),
          ('color', 'Colour', Icons.palette),
        ])
          iconChoiceItem(host, 
            icon: e.$3,
            label: e.$2,
            selected: host.canvasFill == e.$1,
            onTap: () => host.update(() => host.canvasFill = e.$1),
          ),
      ]),
      if (host.canvasFill == 'color') ...[
        const SizedBox(height: 6),
        const Text('Fill colour'),
        const SizedBox(height: 4),
        iconChoiceRail(host, [
          for (final e in const [
            ('black', 'Black', Color(0xFF000000)),
            ('white', 'White', Color(0xFFFFFFFF)),
            ('0x1A1A2E', 'Navy', Color(0xFF1A1A2E)),
            ('0x7C3AED', 'Purple', Color(0xFF7C3AED)),
          ])
            iconChoiceItem(host, 
              icon: Icons.circle,
              iconColor: e.$3,
              label: e.$2,
              selected: host.canvasFillColor == e.$1,
              onTap: () => host.update(() => host.canvasFillColor = e.$1),
            ),
        ]),
      ],
      SectionTitle('Intro / outro attach'),
      Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () async {
                final picked =
                    await host.picker.pickVideo(source: ImageSource.gallery);
                // Phase 0 sweep: setState after an await needs the
                // mounted check (the picker can outlive the screen).
                if (picked != null && host.mounted) {
                  host.update(() => host.introClipPath = picked.path);
                }
              },
              icon: const Icon(Icons.movie_creation_outlined),
              label: Text(
                host.introClipPath == null
                    ? 'Intro chunein'
                    : p.basename(host.introClipPath!),
              ),
            ),
          ),
          if (host.introClipPath != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => host.update(() => host.introClipPath = null),
            ),
        ],
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () async {
                final picked =
                    await host.picker.pickVideo(source: ImageSource.gallery);
                if (picked != null && host.mounted) {
                  host.update(() => host.outroClipPath = picked.path);
                }
              },
              icon: const Icon(Icons.movie_filter_outlined),
              label: Text(
                host.outroClipPath == null
                    ? 'Outro chunein'
                    : p.basename(host.outroClipPath!),
              ),
            ),
          ),
          if (host.outroClipPath != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => host.update(() => host.outroClipPath = null),
            ),
        ],
      ),
      const Text(
        'Attach export ke aakhir mein lagta hai: intro sab se '
        'pehle, outro sab se aakhir mein (export size par '
        'normalise karke).',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const Divider(height: 32),
    ];
  }
  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
