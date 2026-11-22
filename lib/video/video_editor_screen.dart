/// Video editor screen (CapCut-style core): pick clips, trim each clip,
/// merge, text overlay, music, speed, filters, aspect ratio, crossfade.
///
/// Processing is done by [FfmpegService]; this screen only builds the UI
/// state and the command pipeline. All exports are real FFmpeg runs —
/// no mock buttons.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../app_config.dart';
import '../theme.dart';
import '../live/news_template.dart';
import '../live/live_studio_screen.dart';
import '../news/breaking_templates.dart';
import '../news/audio_tools_screen.dart';
import '../news/caption_translator_screen.dart';
import '../news/channel_preset.dart';
import '../news/news_project.dart';
import '../news/project_handoff.dart';
import '../services/coin_service.dart';
import '../services/photo_pipeline.dart';
import '../services/asset_download_service.dart';
import '../services/logo_loop_service.dart';
import '../live/parity_template.dart';
import '../services/unity_ads_service.dart';
import '../services/ffmpeg_service.dart';
import '../services/caption_service.dart';
import '../services/pro_editor.dart';
import '../services/fx_pack.dart';
import '../services/pro_vision.dart';
import '../services/reel_export_service.dart';
import '../services/video_export_service.dart';

part 'video_editor_panels.dart';

class VideoClip {
  VideoClip(this.file, this.duration, this.aspectRatio);
  final File file;
  final Duration duration;
  final double aspectRatio; // width / height, from the real video stream
  double trimStart = 0;
  double trimEnd = -1; // -1 = full duration
  double get effectiveEnd => trimEnd < 0 ? duration.inMilliseconds / 1000 : trimEnd;
  double get effectiveDuration => effectiveEnd - trimStart;

  // v1.3.0 (§6.1): a still PHOTO can sit on the timeline as a clip.
  // It is materialised to a real video segment at export
  // (photoClipCommand); [kenBurns] adds the slow zoom.
  bool isPhoto = false;
  bool kenBurns = true;
  bool kbZoomIn = true;
}

class VideoEditorScreen extends StatefulWidget {
  /// Plain editor: opens empty, clips come from the gallery picker.
  ///
  /// Timeline handoff (Phase 7): when [project] is given, the editor
  /// opens WITH that News Maker project loaded — clips + voiceover +
  /// template + ticker + captions, resolved by [buildHandoff] (see
  /// `lib/news/project_handoff.dart`) — instead of dropping it. [preset]
  /// is the project's channel preset (chroma / PIP / logo settings).
  const VideoEditorScreen({super.key, this.project, this.preset});

  final NewsProject? project;
  final ChannelPreset? preset;

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
  // Music track gain (1.0 = unchanged); applied to the music audio only.
  double _musicVolume = 1.0;
  String? _fontFile;
  List<CaptionSegment> _captions = [];
  String _captionLocale = 'ur';
  bool _transcribing = false;
  CaptionStyle _captionStyle = CaptionStyle.standard;
  bool _captionDrawtextFallback = false;
  // CapCut-style UI state: which single-row tool rail item is open.
  // The panel above the rail shows only this tool's controls; every
  // tool from the old screen is reachable through the rail.
  // CapCut-style tool selection (Jaani 31 Oct 2026): null = tool grid
  // visible, no panel open. Non-null = that tool's panel open, grid hidden.
  String? _activeTool;

  // ---- v1.3.0 layout/feature state (§3–§6). ----
  /// Sub-tab inside the open tool panel (null = the tool's first
  /// tab). Reset whenever the tool changes.
  String? _panelTab;
  /// §6.1 filter intensity 0..1 (1 = the long-standing full look).
  double _filterIntensity = 1;
  /// §6.2 hold-to-compare: while true the stage shows the RAW
  /// frame (no colour matrix).
  bool _comparing = false;
  /// §5A Colour›Adjust: which ONE grade slider is on screen.
  String _gradeSlider = 'LUT';
  /// §5A Overlay›Keyframes: 0 = Start keyframe page, 1 = End.
  int _kfPage = 0;
  /// §6.8 auto music ducking under the clip/voice audio.
  bool _autoDuck = false;
  /// §6.9 music volume keyframes: (timeSec, gain) points.
  final List<(double, double)> _volumePoints = [];
  /// §6.7 main-clip transform (defaults = identity).
  double _tfScale = 1;
  double _tfX = 0;
  double _tfY = 0;
  double _tfRot = 0;
  double _tfOpacity = 1;
  bool get _transformActive =>
      _tfScale != 1 || _tfX != 0 || _tfY != 0 || _tfRot != 0 || _tfOpacity != 1;
  /// §6.5 canvas fill: 'none' (crop), 'blur' or 'color'.
  String _canvasFill = 'none';
  String _canvasFillColor = 'black';
  /// §6.1 intro/outro attach slots (picked video files).
  String? _introClipPath;
  String? _outroClipPath;
  /// True once the AppBar quality pill set the export quality —
  /// [_export] then skips its dialog.
  bool _qualityPicked = false;
  /// §8: this session's AI-tools coin unlock (charged once).
  bool _aiCoinsPaid = false;
  /// §6.6 undo/redo snapshot stacks (see _pushHistory).
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  /// §6.10 custom speed-ramp point speeds (start / middle / end).
  double _rampStart = 1;
  double _rampMid = 0.5;
  double _rampEnd = 1;
  /// §6.11 PIP style state: opacity (1 = solid), blend mode, mask.
  /// Blend modes ARE offered since the completion fix (user order
  /// 22 Nov 2026): the export uses a masked-blend chain — the inset
  /// is blended against the base frame, then its own alpha (mask +
  /// opacity applied) alphamerge-limits the result to the inset's
  /// shape — so a mode never bleeds outside the PIP. The stage
  /// preview composites the inset in a saveLayer with the same
  /// [BlendMode]. Mask values: 'none' / 'circle' / 'rect' /
  /// 'roundrect' / 'heart' / 'star' / 'linear' / 'radial'; one
  /// dart:ui-rendered mask PNG drives BOTH the preview (ImageShader
  /// dstIn) and the export (alpha multiply), so they always match.
  double _pipOpacity = 1;
  String _pipBlend = 'normal';
  String _pipMask = 'none';
  double _pipMaskFeather = 0;
  bool _pipMaskInvert = false;
  // PIP live preview: a muted looping controller for the inset, so
  // blend/mask/opacity are visible on the stage before export.
  VideoPlayerController? _pipController;
  String _pipControllerPath = '';
  bool _pipControllerBusy = false;
  // Decoded preview mask (regenerated when the mask key changes).
  ui.Image? _pipMaskImage;
  String _pipMaskImageKey = '';
  bool _pipMaskImageBusy = false;
  // Status is a transient overlay chip on the stage (§3), not a
  // permanent line: it flashes for a few seconds per message.
  bool _statusVisible = false;
  Timer? _statusTimer;

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
  // One-build: the video grading panel had NO brightness/exposure
  // (proposal S5.2) — added through ProGrade's eq gamma/brightness.
  double _proBrightness = 0;
  double _proExposure = 0;

  // Keyframes animate the motion title/sticker overlay (title first
  // if both are set). Times are 0 and the export duration.
  bool _proKeyframes = false;
  // Keyframe motion curve (linear = the long-standing constant-speed
  // motion; the ease presets reshape the FFmpeg interpolation).
  KeyframeEasing _kfEasing = KeyframeEasing.linear;
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
  double _proChromaSimilarity = 0.3;
  double _proChromaBlend = 0.1;
  String _proChromaBgKind = 'color';
  String _proChromaBgColor = '#00FF00';
  String? _proChromaBgImage;
  // One-build chroma upgrades (addendum B.3): spill (despill),
  // edge (alpha erode/dilate) and the live keyed-frame preview.
  double _proChromaSpill = 0;
  double _proChromaEdge = 0;
  String? _chromaPreviewPath;
  bool _chromaPreviewBusy = false;
  Timer? _chromaPreviewTimer;

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

  VoiceFx _fxVoice = VoiceFx.none;
  double _fxFadeIn = 0.0;
  double _fxFadeOut = 0.0;
  bool _muteOriginal = false;
  bool _fxReverse = false;
  bool _fxSilenceRemove = false;
  bool _fxPip = false;
  String _fxPipVideo = '';
  // PIP inset position/scale — defaults are the long-standing
  // hardcoded values; a timeline handoff replaces them with the
  // channel preset's settings (Phase 7).
  PipPosition _pipPosition = PipPosition.bottomRight;
  double _pipScale = 0.3;
  ShakeFx _fxShake = ShakeFx.none;
  int _fxQuality = 0;

  // ---- Timeline handoff state (Phase 7). Set once in [_loadProject]
  // when the screen was opened with a NewsProject; null in the plain
  // editor. ----
  NewsProject? _handoffProject;
  ChannelPreset? _handoffPreset;
  String? _projectVoiceoverPath;
  String? _projectTemplateKind;
  bool _projectLoading = false;
  // Handoff captions are already timeline-relative (0-based over the
  // whole reel) — [_adjustedCaptions] must NOT re-offset them. The
  // editor's own caption tools (transcribe / edit) record per-clip
  // segments and reset this flag.
  bool _captionsTimelineRelative = false;

  bool get _gradeActive =>
      _proLut.isNotEmpty ||
      _proTemperature != 0 ||
      _proTint != 0 ||
      _proSaturation != 1 ||
      _proVibrance != 1 ||
      _proContrast != 1 ||
      _proShadows != 0 ||
      _proHighlights != 0 ||
      _proBrightness != 0 ||
      _proExposure != 0;

  RampPreset? _rampPreset() => switch (_proRamp) {
        'slowMiddle' => RampPreset.slowMiddle,
        'slowStart' => RampPreset.slowStart,
        'slowEnd' => RampPreset.slowEnd,
        'pulse' => RampPreset.pulse,
        _ => null,
      };

