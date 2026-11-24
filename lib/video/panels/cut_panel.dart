/// CutPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../editor_models.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// CutPanel.
class CutPanel extends StatelessWidget {
  final VideoEditorController host;
  const CutPanel(this.host, {super.key});

  /// Precut › Cut: choose a range INSIDE the selected clip and
  /// remove it — the clip becomes two clips (before / after).
  List<Widget> buildChildren(BuildContext context) {
    final clip = host.clips.isEmpty ? null : host.clips[host.selected];
    if (clip == null) {
      return const [
        Text(
          'Pehle timeline se clip select karein.',
          style: TextStyle(color: Colors.grey),
        ),
      ];
    }
    final start = clip.trimStart;
    final end = clip.effectiveEnd;
    final cutStart = host.cutStart.clamp(start, end);
    final cutEnd = host.cutEnd.clamp(start, end);
    return [
      SectionTitle('Cut — darmiyan ka hissa hatayein'),
      Text(
        'Clip range: ${start.toStringAsFixed(1)}s – '
        '${end.toStringAsFixed(1)}s',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
      ProSlider(
        label: 'Cut start',
        value: cutStart,
        min: start,
        max: end,
        divisions: 100,
        onChanged: (v) => host.update(() => host.cutStart = v),
      ),
      ProSlider(
        label: 'Cut end',
        value: cutEnd,
        min: start,
        max: end,
        divisions: 100,
        onChanged: (v) => host.update(() => host.cutEnd = v),
      ),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: host.busy ? null : () => _applyCutRange(context),
          icon: const Icon(Icons.cut),
          label: const Text('Cut hatao (2 clips ban jayenge)'),
        ),
      ),
      const Divider(height: 32),
    ];
  }

  /// Applies Precut › Cut: replaces the selected clip with its
  /// [trimStart..cutStart] and [cutEnd..effectiveEnd] parts.
  void _applyCutRange(BuildContext context) {
    if (host.clips.isEmpty || host.busy) return;
    final idx = host.selected;
    final clip = host.clips[idx];
    final start = clip.trimStart;
    final end = clip.effectiveEnd;
    final cs = host.cutStart.clamp(start, end);
    final ce = host.cutEnd.clamp(start, end);
    if (ce - cs < 0.2) {
      host.setStatus('Cut range bohat chhota hai — start/end badhayein.');
      return;
    }
    if (cs <= start + 0.05 && ce >= end - 0.05) {
      host.setStatus('Poori clip cut ho jayegi — Delete use karein.');
      return;
    }
    host.pushHistory();
    final parts = <VideoClip>[];
    if (cs > start + 0.05) {
      parts.add(clip.copy()..trimEnd = cs);
    }
    if (ce < end - 0.05) {
      parts.add(clip.copy()..trimStart = ce);
    }
    host.update(() {
      host.clips.replaceRange(idx, idx + 1, parts);
      host.selected = idx;
    });
    host.setStatus('Cut lag gaya — ${parts.length} clip(s) reh gaye.');
    unawaited(host.loadPreview());
  }
  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
