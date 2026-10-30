/// Video editor screen (CapCut-style core): pick clips, trim each clip,
/// merge, text overlay, music, speed, filters, aspect ratio, crossfade.
///
/// Processing is done by [FfmpegService]; this screen only builds the UI
/// state and the command pipeline. All exports are real FFmpeg runs —
/// no mock buttons.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../app_config.dart';
import '../live/news_template.dart';
import '../live/live_studio_screen.dart';
import '../services/ad_service.dart';
import '../services/ffmpeg_service.dart';
import '../services/caption_service.dart';
import '../services/pro_editor.dart';
import '../services/fx_pack.dart';
import '../services/pro_vision.dart';

class VideoClip {
  VideoClip(this.file, this.duration, this.aspectRatio);
  final File file;
  final Duration duration;
  final double aspectRatio; // width / height, from the real video stream
  double trimStart = 0;
  double trimEnd = -1; // -1 = full duration
  double get effectiveEnd => trimEnd < 0 ? duration.inMilliseconds / 1000 : trimEnd;
  double get effectiveDuration => effectiveEnd - trimStart;
}

class VideoEditorScreen extends StatefulWidget {
  const VideoEditorScreen({super.key});

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  final _picker = ImagePicker();
  final List<VideoClip> _clips = [];
  int _selected = 0;
  VideoPlayerController? _controller;
  bool _busy = false;
  String _status = 'Pick a video to start.';
  double _speed = 1.0;
  String _filter = 'Normal';
  String _aspect = 'Original';
  bool _crossfade = false;
  String _text = '';
  String? _musicPath;
  String? _fontFile;
  List<CaptionSegment> _captions = [];
  String _captionLocale = 'ur';
  bool _transcribing = false;
  CaptionStyle _captionStyle = CaptionStyle.standard;
  bool _captionDrawtextFallback = false;
  // CapCut-style UI state: which single-row tool rail item is open.
  // The panel above the rail shows only this tool's controls; every
  // tool from the old screen is reachable through the rail.
  String _activeTool = 'text';

  // ---- PRO tools (v2.1.0) state. Defaults = today's behaviour: every
  // pro switch/dropdown off or neutral, so an untouched export is
  // byte-for-byte the old pipeline plus the guarded post-passes (which
  // are all skipped when their switches are off). ----
  final _previewKey = GlobalKey();

  // Motion titles + sticker (rendered to PNG by pro_editor, never
  // through FFmpeg drawtext, so Urdu shaping stays correct).
  String _proTitle = '';
  String _proTitlePreset = 'fadeIn';
  String _proTitlePosition = 'bottomCenter';
  String _proSticker = '';
  String _proStickerPreset = 'fadeIn';

  // Grading (LUT dropdown values come from proLuts; '' = None).
  String _proLut = '';
  double _proTemperature = 0;
  double _proTint = 0;
  double _proSaturation = 1;
  double _proVibrance = 1;
  double _proContrast = 1;
  double _proShadows = 0;
  double _proHighlights = 0;

  // Keyframes animate the motion title/sticker overlay (title first
  // if both are set). Times are 0 and the export duration.
  bool _proKeyframes = false;
  double _kfStartX = 0.5;
  double _kfStartY = 0.5;
  double _kfStartScale = 1;
  double _kfStartOpacity = 1;
  double _kfStartRotation = 0;
  double _kfEndX = 0.5;
  double _kfEndY = 0.5;
  double _kfEndScale = 1;
  double _kfEndOpacity = 1;
  double _kfEndRotation = 0;

  // Stabilization, speed ramp, transitions.
  bool _proStabilize = false;
  String _proRamp = 'None';
  String _proTransition = 'fade';
  double _proTransitionDur = 0.5;

  // Chromakey.
  bool _proChroma = false;
  String _proChromaColor = 'green';
  double _proChromaSimilarity = 0.4;
  double _proChromaBlend = 0.1;
  String _proChromaBgKind = 'color';
  String _proChromaBgColor = '#00FF00';
  String? _proChromaBgImage;

  // Video background remover (ML — Premium-gated like the photo
  // editor's AI tools).
  bool _proBgRemove = false;
  String _proBgKind = 'color';
  String _proBgColor = '#00FF00';
  String? _proBgImage;

  // Motion tracking (ML — Premium-gated like the photo editor's AI
  // tools). Tap point is stored normalized; the tracked sticker text
  // follows the recorded track in the export.
  String _trackSticker = '';
  double? _trackStartX;
  double? _trackStartY;
  List<TrackPoint> _trackPoints = [];
  bool _tracking = false;

  // Beat sync + waveform.
  List<double> _beats = [];
  bool _beatAutoCut = false;
  bool _detectingBeats = false;
  String? _waveformPath;
  bool _waveformBusy = false;

  // ---- FX Pack v2.2.0 state (CapCut/VN/KineMaster/Alight parity).
  // All default to off/neutral: untouched export = old pipeline. ----
  VoiceFx _fxVoice = VoiceFx.none;
  double _fxFadeIn = 0;
  double _fxFadeOut = 0;
  bool _fxReverse = false;
  bool _fxFreeze = false;
  double _fxFreezeAt = 1.0;
  double _fxFreezeHold = 2.0;
  bool _fxSilenceRemove = false;
  bool _fxPip = false;
  String? _fxPipVideo;
  PipPosition _fxPipPos = PipPosition.bottomRight;
  double _fxPipScale = 0.3;
  ShakeFx _fxShake = ShakeFx.none;
  ExportQuality _fxQuality = ExportQuality.p720;

  bool get _gradeActive =>
      _proLut.isNotEmpty ||
      _proTemperature != 0 ||
      _proTint != 0 ||
      _proSaturation != 1 ||
      _proVibrance != 1 ||
      _proContrast != 1 ||
      _proShadows != 0 ||
      _proHighlights != 0;

  RampPreset? _rampPreset() => switch (_proRamp) {
        'slowMiddle' => RampPreset.slowMiddle,
        'slowStart' => RampPreset.slowStart,
        'slowEnd' => RampPreset.slowEnd,
        'pulse' => RampPreset.pulse,
        _ => null,
      };

