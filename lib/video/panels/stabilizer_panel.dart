/// StabilizerPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController].
library;

import 'dart:async';

import 'package:flutter/material.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// StabilizerPanel.
///
/// v1.17.0 (G5, Point #37b/c): picking a level BAKES the
/// stabilization immediately — every clip is rendered once,
/// right here, with progress — and the export only assembles
/// the baked files. Before v1.17.0 the whole two-pass vidstab
/// ran at EXPORT time over the assembled video, which is
/// exactly what the user saw crawling in the export progress
/// ("Stabilization: analysing motion (pass 1 of 2)…") and a
/// big part of why exports felt slow.
class StabilizerPanel extends StatelessWidget {
  final VideoEditorController host;
  const StabilizerPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
    final level = host.stabLevel;
    return [
      SectionTitle('Stabilizer'),
      iconChoiceRail(host, [
        for (final e in const [
          (0, 'Original', Icons.block),
          (1, 'Low', Icons.videocam),
          (2, 'Standard', Icons.video_stable),
          (3, 'Most Stable', Icons.video_stable),
        ])
          iconChoiceItem(
            host,
            icon: e.$3,
            label: e.$2,
            selected: level == e.$1,
            onTap: () => host.update(() {
              host.stabLevel = e.$1;
              host.proStabilize = e.$1 > 0;
              if (e.$1 > 0) {
                // Bake NOW (unawaited: progress lives in this
                // panel + the status line; completion lands in
                // host state).
                unawaited(host.bakeStabilization());
              }
            }),
          ),
      ]),
      const SizedBox(height: 8),
      if (host.stabBaking) ...[
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: host.stabBakeProgress <= 0
                    ? null
                    : host.stabBakeProgress,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Baking… ${(host.stabBakeProgress * 100).round()}%',
              style: const TextStyle(fontSize: 11.5),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: host.cancelStabBake,
              child: const Text('Cancel'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Stabilizing your clips now — when this finishes, the '
          'export is assembly only and stays fast.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ] else if (level > 0 && host.stabPendingClipCount > 0) ...[
        Row(
          children: [
            Expanded(
              child: Text(
                '${host.stabPendingClipCount} clip(s) are not baked '
                'yet at this level.',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: () => unawaited(host.bakeStabilization()),
              child: const Text('Bake now'),
            ),
          ],
        ),
        const Text(
          'Unbaked clips export WITHOUT stabilization — the '
          'export never processes effects.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ] else if (level > 0)
        const Text(
          'All clips are baked at this level — the export is '
          'assembly only.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        )
      else
        const Text(
          'Pick a level and the stabilization renders right '
          'away, clip by clip — nothing is left for the export '
          'to process.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      const Divider(height: 32),
    ];
  }

  @override
  Widget build(BuildContext context) =>
      PanelColumn(children: buildChildren(context));
}
