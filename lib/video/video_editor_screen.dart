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
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../app_config.dart';
import '../theme.dart';
import '../live/news_template.dart';
import '../news/channel_preset.dart';
import '../news/news_project.dart';
import '../news/project_handoff.dart';
import '../services/ai_tool_charge.dart';
import '../services/feature_gate.dart';
import '../services/photo_pipeline.dart';
import '../services/ffmpeg_service.dart';
import '../services/caption_service.dart';
import '../services/pro_editor.dart';
import '../services/fx_pack.dart';
import '../services/pro_vision.dart';
import '../services/audio_enhance_service.dart';
import '../services/safe_ops.dart';
import '../services/urdu_caption_service.dart';
import 'video_editor_recovery.dart';
import '../services/video_export_service.dart';
import 'editor_stage.dart';
import 'adjust_params.dart';
import 'editor_models.dart';
import 'video_editor_controller.dart';
import 'editor_export_controller.dart';
import 'widgets/timeline_bar.dart';
import 'widgets/tool_rows.dart';
import 'widgets/transport_row.dart';

export 'editor_models.dart';

import 'video_editor_panels.dart';
import 'widgets/panel_controls.dart';

class VideoEditorScreen extends StatefulWidget {
  /// Plain editor: opens empty, clips come from the gallery picker.
  ///
  /// Timeline handoff (Phase 7): when [project] is given, the editor
  /// opens WITH that News Maker project loaded — clips + voiceover +
  /// template + ticker + captions, resolved by [buildHandoff] (see
  /// `lib/news/project_handoff.dart`) — instead of dropping it. [preset]
  /// is the project's channel preset (chroma / PIP / logo settings).
  ///
  /// Projects hub (v1.4.0): [initialVideoPath], when non-null and the
  /// file exists, is loaded as the first timeline clip on open — the
  /// media the user picked in the hub. It is ignored when [project]
  /// is given (the handoff brings its own clips). Null — every
  /// existing call site — keeps the plain empty-editor behaviour.
  const VideoEditorScreen({
    super.key,
    this.project,
    this.preset,
    this.initialVideoPath,
    this.initialPipVideoPath,
  });

  final NewsProject? project;
  final ChannelPreset? preset;
  final String? initialVideoPath;

  /// Motion M2 (v1.14.0): a rendered motion-graphic overlay
  /// (WebM alpha / MP4) handed over by the Motion Editor's
  /// "Video par Lagao" — when the file exists, the editor opens
  /// with the PIP element already set to it, so the design lands
  /// as the editor's own overlay clip (preview + export use the
  /// existing PIP pass). Null — every existing call site — keeps
  /// the plain behaviour.
  final String? initialPipVideoPath;

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen>
    implements VideoEditorController {
  final _picker = ImagePicker();
  final List<VideoClip> _clips = [];
  int _selected = 0;
  VideoPlayerController? _controller;
  bool _busy = false;

  /// Phase 0 export CANCEL state: [_exporting] is true only while
  /// the export pipeline runs (unlike [_busy], which every long
  /// tool sets); [_exportCancelRequested] is set by [_cancelExport]
  /// and checked between pipeline stages via [_checkExportCancelled].
  bool _exporting = false;
  bool _exportCancelRequested = false;
  String _status = 'Pick a video to start.';
  double _speed = 1.0;
  String _filter = 'Normal';
  String _aspect = 'Original';
  bool _crossfade = false;
  String _text = '';
  String? _musicPath;
  // Music track gain (1.0 = unchanged); applied to the music audio only.
  double _musicVolume = 1.0;
  // v1.16.0 G3 (A3): lane controls — audio-lane mute (export
  // binds it) + PIP-lane lock (guards window edits).
  bool _musicMuted = false;
  bool _pipLaneLocked = false;
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

  // ---- v1.4.0 CapCut shell state. ----
  /// The Split panel's mode toggle: ON = Split cuts at the
  /// playhead, OFF = Split cuts at the clip midpoint. (Named
  /// _snapOn since v1.3.0; it was silently unread by the split
  /// path until v1.15.0 G1 wired it for real.)
  bool _snapOn = true;

  // ---- v1.14.0 timeline state (T1 / T2 / T3). ----
  /// T1 (A20): the TIMELINE's own snap — the resting playhead
  /// and the trim handles snap to boundaries / beats / markers.
  /// Separate from [_snapOn] above (that one is Split's
  /// playhead-vs-midpoint choice and keeps its meaning).
  /// Strength: 0 = Halki, 1 = Normal, 2 = Mazboot. Persisted
  /// (SharedPreferences) with [_timecodeOn].
  bool _tlSnapOn = true;
  int _tlSnapStrength = 1;

  /// T1 (A14): timecode readouts (H:MM:SS:FF at the export fps)
  /// in the transport row + the timeline times row, instead of
  /// m:ss. Persisted with [_tlSnapOn].
  bool _timecodeOn = false;

  /// T2: what the selected clip's timeline handles do —
  /// 'trim' (the original edge trim), 'roll' (A6: a handle
  /// moves the boundary WITH the neighbouring clip, total
  /// length unchanged) or 'slip' (A7: dragging the block
  /// slides the used window inside the file; position and
  /// length unchanged).
  String _trimMode = 'trim';

  /// T3 (A4): multi-select. [_multiMode] is the mode switch
  /// (timeline taps then tick clips instead of selecting one);
  /// [_multiSelect] holds the ticked clip indices. Both ride
  /// the undo + session snapshots like the markers do.
  bool _multiMode = false;
  final Set<int> _multiSelect = <int>{};

  /// T3 (A5): range In/Out points in TIMELINE seconds (null =
  /// not set) + the loop-range playback switch. They ride the
  /// undo + session snapshots; range EXPORT is deliberately
  /// not part of this build (its own build, per the research).
  double? _rangeIn;
  double? _rangeOut;
  bool _loopRange = false;

  /// T1 (A13): the px-per-second when the current pinch
  /// gesture on the timeline strip began (updates are computed
  /// FROM it, never accumulated — the stage-pinch rule).
  double _tlPinchBasePps = 42;

  /// Clip-selected row (the context row): true after a timeline
  /// clip is tapped — the tool zone then shows THAT clip's tools
  /// instead of the main tool row, until the row's back/✓ closes it.
  bool _clipRow = false;

  // ---- v1.5.0 InShot shell state. ----
  /// The one playback clock (#5/#29/#30) — see [TimelineClock].
  final TimelineClock _clock = TimelineClock();

  /// Element row (PIP selected): true while the PIP element's own
  /// tool row is showing in the tool zone.
  bool _elementRow = false;

  /// Timeline strip scroll + zoom (px per second of timeline).
  final ScrollController _tlScroll = ScrollController();
  double _tlPxPerSec = 42;

  /// True while the user is dragging the timeline strip — the
  /// clock's auto-scroll must not fight the user's finger.
  bool _tlUserScrolling = false;
  // Build 4 player fix: true while the editor itself is moving the
  // timeline (playback follow / zoom) — jumpTo() manufactures
  // ScrollStart/End notifications that are NOT user scrubs.
  bool _tlProgrammaticScroll = false;

  /// Filmstrip thumbnails per clip file path (generated lazily by
  /// [_ensureThumbs]); a clip with no entry yet renders its first
  /// generated thumb or a plain block until they land.
  final Map<String, List<String>> _thumbCache = {};

  // ---- Build 2 (Phase 1 + 2) state. ----
  /// Stage guides: rule-of-thirds grid + safe zones over the
  /// canvas frame (Canvas panel / stage corner toggle).
  bool _showGrid = false;

  /// The stage layer the user last tapped: null (none), 'pip' or
  /// 'text'. A selected layer shows its outline on the stage and
  /// its property panel/row below — the Phase 1 layer pattern.
  String? _stageLayer;

  /// The canvas frame + media contain rects from the last stage
  /// layout (stage coordinates). Written during the stage build;
  /// read by the PIP layer math and the tap mapping.
  Rect _stageFrameRect = Rect.zero;
  Rect _stageMediaRect = Rect.zero;

  /// Pinch snapshot: the main-clip transform values + focal point
  /// when the current stage scale gesture started. Updates are
  /// computed FROM the snapshot (never accumulated per event, so
  /// the gesture cannot drift). The transform itself is the §6.7
  /// model ([_tfScale]/[_tfX]/[_tfY]/[_tfRot]) the Transform panel
  /// sliders and the export already share.
  double _pinchTfScale = 1;
  double _pinchTfX = 0;
  double _pinchTfY = 0;
  double _pinchTfRot = 0;
  Offset _pinchFocalStart = Offset.zero;

  /// PIP drag: the inset's live offset while it is being dragged
  /// on the stage; on release it snaps to the nearest corner (the
  /// [PipPosition] model) and this returns to zero.
  Offset _pipDragOffset = Offset.zero;
  double _pinchPipScale = 0.3;

  /// Formal-track state (Phase 2): the main track's lock (trim /
  /// reorder on the timeline are disabled while locked; selection
  /// and playback are not) and the collapsed lanes by key
  /// ('pip' / 'audio' / 'text').
  bool _mainTrackLocked = false;
  final Set<String> _laneHidden = <String>{};

  /// Live scrub seek debounce (Phase 2): while the user drags the
  /// timeline (paused), the preview seeks to the centred frame —
  /// throttled so the player is not flooded.
  Timer? _scrubSeekTimer;

  /// Trim-drag snap latch: true while the active trim value sits
  /// on a snap point, so the haptic ticks once per engagement.
  bool _trimSnapped = false;

  /// Music-lane waveform (Phase 2): generated showwavespic PNG per
  /// music path ('' while generating / after a failure).
  final Map<String, String> _musicWaveCache = {};
  final Set<String> _musicWavePending = <String>{};

  /// Long-press drag reorder (Phase 2): the clip index being
  /// dragged, its timeline start (seconds) when the press began —
  /// the invariant reference for the drag math, since swaps move
  /// the clip's own start — and whether it actually moved (a
  /// stationary long press still opens the swap sheet, as before).
  int? _dragClipIndex;
  double _dragOriginStartSec = 0;
  bool _dragMoved = false;

  /// Stabilizer level (v1.5.0): 0 = Original (off), 1 = Low,
  /// 2 = Standard, 3 = Most Stable. [_proStabilize] stays the
  /// export switch (level > 0); the level maps to vidstab
  /// shakiness/smoothing at the export call site.
  int _stabLevel = 0;

  /// AI Cut panel state: silence threshold (dB, negative) + minimum
  /// silence length (seconds) + the last scan's silence ranges.
  double _aicutThresholdDb = -35;
  double _aicutMinSilenceSec = 0.4;
  List<(double, double)> _aicutRanges = const [];
  bool _aicutBusy = false;

  /// Cutout panel mode: 'cutout' (AI BG remove) or 'chroma'.
  String _cutoutMode = 'cutout';

  /// Precut › Cut range (seconds, FILE time of the selected clip).
  double _cutStart = 0;
  double _cutEnd = 0;
  // ---- v1.4.0 Adjust extras (Colour › Adjust, one shared slider).
  // These ride their own ffmpeg chain ([_adjustExtraFilter]) next
  // to the ProGrade values, because ProGrade's field set is fixed.
  // All defaults are neutral: an untouched export is unchanged.
  double _adjBrilliance = 0; // -100..100 (gamma + gentle saturation)
  double _adjSharpen = 0; // 0..100 (unsharp, small radius)
  double _adjClarity = 0; // 0..100 (unsharp, large radius)
  double _adjWhites = 0; // -100..100 (curves, top end)
  double _adjBlacks = 0; // -100..100 (curves, bottom end)
  double _adjHue = 0; // -180..180 degrees
  double _adjFade = 0; // 0..100 (lifted black point)
  double _adjVignette = 0; // 0..100
  double _adjGrain = 0; // 0..100 (ffmpeg noise)
  bool _adjAuto = false; // one-tap normalize (auto adjust)

  /// True when any v1.4.0 Adjust extra is off its neutral value.
  bool get _adjustExtraActive =>
      _adjAuto ||
      _adjBrilliance != 0 ||
      _adjSharpen != 0 ||
      _adjClarity != 0 ||
      _adjWhites != 0 ||
      _adjBlacks != 0 ||
      _adjHue != 0 ||
      _adjFade != 0 ||
      _adjVignette != 0 ||
      _adjGrain != 0;

  /// The Adjust extras as the shared value object (P1-1): the
  /// export chain AND the preview matrix/overlays both derive
  /// from these fields through adjust_params.dart — one source
  /// of truth, so a slider can never move the export without
  /// moving the preview again.
  AdjustValues get _adjustValues => AdjustValues(
        auto: _adjAuto,
        brilliance: _adjBrilliance,
        sharpen: _adjSharpen,
        clarity: _adjClarity,
        whites: _adjWhites,
        blacks: _adjBlacks,
        hue: _adjHue,
        fade: _adjFade,
        vignette: _adjVignette,
        grain: _adjGrain,
      );

  /// The ffmpeg chain for the v1.4.0 Adjust extras ('' = nothing
  /// set) — built by [adjustExtraFilterChain] from the shared
  /// derivation (the chain itself is unchanged). HSL is
  /// deliberately NOT here: the bundled ffmpeg has no
  /// per-hue-range HSL filter, so no fake slider is offered.
  String _adjustExtraFilter() => adjustExtraFilterChain(_adjustValues);

  /// Reset for the whole Colour look (ProGrade + filters + the
  /// v1.4.0 Adjust extras) — the Adjust panel's Reset button.
  void _resetGrade() {
    setState(() {
      _proLut = '';
      _proTemperature = 0;
      _proTint = 0;
      _proSaturation = 1;
      _proVibrance = 1;
      _proContrast = 1;
      _proShadows = 0;
      _proHighlights = 0;
      _proBrightness = 0;
      _proExposure = 0;
      _filter = 'Normal';
      _filterIntensity = 1;
      _adjBrilliance = 0;
      _adjSharpen = 0;
      _adjClarity = 0;
      _adjWhites = 0;
      _adjBlacks = 0;
      _adjHue = 0;
      _adjFade = 0;
      _adjVignette = 0;
      _adjGrain = 0;
      _adjAuto = false;
    });
    _setStatus('Colour / Adjust reset.');
  }

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

  /// Build 3 (Phase 3): PIP keyframes — a second two-keyframe
  /// track (position + opacity only, the v1 scope for video
  /// layers) animated by [keyframedPipFilter] in the export and by
  /// [keyframePoseAt] in the stage preview. X/Y are the inset's
  /// TOP-LEFT corner as fractions of the base size (the
  /// [ProKeyframe] convention); the track spans the whole export,
  /// like the title/sticker track. Defaults: bottom-right area →
  /// top-left area, fully opaque throughout.
  bool _pipKeyframes = false;
  double _pkStartX = 0.7;
  double _pkStartY = 0.7;
  double _pkStartOpacity = 1;
  double _pkEndX = 0.05;
  double _pkEndY = 0.05;
  double _pkEndOpacity = 1;
  KeyframeEasing _pkEasing = KeyframeEasing.linear;
  int _pkPage = 0;

  /// Build 3 (Phase 3): MAIN-clip mask — the PIP mask model
  /// (shape / feather / invert, one dart:ui mask PNG for preview +
  /// export) applied to the main video itself. The stage previews
  /// it as a dstIn ShaderMask over the media layer; the export runs
  /// [mainClipMaskCommand] before the overlay/PIP passes.
  String _mainMask = 'none';
  double _mainMaskFeather = 0;
  bool _mainMaskInvert = false;
  ui.Image? _mainMaskImage;
  String _mainMaskImageKey = '';
  bool _mainMaskImageBusy = false;

  /// Build 3 (Phase 3): the export frame rate (24/30/60). Threaded
  /// into the main render graph + the normalize step; the post
  /// passes re-encode from that stream, so the rate holds.
  int _exportFps = 30;
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

  // Build 10 (7F): session autosave / recovery — a periodic
  // snapshot of the timeline + panel state (see
  // video_editor_recovery.dart). _lastSessionJson dedupes
  // writes; _restoreOffered keeps the offer to once per open.
  Timer? _sessionTimer;
  String _lastSessionJson = '';
  bool _restoreOffered = false;

  // ---- PRO tools (v2.1.0) state. Defaults = today's behaviour: every
  // pro switch/dropdown off or neutral, so an untouched export is
  // byte-for-byte the old pipeline plus the guarded post-passes (which
  // are all skipped when their switches are off). ----

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
  // A1 (v1.12): beat times are relative to the file detection
  // ran on — the music file (timeline 0) or one clip's file
  // (file seconds). The source is recorded at detection time so
  // [timelineBeats] can map them onto the timeline correctly.
  bool _beatSourceMusic = false;
  String? _beatSourcePath;
  // A1 (v1.12): manual markers, in TIMELINE seconds, sorted.
  List<double> _markers = [];
  bool _beatAutoCut = false;
  bool _detectingBeats = false;
  String? _waveformPath;
  bool _waveformBusy = false;

  VoiceFx _fxVoice = VoiceFx.none;
  double _fxFadeIn = 0.0;
  double _fxFadeOut = 0.0;
  bool _muteOriginal = false;
  final bool _fxReverse = false;
  bool _fxSilenceRemove = false;
  bool _fxPip = false;
  String _fxPipVideo = '';
  // PIP inset position/scale — defaults are the long-standing
  // hardcoded values; a timeline handoff replaces them with the
  // channel preset's settings (Phase 7).
  PipPosition _pipPosition = PipPosition.bottomRight;
  double _pipScale = 0.3;
  // v1.16.0 G2 (Motion M3): the PIP window on the timeline —
  // the inset (incl. a Motion "Video par Lagao" overlay, which
  // arrives through this same PIP layer) shows only inside
  // [_pipStartSec, _pipEndSec); _pipEndSec == -1 = to the end.
  // Defaults = the whole timeline (pre-M3 behaviour).
  double _pipStartSec = 0;
  double _pipEndSec = -1;
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
      _proExposure != 0 ||
      _adjustExtraActive;

  RampPreset? _rampPreset() => switch (_proRamp) {
    'slowMiddle' => RampPreset.slowMiddle,
    'slowStart' => RampPreset.slowStart,
    'slowEnd' => RampPreset.slowEnd,
    'pulse' => RampPreset.pulse,
    _ => null,
  };

  /// v1.3.0 (§8): premium ML tools unlock with COINS ONLY — the
  /// ad-unlock path is gone from the whole app. Admins are waived
  /// by CoinService itself.
  ///
  /// Build 9 (v1.7.0, point #6B): the price model changed on the
  /// user's order — instead of a once-per-session 50-coin unlock,
  /// EVERY use of an AI tool (background remover, motion
  /// tracking) now charges the remote-config price
  /// (`ai_tool_price_coins`, default 25) through [AiToolCharge].
  /// Build 9 (point #5): the remote kill switch is checked
  /// first — a killed AI tool shows the polite closed message
  /// and never charges. A failed/insufficient charge keeps the
  /// tool OFF and says why — never a silent pass.
  Future<bool> _ensurePremiumUnlocked() async {
    if (FeatureGate.isKilled(KillableFeature.photoAi)) {
      _setStatus(FeatureGate.killedMessage);
      return false;
    }
    final outcome = await AiToolCharge.chargeWithConfirm(
      context,
      toolLabel: 'AI tools (background remover, motion tracking)',
      reason: AiToolCharge.reasonPhotoAi,
    );
    if (!mounted) return false;
    switch (outcome) {
      case AiChargeOutcome.ok:
        return true;
      case AiChargeOutcome.cancelled:
        return false;
      case AiChargeOutcome.insufficient:
        _setStatus(AiToolCharge.insufficientMessage);
        return false;
      case AiChargeOutcome.failed:
        _setStatus('Charge failed — try again.');
        return false;
    }
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

  /// Tap on the preview media -> normalized (0..1, 0..1) coords.
  ///
  /// Build 2 (Phase 1): EXACT mapping. The gesture detector sits
  /// INSIDE the stage's media subtree (within the canvas frame's
  /// contain rect, under the stage transform), so [TapDownDetails]
  /// .localPosition arrives already in the media box's own
  /// coordinates — Flutter's hit testing inverts the transform —
  /// and dividing by the box size gives the true video-frame
  /// point. The old implementation measured against a fixed 16:9
  /// box through a GlobalKey that was never attached to the stage
  /// (the tap silently never registered); both the approximation
  /// and the dead key are gone.
  void _onPreviewTapDown(TapDownDetails d, Size mediaBox) {
    if (mediaBox.width <= 0 || mediaBox.height <= 0) return;
    final x = (d.localPosition.dx / mediaBox.width).clamp(0.0, 1.0);
    final y = (d.localPosition.dy / mediaBox.height).clamp(0.0, 1.0);
    setState(() {
      // A tap on bare media also clears any stage layer selection.
      _stageLayer = null;
      _trackStartX = x;
      _trackStartY = y;
      _trackPoints = [];
      _status =
          'Object tapped (${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}) — now tap Track.';
    });
  }

  // ---- Build 2 (Phase 1): interactive canvas gestures. ----
  // The stage pinch/pan/rotate writes the §6.7 main-clip transform
  // model ([_tfScale]/[_tfX]/[_tfY]/[_tfRot]) — the same values the
  // Transform panel's sliders edit and the export's transform pass
  // consumes, so what the user sets by hand on the stage is what
  // the export renders. Like the sliders, gestures do not push
  // undo history (the snapshot format has no transform fields);
  // the panel's Reset button restores identity.

  void _onStageScaleStart(ScaleStartDetails d) {
    _pinchTfScale = _tfScale;
    _pinchTfX = _tfX;
    _pinchTfY = _tfY;
    _pinchTfRot = _tfRot;
    _pinchFocalStart = d.focalPoint;
  }

  void _onStageScaleUpdate(ScaleUpdateDetails d) {
    final frame = _stageFrameRect;
    if (frame.width <= 0 || frame.height <= 0) return;
    setState(() {
      // Clamps match the Transform panel sliders exactly, so a
      // value set by hand and a value set by slider live in the
      // same range (the export's own wider clamp still applies).
      if (d.pointerCount >= 2) {
        _tfScale = (_pinchTfScale * d.scale).clamp(0.5, 2.0);
        _tfRot = (_pinchTfRot + d.rotation * 180 / math.pi).clamp(
          -45.0,
          45.0,
        );
      }
      // Pan follows the focal point (one or two fingers); export
      // posX/posY are fractions of the frame, so the pixel delta
      // is divided by the frame size.
      final delta = d.focalPoint - _pinchFocalStart;
      _tfX = (_pinchTfX + delta.dx / frame.width).clamp(-0.5, 0.5);
      _tfY = (_pinchTfY + delta.dy / frame.height).clamp(-0.5, 0.5);
    });
  }

  /// Double-tap on the stage media: reset the canvas transform to
  /// identity (the pinch/pan counterpart of the Transform panel's
  /// Reset button).
  void _resetStageTransform() {
    setState(() {
      _tfScale = 1;
      _tfX = 0;
      _tfY = 0;
      _tfRot = 0;
    });
    _setStatus('Canvas transform reset.');
  }

  /// The stage's render matrix for the main-clip transform:
  /// translate (frame fractions) ∘ rotate (degrees) ∘ scale, about
  /// the frame centre — the same composition the export's
  /// transform pass applies (overlay offset from centre, rotate
  /// about the frame's centre, scaled frame).
  Matrix4 _stageTransformMatrix(Size frameSize) {
    final m = Matrix4.identity();
    m.translateByDouble(
      _tfX * frameSize.width,
      _tfY * frameSize.height,
      0,
      1,
    );
    m.rotateZ(_tfRot * math.pi / 180);
    m.scaleByDouble(_tfScale, _tfScale, 1, 1);
    return m;
  }

  /// The canvas frame's backdrop colour on stage: the chosen fill
  /// colour when Canvas fill = Colour, else black. (Blur fill is
  /// an export render; the stage keeps the plain backdrop.)
  Color _frameBackdropColor() {
    if (_canvasFill != 'color') return Colors.black;
    switch (_canvasFillColor) {
      case 'white':
        return Colors.white;
      case '0x1A1A2E':
        return const Color(0xFF1A1A2E);
      case '0x7C3AED':
        return const Color(0xFF7C3AED);
      default:
        return Colors.black;
    }
  }

  // ---- Build 2 (Phase 2): timeline helpers. ----

  /// Timeline zoom (the − / + buttons in the strip's fixed
  /// column): scales px-per-second around the CURRENT centre, so
  /// the frame under the playhead stays under the playhead.
  void _tlZoomBy(double factor) {
    final old = _tlPxPerSec;
    final next = (old * factor).clamp(12.0, 120.0);
    if (next == old || !_tlScroll.hasClients) {
      if (next != old) setState(() => _tlPxPerSec = next);
      return;
    }
    final centreSec = _tlScroll.offset / old;
    setState(() => _tlPxPerSec = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_tlScroll.hasClients) return;
      final target = (centreSec * next).clamp(
        0.0,
        _tlScroll.position.maxScrollExtent,
      );
      _tlProgrammaticScroll = true;
      try {
        _tlScroll.jumpTo(target);
      } finally {
        _tlProgrammaticScroll = false;
      }
    });
  }