  /// Premium gate mirrored from the photo editor's AI tools
  /// (_runAi): ML features need a rewarded-ad unlock first. Difference
  /// from the photo editor (which asks the user to tap the tool again
  /// after unlocking): here a successful unlock lets the action
  /// proceed immediately, so the BG-remover switch can turn on and the
  /// Track button can run in the same tap.
  Future<bool> _ensurePremiumUnlocked() async {
    if (AdService.isPremiumUnlocked) return true;
    _setStatus(
      'Pro ML tools are Premium. Unlock them with one short ad '
      'from the home screen, then try again.',
    );
    if (!mounted) return false;
    final unlock = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Premium Pro tools'),
        content: const Text(
          'Watch one short ad to unlock video background remover '
          'and motion tracking.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Watch ad'),
          ),
        ],
      ),
    );
    if (unlock == true) {
      final ok = await AdService.showRewarded();
      _setStatus(
        ok
            ? 'Premium Pro unlocked.'
            : 'No ad was available right now. Try again.',
      );
      return ok;
    }
    return false;
  }

  Future<void> _onBgRemoverChanged(bool v) async {
    if (!v) {
      setState(() => _proBgRemove = false);
      return;
    }
    if (await _ensurePremiumUnlocked()) {
      setState(() => _proBgRemove = true);
    }
  }

  /// Tap on the preview -> normalized (0..1, 0..1) coords.
  /// APPROXIMATION (documented): the preview widget is a fixed 16:9
  /// box, while the video inside it may be letterboxed/pillarboxed,
  /// so the tap point is measured against the whole preview box, not
  /// the video frame itself. Tracking treats it as the video-frame
  /// point, which is close for 16:9 clips and approximate otherwise.
  void _onPreviewTapDown(TapDownDetails d) {
    final box =
        _previewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final size = box.size;
    if (size.width <= 0 || size.height <= 0) return;
    final local = box.globalToLocal(d.globalPosition);
    setState(() {
      _trackStartX = (local.dx / size.width).clamp(0.0, 1.0);
      _trackStartY = (local.dy / size.height).clamp(0.0, 1.0);
      _trackPoints = [];
      _status =
          'Object tapped (${_trackStartX!.toStringAsFixed(2)}, ${_trackStartY!.toStringAsFixed(2)}) — ab Track dabayein.';
    });
  }

  Future<void> _trackObject() async {
    if (_clips.isEmpty || _trackStartX == null || _trackStartY == null) {
      _setStatus('Pehle preview par object ko tap karein.');
      return;
    }
    if (_tracking || _busy) return;
    if (!await _ensurePremiumUnlocked()) return;
    setState(() {
      _tracking = true;
      _status = 'Object track ho raha hai…';
    });
    try {
      final dir = await _workDir();
      var lastPct = -1;
      final points = await trackObject(
        videoPath: _clips[_selected].file.path,
        startXNorm: _trackStartX!,
        startYNorm: _trackStartY!,
        workDir: dir,
        onProgress: (v) {
          final pct = (v * 100).round();
          if (pct != lastPct) {
            lastPct = pct;
            _setStatus(
              'Tracking… $pct% done, ${100 - pct}% remaining',
            );
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _trackPoints = points;
        _status = points.isEmpty
            ? 'Object track nahi hua — dobara tap karke try karein.'
            : '${points.length} track points mil gaye.';
      });
    } catch (e) {
      _setStatus('Tracking failed: $e');
    } finally {
      if (mounted) setState(() => _tracking = false);
    }
  }

  Future<void> _detectBeats() async {
    if (_clips.isEmpty) {
      _setStatus('Add a video first.');
      return;
    }
    if (_detectingBeats || _busy) return;
    setState(() {
      _detectingBeats = true;
      _status = 'Beats dhoond rahe hain…';
    });
    try {
      final dir = await _workDir();
      final input = _musicPath ?? _clips[_selected].file.path;
      final beats = await detectBeats(input: input, workDir: dir);
      if (!mounted) return;
      setState(() {
        _beats = beats;
        _status = beats.isEmpty
            ? 'Koi beat nahi mili.'
            : '${beats.length} beats mili.';
      });
    } catch (e) {
      _setStatus('Beat detect failed: $e');
    } finally {
      if (mounted) setState(() => _detectingBeats = false);
    }
  }

  Future<void> _showWaveform() async {
    if (_clips.isEmpty) {
      _setStatus('Add a video first.');
      return;
    }
    if (_waveformBusy || _busy) return;
    setState(() {
      _waveformBusy = true;
      _status = 'Waveform bana rahe hain…';
    });
    try {
      final dir = await _workDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final input = _musicPath ?? _clips[_selected].file.path;
      final outPng = p.join(dir.path, 'waveform_$stamp.png');
      final res = await waveformPng(
        input: input,
        output: outPng,
        width: 720,
        height: 120,
      );
      if (!mounted) return;
      setState(() {
        _waveformPath = res;
        _status = res == null
            ? 'Waveform nahi bana — audio nahi mili.'
            : 'Waveform ready.';
      });
    } catch (e) {
      _setStatus('Waveform failed: $e');
    } finally {
      if (mounted) setState(() => _waveformBusy = false);
    }
  }

  Future<void> _pickProImage(ValueChanged<String> onPicked) async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => onPicked(picked.path));
  }

  /// PNG width/height straight from the IHDR chunk (bytes 16..23,
  /// big-endian), so overlay positioning uses the real rendered PNG
  /// size whatever canvas the sibling renderer chose.
  (int, int)? _pngSize(File f) {
    try {
      final bytes = f.readAsBytesSync();
      if (bytes.length < 24) return null;
      final w = (bytes[16] << 24) |
          (bytes[17] << 16) |
          (bytes[18] << 8) |
          bytes[19];
      final h = (bytes[20] << 24) |
          (bytes[21] << 16) |
          (bytes[22] << 8) |
          bytes[23];
      if (w <= 0 || h <= 0) return null;
      return (w, h);
    } catch (_) {
      return null;
    }
  }

  /// Builds the ONE combined animated-overlay pass command, or null
  /// when nothing is set. Chain order: motion title, then sticker,
  /// then the tracked sticker (tracked last so it sits on top).
  /// Keyframes replace the preset animation for the PRIMARY overlay
  /// (title if set, else sticker); any second overlay keeps its
  /// preset animation. Returns null when there is nothing to overlay.
  Future<String?> _buildOverlayCommand({
    required Directory dir,
    required int stamp,
    required String input,
    required String output,
    required double durationSec,
  }) async {
    final hasTitle = _proTitle.trim().isNotEmpty;
    final hasSticker = _proSticker.trim().isNotEmpty;
    final hasTrack =
        _trackPoints.isNotEmpty && _trackSticker.trim().isNotEmpty;
    if (!hasTitle && !hasSticker && !hasTrack) return null;
    // Export dims approximated from the first clip's aspect (same
    // approximation as the multi-clip normalize step); the aspect
    // setting can change the real frame size.
    final portrait =
        _clips.isEmpty ? true : _clips.first.aspectRatio < 1.0;
    final videoW = portrait ? 720 : 1280;
    final videoH = portrait ? 1280 : 720;
    final useKeyframes = _proKeyframes && (hasTitle || hasSticker);

    Future<ProMotionTitle> titleSpec(
      String text,
      String preset,
      String position,
    ) async {
      return ProMotionTitle(
        text: text,
        preset: preset,
        position: position,
        startSec: 0,
        durationSec: durationSec,
      );
    }

    final steps = <_OverlayStep>[];
    if (hasTitle) {
      final t = await titleSpec(
        _proTitle,
        _proTitlePreset,
        _proTitlePosition,
      );
      final png = await renderTitlePng(t, dir: dir);
      steps.add(_OverlayStep(png: png, keyframed: useKeyframes, title: t));
    }
    if (hasSticker) {
      final t = await titleSpec(_proSticker, _proStickerPreset, 'center');
      final png = await renderTitlePng(t, dir: dir);
      steps.add(
        _OverlayStep(
          png: png,
          keyframed: useKeyframes && !hasTitle,
          title: t,
        ),
      );
    }
    File? trackPng;
    if (hasTrack) {
      // Small canvas so the tracked sticker is a movable overlay,
      // not a full-frame image.
      trackPng = await renderTitlePng(
        ProMotionTitle(
          text: _trackSticker,
          preset: 'fadeIn',
          position: 'center',
          startSec: 0,
          durationSec: durationSec,
        ),
        dir: dir,
        canvasW: 360,
        canvasH: 120,
      );
    }

    final buf = StringBuffer();
    buf.write('-y -i ${FfmpegService.q(input)} ');
    for (final s in steps) {
      buf.write('-loop 1 -framerate 30 -i ${FfmpegService.q(s.png.path)} ');
    }
    var trackIdx = -1;
    if (trackPng != null) {
      trackIdx = 1 + steps.length;
      buf.write('-loop 1 -framerate 30 -i ${FfmpegService.q(trackPng.path)} ');
    }
    final totalOverlays = steps.length + (trackPng != null ? 1 : 0);
    final chain = <String>[];
    var cur = '[0:v]';
    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      final outLabel = i == totalOverlays - 1 ? '[vout]' : '[ov$i]';
      final size = _pngSize(s.png) ?? (720, 1280);
      final overlayLabel = '[${i + 1}:v]';
      if (s.keyframed) {
        chain.add(
          keyframeOverlayFilter(
            baseLabel: cur,
            overlayLabel: overlayLabel,
            track: KeyframeTrack(
              start: ProKeyframe(
                timeSec: 0,
                xNorm: _kfStartX,
                yNorm: _kfStartY,
                scale: _kfStartScale,
                opacity: _kfStartOpacity,
                rotationDeg: _kfStartRotation,
              ),
              end: ProKeyframe(
                timeSec: durationSec,
                xNorm: _kfEndX,
                yNorm: _kfEndY,
                scale: _kfEndScale,
                opacity: _kfEndOpacity,
                rotationDeg: _kfEndRotation,
              ),
            ),
            videoW: videoW,
            videoH: videoH,
            overlayW: size.$1.toInt(),
            overlayH: size.$2.toInt(),
            outLabel: outLabel,
          ),
        );
      } else {
        chain.add(
          animatedTitleFilter(
            baseLabel: cur,
            overlayLabel: overlayLabel,
            t: s.title!,
            videoW: videoW,
            videoH: videoH,
            overlayW: size.$1.toInt(),
            overlayH: size.$2.toInt(),
            outLabel: outLabel,
          ),
        );
      }
      cur = outLabel;
    }
    if (trackPng != null) {
      final size = _pngSize(trackPng) ?? (360, 120);
      chain.add(
        trackOverlayFilter(
          track: _trackPoints,
          baseLabel: cur,
          overlayLabel: '[$trackIdx:v]',
          videoW: videoW,
          videoH: videoH,
          overlayW: size.$1.toInt(),
          overlayH: size.$2.toInt(),
          outLabel: '[vout]',
        ),
      );
    }
    buf.write(
      '-filter_complex "${chain.join(';')}" -map "[vout]" -map 0:a? '
      '-c:v libx264 -preset veryfast -crf 23 -c:a copy '
      '-movflags +faststart ${FfmpegService.q(output)}',
    );
    return buf.toString();
  }


  // v2 news template (shared with Live Studio): breaking banner,
  // lower-third, ticker, clock, logo. Loaded from the same JSON file
  // the Live screen edits, so one template serves both.
  NewsTemplate _news = NewsTemplate();
  bool _newsEnabled = false;

  @override
  void initState() {
    super.initState();
    NewsTemplate.load().then((t) {
      if (mounted) setState(() => _news = t);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    if (_clips.isEmpty) return;
    final old = _controller;
    final c = VideoPlayerController.file(_clips[_selected].file);
    setState(() => _controller = c);
    await old?.dispose();
    try {
      await c.initialize();
      await c.setLooping(true);
      setState(() {});
    } catch (e) {
      setState(() => _status = 'Preview failed: $e');
    }
  }

  Future<void> _addClip() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    final file = File(picked.path);
    final probe = VideoPlayerController.file(file);
    try {
      await probe.initialize();
      final d = probe.value.duration;
      final aspect = probe.value.aspectRatio;
      await probe.dispose();
      setState(() {
        _clips.add(VideoClip(file, d, aspect));
        _selected = _clips.length - 1;
        _status = 'Clip ${_clips.length} added (${d.inSeconds}s).';
      });
      await _loadPreview();
    } catch (e) {
      await probe.dispose();
      setState(() => _status = 'Could not read video: $e');
    }
  }

  Future<void> _pickMusic() async {
    if (!AppConfig.musicOverlayEnabled) {
      _setStatus('Music overlay is turned off in the app config.');
      return;
    }
    final files = await FilePicker.pickFiles(type: FileType.audio);
    if (files.isNotEmpty && files.first.path != null) {
      setState(() {
        _musicPath = files.first.path;
        _status = 'Music: ${p.basename(_musicPath!)}';
      });
    }
  }

  void _setStatus(String s) => setState(() => _status = s);

  Future<Directory> _workDir() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory(p.join(tmp.path, 'pve_video'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Export quality picker (CapCut-style): 720p free, 1080p also
  /// free in TJ Pro (differentiator vs CapCut Pro paywall).
  Future<void> _showExportDialog() async {
    if (_clips.isEmpty) {
      _setStatus('Add at least one video first.');
      return;
    }
    if (_busy) return;
    final quality = await showDialog<ExportQuality>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Export quality'),
        content: StatefulBuilder(
          builder: (ctx, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: ExportQuality.values
                .map((q) => RadioListTile<ExportQuality>(
                      title: Text(exportQualityLabels[q.index]),
                      value: q,
                      groupValue: _fxQuality,
                      onChanged: (v) {
                        setDialogState(() {});
                        setState(() => _fxQuality = v ?? ExportQuality.p720);
                      },
                    ))
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx).pop(_fxQuality),
            child: const Text('Export'),
          ),
        ],
      ),
    );
    if (quality != null && mounted) {
      await _export();
    }
  }

  /// Combine the base audio filter (ramp complex filter or null) with
  /// the FX Pack voice/fade filters and the speed atempo. Returns the
  /// `-af` value, or the complex filter (with [0:a]) unchanged.
  String? _combinedAudioFilter(String? base, double speed, String? fx) {
    if (base != null && base.contains('[0:a]')) {
      // Complex ramp filter: FX voice/fade can't join the labeled graph
      // simply; the ramp contract keeps audio in sync, so we keep it as-is.
      // (Documented limitation: voice/fade skipped when ramp is active.)
      return base;
    }
    final parts = <String>[];
    if (base != null && base.isNotEmpty) parts.add(base);
    if (speed != 1.0 && _musicPath == null) {
      parts.add('atempo=$speed');
    }
    if (fx != null && fx.isNotEmpty) {
      parts.add(fx);
    }
    return parts.isEmpty ? null : parts.join(',');
  }

  Future<void> _exportInner() async {
    try {
      final dir = await _workDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      var out = p.join(dir.path, 'pve_export_$stamp.mp4');

      // ---- FX Pack pre-passes (guarded: failure keeps original clip).
      // Applied to the SELECTED clip before the main pipeline.
      if (_clips.isNotEmpty) {
        final selIdx = _selected.clamp(0, _clips.length - 1);
        var selClip = _clips[selIdx];
        // (a) Reverse.
        if (_fxReverse) {
          try {
            _setStatus('Reversing clip…');
            final revOut = p.join(dir.path, 'fx_reverse_$stamp.mp4');
            final res = await FfmpegService.run(
              reverseCommand(input: selClip.file.path, output: revOut),
            );
            if (res.ok) {
              final oldClip = selClip;
              final newClip = VideoClip(
                File(revOut), oldClip.duration, oldClip.aspectRatio,
              );
              newClip.trimStart = oldClip.trimStart;
              newClip.trimEnd = oldClip.trimEnd;
              selClip = newClip;
              _clips[selIdx] = selClip;
            } else {
              _setStatus('Note: reverse fail ho gaya, original clip use ho rahi hai.');
            }
          } catch (e) {
            _setStatus('Note: reverse fail ho gaya ($e).');
          }
        }
        // (b) Freeze frame.
        if (_fxFreeze) {
          try {
            _setStatus('Freeze frame laga rahe hain…');
            final cmds = freezeFrameCommands(
              input: selClip.file.path,
              freezeAtSec: _fxFreezeAt.clamp(0.5, selClip.effectiveDuration - 0.5),
              holdSec: _fxFreezeHold,
              workDir: dir.path,
              stamp: stamp,
            );
            final paths = freezeFramePaths(dir.path, stamp);
            var ok = true;
            for (final cmd in cmds) {
              final res = await FfmpegService.run(cmd);
              if (!res.ok) { ok = false; break; }
            }
            if (ok) {
              final listFile = File(paths['list']!);
              await listFile.writeAsString(
                [paths['before']!, paths['hold']!, paths['after']!]
                    .map((f) => "file '${f.replaceAll("'", "'\\''")}'")
                    .join('\n'),
              );
              final frozenOut = p.join(dir.path, 'fx_frozen_$stamp.mp4');
              final cc = FfmpegService.concatCommand(
                listFile: paths['list']!,
                output: frozenOut,
              );
              final res = await FfmpegService.run(cc);
              if (res.ok) {
                final newDur = selClip.duration +
                    Duration(milliseconds: (_fxFreezeHold * 1000).round());
                selClip = VideoClip(File(frozenOut), newDur, selClip.aspectRatio);
                _clips[selIdx] = selClip;
              } else {
                ok = false;
              }
            }
            if (!ok) {
              _setStatus('Note: freeze frame fail ho gaya, original clip use ho rahi hai.');
            }
          } catch (e) {
            _setStatus('Note: freeze frame fail ho gaya ($e).');
          }
        }
        // (c) Silence remover.
        if (_fxSilenceRemove) {
          try {
            _setStatus('Khamosh hisse kaat rahe hain…');
            final silOut = p.join(dir.path, 'fx_silence_$stamp.mp4');
            final res = await FfmpegService.run(
              silenceRemoveCommand(
                input: selClip.file.path,
                output: silOut,
              ),
            );
            if (res.ok) {
              // Re-probe duration via video player.
              final probe = VideoPlayerController.file(File(silOut));
              try {
                await probe.initialize();
                final d = probe.value.duration;
                await probe.dispose();
                selClip = VideoClip(
                  File(silOut), d, selClip.aspectRatio,
                );
                _clips[selIdx] = selClip;
              } catch (_) {
                await probe.dispose();
              }
            } else {
              _setStatus('Note: silence remover fail ho gaya, original clip use ho rahi hai.');
            }
          } catch (e) {
            _setStatus('Note: silence remover fail ho gaya ($e).');
          }
        }
      }

      _fontFile ??= FfmpegService.findFontFile();
      final hasText = _text.trim().isNotEmpty;
      if (hasText && _fontFile == null) {
        _setStatus(
          'Note: no system font found, exporting without text overlay.',
        );
      }
      final text = hasText ? _text : null;

      // Auto captions: ASS subtitles (proper Urdu shaping) or, on the
      // fallback retry, timed drawtext (Latin scripts only).
      String? subsPath;
      String? capFilter;
      var useCaptions = _captions.isNotEmpty;
      if (useCaptions) {
        final adjusted = _adjustedCaptions();
        if (adjusted.isEmpty) {
          useCaptions = false;
        } else if (_captionDrawtextFallback) {
          capFilter = CaptionService.buildDrawtextFilters(
            segments: adjusted,
            fontFile: _fontFile,
            fontSize: _clips.first.aspectRatio < 1.0 ? 56 : 40,
          );
          if (capFilter == null) {
            throw Exception(
              'Captions need the subtitles filter for Urdu text, which '
              'this build does not support.',
            );
          }
        } else {
          final assPath = p.join(dir.path, 'captions_$stamp.ass');
          final portrait = _clips.first.aspectRatio < 1.0;
          await File(assPath).writeAsString(
            CaptionService.buildAss(
              segments: adjusted,
              portrait: portrait,
              style: _captionStyle,
            ),
          );
          subsPath = assPath;
        }
      }

      // PRO: beat auto-cut (single clip only). Beats were detected on
      // the source file, so segment boundaries are intersected with
      // the clip's trim range, then each segment is trimmed with the
      // existing normalize primitive and concat-joined into one
      // intermediate clip. The normal pipeline then runs on that
      // intermediate as a one-clip export. Multi-clip + beat sync =
      // markers only (no cut).
      var clips = _clips;
      if (_beatAutoCut && _beats.isNotEmpty && _clips.length == 1) {
        final src = _clips.first;
        final segments = beatSegments(
          _beats,
          src.duration.inMilliseconds / 1000,
        );
        final portraitCut = src.aspectRatio < 1.0;
        final cw = portraitCut ? 720 : 1280;
        final ch = portraitCut ? 1280 : 720;
        final cutParts = <String>[];
        var cutTotalMs = 0;
        for (var i = 0; i < segments.length; i++) {
          final seg = segments[i];
          final s = math.min(
            math.max(seg.start, src.trimStart),
            src.effectiveEnd,
          );
          final e = math.min(
            math.max(seg.end, src.trimStart),
            src.effectiveEnd,
          );
          if (e - s < 0.2) continue;
          final part = p.join(dir.path, 'beatcut_${stamp}_$i.mp4');
          _setStatus('Beat cut ${i + 1}/${segments.length}…');
          final res = await FfmpegService.run(
            FfmpegService.normalizeCommand(
              input: src.file.path,
              trimStart: s,
              trimEnd: e,
              width: cw,
              height: ch,
              output: part,
            ),
          );
          if (!res.ok) {
            throw Exception('Beat cut part ${i + 1} failed. ${res.logs}');
          }
          cutParts.add(part);
          cutTotalMs += ((e - s) * 1000).round();
        }
        if (cutParts.isNotEmpty) {
          final cutList = p.join(dir.path, 'beatcut_$stamp.txt');
          await File(cutList).writeAsString(
            cutParts
                .map((f) => "file '${f.replaceAll("'", "'\\''")}'")
                .join('\n'),
          );
          final cutFile = p.join(dir.path, 'beatcut_$stamp.mp4');
          final cc = FfmpegService.concatCommand(
            listFile: cutList,
            output: cutFile,
          );
          _setStatus('Beat cuts jor rahe hain…');
          final res = await FfmpegService.run(cc);
          if (!res.ok) throw Exception('Beat cut join failed. ${res.logs}');
          clips = [
            VideoClip(
              File(cutFile),
              Duration(milliseconds: cutTotalMs),
              src.aspectRatio,
            ),
          ];
        }
      }

      // PRO: grading + speed ramp, resolved once for the whole export.
      // The LUT asset file is resolved here; on failure the export
      // continues with sliders only (status note, never a failure).
      String? lutPath;
      if (_proLut.isNotEmpty) {
        try {
          String? asset;
          for (final e in proLuts) {
            if ((e['name'] ?? '') == _proLut) asset = e['asset'];
          }
          if (asset != null) {
            final f = await ensureLutFile(asset, dir);
            lutPath = f.path;
          }
        } catch (e) {
          _setStatus(
            'Note: LUT load nahi hua, baghair LUT ke export ho raha hai.',
          );
        }
      }
      final gradeStr = _gradeActive
          ? gradeFilter(
              ProGrade(
                lutName: _proLut,
                temperature: _proTemperature,
                tint: _proTint,
                saturation: _proSaturation,
                vibrance: _proVibrance,
                contrast: _proContrast,
                shadows: _proShadows,
                highlights: _proHighlights,
              ),
              lutFilePath: lutPath,
            )
          : '';
      final rampPreset = _rampPreset();
      final hasRamp = rampPreset != null;
      final exportDurSec =
          clips.fold<double>(0.0, (a, c) => a + c.effectiveDuration);
      final rampSegs =
          hasRamp ? rampSegments(rampPreset, exportDurSec) : <RampSegment>[];
      final extraParts = <String>[];
      if (gradeStr.isNotEmpty) extraParts.add(gradeStr);
      if (hasRamp) extraParts.add(rampSetpts(rampSegs));
      // FX Pack: shake effect (Alight Motion-style).
      final shakeStr = shakeFilter(_fxShake);
      if (shakeStr.isNotEmpty) extraParts.add(shakeStr);
      final extraVideoFilter =
          extraParts.isEmpty ? null : extraParts.join(',');
      // Ramp replaces the fixed speed: the video timing comes from the
      // ramp setpts, and the audio filter from the ramp (music exports
      // keep the music track untouched, so the ramp audio filter only
      // applies when no music is picked).
      final effectiveSpeed = hasRamp ? 1.0 : _speed;
      final rampAudio =
          (hasRamp && _musicPath == null) ? rampAudioFilter(rampSegs) : null;
      // FX Pack: voice changer + fade in/out. Chains after ramp/speed.
      final fxAudioParts = <String>[];
      final voiceStr = voiceFxFilter(_fxVoice);
      if (voiceStr.isNotEmpty) fxAudioParts.add(voiceStr);
      final fadeStr = audioFadeFilter(
        fadeInSec: _fxFadeIn,
        fadeOutSec: _fxFadeOut,
        durationSec: exportDurSec,
      );
      if (fadeStr.isNotEmpty) fxAudioParts.add(fadeStr);
      final fxAudioFilter =
          fxAudioParts.isEmpty ? null : fxAudioParts.join(',');

      double progress = 0;
      void onProgress(double v) {
        if ((v - progress).abs() > 0.05) {
          progress = v;
          _setStatus('Exporting… ${(v * 100).round()}%');
        }
      }

      if (clips.length == 1) {
        final c = clips.first;
        final cmd = FfmpegService.singleClipCommand(
          input: c.file.path,
          trimStart: c.trimStart,
          trimEnd: c.effectiveEnd,
          speed: effectiveSpeed,
          filterPreset: _filter,
          aspect: _aspect,
          text: text,
          fontFile: _fontFile,
          subtitlesPath: subsPath,
          captionFilter: capFilter,
          textAtTop: useCaptions,
          musicPath: _musicPath,
          extraVideoFilter: extraVideoFilter,
          audioFilter: _combinedAudioFilter(rampAudio, effectiveSpeed, fxAudioFilter),
          output: out,
        );
        final totalMs =
            ((c.effectiveDuration / effectiveSpeed) * 1000).round();
        final res = await FfmpegService.run(
          cmd,
          expectedMs: totalMs,
          onProgress: onProgress,
        );
        if (!res.ok && hasRamp) {
          // PRO ramp fallback (contract in pro_editor.dart): a failed
          // ramp (e.g. a clip with no audio track for the ramp audio
          // chain) must NOT fail the whole export — retry un-ramped.
          _setStatus(
            'Note: speed ramp fail ho gaya, baghair ramp ke save ho raha hai.',
          );
          final retryCmd = FfmpegService.singleClipCommand(
            input: c.file.path,
            trimStart: c.trimStart,
            trimEnd: c.effectiveEnd,
            speed: effectiveSpeed,
            filterPreset: _filter,
            aspect: _aspect,
            text: text,
            fontFile: _fontFile,
            subtitlesPath: subsPath,
            captionFilter: capFilter,
            textAtTop: useCaptions,
            musicPath: _musicPath,
            extraVideoFilter: gradeStr.isEmpty ? null : gradeStr,
            audioFilter: null,
            output: out,
          );
          final retryRes = await FfmpegService.run(
            retryCmd,
            expectedMs: totalMs,
            onProgress: onProgress,
          );
          if (!retryRes.ok) {
            throw Exception('FFmpeg failed (${res.returnCode}). ${res.logs}');
          }
        } else if (!res.ok) {
          throw Exception('FFmpeg failed (${res.returnCode}). ${res.logs}');
        }
      } else {
        // Step 1: normalize every clip (trim + common size/fps/codec).
        // Orientation comes from the FIRST clip's real aspect ratio.
        // FX Pack: export quality (720p/1080p) sets the target size.
        final portrait = clips.first.aspectRatio < 1.0;
        final dims = exportDims(_fxQuality, portrait);
        final w = dims.$1;
        final h = dims.$2;
        final normFiles = <String>[];
        final normDurMs = <int>[];
        for (var i = 0; i < clips.length; i++) {
          final c = clips[i];
          final nf = p.join(dir.path, 'norm_${stamp}_$i.mp4');
          final cmd = FfmpegService.normalizeCommand(
            input: c.file.path,
            trimStart: c.trimStart,
            trimEnd: c.effectiveEnd,
            width: w,
            height: h,
            output: nf,
          );
          _setStatus('Preparing clip ${i + 1}/${clips.length}…');
          final res = await FfmpegService.run(cmd);
          if (!res.ok) throw Exception('Clip ${i + 1} prepare failed. ${res.logs}');
          normFiles.add(nf);
          normDurMs.add((c.effectiveDuration * 1000).round());
        }
        // Step 2: join.
        final merged = p.join(dir.path, 'merged_$stamp.mp4');
        String? joinCmd;
        if (_crossfade) {
          // PRO: the selected transition + duration replace the fixed
          // fade; the cut-join fallback below is unchanged.
          joinCmd = proXfadeCommand(
            inputs: normFiles,
            durationsMs: normDurMs,
            transition: ProTransition(
              name: _proTransition,
              durationSec: _proTransitionDur,
            ),
            hasAudio: true,
            output: merged,
          );
        }
        if (joinCmd != null) {
          _setStatus('Applying crossfade…');
          final res = await FfmpegService.run(joinCmd);
          if (!res.ok) {
            // Fall back to a hard cut join rather than failing the export.
            _setStatus('Crossfade failed, falling back to cut join…');
            joinCmd = null;
          }
        }
        if (joinCmd == null) {
          final listFile = p.join(dir.path, 'concat_$stamp.txt');
          final lines = normFiles
              .map((f) => "file '${f.replaceAll("'", "'\\''")}'")
              .join('\n');
          await File(listFile).writeAsString(lines);
          final cc = FfmpegService.concatCommand(
            listFile: listFile,
            output: merged,
          );
          final res = await FfmpegService.run(cc);
          if (!res.ok) throw Exception('Merge failed. ${res.logs}');
        }
        // Step 3: final pass (speed/filter/aspect/text/music).
        final totalMs =
            ((normDurMs.reduce((a, b) => a + b) / effectiveSpeed)).round();
        final fc = FfmpegService.finalPassCommand(
          input: merged,
          speed: effectiveSpeed,
          filterPreset: _filter,
          aspect: _aspect,
          text: text,
          fontFile: _fontFile,
          subtitlesPath: subsPath,
          captionFilter: capFilter,
          textAtTop: useCaptions,
          musicPath: _musicPath,
          extraVideoFilter: extraVideoFilter,
          audioFilter: _combinedAudioFilter(rampAudio, effectiveSpeed, fxAudioFilter),
          output: out,
        );
        final res = await FfmpegService.run(
          fc,
          expectedMs: totalMs,
          onProgress: onProgress,
        );
        if (!res.ok && hasRamp) {
          // PRO ramp fallback, same contract as the single-clip branch.
          _setStatus(
            'Note: speed ramp fail ho gaya, baghair ramp ke save ho raha hai.',
          );
          final retryFc = FfmpegService.finalPassCommand(
            input: merged,
            speed: effectiveSpeed,
            filterPreset: _filter,
            aspect: _aspect,
            text: text,
            fontFile: _fontFile,
            subtitlesPath: subsPath,
            captionFilter: capFilter,
            textAtTop: useCaptions,
            musicPath: _musicPath,
            extraVideoFilter: gradeStr.isEmpty ? null : gradeStr,
            audioFilter: null,
            output: out,
          );
          final retryRes = await FfmpegService.run(
            retryFc,
            expectedMs: totalMs,
            onProgress: onProgress,
          );
          if (!retryRes.ok) {
            throw Exception('Final export failed. ${res.logs}');
          }
        } else if (!res.ok) {
          throw Exception('Final export failed. ${res.logs}');
        }
      }

      // PRO post-passes, AFTER the main pipeline and BEFORE the news
      // template pass. Each is guarded: on failure the previous output
      // is kept, a status note is written, and the export continues —
      // a pro pass NEVER fails the whole export.
      // (a) Stabilization.
      if (_proStabilize) {
        try {
          final stab = p.join(dir.path, 'pve_export_stab_$stamp.mp4');
          var lastPct = -1;
          final res = await runStabilized(
            input: out,
            output: stab,
            workDir: dir,
            expectedMs: (exportDurSec * 1000).round(),
            onProgress: (v) {
              final pct = (v * 100).round();
              if (pct != lastPct) {
                lastPct = pct;
                _setStatus(
                  'Stabilizing… $pct% done, ${100 - pct}% remaining',
                );
              }
            },
            onStep: (s) => _setStatus(s),
          );
          if (res.ok) {
            out = stab;
            _setStatus('Stabilized (${res.engine}).');
          } else {
            _setStatus(
              'Note: stabilization fail ho gaya, baghair is ke save ho raha hai.',
            );
          }
        } catch (e) {
          _setStatus(
            'Note: stabilization fail ho gaya ($e), baghair is ke save ho raha hai.',
          );
        }
      }
      // (b) Chromakey OR video BG remover — mutually exclusive; if
      // both are on, the BG remover wins (status note).
      final useBgRemover = _proBgRemove;
      if (useBgRemover && _proChroma) {
        _setStatus(
          'Note: BG remover aur chromakey dono on hain — BG remover use ho raha hai.',
        );
      }
      if (useBgRemover) {
        try {
          _setStatus(
            'Video background hata rahe hain… (lambi clips par minutes lag sakte hain)',
          );
          var lastPct = -1;
          final bgOut = await removeVideoBackground(
            input: out,
            backgroundKind: _proBgKind,
            backgroundColor: _proBgColor,
            backgroundImagePath:
                _proBgKind == 'image' ? _proBgImage : null,
            workDir: dir,
            onProgress: (v) {
              final pct = (v * 100).round();
              if (pct != lastPct) {
                lastPct = pct;
                _setStatus(
                  'Video BG remover… $pct% done, ${100 - pct}% remaining',
                );
              }
            },
            onStep: (s) => _setStatus(s),
          );
          out = bgOut;
          _setStatus('Video background removed.');
        } catch (e) {
          _setStatus(
            'Note: video BG remover fail ho gaya ($e), pichli video save ho rahi hai.',
          );
        }
      } else if (_proChroma) {
        try {
          _setStatus('Chromakey laga rahe hain…');
          final chromaOut = p.join(dir.path, 'pve_export_chroma_$stamp.mp4');
          final c = ProChroma(
            color: _proChromaColor,
            similarity: _proChromaSimilarity,
            blend: _proChromaBlend,
            backgroundKind: _proChromaBgKind,
            backgroundColor: _proChromaBgColor,
            backgroundImagePath:
                _proChromaBgKind == 'image' ? _proChromaBgImage : null,
          );
          final snippet = chromaFilterComplex(c: c, outLabel: '[vout]');
          final buf = StringBuffer();
          buf.write('-y -i ${FfmpegService.q(out)} ');
          if (_proChromaBgKind == 'image' && _proChromaBgImage != null) {
            buf.write('-i ${FfmpegService.q(_proChromaBgImage!)} ');
          }
          buf.write(
            '-filter_complex "$snippet" -map "[vout]" -map 0:a? '
            '-c:v libx264 -preset veryfast -crf 23 -c:a copy '
            '-movflags +faststart ${FfmpegService.q(chromaOut)}',
          );
          final res = await FfmpegService.run(buf.toString());
          if (res.ok) {
            out = chromaOut;
          } else {
            _setStatus(
              'Note: chromakey fail ho gaya, baghair is ke save ho raha hai.',
            );
          }
        } catch (e) {
          _setStatus(
            'Note: chromakey fail ho gaya ($e), baghair is ke save ho raha hai.',
          );
        }
      }
      // (c) ONE combined animated-overlay pass (motion title/sticker +
      // keyframed overlay + tracked sticker). Skipped entirely when
      // none of them are set.
      if (_proTitle.trim().isNotEmpty ||
          _proSticker.trim().isNotEmpty ||
          (_trackPoints.isNotEmpty && _trackSticker.trim().isNotEmpty)) {
        try {
          _setStatus('Motion titles laga rahe hain…');
          final ovOut = p.join(dir.path, 'pve_export_overlay_$stamp.mp4');
          final cmd = await _buildOverlayCommand(
            dir: dir,
            stamp: stamp,
            input: out,
            output: ovOut,
            durationSec: exportDurSec,
          );
          if (cmd != null) {
            final res = await FfmpegService.run(cmd);
            if (res.ok) {
              out = ovOut;
            } else {
              _setStatus(
                'Note: motion title pass fail ho gaya, baghair is ke save ho raha hai.',
              );
            }
          }
        } catch (e) {
          _setStatus(
            'Note: motion title pass fail ho gaya ($e), baghair is ke save ho raha hai.',
          );
        }
      }

      // FX Pack (d) PIP picture-in-picture post-pass. Guarded: on
      // failure the previous output is kept.
      if (_fxPip && _fxPipVideo != null) {
        try {
          _setStatus('PIP video laga rahe hain…');
          final pipOut = p.join(dir.path, 'pve_export_pip_$stamp.mp4');
          final snippet = pipOverlayFilter(
            pipLabel: '[1:v]',
            position: _fxPipPos,
            pipScale: _fxPipScale,
            margin: 24,
            outLabel: '[vout]',
          );
          final buf = StringBuffer();
          buf.write('-y -i ${FfmpegService.q(out)} ');
          buf.write('-i ${FfmpegService.q(_fxPipVideo!)} ');
          buf.write(
            '-filter_complex "$snippet" -map "[vout]" -map 0:a? '
            '-c:v libx264 -preset veryfast -crf 23 -c:a copy '
            '-movflags +faststart ${FfmpegService.q(pipOut)}',
          );
          final res = await FfmpegService.run(buf.toString());
          if (res.ok) {
            out = pipOut;
          } else {
            _setStatus(
              'Note: PIP fail ho gaya, baghair is ke save ho raha hai.',
            );
          }
        } catch (e) {
          _setStatus('Note: PIP fail ho gaya ($e).');
        }
      }

      // v2 news template + logo second pass (before gallery save).
      // The template frame is rendered by the same dart:ui renderer
      // the live view uses, so Urdu shaping stays correct; the ticker
      // is pinned to the left margin and the clock is the export-time
      // stamp — scrolling ticker and live clock are live-only. If the
      // pass fails, the clean export is saved instead of failing.
      if (_newsEnabled) {
        final useNews = _news.breakingHeadline.trim().isNotEmpty ||
            _news.lowerTitle.trim().isNotEmpty ||
            _news.lowerSubtitle.trim().isNotEmpty ||
            _news.tickerText.trim().isNotEmpty;
        String? templatePng;
        if (useNews) {
          _setStatus('News template laga rahe hain…');
          final tplFile = await renderLiveTemplateImage(
            template: _news,
            tickerPx: 0,
            tickerAtStart: true,
            now: DateTime.now(),
            dir: dir,
          );
          templatePng = tplFile.path;
        }
        String? logoPath;
        final pickedLogo = _news.logoPath;
        if (pickedLogo != null && await File(pickedLogo).exists()) {
          logoPath = pickedLogo;
        }
        final templated = p.join(dir.path, 'pve_export_templated_$stamp.mp4');
        final overlayCmd = FfmpegService.overlayPassCommand(
          input: out,
          templatePngPath: templatePng,
          logoPath: logoPath,
          logoPosition: _news.logoPosition.name,
          output: templated,
        );
        if (overlayCmd != null) {
          final res = await FfmpegService.run(overlayCmd);
          if (!res.ok) {
            _setStatus(
              'Note: news template pass fail ho gaya, saaf video save ho rahi hai.',
            );
          } else {
            out = templated;
          }
        }
      }

      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) {
          throw Exception('Gallery access was denied.');
        }
      }
      await Gal.putVideo(out);
      _setStatus('Saved to gallery: ${p.basename(out)}');
      AdService.showInterstitial();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Video saved to gallery.')),
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Wrapper around [_exportInner] with one subtitles-fallback retry:
  /// if the ASS subtitles filter is missing from this FFmpeg build, retry
  /// the export with timed drawtext captions (Latin scripts only).
  Future<void> _export() async {
    if (_clips.isEmpty) {
      _setStatus('Add at least one video first.');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Exporting…';
    });
    try {
      _captionDrawtextFallback = false;
      await _exportInner();
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final subFail = msg.contains('subtitle') ||
          msg.contains('no such filter') ||
          msg.contains('libass');
      if (_captions.isNotEmpty &&
          subFail &&
          !CaptionService.containsArabicInSegments(_captions)) {
        _setStatus('Subtitles filter failed, retrying with text captions…');
        _captionDrawtextFallback = true;
        try {
          await _exportInner();
        } catch (e2) {
          _setStatus('Export failed: $e2');
        }
      } else {
        _setStatus('Export failed: $e');
      }
    } finally {
      setState(() => _busy = false);
    }
  }

  /// Captions mapped onto the exported timeline: captions were recorded
  /// against the selected clip, so in a merged export they start after
  /// the preceding clips, and everything scales by the export speed.
  List<CaptionSegment> _adjustedCaptions() {
    if (_captions.isEmpty) return [];
    var offset = 0.0;
    for (var i = 0; i < _selected && i < _clips.length; i++) {
      offset += _clips[i].effectiveDuration;
    }
    final speed = _speed;
    return _captions
        .map((s) => CaptionSegment(
              s.text,
              (offset + s.start) / speed,
              (offset + s.end) / speed,
            ))
        .toList();
  }

  /// Generate captions for the selected clip from the video's OWN
  /// audio track: FFmpeg extracts the trimmed range as 16 kHz mono WAV
  /// and whisper.cpp transcribes it on-device (tiny multilingual model,
  /// Urdu/English). No microphone, no quiet room, earphones irrelevant,
  /// and no network after the first model download. One-shot inference: no Stop button
  /// (short clips take seconds; long clips take proportionally longer).
  Future<void> _generateCaptions() async {
    if (_clips.isEmpty) {
      _setStatus('Add a video first.');
      return;
    }
    if (_transcribing || _busy) return;
    final clip = _clips[_selected];
    setState(() {
      _transcribing = true;
      _status = 'Video ki audio nikal rahe hain…';
    });
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory(p.join(tmp.path, 'pve_video'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final wav = await FileCaptionEngine.extractAudio(
        inputPath: clip.file.path,
        trimStart: clip.trimStart,
        trimEnd: clip.effectiveEnd,
        dir: dir,
      );
      if (mounted) setState(() => _status = 'Transcribing…');
      var lastModelPct = -1;
      final raw = await FileCaptionEngine.transcribeFile(
        wavPath: wav.path,
        lang: _captionLocale == 'ur' ? 'ur' : 'en',
        // First captions use downloads the ~75 MB model once, with a
        // real progress bar (standing progress rule); afterwards it
        // works offline and this callback never fires.
        onModelDownloadProgress: (v) {
          final pct = (v * 100).round();
          if (mounted && pct != lastModelPct) {
            lastModelPct = pct;
            setState(
              () => _status =
                  'Caption model download… $pct% (pehli dafa, ek dafa hi)',
            );
          }
        },
      );
      final segments = CaptionService.chunkSegments(raw);
      if (!mounted) return;
      if (segments.isEmpty) {
        setState(() => _status =
            'No speech detected — video me awaz nahi mili ya samajh nahi aayi.');
      } else {
        setState(() {
          _captions = segments;
          _status =
              '${segments.length} caption segments ready — export se pehle Edit se dekh/edit kar sakte hain.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Captions failed: $e');
    } finally {
      if (mounted) setState(() => _transcribing = false);
    }
  }

  /// Review/edit dialog for the generated caption lines (text only;
  /// timings stay as recorded).
  Future<void> _editCaptions() async {
    if (_captions.isEmpty) return;
    final texts = _captions.map((s) => s.text).toList();
    final segs = List<CaptionSegment>.from(_captions);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit captions'),
        content: SizedBox(
          width: double.maxFinite,
          child: StatefulBuilder(
            builder: (ctx, setDialogState) => ListView.builder(
              shrinkWrap: true,
              itemCount: texts.length,
              itemBuilder: (ctx, i) => Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: texts[i],
                      decoration:
                          InputDecoration(labelText: 'Caption ${i + 1}'),
                      onChanged: (v) => texts[i] = v,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => setDialogState(() {
                      texts.removeAt(i);
                      segs.removeAt(i);
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) {
      final kept = <CaptionSegment>[];
      for (var i = 0; i < texts.length; i++) {
        final text = texts[i].trim();
        if (text.isEmpty) continue;
        kept.add(CaptionSegment(text, segs[i].start, segs[i].end));
      }
      setState(() {
        _captions = kept;
        _status = kept.isEmpty
            ? 'Captions cleared.'
            : '${kept.length} caption segments ready.';
      });
    }
  }

  void _splitSelectedClip() {
    if (_clips.isEmpty) return;
    final clip = _clips[_selected];
    if (clip.effectiveDuration < 1.0) {
      _setStatus('Clip too short to split.');
      return;
    }
    final mid = clip.trimStart + clip.effectiveDuration / 2;
    final second = VideoClip(clip.file, clip.duration, clip.aspectRatio);
    second.trimStart = mid;
    second.trimEnd = clip.effectiveEnd;
    clip.trimEnd = mid;
    setState(() {
      _clips.insert(_selected + 1, second);
      _selected = _selected + 1;
    });
    unawaited(_loadPreview());
  }

  Widget _railButton(String key, String label, IconData icon) {
    final selected = _activeTool == key;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _activeTool = key),
        child: Container(
          width: 76,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? Colors.teal.shade700 : const Color(0xFF232323),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: Colors.white),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _toolPanelChildren() {
    switch (_activeTool) {
      case 'stickers':
        return [
          const Text('Stickers / emoji overlay',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
TextField(
                decoration: const InputDecoration(
                  labelText: 'Sticker / emoji overlay',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _proSticker = v),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _proStickerPreset,
                decoration: const InputDecoration(
                  labelText: 'Sticker preset',
                ),
                items: const [
                  'fadeIn',
                  'slideLeft',
                  'slideRight',
                  'slideUp',
                  'zoomPop',
                ]
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _proStickerPreset = v ?? 'fadeIn'),
              ),
              const Divider(height: 32),
          const SizedBox(height: 12),
          const Text(
            'Keyframes animate the title/sticker overlay from start to end.',
            style: TextStyle(color: Colors.grey),
          ),
// Keyframes.
              SwitchListTile(
                title: const Text('Keyframes (motion title/sticker)'),
                subtitle: const Text(
                  'Start se end tak overlay move/scale/fade/rotate hoga.',
                ),
                value: _proKeyframes,
                onChanged: (v) => setState(() => _proKeyframes = v),
              ),
              if (_proKeyframes &&
                  _proTitle.trim().isEmpty &&
                  _proSticker.trim().isEmpty)
                const Text(
                  'Pehle motion title ya sticker likhein — keyframes usi '
                  'overlay par lagenge.',
                  style: TextStyle(color: Colors.grey),
                ),
              if (_proKeyframes &&
                  (_proTitle.trim().isNotEmpty ||
                      _proSticker.trim().isNotEmpty)) ...[
                const Text('Start keyframe',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                _ProSlider(
                  label: 'Start X',
                  value: _kfStartX,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => setState(() => _kfStartX = v),
                ),
                _ProSlider(
                  label: 'Start Y',
                  value: _kfStartY,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => setState(() => _kfStartY = v),
                ),
                _ProSlider(
                  label: 'Start scale',
                  value: _kfStartScale,
                  min: 0.5,
                  max: 2,
                  divisions: 30,
                  onChanged: (v) => setState(() => _kfStartScale = v),
                ),
                _ProSlider(
                  label: 'Start opacity',
                  value: _kfStartOpacity,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => setState(() => _kfStartOpacity = v),
                ),
                _ProSlider(
                  label: 'Start rotation',
                  value: _kfStartRotation,
                  min: -180,
                  max: 180,
                  divisions: 72,
                  digits: 0,
                  onChanged: (v) => setState(() => _kfStartRotation = v),
                ),
                const Text('End keyframe',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                _ProSlider(
                  label: 'End X',
                  value: _kfEndX,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => setState(() => _kfEndX = v),
                ),
                _ProSlider(
                  label: 'End Y',
                  value: _kfEndY,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => setState(() => _kfEndY = v),
                ),
                _ProSlider(
                  label: 'End scale',
                  value: _kfEndScale,
                  min: 0.5,
                  max: 2,
                  divisions: 30,
                  onChanged: (v) => setState(() => _kfEndScale = v),
                ),
                _ProSlider(
                  label: 'End opacity',
                  value: _kfEndOpacity,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => setState(() => _kfEndOpacity = v),
                ),
                _ProSlider(
                  label: 'End rotation',
                  value: _kfEndRotation,
                  min: -180,
                  max: 180,
                  divisions: 72,
                  digits: 0,
                  onChanged: (v) => setState(() => _kfEndRotation = v),
                ),
              ],
              const Divider(height: 32),
        ];
      case 'effects':
        return [
          const Text('Effects — animated motion title',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// Motion titles + sticker.
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Motion title (PNG render, Urdu-safe)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _proTitle = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _proTitlePreset,
                      decoration: const InputDecoration(
                        labelText: 'Title preset',
                      ),
                      items: const [
                        'fadeIn',
                        'slideLeft',
                        'slideRight',
                        'slideUp',
                        'zoomPop',
                      ]
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(s),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _proTitlePreset = v ?? 'fadeIn'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _proTitlePosition,
                      decoration: const InputDecoration(
                        labelText: 'Title position',
                      ),
                      items: const ['topCenter', 'center', 'bottomCenter']
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(s),
                              ))
                          .toList(),
                      onChanged: (v) => setState(
                        () => _proTitlePosition = v ?? 'bottomCenter',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
          const Divider(height: 32),
          const Text('Shake effect (Alight Motion-style)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          DropdownButtonFormField<ShakeFx>(
            initialValue: _fxShake,
            decoration: const InputDecoration(labelText: 'Shake intensity'),
            items: ShakeFx.values
                .map((v) => DropdownMenuItem(
                      value: v,
                      child: Text(shakeFxLabels[v.index]),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _fxShake = v ?? ShakeFx.none),
          ),
          const SizedBox(height: 8),
        ];
      case 'filters':
        return [
          const Text('Filters',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// Speed / filter / aspect
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<double>(
                  initialValue: _speed,
                  decoration: const InputDecoration(labelText: 'Speed'),
                  items: const [0.5, 0.75, 1.0, 1.5, 2.0]
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text('${s}x'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _speed = v ?? 1.0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _filter,
                  decoration: const InputDecoration(labelText: 'Filter'),
                  items: const ['Normal', 'Warm', 'Cool', 'B&W', 'Vivid', 'Sepia']
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                  onChanged: (v) => setState(() => _filter = v ?? 'Normal'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _aspect,
                  decoration: const InputDecoration(labelText: 'Aspect'),
                  items: const ['Original', '9:16', '16:9', '1:1']
                      .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                      .toList(),
                  onChanged: (v) => setState(() => _aspect = v ?? 'Original'),
                ),
              ),
            ],
          ),
        ];
      case 'audio':
        return [
          const Text('Audio — music + waveform',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// Music
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _pickMusic,
                  icon: const Icon(Icons.music_note),
                  label: Text(
                    _musicPath == null
                        ? 'Add music'
                        : p.basename(_musicPath!),
                  ),
                ),
              ),
              if (_musicPath != null)
                IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _musicPath = null),
                ),
            ],
          ),
          const SizedBox(height: 12),
// Waveform.
              const Text('Waveform',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_waveformBusy || _busy || _clips.isEmpty)
                          ? null
                          : _showWaveform,
                      icon: const Icon(Icons.show_chart),
                      label: Text(
                        _waveformBusy ? 'Generating…' : 'Show waveform',
                      ),
                    ),
                  ),
                ],
              ),
              if (_waveformPath != null) ...[
                const SizedBox(height: 8),
                Image.file(
                  File(_waveformPath!),
                  height: 60,
                  width: double.infinity,
                  fit: BoxFit.contain,
                ),
              ],
              const SizedBox(height: 8),
          const Divider(height: 32),
          const Text('Voice changer (CapCut-style)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          DropdownButtonFormField<VoiceFx>(
            initialValue: _fxVoice,
            decoration: const InputDecoration(labelText: 'Voice effect'),
            items: VoiceFx.values
                .map((v) => DropdownMenuItem(
                      value: v,
                      child: Text(voiceFxLabels[v.index]),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _fxVoice = v ?? VoiceFx.none),
          ),
          const SizedBox(height: 8),
          const Text('Audio fade',
              style: TextStyle(fontWeight: FontWeight.bold)),
          _ProSlider(
            label: 'Fade in (s)',
            value: _fxFadeIn,
            min: 0,
            max: 3,
            divisions: 30,
            onChanged: (v) => setState(() => _fxFadeIn = v),
          ),
          _ProSlider(
            label: 'Fade out (s)',
            value: _fxFadeOut,
            min: 0,
            max: 3,
            divisions: 30,
            onChanged: (v) => setState(() => _fxFadeOut = v),
          ),
          const SizedBox(height: 8),
        ];
      case 'speed':
        return [
          const Text('Speed — fixed speed + speed ramps',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// Speed / filter / aspect
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<double>(
                  initialValue: _speed,
                  decoration: const InputDecoration(labelText: 'Speed'),
                  items: const [0.5, 0.75, 1.0, 1.5, 2.0]
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text('${s}x'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _speed = v ?? 1.0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _filter,
                  decoration: const InputDecoration(labelText: 'Filter'),
                  items: const ['Normal', 'Warm', 'Cool', 'B&W', 'Vivid', 'Sepia']
                      .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                      .toList(),
                  onChanged: (v) => setState(() => _filter = v ?? 'Normal'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _aspect,
                  decoration: const InputDecoration(labelText: 'Aspect'),
                  items: const ['Original', '9:16', '16:9', '1:1']
                      .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                      .toList(),
                  onChanged: (v) => setState(() => _aspect = v ?? 'Original'),
                ),
              ),
            ],
          ),
// Speed ramp.
              const Text('Speed ramp',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              DropdownButtonFormField<String>(
                initialValue: _proRamp,
                decoration: const InputDecoration(labelText: 'Ramp preset'),
                items: const [
                  'None',
                  'slowMiddle',
                  'slowStart',
                  'slowEnd',
                  'pulse',
                ]
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _proRamp = v ?? 'None'),
              ),
              const Text(
                'Note: ramp on ho to fixed Speed dropdown ignore ho jata hai.',
                style: TextStyle(color: Colors.grey),
              ),
              const Divider(height: 32),
          const Text('Clip FX (VN/CapCut-style)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          SwitchListTile(
            title: const Text('Reverse video'),
            subtitle: const Text('Poori clip ulti chalegi (video + audio).'),
            value: _fxReverse,
            onChanged: (v) => setState(() => _fxReverse = v),
          ),
          SwitchListTile(
            title: const Text('Freeze frame'),
            subtitle: const Text('Ek frame ko rok kar hold karein.'),
            value: _fxFreeze,
            onChanged: (v) => setState(() => _fxFreeze = v),
          ),
          if (_fxFreeze) ...[
            _ProSlider(
              label: 'Freeze at (s)',
              value: _fxFreezeAt,
              min: 0.5,
              max: 30,
              divisions: 59,
              onChanged: (v) => setState(() => _fxFreezeAt = v),
            ),
            _ProSlider(
              label: 'Hold (s)',
              value: _fxFreezeHold,
              min: 0.5,
              max: 5,
              divisions: 45,
              onChanged: (v) => setState(() => _fxFreezeHold = v),
            ),
          ],
          SwitchListTile(
            title: const Text('Silence remover'),
            subtitle: const Text(
                'Khamosh hisse kaat dein (CapCut auto-cut jaisa).'),
            value: _fxSilenceRemove,
            onChanged: (v) => setState(() => _fxSilenceRemove = v),
          ),
          const Divider(height: 32),
        ];
      case 'transitions':
        return [
          const Text('Transitions',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
if (AppConfig.crossfadeEnabled)
            SwitchListTile(
              title: const Text('Crossfade between clips'),
            subtitle: const Text('Simple fade transition when merging'),
            value: _crossfade,
            onChanged: (v) => setState(() => _crossfade = v),
          ),
          const Divider(height: 32),
          // ---- PRO tools (v2.1.0) ----
// Transitions.
              const Text('Transitions',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              DropdownButtonFormField<String>(
                initialValue: _proTransition,
                decoration: const InputDecoration(labelText: 'Transition'),
                items: const [
                  'fade',
                  'slideleft',
                  'slideright',
                  'slideup',
                  'slidedown',
                  'wipeleft',
                  'wiperight',
                  'wipeup',
                  'wipedown',
                  'circlecrop',
                  'dissolve',
                  'pixelize',
                  'smoothleft',
                  'smoothright',
                  'radial',
                  'rectcrop',
                  'hblur',
                  'circleopen',
                ]
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => _proTransition = v ?? 'fade'),
              ),
              _ProSlider(
                label: 'Transition duration (s)',
                value: _proTransitionDur,
                min: 0.3,
                max: 2.0,
                divisions: 17,
                onChanged: (v) => setState(() => _proTransitionDur = v),
              ),
              const Text(
                'Sirf tab lagega jab Crossfade between clips ON ho; '
                'OFF par aaj ki tarah hard cuts rahenge.',
                style: TextStyle(color: Colors.grey),
              ),
              const Divider(height: 32),
        ];
      case 'overlays':
        return [
          const Text('Overlays — news template (Live Studio wala)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// News template (shared with Live Studio).
          SwitchListTile(
            title: const Text('News Template (Live Studio wala)'),
            subtitle: const Text(
              'Breaking banner, lower-third, ticker, clock, logo — '
              'export par bhi lagega.',
            ),
            value: _newsEnabled,
            onChanged: (v) => setState(() => _newsEnabled = v),
          ),
          if (_newsEnabled) ...[
            TextFormField(
              initialValue: _news.breakingHeadline,
              decoration: const InputDecoration(
                labelText: 'Breaking headline (surkh patti)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                _news.breakingHeadline = v;
                unawaited(_news.save());
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _news.lowerTitle,
              decoration: const InputDecoration(
                labelText: 'Lower-third title (naam)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                _news.lowerTitle = v;
                unawaited(_news.save());
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _news.lowerSubtitle,
              decoration: const InputDecoration(
                labelText: 'Lower-third subtitle (ohda / jagah)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                _news.lowerSubtitle = v;
                unawaited(_news.save());
              },
            ),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: _news.tickerText,
              decoration: const InputDecoration(
                labelText: 'Ticker text (neeche chalta hua)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                _news.tickerText = v;
                unawaited(_news.save());
              },
            ),
            SwitchListTile(
              title: const Text('Live clock / date dikhayein'),
              value: _news.showClock,
              onChanged: (v) {
                setState(() => _news.showClock = v);
                unawaited(_news.save());
              },
            ),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final picked = await _picker.pickImage(
                        source: ImageSource.gallery,
                      );
                      if (picked == null) return;
                      setState(() => _news.logoPath = picked.path);
                      await _news.save();
                    },
                    icon: const Icon(Icons.image),
                    label: Text(
                      _news.logoPath == null
                          ? 'Logo chunein'
                          : 'Logo badlein',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<LogoPosition>(
                    initialValue: _news.logoPosition,
                    decoration: const InputDecoration(
                      labelText: 'Logo jagah',
                      border: OutlineInputBorder(),
                    ),
                    items: LogoPosition.values
                        .map((pos) => DropdownMenuItem(
                              value: pos,
                              child: Text(pos.label),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _news.logoPosition = v);
                      unawaited(_news.save());
                    },
                  ),
                ),
              ],
            ),
            SwitchListTile(
              title: const Text('Logo ahista ghoome (rotation)'),
              subtitle: const Text('Sirf live me ghoomega; export me static.'),
              value: _news.logoRotate,
              onChanged: (v) {
                setState(() => _news.logoRotate = v);
                unawaited(_news.save());
              },
            ),
            const Text(
              'Note: export me ticker aur clock ek still frame honge — '
              'scrolling ticker aur live clock sirf live me chalte hain. '
              'Yehi template Live Studio me bhi use hota hai.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
          const Divider(height: 32),
          const Text('Picture-in-picture (KineMaster-style)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          SwitchListTile(
            title: const Text('PIP video overlay'),
            subtitle: const Text(
                'Doosri video chhoti karke corner me lagayein.'),
            value: _fxPip,
            onChanged: (v) => setState(() => _fxPip = v),
          ),
          if (_fxPip) ...[
            ElevatedButton.icon(
              onPressed: () async {
                final picked =
                    await _picker.pickVideo(source: ImageSource.gallery);
                if (picked != null) {
                  setState(() => _fxPipVideo = picked.path);
                }
              },
              icon: const Icon(Icons.video_library),
              label: Text(_fxPipVideo == null
                  ? 'PIP video chunein'
                  : p.basename(_fxPipVideo!)),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<PipPosition>(
              initialValue: _fxPipPos,
              decoration: const InputDecoration(labelText: 'PIP position'),
              items: PipPosition.values
                  .map((v) => DropdownMenuItem(
                        value: v,
                        child: Text(pipPositionLabels[v.index]),
                      ))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _fxPipPos = v ?? PipPosition.bottomRight),
            ),
            _ProSlider(
              label: 'PIP size',
              value: _fxPipScale,
              min: 0.15,
              max: 0.5,
              divisions: 35,
              onChanged: (v) => setState(() => _fxPipScale = v),
            ),
          ],
          const Divider(height: 32),
        ];
      case 'captions':
        return [
const Text('Auto Captions (CapCut-style)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _captionLocale,
                  decoration:
                      const InputDecoration(labelText: 'Caption language'),
                  items: const [
                    DropdownMenuItem(value: 'ur', child: Text('Urdu')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: (v) => setState(() => _captionLocale = v ?? 'ur'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      (_transcribing || _busy) ? null : _generateCaptions,
                  icon: const Icon(Icons.closed_caption),
                  label: Text(
                    _transcribing ? 'Transcribing…' : 'Generate Auto Captions',
                  ),
                ),
              ),
            ],
          ),
          if (_transcribing) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Video ki apni audio se captions ban rahe hain…',
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: switch (_captionStyle) {
                    CaptionStyle.standard => 'standard',
                    CaptionStyle.highlight => 'highlight',
                    CaptionStyle.gold => 'gold',
                    CaptionStyle.clean => 'clean',
                    CaptionStyle.pop => 'pop',
                  },
                  decoration:
                      const InputDecoration(labelText: 'Caption style'),
                  items: const [
                    DropdownMenuItem(
                        value: 'standard', child: Text('Default')),
                    DropdownMenuItem(
                        value: 'highlight',
                        child: Text('Highlight (black on yellow)')),
                    DropdownMenuItem(
                        value: 'gold', child: Text('Gold')),
                    DropdownMenuItem(
                        value: 'clean', child: Text('Clean')),
                    DropdownMenuItem(
                        value: 'pop',
                        child: Text('Pop (word by word)')),
                  ],
                  onChanged: (v) => setState(() {
                    _captionStyle = switch (v) {
                      'highlight' => CaptionStyle.highlight,
                      'gold' => CaptionStyle.gold,
                      'clean' => CaptionStyle.clean,
                      'pop' => CaptionStyle.pop,
                      _ => CaptionStyle.standard,
                    };
                  }),
                ),
              ),
            ],
          ),
          if (_captions.isNotEmpty && !_transcribing) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_captions.length} caption segments ready — export me video par jal jayenge.',
                  ),
                ),
                TextButton(
                  onPressed: _editCaptions,
                  child: const Text('Edit'),
                ),
                TextButton(
                  onPressed: () => setState(() => _captions = []),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Note: captions video ki apni audio se on-device banenge (whisper, Urdu/English) — mic, quiet room ya earphones ki koi pabandi nahi. Pehli dafa ~75 MB caption model download hoga (progress ke saath); us ke baad sab kuch phone par hi, offline hota hai.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
        ];
      case 'stabilization':
        return [
// Stabilization.
              SwitchListTile(
                title: const Text('Stabilization'),
                subtitle: const Text(
                  'Vidstab jab available ho, warna deshake engine use hoga.',
                ),
                value: _proStabilize,
                onChanged: (v) => setState(() => _proStabilize = v),
              ),
              const Divider(height: 32),
        ];
      case 'chroma':
        return [
          const Text('Chromakey / BG remover',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// Chromakey.
              SwitchListTile(
                title: const Text('Chromakey'),
                subtitle: const Text(
                  'Green/blue background hatakar naya background lagayein.',
                ),
                value: _proChroma,
                onChanged: (v) => setState(() => _proChroma = v),
              ),
              if (_proChroma) ...[
                DropdownButtonFormField<String>(
                  initialValue: _proChromaColor,
                  decoration: const InputDecoration(labelText: 'Key color'),
                  items: const ['green', 'blue']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _proChromaColor = v ?? 'green'),
                ),
                _ProSlider(
                  label: 'Similarity',
                  value: _proChromaSimilarity,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => setState(() => _proChromaSimilarity = v),
                ),
                _ProSlider(
                  label: 'Blend',
                  value: _proChromaBlend,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => setState(() => _proChromaBlend = v),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _proChromaBgKind,
                  decoration:
                      const InputDecoration(labelText: 'Background kind'),
                  items: const [
                    DropdownMenuItem(value: 'color', child: Text('Color')),
                    DropdownMenuItem(value: 'image', child: Text('Image')),
                  ],
                  onChanged: (v) =>
                      setState(() => _proChromaBgKind = v ?? 'color'),
                ),
                if (_proChromaBgKind == 'color')
                  DropdownButtonFormField<String>(
                    initialValue: _proChromaBgColor,
                    decoration:
                        const InputDecoration(labelText: 'Background color'),
                    items: const {
                      '#00FF00': 'Green',
                      '#0000FF': 'Blue',
                      '#000000': 'Black',
                      '#FFFFFF': 'White',
                    }
                        .entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _proChromaBgColor = v ?? '#00FF00'),
                  ),
                if (_proChromaBgKind == 'image')
                  ElevatedButton.icon(
                    onPressed: () => _pickProImage(
                      (path) => _proChromaBgImage = path,
                    ),
                    icon: const Icon(Icons.image),
                    label: Text(
                      _proChromaBgImage == null
                          ? 'Background image chunein'
                          : p.basename(_proChromaBgImage!),
                    ),
                  ),
              ],
              const Divider(height: 32),
