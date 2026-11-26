/// AiCutPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../services/ffmpeg_service.dart';
import '../editor_models.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// AiCutPanel.
class AiCutPanel extends StatelessWidget {
  final VideoEditorController host;
  const AiCutPanel(this.host, {super.key});

  /// AI Cut panel: on-device silence removal (ffmpeg
  /// silencedetect) — scan the selected clip, list the silence
  /// ranges, then rebuild the clip from the keep segments.
  List<Widget> buildChildren(BuildContext context) {
    final clip = host.clips.isEmpty ? null : host.clips[host.selected];
    return [
      SectionTitle('AI Cut — remove silence'),
      const Text(
        'On-device scan: the silent parts are found and cut out '
        'are removed (filler / pauses). No cloud or sign-in.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      if (clip == null)
        const Text(
          'Select a clip first.',
          style: TextStyle(color: Colors.grey),
        )
      else ...[
        ProSlider(
          label: 'Silence threshold (dB)',
          value: host.aicutThresholdDb,
          min: -60,
          max: -10,
          divisions: 50,
          onChanged: (v) => host.update(() => host.aicutThresholdDb = v),
        ),
        ProSlider(
          label: 'Kam az kam silence (s)',
          value: host.aicutMinSilenceSec,
          min: 0.2,
          max: 2,
          divisions: 18,
          onChanged: (v) => host.update(() => host.aicutMinSilenceSec = v),
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: host.aicutBusy ? null : () => _scanSilence(context),
            icon: const Icon(Icons.search),
            label: Text(host.aicutBusy ? 'Scanning…' : 'Scan silence'),
          ),
        ),
        if (host.aicutRanges.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${host.aicutRanges.length} silence ranges found:',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          for (final r in host.aicutRanges)
            Text(
              '${r.$1.toStringAsFixed(1)}s – ${r.$2.toStringAsFixed(1)}s',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: host.aicutBusy ? null : () => _applyAiCut(context),
              icon: const Icon(Icons.content_cut),
              label: const Text('Cut to create a new clip'),
            ),
          ),
        ],
      ],
      const Divider(height: 32),
    ];
  }

  /// Runs silencedetect on the selected clip and parses the
  /// silence_start / silence_end pairs out of the ffmpeg log.
  Future<void> _scanSilence(BuildContext context) async {
    if (host.clips.isEmpty || host.aicutBusy) return;
    final clip = host.clips[host.selected];
    host.update(() {
      host.aicutBusy = true;
      host.aicutRanges = const [];
    });
    try {
      final res = await FfmpegService.run(
        '-i ${FfmpegService.q(clip.file.path)} '
        '-af silencedetect=noise=${host.aicutThresholdDb.toStringAsFixed(0)}dB'
        ':d=${host.aicutMinSilenceSec.toStringAsFixed(2)} '
        '-f null -',
      );
      final starts = <double>[];
      final ranges = <(double, double)>[];
      for (final m in RegExp(r'silence_(start|end): ([\d.]+)')
          .allMatches(res.logs)) {
        final value = double.tryParse(m.group(2) ?? '') ?? 0;
        if (m.group(1) == 'start') {
          starts.add(value);
        } else if (starts.isNotEmpty) {
          ranges.add((starts.removeAt(0), value));
        }
      }
      // An unterminated silence runs to the end of the file.
      final fileEnd = clip.duration.inMilliseconds / 1000;
      for (final s in starts) {
        ranges.add((s, fileEnd));
      }
      if (!host.mounted) return;
      host.update(() => host.aicutRanges = ranges);
      host.setStatus(
        ranges.isEmpty
            ? 'No silence found — try lowering the threshold.'
            : '${ranges.length} silence ranges found.',
      );
    } catch (e) {
      host.setStatus('Silence scan failed: $e');
    } finally {
      if (host.mounted) host.update(() => host.aicutBusy = false);
    }
  }

  /// Rebuilds the selected clip from the KEEP segments (its trimmed
  /// range minus the scanned silences) via one trim/concat graph.
  Future<void> _applyAiCut(BuildContext context) async {
    if (host.clips.isEmpty || host.aicutBusy || host.aicutRanges.isEmpty) return;
    final idx = host.selected;
    final clip = host.clips[idx];
    final start = clip.trimStart;
    final end = clip.effectiveEnd;
    final keeps = <(double, double)>[];
    var cursor = start;
    for (final r in host.aicutRanges) {
      final s = r.$1.clamp(start, end);
      final e = r.$2.clamp(start, end);
      if (s > cursor + 0.05) keeps.add((cursor, s));
      if (e > cursor) cursor = e;
    }
    if (cursor < end - 0.05) keeps.add((cursor, end));
    if (keeps.isEmpty) {
      host.setStatus('The whole clip is silence — nothing will remain.');
      return;
    }
    if (keeps.length == 1 && keeps.first.$1 == start && keeps.first.$2 == end) {
      host.setStatus('No silence in the trim range — the clip stays as it is.');
      return;
    }
    host.update(() => host.aicutBusy = true);
    try {
      final dir = await host.workDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final out = p.join(dir.path, 'aicut_$stamp.mp4');
      String graph(bool withAudio) {
        final b = StringBuffer();
        for (var i = 0; i < keeps.length; i++) {
          b.write(
            '[0:v]trim=start=${keeps[i].$1}:end=${keeps[i].$2},'
            'setpts=PTS-STARTPTS[v$i];',
          );
          if (withAudio) {
            b.write(
              '[0:a]atrim=start=${keeps[i].$1}:end=${keeps[i].$2},'
              'asetpts=PTS-STARTPTS[a$i];',
            );
          }
        }
        final inputs = keeps
            .asMap()
            .entries
            .map((e) => withAudio
                ? '[v${e.key}][a${e.key}]'
                : '[v${e.key}]')
            .join();
        b.write(
          '${inputs}concat=n=${keeps.length}:v=1:a=${withAudio ? 1 : 0}'
          '[outv]${withAudio ? '[outa]' : ''}',
        );
        return b.toString();
      }

      var res = await FfmpegService.run(
        '-i ${FfmpegService.q(clip.file.path)} '
        '-filter_complex "${graph(true)}" -map "[outv]" -map "[outa]" '
        '-c:v libx264 -preset veryfast -crf 23 -c:a aac -b:a 128k '
        '-y ${FfmpegService.q(out)}',
      );
      if (!res.ok) {
        res = await FfmpegService.run(
          '-i ${FfmpegService.q(clip.file.path)} '
          '-filter_complex "${graph(false)}" -map "[outv]" '
          '-c:v libx264 -preset veryfast -crf 23 '
          '-y ${FfmpegService.q(out)}',
        );
      }
      if (!res.ok) {
        host.setStatus('AI Cut failed. ${res.logs}');
        return;
      }
      // Phase 0 sweep: the setState below sat after two ffmpeg
      // awaits with NO mounted check — leaving the editor during
      // an AI Cut crashed on completion.
      if (!host.mounted) return;
      final keepTotal =
          keeps.fold(0.0, (sum, k) => sum + (k.$2 - k.$1));
      host.pushHistory();
      host.update(() {
        final nc = VideoClip(
          File(out),
          Duration(milliseconds: (keepTotal * 1000).round()),
          clip.aspectRatio,
        );
        nc.volume = clip.volume;
        nc.muted = clip.muted;
        host.clips[idx] = nc;
        host.aicutRanges = const [];
      });
      host.setStatus('AI Cut ready — silence removed.');
      await host.loadPreview();
    } catch (e) {
      host.setStatus('AI Cut failed: $e');
    } finally {
      if (host.mounted) host.update(() => host.aicutBusy = false);
    }
  }
  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