  /// v1.14.0 T1 (A13): zoom the strip to an ABSOLUTE
  /// px-per-second (zoom-to-fit + pinch), keeping the frame
  /// under the centre playhead under the playhead — the same
  /// centre rule as [_tlZoomBy].
  void _tlZoomTo(double pxPerSec) {
    final next = pxPerSec.clamp(12.0, 120.0).toDouble();
    if (next == _tlPxPerSec) return;
    if (!_tlScroll.hasClients) {
      setState(() => _tlPxPerSec = next);
      return;
    }
    final centreSec = _tlScroll.offset / _tlPxPerSec;
    setState(() => _tlPxPerSec = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_tlScroll.hasClients) return;
      final target = (centreSec * next).clamp(
        0.0,
        _tlScroll.position.maxScrollExtent,
      );
      _tlProgrammaticScroll = true;
      try {
        _tlScroll.jumpTo(target);
      } finally {
        _tlProgrammaticScroll = false;
      }
    });
  }

  /// v1.14.0 T1 (A13): pinch on the timeline strip — the base
  /// is captured at gesture start and every update is computed
  /// from it (never accumulated, so the gesture cannot drift).
  void _tlPinchStart() => _tlPinchBasePps = _tlPxPerSec;

  void _tlPinchUpdate(double scale) {
    if (scale <= 0) return;
    _tlZoomTo(_tlPinchBasePps * scale);
  }

  /// v1.14.0 T1 (A14): step the playhead exactly one frame
  /// ([direction] -1 / +1) at the export fps. Playback pauses
  /// first — a frame step is a paused-inspection action, and
  /// seeking a playing player frame-by-frame would fight it
  /// (the Build 4 lesson).
  void _stepFrame(int direction) {
    if (_clips.isEmpty) return;
    final ctrl = _controller;
    if (ctrl != null && ctrl.value.isPlaying) {
      unawaited(ctrl.pause());
    }
    final step = 1.0 / (_exportFps <= 0 ? 30 : _exportFps);
    unawaited(
      _seekToGlobalSec(
        (_globalPositionSec + direction * step)
            .clamp(0.0, _totalDurationSec)
            .toDouble(),
      ),
    );
  }

  /// v1.14.0 T1: the timeline display prefs on their own
  /// SharedPreferences keys (see the field docs for why they
  /// are not in the panel snapshot).
  static const String _tlPrefsKey = 've_tl_prefs_v1';

  Future<void> _loadTimelinePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_tlPrefsKey);
      if (raw == null || !mounted) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _tlSnapOn = m['snap'] as bool? ?? true;
        _tlSnapStrength = ((m['strength'] as num?)?.toInt() ?? 1)
            .clamp(0, 2)
            .toInt();
        _timecodeOn = m['tc'] as bool? ?? false;
      });
    } catch (_) {
      // Prefs are a nicety — defaults stand on any failure.
    }
  }

  void _saveTimelinePrefs() {
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _tlPrefsKey,
          jsonEncode({
            'snap': _tlSnapOn,
            'strength': _tlSnapStrength,
            'tc': _timecodeOn,
          }),
        );
      } catch (_) {}
    }());
  }

  /// The playhead second the timeline strip is centred on —
  /// the strip-centre convention Split already uses, falling
  /// back to the clock's global position before first layout.
  double get _playheadSec {
    if (_tlScroll.hasClients && _tlPxPerSec > 0) {
      return (_tlScroll.offset / _tlPxPerSec)
          .clamp(0.0, _totalDurationSec)
          .toDouble();
    }
    return _globalPositionSec;
  }

  // ---- v1.14.0 T2: trim-mode ops (A6 / A7 / A25). ----

  /// A6 ROLL on the boundary BEFORE clip [boundaryIndex]
  /// (1..len-1): both neighbours' trims move together via
  /// [TimelineMath.rollEdit]; the timeline's total length is
  /// unchanged by construction. Used by the Trim panel's roll
  /// buttons; the timeline's roll handles apply the same math
  /// incrementally during their drags.
  void _rollBoundaryBy(int boundaryIndex, double delta) {
    if (boundaryIndex <= 0 || boundaryIndex >= _clips.length) {
      _setStatus('Roll needs the boundary between two clips '
          'is needed.');
      return;
    }
    final a = _clips[boundaryIndex - 1];
    final b = _clips[boundaryIndex];
    final res = TimelineMath.rollEdit(
      aTrimStart: a.trimStart,
      aEffEnd: a.effectiveEnd,
      aFull: a.duration.inMilliseconds / 1000,
      bTrimStart: b.trimStart,
      bEffEnd: b.effectiveEnd,
      delta: delta,
    );
    if (res == null) {
      _setStatus('Roll cannot go further — one of the clips '
          'the file has ended or too little of the part would be '
          'left.');
      return;
    }
    _pushHistory();
    setState(() {
      a.trimEnd = res.aEnd;
      b.trimStart = res.bStart;
    });
    _setStatus('Roll done — the boundary '
        '${res.delta >= 0 ? '+' : ''}${res.delta.toStringAsFixed(2)}s '
        'moved, the total length is the same.');
    unawaited(_loadPreview());
  }

  /// A7 SLIP on the selected clip by [delta] seconds via
  /// [TimelineMath.slipEdit] — position and length unchanged,
  /// only the used window inside the file moves. Photo clips
  /// have no file range to slide: honest refusal.
  void _slipSelectedBy(double delta) {
    if (_clips.isEmpty) return;
    final clip = _clips[_selected];
    if (clip.isPhoto) {
      _setStatus('Slip does not work on a photo clip — inside it '
          'there is no video portion.');
      return;
    }
    final res = TimelineMath.slipEdit(
      trimStart: clip.trimStart,
      effEnd: clip.effectiveEnd,
      full: clip.duration.inMilliseconds / 1000,
      delta: delta,
    );
    if (res == null) {
      _setStatus('Slip cannot go further — the clip is already at the file '
          'edge.');
      return;
    }
    _pushHistory();
    setState(() {
      clip.trimStart = res.start;
      clip.trimEnd = res.end;
    });
    _setStatus('Slip done — the clip is in place, the inside portion '
        '${res.delta >= 0 ? '+' : ''}${res.delta.toStringAsFixed(2)}s '
        'khiska.');
    unawaited(_loadPreview());
  }

  /// A25: move the selected clip's start edge onto the
  /// playhead (the strip's centre second). The playhead must
  /// sit inside the clip — otherwise an honest refusal, never
  /// a silent different trim.
  void _trimToPlayheadStart() {
    if (_clips.isEmpty) return;
    final clip = _clips[_selected];
    final next = TimelineMath.trimStartToPlayhead(
      clipStartSec: _clipStartSec(_selected),
      playheadSec: _playheadSec,
      trimStart: clip.trimStart,
      effEnd: clip.effectiveEnd,
    );
    if (next == null) {
      _setStatus('The playhead is not inside this clip — first '
          'bring the playhead inside the clip.');
      return;
    }
    _pushHistory();
    setState(() => clip.trimStart = next);
    _setStatus('Clip start trimmed to the playhead.');
    unawaited(_loadPreview());
  }

  /// A25: move the selected clip's end edge onto the playhead.
  void _trimToPlayheadEnd() {
    if (_clips.isEmpty) return;
    final clip = _clips[_selected];
    final next = TimelineMath.trimEndToPlayhead(
      clipStartSec: _clipStartSec(_selected),
      playheadSec: _playheadSec,
      trimStart: clip.trimStart,
      effEnd: clip.effectiveEnd,
    );
    if (next == null) {
      _setStatus('The playhead is not inside this clip — first '
          'bring the playhead inside the clip.');
      return;
    }
    _pushHistory();
    setState(() => clip.trimEnd = next);
    _setStatus('Clip end trimmed to the playhead.');
    unawaited(_loadPreview());
  }

  // ---- v1.14.0 T3: multi-select + range ops (A4 / A5). ----

  void _toggleMultiSelect(int i) {
    if (i < 0 || i >= _clips.length) return;
    setState(() {
      if (_multiSelect.contains(i)) {
        _multiSelect.remove(i);
      } else {
        _multiSelect.add(i);
      }
      _selected = i;
    });
    HapticFeedback.selectionClick();
  }

  void _clearMultiSelect() {
    if (_multiSelect.isEmpty) return;
    setState(() => _multiSelect.clear());
  }

  /// A4: delete every ticked clip in ONE history step.
  Future<void> _deleteMultiSelected() async {
    if (_multiSelect.isEmpty || _busy) return;
    final doomed = _multiSelect.where((i) => i < _clips.length).toSet();
    if (doomed.isEmpty) return;
    _pushHistory();
    setState(() {
      final kept = <VideoClip>[
        for (var i = 0; i < _clips.length; i++)
          if (!doomed.contains(i)) _clips[i],
      ];
      _clips
        ..clear()
        ..addAll(kept);
      _multiSelect.clear();
      if (_selected >= _clips.length) {
        _selected = _clips.isEmpty ? 0 : _clips.length - 1;
      }
      if (_clips.isEmpty) _clipRow = false;
    });
    if (_clips.isNotEmpty) {
      await _loadPreview();
    } else {
      await _controller?.dispose();
      if (mounted) setState(() => _controller = null);
    }
    _setStatus('${doomed.length} clips deleted — Undo '
        'can bring them back.');
  }

  /// A4: duplicate every ticked clip right after itself, in
  /// ONE history step. Indices are processed back-to-front so
  /// earlier inserts never shift the ones still to do.
  void _duplicateMultiSelected() {
    if (_multiSelect.isEmpty) return;
    final idx = _multiSelect.where((i) => i < _clips.length).toList()
      ..sort();
    if (idx.isEmpty) return;
    _pushHistory();
    setState(() {
      for (final i in idx.reversed) {
        _clips.insert(i + 1, _clips[i].copy());
      }
      _multiSelect.clear();
    });
    _setStatus('${idx.length} clips duplicated.');
    unawaited(_loadPreview());
  }

  /// A4: move every ticked clip one step in [direction]
  /// (-1 / +1) via [TimelineMath.multiMoveOrder]; the ticked
  /// set follows the clips to their new indices.
  void _moveMultiSelected(int direction) {
    if (_multiSelect.isEmpty || _clips.length < 2) return;
    final order = TimelineMath.multiMoveOrder(
      count: _clips.length,
      selected: _multiSelect,
      direction: direction,
    );
    if (order.asMap().entries.every((e) => e.value == e.key)) {
      _setStatus('These clips cannot move further this way.');
      return;
    }
    // The ticked set at the clips' NEW positions — computed
    // BEFORE the set is touched (a cascade clear would eat it).
    final newSel = <int>{
      for (var pos = 0; pos < order.length; pos++)
        if (_multiSelect.contains(order[pos])) pos,
    };
    _pushHistory();
    setState(() {
      final moved = [for (final old in order) _clips[old]];
      _clips
        ..clear()
        ..addAll(moved);
      _multiSelect
        ..clear()
        ..addAll(newSel);
      _selected = newSel.isEmpty
          ? _selected.clamp(0, _clips.length - 1)
          : newSel.reduce((a, b) => a < b ? a : b);
    });
    _setStatus('Clips moved.');
    unawaited(_loadPreview());
  }

  /// A5: set the range In point at the playhead. Setting In
  /// past an existing Out (or Out before an existing In)
  /// clears the other point — a backwards range is never
  /// stored (the delete/loop math assumes In < Out).
  void _setRangeInAtPlayhead() {
    if (_clips.isEmpty) return;
    final t = _playheadSec;
    setState(() {
      _rangeIn = t;
      if (_rangeOut != null && _rangeOut! <= t) _rangeOut = null;
    });
    _setStatus('Range In point set '
        '(${TimelineMath.formatTimecode(t, _exportFps)}).');
  }

  void _setRangeOutAtPlayhead() {
    if (_clips.isEmpty) return;
    final t = _playheadSec;
    setState(() {
      _rangeOut = t;
      if (_rangeIn != null && _rangeIn! >= t) _rangeIn = null;
    });
    _setStatus('Range Out point set '
        '(${TimelineMath.formatTimecode(t, _exportFps)}).');
  }

  void _clearRange() {
    setState(() {
      _rangeIn = null;
      _rangeOut = null;
      _loopRange = false;
    });
    _setStatus('Range cleared.');
  }

  /// A5: delete the marked range from the timeline — clips
  /// are removed / trimmed / split per
  /// [TimelineMath.rangeDeletePlan], in ONE history step.
  /// The range itself is consumed by the delete.
  Future<void> _deleteRange() async {
    final inSec = _rangeIn;
    final outSec = _rangeOut;
    if (inSec == null || outSec == null || outSec <= inSec) {
      _setStatus('Set both the In and Out points first.');
      return;
    }
    if (_clips.isEmpty || _busy) return;
    final plan = TimelineMath.rangeDeletePlan(
      clipStarts: [
        for (var i = 0; i < _clips.length; i++) _clipStartSec(i),
      ],
      effDurations: _effectiveDurations,
      trimStarts: [for (final c in _clips) c.trimStart],
      rangeIn: inSec,
      rangeOut: outSec,
    );
    _pushHistory();
    var removed = 0;
    var split = 0;
    setState(() {
      final next = <VideoClip>[];
      for (var i = 0; i < _clips.length; i++) {
        final clip = _clips[i];
        final action = plan[i];
        switch (action.kind) {
          case RangeActionKind.keep:
            next.add(clip);
          case RangeActionKind.remove:
            removed++;
          case RangeActionKind.trimLeft:
            clip.trimStart = action.trimStart!;
            next.add(clip);
          case RangeActionKind.trimRight:
            clip.trimEnd = action.effEnd!;
            next.add(clip);
          case RangeActionKind.split:
            split++;
            final right = clip.copy();
            right.trimStart = action.trimStart!;
            right.trimEnd = clip.effectiveEnd;
            clip.trimEnd = action.effEnd!;
            next
              ..add(clip)
              ..add(right);
        }
      }
      _clips
        ..clear()
        ..addAll(next);
      if (_selected >= _clips.length) {
        _selected = _clips.isEmpty ? 0 : _clips.length - 1;
      }
      if (_clips.isEmpty) _clipRow = false;
      _multiSelect.clear();
      _rangeIn = null;
      _rangeOut = null;
      _loopRange = false;
    });
    if (_clips.isNotEmpty) {
      await _loadPreview();
    } else {
      await _controller?.dispose();
      if (mounted) setState(() => _controller = null);
    }
    _setStatus('Range deleted — $removed clip(s) '
        'removed, $split clip(s) cut into two parts. Undo '
        'can bring it back.');
  }

  /// Live scrub (Phase 2): while the user drags the strip with
  /// playback paused, seek the preview to the centred frame —
  /// debounced so the player is not flooded with seeks. The
  /// ScrollEnd seek (with its boundary snap) still lands the
  /// final position.
  void _scheduleScrubSeek() {
    if (_clock.isPlaying || !_tlUserScrolling) return;
    _scrubSeekTimer?.cancel();
    _scrubSeekTimer = Timer(const Duration(milliseconds: 90), () {
      if (!mounted || _clock.isPlaying || !_tlScroll.hasClients) return;
      unawaited(_seekToGlobalSec(_tlScroll.offset / _tlPxPerSec));
    });
  }

  /// Music-lane waveform (Phase 2): render the music file's
  /// showwavespic PNG once per file (cached in the work dir),
  /// used as the audio lane's background. Any failure leaves the
  /// lane exactly as it was (plain block + file name).
  Future<void> _ensureMusicWave(String musicPath) async {
    if (_musicWaveCache.containsKey(musicPath) ||
        _musicWavePending.contains(musicPath)) {
      return;
    }
    _musicWavePending.add(musicPath);
    try {
      final dir = await _workDir();
      final key =
          '${p.basenameWithoutExtension(musicPath)}_${musicPath.hashCode.abs()}';
      final out = p.join(dir.path, 'music_wave_$key.png');
      if (await File(out).exists()) {
        _musicWaveCache[musicPath] = out;
        if (mounted) setState(() {});
        return;
      }
      final result = await FfmpegService.run(
        '-y -i ${FfmpegService.q(musicPath)} -filter_complex '
        '"showwavespic=s=640x44:colors=0xFFD60A" '
        '-frames:v 1 ${FfmpegService.q(out)}',
      );
      _musicWaveCache[musicPath] =
          (result.ok && await File(out).exists()) ? out : '';
      if (mounted) setState(() {});
    } catch (_) {
      _musicWaveCache[musicPath] = '';
    } finally {
      _musicWavePending.remove(musicPath);
    }
  }

  // v1.16.0 G4 (A16): per-clip waveform — the clip's REAL audio
  // (its trimmed range) rendered once via showwavespic and
  // cached in the work dir, keyed by path + trim, so scrolling
  // the timeline never re-renders. A clip with no audio stream
  // fails the render and simply shows no wave ('' in cache).
  final Map<String, String> _clipWaveCache = {};
  final Set<String> _clipWavePending = {};

  String _clipWaveKey(VideoClip clip) =>
      '${clip.file.path}|${(clip.trimStart * 10).round()}|'
      '${(clip.effectiveDuration * 10).round()}';

  Future<void> _ensureClipWave(VideoClip clip) async {
    if (clip.isPhoto) return;
    final key = _clipWaveKey(clip);
    if (_clipWaveCache.containsKey(key) || _clipWavePending.contains(key)) {
      return;
    }
    _clipWavePending.add(key);
    try {
      final dir = await _workDir();
      final out = p.join(
        dir.path,
        'clip_wave_${key.hashCode.abs()}.png',
      );
      if (await File(out).exists()) {
        _clipWaveCache[key] = out;
        if (mounted) setState(() {});
        return;
      }
      final result = await FfmpegService.run(
        '-y -ss ${clip.trimStart.toStringAsFixed(3)} '
        '-t ${clip.effectiveDuration.toStringAsFixed(3)} '
        '-i ${FfmpegService.q(clip.file.path)} -filter_complex '
        '"showwavespic=s=640x36:colors=0x90CAF9" '
        '-frames:v 1 ${FfmpegService.q(out)}',
      );
      _clipWaveCache[key] =
          (result.ok && await File(out).exists()) ? out : '';
      if (mounted) setState(() {});
    } catch (_) {
      _clipWaveCache[key] = '';
    } finally {
      _clipWavePending.remove(key);
    }
  }

  // Long-press drag reorder (Phase 2). The press still opens the
  // swap sheet when it does not move (the original path); once it
  // moves past a neighbour's midpoint the clips swap live, one
  // history entry for the whole drag (pushed at press start).

  void _onClipDragStart(int i) {
    if (_mainTrackLocked) return;
    _pushHistory();
    _dragClipIndex = i;
    _dragOriginStartSec = _clipStartSec(i);
    _dragMoved = false;
  }

  void _onClipDragMove(LongPressMoveUpdateDetails d) {
    final from = _dragClipIndex;
    if (from == null || _mainTrackLocked) return;
    final dxSec = d.offsetFromOrigin.dx / _tlPxPerSec;
    if (dxSec.abs() < 0.05) return;
    final dragged = _clips[from];
    // The dragged clip's centre in absolute timeline seconds,
    // measured from its ORIGINAL slot (invariant across swaps —
    // the current slot start moves with every swap, the origin
    // does not). The midpoint walk itself is TimelineMath's.
    final centre =
        _dragOriginStartSec + dragged.effectiveDuration / 2 + dxSec;
    final idx = TimelineMath.dragTargetIndex(
      _effectiveDurations,
      from,
      centre,
    );
    if (idx == from) return;
    _dragMoved = true;
    setState(() {
      final clip = _clips.removeAt(from);
      _clips.insert(idx, clip);
      _selected = idx;
      _dragClipIndex = idx;
    });
    HapticFeedback.selectionClick();
  }

  void _onClipDragEnd(int i) {
    final wasDrag = _dragMoved;
    _dragClipIndex = null;
    _dragMoved = false;
    if (wasDrag) {
      // One preview reload for the whole drag (the swaps above
      // deliberately do not reload per step).
      unawaited(_loadPreview());
    } else {
      // Stationary long press: the original swap-sheet path.
      showSwapSheet(this, i);
    }
  }

  Future<void> _trackObject() async {
    if (_clips.isEmpty || _trackStartX == null || _trackStartY == null) {
      _setStatus('Tap the object on the preview first.');
      return;
    }
    if (_tracking || _busy) return;
    if (!await _ensurePremiumUnlocked()) return;
    setState(() {
      _tracking = true;
      _status = 'Tracking object…';
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
            _setStatus('Tracking… $pct% done, ${100 - pct}% remaining');
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _trackPoints = points;
        _status = points.isEmpty
            ? 'Object could not be tracked — tap again and try.'
            : '${points.length} track points found.';
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
      _status = 'Finding beats…';
    });
    try {
      final dir = await _workDir();
      final input = _musicPath ?? _clips[_selected].file.path;
      final fromMusic = _musicPath != null;
      final beats = await detectBeats(input: input, workDir: dir);
      if (!mounted) return;
      setState(() {
        _beats = beats;
        _beatSourceMusic = fromMusic;
        _beatSourcePath = input;
        _status = beats.isEmpty
            ? 'No beats found.'
            : '${beats.length} beats found.';
      });
    } catch (e) {
      _setStatus('Beat detect failed: $e');
    } finally {
      if (mounted) setState(() => _detectingBeats = false);
    }
  }

  /// A1 (v1.12): drop a manual marker at the playhead the user
  /// sees (the timeline clock position). Markers are timeline
  /// seconds, kept sorted; a second marker within 0.05 s of an
  /// existing one is refused instead of stacking invisibly.
  void _addMarkerAtPlayhead() {
    if (_clips.isEmpty) {
      _setStatus('Add a clip first.');
      return;
    }
    final t = _globalPositionSec.clamp(0.0, _totalDurationSec).toDouble();
    if (_markers.any((m) => (m - t).abs() < 0.05)) {
      _setStatus('A marker already exists at this spot.');
      return;
    }
    _pushHistory();
    setState(() {
      _markers = [..._markers, t]..sort();
    });
    HapticFeedback.selectionClick();
    _setStatus('Marker added — at ${t.toStringAsFixed(1)}s.');
  }

  /// A1 (v1.12): remove one manual marker (Beats panel list).
  void _removeMarker(double sec) {
    if (!_markers.any((m) => (m - sec).abs() < 0.001)) return;
    _pushHistory();
    setState(() {
      _markers = _markers.where((m) => (m - sec).abs() >= 0.001).toList();
    });
    _setStatus('Marker removed.');
  }

  /// A2 (v1.12): import captions from an .srt / .vtt file. The
  /// file's timings describe the WHOLE video, so imported
  /// segments are timeline-relative (the handoff flag). Existing
  /// captions are only replaced after an explicit confirmation —
  /// never silently wiped; a file with no readable captions
  /// changes nothing.
  Future<void> _importCaptionsFile() async {
    if (_busy) {
      explainToolTap();
      return;
    }
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['srt', 'vtt'],
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      final segments = CaptionService.parseSubtitle(utf8.decode(bytes));
      if (!mounted) return;
      if (segments.isEmpty) {
        _setStatus(
          'No captions found in this file — check the file. '
          'Your existing captions are safe.',
        );
        return;
      }
      if (_captions.isNotEmpty) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Replace captions?'),
            content: Text(
              'Is file ke ${segments.length} segments mojooda '
              '${_captions.length} captions will replace them.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Keep them'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Replace'),
              ),
            ],
          ),
        );
        if (replace != true || !mounted) return;
      }
      setState(() {
        _captions = segments;
        _captionsTimelineRelative = true;
        _status = '${segments.length} caption segments imported.';
      });
    } catch (e) {
      if (mounted) _setStatus('Caption import failed: $e');
    }
  }

  /// A2 (v1.12): write the current captions as an .srt / .vtt
  /// file and hand it to the system share sheet. The segments
  /// are shared exactly as the editor holds them (the same list
  /// the Edit dialog shows), so the file round-trips back
  /// through Import unchanged.
  Future<void> _shareCaptionsFile(String kind) async {
    if (_captions.isEmpty) {
      _setStatus('Create or import captions first.');
      return;
    }
    try {
      final dir = await _workDir();
      final isVtt = kind == 'vtt';
      final content = isVtt
          ? CaptionService.buildVtt(_captions)
          : CaptionService.buildSrt(_captions);
      final out = File(
        '${dir.path}/tj_pro_captions.${isVtt ? 'vtt' : 'srt'}',
      );
      await out.writeAsString(content);
      await SharePlus.instance.share(ShareParams(files: [XFile(out.path)]));
    } catch (e) {
      if (mounted) _setStatus('Caption share failed: $e');
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
      _setStatus('Let the clip preview load first.');
      return;
    }
    final int idx = _selected < _clips.length ? _selected : 0;
    final VideoClip clip = _clips[idx];
    final double posSec = ctrl.value.position.inMilliseconds / 1000.0;
    final double seekSec = posSec.clamp(
      0.0,
      clip.duration.inMilliseconds / 1000.0,
    );
    setState(() {
      _busy = true;
      _status = 'Saving frame…';
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
      _setStatus('Frame photo saved to the gallery.');
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
      _status = 'Extracting audio…';
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
      _setStatus('Audio extracted.');
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
      _status = 'Building waveform…';
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
            ? 'Waveform not built — no audio found.'
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
      final w =
          (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      final h =
          (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
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
    final hasTrack = _trackPoints.isNotEmpty && _trackSticker.trim().isNotEmpty;
    if (!hasTitle && !hasSticker && !hasTrack) return null;
    // Export dims approximated from the first clip's aspect (same
    // approximation as the multi-clip normalize step); the aspect
    // setting can change the real frame size. Aligned with the
    // Export quality setting so keyframed/title positions stay
    // proportional at 1080p and 4K.
    final portrait = _clips.isEmpty ? true : _clips.first.aspectRatio < 1.0;
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
      final t = await titleSpec(_proTitle, _proTitlePreset, _proTitlePosition);
      final png = await renderTitlePng(t, dir: dir);
      steps.add(_OverlayStep(png: png, keyframed: useKeyframes, title: t));
    }
    if (hasSticker) {
      final t = await titleSpec(_proSticker, _proStickerPreset, 'center');
      final png = await renderTitlePng(t, dir: dir);
      steps.add(
        _OverlayStep(png: png, keyframed: useKeyframes && !hasTitle, title: t),
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
    // v1.5.0: while the clock says "playing", keep the timeline
    // strip scrolled so the playhead stays at the centre — unless
    // the user is dragging the strip themselves.
    _clock.addListener(_onClockTick);
    _clock.addListener(_syncPipWindow);
    // Plain editor only: a handoff project brings its own template
    // ([_loadProject] below) — the saved live template must NOT
    // overwrite it when this future resolves.
    NewsTemplate.load().then((t) {
      if (mounted && widget.project == null) setState(() => _news = t);
    });
    if (widget.project != null) {
      _loadProject(widget.project!, widget.preset);
    } else if (widget.initialVideoPath != null) {
      unawaited(_loadInitialVideo());
    } else if (widget.initialPipVideoPath == null) {
      // Build 10 (7F): a plain open may have a crashed/killed
      // session to offer back. Project / hub opens bring their
      // own content and are never offered a draft over it.
      unawaited(_offerSessionRestore());
    }
    // v1.14.0 T1: the timeline display prefs (snap on/strength,
    // timecode) survive relaunches on their own keys — they are
    // NOT part of the panel snapshot, so a panel Cancel can
    // never silently flip them.
    unawaited(_loadTimelinePrefs());
    // Motion M2: a "Video par Lagao" handoff arrives as the PIP
    // element, whatever else the editor opened with.
    final pipHandoff = widget.initialPipVideoPath;
    if (pipHandoff != null && File(pipHandoff).existsSync()) {
      _fxPip = true;
      _fxPipVideo = pipHandoff;
    }
    _sessionTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_saveSessionSnapshot()),
    );
  }

  /// Build 10 (7F): persist the current timeline + panel
  /// state as the rolling recovery draft. An emptied timeline
  /// clears a draft WE wrote this session (the work is done /
  /// discarded); a stored draft from BEFORE this session is
  /// left alone here — it is the restore offer's business.
  Future<void> _saveSessionSnapshot() async {
    await SafeOps.guard('editor.session_save', () async {
      if (_clips.isEmpty) {
        if (_lastSessionJson.isNotEmpty) {
          _lastSessionJson = '';
          await VideoEditorRecoveryStore.clear();
        }
        return;
      }
      final session = VideoEditorSession(
        clips: _clips.map(VideoEditorSession.clipToMap).toList(),
        panel: _panelSnapshot(),
        selected: _selected,
        savedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      final json = session.encode();
      if (json == _lastSessionJson) return;
      _lastSessionJson = json;
      await VideoEditorRecoveryStore.save(json);
    });
  }

  /// Build 10 (7F): when a fresh-enough stored session exists
  /// and at least one of its clip files survives, offer it —
  /// once — via a SnackBar action. Ignoring the offer keeps
  /// the draft stored (it is offered again next open, until
  /// new work overwrites it or it ages out).
  Future<void> _offerSessionRestore() async {
    if (_restoreOffered) return;
    _restoreOffered = true;
    final raw = await VideoEditorRecoveryStore.load();
    if (raw == null || !mounted) return;
    final session = VideoEditorSession.decode(raw);
    if (session == null || session.clips.isEmpty) return;
    if (!session.isFresh(DateTime.now())) {
      await VideoEditorRecoveryStore.clear();
      return;
    }
    var anyExists = false;
    for (final m in session.clips) {
      final path = m['path'];
      if (path is String && await File(path).exists()) {
        anyExists = true;
        break;
      }
    }
    if (!anyExists || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: const Text('Unfinished previous work found.'),
        action: SnackBarAction(
          label: 'Restore',
          onPressed: () => unawaited(_restoreSession(session)),
        ),
      ),
    );
  }

  /// Build 10 (7F): rebuild the timeline from a stored
  /// session — clips whose files survive (stored duration /
  /// aspect, no re-probe needed), then the panel snapshot,
  /// then the preview. Runs through SafeOps (7C): a corrupt
  /// snapshot fails alone with a status line.
  Future<void> _restoreSession(VideoEditorSession session) async {
    final result = await SafeOps.run<int>(
      'editor.session_restore',
      () async {
        var count = 0;
        final restored = <VideoClip>[];
        for (final m in session.clips) {
          final clip = VideoEditorSession.clipFromMap(m);
          if (clip == null) continue;
          if (!await clip.file.exists()) continue;
          restored.add(clip);
          count++;
        }
        if (count == 0) return 0;
        if (!mounted) return 0;
        setState(() {
          _clips
            ..clear()
            ..addAll(restored);
          _selected = session.selected.clamp(0, _clips.length - 1);
        });
        _restorePanelSnapshot(session.panel);
        return count;
      },
    );
    if (!mounted) return;
    if (result.ok && (result.value ?? 0) > 0) {
      // The restored state becomes the live draft again.
      _lastSessionJson = '';
      await _loadPreview();
      setState(
        () => _status = 'Previous work restored (${result.value} clips).',
      );
      _flashStatus();
    } else {
      setState(() => _status = 'Previous work could not be restored.');
      _flashStatus();
    }
  }

  /// Projects hub (v1.4.0): load [VideoEditorScreen.initialVideoPath]
  /// as the first timeline clip, through the SAME probe + add path
  /// as a gallery pick ([_addClipFile]). A missing file is reported
  /// in the status line and the editor stays open, empty and usable
  /// — never a crash, never a silent drop.
  Future<void> _loadInitialVideo() async {
    final path = widget.initialVideoPath;
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) {
      if (mounted) {
        setState(() => _status = 'Hub video not found: $path');
        _flashStatus();
      }
      return;
    }
    await _addClipFile(file);
  }

  /// Timeline handoff (Phase 7): loads [project] into the editor —
  /// clips (probed for duration/aspect like the gallery picker does),
  /// voiceover, template + ticker, captions, and the preset's chroma
  /// + PIP settings. Missing clip files are reported in the status
  /// line, never silently dropped. A failure here never crashes the
  /// screen: the editor stays usable as a plain editor.
  Future<void> _loadProject(NewsProject project, ChannelPreset? preset) async {
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
      _status = 'Loading project…';
    });
    // Bundled chroma backdrop (newsroom / studio desk): materialise
    // the asset to a file, like the LUT loader does — FFmpeg cannot
    // read Flutter assets directly.
    if (handoff.chromaBackgroundAsset != null) {
      try {
        final dir = await _workDir();
        final bgFile = await ensureLutFile(handoff.chromaBackgroundAsset!, dir);
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
            _status = 'Note: the chroma background did not load; a solid background will be used.';
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
      _status =
          'Project loaded: $loaded clip(s)'
          '${handoff.voiceoverPath == null ? '' : ' • voiceover tayyar'}'
          '${dropped.isEmpty ? '' : ' • ${dropped.length} clip file(s) nahi mili'}';
    });
    if (_clips.isNotEmpty) await _loadPreview();
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    // Build 10 (7F): one last draft save on the way out — the
    // latest work is always the stored draft (CapCut-style);
    // the restore offer on the next plain open is opt-in.
    unawaited(_saveSessionSnapshot());
    _clock.removeListener(_onClockTick);
    _clock.removeListener(_syncPipWindow);
    _detachTrimBinding();
    _clock.dispose();
    _scrubSeekTimer?.cancel();
    _tlScroll.dispose();
    _controller?.dispose();
    _pipController?.dispose();
    super.dispose();
  }

  /// Clock listener (playback only): auto-scroll the timeline strip
  /// so the centred playhead tracks the playing position (#29).
  void _onClockTick() {
    if (!mounted || _tlUserScrolling || !_clock.isPlaying) return;
    if (!_tlScroll.hasClients || _clips.isEmpty) return;
    // v1.14.0 T3 (A5): loop-range playback — when the playhead
    // runs past the Out point it jumps back to the In point.
    // Only while playing (this listener never runs paused), so
    // a user's scrub is never fought — the Build 4 rule.
    if (_loopRange &&
        _rangeIn != null &&
        _rangeOut != null &&
        _rangeOut! > _rangeIn! &&
        _globalPositionSec >= _rangeOut! - 0.02) {
      unawaited(_seekToGlobalSec(_rangeIn!));
      return;
    }
    final target = (_globalPositionSec * _tlPxPerSec).clamp(
      0.0,
      _tlScroll.position.maxScrollExtent,
    );
    if ((target - _tlScroll.offset).abs() > 1) {
      _tlProgrammaticScroll = true;
      try {
        _tlScroll.jumpTo(target);
      } finally {
        _tlProgrammaticScroll = false;
      }
    }
  }

  // v1.16.0 G2 (Motion M3): keep the PIP preview's playback
  // phase aligned with its window — the inset starts at its
  // own 0 when the window starts and loops inside it
  // (TimelineMath.pipLocalTime). Only a drift over 0.4 s is
  // corrected, throttled to 4x/sec, and only while the main
  // clock is playing, so scrubbing is never fought.
  DateTime _lastPipSync = DateTime.fromMillisecondsSinceEpoch(0);

  void _syncPipWindow() {
    if (!mounted || !_clock.isPlaying || !_fxPip) return;
    final pc = _pipController;
    if (pc == null || !pc.value.isInitialized) return;
    final total = _totalDurationSec;
    if (total <= 0) return;
    final w = TimelineMath.pipWindowClamp(
      start: _pipStartSec,
      end: _pipEndSec,
      totalDur: total,
    );
    final t = _globalPositionSec;
    if (!TimelineMath.pipVisibleAt(t: t, start: w.start, end: w.end)) {
      return;
    }
    final pipDur = pc.value.duration.inMilliseconds / 1000;
    final want =
        TimelineMath.pipLocalTime(t: t, start: w.start, pipDur: pipDur);
    final have = pc.value.position.inMilliseconds / 1000;
    if ((want - have).abs() < 0.4) return;
    final now = DateTime.now();
    if (now.difference(_lastPipSync).inMilliseconds < 250) return;
    _lastPipSync = now;
    unawaited(pc.seekTo(Duration(milliseconds: (want * 1000).round())));
  }

  /// The export overlay gate for the PIP window: '' when the
  /// window is the whole timeline (historical path), else the
  /// `:enable='between(t,S,E)'` suffix for an overlay filter.
  String get _pipEnableSuffix {
    final total = _totalDurationSec;
    if (TimelineMath.pipWindowIsFull(
      start: _pipStartSec,
      end: _pipEndSec,
      totalDur: total,
    )) {
      return '';
    }
    final w = TimelineMath.pipWindowClamp(
      start: _pipStartSec,
      end: _pipEndSec,
      totalDur: total,
    );
    return ":enable='between(t,${w.start.toStringAsFixed(3)},"
        "${w.end.toStringAsFixed(3)})'";
  }

  // ---- v1.5.0 timeline model: the ONE source of durations. ----
  // Build 2 (Phase 2): the arithmetic now lives in [TimelineMath]
  // (editor_stage.dart) so the #5/#29/#30 invariants are pinned by
  // unit tests; these members keep their exact old semantics by
  // delegating to it.

  /// Effective durations in order — the list form of the ONE
  /// timeline model.
  List<double> get _effectiveDurations =>
      _clips.map((c) => c.effectiveDuration).toList();

  /// Total timeline length (seconds) — the sum of every clip's
  /// effective (trimmed) duration, in order. EVERY readout
  /// (transport, panels, timeline) derives from this.
  double get _totalDurationSec =>
      TimelineMath.totalSec(_effectiveDurations);

  /// Timeline position (seconds) where clip [index] starts.
  double _clipStartSec(int index) =>
      TimelineMath.startSec(_effectiveDurations, index);

  /// A1 (v1.12): every snap target on the timeline, in timeline
  /// seconds — clip boundaries + detected beats (mapped from
  /// their source file) + manual markers. The resting playhead,
  /// Split and the trim handles all snap against this one list.
  List<double> get _snapPoints => [
        ...TimelineMath.boundaries(_effectiveDurations),
        ...timelineBeats,
        ..._markers,
      ];

  /// The playhead's position on the TIMELINE (seconds): the
  /// selected clip's start + the clock position inside its trimmed
  /// range. Photo clips have no clock — their start is the best
  /// position (selecting the clip is what the user sees).
  double get _globalPositionSec {
    if (_clips.isEmpty) return 0;
    final clip = _clips[_selected];
    var inside = 0.0;
    if (!clip.isPhoto && _clock.isInitialized) {
      inside = (_clock.filePositionSec - clip.trimStart).clamp(
        0.0,
        clip.effectiveDuration,
      );
    }
    return _clipStartSec(_selected) + inside;
  }

  /// Seek the preview to a TIMELINE position (seconds): selects the
  /// clip containing it (loading its preview when needed) and seeks
  /// inside the clip's trimmed range (#29 — scrubbing and tapping
  /// the timeline move the preview to the exact frame).
  Future<void> _seekToGlobalSec(double sec) async {
    if (_clips.isEmpty) return;
    final target = sec.clamp(0.0, _totalDurationSec);
    final index = TimelineMath.indexAtSec(_effectiveDurations, target);
    final clip = _clips[index];
    final inside = (target - _clipStartSec(index)).clamp(
      0.0,
      clip.effectiveDuration,
    );
    if (index != _selected) {
      setState(() {
        _selected = index;
        _elementRow = false;
      });
      await _loadPreview();
    }
    final controller = _controller;
    if (controller != null && controller.value.isInitialized && !clip.isPhoto) {
      await controller.seekTo(
        Duration(milliseconds: ((clip.trimStart + inside) * 1000).round()),
      );
    }
  }

  /// Filmstrip cache key: path + size + mtime (Build 2 cache
  /// hardening) — a processed copy written over the same path
  /// never shows the OLD clip's thumbnails. P0-2: the TRIM RANGE
  /// is part of the key too — after a split, both halves point
  /// at the same file with the same stamp, and without the trim
  /// in the key they shared ONE filmstrip, so the split was
  /// invisible in the timeline.
  String _thumbKey(VideoClip clip) {
    var stamp = 'nostat';
    try {
      final st = clip.file.statSync();
      stamp = '${st.size}:${st.modified.millisecondsSinceEpoch}';
    } catch (_) {
      // Keep the fallback stamp; generation below still guards
      // every failure silently.
    }
    return '${clip.file.path}|$stamp'
        '|${clip.trimStart.toStringAsFixed(2)}'
        '|${clip.effectiveEnd.toStringAsFixed(2)}';
  }

  /// Lazily generate filmstrip thumbnails for [clip] (up to 8
  /// frames spread over its effective range) into the work dir.
  /// Fire-and-forget: the timeline renders plain blocks until the
  /// thumbs land, then rebuilds. Failures are silent — a clip
  /// without thumbs is still fully editable.
  Future<void> _ensureThumbs(VideoClip clip) async {
    final key = _thumbKey(clip);
    if (_thumbCache.containsKey(key)) return;
    _thumbCache[key] = const [];
    try {
      final dir = await _workDir();
      final thumbsDir = Directory(p.join(dir.path, 'thumbs'));
      if (!await thumbsDir.exists()) await thumbsDir.create(recursive: true);
      final stamp = key.hashCode.toUnsigned(31).toRadixString(36);
      final paths = <String>[];
      if (clip.isPhoto) {
        paths.add(clip.file.path);
      } else {
        const count = 8;
        for (var i = 0; i < count; i++) {
          final rawT =
              clip.trimStart +
              clip.effectiveDuration * (i / (count - 1)) -
              (i == count - 1 ? 0.05 : 0);
          final t = rawT.clamp(clip.trimStart, clip.effectiveEnd);
          final out = p.join(thumbsDir.path, 'th_${stamp}_$i.jpg');
          if (!await File(out).exists()) {
            final res = await FfmpegService.run(
              '-y -ss ${t.toStringAsFixed(2)} -i ${FfmpegService.q(clip.file.path)} '
              '-frames:v 1 -vf scale=96:-1 -q:v 4 ${FfmpegService.q(out)}',
            );
            if (!res.ok) break;
          }
          paths.add(out);
        }
      }
      if (!mounted) return;
      setState(() => _thumbCache[key] = paths);
    } catch (_) {
      // Thumbnails are decoration — never an error path.
    }
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

  /// P0-2: the trim-range binding for the preview player. The
  /// player loops the clip's whole FILE (setLooping(true)), so
  /// without a binding its position walks past the trim end and
  /// every position reader (the old Split above all) sees a
  /// meaningless time. This listener keeps the playhead inside
  /// the SELECTED clip's trim range: past the end it wraps to
  /// the trim start (the loop the user expects), before the
  /// start it seeks forward. It reads the clip's CURRENT trim
  /// fields on every tick, so a trim edit binds immediately.
  VideoPlayerController? _trimBoundController;
  DateTime _lastTrimSeek = DateTime.fromMillisecondsSinceEpoch(0);

  void _attachTrimBinding(VideoPlayerController c) {
    _detachTrimBinding();
    _trimBoundController = c;
    c.addListener(_enforceTrimRange);
  }

  void _detachTrimBinding() {
    _trimBoundController?.removeListener(_enforceTrimRange);
    _trimBoundController = null;
  }

  void _enforceTrimRange() {
    final c = _trimBoundController;
    if (c == null || !c.value.isInitialized || _clips.isEmpty) return;
    final clip = _clips[_selected];
    if (clip.isPhoto) return;
    final pos = c.value.position.inMilliseconds / 1000;
    final start = clip.trimStart;
    final end = clip.effectiveEnd;
    if (pos < start - 0.05) {
      _guardedTrimSeek(c, start);
    } else if (pos >= end - 0.02 && c.value.isPlaying) {
      _guardedTrimSeek(c, start);
    }
  }

  void _guardedTrimSeek(VideoPlayerController c, double sec) {
    final now = DateTime.now();
    if (now.difference(_lastTrimSeek).inMilliseconds < 300) return;
    _lastTrimSeek = now;
    unawaited(c.seekTo(Duration(milliseconds: (sec * 1000).round())));
  }

  Future<void> _loadPreview() async {
    if (_clips.isEmpty) return;
    // v1.5.0: filmstrip thumbs for the timeline (lazy, cached).
    // Build 2: pre-generate for EVERY clip, not just the selected
    // one (each call is idempotent and cache-guarded), so timeline
    // scrolling never waits on an unselected clip's strip.
    for (final c in _clips) {
      unawaited(_ensureThumbs(c));
    }
    // v1.3.0 (§6.1): a photo clip has no video controller — the
    // stage shows the still image instead.
    if (_clips[_selected].isPhoto) {
      final old = _controller;
      _detachTrimBinding();
      _clock.attach(null);
      setState(() => _controller = null);
      await old?.dispose();
      return;
    }
    final old = _controller;
    final c = VideoPlayerController.file(_clips[_selected].file);
    // v1.5.0: the ONE clock follows the selected clip's controller.
    _clock.attach(c);
    setState(() => _controller = c);
    await old?.dispose();
    try {
      await c.initialize();
      await c.setLooping(true);
      // P0-2: bind the playhead to the clip's trim range.
      _attachTrimBinding(c);
      // Per-clip volume is audible in the preview too (v1.5.0 —
      // the Volume panel's slider now drives the preview gain).
      final clip = _clips[_selected];
      // Build 4 player fix: present the trimmed first frame
      // deterministically — some devices keep a black texture
      // until the first seek lands.
      await c.seekTo(Duration(milliseconds: (clip.trimStart * 1000).round()));
      await c.setVolume(clip.muted || clip.disabled ? 0 : clip.volume);
      if (mounted) setState(() {});
    } catch (e) {
      // Phase 0 sweep: was an unguarded setState after awaits.
      if (mounted) setState(() => _status = 'Preview failed: $e');
    }
  }

  Future<void> _addClip() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (picked == null) return;
    await _addClipFile(File(picked.path));
  }

  /// Probe [file] (real duration + aspect via a throwaway
  /// [VideoPlayerController]) and append it as a timeline clip,
  /// selected, with the preview loaded. The ONE add-media path:
  /// the gallery picker ([_addClip]), the timeline + tile and the
  /// Projects hub's initial video ([_loadInitialVideo]) all land
  /// here, so every entry point behaves identically.
  Future<void> _addClipFile(File file) async {
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
    // Phase 0 safety sweep: this is the ONE status funnel for the
    // whole editor (screen + panels extension) and it is called
    // after awaits all over both files. The unguarded setState
    // here was the single biggest setState-after-dispose hazard
    // in the editor — guarding this one method hardens every
    // call site at once.
    if (!mounted) return;
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
          'vol': c.volume,
          'muted': c.muted,
          'det': c.detachedAudioPath,
          'dis': c.disabled,
          'lbl': c.colorLabel,
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
    // A1 (v1.12): markers + beats ride the undo history too, so
    // undoing a clip op never strands them.
    'markers': _markers,
    'beats': _beats,
    'beatMusic': _beatSourceMusic,
    'beatPath': _beatSourcePath,
    // v1.14.0 T3: the range points + the multi-select set ride
    // along too — undoing a range delete restores the range
    // that produced it. Old snapshots lack these keys; the
    // restore below defaults them (null / empty).
    'rangeIn': _rangeIn,
    'rangeOut': _rangeOut,
    'multiSel': _multiSelect.toList()..sort(),
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
      c.volume = (e['vol'] as num?)?.toDouble() ?? 1;
      c.muted = e['muted'] as bool? ?? false;
      c.detachedAudioPath = e['det'] as String?;
      // v1.16.0 G3: old snapshots have no dis/lbl keys — the
      // defaults (enabled, no label) apply.
      c.disabled = e['dis'] as bool? ?? false;
      c.colorLabel = (e['lbl'] as num?)?.toInt() ?? 0;
      clips.add(c);
    }
    setState(() {
      _clips
        ..clear()
        ..addAll(clips);
      _selected = ((m['sel'] as num?)?.toInt() ?? 0).clamp(
        0,
        clips.isEmpty ? 0 : clips.length - 1,
      );
      _speed = (m['speed'] as num?)?.toDouble() ?? 1;
      _filter = m['filter'] as String? ?? 'Normal';
      _aspect = m['aspect'] as String? ?? 'Original';
      _crossfade = m['crossfade'] as bool? ?? false;
      _musicPath = m['music'] as String?;
      _musicVolume = (m['musicVol'] as num?)?.toDouble() ?? 1;
      _text = m['text'] as String? ?? '';
      _markers = ((m['markers'] as List?) ?? const [])
          .map((e) => (e as num).toDouble())
          .toList();
      _beats = ((m['beats'] as List?) ?? const [])
          .map((e) => (e as num).toDouble())
          .toList();
      _beatSourceMusic = m['beatMusic'] as bool? ?? false;
      _beatSourcePath = m['beatPath'] as String?;
      // v1.14.0 T3: absent in pre-v1.14 snapshots → null/empty.
      _rangeIn = (m['rangeIn'] as num?)?.toDouble();
      _rangeOut = (m['rangeOut'] as num?)?.toDouble();
      _multiSelect
        ..clear()
        ..addAll(
          ((m['multiSel'] as List?) ?? const [])
              .map((e) => (e as num).toInt())
              .where((i) => i >= 0 && i < clips.length),
        );
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
    _setStatus('Undo done.');
  }

  Future<void> _redo() async {
    if (_redoStack.isEmpty || _busy) return;
    _undoStack.add(_snapshot());
    await _restoreSnapshot(_redoStack.removeLast());
    _setStatus('Redo done.');
  }

  /// Build 3 (Phase 3) — the panel-session snapshot behind the
  /// uniform Cancel/Apply pattern: when a tool panel OPENS, the
  /// settings its controls edit are captured; the header's ✗
  /// (Cancel) restores them and closes, the ✓ (Apply) just closes
  /// (panel edits apply live to the preview, PRO-SPEC point 19).
  /// One-tap ACTIONS inside panels (rotate/flip renders, AI cuts,
  /// file picks) are not settings and are never rolled back — the
  /// same rule every editor follows.
  Map<String, Object?>? _panelBase;

  Map<String, Object?> _panelSnapshot() => {
        'speed': _speed,
        'filter': _filter,
        'filterIntensity': _filterIntensity,
        'aspect': _aspect,
        'crossfade': _crossfade,
        'text': _text,
        'musicVolume': _musicVolume,
        'musicMuted': _musicMuted,
        'pipLaneLocked': _pipLaneLocked,
        'autoDuck': _autoDuck,
        'tfScale': _tfScale,
        'tfX': _tfX,
        'tfY': _tfY,
        'tfRot': _tfRot,
        'tfOpacity': _tfOpacity,
        'canvasFill': _canvasFill,
        'canvasFillColor': _canvasFillColor,
        'adjBrilliance': _adjBrilliance,
        'adjSharpen': _adjSharpen,
        'adjClarity': _adjClarity,
        'adjWhites': _adjWhites,
        'adjBlacks': _adjBlacks,
        'adjHue': _adjHue,
        'adjFade': _adjFade,
        'adjVignette': _adjVignette,
        'adjGrain': _adjGrain,
        'adjAuto': _adjAuto,
        'rampStart': _rampStart,
        'rampMid': _rampMid,
        'rampEnd': _rampEnd,
        'proRamp': _proRamp,
        'pipOpacity': _pipOpacity,
        'pipBlend': _pipBlend,
        'pipMask': _pipMask,
        'pipMaskFeather': _pipMaskFeather,
        'pipMaskInvert': _pipMaskInvert,
        'pipPosition': _pipPosition.index,
        'pipScale': _pipScale,
        'pipStart': _pipStartSec,
        'pipEnd': _pipEndSec,
        'pipKeyframes': _pipKeyframes,
        'pkStartX': _pkStartX,
        'pkStartY': _pkStartY,
        'pkStartOpacity': _pkStartOpacity,
        'pkEndX': _pkEndX,
        'pkEndY': _pkEndY,
        'pkEndOpacity': _pkEndOpacity,
        'pkEasing': _pkEasing.index,
        'mainMask': _mainMask,
        'mainMaskFeather': _mainMaskFeather,
        'mainMaskInvert': _mainMaskInvert,
        'exportFps': _exportFps,
        'proTitle': _proTitle,
        'proTitlePreset': _proTitlePreset,
        'proTitlePosition': _proTitlePosition,
        'proSticker': _proSticker,
        'proStickerPreset': _proStickerPreset,
        'proLut': _proLut,
        'proTemperature': _proTemperature,
        'proTint': _proTint,
        'proSaturation': _proSaturation,
        'proVibrance': _proVibrance,
        'proContrast': _proContrast,
        'proShadows': _proShadows,
        'proHighlights': _proHighlights,
        'proBrightness': _proBrightness,
        'proExposure': _proExposure,
        'proKeyframes': _proKeyframes,
        'kfEasing': _kfEasing.index,
        'kfStartX': _kfStartX,
        'kfStartY': _kfStartY,
        'kfStartScale': _kfStartScale,
        'kfStartOpacity': _kfStartOpacity,
        'kfStartRotation': _kfStartRotation,
        'kfEndX': _kfEndX,
        'kfEndY': _kfEndY,
        'kfEndScale': _kfEndScale,
        'kfEndOpacity': _kfEndOpacity,
        'kfEndRotation': _kfEndRotation,
        'proStabilize': _proStabilize,
        'stabLevel': _stabLevel,
        'proTransition': _proTransition,
        'proTransitionDur': _proTransitionDur,
        'proChroma': _proChroma,
        'proChromaColor': _proChromaColor,
        'proChromaSimilarity': _proChromaSimilarity,
        'proChromaBlend': _proChromaBlend,
        'proChromaBgKind': _proChromaBgKind,
        'proChromaBgColor': _proChromaBgColor,
        'proChromaBgImage': _proChromaBgImage,
        'proChromaSpill': _proChromaSpill,
        'proChromaEdge': _proChromaEdge,
        'proBgRemove': _proBgRemove,
        'proBgKind': _proBgKind,
        'proBgColor': _proBgColor,
        'proBgImage': _proBgImage,
        'trackSticker': _trackSticker,
        'fxVoice': _fxVoice.index,
        'fxFadeIn': _fxFadeIn,
        'fxFadeOut': _fxFadeOut,
        'muteOriginal': _muteOriginal,
        'fxSilenceRemove': _fxSilenceRemove,
        'fxPip': _fxPip,
        'fxShake': _fxShake.index,
        'fxQuality': _fxQuality,
        'aicutThresholdDb': _aicutThresholdDb,
        'aicutMinSilenceSec': _aicutMinSilenceSec,
        'newsEnabled': _newsEnabled,
        // A1 (v1.12): the session draft IS this panel map, so
        // markers + beats (with their source) survive a relaunch.
        'markers': List<double>.of(_markers),
        'beats': List<double>.of(_beats),
        'beatMusic': _beatSourceMusic,
        'beatPath': _beatSourcePath,
        // v1.14.0 T3: range points + multi-select survive a
        // relaunch the same way (absent in old drafts → the
        // restore defaults them).
        'rangeIn': _rangeIn,
        'rangeOut': _rangeOut,
        'multiSel': _multiSelect.toList()..sort(),
      };

  void _restorePanelSnapshot(Map<String, Object?> m) {
    double d(String k) => (m[k] as num?)?.toDouble() ?? 0;
    setState(() {
      _speed = d('speed');
      _filter = m['filter'] as String? ?? 'Normal';
      _filterIntensity = d('filterIntensity');
      _aspect = m['aspect'] as String? ?? 'Original';
      _crossfade = m['crossfade'] as bool? ?? false;
      _text = m['text'] as String? ?? '';
      _musicVolume = d('musicVolume');
      // v1.16.0 G3 (A3): old snapshots lack both keys.
      _musicMuted = m['musicMuted'] as bool? ?? false;
      _pipLaneLocked = m['pipLaneLocked'] as bool? ?? false;
      _autoDuck = m['autoDuck'] as bool? ?? false;
      _tfScale = d('tfScale');
      _tfX = d('tfX');
      _tfY = d('tfY');
      _tfRot = d('tfRot');
      _tfOpacity = d('tfOpacity');
      _canvasFill = m['canvasFill'] as String? ?? 'none';
      _canvasFillColor = m['canvasFillColor'] as String? ?? 'black';
      _adjBrilliance = d('adjBrilliance');
      _adjSharpen = d('adjSharpen');
      _adjClarity = d('adjClarity');
      _adjWhites = d('adjWhites');
      _adjBlacks = d('adjBlacks');
      _adjHue = d('adjHue');
      _adjFade = d('adjFade');
      _adjVignette = d('adjVignette');
      _adjGrain = d('adjGrain');
      _adjAuto = m['adjAuto'] as bool? ?? false;
      _rampStart = d('rampStart');
      _rampMid = d('rampMid');
      _rampEnd = d('rampEnd');
      _proRamp = m['proRamp'] as String? ?? 'None';
      _pipOpacity = d('pipOpacity');
      _pipBlend = m['pipBlend'] as String? ?? 'normal';
      _pipMask = m['pipMask'] as String? ?? 'none';
      _pipMaskFeather = d('pipMaskFeather');
      _pipMaskInvert = m['pipMaskInvert'] as bool? ?? false;
      _pipPosition =
          PipPosition.values[(m['pipPosition'] as num?)?.toInt() ?? 3];
      _pipScale = d('pipScale');
      // v1.16.0 G2: PIP window — old snapshots have no keys and
      // fall back to the full-timeline window (0 / -1).
      _pipStartSec = (m['pipStart'] as num?)?.toDouble() ?? 0;
      _pipEndSec = (m['pipEnd'] as num?)?.toDouble() ?? -1;
      _pipKeyframes = m['pipKeyframes'] as bool? ?? false;
      _pkStartX = d('pkStartX');
      _pkStartY = d('pkStartY');
      _pkStartOpacity = d('pkStartOpacity');
      _pkEndX = d('pkEndX');
      _pkEndY = d('pkEndY');
      _pkEndOpacity = d('pkEndOpacity');
      _pkEasing =
          KeyframeEasing.values[(m['pkEasing'] as num?)?.toInt() ?? 0];
      _mainMask = m['mainMask'] as String? ?? 'none';
      _mainMaskFeather = d('mainMaskFeather');
      _mainMaskInvert = m['mainMaskInvert'] as bool? ?? false;
      _exportFps = (m['exportFps'] as num?)?.toInt() ?? 30;
      _proTitle = m['proTitle'] as String? ?? '';
      _proTitlePreset = m['proTitlePreset'] as String? ?? 'fadeIn';
      _proTitlePosition = m['proTitlePosition'] as String? ?? 'bottomCenter';
      _proSticker = m['proSticker'] as String? ?? '';
      _proStickerPreset = m['proStickerPreset'] as String? ?? 'fadeIn';
      _proLut = m['proLut'] as String? ?? '';
      _proTemperature = d('proTemperature');
      _proTint = d('proTint');
      _proSaturation = d('proSaturation');
      _proVibrance = d('proVibrance');
      _proContrast = d('proContrast');
      _proShadows = d('proShadows');
      _proHighlights = d('proHighlights');
      _proBrightness = d('proBrightness');
      _proExposure = d('proExposure');
      _proKeyframes = m['proKeyframes'] as bool? ?? false;
      _kfEasing =
          KeyframeEasing.values[(m['kfEasing'] as num?)?.toInt() ?? 0];
      _kfStartX = d('kfStartX');
      _kfStartY = d('kfStartY');
      _kfStartScale = d('kfStartScale');
      _kfStartOpacity = d('kfStartOpacity');
      _kfStartRotation = d('kfStartRotation');
      _kfEndX = d('kfEndX');
      _kfEndY = d('kfEndY');
      _kfEndScale = d('kfEndScale');
      _kfEndOpacity = d('kfEndOpacity');
      _kfEndRotation = d('kfEndRotation');
      _proStabilize = m['proStabilize'] as bool? ?? false;
      _stabLevel = (m['stabLevel'] as num?)?.toInt() ?? 0;
      _proTransition = m['proTransition'] as String? ?? 'fade';
      _proTransitionDur = d('proTransitionDur');
      _proChroma = m['proChroma'] as bool? ?? false;
      _proChromaColor = m['proChromaColor'] as String? ?? 'green';
      _proChromaSimilarity = d('proChromaSimilarity');
      _proChromaBlend = d('proChromaBlend');
      _proChromaBgKind = m['proChromaBgKind'] as String? ?? 'color';
      _proChromaBgColor = m['proChromaBgColor'] as String? ?? '#00FF00';
      _proChromaBgImage = m['proChromaBgImage'] as String?;
      _proChromaSpill = d('proChromaSpill');
      _proChromaEdge = d('proChromaEdge');
      _proBgRemove = m['proBgRemove'] as bool? ?? false;
      _proBgKind = m['proBgKind'] as String? ?? 'color';
      _proBgColor = m['proBgColor'] as String? ?? '#00FF00';
      _proBgImage = m['proBgImage'] as String?;
      _trackSticker = m['trackSticker'] as String? ?? '';
      _fxVoice = VoiceFx.values[(m['fxVoice'] as num?)?.toInt() ?? 0];
      _fxFadeIn = d('fxFadeIn');
      _fxFadeOut = d('fxFadeOut');
      _muteOriginal = m['muteOriginal'] as bool? ?? false;
      _fxSilenceRemove = m['fxSilenceRemove'] as bool? ?? false;
      _fxPip = m['fxPip'] as bool? ?? false;
      _fxShake = ShakeFx.values[(m['fxShake'] as num?)?.toInt() ?? 0];
      _fxQuality = (m['fxQuality'] as num?)?.toInt() ?? 0;
      _aicutThresholdDb = d('aicutThresholdDb');
      _aicutMinSilenceSec = d('aicutMinSilenceSec');
      _newsEnabled = m['newsEnabled'] as bool? ?? false;
      _markers = ((m['markers'] as List?) ?? const [])
          .map((e) => (e as num).toDouble())
          .toList();
      _beats = ((m['beats'] as List?) ?? const [])
          .map((e) => (e as num).toDouble())
          .toList();
      _beatSourceMusic = m['beatMusic'] as bool? ?? false;
      _beatSourcePath = m['beatPath'] as String?;
      // v1.14.0 T3: absent in pre-v1.14 drafts → null/empty.
      // (No clip-count filter here — the panel map is also the
      // Cancel base; indices are clamped wherever they are
      // read, exactly like _selected is.)
      _rangeIn = (m['rangeIn'] as num?)?.toDouble();
      _rangeOut = (m['rangeOut'] as num?)?.toDouble();
      _multiSelect
        ..clear()
        ..addAll(
          ((m['multiSel'] as List?) ?? const [])
              .map((e) => (e as num).toInt())
              .where((i) => i >= 0),
        );
    });
    // Mask preview images are keyed on the mask fields, so a
    // restored value re-renders itself on the next stage build.
    _mainMaskImageKey = '';
    _pipMaskImageKey = '';
  }

  /// The header ✗: close the open panel and roll back everything
  /// its controls changed since it opened.
  void _cancelPanel() {
    final base = _panelBase;
    _panelBase = null;
    if (base != null) _restorePanelSnapshot(base);
    _openTool(null);
    _setStatus('Panel changes cancelled.');
  }

  /// Build 3: keep the preview's playback rate honest — while the
  /// Speed panel is open the preview plays at the speed being
  /// edited (the fixed speed, or the ramp point under the finger);
  /// every other panel plays at 1.0× so no other tool's preview is
  /// distorted by a leftover rate.
  void _applyPreviewSpeed([double? rate]) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final r = (rate ?? (_proRamp == 'None' ? _speed : _rampMid))
        .clamp(0.25, 2.0);
    unawaited(ctrl.setPlaybackSpeed(r));
  }

  void _resetPreviewSpeed() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    unawaited(ctrl.setPlaybackSpeed(1.0));
  }

  /// Opens a tool panel (or closes it when [key] is null); the
  /// panel always starts on its first sub-tab (§3).
  void _openTool(String? key) {
    if (key != null && key != _activeTool) {
      _panelBase = _panelSnapshot();
    }
    if (key != 'speed') _resetPreviewSpeed();
    setState(() {
      _activeTool = key;
      _panelTab = null;
    });
  }

  /// v1.4.0: opens a tool panel on a SPECIFIC sub-tab — the main
  /// tool row's promoted entries (Captions, Filters, Adjust,
  /// Stickers, Aspect ratio, Background) and every clip-row item
  /// land on the exact panel that implements them.
  void _openToolTab(String key, String tab) {
    if (key != _activeTool) {
      _panelBase = _panelSnapshot();
    }
    if (key != 'speed') _resetPreviewSpeed();
    setState(() {
      _activeTool = key;
      _panelTab = tab;
    });
  }

  /// v1.4.0 clip-row op: delete the selected clip (the Trim panel's
  /// Delete button calls this too — one implementation).
  Future<void> _deleteSelectedClip() async {
    if (_clips.isEmpty || _busy) return;
    _pushHistory();
    setState(() {
      _clips.removeAt(_selected);
      if (_selected >= _clips.length) {
        _selected = _clips.isEmpty ? 0 : _clips.length - 1;
      }
      if (_clips.isEmpty) _clipRow = false;
    });
    if (_clips.isNotEmpty) {
      await _loadPreview();
    } else {
      await _controller?.dispose();
      if (mounted) setState(() => _controller = null);
    }
    _setStatus('Clip deleted — Undo can bring it back.');
  }

  /// v1.4.0 clip-row op: duplicate the selected clip right after
  /// itself (same file, trims and per-clip audio state).
  void _duplicateSelectedClip() {
    if (_clips.isEmpty) return;
    _pushHistory();
    setState(() {
      _clips.insert(_selected + 1, _clips[_selected].copy());
      _selected = _selected + 1;
    });
    _setStatus('Clip duplicated (Clip ${_selected + 1}).');
    unawaited(_loadPreview());
  }

  /// v1.16.0 G3 (A23): disable/enable the selected clip. A
  /// disabled clip keeps its timeline space but renders black
  /// + silent in the preview and the export; it is never
  /// deleted and can be re-enabled any time.
  void _toggleSelectedClipDisabled() {
    if (_clips.isEmpty) return;
    _pushHistory();
    setState(() {
      final c = _clips[_selected];
      c.disabled = !c.disabled;
    });
    _setStatus(_clips[_selected].disabled
        ? 'Clip disabled — it will render black and silent; '
            'its place on the timeline is kept.'
        : 'Clip enabled.');
    unawaited(_loadPreview());
  }

  /// v1.16.0 G3 (C3): set the selected clip's colour label.
  void _setSelectedClipColorLabel(int label) {
    if (_clips.isEmpty) return;
    _pushHistory();
    setState(() {
      _clips[_selected].colorLabel = TimelineMath.clipLabelClamp(label);
    });
    _setStatus(label == 0 ? 'Clip label removed.' : 'Clip label set.');
  }

  /// v1.4.0 clip-row op: replace the selected clip's media with a
  /// newly picked video, keeping its slot and (clamped) trims.
  Future<void> _replaceSelectedClip() async {
    if (_clips.isEmpty || _busy) return;
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
        final old = _clips[_selected];
        final nc = VideoClip(file, d, aspect);
        nc.trimStart = old.trimStart.clamp(0, d.inMilliseconds / 1000);
        final end = old.effectiveEnd.clamp(0, d.inMilliseconds / 1000);
        nc.trimEnd = end > nc.trimStart ? end.toDouble() : -1;
        nc.volume = old.volume;
        nc.muted = old.muted;
        _clips[_selected] = nc;
        _status = 'Clip replaced (${d.inSeconds}s).';
      });
      _flashStatus();
      await _loadPreview();
    } catch (e) {
      await probe.dispose();
      _setStatus('Replace failed: $e');
    }
  }

  /// v1.4.0 clip-row op: unlink the selected clip's audio — the
  /// audio is extracted to its own file, the clip is muted, and
  /// the detached file becomes the music track when none is
  /// picked, so the sound stays on the timeline as its own lane.
  Future<void> _unlinkSelectedClipAudio() async {
    if (_clips.isEmpty || _busy) return;
    final idx = _selected < _clips.length ? _selected : 0;
    final clip = _clips[idx];
    if (clip.isPhoto) {
      _setStatus('Photo clips have no audio.');
      return;
    }
    setState(() => _busy = true);
    try {
      final dir = await _workDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final out = p.join(dir.path, 'unlinked_$stamp.m4a');
      final r = await FfmpegService.run(
        '-ss ${clip.trimStart} -t ${clip.effectiveDuration} '
        '-i ${FfmpegService.q(clip.file.path)} -vn -c:a aac -b:a 128k '
        '-y ${FfmpegService.q(out)}',
      );
      if (!r.ok) {
        _setStatus('Unlink failed — no audio found in the clip. ${r.logs}');
        return;
      }
      _pushHistory();
      setState(() {
        clip.detachedAudioPath = out;
        clip.muted = true;
        _musicPath ??= out;
      });
      _setStatus(
        'Audio unlinked — the sound is on a separate track, the clip is muted.',
      );
    } catch (e) {
      _setStatus('Unlink failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// v1.4.0 clip-row audio tools: Reduce noise / Enhance voice on
  /// the SELECTED clip (AudioEnhanceService). The clip's audio is
  /// extracted, processed, and muxed back into a processed copy of
  /// the clip — the processed file replaces the clip's source, so
  /// preview and export both carry the cleaned audio.
  Future<void> _enhanceSelectedClipAudio({required bool voice}) async {
    if (_clips.isEmpty || _busy) return;
    final idx = _selected < _clips.length ? _selected : 0;
    final clip = _clips[idx];
    if (clip.isPhoto) {
      _setStatus('Photo clips have no audio.');
      return;
    }
    setState(() {
      _busy = true;
      _status = voice ? 'Enhancing voice…' : 'Reducing noise…';
    });
    try {
      final dir = await _workDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final rawWav = p.join(dir.path, 'clipfx_raw_$stamp.wav');
      final cleanWav = p.join(dir.path, 'clipfx_clean_$stamp.wav');
      final extract = await FfmpegService.run(
        '-i ${FfmpegService.q(clip.file.path)} -vn -ac 1 -ar 16000 '
        '-c:a pcm_s16le -y ${FfmpegService.q(rawWav)}',
      );
      if (!extract.ok) {
        _setStatus('No audio could be extracted from the clip. ${extract.logs}');
        return;
      }
      final ok = voice
          ? await AudioEnhanceService.instance.enhanceVoice(rawWav, cleanWav)
          : await AudioEnhanceService.instance.reduceNoise(rawWav, cleanWav);
      if (!ok || !await File(cleanWav).exists()) {
        _setStatus(
          voice
              ? 'Voice enhance failed — the original audio will be kept.'
              : 'Noise reduction failed — the original audio will be kept.',
        );
        return;
      }
      final muxed = p.join(dir.path, 'clipfx_$stamp.mp4');
      final mux = await FfmpegService.run(
        '-i ${FfmpegService.q(clip.file.path)} '
        '-i ${FfmpegService.q(cleanWav)} '
        '-map 0:v -map 1:a -c:v copy -c:a aac -b:a 128k -shortest '
        '-y ${FfmpegService.q(muxed)}',
      );
      if (!mux.ok) {
        _setStatus('Processed audio could not be put back. ${mux.logs}');
        return;
      }
      _pushHistory();
      setState(() {
        final nc = VideoClip(File(muxed), clip.duration, clip.aspectRatio);
        nc.trimStart = clip.trimStart;
        nc.trimEnd = clip.trimEnd;
        nc.volume = clip.volume;
        nc.muted = clip.muted;
        nc.detachedAudioPath = clip.detachedAudioPath;
        _clips[idx] = nc;
      });
      _setStatus(voice ? 'Voice enhanced.' : 'Noise reduced.');
      await _loadPreview();
    } catch (e) {
      _setStatus('Audio tool failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// v1.4.0 Edit › Speed: Smooth Slow-Mo (AI) — RIFE interpolation
  /// via [VideoExportService.smoothSlowMoAi] on the selected
  /// clip's TRIMMED range. The interpolated file (2× duration,
  /// half speed, real in-between frames) replaces the clip.
  /// Fail-soft: any failure keeps the original clip + a message.
  Future<void> _applySlowMoAi() async {
    if (_clips.isEmpty || _busy) return;
    final idx = _selected < _clips.length ? _selected : 0;
    final clip = _clips[idx];
    if (clip.isPhoto) {
      _setStatus('Slow-mo does not apply to photo clips.');
      return;
    }
    if (clip.effectiveDuration > 10.5) {
      _setStatus(
        'Smooth Slow-Mo only applies to clips up to ~10s — '
        'trim the clip first.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Creating Smooth Slow-Mo (AI)…';
    });
    try {
      final dir = await _workDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final seg = p.join(dir.path, 'slowmo_src_$stamp.mp4');
      final segRes = await FfmpegService.run(
        '-ss ${clip.trimStart} -t ${clip.effectiveDuration} '
        '-i ${FfmpegService.q(clip.file.path)} '
        '-c:v libx264 -preset veryfast -crf 23 -c:a aac -b:a 128k '
        '-y ${FfmpegService.q(seg)}',
      );
      if (!segRes.ok) {
        _setStatus('The clip could not be prepared for slow-mo. ${segRes.logs}');
        return;
      }
      var lastPct = -1;
      final outPath = await VideoExportService.smoothSlowMoAi(
        inputPath: seg,
        workDir: dir,
        onProgress: (v) {
          final pct = (v * 100).round();
          if (pct != lastPct) {
            lastPct = pct;
            _setStatus('Smooth Slow-Mo (AI)… $pct%');
          }
        },
      );
      _pushHistory();
      setState(() {
        final nc = VideoClip(
          File(outPath),
          Duration(milliseconds: (clip.effectiveDuration * 2000).round()),
          clip.aspectRatio,
        );
        nc.volume = clip.volume;
        nc.muted = clip.muted;
        _clips[idx] = nc;
      });
      _setStatus('Smooth Slow-Mo ready — the clip is now at 0.5x speed.');
      await _loadPreview();
    } catch (e) {
      _setStatus('Smooth Slow-Mo failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// v1.4.0 Captions: 'Urdu (AI)' — Shruti Urdu recognizer via
  /// [UrduCaptionService] on the selected clip's own file (the
  /// service extracts the audio itself). Segments land in the
  /// same [_captions] list the Whisper path fills, so style /
  /// edit / export behave identically.
  Future<void> _generateUrduCaptions() async {
    if (_clips.isEmpty) {
      _setStatus('Add a video first.');
      return;
    }
    if (_transcribing || _busy) return;
    if (!await _chargeAiCaptions(
      label: 'AI auto captions — Urdu (AI)',
      reason: AiToolCharge.reasonAutoCaptions,
    )) {
      return;
    }
    final clip = _clips[_selected];
    setState(() {
      _transcribing = true;
      _status = 'Creating Urdu (AI) captions…';
    });
    try {
      final caps = await UrduCaptionService.instance.transcribe(clip.file.path);
      if (!mounted) return;
      if (caps.isEmpty) {
        setState(
          () => _status =
              'Urdu (AI): no speech could be understood — or the model pack '
              'has not downloaded yet.',
        );
      } else {
        setState(() {
          _captions = caps
              .map(
                (c) => CaptionSegment(
                  c.text,
                  c.start.inMilliseconds / 1000,
                  c.end.inMilliseconds / 1000,
                ),
              )
              .toList();
          _captionsTimelineRelative = false;
          _status =
              '${caps.length} Urdu (AI) caption segments are ready — view/edit them from Edit.';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Urdu (AI) captions failed: $e');
    } finally {
      if (mounted) setState(() => _transcribing = false);
    }
  }

  /// v1.4.0 top bar search: a real tool index — every editor tool
  /// by name; tapping one opens its exact panel/tab.
  Future<void> _showToolSearch() async {
    // v1.5.0: the index lists the NEW tool keys (the Help dialog is
    // this list — every entry opens the real panel).
    final entries = <(String, String, String?)>[
      ('Canvas — Ratio', 'canvas', 'ratio'),
      ('Canvas — Zoom', 'canvas', 'zoom'),
      ('Canvas — Background', 'canvas', 'background'),
      ('Audio — Music', 'audio', 'music'),
      ('Audio — Voice Effect', 'audio', 'voice'),
      ('Audio — Cleanup', 'audio', 'clean'),
      ('Stickers', 'overlay', 'sticker'),
      ('Text', 'text', 'text'),
      ('Motion titles', 'text', 'titles'),
      ('Captions', 'text', 'captions'),
      ('Effects', 'effects', 'effects'),
      ('Motion tracking', 'effects', 'tracking'),
      ('Filters', 'colour', 'filters'),
      ('Adjust', 'colour', 'adjust'),
      ('PIP / Overlay', 'overlay', 'pip'),
      ('Precut — Trim', 'precut', 'trim'),
      ('Precut — Cut', 'precut', 'cut'),
      ('Precut — Split', 'precut', 'split'),
      ('Volume', 'volume', null),
      ('Chroma key', 'cutout', null),
      ('Speed', 'speed', 'standard'),
      ('Speed curve', 'speed', 'curve'),
      ('Beat sync', 'speed', 'beat'),
      ('Animation / Keyframes', 'overlay', 'keyframes'),
      ('AI Cut', 'aicut', null),
      ('Voice Enhance', 'voiceenhance', null),
      ('Crop / Transform', 'edit', 'transform'),
      ('Enhance (HD)', 'enhance', null),
      ('Stabilizer', 'stabilizer', null),
      ('Cutout / Chroma', 'cutout', null),
      ('Mask', 'mask', null),
      ('Opacity', 'opacity', null),
      ('Rotate / Flip', 'rotate', null),
      ('Ease', 'ease', null),
      ('Transitions', 'transitions', null),
      ('News template', 'news', 'template'),
      ('News text', 'news', 'text'),
      ('News logo', 'news', 'logo'),
    ];
    final picked = await showDialog<(String, String?)>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Search tools'),
        children: [
          for (final e in entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, (e.$2, e.$3)),
              child: Text(e.$1),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _clipRow = false);
    if (picked.$2 != null) {
      _openToolTab(picked.$1, picked.$2!);
    } else {
      _openTool(picked.$1);
    }
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
    final base = buildColorMatrix(
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
    // P1-1: the Adjust extras ride the SAME matrix stage — the
    // preview now reads the fields the export reads, through the
    // shared derivation in adjust_params.dart (brilliance
    // saturation exact; gamma∘curves as a fitted line; hue in
    // standard matrix form). Vignette/Grain are overlays (see
    // the stage), Sharpen/Clarity/LUT stay export-only (no
    // widget equivalent — documented in adjust_params.dart).
    if (!_adjustExtraActive) return base;
    return multiplyColorMatrices(adjustPreviewMatrix(_adjustValues), base);
  }

  /// Export settings dialog (AppBar pill §3 + the export flow):
  /// quality AND frame rate in one place (Build 3, Phase 3 —
  /// PRO-SPEC point 20). Picking ahead of time via the pill makes
  /// [_export] skip the dialog, exactly as the quality-only pill
  /// did. Returns true when the user confirmed (Done), false/null
  /// when cancelled — [_export] then aborts, as before.
  Future<bool?> _pickExportSettings() async {
    var q = _fxQuality;
    var fps = _exportFps;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export settings'),
        content: StatefulBuilder(
          builder: (ctx, setLocal) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Quality',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final entry in const [
                (0, '720p HD (fast)'),
                (1, '1080p Full HD'),
                (2, '2160p 4K (slow)'),
              ])
                ListTile(
                  dense: true,
                  leading: Icon(
                    q == entry.$1
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: q == entry.$1 ? TjProTheme.gold : null,
                  ),
                  title: Text(entry.$2),
                  onTap: () => setLocal(() => q = entry.$1),
                ),
              const SizedBox(height: 8),
              const Text(
                'Frame rate',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final f in const [24, 30, 60])
                ListTile(
                  dense: true,
                  leading: Icon(
                    fps == f
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: fps == f ? TjProTheme.gold : null,
                  ),
                  title: Text('$f fps'),
                  onTap: () => setLocal(() => fps = f),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (ok != true) return ok;
    if (!mounted) return false;
    setState(() {
      _fxQuality = q;
      _exportFps = fps;
      _qualityPicked = true;
    });
    _setStatus(
      'Export: ${const ['720p', '1080p', '4K'][q]} · $fps fps set.',
    );
    return true;
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
      _status = 'Photo clip added (3s, Ken Burns on).';
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
      _setStatus('Let the clip preview load first.');
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
        _setStatus('Freeze frame was not created. ${r.logs}');
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
      _setStatus('Freeze frame clip created (2s).');
      await _loadPreview();
    } catch (e) {
      _setStatus('Freeze frame failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// v1.5.0 Switch (InShot [TUT12], CONFIRMED behaviour): the
  /// selected main-track segment MOVES to the overlay/PIP track —
  /// it leaves the main timeline and becomes the PIP element. The
  /// element-row Switch runs the symmetric move back (that
  /// direction was never demonstrated in InShot — flagged in the
  /// v1.5.0 test report).
  Future<void> _switchSelectedClipToPip() async {
    if (_clips.isEmpty || _busy) return;
    final clip = _clips[_selected];
    if (clip.isPhoto) {
      _setStatus('A photo clip cannot become PIP — choose a video clip.');
      return;
    }
    if (_clips.length < 2) {
      _setStatus(
        'Switch needs at least 2 clips — otherwise the main '
        'track would become empty.',
      );
      return;
    }
    _pushHistory();
    setState(() {
      _fxPip = true;
      _fxPipVideo = clip.file.path;
      _clips.removeAt(_selected);
      if (_selected >= _clips.length) _selected = _clips.length - 1;
      _clipRow = false;
      _elementRow = true;
    });
    _setStatus('Clip moved to the PIP track (Switch).');
    await _loadPreview();
  }

  /// v1.5.0 Switch, element → main track (symmetric implementation;
  /// InShot never demonstrated this direction — flagged): the PIP
  /// video is appended to the main timeline via the ONE add path
  /// and the PIP slot clears.
  Future<void> _switchPipToMainTrack() async {
    if (!_fxPip || _fxPipVideo.isEmpty || _busy) return;
    final file = File(_fxPipVideo);
    if (!await file.exists()) {
      _setStatus('PIP video file not found.');
      return;
    }
    _pushHistory();
    setState(() {
      _fxPip = false;
      _fxPipVideo = '';
      _elementRow = false;
    });
    await _addClipFile(file);
    _setStatus('PIP element moved to the main track (Switch).');
  }

  /// v1.5.0 Capture (InShot): the playhead frame becomes a still
  /// segment INSERTED at the playhead — the selected clip splits
  /// there and the 2s still sits between the halves. (Reuses the
  /// _saveFrameSnapshot frame-grab; that one saves to the gallery,
  /// this one inserts into the timeline.)
  Future<void> _captureFrameInsert() async {
    if (_clips.isEmpty || _busy) return;
    final clip = _clips[_selected];
    if (clip.isPhoto) {
      _setStatus('No Capture on a photo clip — it is already a still.');
      return;
    }
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      _setStatus('Let the clip preview load first.');
      return;
    }
    final posSec = ctrl.value.position.inMilliseconds / 1000.0;
    setState(() => _busy = true);
    try {
      final dir = await _workDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final out = p.join(dir.path, 'capture_$stamp.png');
      final r = await FfmpegService.run(
        '-ss $posSec -i ${FfmpegService.q(clip.file.path)} '
        '-frames:v 1 -q:v 2 -y ${FfmpegService.q(out)}',
      );
      if (!r.ok) {
        _setStatus('Capture failed. ${r.logs}');
        return;
      }
      _pushHistory();
      final idx = _selected;
      final inside = posSec - clip.trimStart;
      final still = VideoClip(
        File(out),
        const Duration(seconds: 2),
        clip.aspectRatio,
      )..isPhoto = true;
      setState(() {
        if (inside > 0.3 && inside < clip.effectiveDuration - 0.3) {
          // Split at the playhead: [first][still][second].
          final second = clip.copy()..trimStart = posSec;
          clip.trimEnd = posSec;
          _clips.insert(idx + 1, second);
          _clips.insert(idx + 1, still);
        } else {
          _clips.insert(idx + 1, still);
        }
        _selected = idx + 1;
      });
      _setStatus('Capture — the frame was placed on the timeline (2s still).');
      await _loadPreview();
    } catch (e) {
      _setStatus('Capture failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// v1.5.0 Reverse (instant, InShot): the selected clip's TRIMMED
  /// range is baked into a reversed processed copy which replaces
  /// the clip (the same replace pattern as Smooth Slow-Mo). A clip
  /// without an audio stream retries video-only.
  Future<void> _reverseSelectedClip() async {
    if (_clips.isEmpty || _busy) return;
    final idx = _selected;
    final clip = _clips[idx];
    if (clip.isPhoto) {
      _setStatus('Photo clips cannot be reversed.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Creating reverse…';
    });
    try {
      final dir = await _workDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final out = p.join(dir.path, 'reverse_$stamp.mp4');
      final base =
          '-ss ${clip.trimStart} -t ${clip.effectiveDuration} '
          '-i ${FfmpegService.q(clip.file.path)} ';
      var r = await FfmpegService.run(
        '$base-vf reverse -af areverse -c:v libx264 -preset veryfast '
        '-crf 23 -c:a aac -b:a 128k -y ${FfmpegService.q(out)}',
      );
      if (!r.ok) {
        r = await FfmpegService.run(
          '$base-vf reverse -an -c:v libx264 -preset veryfast '
          '-crf 23 -y ${FfmpegService.q(out)}',
        );
      }
      if (!r.ok) {
        _setStatus('Reverse failed. ${r.logs}');
        return;
      }
      _pushHistory();
      setState(() {
        final nc = VideoClip(
          File(out),
          Duration(milliseconds: (clip.effectiveDuration * 1000).round()),
          clip.aspectRatio,
        );
        nc.volume = clip.volume;
        nc.muted = clip.muted;
        _clips[idx] = nc;
      });
      _setStatus('Clip reversed.');
      await _loadPreview();
    } catch (e) {
      _setStatus('Reverse failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// v1.5.0 Rotate / Flip (InShot Rotate panel: exactly ROTATE +
  /// FLIP): the trimmed range is baked into a processed copy —
  /// transpose=1 (90° clockwise, aspect swaps) or hflip (mirror).
  Future<void> _rotateSelectedClip({required bool flip}) async {
    if (_clips.isEmpty || _busy) return;
    final idx = _selected;
    final clip = _clips[idx];
    if (clip.isPhoto) {
      _setStatus('For a photo clip, use the Photo Editor\'s Rotate.');
      return;
    }
    setState(() {
      _busy = true;
      _status = flip ? 'Flipping…' : 'Rotating…';
    });
    try {
      final dir = await _workDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final out = p.join(dir.path, '${flip ? 'flip' : 'rotate'}_$stamp.mp4');
      final r = await FfmpegService.run(
        '-ss ${clip.trimStart} -t ${clip.effectiveDuration} '
        '-i ${FfmpegService.q(clip.file.path)} '
        '-vf ${flip ? 'hflip' : 'transpose=1'} '
        '-c:v libx264 -preset veryfast -crf 23 -c:a aac -b:a 128k '
        '-y ${FfmpegService.q(out)}',
      );
      if (!r.ok) {
        _setStatus('${flip ? 'Flip' : 'Rotate'} failed. ${r.logs}');
        return;
      }
      _pushHistory();
      setState(() {
        final nc = VideoClip(
          File(out),
          Duration(milliseconds: (clip.effectiveDuration * 1000).round()),
          flip ? clip.aspectRatio : 1 / clip.aspectRatio,
        );
        nc.volume = clip.volume;
        nc.muted = clip.muted;
        _clips[idx] = nc;
      });
      _setStatus(flip ? 'Clip flipped.' : 'Clip rotated 90°.');
      await _loadPreview();
    } catch (e) {
      _setStatus('${flip ? 'Flip' : 'Rotate'} failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// v1.5.0 Enhance (video): an honest on-device HD enhance — 2x
  /// lanczos upscale + unsharp + a touch of saturation, baked into
  /// a processed copy. This is NOT the ESRGAN AI upscaler (that is
  /// the Photo path); the panel labels it as such.
  Future<void> _enhanceSelectedClipHd() async {
    if (_clips.isEmpty || _busy) return;
    final idx = _selected;
    final clip = _clips[idx];
    if (clip.isPhoto) {
      _setStatus('For a photo clip, use the Photo Editor\'s Enhance.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Creating HD Enhance…';
    });
    try {
      final dir = await _workDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final out = p.join(dir.path, 'enhance_$stamp.mp4');
      final r = await FfmpegService.run(
        '-ss ${clip.trimStart} -t ${clip.effectiveDuration} '
        '-i ${FfmpegService.q(clip.file.path)} '
        '-vf "scale=iw*2:ih*2:flags=lanczos,unsharp=5:5:1.0,'
        'eq=saturation=1.05" '
        '-c:v libx264 -preset veryfast -crf 20 -c:a aac -b:a 128k '
        '-y ${FfmpegService.q(out)}',
      );
      if (!r.ok) {
        _setStatus('HD Enhance failed. ${r.logs}');
        return;
      }
      _pushHistory();
      setState(() {
        final nc = VideoClip(
          File(out),
          Duration(milliseconds: (clip.effectiveDuration * 1000).round()),
          clip.aspectRatio,
        );
        nc.volume = clip.volume;
        nc.muted = clip.muted;
        _clips[idx] = nc;
      });
      _setStatus('HD Enhance ready (2x upscale + sharpen).');
      await _loadPreview();
    } catch (e) {
      _setStatus('HD Enhance failed: $e');
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

  /// Phase 0 export CANCEL: flags the pipeline to stop and kills
  /// the in-flight ffmpeg session through the [FfmpegService]
  /// registry. The pipeline notices at the next
  /// [_checkExportCancelled] checkpoint (the killed stage itself
  /// just reports a failed/cancelled result into its guarded
  /// pass), and [_export] surfaces "Export cancelled."
  /// — never a fake failure.
  void _cancelExport() {
    if (!_exporting || _exportCancelRequested) return;
    _exportCancelRequested = true;
    FfmpegService.cancel();
    _setStatus('Cancelling export…');
  }

  /// Pipeline checkpoint: throws [_ExportCancelled] when
  /// [_cancelExport] has run. Placed between the export stages
  /// (OUTSIDE their guarded try blocks) so a cancel stops the
  /// NEXT stage from starting.
  /// Wrapper around [_exportInner] with one subtitles-fallback retry:
  /// if the ASS subtitles filter is missing from this FFmpeg build, retry
  /// the export with timed drawtext captions (Latin scripts only).
  Future<void> _export() async {
    // Build 9 (v1.7.0, point #5): remote kill switch — a killed
    // export shows the polite closed message and never starts.
    if (FeatureGate.isKilled(KillableFeature.videoExport)) {
      _setStatus(FeatureGate.killedMessage);
      return;
    }
    await VideoEditorExportController(this).export();
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
      b.write('[0:v][pipA]overlay=x=$xx:y=$yy$_pipEnableSuffix[vout]');
    } else {
      // [0:v] is consumed twice (crop + final overlay) — split it.
      b.write('[0:v]split=2[bbg][bcrop];');
      b.write('[bcrop]crop=$pw:$ph:$xx:$yy,format=gbrp[bc];');
      b.write('[pv1]format=gbrp[pc];');
      b.write('[bc][pc]blend=all_mode=$_pipBlend[bl];');
      b.write('[bl]format=yuva420p[blf];');
      b.write('[blf][pa]alphamerge[bla];');
      b.write('[bbg][bla]overlay=x=$xx:y=$yy$_pipEnableSuffix[vout]');
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
        path.addOval(
          Rect.fromCircle(center: Offset(cx, cy), radius: math.min(w, h) / 2),
        );
      case 'roundrect':
        path.addRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, 0, w, h),
            Radius.circular(math.min(w, h) * 0.18),
          ),
        );
      case 'heart':
        Offset pt(double fx, double fy) => Offset(fx * w, fy * h);
        path.moveTo(pt(0.50, 0.90).dx, pt(0.50, 0.90).dy);
        path.cubicTo(
          pt(0.10, 0.62).dx,
          pt(0.10, 0.62).dy,
          pt(0.02, 0.40).dx,
          pt(0.02, 0.40).dy,
          pt(0.12, 0.24).dx,
          pt(0.12, 0.24).dy,
        );
        path.cubicTo(
          pt(0.20, 0.10).dx,
          pt(0.20, 0.10).dy,
          pt(0.38, 0.10).dx,
          pt(0.38, 0.10).dy,
          pt(0.50, 0.30).dx,
          pt(0.50, 0.30).dy,
        );
        path.cubicTo(
          pt(0.62, 0.10).dx,
          pt(0.62, 0.10).dy,
          pt(0.80, 0.10).dx,
          pt(0.80, 0.10).dy,
          pt(0.88, 0.24).dx,
          pt(0.88, 0.24).dy,
        );
        path.cubicTo(
          pt(0.98, 0.40).dx,
          pt(0.98, 0.40).dy,
          pt(0.90, 0.62).dx,
          pt(0.90, 0.62).dy,
          pt(0.50, 0.90).dx,
          pt(0.50, 0.90).dy,
        );
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

  /// Renders a mask (shape / gradient, feather, invert) as PNG
  /// bytes at [width]×[height] — white where the layer shows,
  /// transparent where it is masked out. Feather on shapes is a
  /// real alpha blur (MaskFilter.blur), so the soft edge is
  /// identical in preview and export; on gradients the feather
  /// widens the ramp instead. Build 3: this is the ONE renderer
  /// behind both the PIP mask and the main-clip mask.
  Future<Uint8List?> _maskPngBytes({
    required String shape,
    required double featherValue,
    required bool invert,
    required int width,
    required int height,
  }) async {
    if (width < 2 || height < 2) return null;
    final w = width.toDouble();
    final h = height.toDouble();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final feather = featherValue.clamp(0.0, 1.0);
    const white = Color(0xFFFFFFFF);
    const clear = Color(0x00000000);
    if (shape == 'linear' || shape == 'radial') {
      final paint = ui.Paint();
      if (shape == 'linear') {
        final a = 0.5 - feather / 2;
        final bb = 0.5 + feather / 2;
        paint.shader = ui.Gradient.linear(
          Offset.zero,
          Offset(w, 0),
          invert
              ? const [clear, clear, white, white]
              : const [white, white, clear, clear],
          [0, a, bb, 1],
        );
      } else {
        final radius = math.sqrt(w * w + h * h) / 2;
        paint.shader = ui.Gradient.radial(
          Offset(w / 2, h / 2),
          radius,
          invert
              ? const [clear, clear, white]
              : const [white, white, clear],
          [0, (1 - feather).clamp(0.0, 1.0), 1],
        );
      }
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), paint);
    } else {
      final path = _pipMaskShapePath(shape, Size(w, h));
      final sigma = feather * math.min(w, h) * 0.2;
      if (invert) {
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), ui.Paint()..color = white);
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

  /// The current PIP mask as PNG bytes (the [_maskPngBytes]
  /// renderer fed with the PIP fields).
  Future<Uint8List?> _pipMaskPngBytes(int width, int height) =>
      _maskPngBytes(
        shape: _pipMask,
        featherValue: _pipMaskFeather,
        invert: _pipMaskInvert,
        width: width,
        height: height,
      );

  /// Writes the export-resolution mask PNG for the MAIN-clip mask
  /// pass; returns its path, or null when rendering failed (the
  /// caller then keeps the unmasked export with a status note).
  Future<String?> _renderMainMaskPng({
    required Directory dir,
    required int stamp,
    required int width,
    required int height,
  }) async {
    try {
      final bytes = await _maskPngBytes(
        shape: _mainMask,
        featherValue: _mainMaskFeather,
        invert: _mainMaskInvert,
        width: width,
        height: height,
      );
      if (bytes == null) return null;
      final f = File(p.join(dir.path, 'main_mask_$stamp.png'));
      await f.writeAsBytes(bytes);
      return f.path;
    } catch (_) {
      return null;
    }
  }

  /// Loads (once per parameter change) the preview-resolution
  /// MAIN mask image used by the stage's ShaderMask — the twin of
  /// [_ensurePipMaskImage].
  void _ensureMainMaskImage(int width, int height) {
    final key =
        '$_mainMask|${_mainMaskFeather.toStringAsFixed(2)}|'
        '$_mainMaskInvert|${width}x$height';
    if (_mainMaskImageKey == key || _mainMaskImageBusy) return;
    _mainMaskImageKey = key;
    _mainMaskImageBusy = true;
    () async {
      ui.Image? img;
      try {
        final bytes = await _maskPngBytes(
          shape: _mainMask,
          featherValue: _mainMaskFeather,
          invert: _mainMaskInvert,
          width: width,
          height: height,
        );
        if (bytes != null) {
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          img = frame.image;
        }
      } catch (_) {
        img = null;
      }
      _mainMaskImageBusy = false;
      if (!mounted) {
        img?.dispose();
        return;
      }
      final old = _mainMaskImage;
      setState(() => _mainMaskImage = img);
      old?.dispose();
    }();
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
    final key =
        '$_pipMask|${_pipMaskFeather.toStringAsFixed(2)}|'
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

  /// Build 2 (Phase 1): the stage canvas. The chosen Canvas ratio
  /// becomes a real FRAME centred on the stage; the media is
  /// contain-fitted inside it (never stretched — the VideoPlayer
  /// texture previously filled the whole stage box, distorting
  /// every non-stage-shaped clip); the §6.7 transform renders live
  /// around the frame centre; the text overlay sits in frame
  /// coordinates (the export's drawtext spot); PIP composites over
  /// the frame AFTER the transform, exactly like the export; the
  /// grid/safe-zone guides paint on top when enabled.

  /// The media itself inside the canvas frame's contain rect:
  /// photo still or video texture, carrying the stage gestures —
  /// tap = tracking point + layer deselect, hold = compare
  /// (§6.2), scale = canvas transform (Phase 1), double-tap =
  /// transform reset.
  /// Build 3 (Phase 3): wraps the main media in the MAIN-clip
  /// mask's dstIn ShaderMask when a mask is chosen — the same
  /// preview mechanism the PIP layer uses (the SAME generated mask
  /// PNG as the export, so preview and export cannot drift). The
  /// mask image renders at a capped resolution (shapes/gradients
  /// are scale-invariant; feather is relative to the short side).


  /// Build 3 (Phase 3): the keyframed title/sticker as a stage
  /// layer — a dark pill standing in for the export's rendered
  /// PNG, posed by [keyframePoseAt] at the playhead over the
  /// media's contain rect (the keyframe norms are fractions of
  /// the VIDEO size, and the export anchors the PNG's top-left
  /// the same way). Shown only while keyframes are ON for the
  /// title/sticker, so the non-keyframed preview is untouched.

  /// The editor's text overlay as a stage layer (Phase 1): drawn
  /// in frame coordinates at the export's drawtext spot (bottom
  /// centre). Tapping it selects the layer and opens the Text
  /// panel below — its property panel. The export position is
  /// fixed by drawtext, so the layer is selectable but not
  /// draggable; the gold outline shows the selection.

  /// The stage's PIP layer: the inset composited over the main
  /// preview at the export's position/scale fractions, with the
  /// chosen blend mode (saveLayer), opacity and mask (the SAME
  /// generated mask PNG as the export, as a dstIn ImageShader).
  /// Build 2: [stage] is now the CANVAS FRAME's size (the layer is
  /// composited inside the frame); the §6.11 pixel-true sizing and
  /// contain anchoring below are unchanged. On top of that:
  /// tapping the inset selects the layer and opens its element
  /// row, dragging moves it (release snaps to the nearest corner
  /// — the [PipPosition] model), pinching rescales it.

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
        .map(
          (s) => CaptionSegment(
            s.text,
            (offset + s.start) / speed,
            (offset + s.end) / speed,
          ),
        )
        .toList();
  }

  /// Build 9 (v1.7.0, points #5 + #6B): the kill-switch gate +
  /// per-use coin charge shared by BOTH AI caption generators
  /// (Whisper "Generate Captions" and "Urdu (AI)"). Until this
  /// build both ran free; they now charge the remote-config
  /// price (`ai_tool_price_coins`, default 25) per generation
  /// through [AiToolCharge]. A killed feature never charges.
  Future<bool> _chargeAiCaptions({
    required String label,
    required String reason,
  }) async {
    if (FeatureGate.isKilled(KillableFeature.aiCaptions)) {
      _setStatus(FeatureGate.killedMessage);
      return false;
    }
    final outcome = await AiToolCharge.chargeWithConfirm(
      context,
      toolLabel: label,
      reason: reason,
    );
    if (!mounted) return false;
    switch (outcome) {
      case AiChargeOutcome.ok:
        return true;
      case AiChargeOutcome.cancelled:
        return false;
      case AiChargeOutcome.insufficient:
        _setStatus(AiToolCharge.insufficientMessage);
        return false;
      case AiChargeOutcome.failed:
        _setStatus('Charge failed — try again.');
        return false;
    }
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
    if (!await _chargeAiCaptions(
      label: 'AI Caption Generator',
      reason: AiToolCharge.reasonCaptionGenerator,
    )) {
      return;
    }
    final clip = _clips[_selected];
    setState(() {
      _transcribing = true;
      _status = 'Extracting the video\'s audio…';
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
                  'Caption model download… $pct% (first time only, one time)',
            );
          }
        },
      );
      final segments = CaptionService.chunkSegments(raw);
      if (!mounted) return;
      if (segments.isEmpty) {
        setState(
          () => _status = 'No speech detected — no sound found in the video, or it could not be understood.',
        );
      } else {
        setState(() {
          _captions = segments;
          // Transcribed segments are per-clip, not timeline-relative.
          _captionsTimelineRelative = false;
          _status =
              '${segments.length} caption segments ready — view/edit them from Edit before export.';
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
  /// v1.16.0 G4 (A18): the captions lane's tap target — seek
  /// the playhead to the caption's timeline start (the same
  /// span mapping the lane paints and the export applies) and
  /// open the editor focused on that caption.
  int _captionFocusIndex = -1;

  Future<void> _editCaptionAt(int index) async {
    if (index < 0 || index >= _captions.length) return;
    final spans = TimelineMath.captionStripSpans(
      segments: [for (final s in _captions) (start: s.start, end: s.end)],
      timelineRelative: _captionsTimelineRelative,
      selectedClipStart: _clips.isEmpty ? 0 : _clipStartSec(_selected),
      totalDur: _totalDurationSec,
    );
    await _seekToGlobalSec(spans[index].start);
    _captionFocusIndex = index;
    try {
      await _editCaptions();
    } finally {
      _captionFocusIndex = -1;
    }
  }

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
                      // v1.16.0 G4 (A18): opened from the
                      // captions lane, the tapped caption is
                      // focused and its label gilded.
                      autofocus: i == _captionFocusIndex,
                      decoration: InputDecoration(
                        labelText: 'Caption ${i + 1}',
                        labelStyle: i == _captionFocusIndex
                            ? const TextStyle(color: TjProTheme.gold)
                            : null,
                      ),
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

  /// Split (v1.15.0 G1 — the full diagnosis fix; P0-2's earlier
  /// pass left six roots, see SPLIT-DIAGNOSIS-2026-11-26):
  ///
  /// * The strip geometry is exact now (halfPad == the centre
  ///   line's x), so centreSec = scrollOffset / pxPerSec IS the
  ///   second under the yellow line at every zoom.
  /// * Playhead mode (the Split panel toggle, [_snapOn] ON): the
  ///   clip UNDER the line is cut at the line — the selection
  ///   moves to it. The centre is snapped with the TIMELINE's own
  ///   snap setting (A20: on/off + strength, [tlSnapThreshold]) —
  ///   and if the snap would move the cut into a DIFFERENT clip,
  ///   the snap is cancelled (the old hardcoded-0.15 snap dragged
  ///   near-boundary playheads ONTO the boundary, where the edge
  ///   rule then misfired). A line resting within 0.15 s of the
  ///   target clip's edge is REFUSED with a clear status — never
  ///   a silent midpoint fallback (that fallback was the "press
  ///   again and again" cascade: after a split the centre sits
  ///   exactly on the new boundary, so every extra tap halved
  ///   the remainder).
  /// * Midpoint mode (toggle OFF): the SELECTED clip is cut at
  ///   its midpoint and the status says exactly that.
  /// * After a successful split the selection stays on the FIRST
  ///   (left) part, so the centre — still on the boundary — can
  ///   never cascade.
  void _splitSelectedClip() {
    if (_busy) {
      explainToolTap();
      return;
    }
    if (_clips.isEmpty) return;
    final playheadMode = _snapOn;
    final selectedClip = _clips[_selected];
    double? centreSec;
    if (playheadMode && _tlScroll.hasClients && _tlPxPerSec > 0) {
      var c = (_tlScroll.offset / _tlPxPerSec)
          .clamp(0.0, _totalDurationSec)
          .toDouble();
      // G1.4: snap per the A20 setting (off = no snap at all);
      // cancel the snap if it would change the target clip.
      final thresh = tlSnapThreshold(false);
      if (thresh > 0) {
        final snapped = TimelineMath.snapSec(c, _snapPoints, thresh);
        if (snapped != c &&
            TimelineMath.indexAtSec(_effectiveDurations, snapped) ==
                TimelineMath.indexAtSec(_effectiveDurations, c)) {
          c = snapped;
        }
      }
      centreSec = c;
    }
    // The cut decision is the pure resolveSplit (editor_stage)
    // — the functional tests pin it; this method only applies
    // the trim math below (which was already correct).
    final res = resolveSplit(
      effectiveDurations: _effectiveDurations,
      trimStarts: [for (final c in _clips) c.trimStart],
      selected: _selected,
      clockInsideSelected:
          !selectedClip.isPhoto && _clock.isInitialized
              ? _clock.filePositionSec - selectedClip.trimStart
              : 0.0,
      centreSec: centreSec,
      playheadMode: playheadMode,
    );
    if (res == null) return; // unreachable: inputs guarded above
    if (res.refusal == SplitRefusal.tooSmall) {
      _setStatus('The clip is too short — it cannot be split.');
      return;
    }
    if (res.refusal == SplitRefusal.atEdge) {
      _setStatus(
        'The playhead is exactly on the clip\'s edge — the split was not cut. '
        'Move the line a little inward, or from the Split panel '
        'Choose "From the middle".',
      );
      return;
    }
    final target = res.index;
    final clip = _clips[target];
    final mid = res.cutFileSec;
    final second = VideoClip(clip.file, clip.duration, clip.aspectRatio);
    second.volume = clip.volume;
    second.muted = clip.muted;
    second.isPhoto = clip.isPhoto;
    second.kenBurns = clip.kenBurns;
    second.kbZoomIn = clip.kbZoomIn;
    second.trimStart = mid;
    second.trimEnd = clip.effectiveEnd;
    _pushHistory();
    clip.trimEnd = mid;
    setState(() {
      _clips.insert(target + 1, second);
      // Selection stays on the FIRST part (G1.2 anti-cascade).
      _selected = target;
    });
    HapticFeedback.selectionClick();
    _setStatus(
      playheadMode
          ? 'Split done — cut at the playhead, 2 clips created.'
          : 'Split done — cut from the middle, 2 clips created.',
    );
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
      backgroundImagePath: _proChromaBgKind == 'image'
          ? _proChromaBgImage
          : null,
      spill: _proChromaSpill,
      edge: _proChromaEdge,
    );
  }

  /// Debounced live keyed preview (addendum B.3): slider/colour
  /// changes re-render ONE frame through the exact export graph.
  void _scheduleChromaPreview() {
    _chromaPreviewTimer?.cancel();
    _chromaPreviewTimer = Timer(
      const Duration(milliseconds: 450),
      _refreshChromaPreview,
    );
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
      _setStatus('Select a clip first.');
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
        _setStatus('Frame not found — play the video and try again.');
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
      _setStatus('Backdrop did not load: $e');
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







  /// Display name for a tool key (used in the panel header).
  String _toolDisplayName(String key) {
    const Map<String, String> names = <String, String>{
      'canvas': 'Canvas',
      'audio': 'Audio',
      'text': 'Text',
      'colour': 'Colour',
      'effects': 'Effects',
      'overlay': 'Overlay',
      'precut': 'Precut',
      'volume': 'Volume',
      'clipVolume': 'Volume',
      'speed': 'Speed',
      'aicut': 'AI Cut',
      'voiceenhance': 'Voice Enhance',
      'edit': 'Crop',
      'enhance': 'Enhance',
      'stabilizer': 'Stabilizer',
      'cutout': 'Cutout',
      'mask': 'Mask',
      'opacity': 'Opacity',
      'rotate': 'Rotate',
      'ease': 'Ease',
      'transitions': 'Transitions',
      'news': 'News',
    };
    return names[key] ?? key;
  }


  /// v1.5.0 top bar (mockups V1/V2 — NO AppBar): back arrow, help
  /// (the tool index lives inside it), quality as plain text, and
  /// Export as PLAIN TEXT top-right (no pill).
  Widget _topBar() {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      color: const Color(0xFF1E1E1E),
      padding: EdgeInsets.fromLTRB(4, topPad + 2, 8, 2),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close editor',
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          IconButton(
            tooltip: 'Help — saare tools ki list',
            icon: const Icon(Icons.help_outline, color: Colors.white),
            onPressed: _busy ? null : _showToolSearch,
          ),
          const Spacer(),
          TextButton(
            onPressed: _busy ? null : _pickExportSettings,
            child: Text(
              _qualityLabel,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            // Phase 0: while an export runs, this button is the
            // CANCEL for it (the Export action returns the moment
            // the export ends or is cancelled). Other busy states
            // keep the old disabled "Exporting…" behaviour.
            onPressed: _exporting
                ? _cancelExport
                : (_busy ? null : _export),
            child: Text(
              _exporting ? 'Cancel' : (_busy ? 'Exporting…' : 'Export'),
              style: TextStyle(
                color: _exporting ? Colors.redAccent : TjProTheme.gold,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
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
    // PIP preview sync (idempotent; only acts on a pick change).
    if ((_fxPip &&
            _fxPipVideo.isNotEmpty &&
            _pipControllerPath != _fxPipVideo) ||
        (!_fxPip && _pipController != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePipPreview());
    }
    // v1.5.0: build() no longer reads the controller's position —
    // the transport row listens to the ONE TimelineClock instead
    // (#30: the frozen counter's root cause was exactly this
    // read-once-per-build pattern).

    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: TjProTheme.gold,
          brightness: Brightness.dark,
        ),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        // LAYOUT v1.5.0 (InShot copy, mockups V1/V2): NO AppBar —
        // the custom top bar (back / help / quality / plain-text
        // Export) → handoff banner → stage (60% in row mode) →
        // transport row BELOW the stage → centred-playhead timeline
        // → ONE tool zone (main row / clip row / element row / the
        // open panel). Nothing else is ever open.
        body: Column(
          children: [
            _topBar(),
            if (_handoffProject != null)
              Container(
                width: double.infinity,
                color: const Color(0xFF1E1E2E),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  key: const Key('handoffProjectBanner'),
                  'News project: ${_projectTitle()} • ${_clips.length} clip(s)'
                  '${_projectVoiceoverPath == null ? '' : ' • voiceover'}'
                  ' • ${_projectTemplateKind ?? 'live'} template'
                  '${_projectLoading ? ' • load ho raha hai…' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            // ---- STAGE ----
            // v1.5.2 (fix #67/#69a): the stage sits in an Expanded
            // + LayoutBuilder — it takes exactly the space the
            // chrome leaves, capped at the 60% rule. Overflow is
            // now structurally impossible whatever the transport /
            // timeline / panel heights are (the old computed
            // _stageHeight chrome math kept drifting short).
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cap = MediaQuery.sizeOf(context).height * 0.60;
                  final h = constraints.maxHeight < cap
                      ? constraints.maxHeight
                      : cap;
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      height: h,
                      child: Container(
                        color: Colors.black,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: clip == null
                                  ? Center(
                                      // Scrollable (v1.5.2, #67/#69): on
                                      // short screens the stage can be
                                      // shorter than this empty-state column
                                      // (add box + labels) — scroll instead
                                      // of overflowing.
                                      child: SingleChildScrollView(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // + empty-state on the stage (§4):
                                            // the same add action as the
                                            // timeline's + tile.
                                            InkWell(
                                              onTap: _addClip,
                                              borderRadius:
                                                  BorderRadius.circular(16),
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
                                                    Icon(
                                                      Icons.add,
                                                      color: TjProTheme.gold,
                                                      size: 40,
                                                    ),
                                                    SizedBox(height: 4),
                                                    Text(
                                                      'Add video',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            const Text(
                                              'Add the first video — or the timeline '
                                              'ke + tile se.',
                                              style: TextStyle(
                                                color: Colors.white54,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : StageCanvas(host: this, clip: clip, ctrl: ctrl, ready: ready),
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
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.75,
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text(
                                      _status,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // ---- TRANSPORT (below the stage, #10) ----
            TransportRow(this),
            // ---- TIMELINE (directly under the transport) ----
            // Point #32 (v1.15.0 G2): while any tool panel is
            // open the TIMELINE HIDES — the freed height goes to
            // the stage, so the preview stays BIG (Point #27's
            // law, now in VE too) and only the open tool's
            // options show. The transport row stays: it is
            // preview chrome, not timeline.
            if (_activeTool == null) TimelineBar(this),
            // ---- TOOL ZONE: row ⇄ the one open panel ----
            // v1.5.2 (#69): NO AnimatedSwitcher here anymore —
            // its cross-fade kept the outgoing panel alive while
            // this SizedBox snapped 236 <-> 76, squeezing the
            // outgoing panel's Column into the wrong height and
            // overflowing it on every open/close. The sibling
            // editors (Photo, News Maker) swap instantly; so
            // does this zone now.
            SizedBox(
              height: _activeTool != null ? 236 : 76,
              child: _activeTool != null
                  ? Material(
                      key: ValueKey<String>('video-panel-${_activeTool!}'),
                      color: const Color(0xFF121212),
                      // Material, not a coloured Container
                      // (v1.5.2, #69): panels contain ListTiles /
                      // SwitchListTiles, which lose their
                      // background + ink under a ColoredBox.
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ToolPanelHeader(this, _activeTool!),
                            PanelTabRow(this),
                            Expanded(
                              // Point #29 (v1.15.0 G2): a body with
                              // 2+ sections drills — section chips
                              // in ONE line, only the chosen
                              // section below — instead of one long
                              // scrolling panel.
                              child: Builder(
                                builder: (context) {
                                  final children =
                                      toolPanelChildren(this, context);
                                  if (PanelDrillDown.appliesTo(
                                      children)) {
                                    return PanelDrillDown(
                                      this,
                                      key: ValueKey<String>(
                                          'drill-${_activeTool!}-'
                                          '${_panelTab ?? ''}'),
                                      children: children,
                                    );
                                  }
                                  return ListView(
                                    padding:
                                        const EdgeInsets.only(top: 4),
                                    children: children,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _elementRow && _fxPip
                  ? ElementToolRow(this)
                  : _clipRow && _clips.isNotEmpty
                  ? ClipToolRow(this)
                  : MainToolRow(this),
            ),
          ],
        ),
      ),
    );
  }

  /// Pipeline checkpoint: throws [ExportCancelled] when
  /// [_cancelExport] has run. Placed between the export stages
  /// (OUTSIDE their guarded try blocks) so a cancel stops the
  /// NEXT stage from starting.
  void _checkExportCancelled() {
    if (_exportCancelRequested) throw const ExportCancelled();
  }

  // ── Phase 4: VideoEditorController forwards ──────────────────
  // Thin forwards: each public member below delegates to the
  // private member of the same name, so the split-out widgets
  // (panels / timeline / tool rows / stage / export) can reach
  // the editor state through the contract with no behaviour
  // change.
  @override
  void update(VoidCallback fn) => setState(fn);

  @override
  void cancelPanel() => _cancelPanel();

  @override
  Future<void> openFullscreen() => _openFullscreen();

  @override
  Future<void> redo() => _redo();

  @override
  List<String> get redoStack => _redoStack;

  @override
  Future<void> seekToGlobalSec(double sec) => _seekToGlobalSec(sec);

  @override
  Future<void> switchSelectedClipToPip() => _switchSelectedClipToPip();

  @override
  String toolDisplayName(String key) => _toolDisplayName(key);

  @override
  Future<void> undo() => _undo();

  @override
  List<String> get undoStack => _undoStack;

  @override
  String? get activeTool => _activeTool;
  @override
  set activeTool(String? value) => _activeTool = value;
  @override
  Future<void> addClip() => _addClip();
  @override
  Future<void> addPhotoClip() => _addPhotoClip();
  @override
  bool get adjAuto => _adjAuto;
  @override
  set adjAuto(bool value) => _adjAuto = value;
  @override
  double get adjBlacks => _adjBlacks;
  @override
  set adjBlacks(double value) => _adjBlacks = value;
  @override
  double get adjBrilliance => _adjBrilliance;
  @override
  set adjBrilliance(double value) => _adjBrilliance = value;
  @override
  double get adjClarity => _adjClarity;
  @override
  set adjClarity(double value) => _adjClarity = value;
  @override
  double get adjFade => _adjFade;
  @override
  set adjFade(double value) => _adjFade = value;
  @override
  double get adjGrain => _adjGrain;
  @override
  set adjGrain(double value) => _adjGrain = value;
  @override
  double get adjHue => _adjHue;
  @override
  set adjHue(double value) => _adjHue = value;
  @override
  double get adjSharpen => _adjSharpen;
  @override
  set adjSharpen(double value) => _adjSharpen = value;
  @override
  double get adjVignette => _adjVignette;
  @override
  set adjVignette(double value) => _adjVignette = value;
  @override
  double get adjWhites => _adjWhites;
  @override
  set adjWhites(double value) => _adjWhites = value;
  @override
  String adjustExtraFilter() => _adjustExtraFilter();
  @override
  List<CaptionSegment> adjustedCaptions() => _adjustedCaptions();
  @override
  bool get aicutBusy => _aicutBusy;
  @override
  set aicutBusy(bool value) => _aicutBusy = value;
  @override
  double get aicutMinSilenceSec => _aicutMinSilenceSec;
  @override
  set aicutMinSilenceSec(double value) => _aicutMinSilenceSec = value;
  @override
  List<(double, double)> get aicutRanges => _aicutRanges;
  @override
  set aicutRanges(List<(double, double)> value) => _aicutRanges = value;
  @override
  double get aicutThresholdDb => _aicutThresholdDb;
  @override
  set aicutThresholdDb(double value) => _aicutThresholdDb = value;
  @override
  Future<void> applyBackdropAsset(String asset) => _applyBackdropAsset(asset);
  @override
  void applyNewsAnchorPreset() => _applyNewsAnchorPreset();
  @override
  void applyPreviewSpeed([double? rate]) => _applyPreviewSpeed(rate);
  @override
  Future<void> applySlowMoAi() => _applySlowMoAi();
  @override
  String get aspect => _aspect;
  @override
  set aspect(String value) => _aspect = value;
  @override
  bool get autoDuck => _autoDuck;
  @override
  set autoDuck(bool value) => _autoDuck = value;
  @override
  bool get beatAutoCut => _beatAutoCut;
  @override
  set beatAutoCut(bool value) => _beatAutoCut = value;
  @override
  List<double> get beats => _beats;
  @override
  set beats(List<double> value) => _beats = value;
  @override
  List<double> get timelineBeats => TimelineMath.beatsToTimeline(
        beats: _beats,
        sourceIsMusic: _beatSourceMusic,
        sourceClipIndex: _beatSourceMusic
            ? -1
            : _clips.indexWhere((c) => c.file.path == _beatSourcePath),
        clipStarts: [
          for (var i = 0; i < _clips.length; i++) _clipStartSec(i),
        ],
        trimStarts: [for (final c in _clips) c.trimStart],
        effectiveDurations: _effectiveDurations,
      );
  @override
  List<double> get markers => _markers;
  @override
  set markers(List<double> value) => _markers = value;
  @override
  void addMarkerAtPlayhead() => _addMarkerAtPlayhead();
  @override
  void removeMarker(double sec) => _removeMarker(sec);
  @override
  Future<void> importCaptionsFile() => _importCaptionsFile();
  @override
  Future<void> shareCaptionsFile(String kind) => _shareCaptionsFile(kind);
  @override
  Future<String?> buildOverlayCommand({ required Directory dir, required int stamp, required String input, required String output, required double durationSec, }) => _buildOverlayCommand(dir: dir, stamp: stamp, input: input, output: output, durationSec: durationSec);
  @override
  bool get busy => _busy;
  @override
  set busy(bool value) => _busy = value;
  @override
  String get canvasFill => _canvasFill;
  @override
  set canvasFill(String value) => _canvasFill = value;
  @override
  String get canvasFillColor => _canvasFillColor;
  @override
  set canvasFillColor(String value) => _canvasFillColor = value;
  @override
  bool get captionDrawtextFallback => _captionDrawtextFallback;
  @override
  set captionDrawtextFallback(bool value) => _captionDrawtextFallback = value;
  @override
  String get captionLocale => _captionLocale;
  @override
  set captionLocale(String value) => _captionLocale = value;
  @override
  CaptionStyle get captionStyle => _captionStyle;
  @override
  set captionStyle(CaptionStyle value) => _captionStyle = value;
  @override
  List<CaptionSegment> get captions => _captions;
  @override
  bool get captionsTimelineRelative => _captionsTimelineRelative;
  @override
  Future<void> editCaptionAt(int index) => _editCaptionAt(index);
  @override
  set captions(List<CaptionSegment> value) => _captions = value;
  @override
  Future<void> captureFrameInsert() => _captureFrameInsert();
  @override
  void checkExportCancelled() => _checkExportCancelled();
  @override
  bool get chromaPreviewBusy => _chromaPreviewBusy;
  @override
  set chromaPreviewBusy(bool value) => _chromaPreviewBusy = value;
  @override
  String? get chromaPreviewPath => _chromaPreviewPath;
  @override
  set chromaPreviewPath(String? value) => _chromaPreviewPath = value;
  @override
  bool get clipRow => _clipRow;
  @override
  set clipRow(bool value) => _clipRow = value;
  @override
  double clipStartSec(int index) => _clipStartSec(index);
  @override
  List<VideoClip> get clips => _clips;
  @override
  TimelineClock get clock => _clock;
  @override
  bool get comparing => _comparing;
  @override
  set comparing(bool value) => _comparing = value;
  @override
  VideoPlayerController? get controller => _controller;
  @override
  set controller(VideoPlayerController? value) => _controller = value;
  @override
  bool get crossfade => _crossfade;
  @override
  set crossfade(bool value) => _crossfade = value;
  @override
  double get cutEnd => _cutEnd;
  @override
  set cutEnd(double value) => _cutEnd = value;
  @override
  double get cutStart => _cutStart;
  @override
  set cutStart(double value) => _cutStart = value;
  @override
  String get cutoutMode => _cutoutMode;
  @override
  set cutoutMode(String value) => _cutoutMode = value;
  @override
  Future<void> deleteSelectedClip() => _deleteSelectedClip();
  @override
  Future<void> runBeatDetection() => _detectBeats();
  @override
  bool get detectingBeats => _detectingBeats;
  @override
  set detectingBeats(bool value) => _detectingBeats = value;
  @override
  void duplicateSelectedClip() => _duplicateSelectedClip();
  @override
  void toggleSelectedClipDisabled() => _toggleSelectedClipDisabled();
  @override
  void setSelectedClipColorLabel(int label) =>
      _setSelectedClipColorLabel(label);
  @override
  Future<void> editCaptions() => _editCaptions();
  @override
  List<double> get effectiveDurations => _effectiveDurations;
  @override
  bool get elementRow => _elementRow;
  @override
  set elementRow(bool value) => _elementRow = value;
  @override
  Future<void> enhanceSelectedClipAudio({required bool voice}) => _enhanceSelectedClipAudio(voice: voice);
  @override
  Future<void> enhanceSelectedClipHd() => _enhanceSelectedClipHd();
  @override
  void ensureMainMaskImage(int width, int height) => _ensureMainMaskImage(width, height);
  @override
  Future<void> ensureMusicWave(String musicPath) => _ensureMusicWave(musicPath);
  @override
  void ensurePipMaskImage(int width, int height) => _ensurePipMaskImage(width, height);
  @override
  void ensurePipPreview() => _ensurePipPreview();
  @override
  bool get exportCancelRequested => _exportCancelRequested;
  @override
  set exportCancelRequested(bool value) => _exportCancelRequested = value;
  @override
  int get exportFps => _exportFps;
  @override
  set exportFps(int value) => _exportFps = value;
  @override
  bool get exporting => _exporting;
  @override
  set exporting(bool value) => _exporting = value;
  @override
  Future<void> extractClipAudio() => _extractClipAudio();
  @override
  Future<void> eyedropperPick() => _eyedropperPick();
  @override
  String get filter => _filter;
  @override
  set filter(String value) => _filter = value;
  @override
  double get filterIntensity => _filterIntensity;
  @override
  set filterIntensity(double value) => _filterIntensity = value;
  @override
  String? get fontFile => _fontFile;
  @override
  set fontFile(String? value) => _fontFile = value;
  @override
  Color frameBackdropColor() => _frameBackdropColor();
  @override
  Future<void> freezeFrameInsert() => _freezeFrameInsert();
  @override
  double get fxFadeIn => _fxFadeIn;
  @override
  set fxFadeIn(double value) => _fxFadeIn = value;
  @override
  double get fxFadeOut => _fxFadeOut;
  @override
  set fxFadeOut(double value) => _fxFadeOut = value;
  @override
  bool get fxPip => _fxPip;
  @override
  set fxPip(bool value) => _fxPip = value;
  @override
  String get fxPipVideo => _fxPipVideo;
  @override
  set fxPipVideo(String value) => _fxPipVideo = value;
  @override
  int get fxQuality => _fxQuality;
  @override
  set fxQuality(int value) => _fxQuality = value;
  @override
  bool get fxReverse => _fxReverse;
  @override
  ShakeFx get fxShake => _fxShake;
  @override
  set fxShake(ShakeFx value) => _fxShake = value;
  @override
  bool get fxSilenceRemove => _fxSilenceRemove;
  @override
  set fxSilenceRemove(bool value) => _fxSilenceRemove = value;
  @override
  VoiceFx get fxVoice => _fxVoice;
  @override
  set fxVoice(VoiceFx value) => _fxVoice = value;
  @override
  Future<void> generateCaptions() => _generateCaptions();
  @override
  Future<void> generateUrduCaptions() => _generateUrduCaptions();
  @override
  double get globalPositionSec => _globalPositionSec;
  @override
  bool get gradeActive => _gradeActive;
  @override
  String get gradeSlider => _gradeSlider;
  @override
  set gradeSlider(String value) => _gradeSlider = value;
  @override
  ChannelPreset? get handoffPreset => _handoffPreset;
  @override
  set handoffPreset(ChannelPreset? value) => _handoffPreset = value;
  @override
  NewsProject? get handoffProject => _handoffProject;
  @override
  set handoffProject(NewsProject? value) => _handoffProject = value;
  @override
  String? get introClipPath => _introClipPath;
  @override
  set introClipPath(String? value) => _introClipPath = value;
  @override
  KeyframeEasing get kfEasing => _kfEasing;
  @override
  set kfEasing(KeyframeEasing value) => _kfEasing = value;
  @override
  double get kfEndOpacity => _kfEndOpacity;
  @override
  set kfEndOpacity(double value) => _kfEndOpacity = value;
  @override
  double get kfEndRotation => _kfEndRotation;
  @override
  set kfEndRotation(double value) => _kfEndRotation = value;
  @override
  double get kfEndScale => _kfEndScale;
  @override
  set kfEndScale(double value) => _kfEndScale = value;
  @override
  double get kfEndX => _kfEndX;
  @override
  set kfEndX(double value) => _kfEndX = value;
  @override
  double get kfEndY => _kfEndY;
  @override
  set kfEndY(double value) => _kfEndY = value;
  @override
  int get kfPage => _kfPage;
  @override
  set kfPage(int value) => _kfPage = value;
  @override
  double get kfStartOpacity => _kfStartOpacity;
  @override
  set kfStartOpacity(double value) => _kfStartOpacity = value;
  @override
  double get kfStartRotation => _kfStartRotation;
  @override
  set kfStartRotation(double value) => _kfStartRotation = value;
  @override
  double get kfStartScale => _kfStartScale;
  @override
  set kfStartScale(double value) => _kfStartScale = value;
  @override
  double get kfStartX => _kfStartX;
  @override
  set kfStartX(double value) => _kfStartX = value;
  @override
  double get kfStartY => _kfStartY;
  @override
  set kfStartY(double value) => _kfStartY = value;
  @override
  Set<String> get laneHidden => _laneHidden;
  @override
  Future<void> loadPreview() => _loadPreview();
  @override
  String get mainMask => _mainMask;
  @override
  set mainMask(String value) => _mainMask = value;
  @override
  double get mainMaskFeather => _mainMaskFeather;
  @override
  set mainMaskFeather(double value) => _mainMaskFeather = value;
  @override
  ui.Image? get mainMaskImage => _mainMaskImage;
  @override
  set mainMaskImage(ui.Image? value) => _mainMaskImage = value;
  @override
  bool get mainMaskInvert => _mainMaskInvert;
  @override
  set mainMaskInvert(bool value) => _mainMaskInvert = value;
  @override
  bool get mainTrackLocked => _mainTrackLocked;
  @override
  set mainTrackLocked(bool value) => _mainTrackLocked = value;
  @override
  String? get musicPath => _musicPath;
  @override
  set musicPath(String? value) => _musicPath = value;
  @override
  double get musicVolume => _musicVolume;
  @override
  set musicVolume(double value) => _musicVolume = value;
  @override
  bool get musicMuted => _musicMuted;
  @override
  set musicMuted(bool value) => _musicMuted = value;
  @override
  bool get pipLaneLocked => _pipLaneLocked;
  @override
  set pipLaneLocked(bool value) => _pipLaneLocked = value;
  @override
  Map<String, String> get musicWaveCache => _musicWaveCache;
  @override
  Map<String, String> get clipWaveCache => _clipWaveCache;
  @override
  void ensureClipWave(VideoClip clip) => _ensureClipWave(clip);
  @override
  String clipWaveKey(VideoClip clip) => _clipWaveKey(clip);
  @override
  bool get muteOriginal => _muteOriginal;
  @override
  set muteOriginal(bool value) => _muteOriginal = value;
  @override
  NewsTemplate get news => _news;
  @override
  set news(NewsTemplate value) => _news = value;
  @override
  bool get newsEnabled => _newsEnabled;
  @override
  set newsEnabled(bool value) => _newsEnabled = value;
  @override
  Future<void> onBgRemoverChanged(bool v) => _onBgRemoverChanged(v);
  @override
  void onClipDragEnd(int i) => _onClipDragEnd(i);
  @override
  void onClipDragMove(LongPressMoveUpdateDetails d) => _onClipDragMove(d);
  @override
  void onClipDragStart(int i) => _onClipDragStart(i);
  @override
  void onPreviewTapDown(TapDownDetails d, Size mediaBox) => _onPreviewTapDown(d, mediaBox);
  @override
  void onStageScaleStart(ScaleStartDetails d) => _onStageScaleStart(d);
  @override
  void onStageScaleUpdate(ScaleUpdateDetails d) => _onStageScaleUpdate(d);
  @override
  void openTool(String? key) => _openTool(key);
  @override
  void openToolTab(String key, String tab) => _openToolTab(key, tab);
  @override
  String? get outroClipPath => _outroClipPath;
  @override
  set outroClipPath(String? value) => _outroClipPath = value;
  @override
  String? get panelTab => _panelTab;
  @override
  set panelTab(String? value) => _panelTab = value;
  @override
  Future<bool?> pickExportSettings() => _pickExportSettings();
  @override
  Future<void> pickMusic() => _pickMusic();
  @override
  Future<void> pickProImage(ValueChanged<String> onPicked) => _pickProImage(onPicked);
  @override
  ImagePicker get picker => _picker;
  @override
  double get pinchPipScale => _pinchPipScale;
  @override
  set pinchPipScale(double value) => _pinchPipScale = value;
  @override
  String get pipBlend => _pipBlend;
  @override
  set pipBlend(String value) => _pipBlend = value;
  @override
  BlendMode? pipBlendMode(String key) => _pipBlendMode(key);
  @override
  VideoPlayerController? get pipController => _pipController;
  @override
  set pipController(VideoPlayerController? value) => _pipController = value;
  @override
  Offset get pipDragOffset => _pipDragOffset;
  @override
  set pipDragOffset(Offset value) => _pipDragOffset = value;
  @override
  bool get pipKeyframes => _pipKeyframes;
  @override
  set pipKeyframes(bool value) => _pipKeyframes = value;
  @override
  String get pipMask => _pipMask;
  @override
  set pipMask(String value) => _pipMask = value;
  @override
  double get pipMaskFeather => _pipMaskFeather;
  @override
  set pipMaskFeather(double value) => _pipMaskFeather = value;
  @override
  ui.Image? get pipMaskImage => _pipMaskImage;
  @override
  set pipMaskImage(ui.Image? value) => _pipMaskImage = value;
  @override
  bool get pipMaskInvert => _pipMaskInvert;
  @override
  set pipMaskInvert(bool value) => _pipMaskInvert = value;
  @override
  double get pipOpacity => _pipOpacity;
  @override
  set pipOpacity(double value) => _pipOpacity = value;
  @override
  PipPosition get pipPosition => _pipPosition;
  @override
  set pipPosition(PipPosition value) => _pipPosition = value;
  @override
  double get pipScale => _pipScale;
  @override
  set pipScale(double value) => _pipScale = value;
  @override
  double get pipStartSec => _pipStartSec;
  @override
  set pipStartSec(double value) => _pipStartSec = value;
  @override
  double get pipEndSec => _pipEndSec;
  @override
  set pipEndSec(double value) => _pipEndSec = value;
  @override
  String pipSnippetAdvanced({ required VideoSize base, required VideoSize pip, required bool hasMask, }) => _pipSnippetAdvanced(base: base, pip: pip, hasMask: hasMask);
  @override
  KeyframeEasing get pkEasing => _pkEasing;
  @override
  set pkEasing(KeyframeEasing value) => _pkEasing = value;
  @override
  double get pkEndOpacity => _pkEndOpacity;
  @override
  set pkEndOpacity(double value) => _pkEndOpacity = value;
  @override
  double get pkEndX => _pkEndX;
  @override
  set pkEndX(double value) => _pkEndX = value;
  @override
  double get pkEndY => _pkEndY;
  @override
  set pkEndY(double value) => _pkEndY = value;
  @override
  int get pkPage => _pkPage;
  @override
  set pkPage(int value) => _pkPage = value;
  @override
  double get pkStartOpacity => _pkStartOpacity;
  @override
  set pkStartOpacity(double value) => _pkStartOpacity = value;
  @override
  double get pkStartX => _pkStartX;
  @override
  set pkStartX(double value) => _pkStartX = value;
  @override
  double get pkStartY => _pkStartY;
  @override
  set pkStartY(double value) => _pkStartY = value;
  @override
  String get proBgColor => _proBgColor;
  @override
  set proBgColor(String value) => _proBgColor = value;
  @override
  String? get proBgImage => _proBgImage;
  @override
  set proBgImage(String? value) => _proBgImage = value;
  @override
  String get proBgKind => _proBgKind;
  @override
  set proBgKind(String value) => _proBgKind = value;
  @override
  bool get proBgRemove => _proBgRemove;
  @override
  set proBgRemove(bool value) => _proBgRemove = value;
  @override
  double get proBrightness => _proBrightness;
  @override
  set proBrightness(double value) => _proBrightness = value;
  @override
  bool get proChroma => _proChroma;
  @override
  set proChroma(bool value) => _proChroma = value;
  @override
  String get proChromaBgColor => _proChromaBgColor;
  @override
  set proChromaBgColor(String value) => _proChromaBgColor = value;
  @override
  String? get proChromaBgImage => _proChromaBgImage;
  @override
  set proChromaBgImage(String? value) => _proChromaBgImage = value;
  @override
  String get proChromaBgKind => _proChromaBgKind;
  @override
  set proChromaBgKind(String value) => _proChromaBgKind = value;
  @override
  double get proChromaBlend => _proChromaBlend;
  @override
  set proChromaBlend(double value) => _proChromaBlend = value;
  @override
  String get proChromaColor => _proChromaColor;
  @override
  set proChromaColor(String value) => _proChromaColor = value;
  @override
  double get proChromaEdge => _proChromaEdge;
  @override
  set proChromaEdge(double value) => _proChromaEdge = value;
  @override
  double get proChromaSimilarity => _proChromaSimilarity;
  @override
  set proChromaSimilarity(double value) => _proChromaSimilarity = value;
  @override
  double get proChromaSpill => _proChromaSpill;
  @override
  set proChromaSpill(double value) => _proChromaSpill = value;
  @override
  double get proContrast => _proContrast;
  @override
  set proContrast(double value) => _proContrast = value;
  @override
  double get proExposure => _proExposure;
  @override
  set proExposure(double value) => _proExposure = value;
  @override
  double get proHighlights => _proHighlights;
  @override
  set proHighlights(double value) => _proHighlights = value;
  @override
  bool get proKeyframes => _proKeyframes;
  @override
  set proKeyframes(bool value) => _proKeyframes = value;
  @override
  String get proLut => _proLut;
  @override
  set proLut(String value) => _proLut = value;
  @override
  String get proRamp => _proRamp;
  @override
  set proRamp(String value) => _proRamp = value;
  @override
  double get proSaturation => _proSaturation;
  @override
  set proSaturation(double value) => _proSaturation = value;
  @override
  double get proShadows => _proShadows;
  @override
  set proShadows(double value) => _proShadows = value;
  @override
  bool get proStabilize => _proStabilize;
  @override
  set proStabilize(bool value) => _proStabilize = value;
  @override
  String get proSticker => _proSticker;
  @override
  set proSticker(String value) => _proSticker = value;
  @override
  String get proStickerPreset => _proStickerPreset;
  @override
  set proStickerPreset(String value) => _proStickerPreset = value;
  @override
  double get proTemperature => _proTemperature;
  @override
  set proTemperature(double value) => _proTemperature = value;
  @override
  double get proTint => _proTint;
  @override
  set proTint(double value) => _proTint = value;
  @override
  String get proTitle => _proTitle;
  @override
  set proTitle(String value) => _proTitle = value;
  @override
  String get proTitlePosition => _proTitlePosition;
  @override
  set proTitlePosition(String value) => _proTitlePosition = value;
  @override
  String get proTitlePreset => _proTitlePreset;
  @override
  set proTitlePreset(String value) => _proTitlePreset = value;
  @override
  String get proTransition => _proTransition;
  @override
  set proTransition(String value) => _proTransition = value;
  @override
  double get proTransitionDur => _proTransitionDur;
  @override
  set proTransitionDur(double value) => _proTransitionDur = value;
  @override
  double get proVibrance => _proVibrance;
  @override
  set proVibrance(double value) => _proVibrance = value;
  @override
  String? get projectTemplateKind => _projectTemplateKind;
  @override
  set projectTemplateKind(String? value) => _projectTemplateKind = value;
  @override
  String? get projectVoiceoverPath => _projectVoiceoverPath;
  @override
  set projectVoiceoverPath(String? value) => _projectVoiceoverPath = value;
  @override
  void pushHistory() => _pushHistory();
  @override
  bool get qualityPicked => _qualityPicked;
  @override
  set qualityPicked(bool value) => _qualityPicked = value;
  @override
  double get rampEnd => _rampEnd;
  @override
  set rampEnd(double value) => _rampEnd = value;
  @override
  double get rampMid => _rampMid;
  @override
  set rampMid(double value) => _rampMid = value;
  @override
  RampPreset? rampPreset() => _rampPreset();
  @override
  double get rampStart => _rampStart;
  @override
  set rampStart(double value) => _rampStart = value;
  @override
  Future<void> refreshChromaPreview() => _refreshChromaPreview();
  @override
  Future<String?> renderMainMaskPng({ required Directory dir, required int stamp, required int width, required int height, }) => _renderMainMaskPng(dir: dir, stamp: stamp, width: width, height: height);
  @override
  Future<String?> renderPipMaskPng({ required Directory dir, required int stamp, required int width, required int height, }) => _renderPipMaskPng(dir: dir, stamp: stamp, width: width, height: height);
  @override
  Future<void> replaceSelectedClip() => _replaceSelectedClip();
  @override
  void resetGrade() => _resetGrade();
  @override
  void resetStageTransform() => _resetStageTransform();
  @override
  Future<void> reverseSelectedClip() => _reverseSelectedClip();
  @override
  Future<void> rotateSelectedClip({required bool flip}) => _rotateSelectedClip(flip: flip);
  @override
  Future<void> saveFrameSnapshot() => _saveFrameSnapshot();
  @override
  void scheduleChromaPreview() => _scheduleChromaPreview();
  @override
  void scheduleScrubSeek() => _scheduleScrubSeek();
  @override
  int get selected => _selected;
  @override
  set selected(int value) => _selected = value;
  @override
  void setStatus(String s) => _setStatus(s);
  @override
  bool get showGrid => _showGrid;
  @override
  set showGrid(bool value) => _showGrid = value;
  @override
  Future<void> showWaveform() => _showWaveform();
  @override
  bool get snapOn => _snapOn;
  @override
  set snapOn(bool value) => _snapOn = value;
  @override
  double get speed => _speed;
  @override
  set speed(double value) => _speed = value;
  @override
  void splitSelectedClip() => _splitSelectedClip();
  @override
  int get stabLevel => _stabLevel;
  @override
  set stabLevel(int value) => _stabLevel = value;
  @override
  Rect get stageFrameRect => _stageFrameRect;
  @override
  set stageFrameRect(Rect value) => _stageFrameRect = value;
  @override
  String? get stageLayer => _stageLayer;
  @override
  set stageLayer(String? value) => _stageLayer = value;
  @override
  List<double> get stageMatrix => _stageMatrix;

  @override
  double get adjustVignetteStrength => _comparing
      ? 0
      : deriveAdjustParams(_adjustValues).vignetteStrength;

  @override
  double get adjustGrainOpacity =>
      _comparing ? 0 : deriveAdjustParams(_adjustValues).grainOpacity;

  @override
  void explainToolTap() {
    if (_busy) {
      _setStatus(
        _status.isNotEmpty
            ? 'Currently running: $_status'
            : 'A task is already running — let it finish, '
                'then try again.',
      );
    } else if (_clips.isEmpty) {
      _setStatus(
        'Add a clip first — without a clip this tool '
        'will not work.',
      );
    }
  }
  @override
  Rect get stageMediaRect => _stageMediaRect;
  @override
  set stageMediaRect(Rect value) => _stageMediaRect = value;
  @override
  Matrix4 stageTransformMatrix(Size frameSize) => _stageTransformMatrix(frameSize);
  @override
  String get status => _status;
  @override
  set status(String value) => _status = value;
  @override
  Future<void> switchPipToMainTrack() => _switchPipToMainTrack();
  @override
  String get text => _text;
  @override
  set text(String value) => _text = value;
  @override
  double get tfOpacity => _tfOpacity;
  @override
  set tfOpacity(double value) => _tfOpacity = value;
  @override
  double get tfRot => _tfRot;
  @override
  set tfRot(double value) => _tfRot = value;
  @override
  double get tfScale => _tfScale;
  @override
  set tfScale(double value) => _tfScale = value;
  @override
  double get tfX => _tfX;
  @override
  set tfX(double value) => _tfX = value;
  @override
  double get tfY => _tfY;
  @override
  set tfY(double value) => _tfY = value;
  @override
  Map<String, List<String>> get thumbCache => _thumbCache;
  @override
  String thumbKey(VideoClip clip) => _thumbKey(clip);
  @override
  double get tlPxPerSec => _tlPxPerSec;
  @override
  set tlPxPerSec(double value) => _tlPxPerSec = value;
  @override
  ScrollController get tlScroll => _tlScroll;
  @override
  bool get tlUserScrolling => _tlUserScrolling;
  @override
  bool get tlProgrammaticScroll => _tlProgrammaticScroll;
  @override
  set tlProgrammaticScroll(bool v) => _tlProgrammaticScroll = v;
  @override
  set tlUserScrolling(bool value) => _tlUserScrolling = value;
  @override
  void tlZoomBy(double factor) => _tlZoomBy(factor);

  @override
  void tlZoomToFit(double widthPx) => _tlZoomTo(
        TimelineMath.pxPerSecToFit(
          totalSec: _totalDurationSec,
          widthPx: widthPx,
        ),
      );

  @override
  void tlPinchStart() => _tlPinchStart();

  @override
  void tlPinchUpdate(double scale) => _tlPinchUpdate(scale);

  @override
  bool get tlSnapOn => _tlSnapOn;

  @override
  set tlSnapOn(bool value) {
    _tlSnapOn = value;
    _saveTimelinePrefs();
  }

  @override
  int get tlSnapStrength => _tlSnapStrength;

  @override
  set tlSnapStrength(int value) {
    _tlSnapStrength = value;
    _saveTimelinePrefs();
  }

  @override
  double tlSnapThreshold(bool forTrim) => TimelineMath.snapThreshold(
        on: _tlSnapOn,
        strength: _tlSnapStrength,
        forTrim: forTrim,
      );

  @override
  bool get timecodeOn => _timecodeOn;

  @override
  set timecodeOn(bool value) {
    _timecodeOn = value;
    _saveTimelinePrefs();
  }

  @override
  void stepFrame(int direction) => _stepFrame(direction);

  @override
  String get trimMode => _trimMode;

  @override
  set trimMode(String value) => _trimMode = value;

  @override
  void rollBoundaryBy(int boundaryIndex, double delta) =>
      _rollBoundaryBy(boundaryIndex, delta);

  @override
  void slipSelectedBy(double delta) => _slipSelectedBy(delta);

  @override
  void trimToPlayheadStart() => _trimToPlayheadStart();

  @override
  void trimToPlayheadEnd() => _trimToPlayheadEnd();

  @override
  bool get multiMode => _multiMode;

  @override
  set multiMode(bool value) => _multiMode = value;

  @override
  Set<int> get multiSelect => _multiSelect;

  @override
  void toggleMultiSelect(int i) => _toggleMultiSelect(i);

  @override
  void clearMultiSelect() => _clearMultiSelect();

  @override
  Future<void> deleteMultiSelected() => _deleteMultiSelected();

  @override
  void duplicateMultiSelected() => _duplicateMultiSelected();

  @override
  void moveMultiSelected(int direction) => _moveMultiSelected(direction);

  @override
  double? get rangeIn => _rangeIn;

  @override
  double? get rangeOut => _rangeOut;

  @override
  bool get loopRange => _loopRange;

  @override
  set loopRange(bool value) => _loopRange = value;

  @override
  void setRangeInAtPlayhead() => _setRangeInAtPlayhead();

  @override
  void setRangeOutAtPlayhead() => _setRangeOutAtPlayhead();

  @override
  void clearRange() => _clearRange();

  @override
  Future<void> deleteRange() => _deleteRange();
  @override
  double get totalDurationSec => _totalDurationSec;
  @override
  Future<void> runObjectTracking() => _trackObject();
  @override
  List<TrackPoint> get trackPoints => _trackPoints;
  @override
  set trackPoints(List<TrackPoint> value) => _trackPoints = value;
  @override
  double? get trackStartX => _trackStartX;
  @override
  set trackStartX(double? value) => _trackStartX = value;
  @override
  double? get trackStartY => _trackStartY;
  @override
  set trackStartY(double? value) => _trackStartY = value;
  @override
  String get trackSticker => _trackSticker;
  @override
  set trackSticker(String value) => _trackSticker = value;
  @override
  bool get tracking => _tracking;
  @override
  set tracking(bool value) => _tracking = value;
  @override
  bool get transcribing => _transcribing;
  @override
  set transcribing(bool value) => _transcribing = value;
  @override
  bool get transformActive => _transformActive;
  @override
  bool get trimSnapped => _trimSnapped;
  @override
  set trimSnapped(bool value) => _trimSnapped = value;
  @override
  Future<void> unlinkSelectedClipAudio() => _unlinkSelectedClipAudio();
  @override
  List<(double, double)> get volumePoints => _volumePoints;
  @override
  bool get waveformBusy => _waveformBusy;
  @override
  set waveformBusy(bool value) => _waveformBusy = value;
  @override
  String? get waveformPath => _waveformPath;
  @override
  set waveformPath(String? value) => _waveformPath = value;
  @override
  Future<Directory> workDir() => _workDir();
}

/// Composites its child against everything painted beneath it in
/// the same layer tree using [mode] — a saveLayer whose paint
/// carries the blend mode, so the layer's content blends with the
/// actual stage pixels under it (the video texture included). This
/// is the preview twin of the export's masked-blend chain: for
/// opaque inset pixels the result is the same blend equation;
/// at feathered/transparent edges both interpolate towards the
/// untouched base.



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
      title: const Text('Pick a colour — tap the frame'),
      content: SizedBox(
        width: 320,
        height: 320,
        child: _image == null
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
                builder: (context, constraints) {
                  final box = Size(constraints.maxWidth, constraints.maxHeight);
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
