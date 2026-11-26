/// LegacyCaptionsPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/caption_service.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// Legacy 'captions' panel.
class LegacyCaptionsPanel extends StatelessWidget {
  final VideoEditorController host;
  const LegacyCaptionsPanel(this.host, {super.key});

  List<Widget> buildChildren(BuildContext context) {
        return [
SectionTitle('Auto Captions (CapCut-style)'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: iconChoiceRail(host, [
                  iconChoiceItem(host, 
                    icon: Icons.translate,
                    label: 'Urdu',
                    selected: host.captionLocale == 'ur',
                    onTap: () => host.update(() => host.captionLocale = 'ur'),
                  ),
                  iconChoiceItem(host, 
                    icon: Icons.abc,
                    label: 'English',
                    selected: host.captionLocale == 'en',
                    onTap: () => host.update(() => host.captionLocale = 'en'),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      (host.transcribing || host.busy) ? null : host.generateCaptions,
                  icon: const Icon(Icons.closed_caption),
                  label: Text(
                    host.transcribing ? 'Transcribing…' : 'Generate Auto Captions',
                  ),
                ),
              ),
            ],
          ),
          if (host.transcribing) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Creating captions from the video\'s own audio…',
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          SectionTitle('Caption style'),
          const SizedBox(height: 4),
          iconChoiceRail(host, [
            for (final e in const [
              (CaptionStyle.standard, 'Default', Icons.closed_caption),
              (CaptionStyle.highlight, 'Highlight', Icons.highlight),
              (CaptionStyle.gold, 'Gold', Icons.star),
              (CaptionStyle.clean, 'Clean', Icons.format_clear),
              (CaptionStyle.pop, 'Pop', Icons.bolt),
              (CaptionStyle.boxed, 'Boxed', Icons.check_box_outline_blank),
            ])
              iconChoiceItem(host, 
                icon: e.$3,
                label: e.$2,
                selected: host.captionStyle == e.$1,
                onTap: () => host.update(() => host.captionStyle = e.$1),
              ),
          ]),
          if (host.captions.isNotEmpty && !host.transcribing) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${host.captions.length} caption segments ready — they will burn onto the video in the export.',
                  ),
                ),
                TextButton(
                  onPressed: host.editCaptions,
                  child: const Text('Edit'),
                ),
                TextButton(
                  onPressed: () => host.update(() => host.captions = []),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          // A2 (v1.12): SRT/VTT import + export/share.
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: host.busy ? null : host.importCaptionsFile,
                  icon: const Icon(Icons.file_open_outlined, size: 18),
                  label: const Text('SRT/VTT Import'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: host.captions.isEmpty
                      ? null
                      : () => _shareSheet(context),
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Export / Share'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Note: captions are created on-device from the video\'s own audio (Whisper, Urdu/English) — no mic, quiet room or earphones needed. The first time, a ~75 MB caption model will download (with progress); after that everything happens on the phone, offline.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
        ];
  }

  /// A2 (v1.12): choose the subtitle format, then share the
  /// file through the system share sheet.
  void _shareSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.closed_caption, color: Colors.white),
              title: const Text(
                'Share SRT file',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                unawaited(host.shareCaptionsFile('srt'));
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.closed_caption_outlined,
                color: Colors.white,
              ),
              title: const Text(
                'Share VTT file',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                unawaited(host.shareCaptionsFile('vtt'));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}