  /// v1.3.0 (§8): premium ML tools unlock with COINS ONLY — the
  /// ad-unlock path is gone from the whole app. The first AI use
  /// in a session asks once: a confirm dialog shows the cost
  /// (CoinFeature.aiEnhance = 50) and the current balance, then
  /// [CoinService.spend] charges it. Admins are waived by
  /// CoinService itself. Later AI uses in the same session proceed
  /// without asking again. A failed/insufficient spend keeps the
  /// tool OFF and says why — never a silent pass.
  Future<bool> _ensurePremiumUnlocked() async {
    if (_aiCoinsPaid || CoinService.instance.isAdminNow) return true;
    final cost = CoinCosts.costFor(CoinFeature.aiEnhance);
    final balance = CoinService.instance.balance.value;
    if (!mounted) return false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Premium AI tools'),
        content: Text(
          'AI tools (background remover, motion tracking) is session '
          'mein $cost coins se unlock honge.\n'
          'Aap ka balance: $balance coins.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Unlock — $cost coins'),
          ),
        ],
      ),
    );
    if (confirm != true) return false;
    final res = await CoinService.instance.spend(CoinFeature.aiEnhance);
    if (res.ok) {
      _aiCoinsPaid = true;
      _setStatus(
        res.adminFree
            ? 'Admin — AI tools free unlock ho gaye.'
            : 'AI tools unlock ho gaye ($cost coins).',
      );
      return true;
    }
    _setStatus(
      res.error == 'insufficient_balance'
          ? 'Coins kam hain — Coins section se rewarded ads dekh kar '
              'coins kamayein.'
          : 'Unlock nahi hua (${res.error ?? 'error'}). Dobara try karein.',
    );
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

  /// Snapshot (CapCut/VN-style): save the preview playhead frame of the
  /// selected clip as a PNG photo into the gallery. A local FFmpeg frame
  /// extract — it does not touch the export pipeline or the clip list.
  Future<void> _saveFrameSnapshot() async {
    if (_clips.isEmpty || _busy) {
      return;
    }
    final VideoPlayerController? ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      _setStatus('Pehle clip ka preview load honay dein.');
      return;
    }
    final int idx = _selected < _clips.length ? _selected : 0;
    final VideoClip clip = _clips[idx];
    final double posSec = ctrl.value.position.inMilliseconds / 1000.0;
    final double seekSec =
        posSec.clamp(0.0, clip.duration.inMilliseconds / 1000.0);
    setState(() {
      _busy = true;
      _status = 'Frame save ho raha hai…';
    });
    try {
      final Directory dir = await _workDir();
      final int stamp = DateTime.now().millisecondsSinceEpoch;
      final String out = p.join(dir.path, 'frame_$stamp.png');
      final FfmpegResult r = await FfmpegService.run(
        '-ss $seekSec -i ${FfmpegService.q(clip.file.path)} '
        '-frames:v 1 -q:v 2 -y ${FfmpegService.q(out)}',
      );
      if (!r.ok) {
        _setStatus('Frame save failed. ${r.logs}');
        return;
      }
      await Gal.putImage(out);
      _setStatus('Frame photo gallery mein save ho gaya.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Frame saved to gallery.')),
        );
      }
    } catch (e) {
      _setStatus('Frame save failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Extract audio (VN-style): save the selected clip's trimmed audio as
  /// an .m4a file and open it, so the video's sound can be reused as a
  /// music track elsewhere.
  Future<void> _extractClipAudio() async {
    if (_clips.isEmpty || _busy) {
      return;
    }
    final int idx = _selected < _clips.length ? _selected : 0;
    final VideoClip clip = _clips[idx];
    setState(() {
      _busy = true;
      _status = 'Audio extract ho raha hai…';
    });
    try {
      final Directory dir = await _workDir();
      final int stamp = DateTime.now().millisecondsSinceEpoch;
      final String out = p.join(dir.path, 'clip_audio_$stamp.m4a');
      final FfmpegResult r = await FfmpegService.run(
        '-ss ${clip.trimStart} -t ${clip.effectiveDuration} '
        '-i ${FfmpegService.q(clip.file.path)} -vn -c:a aac -b:a 128k '
        '-y ${FfmpegService.q(out)}',
      );
      if (!r.ok) {
        _setStatus('Audio extract failed. ${r.logs}');
        return;
      }
      _setStatus('Audio extract ho gaya.');
      await OpenFilex.open(out);
    } catch (e) {
      _setStatus('Audio extract failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
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
    // setting can change the real frame size. Aligned with the
    // Export quality setting so keyframed/title positions stay
    // proportional at 1080p and 4K.
    final portrait =
        _clips.isEmpty ? true : _clips.first.aspectRatio < 1.0;
    final int videoW;
    final int videoH;
    if (_fxQuality == 2) {
      videoW = portrait ? 2160 : 3840;
      videoH = portrait ? 3840 : 2160;
    } else if (_fxQuality == 1) {
      videoW = portrait ? 1080 : 1920;
      videoH = portrait ? 1920 : 1080;
    } else {
      videoW = portrait ? 720 : 1280;
      videoH = portrait ? 1280 : 720;
    }
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
            easing: _kfEasing,
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
    // Plain editor only: a handoff project brings its own template
    // ([_loadProject] below) — the saved live template must NOT
    // overwrite it when this future resolves.
    NewsTemplate.load().then((t) {
      if (mounted && widget.project == null) setState(() => _news = t);
    });
    if (widget.project != null) {
      _loadProject(widget.project!, widget.preset);
    }
  }

  /// Timeline handoff (Phase 7): loads [project] into the editor —
  /// clips (probed for duration/aspect like the gallery picker does),
  /// voiceover, template + ticker, captions, and the preset's chroma
  /// + PIP settings. Missing clip files are reported in the status
  /// line, never silently dropped. A failure here never crashes the
  /// screen: the editor stays usable as a plain editor.
  Future<void> _loadProject(
    NewsProject project,
    ChannelPreset? preset,
  ) async {
    final handoff = buildHandoff(project: project, preset: preset);
    setState(() {
      _projectLoading = true;
      _handoffProject = project;
      _handoffPreset = preset;
      _projectTemplateKind = handoff.templateKind;
      _projectVoiceoverPath = handoff.voiceoverPath;
      _captions = handoff.captions;
      _captionsTimelineRelative = handoff.captions.isNotEmpty;
      _news = handoff.template;
      _newsEnabled = true;
      _fxPip = handoff.pipEnabled;
      _pipPosition = handoff.pipPosition;
      _pipScale = handoff.pipScale;
      if (handoff.chroma != null) {
        _proChroma = true;
        _proChromaSimilarity = handoff.chroma!.similarity;
        _proChromaBlend = handoff.chroma!.blend;
        _proChromaBgKind = 'image';
        _proChromaBgImage = handoff.chroma!.backgroundImagePath;
      }
      _status = 'Project load ho raha hai…';
    });
    // Bundled chroma backdrop (newsroom / studio desk): materialise
    // the asset to a file, like the LUT loader does — FFmpeg cannot
    // read Flutter assets directly.
    if (handoff.chromaBackgroundAsset != null) {
      try {
        final dir = await _workDir();
        final bgFile =
            await ensureLutFile(handoff.chromaBackgroundAsset!, dir);
        if (mounted) {
          setState(() => _proChromaBgImage = bgFile.path);
        }
      } catch (e) {
        if (mounted) {
          // Asset unreadable: fall back to the solid-colour
          // background so the chroma pass still runs (as the status
          // note below says) instead of referencing a missing [1:v].
          setState(() {
            _proChromaBgKind = 'color';
            _proChromaBgImage = null;
            _status =
                'Note: chroma background load nahi hua, solid background use hoga.';
          });
        }
      }
    }
    // Load the clips (same probe as the gallery picker: real duration
    // + aspect from the video stream).
    var loaded = 0;
    for (final path in handoff.clipPaths) {
      final file = File(path);
      final probe = VideoPlayerController.file(file);
      try {
        await probe.initialize();
        final d = probe.value.duration;
        final aspect = probe.value.aspectRatio;
        await probe.dispose();
        if (!mounted) return;
        setState(() {
          _clips.add(VideoClip(file, d, aspect));
          loaded++;
        });
      } catch (e) {
        await probe.dispose();
      }
    }
    if (!mounted) return;
    setState(() {
      _projectLoading = false;
      final dropped = handoff.droppedClipPaths;
      _status = 'Project loaded: $loaded clip(s)'
          '${handoff.voiceoverPath == null ? '' : ' • voiceover tayyar'}'
          '${dropped.isEmpty ? '' : ' • ${dropped.length} clip file(s) nahi mili'}';
    });
    if (_clips.isNotEmpty) await _loadPreview();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _pipController?.dispose();
    super.dispose();
  }

  /// Display title for the handoff banner (project title, else
  /// headline, else 'Untitled').
  String _projectTitle() {
    final p = _handoffProject;
    if (p == null) return 'Untitled';
    if (p.title.trim().isNotEmpty) return p.title.trim();
    if (p.headline.trim().isNotEmpty) return p.headline.trim();
    return 'Untitled';
  }

  Future<void> _loadPreview() async {
    if (_clips.isEmpty) return;
    // v1.3.0 (§6.1): a photo clip has no video controller — the
    // stage shows the still image instead.
    if (_clips[_selected].isPhoto) {
      final old = _controller;
      setState(() => _controller = null);
      await old?.dispose();
      return;
    }
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
      _pushHistory();
      setState(() {
        _clips.add(VideoClip(file, d, aspect));
        _selected = _clips.length - 1;
        _status = 'Clip ${_clips.length} added (${d.inSeconds}s).';
      });
      _flashStatus();
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

  void _setStatus(String s) {
    setState(() => _status = s);
    _flashStatus();
  }

  /// Shows the status chip (stage overlay) and arms its auto-hide.
  /// While an export runs the chip stays (progress lives there).
  void _flashStatus() {
    if (!mounted) return;
    setState(() => _statusVisible = true);
    _statusTimer?.cancel();
    _statusTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_busy) setState(() => _statusVisible = false);
    });
  }

  // ---- §6.6 undo/redo -------------------------------------------------
  // A snapshot is the whole editable project state as JSON: clip
  // files + trims + the global look/audio scalars. Pushed BEFORE
  // structural mutations (add / remove / split / trim-end / freeze
  // / photo-add); undo restores the exact prior state.
  String _snapshot() => jsonEncode({
        'clips': [
          for (final c in _clips)
            {
              'path': c.file.path,
              'durMs': c.duration.inMilliseconds,
              'ar': c.aspectRatio,
              'ts': c.trimStart,
              'te': c.trimEnd,
              'photo': c.isPhoto,
              'kb': c.kenBurns,
              'kbin': c.kbZoomIn,
            },
        ],
        'sel': _selected,
        'speed': _speed,
        'filter': _filter,
        'aspect': _aspect,
        'crossfade': _crossfade,
        'music': _musicPath,
        'musicVol': _musicVolume,
        'text': _text,
      });

  void _pushHistory() {
    _undoStack.add(_snapshot());
    if (_undoStack.length > 40) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  Future<void> _restoreSnapshot(String snap) async {
    final m = jsonDecode(snap) as Map<String, dynamic>;
    final clips = <VideoClip>[];
    for (final e in (m['clips'] as List).cast<Map<String, dynamic>>()) {
      final c = VideoClip(
        File(e['path'] as String),
        Duration(milliseconds: (e['durMs'] as num).toInt()),
        (e['ar'] as num).toDouble(),
      );
      c.trimStart = (e['ts'] as num).toDouble();
      c.trimEnd = (e['te'] as num).toDouble();
      c.isPhoto = e['photo'] as bool? ?? false;
      c.kenBurns = e['kb'] as bool? ?? true;
      c.kbZoomIn = e['kbin'] as bool? ?? true;
      clips.add(c);
    }
    setState(() {
      _clips
        ..clear()
        ..addAll(clips);
      _selected = ((m['sel'] as num?)?.toInt() ?? 0)
          .clamp(0, clips.isEmpty ? 0 : clips.length - 1);
      _speed = (m['speed'] as num?)?.toDouble() ?? 1;
      _filter = m['filter'] as String? ?? 'Normal';
      _aspect = m['aspect'] as String? ?? 'Original';
      _crossfade = m['crossfade'] as bool? ?? false;
      _musicPath = m['music'] as String?;
      _musicVolume = (m['musicVol'] as num?)?.toDouble() ?? 1;
      _text = m['text'] as String? ?? '';
    });
    if (_clips.isNotEmpty) {
      await _loadPreview();
    } else {
      await _controller?.dispose();
      if (mounted) setState(() => _controller = null);
    }
  }

  Future<void> _undo() async {
    if (_undoStack.isEmpty || _busy) return;
    _redoStack.add(_snapshot());
    await _restoreSnapshot(_undoStack.removeLast());
    _setStatus('Undo ho gaya.');
  }

  Future<void> _redo() async {
    if (_redoStack.isEmpty || _busy) return;
    _undoStack.add(_snapshot());
    await _restoreSnapshot(_redoStack.removeLast());
    _setStatus('Redo ho gaya.');
  }

  /// Opens a tool panel (or closes it when [key] is null); the
  /// panel always starts on its first sub-tab (§3).
  void _openTool(String? key) {
    setState(() {
      _activeTool = key;
      _panelTab = null;
    });
  }

  /// The stage's LIVE colour matrix (§3/§6.1/§6.2): the chosen
  /// filter at [_filterIntensity] plus the ProGrade values the
  /// matrix can express (LUTs are file-based and export-only —
  /// the preview says so in the Colour panel). Hold-to-compare
  /// swaps in the identity matrix.
  List<double> get _stageMatrix {
    if (_comparing) {
      return const [
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, 1, 0,
      ];
    }
    final filter = switch (_filter) {
      'Warm' => PhotoFilter.warm,
      'Cool' => PhotoFilter.cool,
      'B&W' => PhotoFilter.blackWhite,
      'Vivid' => PhotoFilter.vivid,
      'Sepia' => PhotoFilter.sepia,
      _ => PhotoFilter.normal,
    };
    return buildColorMatrix(
      filter: filter,
      brightness: _proBrightness,
      contrast: _proContrast,
      saturation: _proSaturation,
      filterIntensity: _filterIntensity,
      exposure: _proExposure,
      temperature: _proTemperature,
      tint: _proTint,
      vibrance: (_proVibrance - 1) * 100,
    );
  }

  /// AppBar quality pill (§3): pick the export quality ahead of
  /// time; [_export] then skips its dialog.
  Future<void> _pickExportQuality() async {
    final quality = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Export quality'),
        children: [
          for (final entry in const [
            (0, '720p HD (fast)'),
            (1, '1080p Full HD'),
            (2, '2160p 4K (slow)'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, entry.$1),
              child: Text(entry.$2),
            ),
        ],
      ),
    );
    if (quality == null) return;
    setState(() {
      _fxQuality = quality;
      _qualityPicked = true;
    });
    _setStatus(
      'Export quality: ${const ['720p', '1080p', '4K'][quality]} set ho gayi.',
    );
  }

  String get _qualityLabel =>
      const ['720p', '1080p', '4K'][_fxQuality.clamp(0, 2)];

  /// §6.1 — add a PHOTO as a timeline clip (3 s default, Ken Burns
  /// on). The photo is materialised to a video segment at export.
  Future<void> _addPhotoClip() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final file = File(picked.path);
    var aspect = 16 / 9;
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      aspect = frame.image.width / frame.image.height;
      frame.image.dispose();
    } catch (_) {}
    _pushHistory();
    final clip = VideoClip(file, const Duration(seconds: 3), aspect)
      ..isPhoto = true;
    setState(() {
      _clips.add(clip);
      _selected = _clips.length - 1;
      _status = 'Photo clip add ho gaya (3s, Ken Burns on).';
    });
    _flashStatus();
    await _loadPreview();
  }

  /// §6.3 — freeze-frame insert: the current playhead frame becomes
  /// a 2 s photo clip right after the selected clip.
  Future<void> _freezeFrameInsert() async {
    if (_clips.isEmpty || _busy) return;
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      _setStatus('Pehle clip ka preview load honay dein.');
      return;
    }
    final idx = _selected < _clips.length ? _selected : 0;
    final clip = _clips[idx];
    final posSec = ctrl.value.position.inMilliseconds / 1000.0;
    final seekSec = posSec.clamp(0.0, clip.duration.inMilliseconds / 1000.0);
    setState(() => _busy = true);
    try {
      final dir = await _workDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final out = p.join(dir.path, 'freeze_$stamp.png');
      final r = await FfmpegService.run(
        '-ss $seekSec -i ${FfmpegService.q(clip.file.path)} '
        '-frames:v 1 -q:v 2 -y ${FfmpegService.q(out)}',
      );
      if (!r.ok) {
        _setStatus('Freeze frame nahi bana. ${r.logs}');
        return;
      }
      _pushHistory();
      final frozen = VideoClip(
        File(out),
        const Duration(seconds: 2),
        clip.aspectRatio,
      )..isPhoto = true;
      setState(() {
        _clips.insert(idx + 1, frozen);
        _selected = idx + 1;
      });
      _setStatus('Freeze frame clip ban gaya (2s).');
      await _loadPreview();
    } catch (e) {
      _setStatus('Freeze frame failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Fullscreen preview (transport row): the same controller in a
  /// full-screen dialog, with the live colour matrix applied.
  Future<void> _openFullscreen() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: ColorFiltered(
                colorFilter: ColorFilter.matrix(_stageMatrix),
                child: AspectRatio(
                  aspectRatio: ctrl.value.aspectRatio,
                  child: VideoPlayer(ctrl),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<Directory> _workDir() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory(p.join(tmp.path, 'pve_video'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _exportInner() async {
    try {
      final dir = await _workDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      var out = p.join(dir.path, 'pve_export_$stamp.mp4');
      if (_clips.isNotEmpty) {
        final int idx = _selected < _clips.length ? _selected : 0;
        VideoClip clip = _clips[idx];
        if (_fxReverse) {
          final String revOut = p.join(dir.path, 'fx_rev_$stamp.mp4');
          final FfmpegResult r = await FfmpegService.run(
            reverseCommand(input: clip.file.path, output: revOut),
          );
          if (r.ok) {
            final VideoClip nc =
                VideoClip(File(revOut), clip.duration, clip.aspectRatio);
            nc.trimStart = clip.trimStart;
            nc.trimEnd = clip.trimEnd;
            _clips[idx] = nc;
          }
        }
        if (_fxSilenceRemove) {
          final String silOut = p.join(dir.path, 'fx_sil_$stamp.mp4');
          final VideoClip cur = _clips[idx];
          final FfmpegResult r = await FfmpegService.run(
            silenceRemoveCommand(input: cur.file.path, output: silOut),
          );
          if (r.ok) {
            _clips[idx] =
                VideoClip(File(silOut), cur.duration, cur.aspectRatio);
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
      // v1.3.0 (§6.1): photo clips are materialised to real video
      // segments first (Ken Burns zoom or a static hold), so every
      // later stage sees ordinary video clips.
      var hadPhoto = false;
      if (clips.any((c) => c.isPhoto)) {
        hadPhoto = true;
        final mat = <VideoClip>[];
        for (var i = 0; i < clips.length; i++) {
          final c = clips[i];
          if (!c.isPhoto) {
            mat.add(c);
            continue;
          }
          final portraitP = c.aspectRatio < 1.0;
          final pw = _fxQuality == 2
              ? (portraitP ? 2160 : 3840)
              : _fxQuality == 1
                  ? (portraitP ? 1080 : 1920)
                  : (portraitP ? 720 : 1280);
          final ph = _fxQuality == 2
              ? (portraitP ? 3840 : 2160)
              : _fxQuality == 1
                  ? (portraitP ? 1920 : 1080)
                  : (portraitP ? 1280 : 720);
          final seg = p.join(dir.path, 'photo_${stamp}_$i.mp4');
          _setStatus('Photo clip ${i + 1} tayyar ho raha hai…');
          final res = await FfmpegService.run(
            FfmpegService.photoClipCommand(
              imagePath: c.file.path,
              output: seg,
              width: pw,
              height: ph,
              durationSec: c.effectiveDuration,
              kenBurns: c.kenBurns,
              zoomIn: c.kbZoomIn,
            ),
          );
          if (!res.ok) {
            throw Exception('Photo clip ${i + 1} failed. ${res.logs}');
          }
          mat.add(VideoClip(File(seg), c.duration, c.aspectRatio));
        }
        clips = mat;
      }
      if (_beatAutoCut && _beats.isNotEmpty && _clips.length == 1 && !hadPhoto) {
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
                brightness: _proBrightness,
                exposure: _proExposure,
              ),
              lutFilePath: lutPath,
            )
          : '';
      final rampPreset = _rampPreset();
      final exportDurSec =
          clips.fold<double>(0.0, (a, c) => a + c.effectiveDuration);
      // v1.3.0 (§6.10): the 'Custom' ramp builds its segments from
      // the three point speeds (start / middle / end thirds).
      final customRamp = _proRamp == 'Custom' && exportDurSec > 0;
      final hasRamp = rampPreset != null || customRamp;
      final rampSegs = rampPreset != null
          ? rampSegments(rampPreset, exportDurSec)
          : customRamp
              ? <RampSegment>[
                  RampSegment(
                      tStart: 0, tEnd: exportDurSec / 3, speed: _rampStart),
                  RampSegment(
                      tStart: exportDurSec / 3,
                      tEnd: exportDurSec * 2 / 3,
                      speed: _rampMid),
                  RampSegment(
                      tStart: exportDurSec * 2 / 3,
                      tEnd: exportDurSec,
                      speed: _rampEnd),
                ]
              : <RampSegment>[];
      final List<String> extraParts = <String>[];
      if (gradeStr.isNotEmpty) extraParts.add(gradeStr);
      if (hasRamp) extraParts.add(rampSetpts(rampSegs));
      final String shakeStr = shakeFilter(_fxShake);
      if (shakeStr.isNotEmpty) extraParts.add(shakeStr);
      final String? extraVideoFilter =
          extraParts.isEmpty ? null : extraParts.join(',');
      // Ramp replaces the fixed speed: the video timing comes from the
      // ramp setpts, and the audio filter from the ramp (music exports
      // keep the music track untouched, so the ramp audio filter only
      // applies when no music is picked).
      final effectiveSpeed = hasRamp ? 1.0 : _speed;
      // v1.3.0 (§6.8): auto-duck keeps the music OUT of the main
      // pass — a post-pass sidechain-ducks it under the clip audio.
      final duckMusic = _autoDuck && _musicPath != null;
      final String? mainMusicPath = duckMusic ? null : _musicPath;
      final String? rampAudio =
          (hasRamp && mainMusicPath == null) ? rampAudioFilter(rampSegs) : null;
      final String voiceStr = voiceFxFilter(_fxVoice);
      final String fadeStr = audioFadeFilter(
        fadeInSec: _fxFadeIn,
        fadeOutSec: _fxFadeOut,
        durationSec: exportDurSec,
      );
      String fxAudioFilter = '';
      if (voiceStr.isNotEmpty) {
        fxAudioFilter = voiceStr;
      }
      if (fadeStr.isNotEmpty) {
        if (fxAudioFilter.isNotEmpty) {
          fxAudioFilter = '$fxAudioFilter,$fadeStr';
        } else {
          fxAudioFilter = fadeStr;
        }
      }
      String? finalAudioFilter;
      final bool isComplex =
          rampAudio != null && rampAudio.contains('[0:a]');
      if (isComplex) {
        finalAudioFilter = rampAudio;
      } else {
        final List<String> afParts = <String>[];
        // Mute original audio (CapCut/VN-style): silence the clip's own
        // audio at export. Ignored when music is picked — music already
        // replaces the clip audio track.
        if (_muteOriginal && mainMusicPath == null) {
          afParts.add('volume=0');
        }
        if (effectiveSpeed != 1.0 && mainMusicPath == null) {
          afParts.add('atempo=$effectiveSpeed');
        }
        if (fxAudioFilter.isNotEmpty) {
          afParts.add(fxAudioFilter);
        }
        // Music track gain: with music picked, the output audio stream is
        // the music track, so volume= here adjusts music only.
        if (mainMusicPath != null && _volumePoints.isNotEmpty) {
          // v1.3.0 (§6.9): music volume keyframes — a piecewise
          // linear gain envelope over the music track.
          afParts.add(
            "volume='${FfmpegService.volumeEnvelopeExpression(_volumePoints, _musicVolume)}':eval=frame",
          );
        } else if (mainMusicPath != null && _musicVolume != 1.0) {
          afParts.add('volume=${_musicVolume.toStringAsFixed(2)}');
        }
        if (afParts.isNotEmpty) {
          finalAudioFilter = afParts.join(',');
        }
      }

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
          // §6.5 blur fill: the main pass keeps the original frame;
          // a post-pass reframes it over its own blurred copy.
          aspect: _canvasFill == 'blur' ? 'Original' : _aspect,
          text: text,
          fontFile: _fontFile,
          subtitlesPath: subsPath,
          captionFilter: capFilter,
          textAtTop: useCaptions,
          musicPath: mainMusicPath,
          extraVideoFilter: extraVideoFilter,
          audioFilter: finalAudioFilter,
          exportQuality: _fxQuality,
          filterIntensity: _filterIntensity,
          canvasFill: _canvasFill == 'color' ? 'color' : 'none',
          fillColor: _canvasFillColor,
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
            aspect: _canvasFill == 'blur' ? 'Original' : _aspect,
            text: text,
            fontFile: _fontFile,
            subtitlesPath: subsPath,
            captionFilter: capFilter,
            textAtTop: useCaptions,
            musicPath: mainMusicPath,
            extraVideoFilter: gradeStr.isEmpty ? null : gradeStr,
            audioFilter: null,
            exportQuality: _fxQuality,
            filterIntensity: _filterIntensity,
            canvasFill: _canvasFill == 'color' ? 'color' : 'none',
            fillColor: _canvasFillColor,
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
        final bool portrait = clips.first.aspectRatio < 1.0;
        int w;
        int h;
        if (_fxQuality == 2) {
          // 2160p 4K (slow): 2026 baseline export; needs more time on
          // low-end phones — the dropdown label says so.
          w = portrait ? 2160 : 3840;
          h = portrait ? 3840 : 2160;
        } else if (_fxQuality == 1) {
          w = portrait ? 1080 : 1920;
          h = portrait ? 1920 : 1080;
        } else {
          w = portrait ? 720 : 1280;
          h = portrait ? 1280 : 720;
        }
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
            // §6.5: blur fill frames every clip over its own
            // blurred copy instead of cropping.
            blurFill: _canvasFill == 'blur',
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
          // Blur fill already framed the clips in normalize.
          aspect: _canvasFill == 'blur' ? 'Original' : _aspect,
          text: text,
          fontFile: _fontFile,
          subtitlesPath: subsPath,
          captionFilter: capFilter,
          textAtTop: useCaptions,
          musicPath: mainMusicPath,
          extraVideoFilter: extraVideoFilter,
          audioFilter: finalAudioFilter,
          exportQuality: _fxQuality,
          filterIntensity: _filterIntensity,
          canvasFill: _canvasFill == 'color' ? 'color' : 'none',
          fillColor: _canvasFillColor,
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
            aspect: _canvasFill == 'blur' ? 'Original' : _aspect,
            text: text,
            fontFile: _fontFile,
            subtitlesPath: subsPath,
            captionFilter: capFilter,
            textAtTop: useCaptions,
            musicPath: mainMusicPath,
            extraVideoFilter: gradeStr.isEmpty ? null : gradeStr,
            audioFilter: null,
            exportQuality: _fxQuality,
            filterIntensity: _filterIntensity,
            canvasFill: _canvasFill == 'color' ? 'color' : 'none',
            fillColor: _canvasFillColor,
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

      // v1.3.0 (§6.5): blur-fill reframe for the SINGLE-clip path
      // (the main pass ran with aspect 'Original'). Guarded like
      // every post-pass.
      if (clips.length == 1 && _canvasFill == 'blur' && _aspect != 'Original') {
        try {
          final dims = FfmpegService.exportDims(_aspect, _fxQuality);
          if (dims != null) {
            _setStatus('Canvas blur fill lag raha hai…');
            final bfOut = p.join(dir.path, 'pve_export_blurfill_$stamp.mp4');
            final res = await FfmpegService.run(
              FfmpegService.blurFillPassCommand(
                input: out,
                output: bfOut,
                width: dims.$1,
                height: dims.$2,
              ),
            );
            if (res.ok) {
              out = bfOut;
            } else {
              _setStatus(
                'Note: blur fill fail ho gaya, baghair is ke save ho raha hai.',
              );
            }
          }
        } catch (e) {
          _setStatus(
            'Note: blur fill fail ho gaya ($e), baghair is ke save ho raha hai.',
          );
        }
      }

      // v1.3.0 (§6.8): auto music ducking — the music was kept out
      // of the main pass; here it is sidechain-ducked under the
      // clip's own audio (or becomes the track when there is none).
      if (duckMusic) {
        try {
          _setStatus('Music ducking ho raha hai…');
          final hasAudio = await ReelExportService.probeHasAudio(File(out));
          final duckOut = p.join(dir.path, 'pve_export_duck_$stamp.mp4');
          final res = await FfmpegService.run(
            FfmpegService.musicDuckCommand(
              input: out,
              musicPath: _musicPath!,
              output: duckOut,
              hasClipAudio: hasAudio,
              musicVolume: _musicVolume,
            ),
          );
          if (res.ok) {
            out = duckOut;
          } else {
            _setStatus(
              'Note: music ducking fail ho gaya, baghair music ke save ho raha hai.',
            );
          }
        } catch (e) {
          _setStatus(
            'Note: music ducking fail ho gaya ($e), baghair music ke save ho raha hai.',
          );
        }
      }

      // Timeline handoff (Phase 7): voiceover mix. The project
      // voiceover (Gemini WAV) is mixed over the clip audio, ducked
      // so the voice stays on top; when the video has no audio track
      // the voiceover simply becomes the track. Guarded like the
      // other post-passes: a failure keeps the unmixed export.
      if (_projectVoiceoverPath != null &&
          await File(_projectVoiceoverPath!).exists()) {
        try {
          _setStatus('Voiceover mix ho raha hai…');
          final hasAudio = await ReelExportService.probeHasAudio(File(out));
          final mixOut = p.join(dir.path, 'pve_export_voicemix_$stamp.mp4');
          final res = await FfmpegService.run(
            FfmpegService.voiceoverMixCommand(
              input: out,
              voiceoverPath: _projectVoiceoverPath!,
              output: mixOut,
              hasClipAudio: hasAudio,
            ),
          );
          if (res.ok) {
            out = mixOut;
          } else {
            _setStatus(
              'Note: voiceover mix fail ho gaya, baghair voice ke save ho raha hai.',
            );
          }
        } catch (e) {
          _setStatus(
            'Note: voiceover mix fail ho gaya ($e), baghair voice ke save ho raha hai.',
          );
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
      // (a2) v1.3.0 (§6.7): main-clip transform (scale / position /
      // rotation / opacity over a blurred backdrop).
      if (_transformActive) {
        try {
          final size = await VideoExportService.probeVideoSize(File(out));
          if (size != null) {
            _setStatus('Transform lag raha hai…');
            final tfOut = p.join(dir.path, 'pve_export_transform_$stamp.mp4');
            final res = await FfmpegService.run(
              FfmpegService.transformPassCommand(
                input: out,
                output: tfOut,
                width: size.width,
                height: size.height,
                scale: _tfScale,
                posX: _tfX,
                posY: _tfY,
                rotationDeg: _tfRot,
                opacity: _tfOpacity,
              ),
            );
            if (res.ok) {
              out = tfOut;
            } else {
              _setStatus(
                'Note: transform fail ho gaya, baghair is ke save ho raha hai.',
              );
            }
          }
        } catch (e) {
          _setStatus(
            'Note: transform fail ho gaya ($e), baghair is ke save ho raha hai.',
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
            spill: _proChromaSpill,
            edge: _proChromaEdge,
            backgroundKind: _proChromaBgKind,
            backgroundColor: _proChromaBgColor,
            backgroundImagePath:
                _proChromaBgKind == 'image' ? _proChromaBgImage : null,
          );
          // ONE builder for the chroma graph (shared with the reel
          // export) — the Template Studio sensitivity + background and
          // the editor's own chroma controls apply through it.
          final cmd = chromaPassCommand(
            input: out,
            c: c,
            output: chromaOut,
          );
          final res = await FfmpegService.run(cmd);
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

      // PIP (Phase 7): the inset IS composited for real in the export
      // ([pipOverlayFilter]) at the preset's position/scale when
      // opened via timeline handoff. SPLIT SCREEN stays deferred:
      // it needs a second concurrent video track, but this timeline
      // is a single sequential clip list — there is no second input
      // to composite (see the reel export header for the full reason).
      if (_fxPip && _fxPipVideo.isNotEmpty) {
        final String pipOut = p.join(dir.path, 'pve_export_pip_$stamp.mp4');
        // PIP position/scale: the long-standing defaults, or the
        // channel preset's settings when opened via timeline handoff
        // (Phase 7) — the inset is composited for real, never a
        // preview-only effect.
        // v1.3.0 (§6.11): opacity + circle mask. Completion fix
        // (user order 22 Nov 2026): blend modes + the full mask set
        // (shapes / linear / radial, feather, invert) via the
        // masked-blend chain in [_pipSnippetAdvanced]. The untouched
        // default (Normal + no mask + full opacity) still takes the
        // original stock snippet, byte-for-byte.
        final bool pipStock = _pipBlend == 'normal' &&
            _pipMask == 'none' &&
            _pipOpacity >= 1;
        String snippet;
        String? pipMaskPath;
        if (pipStock) {
          snippet = pipOverlayFilter(
            pipLabel: '[1:v]',
            position: _pipPosition,
            pipScale: _pipScale,
            margin: 24,
            outLabel: '[vout]',
          );
        } else {
          final baseSize =
              await VideoExportService.probeVideoSize(File(out));
          final pipSize =
              await VideoExportService.probeVideoSize(File(_fxPipVideo));
          if (baseSize == null || pipSize == null) {
            // Guarded fallback (FX-pass contract): without probed
            // geometry the advanced graph cannot be built, so the
            // stock composite runs and the user is told.
            _setStatus(
              'Note: PIP blend/mask ke liye size nahi mila — '
              'simple PIP lag raha hai.',
            );
            snippet = pipOverlayFilter(
              pipLabel: '[1:v]',
              position: _pipPosition,
              pipScale: _pipScale,
              margin: 24,
              outLabel: '[vout]',
            );
          } else {
            if (_pipMask != 'none') {
              pipMaskPath = await _renderPipMaskPng(
                dir: dir,
                stamp: stamp,
                width: pipSize.width,
                height: pipSize.height,
              );
            }
            snippet = _pipSnippetAdvanced(
              base: baseSize,
              pip: pipSize,
              hasMask: pipMaskPath != null,
            );
          }
        }
        final StringBuffer pb = StringBuffer();
        pb.write('-y -i ');
        pb.write(FfmpegService.q(out));
        pb.write(' -i ');
        pb.write(FfmpegService.q(_fxPipVideo));
        if (pipMaskPath != null) {
          pb.write(' -loop 1 -i ');
          pb.write(FfmpegService.q(pipMaskPath));
        }
        pb.write(' -filter_complex "');
        pb.write(snippet);
        pb.write('" -map "[vout]" -map 0:a? -c:v libx264 -preset veryfast ');
        pb.write('-crf 23 -c:a copy -movflags +faststart ');
        pb.write(FfmpegService.q(pipOut));
        final FfmpegResult pr = await FfmpegService.run(pb.toString());
        if (pr.ok) {
          out = pipOut;
        }
      } else if (_fxPip) {
        // PIP on but no inset video picked: the pass is skipped and
        // the user is told — never a fake PIP claim.
        _setStatus(
          'Note: PIP video nahi chuna — PIP ke baghair save ho raha hai.',
        );
      }

      // v2 news template + logo second pass (before gallery save).
      // The template frame is rendered by the same dart:ui renderer
      // the live view uses, so Urdu shaping stays correct. If the
      // pass fails, the clean export is saved instead of failing.
      //
      // v1.3.0 (§9): a 'nigraanFinal' HANDOFF project takes the
      // ANIMATED parity pass instead (both ribbons scroll, rotating
      // logo + flipping clock capsule — parity_template.dart), with
      // the Kasheeda font gate: no font, no template (a loud status,
      // never a fallback-font lookalike). The plain editor's live
      // design keeps the static pass; its ticker/clock note in the
      // News panel was updated accordingly.
      if (_newsEnabled) {
        var parityDone = false;
        if (_projectTemplateKind == 'nigraanFinal' &&
            _handoffProject != null &&
            _handoffPreset != null) {
          final svc = const AssetDownloadService();
          final fontReady = await svc.ensureKasheedaFontReady(
            url: AppConfig.kasheedaFontUrl,
          );
          if (!fontReady) {
            _setStatus(
              'Kasheeda font nahi mila — Final template nahi laga, '
              'saaf video save ho rahi hai.',
            );
          } else {
            try {
              _setStatus('Final template (animated) lag raha hai…');
              final size =
                  await VideoExportService.probeVideoSize(File(out));
              if (size != null) {
                final effPreset = effectivePresetFor(
                  project: _handoffProject!,
                  preset: _handoffPreset!,
                );
                final assets = await renderParityAssets(
                  preset: effPreset,
                  dir: dir,
                  width: size.width,
                  height: size.height,
                  now: DateTime.now(),
                  fontReady: fontReady,
                );
                String? movPath;
                String? framesDir;
                String? stillPath;
                final mov = await svc.cachedLogoMov();
                if (mov != null) {
                  movPath = mov.path;
                } else if (_news.logoPath != null &&
                    await File(_news.logoPath!).exists()) {
                  // Logo parity (user spec 22 Nov 2026): a user-imported
                  // logo ROTATES in 3D exactly like the channel logo —
                  // generate its loop frames the same way the reel
                  // export does; the still is only a fallback.
                  try {
                    final key =
                        logoLoopCacheKey(logoFile: File(_news.logoPath!));
                    final dirFrames =
                        Directory(p.join(dir.path, 'logo_loop_$key'));
                    await LogoLoopService.generateFrames(
                      logoFile: File(_news.logoPath!),
                      outDir: dirFrames,
                    );
                    framesDir = dirFrames.path;
                  } catch (_) {
                    stillPath = _news.logoPath;
                  }
                }
                String? clockFont;
                final dejaVu = await svc.ensureDejaVuFile();
                clockFont = dejaVu?.path ?? FfmpegService.findFontFile();
                final parityOut =
                    p.join(dir.path, 'pve_export_parity_$stamp.mp4');
                final cmd = buildParityTemplateCommand(
                  input: out,
                  output: parityOut,
                  assets: assets,
                  logoMovPath: movPath,
                  logoFramesDir: framesDir,
                  logoStillPng: stillPath,
                  clockFontFile: clockFont,
                  exportStart: DateTime.now(),
                  videoBitrateKbps: null,
                );
                final res = await FfmpegService.run(cmd);
                if (res.ok) {
                  out = parityOut;
                  parityDone = true;
                } else {
                  _setStatus(
                    'Note: animated template fail ho gaya, static '
                    'template se try ho raha hai.',
                  );
                }
              }
            } catch (e) {
              _setStatus(
                'Note: animated template fail ho gaya ($e), static '
                'template se try ho raha hai.',
              );
            }
          }
        }
        if (!parityDone) {
          final useNews = _news.breakingHeadline.trim().isNotEmpty ||
              _news.lowerTitle.trim().isNotEmpty ||
              _news.lowerSubtitle.trim().isNotEmpty ||
              _news.tickerText.trim().isNotEmpty;
          String? templatePng;
          if (useNews) {
            _setStatus('News template laga rahe hain…');
            // Timeline handoff (Phase 7): render the PROJECT's template
            // kind (nigraanFinal / breaking / classic) from its preset
            // instead of the live design, with the logo left out of the
            // PNG (the static logo comes from the overlay pass below,
            // as before). The plain editor keeps the live render.
            final tplFile = await renderLiveTemplateImage(
              template: _news,
              tickerPx: 0,
              tickerAtStart: true,
              now: DateTime.now(),
              dir: dir,
              templateKind: _projectTemplateKind ?? 'live',
              preset: _handoffPreset,
              breakingTemplate: _projectTemplateKind == 'breaking' &&
                      _handoffProject != null &&
                      _handoffPreset != null
                  ? BreakingTemplate.fromProject(
                      _handoffProject!,
                      _handoffPreset!,
                    )
                  : null,
              includeLogo: _handoffPreset == null,
              includeIntroMarker: _handoffPreset == null,
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
      }

      // v1.3.0 (§6.1): intro / outro attach slots — the picked
      // videos are normalised to the export's own dims and joined
      // with the concat demuxer (intro first, outro last). Guarded:
      // a failed attach keeps the unattached export.
      if (_introClipPath != null || _outroClipPath != null) {
        try {
          final size = await VideoExportService.probeVideoSize(File(out));
          if (size != null) {
            final segments = <String>[];
            Future<String?> attach(String path, String tag) async {
              final hasAudio =
                  await ReelExportService.probeHasAudio(File(path));
              final norm = p.join(dir.path, 'attach_${tag}_$stamp.mp4');
              final res = await FfmpegService.run(
                FfmpegService.normalizeWithAudioCommand(
                  input: path,
                  trimStart: 0,
                  trimEnd: 3600,
                  width: size.width,
                  height: size.height,
                  output: norm,
                  addSilentAudio: !hasAudio,
                ),
              );
              return res.ok ? norm : null;
            }

            if (_introClipPath != null) {
              final n = await attach(_introClipPath!, 'intro');
              if (n != null) segments.add(n);
            }
            segments.add(out);
            if (_outroClipPath != null) {
              final n = await attach(_outroClipPath!, 'outro');
              if (n != null) segments.add(n);
            }
            if (segments.length > 1) {
              _setStatus('Intro/outro jor rahe hain…');
              final listFile = p.join(dir.path, 'attach_$stamp.txt');
              await File(listFile).writeAsString(
                segments
                    .map((f) => "file '${f.replaceAll("'", "'\\''")}'")
                    .join('\n'),
              );
              final joined = p.join(dir.path, 'pve_export_joined_$stamp.mp4');
              final res = await FfmpegService.run(
                FfmpegService.concatCommand(
                  listFile: listFile,
                  output: joined,
                ),
              );
              if (res.ok) {
                out = joined;
              } else {
                _setStatus(
                  'Note: intro/outro attach fail ho gaya, baghair is ke save ho raha hai.',
                );
              }
            }
          }
        } catch (e) {
          _setStatus(
            'Note: intro/outro attach fail ho gaya ($e), baghair is ke save ho raha hai.',
          );
        }
      }

      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) {
          throw Exception('Gallery access was denied.');
        }
      }
      await Gal.putVideo(out);
      _setStatus('Saved to gallery: ${p.basename(out)}');
      UnityAdsService.showInterstitialAd();
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
    // Export quality lives at the export step now (one-build): it
    // used to hide inside the old Filters panel; the user confirms
    // it here, CapCut-style, before the render starts. v1.3.0: when
    // the AppBar quality pill already set it, the dialog is skipped.
    final quality = _qualityPicked
        ? _fxQuality
        : await showDialog<int>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('Export quality'),
              children: [
                for (final entry in const [
                  (0, '720p HD (fast)'),
                  (1, '1080p Full HD'),
                  (2, '2160p 4K (slow)'),
                ])
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, entry.$1),
                    child: Text(entry.$2),
                  ),
              ],
            ),
          );
    if (quality == null || !mounted) return;
    _fxQuality = quality;
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

  /// §6.11 PIP advanced graph (completion fix, user order
  /// 22 Nov 2026): blend modes + masks + opacity, built on probed
  /// pixel geometry so every size is an exact integer.
  ///
  /// Alpha chain (shared): the scaled inset is split — one branch
  /// keeps its colour, the other gives its alpha (opacity applied
  /// via colorchannelmixer BEFORE alphaextract, as the old snippet
  /// did). When a mask PNG is input [2:v], the mask MULTIPLIES the
  /// alpha (blend multiply on two gray streams = a*b/255), so mask
  /// + feather + invert + opacity all compose into one final alpha.
  ///
  /// Normal mode: the final alpha is alphamerge'd back onto the
  /// inset and overlaid on the untouched base — the old alpha path,
  /// generalised from the geq circle to the mask PNG set.
  ///
  /// Blend modes: the base is CROPPED to the inset's rect and
  /// blended (gbrp) with the inset's colour; the blended crop is
  /// alphamerge'd with the SAME final alpha and overlaid back onto
  /// the untouched base at the same rect. Inside the alpha the
  /// blend shows; outside it the original frame survives — this is
  /// what ffmpeg's raw `blend` alone cannot do, because it has no
  /// notion of the overlay's alpha.
  String _pipSnippetAdvanced({
    required VideoSize base,
    required VideoSize pip,
    required bool hasMask,
  }) {
    const margin = 24;
    final s = _pipScale.clamp(0.15, 0.5);
    var pw = ((pip.width * s) / 2).floor() * 2;
    var ph = ((pip.height * s) / 2).floor() * 2;
    if (pw > base.width) pw = base.width - (base.width % 2);
    if (ph > base.height) ph = base.height - (base.height % 2);
    if (pw < 2) pw = 2;
    if (ph < 2) ph = 2;
    final right = base.width - pw - margin;
    final bottom = base.height - ph - margin;
    final (x, y) = switch (_pipPosition) {
      PipPosition.topLeft => (margin, margin),
      PipPosition.topRight => (right, margin),
      PipPosition.bottomLeft => (margin, bottom),
      _ => (right, bottom),
    };
    final xx = x < 0 ? 0 : x;
    final yy = y < 0 ? 0 : y;
    final b = StringBuffer();
    b.write('[1:v]scale=$pw:$ph,format=yuva420p,split=2[pv1][pv2];');
    b.write('[pv2]');
    if (_pipOpacity < 1) {
      b.write('colorchannelmixer=aa=${_pipOpacity.toStringAsFixed(2)},');
    }
    b.write('alphaextract[pa0];');
    if (hasMask) {
      b.write('[2:v]scale=$pw:$ph,format=gray[mg];');
      b.write('[pa0][mg]blend=all_mode=multiply[pa];');
    } else {
      b.write('[pa0]null[pa];');
    }
    if (_pipBlend == 'normal') {
      b.write('[pv1][pa]alphamerge[pipA];');
      b.write('[0:v][pipA]overlay=x=$xx:y=$yy[vout]');
    } else {
      // [0:v] is consumed twice (crop + final overlay) — split it.
      b.write('[0:v]split=2[bbg][bcrop];');
      b.write('[bcrop]crop=$pw:$ph:$xx:$yy,format=gbrp[bc];');
      b.write('[pv1]format=gbrp[pc];');
      b.write('[bc][pc]blend=all_mode=$_pipBlend[bl];');
      b.write('[bl]format=yuva420p[blf];');
      b.write('[blf][pa]alphamerge[bla];');
      b.write('[bbg][bla]overlay=x=$xx:y=$yy[vout]');
    }
    return b.toString();
  }

  /// The PIP mask shape as a [Path] in a [size] rect — the ONE
  /// shape definition behind both the exported mask PNG and the
  /// preview, so they cannot drift apart. Only the shape masks
  /// ('circle' / 'rect' / 'roundrect' / 'heart' / 'star') come
  /// through here; 'linear' / 'radial' are gradients, drawn
  /// directly by [_pipMaskPngBytes].
  Path _pipMaskShapePath(String shape, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final path = Path();
    switch (shape) {
      case 'circle':
        // Same disc the old geq snippet drew: diameter min(w,h),
        // centred on the inset.
        path.addOval(Rect.fromCircle(
          center: Offset(cx, cy),
          radius: math.min(w, h) / 2,
        ));
      case 'roundrect':
        path.addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, w, h),
          Radius.circular(math.min(w, h) * 0.18),
        ));
      case 'heart':
        Offset pt(double fx, double fy) => Offset(fx * w, fy * h);
        path.moveTo(pt(0.50, 0.90).dx, pt(0.50, 0.90).dy);
        path.cubicTo(pt(0.10, 0.62).dx, pt(0.10, 0.62).dy, pt(0.02, 0.40).dx,
            pt(0.02, 0.40).dy, pt(0.12, 0.24).dx, pt(0.12, 0.24).dy);
        path.cubicTo(pt(0.20, 0.10).dx, pt(0.20, 0.10).dy, pt(0.38, 0.10).dx,
            pt(0.38, 0.10).dy, pt(0.50, 0.30).dx, pt(0.50, 0.30).dy);
        path.cubicTo(pt(0.62, 0.10).dx, pt(0.62, 0.10).dy, pt(0.80, 0.10).dx,
            pt(0.80, 0.10).dy, pt(0.88, 0.24).dx, pt(0.88, 0.24).dy);
        path.cubicTo(pt(0.98, 0.40).dx, pt(0.98, 0.40).dy, pt(0.90, 0.62).dx,
            pt(0.90, 0.62).dy, pt(0.50, 0.90).dx, pt(0.50, 0.90).dy);
        path.close();
      case 'star':
        final rOut = math.min(w, h) / 2;
        final rIn = rOut * 0.45;
        for (var i = 0; i < 10; i++) {
          final ang = -math.pi / 2 + i * math.pi / 5;
          final r = i.isEven ? rOut : rIn;
          final px = cx + math.cos(ang) * r;
          final py = cy + math.sin(ang) * r;
          if (i == 0) {
            path.moveTo(px, py);
          } else {
            path.lineTo(px, py);
          }
        }
        path.close();
      default: // 'rect' — the full inset.
        path.addRect(Rect.fromLTWH(0, 0, w, h));
    }
    return path;
  }

  /// Renders the current PIP mask (shape / gradient, feather,
  /// invert) as PNG bytes at [width]×[height] — white where the
  /// inset shows, transparent where it is masked out. Feather on
  /// shapes is a real alpha blur (MaskFilter.blur), so the soft
  /// edge is identical in preview and export; on gradients the
  /// feather widens the ramp instead.
  Future<Uint8List?> _pipMaskPngBytes(int width, int height) async {
    if (width < 2 || height < 2) return null;
    final w = width.toDouble();
    final h = height.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final feather = _pipMaskFeather.clamp(0.0, 1.0);
    const white = Color(0xFFFFFFFF);
    const clear = Color(0x00000000);
    if (_pipMask == 'linear' || _pipMask == 'radial') {
      final paint = ui.Paint();
      if (_pipMask == 'linear') {
        final a = 0.5 - feather / 2;
        final bb = 0.5 + feather / 2;
        paint.shader = ui.Gradient.linear(
          Offset.zero,
          Offset(w, 0),
          _pipMaskInvert
              ? const [clear, clear, white, white]
              : const [white, white, clear, clear],
          [0, a, bb, 1],
        );
      } else {
        final radius = math.sqrt(w * w + h * h) / 2;
        paint.shader = ui.Gradient.radial(
          Offset(w / 2, h / 2),
          radius,
          _pipMaskInvert
              ? const [clear, clear, white]
              : const [white, white, clear],
          [0, (1 - feather).clamp(0.0, 1.0), 1],
        );
      }
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
    } else {
      final path = _pipMaskShapePath(_pipMask, Size(w, h));
      final sigma = feather * math.min(w, h) * 0.2;
      if (_pipMaskInvert) {
        canvas.drawRect(
            Rect.fromLTWH(0, 0, w, h), ui.Paint()..color = white);
        final cut = ui.Paint()..blendMode = BlendMode.clear;
        if (sigma > 0) {
          cut.maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma);
        }
        canvas.drawPath(path, cut);
      } else {
        final fill = ui.Paint()..color = white;
        if (sigma > 0) {
          fill.maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, sigma);
        }
        canvas.drawPath(path, fill);
      }
    }
    final picture = recorder.endRecording();
    final img = await picture.toImage(width, height);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    picture.dispose();
    return data?.buffer.asUint8List();
  }

  /// Writes the export-resolution mask PNG for the PIP pass;
  /// returns its path, or null when rendering failed (the caller
  /// then builds the graph without the mask input).
  Future<String?> _renderPipMaskPng({
    required Directory dir,
    required int stamp,
    required int width,
    required int height,
  }) async {
    try {
      final bytes = await _pipMaskPngBytes(width, height);
      if (bytes == null) return null;
      final f = File(p.join(dir.path, 'pip_mask_$stamp.png'));
      await f.writeAsBytes(bytes);
      return f.path;
    } catch (_) {
      return null;
    }
  }

  /// Keeps the PIP preview controller in sync with the picked
  /// inset: created (muted, looping) when a video is chosen,
  /// disposed when PIP is switched off or the pick changes.
  /// Idempotent — safe to call from build and from the pickers.
  void _ensurePipPreview() {
    if (!_fxPip || _fxPipVideo.isEmpty) {
      if (_pipController != null) {
        _pipController!.dispose();
        _pipController = null;
        _pipControllerPath = '';
      }
      return;
    }
    if (_pipControllerPath == _fxPipVideo || _pipControllerBusy) return;
    _pipControllerBusy = true;
    final path = _fxPipVideo;
    final old = _pipController;
    final c = VideoPlayerController.file(File(path));
    _pipController = c;
    _pipControllerPath = path;
    old?.dispose();
    () async {
      try {
        await c.initialize();
        await c.setLooping(true);
        await c.setVolume(0);
        await c.play();
      } catch (_) {
        // Preview is best-effort — the export never depends on it.
      }
      _pipControllerBusy = false;
      if (mounted) setState(() {});
    }();
  }

  /// Loads (once per parameter change) the preview-resolution
  /// mask image used by the stage's ShaderMask.
  void _ensurePipMaskImage(int width, int height) {
    final key = '$_pipMask|${_pipMaskFeather.toStringAsFixed(2)}|'
        '$_pipMaskInvert|${width}x$height';
    if (_pipMaskImageKey == key || _pipMaskImageBusy) return;
    _pipMaskImageKey = key;
    _pipMaskImageBusy = true;
    () async {
      ui.Image? img;
      try {
        final bytes = await _pipMaskPngBytes(width, height);
        if (bytes != null) {
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          img = frame.image;
        }
      } catch (_) {
        img = null;
      }
      _pipMaskImageBusy = false;
      if (!mounted) {
        img?.dispose();
        return;
      }
      final old = _pipMaskImage;
      setState(() => _pipMaskImage = img);
      old?.dispose();
    }();
  }

  /// The stage's PIP layer: the inset composited over the main
  /// preview at the export's position/scale fractions, with the
  /// chosen blend mode (saveLayer), opacity and mask (the SAME
  /// generated mask PNG as the export, as a dstIn ImageShader).
  Widget _pipPreviewLayer(Size stage) {
    final clip = _clips.isEmpty ? null : _clips[_selected];
    final ctrl = _controller;
    // Main content rect (contain fit, centred on the black stage).
    double mainAspect = stage.aspectRatio;
    double basePxW = 1280;
    if (clip != null && clip.isPhoto) {
      mainAspect = clip.aspectRatio;
      basePxW = 1920;
    } else if (ctrl != null && ctrl.value.isInitialized) {
      mainAspect = ctrl.value.aspectRatio;
      basePxW = ctrl.value.size.width;
    }
    var dispW = stage.width;
    var dispH = dispW / mainAspect;
    if (dispH > stage.height) {
      dispH = stage.height;
      dispW = dispH * mainAspect;
    }
    final dispX = (stage.width - dispW) / 2;
    final dispY = (stage.height - dispH) / 2;
    final pipCtrl = _pipController;
    final pipReady = pipCtrl != null && pipCtrl.value.isInitialized;
    final pipPxW = pipReady ? pipCtrl!.value.size.width : 1280;
    final pipAspect = pipReady ? pipCtrl!.value.aspectRatio : 16 / 9;
    final s = _pipScale.clamp(0.15, 0.5);
    final pipW = dispW * pipPxW * s / basePxW;
    final pipH = pipW / pipAspect;
    final margin = dispW * 24 / basePxW;
    final (lx, ty) = switch (_pipPosition) {
      PipPosition.topLeft => (dispX + margin, dispY + margin),
      PipPosition.topRight => (dispX + dispW - pipW - margin, dispY + margin),
      PipPosition.bottomLeft => (dispX + margin, dispY + dispH - pipH - margin),
      _ => (dispX + dispW - pipW - margin, dispY + dispH - pipH - margin),
    };
    // Preview mask at a capped resolution (shapes/gradients are
    // scale-invariant; feather is relative to the short side).
    if (_pipMask != 'none' && pipReady) {
      final mw = pipCtrl!.value.size.width.round();
      final mh = pipCtrl!.value.size.height.round();
      final cap = 480 / math.max(mw, mh);
      final sw = cap < 1 ? (mw * cap).round() : mw;
      final sh = cap < 1 ? (mh * cap).round() : mh;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensurePipMaskImage(sw, sh);
      });
    }
    Widget content = pipReady
        ? VideoPlayer(pipCtrl!)
        : Container(
            decoration: BoxDecoration(
              color: Colors.black54,
              border: Border.all(color: TjProTheme.gold),
            ),
            child: const Center(
              child: Icon(Icons.picture_in_picture_alt,
                  color: Colors.white70, size: 28),
            ),
          );
    if (_pipMask != 'none' && _pipMaskImage != null) {
      final img = _pipMaskImage!;
      content = ShaderMask(
        shaderCallback: (bounds) => ui.ImageShader(
          img,
          ui.TileMode.clamp,
          ui.TileMode.clamp,
          (Matrix4.identity()
                ..scale(bounds.width / img.width, bounds.height / img.height))
              .storage,
        ),
        blendMode: BlendMode.dstIn,
        child: content,
      );
    }
    content = Opacity(opacity: _pipOpacity.clamp(0.1, 1.0), child: content);
    final mode = _pipBlendMode(_pipBlend);
    if (mode != null) {
      content = _BlendLayer(mode: mode, child: content);
    }
    return Positioned(
      left: lx,
      top: ty,
      width: pipW,
      height: pipH,
      child: content,
    );
  }

  /// dart:ui blend mode for a PIP blend key ('normal' → null,
  /// meaning plain source-over compositing).
  BlendMode? _pipBlendMode(String key) {
    switch (key) {
      case 'multiply':
        return BlendMode.multiply;
      case 'screen':
        return BlendMode.screen;
      case 'overlay':
        return BlendMode.overlay;
      case 'softlight':
        return BlendMode.softLight;
      case 'hardlight':
        return BlendMode.hardLight;
      case 'darken':
        return BlendMode.darken;
      case 'lighten':
        return BlendMode.lighten;
      case 'difference':
        return BlendMode.difference;
      case 'dodge':
        return BlendMode.colorDodge;
      case 'burn':
        return BlendMode.colorBurn;
      default:
        return null;
    }
  }

  /// One icon+label choice item — the global UI rule (user order
  /// 22 Nov 2026): every choice inside a tool is an icon above a
  /// label, in a horizontal swipeable row, never bare text. Mirrors
  /// the main tool rail's look (violet when selected).
  Widget _iconChoiceItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback? onTap,
    Color? iconColor,
    TextStyle? labelStyle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
            decoration: BoxDecoration(
              color: selected ? TjProTheme.violet : const Color(0xFF232323),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 21, color: iconColor ?? Colors.white),
                const SizedBox(height: 3),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle ??
                      const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A horizontal scrollable row of [_iconChoiceItem]s — swipe
  /// left/right and more options keep appearing; nothing is
  /// buried in a dropdown or a wrapped stack.
  Widget _iconChoiceRail(List<Widget> items) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: items),
    );
  }

  /// Captions mapped onto the exported timeline: captions were recorded
  /// against the selected clip, so in a merged export they start after
  /// the preceding clips, and everything scales by the export speed.
  /// EXCEPTION (Phase 7 handoff): project captions are already
  /// timeline-relative over the whole reel, so they get no offset —
  /// only the speed scaling.
  List<CaptionSegment> _adjustedCaptions() {
    if (_captions.isEmpty) return [];
    var offset = 0.0;
    if (!_captionsTimelineRelative) {
      for (var i = 0; i < _selected && i < _clips.length; i++) {
        offset += _clips[i].effectiveDuration;
      }
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
          // Transcribed segments are per-clip, not timeline-relative.
          _captionsTimelineRelative = false;
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
        // Edited segments are per-clip, not timeline-relative.
        _captionsTimelineRelative = false;
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
    _pushHistory();
    clip.trimEnd = mid;
    setState(() {
      _clips.insert(_selected + 1, second);
      _selected = _selected + 1;
    });
    unawaited(_loadPreview());
  }


  /// The chroma settings exactly as the export pass will use them.
  ProChroma _currentChroma() {
    return ProChroma(
      color: _proChromaColor,
      similarity: _proChromaSimilarity,
      blend: _proChromaBlend,
      backgroundKind: _proChromaBgKind,
      backgroundColor: _proChromaBgColor,
      backgroundImagePath:
          _proChromaBgKind == 'image' ? _proChromaBgImage : null,
      spill: _proChromaSpill,
      edge: _proChromaEdge,
    );
  }

  /// Debounced live keyed preview (addendum B.3): slider/colour
  /// changes re-render ONE frame through the exact export graph.
  void _scheduleChromaPreview() {
    _chromaPreviewTimer?.cancel();
    _chromaPreviewTimer =
        Timer(const Duration(milliseconds: 450), _refreshChromaPreview);
  }

  Future<void> _refreshChromaPreview() async {
    if (!_proChroma || _clips.isEmpty || _chromaPreviewBusy) return;
    _chromaPreviewBusy = true;
    try {
      final dir = await _workDir();
      final out = p.join(dir.path, 'chroma_preview.png');
      final clip = _clips[_selected < _clips.length ? _selected : 0];
      final ctrl = _controller;
      final posSec = (ctrl != null && ctrl.value.isInitialized)
          ? ctrl.value.position.inMilliseconds / 1000.0
          : 0.5;
      final cmd = chromaPreviewFrameCommand(
        input: clip.file.path,
        c: _currentChroma(),
        output: out,
        atSec: posSec,
      );
      final res = await FfmpegService.run(cmd);
      if (res.ok && mounted) {
        setState(() => _chromaPreviewPath = out);
      }
    } catch (_) {
      // Preview is best-effort; the export graph is unchanged.
    } finally {
      _chromaPreviewBusy = false;
    }
  }

  /// Eyedropper (addendum B.3): grab the current frame, let the user
  /// tap the colour to key out, store it as '#RRGGBB'.
  Future<void> _eyedropperPick() async {
    if (_clips.isEmpty) {
      _setStatus('Pehle clip select karein.');
      return;
    }
    final clip = _clips[_selected < _clips.length ? _selected : 0];
    final ctrl = _controller;
    final posSec = (ctrl != null && ctrl.value.isInitialized)
        ? ctrl.value.position.inMilliseconds / 1000.0
        : 0.5;
    try {
      final dir = await _workDir();
      final frame = p.join(dir.path, 'chroma_eye_frame.png');
      final r = await FfmpegService.run(
        '-ss $posSec -i ${FfmpegService.q(clip.file.path)} '
        '-frames:v 1 -q:v 2 -y ${FfmpegService.q(frame)}',
      );
      if (!r.ok) {
        _setStatus('Frame nahi mila — video play karke dobara try karein.');
        return;
      }
      if (!mounted) return;
      final picked = await showDialog<String>(
        context: context,
        builder: (_) => _ChromaEyeDialog(framePath: frame),
      );
      if (picked != null) {
        setState(() => _proChromaColor = picked);
        _scheduleChromaPreview();
      }
    } catch (e) {
      _setStatus('Eyedropper fail: $e');
    }
  }

  /// Bundled backdrop chip (Newsroom / Studio Desk): materialise
  /// the asset like the project-handoff path does, then point the
  /// chroma background at it.
  Future<void> _applyBackdropAsset(String asset) async {
    try {
      final dir = await _workDir();
      final f = await ensureLutFile(asset, dir);
      setState(() {
        _proChromaBgKind = 'image';
        _proChromaBgImage = f.path;
      });
      _scheduleChromaPreview();
    } catch (e) {
      _setStatus('Backdrop load nahi hua: $e');
    }
  }

  /// "News anchor" preset (addendum B.3): one blessed set of values
  /// for a lit green-screen studio shot. Similarity 0.3 is the ONE
  /// default everywhere now (the editor used to default to 0.4
  /// while the engine documented 0.3 — addendum V2).
  void _applyNewsAnchorPreset() {
    setState(() {
      _proChromaColor = 'green';
      _proChromaSimilarity = 0.3;
      _proChromaBlend = 0.1;
      _proChromaSpill = 0.5;
      _proChromaEdge = 0;
    });
    _scheduleChromaPreview();
  }

  Widget _railButton(String key, String label, IconData icon) {
    final selected = _activeTool == key;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openTool(key),
        child: Container(
          width: 76,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? TjProTheme.violet : const Color(0xFF232323),
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

  /// Display name for a tool key (used in the panel header).
  String _toolDisplayName(String key) {
    const Map<String, String> names = <String, String>{
      'edit': 'Edit',
      'audio': 'Audio',
      'text': 'Text',
      'colour': 'Colour',
      'effects': 'Effects',
      'overlay': 'Overlay',
      'transitions': 'Transitions',
      'news': 'News',
    };
    return names[key] ?? key;
  }

  /// Header for the open tool panel: Back button + tool name + Done button.
  /// CapCut-style: Back/Done closes the panel and returns to the tool grid.
  Widget _toolPanelHeader(String toolKey) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back to tools',
            onPressed: () => _openTool(null),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          Expanded(
            child: Text(
              _toolDisplayName(toolKey),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => _openTool(null),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final clip = _clips.isEmpty ? null : _clips[_selected];
    final ctrl = _controller;
    final ready = ctrl != null && ctrl.value.isInitialized;
    final isPlaying = ready && ctrl.value.isPlaying;
    // PIP preview sync (idempotent; only acts on a pick change).
    if ((_fxPip && _fxPipVideo.isNotEmpty && _pipControllerPath != _fxPipVideo) ||
        (!_fxPip && _pipController != null)) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _ensurePipPreview());
    }
    final posSec = ready ? ctrl.value.position.inMilliseconds / 1000 : 0.0;
    final durSec = clip != null ? clip.duration.inMilliseconds / 1000 : 0.0;
    String fmt(double sec) {
      final m = sec ~/ 60;
      final ss = (sec % 60).toStringAsFixed(1).padLeft(4, '0');
      return '$m:$ss';
    }

    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
            seedColor: TjProTheme.gold, brightness: Brightness.dark),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('TJ Pro — Video Editor'),
          actions: [
            // Export-quality pill (§3): tap to set the quality
            // ahead of time; Export then skips its dialog.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: OutlinedButton(
                onPressed: _busy ? null : _pickExportQuality,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white38),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: Text(_qualityLabel),
              ),
            ),
            // ONE gold Export pill — top-right, always (§3/§4).
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _export,
                style: ElevatedButton.styleFrom(
                  backgroundColor: TjProTheme.gold,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.ios_share, size: 18),
                label: Text(_busy ? 'Exporting…' : 'Export'),
              ),
            ),
          ],
        ),
        // LAYOUT v1.3.0 (§3 — the user's screenshot complaint: the
        // preview was crushed by permanently-open blocks). Top to
        // bottom: handoff banner → BIG stage (dominant share, the
        // transport row pinned to ITS bottom, status as a transient
        // overlay chip) → timeline directly under the stage → ONE
        // tool zone: the tool rail, or ONLY the open tool's panel
        // in the rail's place. Nothing else is ever open; there is
        // NO separate Add-video row (the + tile lives at the end
        // of the timeline) and NO second Export button.
        body: Column(
          children: [
            if (_handoffProject != null)
              Container(
                width: double.infinity,
                color: const Color(0xFF1E1E2E),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  key: const Key('handoffProjectBanner'),
                  'News project: ${_projectTitle()} • ${_clips.length} clip(s)'
                  '${_projectVoiceoverPath == null ? '' : ' • voiceover'}'
                  ' • ${_projectTemplateKind ?? 'live'} template'
                  '${_projectLoading ? ' • load ho raha hai…' : ''}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            // ---- STAGE ----
            Expanded(
              child: Container(
                color: Colors.black,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: clip == null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // + empty-state on the stage (§4):
                                  // the same add action as the
                                  // timeline's + tile.
                                  InkWell(
                                    onTap: _addClip,
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      width: 110,
                                      height: 110,
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: TjProTheme.gold,
                                          width: 2,
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(16),
                                      ),
                                      child: const Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.add,
                                              color: TjProTheme.gold,
                                              size: 40),
                                          SizedBox(height: 4),
                                          Text('Add video',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Pehli video add karein — ya timeline '
                                    'ke + tile se.',
                                    style: TextStyle(color: Colors.white54),
                                  ),
                                ],
                              ),
                            )
                          : clip.isPhoto
                              ? ColorFiltered(
                                  colorFilter:
                                      ColorFilter.matrix(_stageMatrix),
                                  child: Image.file(
                                    clip.file,
                                    fit: BoxFit.contain,
                                    width: double.infinity,
                                    height: double.infinity,
                                  ),
                                )
                              : ready
                                  ? GestureDetector(
                                      onTapDown: _onPreviewTapDown,
                                      // §6.2 hold-to-compare: hold
                                      // the stage to see the RAW
                                      // frame, release for the
                                      // graded one.
                                      onLongPressStart: (_) =>
                                          setState(() => _comparing = true),
                                      onLongPressEnd: (_) =>
                                          setState(() => _comparing = false),
                                      child: Stack(
                                        alignment: Alignment.bottomCenter,
                                        children: [
                                          ColorFiltered(
                                            colorFilter: ColorFilter.matrix(
                                                _stageMatrix),
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
                                              padding: const EdgeInsets.only(
                                                  bottom: 64),
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
                                          if (_comparing)
                                            const Positioned(
                                              top: 10,
                                              child: Chip(
                                                label: Text('Original'),
                                                backgroundColor:
                                                    Colors.black54,
                                                labelStyle: TextStyle(
                                                    color: Colors.white),
                                              ),
                                            ),
                                        ],
                                      ),
                                    )
                                  : const Center(
                                      child: Text('Preview load ho raha hai…',
                                          style:
                                              TextStyle(color: Colors.white70)),
                                    ),
                    ),
                    // PIP live preview (§6.11 completion fix):
                    // the inset composited on the stage with its
                    // blend mode / mask / opacity, exactly where
                    // the export will put it.
                    if (_fxPip && _fxPipVideo.isNotEmpty)
                      Positioned.fill(
                        child: LayoutBuilder(
                          builder: (context, constraints) =>
                              Stack(children: [
                            _pipPreviewLayer(constraints.biggest),
                          ]),
                        ),
                      ),
                    // Transient status chip (§3) — overlays the
                    // stage, auto-hides; never a permanent line.
                    if (_statusVisible)
                      Positioned(
                        top: 10,
                        left: 12,
                        right: 12,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _status,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                    // Transport row — pinned to the STAGE bottom.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.55),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Undo',
                              onPressed: _undoStack.isEmpty ? null : _undo,
                              icon: const Icon(Icons.undo,
                                  color: Colors.white, size: 20),
                            ),
                            IconButton(
                              tooltip: 'Redo',
                              onPressed: _redoStack.isEmpty ? null : _redo,
                              icon: const Icon(Icons.redo,
                                  color: Colors.white, size: 20),
                            ),
                            const Spacer(),
                            if (ready)
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    isPlaying ? ctrl.pause() : ctrl.play();
                                  });
                                },
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: const BoxDecoration(
                                    color: TjProTheme.gold,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isPlaying
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    color: Colors.black,
                                    size: 28,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 12),
                            Text(
                              '${fmt(posSec)} / ${fmt(durSec)}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: 'Fullscreen',
                              onPressed: ready ? _openFullscreen : null,
                              icon: const Icon(Icons.fullscreen,
                                  color: Colors.white, size: 22),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ---- TIMELINE (directly under the stage) ----
            _timelineSection(clip),
            // ---- TOOL ZONE: rail ⇄ the one open panel ----
            SizedBox(
              height: 218,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                transitionBuilder:
                    (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.05),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                          parent: animation, curve: Curves.easeOut)),
                      child: child,
                    ),
                  );
                },
                child: _activeTool == null
                    ? Container(
                        key: const ValueKey<String>('video-rail'),
                        color: const Color(0xFF1B1B1B),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(12, 10, 12, 2),
                              child: Text(
                                'Tools — koi tool chunein, sirf usi ke '
                                'controls khulenge.',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 12),
                              ),
                            ),
                            SizedBox(
                              height: 88,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                children: [
                                  _railButton(
                                      'edit', 'Edit', Icons.content_cut),
                                  _railButton(
                                      'audio', 'Audio', Icons.music_note),
                                  _railButton(
                                      'text', 'Text', Icons.text_fields),
                                  _railButton(
                                      'colour', 'Colour', Icons.palette),
                                  _railButton('effects', 'Effects',
                                      Icons.auto_awesome),
                                  _railButton(
                                      'overlay', 'Overlay', Icons.layers),
                                  _railButton('transitions', 'Transitions',
                                      Icons.swap_horiz),
                                  _railButton(
                                      'news', 'News', Icons.newspaper),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        key: ValueKey<String>('video-panel-${_activeTool!}'),
                        color: const Color(0xFF121212),
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _toolPanelHeader(_activeTool!),
                            _panelTabRow(),
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.only(top: 4),
                                children: _toolPanelChildren(),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}



/// Composites its child against everything painted beneath it in
/// the same layer tree using [mode] — a saveLayer whose paint
/// carries the blend mode, so the layer's content blends with the
/// actual stage pixels under it (the video texture included). This
/// is the preview twin of the export's masked-blend chain: for
/// opaque inset pixels the result is the same blend equation;
/// at feathered/transparent edges both interpolate towards the
/// untouched base.
class _BlendLayer extends SingleChildRenderObjectWidget {
  const _BlendLayer({required this.mode, required super.child});

  final BlendMode mode;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBlendLayer(mode);

  @override
  void updateRenderObject(
      BuildContext context, _RenderBlendLayer renderObject) {
    renderObject.mode = mode;
  }
}

class _RenderBlendLayer extends RenderProxyBox {
  _RenderBlendLayer(this._mode);

  BlendMode _mode;

  set mode(BlendMode value) {
    if (_mode != value) {
      _mode = value;
      markNeedsPaint();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (_mode == BlendMode.srcOver) {
      super.paint(context, offset);
      return;
    }
    context.canvas
        .saveLayer(offset & size, Paint()..blendMode = _mode);
    super.paint(context, offset);
    context.canvas.restore();
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


/// Eyedropper dialog: shows one grabbed frame; tapping it samples
/// the tapped pixel's colour and pops with '#RRGGBB'. The image is
/// decoded once (raw RGBA) so sampling is exact; the tap is mapped
/// through the same BoxFit.contain letterboxing the Image widget
/// uses, so the sampled point is the point the user sees.
class _ChromaEyeDialog extends StatefulWidget {
  const _ChromaEyeDialog({required this.framePath});

  final String framePath;

  @override
  State<_ChromaEyeDialog> createState() => _ChromaEyeDialogState();
}

class _ChromaEyeDialogState extends State<_ChromaEyeDialog> {
  ui.Image? _image;
  ByteData? _pixels;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.framePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (!mounted) return;
      setState(() {
        _image = frame.image;
        _pixels = data;
      });
    } catch (_) {
      if (mounted) Navigator.pop(context);
    }
  }

  void _onTap(TapDownDetails d, Size box) {
    final img = _image;
    final px = _pixels;
    if (img == null || px == null) return;
    // BoxFit.contain: scale to fit, centered.
    final scale = math.min(box.width / img.width, box.height / img.height);
    final dw = img.width * scale;
    final dh = img.height * scale;
    final ox = (box.width - dw) / 2;
    final oy = (box.height - dh) / 2;
    final lx = d.localPosition.dx - ox;
    final ly = d.localPosition.dy - oy;
    if (lx < 0 || ly < 0 || lx >= dw || ly >= dh) return;
    final x = (lx / scale).floor().clamp(0, img.width - 1);
    final y = (ly / scale).floor().clamp(0, img.height - 1);
    final i = (y * img.width + x) * 4;
    final r = px.getUint8(i);
    final g = px.getUint8(i + 1);
    final b = px.getUint8(i + 2);
    String h(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    Navigator.pop(context, '#${h(r)}${h(g)}${h(b)}');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rang chunein — frame par tap karein'),
      content: SizedBox(
        width: 320,
        height: 320,
        child: _image == null
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final box =
                      Size(constraints.maxWidth, constraints.maxHeight);
                  return GestureDetector(
                    onTapDown: (d) => _onTap(d, box),
                    child: Image.file(
                      File(widget.framePath),
                      fit: BoxFit.contain,
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