// Video BG remover.
              SwitchListTile(
                title: const Text('Video background remover (ML)'),
                subtitle: const Text(
                  'Premium: pehle ek short ad se unlock hoga.',
                ),
                value: _proBgRemove,
                onChanged: _onBgRemoverChanged,
              ),
              if (_proBgRemove) ...[
                DropdownButtonFormField<String>(
                  initialValue: _proBgKind,
                  decoration:
                      const InputDecoration(labelText: 'Background kind'),
                  items: const [
                    DropdownMenuItem(value: 'color', child: Text('Color')),
                    DropdownMenuItem(value: 'image', child: Text('Image')),
                  ],
                  onChanged: (v) => setState(() => _proBgKind = v ?? 'color'),
                ),
                if (_proBgKind == 'color')
                  DropdownButtonFormField<String>(
                    initialValue: _proBgColor,
                    decoration:
                        const InputDecoration(labelText: 'Background color'),
                    items: const {
                      '#00FF00': 'Green',
                      '#0000FF': 'Blue',
                      '#000000': 'Black',
                      '#FFFFFF': 'White',
                    }
                        .entries
                        .map((e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _proBgColor = v ?? '#00FF00'),
                  ),
                if (_proBgKind == 'image')
                  ElevatedButton.icon(
                    onPressed: () =>
                        _pickProImage((path) => _proBgImage = path),
                    icon: const Icon(Icons.image),
                    label: Text(
                      _proBgImage == null
                          ? 'Background image chunein'
                          : p.basename(_proBgImage!),
                    ),
                  ),
              ],
              const Text(
                'Note: lambi clips par minutes lag sakte hain; width '
                'capped hai; saaf subject wali video par behtareen '
                'result milta hai. Progress export status me dikhega.',
                style: TextStyle(color: Colors.grey),
              ),
              const Divider(height: 32),
        ];
      case 'tracking':
        return [
// Motion tracking.
              const Text('Motion tracking (ML)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Text(
                'Preview video par object ko tap karein, phir Track '
                'dabayein. (Preview 16:9 box hai, is liye tap point '
                'approximate hai.)',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Tracked sticker text',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _trackSticker = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_trackStartX == null ||
                              _tracking ||
                              _busy)
                          ? null
                          : _trackObject,
                      icon: const Icon(Icons.my_location),
                      label: Text(_tracking ? 'Tracking…' : 'Track object'),
                    ),
                  ),
                ],
              ),
              if (_trackStartX != null)
                Text(
                  'Tapped: (${_trackStartX!.toStringAsFixed(2)}, ${_trackStartY!.toStringAsFixed(2)})',
                ),
              if (_trackPoints.isNotEmpty)
                Text('${_trackPoints.length} track points ready.'),
              const Divider(height: 32),
        ];
      case 'beats':
        return [
// Beat sync.
              const Text('Beat sync',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_detectingBeats || _busy || _clips.isEmpty)
                          ? null
                          : _detectBeats,
                      icon: const Icon(Icons.graphic_eq),
                      label: Text(
                        _detectingBeats ? 'Detecting…' : 'Detect beats',
                      ),
                    ),
                  ),
                ],
              ),
              if (_beats.isNotEmpty)
                Text(
                  '${_beats.length} beats — '
                  '${_beats.take(5).map((b) => '${b.toStringAsFixed(1)}s').join(', ')}'
                  '${_beats.length > 5 ? ', …' : ''}',
                ),
              SwitchListTile(
                title: const Text('Beat auto-cut'),
                subtitle: const Text(
                  'Single clip ko beat boundaries par kaatkar jorega.',
                ),
                value: _beatAutoCut,
                onChanged: (v) => setState(() => _beatAutoCut = v),
              ),
              if (_beatAutoCut && _clips.length > 1)
                const Text(
                  'Note: multi-clip me beat auto-cut nahi lagta — sirf '
                  'markers dikhenge; cut sirf single clip par hota hai. '
                  'Auto-cut OFF rakhein to single clip par bhi sirf '
                  'markers rehte hain.',
                  style: TextStyle(color: Colors.grey),
                ),
              const Divider(height: 32),
        ];
      case 'grading':
        return [
// Grading.
              const Text('Grading',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _proLut,
                decoration: const InputDecoration(labelText: 'LUT look'),
                items: proLuts
                    .map((e) => DropdownMenuItem(
                          value: e['name'] ?? '',
                          child: Text(
                            (e['name'] ?? '').isEmpty ? 'None' : e['name']!,
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _proLut = v ?? ''),
              ),
              _ProSlider(
                label: 'Temperature',
                value: _proTemperature,
                min: -100,
                max: 100,
                divisions: 40,
                digits: 0,
                onChanged: (v) => setState(() => _proTemperature = v),
              ),
              _ProSlider(
                label: 'Tint',
                value: _proTint,
                min: -100,
                max: 100,
                divisions: 40,
                digits: 0,
                onChanged: (v) => setState(() => _proTint = v),
              ),
              _ProSlider(
                label: 'Saturation',
                value: _proSaturation,
                min: 0,
                max: 2,
                divisions: 40,
                onChanged: (v) => setState(() => _proSaturation = v),
              ),
              _ProSlider(
                label: 'Vibrance',
                value: _proVibrance,
                min: 0,
                max: 2,
                divisions: 40,
                onChanged: (v) => setState(() => _proVibrance = v),
              ),
              _ProSlider(
                label: 'Contrast',
                value: _proContrast,
                min: 0,
                max: 2,
                divisions: 40,
                onChanged: (v) => setState(() => _proContrast = v),
              ),
              _ProSlider(
                label: 'Shadows',
                value: _proShadows,
                min: -100,
                max: 100,
                divisions: 40,
                digits: 0,
                onChanged: (v) => setState(() => _proShadows = v),
              ),
              _ProSlider(
                label: 'Highlights',
                value: _proHighlights,
                min: -100,
                max: 100,
                divisions: 40,
                digits: 0,
                onChanged: (v) => setState(() => _proHighlights = v),
              ),
              const Divider(height: 32),
        ];
      case 'live':
        return [
          const Text('Live Studio',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            'Facebook + YouTube par ek saath live — breaking news '
            'templates ke saath. Live Studio apni screen par khulta hai.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LiveStudioScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.live_tv),
              label: const Text('Open Live Studio'),
            ),
          ),
        ];
      case 'text':
      default:
        return [
          const Text('Text overlay',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
// Text overlay
          TextField(
            decoration: const InputDecoration(
              labelText: 'Text overlay (single line)',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _text = v),
          ),
          const SizedBox(height: 12),
          const Divider(height: 32),
        ];
    }
  }

  Widget _timelineSection(VideoClip? clip) {
    final ctrl = _controller;
    final pos = ctrl != null && ctrl.value.isInitialized
        ? ctrl.value.position.inMilliseconds / 1000
        : 0.0;
    final dur = clip != null ? clip.duration.inMilliseconds / 1000 : 0.0;
    final frac = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
    return Container(
      color: const Color(0xFF1B1B1B),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Timeline',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _clips.isEmpty
                      ? 'No clips yet — Add video above'
                      : 'Playhead ${pos.toStringAsFixed(1)}s / ${dur.toStringAsFixed(1)}s'
                          ' • Clip ${_selected + 1} of ${_clips.length}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: _clips.isEmpty ? null : _splitSelectedClip,
                icon: const Icon(Icons.content_cut, size: 18),
                label: const Text('Split'),
              ),
            ],
          ),
          // Playhead marker (red) above the clip blocks.
          Container(
            height: 4,
            alignment: Alignment(frac * 2 - 1, 0),
            child: Container(width: 28, height: 4, color: Colors.redAccent),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 64,
            child: _clips.isEmpty
                ? const Center(
                    child: Text('Timeline khaali hai',
                        style: TextStyle(color: Colors.grey)))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _clips.asMap().entries.map((e) {
                        final i = e.key;
                        final c = e.value;
                        final selected = i == _selected;
                        return GestureDetector(
                          onTap: () async {
                            setState(() => _selected = i);
                            await _loadPreview();
                          },
                          child: Container(
                            width: 128,
                            height: 64,
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? Colors.teal.shade700
                                  : const Color(0xFF2E2E2E),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? Colors.tealAccent
                                    : Colors.grey.shade700,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text('Clip ${i + 1}',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12)),
                                    ),
                                    GestureDetector(
                                      onTap: () async {
                                        setState(() {
                                          _clips.removeAt(i);
                                          if (_selected >= _clips.length) {
                                            _selected = _clips.length - 1;
                                          }
                                        });
                                        if (_clips.isNotEmpty) {
                                          await _loadPreview();
                                        } else {
                                          await _controller?.dispose();
                                          setState(() => _controller = null);
                                        }
                                      },
                                      child: const Icon(Icons.close,
                                          size: 16, color: Colors.white70),
                                    ),
                                  ],
                                ),
                                Text(
                                  p.basename(c.file.path),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 11),
                                ),
                                Text(
                                  '${c.effectiveDuration.toStringAsFixed(1)}s'
                                  ' • trim ${c.trimStart.toStringAsFixed(1)}'
                                  '–${c.effectiveEnd.toStringAsFixed(1)}s',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
          if (_clips.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text('Trim selected clip — drag the handles',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
if (clip != null) ...[
              const SizedBox(height: 8),
              Text(
                'Trim selected clip: ${clip.trimStart.toStringAsFixed(1)}s – ${clip.effectiveEnd.toStringAsFixed(1)}s',
              ),
              RangeSlider(
                values: RangeValues(
                  clip.trimStart,
                  clip.effectiveEnd,
                ),
                min: 0,
                max: clip.duration.inMilliseconds / 1000,
                divisions:
                    (clip.duration.inMilliseconds / 100).round().clamp(1, 1000),
                labels: RangeLabels(
                  '${clip.trimStart.toStringAsFixed(1)}s',
                  '${clip.effectiveEnd.toStringAsFixed(1)}s',
                ),
                onChanged: (v) {
                  if (v.end - v.start < 0.5) return;
                  setState(() {
                    clip.trimStart = v.start;
                    clip.trimEnd = v.end;
                  });
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clip = _clips.isEmpty ? null : _clips[_selected];
    final ctrl = _controller;
    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal, brightness: Brightness.dark),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('TJ Pro — Video Editor'),
          actions: [
            IconButton(
              tooltip: 'Export video',
              onPressed: _busy ? null : _showExportDialog,
              icon: const Icon(Icons.ios_share),
            ),
          ],
        ),
        // LAYOUT (Jaani spec 28 Oct 12:02 PKT, top to bottom):
        // 1. preview on top (large)  2. timeline beneath it
        // 3. tool panel  4. ONE single-row tool rail at the bottom.
        body: Column(
          children: [
            Expanded(
              flex: 5,
              child: Container(
                color: Colors.black,
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: ctrl != null && ctrl.value.isInitialized
                            ? Stack(
                                alignment: Alignment.bottomCenter,
                                children: [
                                  GestureDetector(
                                    onTapDown: _onPreviewTapDown,
                                    child: VideoPlayer(ctrl),
                                  ),
                                  if (_trackStartX != null)
                                    Align(
                                      alignment: Alignment(
                                        _trackStartX! * 2 - 1,
                                        _trackStartY! * 2 - 1,
                                      ),
                                      child: const Icon(
                                        Icons.location_on,
                                        color: Colors.redAccent,
                                        size: 28,
                                      ),
                                    ),
                                  if (_text.trim().isNotEmpty)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 24),
                                      child: Text(
                                        _text,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          shadows: [
                                            Shadow(
                                                color: Colors.black,
                                                blurRadius: 6),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              )
                            : const Text('No video selected',
                                style: TextStyle(color: Colors.white70)),
                      ),
                    ),
                    const SizedBox(height: 8),
Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _addClip,
                  icon: const Icon(Icons.video_library),
                  label: const Text('Add video'),
                ),
              ),
              const SizedBox(width: 8),
              if (ctrl != null && ctrl.value.isInitialized)
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      ctrl.value.isPlaying ? ctrl.pause() : ctrl.play();
                    });
                  },
                  icon: Icon(
                    ctrl.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  ),
                  label: Text(ctrl.value.isPlaying ? 'Pause' : 'Play'),
                ),
            ],
          ),
                  ],
                ),
              ),
            ),
            _timelineSection(clip),
            Expanded(
              flex: 4,
              child: Container(
                color: const Color(0xFF121212),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _export,
                        icon: const Icon(Icons.ios_share),
                        label: Text(_busy ? 'Exporting…' : 'Export video'),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(top: 8),
                        children: _toolPanelChildren(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(_status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            // ONE single horizontal tool row (scrollable) — never a grid,
            // never two rows. Every tool from the old screen is here.
            Container(
              height: 76,
              color: const Color(0xFF1B1B1B),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  _railButton('text', 'Text', Icons.text_fields),
                  _railButton('stickers', 'Stickers', Icons.emoji_emotions),
                  _railButton('effects', 'Effects', Icons.auto_awesome),
                  _railButton('filters', 'Filters', Icons.filter_vintage),
                  _railButton('audio', 'Audio', Icons.music_note),
                  _railButton('speed', 'Speed', Icons.speed),
                  _railButton('transitions', 'Transitions', Icons.swap_horiz),
                  _railButton('overlays', 'Overlays', Icons.layers),
                  _railButton('captions', 'Captions', Icons.closed_caption),
                  _railButton('stabilization', 'Stabilization', Icons.videocam),
                  _railButton('chroma', 'Chromakey/BG remover', Icons.person_off),
                  _railButton('tracking', 'Tracking', Icons.my_location),
                  _railButton('beats', 'Beat sync', Icons.graphic_eq),
                  _railButton('grading', 'Grading/LUTs', Icons.tune),
                  _railButton('live', 'Live Studio', Icons.live_tv),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Label + value slider row for the Pro tools panel.
class _ProSlider extends StatelessWidget {
  const _ProSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.digits = 2,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;
  final int digits;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value.toStringAsFixed(digits)),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// One step of the combined animated-overlay pass: the rendered PNG,
/// whether keyframes replace its preset animation, and the motion
/// title spec (null for the tracked sticker, which uses the track).
class _OverlayStep {
  _OverlayStep({required this.png, required this.keyframed, this.title});
  final File png;
  final bool keyframed;
  final ProMotionTitle? title;
}
