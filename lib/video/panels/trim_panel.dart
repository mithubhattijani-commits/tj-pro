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
      // ── v1.14.0 T2: Trim modes (A6 Roll / A7 Slip / A25
      // trim-to-playhead). The mode changes what the timeline
      // trim HANDLES do; the buttons here are the precise,
      // testable path to the same operations.
      SectionTitle('Trim mode'),
      iconChoiceRail(host, [
        KeyedSubtree(
          key: const Key('trimModeTrim'),
          child: iconChoiceItem(host,
            icon: Icons.content_cut,
            label: 'Trim',
            selected: host.trimMode == 'trim',
            onTap: () => host.update(() => host.trimMode = 'trim'),
          ),
        ),
        KeyedSubtree(
          key: const Key('trimModeRoll'),
          child: iconChoiceItem(host,
            icon: Icons.swap_horiz,
            label: 'Roll',
            selected: host.trimMode == 'roll',
            onTap: () => host.update(() => host.trimMode = 'roll'),
          ),
        ),
        KeyedSubtree(
          key: const Key('trimModeSlip'),
          child: iconChoiceItem(host,
            icon: Icons.compare_arrows,
            label: 'Slip',
            selected: host.trimMode == 'slip',
            onTap: () => host.update(() => host.trimMode = 'slip'),
          ),
        ),
      ]),
      if (host.trimMode == 'roll') ...[
        const Text(
          'Roll: do clips ke darmiyan ki boundary hile gi — aik '
          'clip lamba, dusra chhota, kul lambai waisi ki waisi. '
          'Timeline par handle ghaseetein ya ye buttons dabayein '
          '(selected clip ki peechay wali boundary).',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        Row(
          children: [
            TextButton.icon(
              key: const Key('rollNudgeBack'),
              onPressed: clip == null
                  ? null
                  : () => host.rollBoundaryBy(
                      host.selected, -(1 / host.exportFps)),
              icon: const Icon(Icons.remove, size: 18),
              label: const Text('1 frame'),
            ),
            TextButton.icon(
              key: const Key('rollNudgeNext'),
              onPressed: clip == null
                  ? null
                  : () => host.rollBoundaryBy(
                      host.selected, 1 / host.exportFps),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('1 frame'),
            ),
          ],
        ),
      ],
      if (host.trimMode == 'slip') ...[
        const Text(
          'Slip: clip apni jagah par rehta hai, andar ka hissa '
          'aage/peechay sarakta hai. Timeline par clip ko '
          'left/right ghaseetein ya ye buttons dabayein.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        Row(
          children: [
            TextButton.icon(
              key: const Key('slipNudgeBack'),
              onPressed: clip == null || clip.isPhoto
                  ? null
                  : () => host.slipSelectedBy(-0.1),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('0.1s'),
            ),
            TextButton.icon(
              key: const Key('slipNudgeNext'),
              onPressed: clip == null || clip.isPhoto
                  ? null
                  : () => host.slipSelectedBy(0.1),
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text('0.1s'),
            ),
          ],
        ),
      ],
      if (host.trimMode == 'trim') ...[
        const Text(
          'Playhead ko clip ke andar rakhein, phir clip ka start '
          'ya end playhead tak trim karein:',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        Wrap(
          spacing: 6,
          children: [
            TextButton.icon(
              key: const Key('trimToPlayheadStart'),
              onPressed: clip == null ? null : host.trimToPlayheadStart,
              icon: const Icon(Icons.first_page, size: 18),
              label: const Text('Start → playhead'),
            ),
            TextButton.icon(
              key: const Key('trimToPlayheadEnd'),
              onPressed: clip == null ? null : host.trimToPlayheadEnd,
              icon: const Icon(Icons.last_page, size: 18),
              label: const Text('End → playhead'),
            ),
          ],
        ),
      ],
      // ── v1.14.0 T3 (A5): range In/Out on the ruler.
      SectionTitle('Range (In / Out)'),
      Text(
        host.rangeIn != null && host.rangeOut != null
            ? 'Range: ${host.rangeIn!.toStringAsFixed(1)}s – '
                '${host.rangeOut!.toStringAsFixed(1)}s'
            : 'Range nahi laga. Playhead rakhein aur In/Out '
                'lagayein — gold band timeline par nazar aye ga.',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          TextButton.icon(
            key: const Key('rangeSetIn'),
            onPressed:
                host.clips.isEmpty ? null : host.setRangeInAtPlayhead,
            icon: const Icon(Icons.arrow_right_alt, size: 18),
            label: const Text('In lagayein'),
          ),
          TextButton.icon(
            key: const Key('rangeSetOut'),
            onPressed:
                host.clips.isEmpty ? null : host.setRangeOutAtPlayhead,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Out lagayein'),
          ),
          TextButton.icon(
            key: const Key('rangeDelete'),
            onPressed: host.rangeIn != null && host.rangeOut != null
                ? host.deleteRange
                : null,
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('Range delete'),
          ),
          TextButton.icon(
            key: const Key('rangeClear'),
            onPressed: host.rangeIn != null || host.rangeOut != null
                ? host.clearRange
                : null,
            icon: const Icon(Icons.clear, size: 18),
            label: const Text('Saaf'),
          ),
        ],
      ),
      Row(
        children: [
          const Icon(Icons.repeat, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          const Expanded(child: Text('Range loop (play sirf range mein)')),
          Switch(
            key: const Key('rangeLoopSwitch'),
            value: host.loopRange,
            onChanged: host.rangeIn != null && host.rangeOut != null
                ? (v) => host.update(() => host.loopRange = v)
                : null,
          ),
        ],
      ),
      // ── v1.14.0 T1 (A20/A14): timeline ki mukammal settings —
      // header chips sirf jaldi toggle hain, asal ghar ye hai.
      SectionTitle('Timeline'),
      Row(
        children: [
          const Icon(Icons.anchor, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          const Expanded(
              child: Text('Snap (playhead/trim qareebi point par)')),
          Switch(
            key: const Key('tlSnapSwitch'),
            value: host.tlSnapOn,
            onChanged: (v) => host.tlSnapOn = v,
          ),
        ],
      ),
      if (host.tlSnapOn)
        iconChoiceRail(host, [
          for (final s in const [
            (0, 'Halki'),
            (1, 'Normal'),
            (2, 'Mazboot'),
          ])
            KeyedSubtree(
              key: Key('tlSnapStrength${s.$1}'),
              child: iconChoiceItem(host,
                icon: Icons.anchor,
                label: s.$2,
                selected: host.tlSnapStrength == s.$1,
                onTap: () => host.tlSnapStrength = s.$1,
              ),
            ),
        ]),
      Row(
        children: [
          const Icon(Icons.timer_outlined, size: 18, color: Colors.white70),
          const SizedBox(width: 8),
          const Expanded(child: Text('Timecode (H:MM:SS:FF)')),
          Switch(
            key: const Key('tlTimecodeSwitch'),
            value: host.timecodeOn,
            onChanged: (v) => host.timecodeOn = v,
          ),
        ],
      ),
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
  Widget build(BuildContext context) =>
      panelDrillOrColumn(host, buildChildren(context));
}
