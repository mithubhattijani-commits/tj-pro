/// Shared reel-export card for the News Maker and the One Click AI
/// News Maker (Phase 7).
///
/// REAL controls, no fake buttons:
///   - Quality selector (720p / 1080p / 4K) — becomes the export
///     screen's starting quality.
///   - "Open in Timeline" — saves the project, then opens the video
///     editor with the project loaded (clips + voiceover + template +
///     captions — see `lib/news/project_handoff.dart`).
///   - "Export Reel" — opens the real Phase 9 export screen
///     (`lib/news/export_screen.dart`: quality / fps / bitrate /
///     audio / aspect + size estimate + live progress + retry +
///     poster export). The card itself no longer runs the bare
///     export call.
///   - Intro state row — shows whether the 10 s intro is cached, and
///     offers a real download only when a download URL is configured;
///     when the intro is not hosted yet the row says so plainly and
///     the export runs without it (never a fake "intro added").
library;

import 'package:flutter/material.dart';

import '../../app_config.dart';
import '../../services/asset_download_service.dart';
import '../../services/reel_export_service.dart';
import '../../video/video_editor_screen.dart';
import '../breaking_templates.dart';
import '../channel_preset.dart';
import '../export_screen.dart';
import '../news_project.dart';

class ReelExportCard extends StatefulWidget {
  const ReelExportCard({
    super.key,
    required this.project,
    required this.preset,
  });

  final NewsProject project;
  final ChannelPreset preset;

  @override
  State<ReelExportCard> createState() => _ReelExportCardState();
}

class _ReelExportCardState extends State<ReelExportCard> {
  int _quality = 0;

  /// Built-in background music selection (v1.2.0 §2.4): a
  /// [BuiltInNewsMusic] asset path, or null = none. Persisted on
  /// the project the moment it changes. Built-in music is FREE.
  String? _musicAsset;

  IntroAvailability? _intro;
  bool _introBusy = false;
  String _introMessage = '';

  @override
  void initState() {
    super.initState();
    _musicAsset = widget.project.backgroundMusicAsset;
    _checkIntro();
  }

  void _selectMusic(String? assetPath) {
    setState(() => _musicAsset = assetPath);
    widget.project.backgroundMusicAsset = assetPath;
    NewsProjectStore.save(widget.project);
  }

  Future<void> _checkIntro() async {
    final state = await ReelExportService.introState();
    if (!mounted) return;
    setState(() => _intro = state);
  }

  Future<void> _downloadIntro() async {
    if (_introBusy) return;
    setState(() {
      _introBusy = true;
      _introMessage = 'Intro is downloading…';
    });
    try {
      await const AssetDownloadService().getIntroVideo(
        url: AppConfig.nigraanIntroUrl,
      );
      if (!mounted) return;
      setState(() {
        _intro = IntroAvailability.ready;
        _introMessage = 'Intro downloaded — it will apply in the export.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _introMessage = 'Intro did not download: $e');
    } finally {
      if (mounted) setState(() => _introBusy = false);
    }
  }

  Future<void> _openTimeline() async {
    await NewsProjectStore.save(widget.project);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoEditorScreen(
          project: widget.project,
          preset: widget.preset,
        ),
      ),
    );
  }

  Future<void> _export() async {
    // Phase 9 — the card no longer runs the bare export call: it
    // opens the real export screen (quality / fps / bitrate / audio
    // / aspect + size estimate + live progress + retry + poster).
    // The card's quality selector becomes the screen's starting
    // quality.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExportScreen(
          project: widget.project,
          preset: widget.preset,
          initialQuality: _quality,
        ),
      ),
    );
  }

  String get _qualityLabel => switch (_quality) {
        1 => '1080p',
        2 => '4K',
        _ => '720p',
      };

  @override
  Widget build(BuildContext context) {
    final intro = _intro;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Export Reel',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.project.clipPaths.length} clips • '
              '${widget.project.voiceoverPath == null ? 'voiceover nahi bani' : 'voiceover tayyar'} • '
              '${widget.project.templateKind == 'nigraanFinal' ? 'Final 3-Ribbon' : widget.project.templateKind == 'breaking' ? 'Breaking' : 'Classic'} template',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              key: const Key('exportQualitySelector'),
              segments: const [
                ButtonSegment(value: 0, label: Text('720p')),
                ButtonSegment(value: 1, label: Text('1080p')),
                ButtonSegment(value: 2, label: Text('4K')),
              ],
              selected: {_quality},
              onSelectionChanged: (s) => setState(() => _quality = s.first),
            ),
            if (widget.project.videoTemplateId.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Video intro: '
                '${VideoIntroTemplate.fromId(widget.project.videoTemplateId)?.label ?? widget.project.videoTemplateId}'
                ' • Ticker direction: '
                '${widget.project.effectiveTickerDirection == RibbonDirection.rtl ? 'Left' : 'Right'}',
                key: const Key('exportVideoIntroLine'),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Background music — built-in (FREE)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('exportMusic-none'),
                  label: const Text('No music'),
                  selected: _musicAsset == null,
                  onSelected: (_) => _selectMusic(null),
                ),
                ...BuiltInNewsMusic.defaults().map((music) {
                  return ChoiceChip(
                    key: Key('exportMusic-${music.id}'),
                    label: Text('${music.label} • FREE'),
                    selected: _musicAsset == music.assetPath,
                    onSelected: (_) => _selectMusic(music.assetPath),
                  );
                }),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    intro == null
                        ? 'Checking the intro…'
                        : intro == IntroAvailability.ready
                            ? 'Intro (10s): ready — it will apply in the export.'
                            : intro == IntroAvailability.notDownloaded
                                ? 'Intro (10s): not downloaded yet.'
                                : 'Intro (10s): not hosted yet — the export will happen without the intro.',
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
                if (intro == IntroAvailability.notDownloaded)
                  TextButton(
                    key: const Key('downloadIntroButton'),
                    onPressed: _introBusy ? null : _downloadIntro,
                    child: Text(
                      _introBusy ? 'Download…' : 'Download',
                    ),
                  ),
              ],
            ),
            if (_introMessage.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _introMessage,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('openTimelineButton'),
                    onPressed: _openTimeline,
                    child: const Text('Open in Timeline'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const Key('exportReelButton'),
                    onPressed: _export,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                    ),
                    child: Text('Export Reel • $_qualityLabel'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'The export screen has quality, FPS, bitrate, audio and a size '
              'estimate are available — the export happens from there.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
