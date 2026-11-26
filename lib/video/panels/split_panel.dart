/// SplitPanel of the Video Editor (Master Plan Phase 4 split).
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

/// SplitPanel.
class SplitPanel extends StatelessWidget {
  final VideoEditorController host;
  const SplitPanel(this.host, {super.key});

  /// Precut › Split: the snap choice (playhead / midpoint — the
  /// toggle that used to sit in the transport row lives here now),
  /// Split, and Multi Split into N equal parts.
  List<Widget> buildChildren(BuildContext context) {
    return [
      SectionTitle('Split'),
      const Text('Split point'),
      const SizedBox(height: 4),
      iconChoiceRail(host, [
        iconChoiceItem(host, 
          icon: Icons.push_pin,
          label: 'Playhead par',
          selected: host.snapOn,
          onTap: () => host.update(() => host.snapOn = true),
        ),
        iconChoiceItem(host, 
          icon: Icons.horizontal_rule,
          label: 'Darmiyan se',
          selected: !host.snapOn,
          onTap: () => host.update(() => host.snapOn = false),
        ),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: host.busy || host.clips.isEmpty ? null : host.splitSelectedClip,
          icon: const Icon(Icons.call_split),
          label: const Text('Split karein'),
        ),
      ),
      SectionTitle('Multi split'),
      iconChoiceRail(host, [
        for (final n in const [2, 3, 4, 5])
          iconChoiceItem(host, 
            icon: Icons.grid_view,
            label: '$n hisse',
            selected: false,
            onTap: host.busy || host.clips.isEmpty ? null : () => _multiSplit(context, n),
          ),
      ]),
      const Divider(height: 32),
    ];
  }

  /// Multi Split: the selected clip becomes [n] equal-length clips
  /// (trim copies — no re-encode).
  void _multiSplit(BuildContext context, int n) {
    if (host.clips.isEmpty || host.busy) return;
    final idx = host.selected;
    final clip = host.clips[idx];
    final start = clip.trimStart;
    final step = clip.effectiveDuration / n;
    if (step < 0.3) {
      host.setStatus('Clip bohat chhoti hai $n hisson ke liye.');
      return;
    }
    host.pushHistory();
    final parts = <VideoClip>[];
    for (var i = 0; i < n; i++) {
      final part = clip.copy();
      part.trimStart = start + step * i;
      part.trimEnd = start + step * (i + 1);
      parts.add(part);
    }
    host.update(() {
      host.clips.replaceRange(idx, idx + 1, parts);
      host.selected = idx;
    });
    host.setStatus('Multi split — $n clips ban gaye.');
    unawaited(host.loadPreview());
  }
  @override
  Widget build(BuildContext context) =>
      panelDrillOrColumn(host, buildChildren(context));
}
