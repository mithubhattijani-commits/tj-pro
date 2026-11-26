/// KeyframesPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../../services/pro_editor.dart';
import '../video_editor_controller.dart';
import '../video_editor_panels.dart';
import '../widgets/panel_controls.dart';

/// KeyframesPanel.
class KeyframesPanel extends StatelessWidget {
  final VideoEditorController host;
  const KeyframesPanel(this.host, {super.key});

  /// Overlay › Keyframes: easing chips + curve graph on top, then
  /// the Start OR End keyframe sliders (§5A — one page at a time).
  List<Widget> buildChildren(BuildContext context) {
    final body = panelBody(host, context, 'stickers');
    final kfIdx =
        anchorIndex(body, (w) => isTextStarting(w, 'Keyframes animate'));
    if (kfIdx < 0) return body;
    final slice = body.sublist(kfIdx);
    final startIdx =
        anchorIndex(slice, (w) => isTextStarting(w, 'Start keyframe'));
    final endIdx =
        anchorIndex(slice, (w) => isTextStarting(w, 'End keyframe'));
    if (startIdx < 0 || endIdx < 0) return slice;
    final header = slice.sublist(0, startIdx);
    final startSliders = slice.sublist(startIdx, endIdx);
    final endSliders = slice.sublist(endIdx);
    return [
      ...header,
      if (host.proKeyframes &&
          (host.proTitle.trim().isNotEmpty || host.proSticker.trim().isNotEmpty)) ...[
        const Text('Motion easing',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        iconChoiceRail(host, [
          for (final e in KeyframeEasing.values)
            iconChoiceItem(host, 
              icon: switch (e) {
                KeyframeEasing.linear => Icons.trending_flat,
                KeyframeEasing.easeIn => Icons.trending_up,
                KeyframeEasing.easeOut => Icons.trending_down,
                KeyframeEasing.easeInOut => Icons.show_chart,
              },
              label: keyframeEasingLabel(e).split(' (').first,
              selected: host.kfEasing == e,
              onTap: () => host.update(() => host.kfEasing = e),
            ),
        ]),
        Container(
          height: 56,
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1B1B),
            borderRadius: BorderRadius.circular(8),
          ),
          child: CustomPaint(
            painter: EasingCurvePainter(host.kfEasing),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 4),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Start keyframe')),
            ButtonSegment(value: 1, label: Text('End keyframe')),
          ],
          selected: {host.kfPage},
          onSelectionChanged: (v) => host.update(() => host.kfPage = v.first),
        ),
        const SizedBox(height: 8),
      ],
      if (host.kfPage == 0) ...startSliders else ...endSliders,
      ..._pipKeyframeWidgets(context),
    ];
  }

  /// Build 3 (Phase 3): the PIP layer's keyframes — a second
  /// two-keyframe track (position + opacity, the v1 scope for
  /// video layers) edited beside the title/sticker track in the
  /// Animation panel, with its own Start/End page ([_pkPage]) and
  /// easing ([_pkEasing]). The export runs [keyframedPipFilter];
  /// the stage preview interpolates with [keyframePoseAt] — the
  /// same lerp on both sides.
  List<Widget> _pipKeyframeWidgets(BuildContext context) {
    if (!host.fxPip) {
      return [
        const Divider(height: 32),
        SectionTitle('PIP keyframes'),
        const Text(
          'For PIP keyframes, add PIP first — then the inset '
          'ki position / opacity yahan start se end tak animate '
          'will be.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ];
    }
    return [
      const Divider(height: 32),
      SectionTitle('PIP keyframes'),
      SwitchListTile(
        title: const Text('PIP keyframes (position + opacity)'),
        subtitle: const Text(
          'The inset will move / fade from the start pose to the end pose — '
          'poori video ki lambai par.',
        ),
        value: host.pipKeyframes,
        onChanged: (v) => host.update(() => host.pipKeyframes = v),
      ),
      if (host.pipKeyframes) ...[
        const Text(
          'Motion easing',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        iconChoiceRail(host, [
          for (final e in KeyframeEasing.values)
            iconChoiceItem(host, 
              icon: switch (e) {
                KeyframeEasing.linear => Icons.trending_flat,
                KeyframeEasing.easeIn => Icons.trending_up,
                KeyframeEasing.easeOut => Icons.trending_down,
                KeyframeEasing.easeInOut => Icons.show_chart,
              },
              label: keyframeEasingLabel(e).split(' (').first,
              selected: host.pkEasing == e,
              onTap: () => host.update(() => host.pkEasing = e),
            ),
        ]),
        const SizedBox(height: 4),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('Start keyframe')),
            ButtonSegment(value: 1, label: Text('End keyframe')),
          ],
          selected: {host.pkPage},
          onSelectionChanged: (v) => host.update(() => host.pkPage = v.first),
        ),
        const SizedBox(height: 8),
        if (host.pkPage == 0) ...[
          ProSlider(
            label: 'Start X',
            value: host.pkStartX,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: (v) => host.update(() => host.pkStartX = v),
          ),
          ProSlider(
            label: 'Start Y',
            value: host.pkStartY,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: (v) => host.update(() => host.pkStartY = v),
          ),
          ProSlider(
            label: 'Start opacity',
            value: host.pkStartOpacity,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: (v) => host.update(() => host.pkStartOpacity = v),
          ),
        ] else ...[
          ProSlider(
            label: 'End X',
            value: host.pkEndX,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: (v) => host.update(() => host.pkEndX = v),
          ),
          ProSlider(
            label: 'End Y',
            value: host.pkEndY,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: (v) => host.update(() => host.pkEndY = v),
          ),
          ProSlider(
            label: 'End opacity',
            value: host.pkEndOpacity,
            min: 0,
            max: 1,
            divisions: 20,
            onChanged: (v) => host.update(() => host.pkEndOpacity = v),
          ),
        ],
        const Text(
          'When keyframes are on, instead of the static PIP opacity, the track '
          'opacity applies. With blend mode, keyframes do not '
          'chalte — static PIP lagega. Timeline ki Keyframes lane '
          '◆ points show.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    ];
  }
  @override
  Widget build(BuildContext context) =>
      panelDrillOrColumn(host, buildChildren(context));
}
