/// Real export screen (Phase 9, master prompt §11 + §14).
///
/// The Phase 7 `ReelExportCard` had a quality selector and a bare
/// "Export Reel" call. This screen is the full flow:
///
///   - Quality picker (720p / 1080p / 4K) + FPS (24/30/60) +
///     video bitrate (Auto / 2.5–20 Mbps) + audio bitrate (Auto /
///     128/192/256 kbps) + aspect (9:16 / 16:9 / 1:1) — ALL real:
///     they travel as [ExportSettings] into every FFmpeg encoding
///     pass (see `FfmpegService.normalizeCommand` etc.). Changing a
///     setting changes the command, not just a label.
///   - Estimated output size shown BEFORE the export, from the real
///     formula (duration × bitrate / 8 + overhead) and the project's
///     known duration (voiceover length, else subtitle end). When
///     no duration is known the screen says so instead of inventing
///     a number.
///   - Live per-stage progress: stage name + % from the real ffmpeg
///     statistics callback, mapped into each stage's range (see
///     `ReelExportService.exportReel`). Cancel stops the export
///     between stages (and cancels the in-flight ffmpeg pass).
///   - Error handling with the failed step named + a real Retry
///     button (same settings, re-runs the export).
///   - Finished state: file path, REAL file size (from disk), Open
///     (OpenFilex) + Share (system share sheet) actions, plus the
///     export's honest notes (skipped intro, missing voiceover…).
///   - Thumbnail/poster export: renders the current template frame
///     as a real PNG poster (720×1280 portrait or 1280×720
///     landscape), saves it to the gallery, shareable.
///
/// Honest limits shown on the screen, not hidden:
///   - the ticker in the exported video is STATIC (one PNG frame);
///     a scrolling ticker is deferred — the renderer has no
///     ticker-strip-only output (see `ReelExportService` header).
///   - max 20 clips per project; preview renders are capped at
///     720×1280; 2K/H.265 need a device codec check and are not
///     offered.
///
/// The screen loads nothing async in initState (project + preset
/// arrive as constructor args), so it pumps cleanly in widget
/// tests — unlike the News Studio home's FutureBuilder.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../services/coin_service.dart';
import '../services/crash_guard.dart';
import '../services/export_settings.dart';
import '../services/feature_gate.dart';
import '../services/ffmpeg_service.dart';
import '../services/poster_export_service.dart';
import '../services/reel_export_service.dart';
import '../services/unity_ads_service.dart';
import 'channel_preset.dart';
import 'news_project.dart';

/// Maps the export quality index (0 = 720p, 1 = 1080p, 2 = 4K) to
/// the legacy priced [CoinFeature] (plan §15: 50 / 100 / 200 coins).
/// Pure — unit-tested in test/news_studio_phase10_test.dart.
///
/// v1.2.0: export resolution is NO LONGER charged in coins — Unity
/// interstitials play alongside the export instead (see
/// [UnityAdsService.showExportAds]). This mapping is retained only
/// for legacy compatibility; the export flow does not spend it.
CoinFeature coinFeatureForQuality(int quality) {
  switch (quality) {
    case 1:
      return CoinFeature.export1080p;
    case 2:
      return CoinFeature.export4k;
    default:
      return CoinFeature.export720p;
  }
}

class ExportScreen extends StatefulWidget {
  const ExportScreen({
    super.key,
    required this.project,
    required this.preset,
    this.initialQuality = 0,
  });

  final NewsProject project;
  final ChannelPreset preset;

  /// Quality the card had selected (0 = 720p, 1 = 1080p, 2 = 4K).
  final int initialQuality;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late ExportSettings _settings;
  bool _exporting = false;
  bool _cancelRequested = false;
  double _progress = 0;
  String _status = '';
  String? _error;
  String? _failedStep;
  List<String> _notes = const [];
  String? _savedPath;
  int? _savedSizeBytes;

  PosterSize _posterSize = PosterSize.portrait;
  bool _posterBusy = false;
  String? _posterPath;
  String? _posterMessage;

  @override
  void initState() {
    super.initState();
    _settings = ExportSettings(quality: widget.initialQuality.clamp(0, 2));
  }

  double? get _durationSec =>
      ReelExportService.estimatedDurationSec(widget.project);

  /// Total coin cost of THIS export at the current settings.
  /// v1.2.0: resolution is FREE (720p / 1080p / 4K all cost 0 coins —
  /// Unity interstitials play alongside the export instead). The
  /// only remaining charge is +50 when the preset has chroma key on
  /// — that is the chroma feature's own price, not a resolution
  /// price. Shown on the Export button.
  int get _exportCostCoins =>
      widget.preset.chromaEnabled ? CoinCosts.chromaKey : 0;

  String get _sizeEstimate {
    final label = _settings.estimatedSizeLabel(_durationSec);
    if (label == null) {
      return 'Size estimate: duration maloom nahi — pehle voiceover '
          'banayein ya subtitles hon.';
    }
    return 'Estimated size: $label '
        '(${_durationSec!.toStringAsFixed(0)}s • '
        '${_settings.effectiveVideoBitrateKbps} kbps video + '
        '${_settings.effectiveAudioBitrateKbps} kbps audio)';
  }

  Future<void> _export() async {
    if (_exporting) return;
    // Build 9 (v1.7.0, point #5): remote kill switch — a killed
    // export shows the polite closed message and never starts
    // (and never reaches the chroma charge below).
    if (FeatureGate.isKilled(KillableFeature.videoExport)) {
      setState(() {
        _error = FeatureGate.killedMessage;
        _failedStep = 'Export';
      });
      return;
    }
    final validationError = _settings.error;
    if (validationError != null) {
      setState(() {
        _error = validationError;
        _failedStep = 'Settings';
      });
      return;
    }
    // COINS (v1.2.0): export resolution costs NO coins any more —
    // the old 720p 50 / 1080p 100 / 4K 200 charge is abolished;
    // Unity interstitials play alongside the export instead (fired
    // unawaited below). The ONLY charge left here is chroma key
    // (50) when the preset has chroma on — the chroma feature's own
    // price (plan §15), not a resolution price; the chroma pass runs
    // inside this export. Affordability of the TOTAL is checked
    // first so a half-paid export never starts; the spends then land
    // in order. A failed export does NOT auto-refund — no refund
    // function exists server-side; the charge is per export attempt,
    // stated on the button. Admins are waived server-side.
    final charges = <CoinFeature>[
      if (widget.preset.chromaEnabled) CoinFeature.chromaKey,
    ];
    final totalCost =
        charges.fold(0, (sum, f) => sum + CoinCosts.costFor(f));
    if (!CoinService.instance.canAffordAmount(totalCost)) {
      setState(() {
        _error = 'Coins kam hain — is export ke liye $totalCost coins '
            'chahiye (Chroma key). Watch Ads se kamayein.';
        _failedStep = 'Coins';
      });
      return;
    }
    for (final feature in charges) {
      final spendResult = await CoinService.instance.spend(feature);
      if (!spendResult.ok) {
        if (!mounted) return;
        setState(() {
          _error = 'Coins nahi kat sake (${spendResult.error}) — '
              'export shuru nahi hua.';
          _failedStep = 'Coins';
        });
        return;
      }
    }
    setState(() {
      _exporting = true;
      _cancelRequested = false;
      _progress = 0;
      _status = 'Export shuru ho raha hai…';
      _error = null;
      _failedStep = null;
      _notes = const [];
      _savedPath = null;
      _savedSizeBytes = null;
    });
    // ADS ALONGSIDE EXPORT (v1.2.0): 720p → 1 interstitial,
    // 1080p / 4K → 2 back-to-back. Fired UNAWAITED on purpose: the
    // export starts immediately (the await below) and the ads never
    // delay, block or fail it — showExportAds swallows every failure
    // (offline / no fill included).
    unawaited(
      UnityAdsService.showExportAds(_settings.quality == 0 ? 1 : 2),
    );
    final ReelExportResult result;
    try {
      result = await ReelExportService.exportReel(
        project: widget.project,
        preset: widget.preset,
        settings: _settings,
        isCancelled: () => _cancelRequested,
        onProgress: (v) {
          if (mounted) setState(() => _progress = v);
        },
        onStep: (s) {
          if (mounted) setState(() => _status = s);
        },
      );
    } catch (e, s) {
      // Build 7 (v1.5.9): an export that THROWS (instead of
      // returning a failed result) is reported with its boundary
      // tag AND lands on the same failure UI a failed result
      // uses. Before, the throw escaped the tap handler — the
      // user got only the generic error banner and this screen
      // stayed stuck on "exporting" with no Retry.
      CrashGuard.report(e, s, source: 'export.start');
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _progress = 0;
        _status = 'Export fail ho gaya.';
        _error = 'Export ke dauraan khata aa gaya: $e';
        _failedStep = 'Export';
      });
      return;
    }
    if (!mounted) return;
    int? size;
    if (result.success && result.outputPath != null) {
      try {
        size = await File(result.outputPath!).length();
      } catch (_) {
        size = null;
      }
    }
    setState(() {
      _exporting = false;
      _progress = result.success ? 1.0 : 0;
      _status = _cancelRequested
          ? 'Export cancel kar diya gaya.'
          : result.success
              ? 'Gallery mein save ho gaya.'
              : (result.error ?? 'Export fail ho gaya.');
      _notes = result.notes;
      _savedPath = result.outputPath;
      _savedSizeBytes = size;
      _error = _cancelRequested
          ? 'Export cancel kar diya gaya.'
          : result.success
              ? null
              : result.error;
      _failedStep = _cancelRequested ? 'Export (cancel)' : result.failedStep;
    });
  }

  void _cancel() {
    if (!_exporting) return;
    setState(() {
      _cancelRequested = true;
      _status = 'Export cancel ho raha hai…';
    });
    // Cancels the in-flight ffmpeg pass; the export loop also checks
    // the flag between stages and stops there.
    FfmpegService.cancel();
  }

  Future<void> _openSaved() async {
    final path = _savedPath;
    if (path == null) return;
    try {
      await OpenFilex.open(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File khol nahi saki: $e')),
        );
      }
    }
  }

  Future<void> _shareSaved() async {
    final path = _savedPath;
    if (path == null) return;
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)]),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share nahi hua: $e')),
        );
      }
    }
  }

  Future<void> _exportPoster() async {
    if (_posterBusy) return;
    setState(() {
      _posterBusy = true;
      _posterMessage = 'Poster render ho raha hai…';
      _posterPath = null;
    });
    final result = await PosterExportService.renderPoster(
      project: widget.project,
      preset: widget.preset,
      size: _posterSize,
    );
    if (!mounted) return;
    if (!result.success || result.file == null) {
      setState(() {
        _posterBusy = false;
        _posterMessage = result.error ?? 'Poster render nahi hua.';
      });
      return;
    }
    final saved = await PosterExportService.saveToGallery(result.file!);
    if (!mounted) return;
    setState(() {
      _posterBusy = false;
      _posterPath = result.file!.path;
      _posterMessage = saved.ok
          ? 'Poster gallery mein save ho gaya (${_posterSize.label}).'
          : 'Poster bana, gallery save nahi hua: ${saved.error}';
    });
  }

  Future<void> _sharePoster() async {
    final path = _posterPath;
    if (path == null) return;
    final result =
        await PosterExportService.sharePoster(File(path));
    if (!mounted) return;
    if (!result.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share nahi hua: ${result.error}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${project.clipPaths.length} clips • '
            '${project.voiceoverPath == null ? 'voiceover nahi bani' : 'voiceover tayyar'} • '
            '${project.templateKind == 'nigraanFinal' ? 'Final 3-Ribbon' : project.templateKind == 'breaking' ? 'Breaking' : 'Classic'} template',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          const Text(
            'Quality',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            key: const Key('exportQualitySelector'),
            segments: const [
              ButtonSegment(value: 0, label: Text('720p')),
              ButtonSegment(value: 1, label: Text('1080p')),
              ButtonSegment(value: 2, label: Text('4K')),
            ],
            selected: {_settings.quality},
            onSelectionChanged: _exporting
                ? null
                : (s) => setState(
                      () => _settings =
                          _settings.copyWith(quality: s.first),
                    ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Aspect',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            key: const Key('exportAspectSelector'),
            segments: const [
              ButtonSegment(value: '9:16', label: Text('9:16 Reel')),
              ButtonSegment(value: '16:9', label: Text('16:9')),
              ButtonSegment(value: '1:1', label: Text('1:1')),
            ],
            selected: {_settings.aspect},
            onSelectionChanged: _exporting
                ? null
                : (s) => setState(
                      () => _settings = _settings.copyWith(aspect: s.first),
                    ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FPS',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    DropdownButton<int>(
                      key: const Key('exportFpsDropdown'),
                      value: _settings.fps,
                      isExpanded: true,
                      onChanged: _exporting
                          ? null
                          : (v) => setState(
                                () => _settings =
                                    _settings.copyWith(fps: v ?? 30),
                              ),
                      items: const [
                        DropdownMenuItem(value: 24, child: Text('24 fps')),
                        DropdownMenuItem(value: 30, child: Text('30 fps')),
                        DropdownMenuItem(value: 60, child: Text('60 fps')),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Audio bitrate',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    DropdownButton<int?>(
                      key: const Key('exportAudioBitrateDropdown'),
                      value: _settings.audioBitrateKbps,
                      isExpanded: true,
                      onChanged: _exporting
                          ? null
                          : (v) => setState(
                                () => _settings = _settings.copyWith(
                                  audioBitrateKbps: v,
                                ),
                              ),
                      items: const [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Auto (128 kbps)'),
                        ),
                        DropdownMenuItem(value: 128, child: Text('128 kbps')),
                        DropdownMenuItem(value: 192, child: Text('192 kbps')),
                        DropdownMenuItem(value: 256, child: Text('256 kbps')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Video bitrate',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          DropdownButton<int?>(
            key: const Key('exportVideoBitrateDropdown'),
            value: _settings.videoBitrateKbps,
            isExpanded: true,
            onChanged: _exporting
                ? null
                : (v) => setState(
                      () => _settings = _settings.copyWith(
                        videoBitrateKbps: v,
                      ),
                    ),
            items: const [
              DropdownMenuItem<int?>(
                value: null,
                child: Text('Auto (CRF 23)'),
              ),
              DropdownMenuItem(value: 2500, child: Text('2.5 Mbps')),
              DropdownMenuItem(value: 5000, child: Text('5 Mbps')),
              DropdownMenuItem(value: 8000, child: Text('8 Mbps')),
              DropdownMenuItem(value: 12000, child: Text('12 Mbps')),
              DropdownMenuItem(value: 20000, child: Text('20 Mbps')),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _sizeEstimate,
            key: const Key('estimatedSizeText'),
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Export: ${_settings.qualityLabel} • ${_settings.fps} fps • '
            '${_settings.dims.$1}×${_settings.dims.$2} • H.264 + AAC',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const Key('startExportButton'),
                  onPressed: _exporting ? null : _export,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                  ),
                  child: Text(
                    _exporting
                        ? 'Export ho raha hai…'
                        : _exportCostCoins > 0
                            ? 'Export • ${_settings.qualityLabel} • '
                                '$_exportCostCoins coins'
                            : 'Export • ${_settings.qualityLabel} • Free',
                  ),
                ),
              ),
              if (_exporting) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('cancelExportButton'),
                  onPressed: _cancel,
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
          if (_exporting || _status.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (_exporting)
              LinearProgressIndicator(value: _progress),
            const SizedBox(height: 6),
            Text(
              _status,
              key: const Key('exportStatusText'),
              style: TextStyle(
                color: _error != null ? Colors.red[300] : Colors.grey,
                fontSize: 12,
              ),
            ),
            if (_exporting)
              Text(
                '${(_progress * 100).toStringAsFixed(0)}%',
                key: const Key('exportProgressText'),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _failedStep != null
                  ? 'Fail hua — step: $_failedStep'
                  : 'Export fail ho gaya.',
              style: TextStyle(
                color: Colors.red[300],
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            // The error detail itself is already shown in the status
            // line above — not repeated here.
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('retryExportButton'),
              onPressed: _exporting ? null : _export,
              child: const Text('Retry karein'),
            ),
          ],
          if (_savedPath != null) ...[
            const SizedBox(height: 12),
            const Text(
              'Export complete',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              _savedPath!,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            if (_savedSizeBytes != null)
              Text(
                'Size: ${ExportSettings.formatBytes(_savedSizeBytes!)}',
                key: const Key('exportedFileSizeText'),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('openExportedButton'),
                    onPressed: _openSaved,
                    child: const Text('Open karein'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const Key('shareExportedButton'),
                    onPressed: _shareSaved,
                    child: const Text('Share karein'),
                  ),
                ),
              ],
            ),
          ],
          if (_notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final note in _notes)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '• $note',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
          ],
          const Divider(height: 32),
          const Text(
            'Thumbnail / Poster',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          const Text(
            'Current template frame as a poster PNG — gallery mein save '
            'hota hai, share bhi ho sakta hai.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 8),
          SegmentedButton<PosterSize>(
            key: const Key('posterSizeSelector'),
            segments: const [
              ButtonSegment(
                value: PosterSize.portrait,
                label: Text('Portrait 720×1280'),
              ),
              ButtonSegment(
                value: PosterSize.landscape,
                label: Text('Landscape 1280×720'),
              ),
            ],
            selected: {_posterSize},
            onSelectionChanged: _posterBusy
                ? null
                : (s) => setState(() => _posterSize = s.first),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('exportPosterButton'),
                  onPressed: _posterBusy ? null : _exportPoster,
                  child: Text(
                    _posterBusy ? 'Poster ban raha hai…' : 'Poster export',
                  ),
                ),
              ),
              if (_posterPath != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const Key('sharePosterButton'),
                    onPressed: _sharePoster,
                    child: const Text('Poster share karein'),
                  ),
                ),
              ],
            ],
          ),
          if (_posterMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              _posterMessage!,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
          if (_posterPath != null) ...[
            const SizedBox(height: 4),
            Text(
              _posterPath!,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
          const Divider(height: 32),
          const Text(
            'Preview renders 720×1280 tak capped hain; '
            'project mein zyada se zyada 20 clips; ticker export mein '
            'static rehta hai (scrolling ticker deferred hai — renderer '
            'mein ticker-strip output nahi hai); 2K/H.265 device codec '
            'check ke baghair nahi milte, is liye H.264 hi use hota hai.',
            style: TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
