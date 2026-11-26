/// News Maker editor (Phase 4, mockup 2; Phase 6: template choice
/// persists per project and the preview renders all three template
/// kinds for real).
///
/// Tehreer box (Urdu) → Gemini voiceover → clips → live 3-ribbon
/// template preview → project save as JSON (autosave on change).
/// Look: mockup 2 (`news-maker-editor.png`) — dark navy/black,
/// purple accents, preview up top.
///
/// What is REAL here:
///   - "Voice banao" REALLY calls [GeminiVoiceService] (chunked
///     ≤2000 chars, cache-first — repeats are free, 5/day cap).
///     The voice preview player plays the cached WAV back, and
///     "Regenerate" deletes the cached file and re-synthesises (costs
///     new proxy request(s) — the status line says so).
///   - Voice controls (Phase 5): speed 0.5–2.0x + pause between
///     sentences + background music — applied on-device to the
///     voiceover (see `tts_processing.dart`) and saved on the
///     project, so "Regenerate" re-applies them.
///   - Karaoke sync (Phase 5): once a voiceover exists, the
///     project's subtitles are re-timed against the REAL voiceover
///     duration (see `karaoke_sync.dart`) — no longer the Phase 4
///     word-count estimate. The "Captions →" button opens the
///     Caption Studio for the same project.
///   - Clips picker is real (gallery video + multi-file video pick,
///     reorder, remove) and clip paths live in the project JSON.
///   - Ticker field is paste-to-run (same contract as Phase 3): the
///     preview scrolls the pasted text immediately.
///   - Template & Studio and SEO are real navigation (the project
///     travels with them); saving is the shared project JSON.
///
/// What is DELIBERATELY NOT here (no fake buttons):
///   - NO One Click publish — publishing is PARKED (all 5 platform
///     approvals pending); the Publish UI lives in the AI News Maker's
///     later steps, not here.
///   - Export + Timeline (Phase 7, DONE): the "Export Reel" card below
///     runs the real FFmpeg reel export and "Open in Timeline" opens
///     the video editor with this project loaded.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../app_config.dart';
import '../live/news_template.dart';
import '../motion/motion_gallery_screen.dart';
import '../video/widgets/editor_stage.dart';
import '../widgets/tool_guide.dart';
import '../services/ai_tool_charge.dart';
import '../services/asset_download_service.dart';
import '../services/caption_styles.dart';
import '../services/crash_guard.dart';
import '../services/project_recovery.dart';
import '../services/remote_config_service.dart';
import '../services/coin_service.dart';
import '../services/ffmpeg_service.dart';
import '../services/font_registry.dart';
import '../services/gemini_voice_service.dart';
import '../services/library_service.dart';
import '../services/logo_key_service.dart';
import '../services/logo_loop_service.dart';
import '../services/logo_parts_service.dart';
import '../services/permanent_logo_service.dart';
import '../services/pricing_service.dart';
import '../services/pro_service.dart';
import '../services/supabase_service.dart';
import '../services/store_audio_preview.dart';
import '../services/store_service.dart';
import '../services/tts_processing.dart';
import '../services/tts_studio_service.dart';
import '../services/user_font_service.dart';
import 'advertise_screen.dart';
import 'ai_news_maker_screen.dart';
import 'breaking_templates.dart';
import 'caption_studio_screen.dart';
import 'channel_branding_screen.dart';
import 'channel_preset.dart';
import 'caption_alignment.dart';
import 'karaoke_sync.dart';
import 'logo_parts.dart';
import 'news_analysis.dart';
import 'element_override.dart';
import 'news_project.dart';
import 'teleprompter_screen.dart';
import 'seo_screen.dart';
import 'store_screen.dart';
import 'widgets/breaking_preview.dart';
import 'widgets/clip_picker.dart';
import 'widgets/font_picker.dart';
import 'widgets/nigraan_final_preview.dart';
import 'widgets/reel_export_card.dart';
import 'widgets/rotating_logo.dart';
import 'widgets/reporter_overlay.dart';
import 'widgets/studio_pickers.dart';
import 'widgets/styled_caption_preview.dart';
import 'widgets/template_media_preview.dart';
import 'widgets/voice_preview_player.dart';

/// B7 filmstrip math (v1.16.0 G5, pure): the frame times for a
/// clip's timeline filmstrip — one frame per ~4 s of clip, at
/// least 1 and at most [maxFrames], each at its segment's
/// midpoint so a long clip shows what is inside it, not just
/// its first frame.
List<double> nsStripFrameTimes(double durationSec, {int maxFrames = 6}) {
  if (durationSec <= 0) return const [0.5];
  final n = (durationSec / 4).ceil().clamp(1, maxFrames);
  if (n == 1) return [durationSec / 2];
  return [for (var i = 0; i < n; i++) durationSec * (i + 0.5) / n];
}

/// B3 drag-trim math (v1.15.0 G5, pure — the regression tests
/// pin it): dragging clip edge by [dSec] seconds (file seconds
/// == timeline seconds inside the used range). Clamps: the
/// start never goes below 0 or past (end − 0.3); the end never
/// passes the file duration or (start + 0.3); an end dragged to
/// the file's end becomes the full range again (endSec null),
/// exactly like the Media panel's End slider.
ClipTrim nsDragTrimmed(
    ClipTrim trim, double fileDur, bool leftEdge, double dSec) {
  if (leftEdge) {
    final end = trim.endSec ?? fileDur;
    var newStart = trim.startSec + dSec;
    if (newStart < 0) newStart = 0;
    if (newStart > end - 0.3) newStart = end - 0.3;
    return trim.copyWith(startSec: newStart);
  }
  final cur = trim.endSec ?? fileDur;
  var newEnd = cur + dSec;
  if (newEnd > fileDur) newEnd = fileDur;
  if (newEnd < trim.startSec + 0.3) newEnd = trim.startSec + 0.3;
  return newEnd >= fileDur
      ? trim.copyWith(clearEnd: true)
      : trim.copyWith(endSec: newEnd);
}

class NewsMakerScreen extends StatefulWidget {
  /// Test/deep-link seams: when given, the screen edits that preset /
  /// project directly instead of loading from the stores first.
  /// Production passes neither.
  const NewsMakerScreen({super.key, this.initialPreset, this.initialProject});

  final ChannelPreset? initialPreset;
  final NewsProject? initialProject;

  @override
  State<NewsMakerScreen> createState() => _NewsMakerScreenState();
}

class _NewsMakerScreenState extends State<NewsMakerScreen> {
  ChannelPreset? _preset;
  NewsProject? _project;
  bool _loaded = false;
  bool _fontReady = false;

  final _tehreerController = TextEditingController();
  final _tickerController = TextEditingController();

  /// v1.5.2 (fix #65): the English ticker's controller — the
  /// Ticker panel's second text box.
  final _englishTickerController = TextEditingController();

  /// v1.5.1 (#49/#50): controllers for the Ticker panel's side
  /// label and the Reporter panel's name field.
  final _tickerLabelController = TextEditingController();
  final _reporterNameController = TextEditingController();

  /// Build 5 (v1.5.7): the retired Template & Studio screen's
  /// preset-level fields, absorbed into the Template panel (lower
  /// third / category / interview plate) and the Ribbons panel
  /// (the three preset ribbon texts) — their controllers, synced
  /// from the working preset by [_syncStudioControllers].
  final _ltTitleController = TextEditingController();
  final _ltSubtitleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _interviewNameController = TextEditingController();
  final _interviewDesigController = TextEditingController();
  final _presetTopTextController = TextEditingController();
  final _presetUrduTextController = TextEditingController();
  final _presetEnglishTextController = TextEditingController();

  /// Build 5: every channel preset (the Template panel's preset
  /// selector — switching persists the selection, exactly like
  /// the retired screen's store calls did).
  List<ChannelPreset> _allPresets = const [];

  /// Build 5: Kasheeda font section state (Template panel) — the
  /// status line + whether a manual Download may be offered. The
  /// Maker's [_fontReady] above stays the render flag.
  bool _fontUrlAvailable = false;
  String _fontStatus = 'Checking…';

  /// Build 5: template frame (poster) export in flight (Export
  /// panel — the retired screen's bottom button, renamed to what
  /// it is and moved to the one export door).
  bool _frameExporting = false;

  /// v1.5.1 (News Studio step, NS2): the open tool of the tool
  /// line (null = the summary card shows).
  String? _activeTool;

  /// v1.13.0 (G4): safe-area guides over the big preview — the
  /// Video Editor's [StageGridPainter] (thirds + action/title
  /// safe rects), toggled from the preview's corner, default OFF
  /// exactly like the Video Editor's grid. Preview-only state:
  /// it lives on this State, never on the project/preset, so it
  /// cannot reach the export by construction.
  bool _nsShowGuides = false;

  /// v1.5.1 (#52): Library listings (cache-first; refreshed by
  /// _initFontsAndLibrary on entry).
  List<LibraryItem> _textStyles = const [];
  List<LibraryItem> _transitions = const [];
  List<LibraryItem> _effects = const [];

  /// v1.5.1 (#50): Reporter panel state — BG work in flight, its
  /// status line, and the BG Replace colour row's visibility.
  bool _reporterBusy = false;
  String _reporterStatus = '';
  bool _reporterShowBgChoices = false;

  GeminiVoice _voice = GeminiVoice.aoede;

  /// v1.5.0 (#19): the ONE unified voice selection — a StudioVoice
  /// id from the shared 8-voice catalogue. Gemini picks also keep
  /// [_voice] in sync (the Gemini path + project.voice use it);
  /// Edge picks (Asad/Uzma) live only here + project.studioVoiceId.
  String _studioVoiceId = 'aoede';

  StudioVoice get _selectedStudioVoice => StudioVoice.byId(_studioVoiceId);

  bool _voiceBusy = false;
  String _voiceStatus = 'No voice has been created yet.';
  int? _voiceRemaining;

  // v1.4.0 audio trio (requirements #6): Record / Import /
  // Text se Audio — all three land in the SAME project voiceover
  // slot (project.voiceoverPath) the Gemini flow already uses.
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;

  /// Build 12 (point #9a): the user's OWNED Online Store audio
  /// items (Music category — sound effects + background music),
  /// shown in the Audio panel. Loaded on entry and reloaded
  /// whenever the store's ownership revision moves (a purchase
  /// in the Store screen lands here without a restart).
  List<StoreOwnedItem> _storeAudioItems = const [];
  bool _storeAudioLoading = false;

  /// Build 12 (point #13): logo-video background detection /
  /// keying in flight + its honest status line for the Logo
  /// panel.
  bool _logoVideoBusy = false;

  /// Build 13 (point #16): the "Asal timings" (Whisper word
  /// alignment) run state for the Captions panel.
  bool _alignBusy = false;

  /// Build 13 (point 6): Logo Parts + Permanent Logo run state.
  bool _partsBusy = false;
  bool _permBusy = false;

  /// Logo Parts redesign Build 1: the parts tool's own dock
  /// tab (logo / hisay / ghumao / waqt / glow / save — har
  /// button apni build ke sath aya), the selected part,
  /// box-draw mode and the big preview's play state.
  String _partsTab = 'hisay';
  String? _selectedPartId;
  String? _isolatePartId;
  bool _partsDrawMode = false;
  bool _partsPlaying = true;

  /// Redesign Build 2 (Option 35): the big preview's
  /// background — 'black' (kala, the Build 1 look), 'green'
  /// (the export green screen) or 'checker'. PREVIEW-ONLY:
  /// it never touches the export, it just lets the user see
  /// the logo the way it will sit on a video.
  String _partsPreviewBg = 'black';

  /// Redesign Build 3 (Option 40): the part whose animation
  /// settings were copied in the Ghumao tab, waiting to be
  /// pasted onto another part. Session-only UI state.
  String? _copiedPartAnimId;

  /// Build 13 (point #19): the timeline transport — the media
  /// preview's OWN video controller (reported through
  /// TemplateMediaPreview.onPlayerController), the last heard
  /// position, and the selected timeline tab. No second player
  /// exists: the transport drives the preview's player.
  VideoPlayerController? _transportController;
  Duration _transportPosition = Duration.zero;
  bool _transportPlaying = false;
  String _timelineTab = 'clips';

  /// Tools-fix wave (P1-3): the clip the Clips lane / Media
  /// panel's Trim & Split controls act on. Kept clamped to the
  /// clip list wherever it is read.
  int _selectedClipIndex = 0;
  String _clipEditStatus = '';

  /// v1.14.0 T4 (B1/B2/B5): the Maker timeline is now a REAL
  /// time-scale — clips sit at cumulative-second positions under
  /// a ruler, the playhead can be dragged (scrub), and the lane
  /// area scrolls when zoomed. [_nsPps] null = fit-to-width (the
  /// old everything-visible default, so nothing changes until
  /// the user zooms). [_scrubSec] is the dragged playhead
  /// position while the transport is not playing (the transport
  /// still only plays the FIRST clip — see [_scrubTo]).
  /// UI-only state: the project JSON is untouched, so old
  /// projects cannot break.
  double? _nsPps;
  double _nsScrollX = 0;
  double? _scrubSec;
  double _nsViewportW = 0;
  double _nsLayoutTotal = 0;

  /// v1.15.0 G5 (B10): lanes the user has hidden from the
  /// timeline (view-only — the project and the export are
  /// untouched). Ids: 'v1', 'a1', 'a2', 'tc'.
  final Set<String> _nsLaneHidden = {};

  /// v1.15.0 G5 (B4): the clip being drag-reordered (long-press),
  /// and the drag's reference geometry: the global X where the
  /// current reference was taken + the dragged clip's start
  /// second at that moment. Both reset at every live swap, so
  /// the math never depends on a stale build.
  int? _nsDragIndex;
  double _nsDragRefGlobalX = 0;
  double _nsDragRefStartSec = 0;

  /// Tools-fix wave (P2): debounce for the bare-rebuild text
  /// fields (Tehreer / tickers / voice script) — typing used to
  /// rebuild the WHOLE Maker screen on every keystroke just so
  /// the preview + counters refreshed; now the rebuild happens
  /// once, 250 ms after the last keystroke.
  Timer? _textDebounce;

  void _textFieldChanged() {
    _scheduleSave();
    _textDebounce?.cancel();
    _textDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() {});
    });
  }

  /// The ONE height of the lower zone under the preview (P0-4):
  /// the panel host and the timeline state share it, so the
  /// preview's size can never depend on which state is showing.
  double get _lowerZoneHeight =>
      MediaQuery.of(context).size.height < 700 ? 212 : 272;

  void _onTransportController(VideoPlayerController? controller) {
    if (identical(controller, _transportController)) return;
    _transportController?.removeListener(_onTransportTick);
    _transportController = controller;
    _transportPosition = Duration.zero;
    _transportPlaying = false;
    controller?.addListener(_onTransportTick);
  }

  void _onTransportTick() {
    final controller = _transportController;
    if (controller == null || !mounted) return;
    final value = controller.value;
    final pos = value.position;
    if (pos.inMilliseconds ~/ 250 != _transportPosition.inMilliseconds ~/ 250 ||
        value.isPlaying != _transportPlaying) {
      setState(() {
        _transportPosition = pos;
        _transportPlaying = value.isPlaying;
        if (value.isPlaying) {
          // Playing takes the playhead back from any scrub and
          // keeps it visible in a zoomed timeline (T4).
          _scrubSec = null;
          _nsFollowPlayhead();
        }
      });
    }
  }

  /// T4: while playing, jump the lane scroll just enough to
  /// keep the playhead inside the visible window. Fit mode
  /// (pps null) never scrolls.
  void _nsFollowPlayhead() {
    final pps = _nsPps;
    if (pps == null || _nsViewportW <= 0 || _nsLayoutTotal <= 0) return;
    final px = _transportPosition.inMilliseconds / 1000.0 * pps;
    var maxScroll = _nsLayoutTotal * pps - _nsViewportW;
    if (maxScroll < 0) maxScroll = 0;
    if (px < _nsScrollX) {
      _nsScrollX = px.clamp(0.0, maxScroll);
    } else if (px > _nsScrollX + _nsViewportW - 24) {
      _nsScrollX = (px - 24).clamp(0.0, maxScroll);
    }
  }

  /// The position the timeline SHOWS: a scrubbed playhead wins
  /// while paused; the transport position wins while playing.
  double get _effectivePosSec =>
      _scrubSec ?? _transportPosition.inMilliseconds / 1000.0;

  /// v1.14.0 T4 (B2): drag the playhead to [globalSec] on the
  /// reel timeline. Scrubbing pauses playback. The transport
  /// only plays the FIRST clip, so a target inside clip 1's used
  /// range also seeks the player to the matching file position;
  /// beyond clip 1 the playhead/readout move and the preview
  /// keeps showing clip 1 — an honest limit (the guide says so).
  Future<void> _scrubTo(NewsProject project, double globalSec) async {
    final total = _nsLayoutTotal;
    final target =
        total > 0 ? globalSec.clamp(0.0, total) : (globalSec < 0 ? 0.0 : globalSec);
    setState(() => _scrubSec = target);
    final controller = _transportController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (controller.value.isPlaying) await controller.pause();
      if (project.clipPaths.isNotEmpty) {
        final eff0 = _entryDurationSec(project, 0);
        if (eff0 != null && target < eff0) {
          final trim = project.trimAt(0);
          await controller.seekTo(Duration(
              milliseconds: ((trim.startSec + target) * 1000).round()));
        }
      }
    } catch (_) {
      // A broken clip must never break the workspace.
    }
  }

  /// T4 (B1): header zoom — ×/÷ around the current scale; fit
  /// returns to the everything-visible default.
  void _nsZoomBy(double factor) {
    final fit = _nsLayoutTotal > 0 && _nsViewportW > 0
        ? _nsViewportW / _nsLayoutTotal
        : 42.0;
    final cur = _nsPps ?? fit;
    setState(() => _nsPps = (cur * factor).clamp(4.0, 400.0));
  }

  void _nsZoomFit() {
    setState(() {
      _nsPps = null;
      _nsScrollX = 0;
    });
  }

  Future<void> _transportToggle() async {
    final controller = _transportController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        if (controller.value.position >= controller.value.duration &&
            controller.value.duration > Duration.zero) {
          await controller.seekTo(Duration.zero);
        }
        await controller.play();
      }
    } catch (_) {
      // A broken clip must never break the workspace.
    }
  }

  Future<void> _transportStop() async {
    final controller = _transportController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.pause();
      await controller.seekTo(Duration.zero);
    } catch (_) {}
  }
  String _logoVideoStatus = '';

  String _saveStatus = '';
  Timer? _saveTimer;

  /// Build 4 (News Studio workspace): project-bar undo/redo —
  /// JSON snapshots of persisted states (see [_saveNow]).
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  String? _lastSnap;
  bool _restoringHistory = false;

  /// Build 4: probed clip durations + first-frame thumbnails for
  /// the timeline zone (a visual map only — failures are silent).
  final Map<String, double> _clipDurations = {};
  final Map<String, String> _clipThumbs = {};

  /// v1.16.0 G5 (B7): per-clip filmstrips (several frames across
  /// the clip, [nsStripFrameTimes]) + lane waveform PNGs for the
  /// A1 voice / A2 music lanes (showwavespic, cached per file).
  /// Decoration only, like the thumbnails — failures are silent.
  final Map<String, List<String>> _clipStrips = {};
  final Map<String, String> _nsWaveCache = {};
  final Set<String> _nsWavePending = {};

  /// v1.5.0 (#33): the element selected in the Elements panel /
  /// by tapping the preview (a [NewsElement] id).
  String _selectedElement = NewsElement.media;

  /// Drag-session state for the preview gesture layer.
  Offset? _panStart;
  ElementOverride? _panInitOverride;
  bool _panResizing = false;

  @override
  void initState() {
    super.initState();
    // Build 13 (point 6): the Permanent Logo entitlement state
    // (fail-soft; the Logo panel reads it).
    unawaited(PermanentLogoService.instance.init());
    final preset = widget.initialPreset;
    final project = widget.initialProject;
    if (preset != null || project != null) {
      _preset = preset ?? ChannelPreset.nigraanTv();
      _project = project ?? NewsProject.create(presetId: _preset!.id);
      _voice = _project!.voice;
      _studioVoiceId = _project!.studioVoiceId.isNotEmpty
          ? _project!.studioVoiceId
          : _project!.voice.name;
      _tehreerController.text = _project!.tehreer;
      _tickerController.text = _project!.tickerText;
      _englishTickerController.text = _project!.englishTickerText;
      _tickerLabelController.text = _project!.tickerLabel;
      _reporterNameController.text = _project!.reporterName;
      _allPresets = [_preset!];
      _syncStudioControllers();
      _loaded = true;
      _lastSnap = jsonEncode(_project!.toJson());
      unawaited(_probeClips());
      _refreshVoiceStatus();
      _checkFont();
      _initFontsAndLibrary();
      unawaited(_loadStoreAudio());
    } else {
      _load();
    }
    StoreService.instance.revision.addListener(_onStoreRevision);
  }

  /// Build 12 (point #9a): (re)loads the owned store audio for
  /// the Audio panel. Fail-soft: any store failure just leaves
  /// the previous list (or the empty state with its Store
  /// button).
  Future<void> _loadStoreAudio() async {
    if (_storeAudioLoading) return;
    _storeAudioLoading = true;
    try {
      // 'Music' is the StoreConfig category (the Drive
      // subfolder name) holding sound effects + background
      // music.
      final owned = await StoreService.instance.ownedItems('Music');
      final audio = owned
          .where(
            (o) => storeItemIsAudio(
              StoreItem(id: o.id, name: o.name, category: o.category),
            ),
          )
          .toList();
      if (!mounted) return;
      setState(() => _storeAudioItems = audio);
    } catch (_) {
      // Store unavailable — the panel keeps its honest empty
      // state; nothing here may break the Maker.
    } finally {
      _storeAudioLoading = false;
    }
  }

  void _onStoreRevision() {
    unawaited(_loadStoreAudio());
  }

  Future<void> _load() async {
    // Build 5 (v1.5.7, error-banner fix): fail-soft — a store or
    // quota failure here used to escape as an unhandled async
    // error (one of the CrashGuard banner sources on the user's
    // phone). Any failure lands on the factory preset + a fresh
    // project instead of an endless spinner or a banner.
    try {
      final presets = await ChannelPresetStore.loadAll();
      final selectedId = await ChannelPresetStore.loadSelectedId();
      final preset = selectedId == null
          ? presets.first
          : presets.firstWhere(
              (p) => p.id == selectedId,
              orElse: () => presets.first,
            );
      final project = await NewsProjectStore.loadLatest() ??
          NewsProject.create(presetId: preset.id);
      if (!mounted) return;
      _restorePartsState(preset);
      setState(() {
        _preset = preset;
        _allPresets = presets;
        _project = project;
        _voice = project.voice;
        _studioVoiceId = project.studioVoiceId.isNotEmpty
            ? project.studioVoiceId
            : project.voice.name;
        _tehreerController.text = project.tehreer;
        _tickerController.text = project.tickerText;
        _englishTickerController.text = project.englishTickerText;
        _tickerLabelController.text = project.tickerLabel;
        _reporterNameController.text = project.reporterName;
        _syncStudioControllers();
        _loaded = true;
      });
      _lastSnap = jsonEncode(_project!.toJson());
      unawaited(_probeClips());
      await _refreshVoiceStatus();
      await _checkFont();
      await _initFontsAndLibrary();
      unawaited(_loadStoreAudio());
    } catch (e, s) {
      // Build 7: recorded with its boundary tag (no banner) —
      // the fallback below still applies exactly as before.
      CrashGuard.captureHandled(e, s, source: 'maker.load');
      if (!mounted || _loaded) return;
      final preset = ChannelPreset.nigraanTv();
      final project = NewsProject.create(presetId: preset.id);
      setState(() {
        _preset = preset;
        _allPresets = [preset];
        _project = project;
        _voice = project.voice;
        _studioVoiceId = project.voice.name;
        _syncStudioControllers();
        _loaded = true;
      });
      _lastSnap = jsonEncode(project.toJson());
    }
  }

  Future<void> _refreshVoiceStatus() async {
    // Build 5 (v1.5.7, error-banner fix): fail-soft — the quota
    // read touches storage/platform channels and is called from
    // initState and every undo/redo restore; a failure must never
    // escape as an unhandled async error. The Voice panel simply
    // shows no remaining-count line when the read failed.
    try {
      final remaining = await GeminiVoiceService().remainingToday();
      if (!mounted) return;
      setState(() => _voiceRemaining = remaining);
    } catch (e, s) {
      // Quota display is decoration — never an error path.
      // Build 7: recorded with its boundary tag (no banner).
      CrashGuard.captureHandled(e, s, source: 'maker.voice');
    }
  }

  Future<void> _checkFont() async {
    // Build 5 (v1.5.7): the retired Template & Studio screen's
    // Kasheeda logic, absorbed whole — cached file → load it;
    // no cache but an effective download URL → download + load
    // it here; no URL → the honest fallback status. Fail-soft
    // throughout (the old Maker version silently did only the
    // cached branch; the status line + Download button in the
    // Template panel read [_fontStatus] / [_fontUrlAvailable]).
    try {
      final cached = await const AssetDownloadService()
          .cachedFile(AssetDownloadService.kasheedaFileName);
      if (cached != null) {
        await AssetDownloadService.loadKasheedaFontFromFile(cached);
        if (!mounted) return;
        setState(() {
          _fontReady = true;
          _fontStatus = 'Urdu font (Kasheeda): ready';
        });
        return;
      }
      final url = await _effectiveKasheedaFontUrl();
      if (!mounted) return;
      if (url.isEmpty) {
        setState(() {
          _fontUrlAvailable = false;
          _fontStatus = 'Urdu font (Kasheeda): not available right now '
              '— a fallback font is being used';
        });
        return;
      }
      setState(() {
        _fontUrlAvailable = true;
        _fontStatus = 'Urdu font (Kasheeda): downloading…';
      });
      try {
        await const AssetDownloadService().loadKasheedaFont(url: url);
        if (!mounted) return;
        setState(() {
          _fontReady = true;
          _fontStatus = 'Urdu font (Kasheeda): ready';
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _fontStatus = 'Urdu font (Kasheeda): download fail — '
              'the fallback font is in use';
        });
      }
    } catch (e, s) {
      // Font state is fail-soft — the preview uses the fallback.
      // Build 7: recorded with its boundary tag (no banner).
      CrashGuard.captureHandled(e, s, source: 'maker.fonts');
    }
  }

  /// The EFFECTIVE Kasheeda download URL (ported from the retired
  /// Template & Studio screen): the remote-config value when
  /// non-empty, else the compile-time [AppConfig] fallback (empty
  /// by design — the real URL is hosted). Fail-soft.
  Future<String> _effectiveKasheedaFontUrl() async {
    try {
      await RemoteConfigService.instance.init();
    } catch (_) {
      // Fail-soft: keep whatever config is already resolved.
    }
    final remoteUrl =
        RemoteConfigService.instance.config.kasheedaFontUrl.trim();
    if (remoteUrl.isNotEmpty) return remoteUrl;
    return AppConfig.kasheedaFontUrl.trim();
  }

  /// Manual Kasheeda download/retry (the Template panel's
  /// Download button — the retired screen's control, same logic).
  Future<void> _downloadKasheedaFont() async {
    final url = await _effectiveKasheedaFontUrl();
    if (!mounted) return;
    if (url.isEmpty) {
      setState(() {
        _fontUrlAvailable = false;
        _fontStatus = 'Urdu font (Kasheeda): not available right now '
            '— a fallback font is being used';
      });
      return;
    }
    setState(() {
      _fontUrlAvailable = true;
      _fontStatus = 'Urdu font (Kasheeda): downloading…';
    });
    try {
      await const AssetDownloadService().loadKasheedaFont(url: url);
      if (!mounted) return;
      setState(() {
        _fontReady = true;
        _fontStatus = 'Urdu font (Kasheeda): ready';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _fontStatus = 'Urdu font download fail: $e');
    }
  }

  @override
  void dispose() {
    StoreService.instance.revision.removeListener(_onStoreRevision);
    _transportController?.removeListener(_onTransportTick);
    _saveTimer?.cancel();
    _textDebounce?.cancel();
    unawaited(_recorder.dispose());
    _tehreerController.dispose();
    _tickerController.dispose();
    _englishTickerController.dispose();
    _tickerLabelController.dispose();
    _reporterNameController.dispose();
    _ltTitleController.dispose();
    _ltSubtitleController.dispose();
    _categoryController.dispose();
    _interviewNameController.dispose();
    _interviewDesigController.dispose();
    _presetTopTextController.dispose();
    _presetUrduTextController.dispose();
    _presetEnglishTextController.dispose();
    super.dispose();
  }

  /// Build 5 (v1.5.7): writes the working preset's Template &
  /// Studio fields into their controllers (the panels edit the
  /// preset through these). Called on every preset (re)load and
  /// switch — the panels never read a stale copy.
  void _syncStudioControllers() {
    final preset = _preset;
    if (preset == null) return;
    _ltTitleController.text = preset.lowerThirdTitle;
    _ltSubtitleController.text = preset.lowerThirdSubtitle;
    _categoryController.text = preset.categoryLabel;
    _interviewNameController.text = preset.interviewName;
    _interviewDesigController.text = preset.interviewDesignation;
    _presetTopTextController.text = preset.topRibbon.text;
    _presetUrduTextController.text = preset.urduRibbon.text;
    _presetEnglishTextController.text = preset.englishRibbon.text;
  }

  /// v1.4.0 audio trio: the ONE place every audio source lands —
  /// sets the project's voiceover slot, re-syncs the karaoke
  /// subtitles against the real duration when the tehreer exists,
  /// updates the status line and autosaves.
  Future<void> _setProjectVoiceover(
    String path,
    double? durationSec,
    String sourceLabel,
  ) async {
    final project = _project;
    if (project == null) return;
    var syncNote = '';
    final text = _tehreerController.text.trim();
    if (durationSec != null && durationSec > 0 && text.isNotEmpty) {
      project.subtitles = syncSubtitlesToVoiceover(text, durationSec);
      // Build 13: estimator timings — the timing source is
      // stamped honestly (a later "Asal timings" run can upgrade
      // them to real Whisper timings).
      project.captionTimingSource = 'estimate';
      project.captionAlignedHash = '';
      syncNote = ' Subtitles synced with the voiceover.';
    }
    setState(() {
      project.voiceoverPath = path;
      project.voiceoverDurationSec = durationSec;
      _voiceStatus = '$sourceLabel is ready.$syncNote';
    });
    _scheduleSave();
  }

  /// Trio option 1 — Record: mic recording (record package) saved
  /// as WAV in the app's documents folder; stopping the recording
  /// attaches it as the project voiceover. The existing
  /// VoicePreviewPlayer below previews it.
  Future<void> _toggleRecord() async {
    final project = _project;
    if (project == null || _voiceBusy) return;
    if (_recording) {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() => _recording = false);
      if (path == null) {
        _showMessage('The recording could not be saved.');
        return;
      }
      final bytes = await File(path).readAsBytes();
      final dur = audioDurationSeconds(bytes, 'wav');
      await _setProjectVoiceover(
        path,
        dur > 0 ? dur : null,
        'Your recording',
      );
      return;
    }
    if (!await _recorder.hasPermission()) {
      _showMessage('Mic permission is needed for recording.');
      return;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'news_audio'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = p.join(
      dir.path,
      'voice_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav),
      path: path,
    );
    if (!mounted) return;
    setState(() {
      _recording = true;
      _voiceStatus = 'Recording… tap Stop when done.';
    });
  }

  /// Trio option 2 — Import: pick an audio file from the phone;
  /// it is copied into the app's documents folder (picker cache
  /// paths can be cleaned by the OS) and set as the voiceover.
  Future<void> _importAudio() async {
    final project = _project;
    if (project == null || _voiceBusy) return;
    final files = await FilePicker.pickFiles(type: FileType.audio);
    if (files.isEmpty || files.first.path == null) return;
    final src = File(files.first.path!);
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'news_audio'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final ext = p.extension(src.path).replaceAll('.', '').toLowerCase();
      final dest = p.join(
        dir.path,
        'import_${DateTime.now().millisecondsSinceEpoch}'
        '${ext.isEmpty ? '' : '.$ext'}',
      );
      await src.copy(dest);
      final bytes = await File(dest).readAsBytes();
      final dur = audioDurationSeconds(bytes, ext.isEmpty ? 'wav' : ext);
      await _setProjectVoiceover(
        dest,
        dur > 0 ? dur : null,
        'Imported audio (${p.basename(src.path)})',
      );
    } catch (e) {
      _showMessage('Audio could not be imported: $e');
    }
  }

  /// Trio option 3 (free-TTS half) — Text se Audio via the free
  /// Edge voices in [TtsStudioService]. v1.5.0 (#19): uses the
  /// SELECTED Edge voice (Asad or Uzma) directly — the old
  /// gender-match against the Gemini selection is gone, because
  /// the 8 chips below are the one selection now. COSTS COINS like
  /// the Gemini path ([CoinFeature.voiceover], charged when the
  /// result is not a cache hit); a failed spend attaches nothing.
  Future<void> _buildFreeTtsVoice() async {
    final project = _project;
    if (project == null || _voiceBusy) return;
    final text = _tehreerController.text.trim();
    if (text.isEmpty) {
      _showMessage('Write the script first.');
      return;
    }
    setState(() {
      _voiceBusy = true;
      _voiceStatus = 'Creating the voice with Free TTS…';
    });
    try {
      final result = await TtsStudioService().generate(
        text,
        voice: _selectedStudioVoice,
        controls: TtsControls(
          speed: project.voiceSpeed,
          pauseSeconds: project.voicePauseSec,
        ),
        music: project.voiceMusic,
      );
      if (!result.cached) {
        // Point #20: remote-priced via PricingService
        // (price_ns_voiceover, fallback 50) — coins / free /
        // Pro-only / ad-unlock per tj-pro.json, no new build.
        final spendResult = await PricingService.charge(
          PricingService.keyNsVoiceover,
          reason: CoinCosts.reasonFor(CoinFeature.voiceover),
          fallbackCoins: CoinCosts.voiceover,
        );
        if (!spendResult.ok) {
          if (!mounted) return;
          final String failLine =
              spendResult.error == PricingService.errorProRequired
                  ? 'Voiceover is for Pro users only.'
                  : spendResult.error ==
                          PricingService.errorAdNotCompleted
                      ? 'The ad did not complete — the voiceover was not created.'
                      : 'For the voiceover, '
                          '${PricingService.coinsOr(PricingService.keyNsVoiceover, CoinCosts.voiceover)} '
                          'coins are needed — balance is low. '
                          'Watch Ads se coins kamayein.';
          setState(() {
            _voiceBusy = false;
            _voiceStatus = failLine;
          });
          _showMessage(failLine);
          return;
        }
      }
      final path = result.filePath;
      if (path == null) {
        throw Exception('The audio file could not be saved.');
      }
      if (!mounted) return;
      setState(() => _voiceBusy = false);
      await _setProjectVoiceover(
        path,
        result.durationSec > 0 ? result.durationSec : null,
        result.cached ? 'Free TTS voice (cached — 0 coins)' : 'Free TTS voice',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _voiceBusy = false;
        _voiceStatus = 'Free TTS voice was not created: $e';
      });
    }
  }

  /// Trio option 3 — Text se Audio, UNIFIED (v1.5.0: the old
  /// Gemini-vs-Free chooser dialog AND the separate "Voice banao"
  /// button were two controls for this one action — both removed).
  /// The 8 voice chips below ARE the engine choice: a Gemini chip
  /// builds via the Gemini path, an Edge chip (Asad/Uzma) via the
  /// free-TTS path. Both cost coins for a new voice; both land in
  /// the same voiceover slot.
  Future<void> _buildSelectedVoice() async {
    if (_selectedStudioVoice.engine == StudioTtsEngine.edge) {
      await _buildFreeTtsVoice();
    } else {
      await _buildVoice();
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Syncs the controllers into the working project and persists it
  /// (debounced so typing does not write JSON on every keystroke).
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveNow);
  }

  Future<void> _saveNow() async {
    final project = _project;
    if (project == null) return;
    // Build 6 (v1.5.8, error-banner audit): autosave fires from a
    // bare Timer (500 ms after every edit) and via unawaited()
    // menu calls, so a store failure here escaped as an unhandled
    // async error — a banner while simply editing. Fail-soft: a
    // failed autosave just leaves the previous "Saved" stamp; the
    // next edit retries.
    try {
      _syncTextControllers(project);
      // Build 4 (News Studio workspace): the persisted state becomes
      // an undo step (the state it replaced) for the project bar's
      // undo/redo. Restores also save through here, flagged off.
      final snap = jsonEncode(project.toJson());
      if (!_restoringHistory && _lastSnap != null && snap != _lastSnap) {
        _undoStack.add(_lastSnap!);
        if (_undoStack.length > 50) _undoStack.removeAt(0);
        _redoStack.clear();
      }
      _lastSnap = snap;
      await NewsProjectStore.save(project);
      if (!mounted) return;
      final now = DateTime.now();
      setState(
        () => _saveStatus =
            'Saved • ${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}',
      );
    } catch (e, s) {
      // Autosave is background bookkeeping — never an error path.
      // Build 7: recorded with its boundary tag (no banner).
      CrashGuard.captureHandled(e, s, source: 'maker.autosave');
    }
  }

  /// v1.5.0 (#33): writes one element's override and autosaves.
  void _setElementOverride(String id, ElementOverride value) {
    final project = _project;
    if (project == null) return;
    setState(() {
      if (value.isIdentity) {
        project.elementOverrides.remove(id);
      } else {
        project.elementOverrides[id] = value;
      }
    });
    _scheduleSave();
  }

  ElementOverride _elementOv(NewsProject project, String id) =>
      overrideFor(project.elementOverrides, id);

  /// v1.5.0 (#33): wraps the Final preview with the element
  /// gesture layer — tap selects an element (hit-tested against
  /// the override-adjusted rects), drag moves it, dragging its
  /// bottom-right corner handle resizes it. Other template kinds
  /// keep the plain preview (their adjustments live in the
  /// Elements panel below; the Final template is the one whose
  /// preview + export both honour overrides).
  Widget _withElementGestures(
    NewsProject project,
    ChannelPreset preset,
    Widget child, {
    required double height,
  }) {
    if (project.templateKind != 'nigraanFinal') return child;
    final ph = height;
    final pw = ph * 9 / 16;
    final rects = finalElementRects(
      preset: preset,
      overrides: project.elementOverrides,
      w: pw,
      h: ph,
    );
    final selRect = rects[_selectedElement];
    final selOv = _elementOv(project, _selectedElement);
    return SizedBox(
      width: pw,
      height: ph,
      child: Stack(
        children: [
          child,
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) =>
                  _elementTap(project, rects, d.localPosition),
              onPanStart: (d) =>
                  _elementPanStart(project, rects, d.localPosition),
              onPanUpdate: (d) =>
                  _elementPanUpdate(project, pw, ph, d.localPosition),
              onPanEnd: (_) {
                _panStart = null;
                _panInitOverride = null;
              },
            ),
          ),
          if (selRect != null && !selOv.hidden)
            Positioned.fromRect(
              rect: selRect,
              child: IgnorePointer(
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: const Color(0xFFF5C542),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 18,
                        height: 18,
                        color: const Color(0xFFF5C542),
                        child: const Icon(
                          Icons.open_in_full,
                          size: 11,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Hit-test priority: small elements first, texts before their
  /// band, the media (background) last.
  static const _hitPriority = [
    NewsElement.capsule,
    NewsElement.logo,
    NewsElement.reporter,
    NewsElement.headlineText,
    NewsElement.tickerText,
    NewsElement.topRibbon,
    NewsElement.middleRibbon,
    NewsElement.bottomRibbon,
    NewsElement.overlay,
    NewsElement.media,
  ];

  String? _hitElement(Map<String, Rect> rects, Offset pos) {
    for (final id in _hitPriority) {
      final r = rects[id];
      if (r != null && r.contains(pos)) return id;
    }
    return null;
  }

  void _elementTap(
    NewsProject project,
    Map<String, Rect> rects,
    Offset pos,
  ) {
    final hit = _hitElement(rects, pos);
    if (hit != null) {
      setState(() {
        _selectedElement = hit;
        // v1.5.1: tapping the logo / reporter in the preview
        // opens their own tool panels (NS6/NS7 behaviour).
        if (hit == NewsElement.logo) _activeTool = 'logo';
        if (hit == NewsElement.reporter) _activeTool = 'reporter';
      });
    }
  }

  void _elementPanStart(
    NewsProject project,
    Map<String, Rect> rects,
    Offset pos,
  ) {
    var sel = _selectedElement;
    final selRect = rects[sel];
    if (selRect == null || !selRect.contains(pos)) {
      final hit = _hitElement(rects, pos);
      if (hit == null) {
        _panStart = null;
        return;
      }
      sel = hit;
      setState(() => _selectedElement = hit);
    }
    _panStart = pos;
    _panInitOverride = _elementOv(project, sel);
    final r = rects[sel];
    _panResizing = r != null &&
        (r.bottomRight - pos).distance < 30 &&
        !_panInitOverride!.hidden;
  }

  void _elementPanUpdate(
    NewsProject project,
    double pw,
    double ph,
    Offset pos,
  ) {
    final start = _panStart;
    final init = _panInitOverride;
    if (start == null || init == null) return;
    final dxPx = pos.dx - start.dx;
    final dyPx = pos.dy - start.dy;
    if (_panResizing) {
      final scale = (init.scale * (1 + (dxPx + dyPx) / 260))
          .clamp(0.4, 2.5);
      _setElementOverride(
        _selectedElement,
        init.copyWith(scale: scale.toDouble()),
      );
    } else {
      _setElementOverride(
        _selectedElement,
        init.copyWith(
          dx: (init.dx + dxPx / pw).clamp(-0.5, 0.5).toDouble(),
          dy: (init.dy + dyPx / ph).clamp(-0.5, 0.5).toDouble(),
        ),
      );
    }
  }

  /// v1.5.0 (#33): the Elements panel — element chips, the
  /// selected element's move/size sliders (the panel half of the
  /// corner-handle resize), hide/show (= remove), reset, and
  /// (v1.5.1) the preset watermark toggle.
  Widget _elementsPanel(NewsProject project) {
    final sel = _selectedElement;
    final ov = _elementOv(project, sel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // v1.5.1: the panel shell carries the 'Elements' title
        // now; this row keeps only the Reset-all action.
        if (project.elementOverrides.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                setState(() => project.elementOverrides.clear());
                _scheduleSave();
              },
              child: const Text('Reset all'),
            ),
          ),
        // v1.5.2 (fix #60): ONE horizontal rail of element chips.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final id in NewsElement.all) ...[
                ChoiceChip(
                  key: Key('elementChip-$id'),
                  label: Text(
                    overrideFor(project.elementOverrides, id).hidden
                        ? '${NewsElement.labels[id]} (hidden)'
                        : NewsElement.labels[id]!,
                  ),
                  selected: sel == id,
                  onSelected: (_) => setState(() => _selectedElement = id),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${NewsElement.labels[sel]} — position / size',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        _elementSlider(
          label: 'Left / Right',
          value: ov.dx,
          min: -0.3,
          max: 0.3,
          onChanged: (v) =>
              _setElementOverride(sel, ov.copyWith(dx: v)),
        ),
        _elementSlider(
          label: 'Up / Down',
          value: ov.dy,
          min: -0.3,
          max: 0.3,
          onChanged: (v) =>
              _setElementOverride(sel, ov.copyWith(dy: v)),
        ),
        _elementSlider(
          label: 'Size',
          value: ov.scale,
          min: 0.5,
          max: 2.0,
          onChanged: (v) =>
              _setElementOverride(sel, ov.copyWith(scale: v)),
        ),
        // v1.5.2 (#69 sweep): Expanded + FittedBox labels — the
        // two buttons side by side overflowed narrow screens
        // (caught by the panel overflow guard at 360px).
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('elementHideButton'),
                onPressed: () => _setElementOverride(
                  sel,
                  ov.copyWith(hidden: !ov.hidden),
                ),
                icon: Icon(
                  ov.hidden ? Icons.visibility : Icons.visibility_off,
                  size: 18,
                ),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(ov.hidden ? 'Show (restore)' : 'Remove (hide)'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: ov.isIdentity
                    ? null
                    : () =>
                        _setElementOverride(sel, ElementOverride.identity),
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Reset element'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // v1.5.1 (#45 dedupe): the old Add row is gone — Add
        // Video lives in the quick row + Media panel, Add Text
        // is the headline chip's Show action above. The
        // watermark toggle stays: it is the ONLY Maker control
        // for the preset watermark.
        OutlinedButton.icon(
          key: const Key('elementWatermarkButton'),
          onPressed: () async {
            final preset = _preset;
            if (preset == null) return;
            preset.watermarkEnabled = !preset.watermarkEnabled;
            await persistPresetChange(preset);
            if (preset.watermarkEnabled) {
              _setElementOverride(
                NewsElement.overlay,
                _elementOv(project, NewsElement.overlay)
                    .copyWith(hidden: false),
              );
            }
            if (!mounted) return;
            setState(() {});
          },
          icon: const Icon(Icons.branding_watermark, size: 18),
          label: Text(
            (_preset?.watermarkEnabled ?? false)
                ? 'Watermark ON (turn off)'
                : 'Watermark OFF (apply)',
          ),
        ),
      ],
    );
  }

  Widget _elementSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 84,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  /// Opens the Caption Studio for the working project and reloads
  /// the saved project on return (lines + style may have changed).
  Future<void> _openCaptions() async {
    final project = _project;
    if (project == null) return;
    await _saveNow();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CaptionStudioScreen(initialProject: project),
      ),
    );
    final reloaded = await NewsProjectStore.load(project.id);
    if (reloaded != null && mounted) {
      setState(() => _project = reloaded);
    }
  }

  /// Build 13 (point #16): the Captions panel's "Asal timings"
  /// action — word-split Whisper transcription of the voiceover
  /// + script alignment (caption_alignment.dart). On success the
  /// project carries REAL word timings and the source stamp; on
  /// any failure the estimator timings stay and the message says
  /// why. Runs on-device; can take a while on weak phones, hence
  /// the busy state on the button.
  Future<void> _runCaptionAlignment(NewsProject project) async {
    if (_alignBusy) return;
    setState(() => _alignBusy = true);
    try {
      final temp = await getTemporaryDirectory();
      final workDir = Directory(p.join(temp.path, 'caption_align'));
      if (!await workDir.exists()) {
        await workDir.create(recursive: true);
      }
      final outcome = await alignProjectCaptionsToVoiceover(
        project,
        workDir: workDir,
      );
      if (!mounted) return;
      if (outcome.applied) {
        setState(() {});
        _scheduleSave();
      }
      _showMessage(outcome.message);
    } catch (e) {
      if (mounted) {
        _showMessage('Real timings could not be applied: $e');
      }
    } finally {
      if (mounted) setState(() => _alignBusy = false);
    }
  }

  /// Real voiceover build through the Gemini proxy (see the file
  /// header + GeminiVoiceService: chunked, cache-first, 5/day cap).
  /// [regenerate] ("Regenerate") deletes the cached file first, so the
  /// next synthesize costs new proxy request(s).
  ///
  /// COINS (Phase 10): a NEW voiceover costs 50 coins
  /// ([CoinFeature.voiceover]) — spent BEFORE synthesizing. A cached
  /// voice (same tehreer + voice + controls) is free: the spend is
  /// skipped when [GeminiVoiceService.hasCachedVoice] is true, and a
  /// regenerate always spends (the cache is deleted first). Admins
  /// are waived server-side; insufficient balance aborts with a
  /// message and no voice is built.
  Future<void> _buildVoice({bool regenerate = false}) async {
    final project = _project;
    if (project == null || _voiceBusy) return;
    final text = _tehreerController.text.trim();
    if (text.isEmpty) {
      _showMessage('Write the script first.');
      return;
    }
    setState(() {
      _voiceBusy = true;
      _voiceStatus = 'Creating voice…';
    });
    try {
      final controls = TtsControls(
        speed: project.voiceSpeed,
        pauseSeconds: project.voicePauseSec,
      );
      final cached = regenerate
          ? false
          : await GeminiVoiceService().hasCachedVoice(
              text,
              voice: _voice,
              controls: controls,
              backgroundMusic: project.voiceMusic,
            );
      if (!cached) {
        // Point #20: remote-priced via PricingService
        // (price_ns_voiceover, fallback 50) — coins / free /
        // Pro-only / ad-unlock per tj-pro.json, no new build.
        final spendResult = await PricingService.charge(
          PricingService.keyNsVoiceover,
          reason: CoinCosts.reasonFor(CoinFeature.voiceover),
          fallbackCoins: CoinCosts.voiceover,
        );
        if (!spendResult.ok) {
          if (!mounted) return;
          final String failLine =
              spendResult.error == PricingService.errorProRequired
                  ? 'Voiceover is for Pro users only.'
                  : spendResult.error ==
                          PricingService.errorAdNotCompleted
                      ? 'The ad did not complete — the voiceover was not created.'
                      : 'For the voiceover, '
                          '${PricingService.coinsOr(PricingService.keyNsVoiceover, CoinCosts.voiceover)} '
                          'coins are needed — balance is low. '
                          'Watch Ads se coins kamayein.';
          setState(() {
            _voiceBusy = false;
            _voiceStatus = failLine;
          });
          _showMessage(failLine);
          return;
        }
      }
      if (regenerate && project.voiceoverPath != null) {
        try {
          await File(project.voiceoverPath!).delete();
        } catch (_) {}
        project.voiceoverPath = null;
        project.voiceoverDurationSec = null;
      }
      final result = await GeminiVoiceService().synthesize(
        text,
        voice: _voice,
        controls: controls,
        backgroundMusic: project.voiceMusic,
      );
      final duration = wavDurationSeconds(result.file);
      final remaining = await GeminiVoiceService().remainingToday();
      if (!mounted) return;
      // Karaoke sync (Phase 5): the real voiceover duration re-times
      // the subtitles — the Phase 4 word-count estimate is replaced.
      var syncNote = '';
      if (duration != null && duration > 0) {
        project.subtitles = syncSubtitlesToVoiceover(text, duration);
        project.captionTimingSource = 'estimate';
        project.captionAlignedHash = '';
        syncNote = ' Subtitles synced with the voiceover.';
      }
      setState(() {
        _voiceBusy = false;
        project.voiceoverPath = result.file.path;
        project.voiceoverDurationSec = duration;
        _voiceRemaining = remaining;
        _voiceStatus = result.cached
            ? 'Cached voice — 0 new calls (same script).$syncNote'
            : result.usedDeviceFallback
                ? 'Device voice used (proxy/cap issue) — 0 proxy calls.$syncNote'
                : 'New voice — ${result.proxyRequests} request(s) used.$syncNote';
      });
      _scheduleSave();
    } catch (e, s) {
      // Build 7: recorded with its boundary tag (no banner) —
      // the status line below still reports it to the user.
      CrashGuard.captureHandled(e, s, source: 'maker.voice');
      if (!mounted) return;
      setState(() {
        _voiceBusy = false;
        _voiceStatus = 'Could not create the voice: $e';
      });
    }
  }

  Future<void> _pasteTicker() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _showMessage('Clipboard is empty — copy some text first.');
      return;
    }
    setState(() => _tickerController.text = text);
    _scheduleSave();
  }

  /// v1.5.2 (fix #65): Paste for the English ticker's box — the
  /// same paste-to-run contract as the Urdu ticker's.
  Future<void> _pasteEnglishTicker() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _showMessage('Clipboard is empty — copy some text first.');
      return;
    }
    setState(() => _englishTickerController.text = text);
    _scheduleSave();
  }

  Future<void> _reloadPreset() async {
    final presets = await ChannelPresetStore.loadAll();
    final selectedId = await ChannelPresetStore.loadSelectedId();
    final preset = selectedId == null
        ? presets.first
        : presets.firstWhere(
            (p) => p.id == selectedId,
            orElse: () => presets.first,
          );
    if (!mounted) return;
    _restorePartsState(preset);
    setState(() {
      _preset = preset;
      _allPresets = presets;
      _syncStudioControllers();
    });
  }

  /// Build 13 (point 6): restores a preset's WORKING logo parts
  /// from its paid save while the save is active; an expired
  /// save is cleared for good (the user's model: expiry = the
  /// settings are gone, saving again costs another 300 coins).
  void _restorePartsState(ChannelPreset preset) {
    final now = DateTime.now().millisecondsSinceEpoch;
    switch (logoPartsSaveState(preset.logoPartsSavedAtMs, now)) {
      case LogoPartsSaveState.active:
        if (preset.logoParts.isEmpty) {
          // Build 2: the payload carries the SCENE (glow +
          // base) with the parts; a Build 1 payload (bare
          // list) restores the parts with the default scene.
          final data = decodeLogoPartsSave(preset.logoPartsSavedJson);
          preset.logoParts = data.parts;
          preset.logoPartsScene = data.scene;
          preset.logoPartsSourcePath = preset.logoPath;
        }
      case LogoPartsSaveState.expired:
        preset.logoPartsSavedJson = '';
        preset.logoPartsSavedAtMs = 0;
        preset.logoParts = const [];
        preset.logoPartsScene = LogoPartsScene();
        preset.logoPartsSourcePath = null;
        unawaited(persistPresetChange(preset));
      case LogoPartsSaveState.never:
        break;
    }
  }

  /// Build 5 (v1.5.7): the Template panel's preset selector —
  /// switching the channel preset persists the selection via the
  /// store (the retired Template & Studio / Branding screens'
  /// behaviour) and re-syncs every preset-level panel field.
  Future<void> _switchPreset(ChannelPreset next) async {
    if (_preset?.id == next.id) return;
    await ChannelPresetStore.saveAll(_allPresets, selectedId: next.id);
    if (!mounted) return;
    _restorePartsState(next);
    setState(() {
      _preset = next;
      _syncStudioControllers();
    });
  }

  /// v1.5.2 (coherence, fixes #57/#62b/#63b): THE one place a
  /// template selection is applied in the Maker — it sets BOTH
  /// switches that decide the render (the project's template
  /// kind AND the preset's Final variant) and persists both, so
  /// the header, the picker cards and the preview can never
  /// disagree again. (Before this fix the Template chips set only
  /// the kind: a project whose preset variant was Classic 2 kept
  /// rendering blue/red while its header said 'Final 3-Ribbon'.)
  Future<void> _applyTemplatePick(TemplatePick pick) async {
    final project = _project;
    if (project == null) return;
    if (await openTemplatePickDestination(context, pick)) {
      await _reloadPreset();
      return;
    }
    switch (pick) {
      case TemplatePick.final3:
        project.templateKind = 'nigraanFinal';
        project.breaking = false;
        await _applyFinalVariant(final3: true);
      case TemplatePick.classic2:
        project.templateKind = 'nigraanFinal';
        project.breaking = false;
        await _applyFinalVariant(final3: false);
      case TemplatePick.breaking:
        project.templateKind = 'breaking';
        project.breaking = true;
      case TemplatePick.classic:
        project.templateKind = 'classic';
        project.breaking = false;
      case TemplatePick.store:
      case TemplatePick.library:
        break; // handled by openTemplatePickDestination above
    }
    if (!mounted) return;
    setState(() {});
    _scheduleSave();
  }

  /// The Final design variant lives on the PRESET (the export reads
  /// the preset, so a preview-only variant would lie) — set +
  /// persist it, exactly like Template & Studio does.
  Future<void> _applyFinalVariant({required bool final3}) async {
    final preset = _preset;
    if (preset == null) return;
    preset.finalVariant = final3 ? kFinalVariant3 : kFinalVariantClassic2;
    await persistPresetChange(preset);
    if (!mounted) return;
    setState(() {});
  }

  /// v1.5.2 (coherence): a Ribbons-panel DESIGN pick — a ribbon
  /// design exists only on the Final template family, so picking
  /// one also brings the project onto that family (kind +
  /// variant together, persisted) instead of flipping the
  /// variant alone under a Breaking/Classic project.
  Future<void> _applyRibbonDesignPick(RibbonPick pick) async {
    final project = _project;
    final preset = _preset;
    if (project == null || preset == null) return;
    switch (pick) {
      case RibbonPick.finalDesign:
      case RibbonPick.classicDesign:
        project.templateKind = 'nigraanFinal';
        project.breaking = false;
        applyRibbonDesign(
          preset,
          final3: pick == RibbonPick.finalDesign,
        );
        await persistPresetChange(preset);
        if (!mounted) return;
        setState(() {});
        _scheduleSave();
      case RibbonPick.studio:
        // Build 5 (v1.5.7): Template & Studio is retired — its
        // controls live in the Template panel now, so the rail's
        // Studio card (hidden in this panel) lands there.
        setState(() => _activeTool = 'template');
      case RibbonPick.store:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                const StoreScreen(initialCategory: 'Ribbons'),
          ),
        );
    }
  }

  Future<void> _openSeo() async {
    final project = _project;
    if (project == null) return;
    await _saveNow();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SeoScreen(project: project)),
    );
    // SEO may have changed — reload the saved project.
    final reloaded = await NewsProjectStore.load(project.id);
    if (reloaded != null && mounted) {
      setState(() => _project = reloaded);
    }
  }

  /// Preview preset: a clone of the working preset whose top ribbon
  /// carries the ticker text (or the headline when the ticker field
  /// is empty — the preview never invents a ticker, it shows the
  /// story's own first line).
  ChannelPreset _previewPreset() {
    final preset = ChannelPreset.fromJson(_preset!.toJson());
    final ticker = _tickerController.text.trim();
    preset.topRibbon.text = ticker.isEmpty
        ? extractHeadline(_tehreerController.text)
        : ticker;
    // v1.5.2 (fix #65): the English ticker box drives the bottom
    // ribbon — the same rule effectivePresetFor applies at
    // export, so preview and export agree.
    final englishTicker = _englishTickerController.text.trim();
    if (englishTicker.isNotEmpty) {
      preset.englishRibbon.text = englishTicker;
    }
    // v1.5.2 (fix #65): the project's direction override steers
    // the top ticker's marquee in this preview too (the Breaking
    // template already honours it; the Final bands' directions
    // are fixed by the design, exactly as in the parity export).
    final directionOverride = _project?.tickerDirection;
    if (directionOverride != null) {
      preset.topRibbon.direction =
          RibbonDirection.fromId(directionOverride);
    }
    // Build 13 (point #19): the project's ticker speed + loop
    // ride the clone as transient fields — the same rule
    // effectivePresetFor applies at export, so preview and
    // export agree.
    final proj = _project;
    if (proj != null) {
      preset.tickerSpeedFactor = proj.tickerSpeed;
      preset.tickerLoop = proj.tickerLoop;
    }
    // Build 13 (point 6): the working logo parts ride the
    // preview clone too (transient — see ChannelPreset).
    // Build 2: their SCENE (glow + base) rides along.
    final src = _preset;
    if (src != null) {
      preset.logoParts = src.logoParts;
      preset.logoPartsScene = src.logoPartsScene;
      preset.logoPartsSourcePath = src.logoPartsSourcePath;
    }
    return preset;
  }

  /// v1.5.2 (coherence, fixes #57/#62b/#63b): the header label —
  /// derived from BOTH render switches (project kind + preset
  /// variant) through the ONE shared derivation, so it can never
  /// claim a design the preview is not rendering.
  String _templateLabel(NewsProject project) => templateDisplayLabel(
        templateKind: project.templateKind,
        isFinal3: _preset?.finalIs3Ribbon ?? true,
        breakingVariantLabel:
            BreakingVariant.fromId(project.breakingVariant).label,
      );

  @override
  Widget build(BuildContext context) {
    return Theme(
      // Build 4 (News Studio workspace, approved mockup): deep
      // navy/charcoal palette, gold as the single accent, thin
      // sliders with white thumbs, dark switch/chip grammar.
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFC800),
          secondary: Color(0xFFFFC800),
          surface: Color(0xFF12151C),
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0D12),
        cardColor: const Color(0xFF12151C),
        sliderTheme: const SliderThemeData(
          trackHeight: 2.5,
          activeTrackColor: Color(0xFFFFC800),
          inactiveTrackColor: Color(0x21FFFFFF),
          thumbColor: Colors.white,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
          valueIndicatorColor: Color(0xFFFFC800),
          valueIndicatorTextStyle: TextStyle(color: Colors.black),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.selected)
                ? const Color(0xFFFFC800)
                : const Color(0xFF9AA1AB),
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.selected)
                ? const Color(0xFF232833)
                : const Color(0xFF171B24),
          ),
          trackOutlineColor: WidgetStateProperty.resolveWith(
            (st) => st.contains(WidgetState.selected)
                ? const Color(0x73FFC800)
                : const Color(0x1FFFFFFF),
          ),
        ),
        chipTheme: const ChipThemeData(
          backgroundColor: Color(0xFF171B24),
          selectedColor: Color(0xFFFFC800),
          checkmarkColor: Colors.black,
          labelStyle: TextStyle(color: Color(0xFFC4C9D0), fontSize: 12.5),
          secondaryLabelStyle:
              TextStyle(color: Colors.black, fontSize: 12.5),
          side: BorderSide(color: Color(0x1FFFFFFF)),
        ),
      ),
      child: Scaffold(
        // The AppBar is replaced by the workspace project bar
        // (first row of _buildBody): back, project title, undo /
        // redo, save, preset chip, flat gold Export.
        body: SafeArea(
          child: !_loaded || _preset == null || _project == null
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(_preset!, _project!),
        ),
      ),
    );
  }

  /// v1.5.1 (News Studio step, NS2): the tool line — 12 tools in
  /// the approved order. Tapping one opens its panel under the
  /// preview; tapping it again returns to the summary card.
  static const _toolDefs = <(String, IconData, String)>[
    ('template', Icons.dashboard_customize_outlined, 'Template'),
    ('media', Icons.video_library_outlined, 'Media'),
    ('elements', Icons.widgets_outlined, 'Elements'),
    ('tehreer', Icons.edit_note, 'Tehreer'),
    ('ticker', Icons.short_text, 'Ticker'),
    ('ribbons', Icons.view_agenda_outlined, 'Ribbons'),
    ('logo', Icons.image_outlined, 'Logo'),
    ('reporter', Icons.person_pin_outlined, 'Reporter'),
    ('audio', Icons.audiotrack_outlined, 'Audio'),
    ('voice', Icons.record_voice_over_outlined, 'Voice'),
    ('captions', Icons.closed_caption_outlined, 'Captions'),
    ('export', Icons.ios_share_outlined, 'Export'),
    // Build M1 (v1.11.0, user order): the Motion Graphics
    // Studio's third entry point — appended at the END of the
    // dock so the approved 12 keep their exact order. Unlike
    // the others it opens a SCREEN (the Motion Gallery), not a
    // panel — see the special case in _toolLine's onTap.
    ('motion', Icons.animation, 'Motion'),
  ];

  /// Build 13: the user's own tool icons (his artwork, supplied
  /// 2026-11-25) for the tools he provided them for. Tools NOT
  /// in this map (Ribbons, Audio, Voice, Export — he has not
  /// sent theirs yet) keep their Material icons above.
  static const _toolIconAssets = <String, String>{
    'template': 'assets/ns_icons/template.png',
    'media': 'assets/ns_icons/media.png',
    'elements': 'assets/ns_icons/elements.png',
    'tehreer': 'assets/ns_icons/tehreer.png',
    'ticker': 'assets/ns_icons/ticker.png',
    'logo': 'assets/ns_icons/logo.png',
    'reporter': 'assets/ns_icons/reporter.png',
    'captions': 'assets/ns_icons/captions.png',
  };

  Widget _toolLine() {
    // Editors' tool-line item geometry (Photo Editor toolbar):
    // 64-wide icon-above-label items in one horizontal line.
    return SizedBox(
      key: const Key('makerToolLine'),
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        itemCount: _toolDefs.length,
        separatorBuilder: (_, _) => Container(
          width: 1,
          margin: const EdgeInsets.symmetric(vertical: 16),
          color: const Color(0x14FFFFFF),
        ),
        itemBuilder: (ctx, i) {
          final (id, icon, label) = _toolDefs[i];
          final active = _activeTool == id;
          final color =
              active ? const Color(0xFFF5C542) : Colors.white70;
          return InkWell(
            key: Key('makerTool-$id'),
            onTap: () {
              // Build M1: Motion is a door, not a panel — it
              // pushes the Motion Gallery and never becomes the
              // active tool (no 'motion' panel exists).
              if (id == 'motion') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MotionGalleryScreen(),
                  ),
                );
                return;
              }
              setState(() => _activeTool = active ? null : id);
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 64,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border(
                  bottom: BorderSide(
                    color: active
                        ? const Color(0xFFF5C542)
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_toolIconAssets[id] != null)
                    Image.asset(
                      _toolIconAssets[id]!,
                      key: Key('makerToolIcon-$id'),
                      width: 26,
                      height: 26,
                      errorBuilder: (context, error, stack) =>
                          Icon(icon, size: 24, color: color),
                    )
                  else
                    Icon(icon, size: 24, color: color),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(fontSize: 11, color: color),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Panel host (v1.5.2, fix #69a — the editors' ONE safe host,
  /// mirrored from the Photo Editor): a fixed-height bottom zone
  /// with the panel header (title + ONE gold ✓ that closes back
  /// to the tool line) and the panel's content in an Expanded
  /// SingleChildScrollView. Panel content can NEVER overflow
  /// this host — it scrolls. Every Maker panel mounts here.
  Widget _panelShell(String title, List<Widget> children) {
    // Material (not a coloured Container) paints the panel
    // background: panels contain SwitchListTiles, and a ListTile
    // under a ColoredBox loses its background/ink (framework
    // assertion in debug, invisible tile states in release).
    return Material(
      key: Key('makerPanel-$_activeTool'),
      color: const Color(0xFF12151C),
      child: Container(
        height: _lowerZoneHeight,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'INSPECTOR',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2,
                  color: Color(0xFF8A919C),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFECEEF1),
                  ),
                ),
              ),
              // Point #21: har tool ki Guide — isi panel ke
              // tool ki guide khulti hai (data: tool_guide.dart).
              if (_activeTool != null)
                ToolGuideButton(guideId: 'ns.$_activeTool', compact: true),
              InkWell(
                key: const Key('makerPanelDone'),
                onTap: () => setState(() => _activeTool = null),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF5C542),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 17,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }

  LibraryItem? _libraryById(List<LibraryItem> items, String id) {
    if (id.isEmpty) return null;
    for (final item in items) {
      if (item.folderId == id) return item;
    }
    return null;
  }

  /// One Library picker (Text Styles / Transitions / Effects):
  /// 'None' + one chip per valid Drive item. An empty library
  /// shows the honest note instead of a dead control.
  Widget _libraryPicker({
    required String keyPrefix,
    required List<LibraryItem> items,
    required String selectedId,
    required ValueChanged<String> onChanged,
    required String emptyNote,
  }) {
    if (items.isEmpty) {
      return Text(
        emptyNote,
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      );
    }
    // v1.5.2 (fix #60): ONE horizontal rail, the editors' choice
    // row — no multi-row Wrap.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            key: Key('$keyPrefix-none'),
            label: const Text('None'),
            selected: selectedId.isEmpty,
            onSelected: (_) => onChanged(''),
          ),
          const SizedBox(width: 8),
          for (final item in items) ...[
            ChoiceChip(
              key: Key('$keyPrefix-${item.folderId}'),
              label: Text(item.name),
              selected: selectedId == item.folderId,
              onSelected: (_) => onChanged(item.folderId),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }


  // ==========================================================
  // Build 4 — News Studio workspace (approved mockup): project
  // bar, stage chips, summary inspector, timeline zone, and the
  // snapshot undo/redo behind the bar's arrows.
  // ==========================================================

  /// The one place the five text controllers + voice picks are
  /// written back into the working project (was inline in
  /// [_saveNow]; undo/redo need the same sync).
  void _syncTextControllers(NewsProject project) {
    project.tehreer = _tehreerController.text;
    project.tickerText = _tickerController.text;
    project.englishTickerText = _englishTickerController.text;
    project.tickerLabel = _tickerLabelController.text.trim();
    project.reporterName = _reporterNameController.text;
    project.voice = _voice;
    project.studioVoiceId = _studioVoiceId;
  }

  Future<void> _undoProject() async {
    final project = _project;
    if (project == null || _undoStack.isEmpty) return;
    _syncTextControllers(project);
    _redoStack.add(jsonEncode(project.toJson()));
    await _restoreProject(_undoStack.removeLast());
  }

  Future<void> _redoProject() async {
    final project = _project;
    if (project == null || _redoStack.isEmpty) return;
    _syncTextControllers(project);
    _undoStack.add(jsonEncode(project.toJson()));
    await _restoreProject(_redoStack.removeLast());
  }

  /// Restores one snapshot: swaps the working project and re-syncs
  /// every screen-level mirror (voice picks + text controllers),
  /// then persists the restored state without touching history.
  Future<void> _restoreProject(String snap) async {
    final restored = NewsProject.fromJson(
      jsonDecode(snap) as Map<String, dynamic>,
    );
    _restoringHistory = true;
    setState(() {
      _project = restored;
      _voice = restored.voice;
      _studioVoiceId = restored.studioVoiceId.isNotEmpty
          ? restored.studioVoiceId
          : restored.voice.name;
      _tehreerController.text = restored.tehreer;
      _tickerController.text = restored.tickerText;
      _englishTickerController.text = restored.englishTickerText;
      _tickerLabelController.text = restored.tickerLabel;
      _reporterNameController.text = restored.reporterName;
      _selectedElement = NewsElement.media;
    });
    await _refreshVoiceStatus();
    await _saveNow();
    _restoringHistory = false;
    _lastSnap = snap;
    unawaited(_probeClips());
  }

  /// Probes clip durations + grabs one first-frame thumbnail per
  /// clip for the timeline zone. Decoration only: every failure is
  /// swallowed and the lane falls back to a plain block.
  Future<void> _probeClips() async {
    final project = _project;
    if (project == null) return;
    var changed = false;
    for (final path in project.clipPaths) {
      final ext = p.extension(path).toLowerCase();
      const photoExts = {'.jpg', '.jpeg', '.png', '.webp'};
      if (photoExts.contains(ext)) {
        if (_clipThumbs[path] != path) {
          _clipThumbs[path] = path;
          changed = true;
        }
        continue;
      }
      if (!_clipDurations.containsKey(path)) {
        try {
          final c = VideoPlayerController.file(File(path));
          await c.initialize();
          final d = c.value.duration.inMilliseconds / 1000.0;
          await c.dispose();
          if (d > 0) {
            _clipDurations[path] = d;
            changed = true;
          }
        } catch (e, s) {
          // Not a readable video — the lane uses equal flex.
          // Build 7 (v1.5.9): recorded (no banner) so a preview
          // player init/dispose failure is diagnosable from
          // About → Diagnostics instead of staying invisible.
          CrashGuard.captureHandled(e, s, source: 'maker.preview');
        }
      }
      if (!_clipThumbs.containsKey(path)) {
        try {
          final dir = await getTemporaryDirectory();
          final td = Directory(p.join(dir.path, 'maker_thumbs'));
          if (!await td.exists()) await td.create(recursive: true);
          final out = p.join(
            td.path,
            'mt_${path.hashCode.toUnsigned(31).toRadixString(36)}.jpg',
          );
          if (await File(out).exists()) {
            _clipThumbs[path] = out;
            changed = true;
          } else {
            final res = await FfmpegService.run(
              '-y -ss 0.50 -i ${FfmpegService.q(path)} '
              '-frames:v 1 -vf scale=128:-1 -q:v 4 '
              '${FfmpegService.q(out)}',
            );
            if (res.ok && await File(out).exists()) {
              _clipThumbs[path] = out;
              changed = true;
            }
          }
        } catch (_) {
          // Thumbnails are decoration — never an error path.
        }
      }
      // v1.16.0 G5 (B7): the filmstrip — several frames across
      // the clip so a long clip shows what is inside it. Only
      // for probed videos; a single-frame strip is pointless
      // (the plain thumbnail already covers it).
      if (!_clipStrips.containsKey(path)) {
        final d = _clipDurations[path];
        if (d != null && d > 0) {
          try {
            final td = Directory(
                p.join((await getTemporaryDirectory()).path, 'maker_thumbs'));
            if (!await td.exists()) await td.create(recursive: true);
            final times = nsStripFrameTimes(d);
            if (times.length > 1) {
              final frames = <String>[];
              var okAll = true;
              for (var fi = 0; fi < times.length; fi++) {
                final out = p.join(
                  td.path,
                  'mts_${path.hashCode.toUnsigned(31).toRadixString(36)}_$fi.jpg',
                );
                if (!await File(out).exists()) {
                  final res = await FfmpegService.run(
                    '-y -ss ${times[fi].toStringAsFixed(2)} '
                    '-i ${FfmpegService.q(path)} '
                    '-frames:v 1 -vf scale=96:-1 -q:v 5 '
                    '${FfmpegService.q(out)}',
                  );
                  if (!res.ok) {
                    okAll = false;
                    break;
                  }
                }
                frames.add(out);
              }
              if (okAll && frames.length > 1) {
                _clipStrips[path] = frames;
                changed = true;
              }
            }
          } catch (_) {
            // Filmstrips are decoration — never an error path.
          }
        }
      }
    }
    if (changed && mounted) setState(() {});
  }

  /// v1.16.0 G5 (B7): a lane waveform PNG for an audio file
  /// (voiceover / store music), rendered once via showwavespic
  /// and cached in the temp dir. Silent failure: no waveform,
  /// the lane keeps its plain look.
  Future<void> _ensureNsWave(String audioPath, {required bool voice}) async {
    final key = '${voice ? 'vo' : 'mu'}|$audioPath';
    if (_nsWaveCache.containsKey(key) || _nsWavePending.contains(key)) {
      return;
    }
    _nsWavePending.add(key);
    try {
      final dir = await getTemporaryDirectory();
      final out = p.join(
        dir.path,
        'ns_wave_${voice ? 'vo' : 'mu'}_${audioPath.hashCode.toUnsigned(31).toRadixString(36)}.png',
      );
      if (await File(out).exists()) {
        _nsWaveCache[key] = out;
        if (mounted) setState(() {});
        return;
      }
      final result = await FfmpegService.run(
        '-y -i ${FfmpegService.q(audioPath)} -filter_complex '
        '"showwavespic=s=800x48:colors=${voice ? '0xFFC800' : '0x90CAF9'}" '
        '-frames:v 1 ${FfmpegService.q(out)}',
      );
      _nsWaveCache[key] =
          (result.ok && await File(out).exists()) ? out : '';
      if (mounted) setState(() {});
    } catch (_) {
      _nsWaveCache[key] = '';
    } finally {
      _nsWavePending.remove(key);
    }
  }

  String _fmtDur(double sec) {
    final s = sec.round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// One slim 34px bar icon (fixed size so the bar's width is
  /// deterministic at 360px — the overflow guard's phone size).
  Widget _barIcon(
    IconData icon,
    double size,
    Color color,
    VoidCallback? onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 30,
        height: 34,
        child: Icon(
          icon,
          size: size,
          color: onTap == null ? const Color(0xFF3A4048) : color,
        ),
      ),
    );
  }

  /// Slim project bar: back, project title + save status,
  /// undo/redo (snapshot history), the save check (the old AppBar
  /// action, unchanged), a preset chip that opens the Template
  /// panel, and the flat gold Export (opens the Export panel).
  Widget _projectBar(
    ChannelPreset preset,
    NewsProject project,
    String templateLabel,
  ) {
    final title = project.title.trim().isNotEmpty
        ? project.title
        : project.tehreer.trim().isNotEmpty
            ? project.tehreer
            : preset.name;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0D12),
        border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Row(
        children: [
          _barIcon(
            Icons.arrow_back_ios_new,
            18,
            const Color(0xFFD8DCE2),
            () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFECEEF1),
                  ),
                ),
                Row(
                  children: [
                    const Flexible(
                      child: Text(
                        'News Maker',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF5E646F),
                        ),
                      ),
                    ),
                    if (_saveStatus.isNotEmpty)
                      Flexible(
                        child: Text(
                          ' • $_saveStatus',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF5E646F),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          _barIcon(
            Icons.undo,
            20,
            const Color(0xFFAEB4BD),
            _undoStack.isEmpty ? null : _undoProject,
          ),
          _barIcon(
            Icons.redo,
            20,
            const Color(0xFFAEB4BD),
            _redoStack.isEmpty ? null : _redoProject,
          ),
          _barIcon(
            Icons.check,
            20,
            const Color(0xFFAEB4BD),
            () async {
              await _saveNow();
              _showMessage('Project saved.');
            },
          ),
          InkWell(
            onTap: () => setState(() => _activeTool = 'template'),
            borderRadius: BorderRadius.circular(7),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 56),
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: const Color(0x1FFFFFFF)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFC800),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      templateLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFC9CDD3),
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    size: 15,
                    color: Color(0xFF8A919C),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 2),
          // Build 5 (v1.5.7): the workspace menu — the retired
          // News Studio hub's unique destinations live here now
          // (project chooser, AI News Maker, Channel Branding,
          // Advertise), inside the workspace's own project bar.
          // The tight 34px box keeps the bar inside a 360px phone
          // at large text scales (the default menu button is
          // 48px and overflowed the bar — see BUILD5 report).
          SizedBox(
            width: 34,
            height: 34,
            child: PopupMenuButton<String>(
              key: const Key('makerMoreMenu'),
              icon: const Icon(
                Icons.more_vert,
                size: 20,
                color: Color(0xFFAEB4BD),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(maxWidth: 260),
              color: const Color(0xFF171B24),
              onSelected: _onMakerMenu,
              itemBuilder: (ctx) => const [
                PopupMenuItem(
                  value: 'projects',
                  child: Text('Projects — open / new / delete'),
                ),
                PopupMenuItem(
                  value: 'ai',
                  child: Text('AI News Maker (One Click)'),
                ),
                PopupMenuItem(
                  value: 'branding',
                  child: Text('Channel Branding'),
                ),
                PopupMenuItem(
                  value: 'advertise',
                  child: Text('Advertise'),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => setState(() => _activeTool = 'export'),
            borderRadius: BorderRadius.circular(7),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC800),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.upload_outlined, size: 15, color: Colors.black),
                  SizedBox(width: 5),
                  Text(
                    'Export',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 2),
        ],
      ),
    );
  }

  /// Build 5 (v1.5.7): the project-bar menu's actions — the
  /// retired hub's unique destinations, one tap each from inside
  /// the workspace.
  void _onMakerMenu(String action) {
    switch (action) {
      case 'projects':
        unawaited(_showProjectChooser());
      case 'ai':
        unawaited(_openStudioDestination(const AiNewsMakerScreen()));
      case 'branding':
        unawaited(
          _openStudioDestination(
            ChannelBrandingScreen(initialPreset: _preset),
          ),
        );
      case 'advertise':
        unawaited(_openStudioDestination(const AdvertiseScreen()));
    }
  }

  /// Pushes a studio destination and re-syncs on return (the
  /// destination may have changed the preset or the project —
  /// the same reload the retired hub did after every push). The
  /// pre-push save is fire-and-forget: the Maker's autosave has
  /// already persisted every edit, and navigation must never
  /// wait on storage.
  Future<void> _openStudioDestination(Widget screen) async {
    unawaited(_saveNow());
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
    await _reloadPreset();
    final current = _project;
    if (current == null || !mounted) return;
    final reloaded = await NewsProjectStore.load(current.id);
    if (reloaded != null && mounted) {
      setState(() => _project = reloaded);
    }
  }

  /// Build 5 (v1.5.7): the workspace's own project chooser — the
  /// retired hub's Recent projects list + draft handling, folded
  /// into the project bar (project selection happens INSIDE the
  /// workspace screen, not on a separate hub). The Maker already
  /// auto-loads the latest project on entry, so the old recovery
  /// card's Resume is automatic; its Discard is the delete here.
  Future<void> _showProjectChooser() async {
    final all = await NewsProjectStore.loadAll();
    if (!mounted) return;
    final sorted = List<NewsProject>.from(all)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12151C),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              key: const Key('chooserNewProject'),
              leading: const Icon(
                Icons.add_circle_outline,
                color: Color(0xFFFFC800),
              ),
              title: const Text('New project'),
              onTap: () {
                Navigator.of(ctx).pop();
                unawaited(_newProject());
              },
            ),
            const Divider(height: 1),
            if (sorted.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No project yet.',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in sorted)
                      ListTile(
                        key: Key('chooserProject-${p.id}'),
                        leading: Icon(
                          p.id == _project?.id
                              ? Icons.radio_button_checked
                              : Icons.folder_open_outlined,
                          size: 20,
                          color: p.id == _project?.id
                              ? const Color(0xFFFFC800)
                              : const Color(0xFFAEB4BD),
                        ),
                        title: Text(
                          p.title.trim().isNotEmpty
                              ? p.title
                              : p.tehreer.trim().isNotEmpty
                                  ? p.tehreer
                                  : 'Untitled project',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${p.clipPaths.length} clip(s) • '
                          '${p.updatedAt.day}/${p.updatedAt.month} '
                          '${p.updatedAt.hour.toString().padLeft(2, '0')}:'
                          '${p.updatedAt.minute.toString().padLeft(2, '0')}'
                          '${isRecoverableDraft(p) ? ' • Draft' : ''}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 19),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            unawaited(_deleteProject(p));
                          },
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          unawaited(_openProject(p));
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Opens [project] in the workspace (the chooser's tap): swaps
  /// the working project and re-syncs every mirror (voice picks,
  /// text controllers, history) — the same sync [_load] does.
  Future<void> _openProject(NewsProject project) async {
    await _saveNow();
    if (!mounted) return;
    setState(() {
      _project = project;
      _voice = project.voice;
      _studioVoiceId = project.studioVoiceId.isNotEmpty
          ? project.studioVoiceId
          : project.voice.name;
      _tehreerController.text = project.tehreer;
      _tickerController.text = project.tickerText;
      _englishTickerController.text = project.englishTickerText;
      _tickerLabelController.text = project.tickerLabel;
      _reporterNameController.text = project.reporterName;
      _selectedElement = NewsElement.media;
      _undoStack.clear();
      _redoStack.clear();
    });
    _lastSnap = jsonEncode(project.toJson());
    unawaited(_probeClips());
    await _refreshVoiceStatus();
  }

  Future<void> _newProject() async {
    final preset = _preset;
    if (preset == null) return;
    final project = NewsProject.create(presetId: preset.id);
    await NewsProjectStore.save(project);
    await _openProject(project);
  }

  /// Deletes a project (the chooser's discard). Deleting the
  /// open project falls back to the latest remaining one, or a
  /// fresh project when none is left.
  Future<void> _deleteProject(NewsProject project) async {
    await NewsProjectStore.delete(project.id);
    if (!mounted) return;
    if (_project?.id != project.id) return;
    final latest = await NewsProjectStore.loadLatest();
    if (!mounted) return;
    if (latest != null) {
      await _openProject(latest);
    } else {
      await _newProject();
    }
  }

  Widget _stageChip(String label, {bool goldDot = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x9E06080A),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (goldDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFFFFC800),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFFC9CDD3),
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  /// The inspector zone when no tool is open: the summary — the
  /// old header label (preset • template • save status) lives
  /// here now, unchanged.
  Widget _summaryInspector(
    ChannelPreset preset,
    NewsProject project,
    String templateLabel,
  ) {
    return Material(
      color: const Color(0xFF12151C),
      child: Container(
        // Build 5 (v1.5.7, error-banner fix): NO fixed height —
        // the old fixed 84px box overflowed by ~11px at textScale
        // 1.3 (the user's phone), and that RenderFlex overflow
        // refiring on every layout was the repeating CrashGuard
        // banner in the v1.5.6 screenshots. The column now sizes
        // to its content; the preview's Expanded absorbs the
        // difference.
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Text(
                  'INSPECTOR',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 2,
                    color: Color(0xFF8A919C),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  'Summary',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFECEEF1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${preset.name} preset • $templateLabel'
              '${_saveStatus.isEmpty ? '' : ' • $_saveStatus'}',
              key: const Key('makerHeaderLabel'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF8A919C),
                fontSize: 12.5,
              ),
            ),
            const Text(
              'Choose a tool from the tool line — the timeline\'s lanes also '
              'open the same tool.',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Color(0xFF5E646F), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  /// One timeline tab (Build 13, point #19): the reference's
  /// CLIPS / VOICE / TICKER / RIBBONS tabs. Tapping selects the
  /// tab (gold) AND opens its tool below — the pre-Build-13
  /// behaviour of these chips, kept.
  Widget _tlChip(
    String label,
    IconData icon,
    String tool,
    String tab, {
    String? imageAsset,
  }) {
    final selected = _timelineTab == tab;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        key: Key('tlTab-$tab'),
        onTap: () => setState(() {
          _activeTool = tool;
          _timelineTab = tab;
        }),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0x1AFFC800)
                : const Color(0x0DFFFFFF),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: selected
                  ? const Color(0xFFFFC800)
                  : const Color(0x1FFFFFFF),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (imageAsset != null)
                Image.asset(
                  imageAsset,
                  key: Key('tlTabIcon-$tab'),
                  width: 16,
                  height: 16,
                  errorBuilder: (context, error, stack) => Icon(
                    icon,
                    size: 14,
                    color: selected
                        ? const Color(0xFFFFC800)
                        : const Color(0xFFAEB4BD),
                  ),
                )
              else
                Icon(
                  icon,
                  size: 14,
                  color: selected
                      ? const Color(0xFFFFC800)
                      : const Color(0xFFAEB4BD),
                ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.normal,
                  color: selected
                      ? const Color(0xFFFFC800)
                      : const Color(0xFFC4C9D0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The project timeline (Build 13, point #19 — upgraded to
  /// the reference-style WORKING panel; this is the same single
  /// timeline zone, not a second one): a transport row (play /
  /// pause / stop + time, driving the media preview's own
  /// player), the CLIPS / VOICE / TICKER / RIBBONS tabs, a time
  /// ruler, and the V1 / A1 / A2 / TC lanes reflecting the real
  /// project state, with a gold playhead at the transport
  /// position. P0-4 (Point #27): it shows only in the no-tool
  /// state — opening any tool collapses it away so the preview
  /// keeps its full size; closing the tool brings it back.
  /// P1-3: the USED length of timeline entry [i] — its file
  /// duration run through its trim range (a split's halves count
  /// their own parts, not the whole file twice).
  double? _entryDurationSec(NewsProject project, int i) =>
      project.clipEffectiveDurationAt(
        i,
        _clipDurations[project.clipPaths[i]],
      );

  Widget _timelineZone(NewsProject project) {
    final compact = MediaQuery.of(context).size.height < 700;
    var clipsTotal = 0.0;
    for (var i = 0; i < project.clipPaths.length; i++) {
      final eff = _entryDurationSec(project, i);
      if (eff != null) clipsTotal += eff;
    }
    final totalAll =
        clipsTotal > 0 ? clipsTotal : (project.voiceoverDurationSec ?? 0);
    final hasVoice = project.voiceoverPath != null &&
        project.voiceoverPath!.isNotEmpty;
    // v1.16.0 G5 (B7): lane waveforms — cached renders; the
    // ensure calls are no-ops once rendered or in flight.
    if (hasVoice) {
      unawaited(_ensureNsWave(project.voiceoverPath!, voice: true));
    }
    if (project.storeMusicPath != null) {
      unawaited(_ensureNsWave(project.storeMusicPath!, voice: false));
    }
    final tickerText = project.tickerText.trim().isNotEmpty
        ? project.tickerText.trim()
        : project.englishTickerText.trim();
    // T4: the SCALE total counts every clip (an unprobed clip
    // gets a nominal 3 s, so positions exist even before the
    // duration probes land); the header total keeps the probed
    // sum it has always shown.
    var layoutTotal = 0.0;
    for (var i = 0; i < project.clipPaths.length; i++) {
      layoutTotal += _entryDurationSec(project, i) ?? 3.0;
    }
    if (layoutTotal <= 0) layoutTotal = totalAll;
    _nsLayoutTotal = layoutTotal;
    final posSec = _effectivePosSec;
    final shownPos =
        layoutTotal > 0 && posSec > layoutTotal ? layoutTotal : posSec;
    final hasTransport = _transportController != null &&
        (_transportController?.value.isInitialized ?? false);
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0E1118),
        border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'TIMELINE',
                style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1.6,
                  color: Color(0xFF8A919C),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${project.clipPaths.length} clips'
                  '${totalAll > 0 ? ' \u2022 ${_fmtDur(totalAll)}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF5E646F),
                  ),
                ),
              ),
              // Transport: play/pause + stop + the time readout.
              IconButton(
                key: const Key('tlPlayPause'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                constraints:
                    const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: Icon(
                  _transportPlaying ? Icons.pause : Icons.play_arrow,
                  size: 20,
                ),
                color: hasTransport
                    ? const Color(0xFFFFC800)
                    : const Color(0xFF5E646F),
                onPressed: hasTransport ? _transportToggle : null,
              ),
              IconButton(
                key: const Key('tlStop'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                constraints:
                    const BoxConstraints(minWidth: 30, minHeight: 30),
                icon: const Icon(Icons.stop, size: 18),
                color: hasTransport
                    ? const Color(0xFFC4C9D0)
                    : const Color(0xFF5E646F),
                onPressed: hasTransport ? _transportStop : null,
              ),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${_fmtDur(shownPos)} / ${_fmtDur(totalAll)}',
                    key: const Key('tlTimeText'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFC4C9D0),
                    ),
                  ),
                ),
              ),
              // v1.14.0 T4 (B1): timeline zoom — out / fit / in.
              IconButton(
                key: const Key('nsTlZoomOut'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                constraints:
                    const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: const Icon(Icons.remove, size: 16),
                color: const Color(0xFFC4C9D0),
                tooltip: 'Zoom out timeline',
                onPressed: layoutTotal > 0 ? () => _nsZoomBy(1 / 1.5) : null,
              ),
              IconButton(
                key: const Key('nsTlZoomFit'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                constraints:
                    const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: const Icon(Icons.fit_screen, size: 15),
                color: const Color(0xFFC4C9D0),
                tooltip: 'Show all (fit)',
                onPressed: layoutTotal > 0 ? _nsZoomFit : null,
              ),
              IconButton(
                key: const Key('nsTlZoomIn'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                constraints:
                    const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: const Icon(Icons.add, size: 16),
                color: const Color(0xFFC4C9D0),
                tooltip: 'Zoom in timeline',
                onPressed: layoutTotal > 0 ? () => _nsZoomBy(1.5) : null,
              ),
              // v1.15.0 G5 (B9): marker at the playhead position.
              // Toggle: dabane se marker lagta hai; usi jagah
              // dobara dabane se hat jata hai. Marker par tap
              // karne se bhi hat jata hai.
              IconButton(
                key: const Key('nsMarkerAdd'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                constraints:
                    const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: const Icon(Icons.bookmark_add_outlined, size: 16),
                color: const Color(0xFFFFC800),
                tooltip: 'Add / remove marker',
                onPressed: layoutTotal > 0
                    ? () {
                        setState(() {
                          project.timelineMarkers =
                              NewsProject.toggledTimelineMarkers(
                            project.timelineMarkers,
                            shownPos.clamp(0.0, layoutTotal).toDouble(),
                          );
                        });
                        _scheduleSave();
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _tlChip(
                  'Clips',
                  Icons.movie_outlined,
                  'media',
                  'clips',
                  imageAsset: 'assets/ns_icons/clips.png',
                ),
                _tlChip('Voice', Icons.mic_none_outlined, 'voice', 'voice'),
                _tlChip('Ticker', Icons.short_text, 'ticker', 'ticker'),
                _tlChip(
                    'Ribbons', Icons.view_agenda_outlined, 'ribbons', 'ribbons'),
              ],
            ),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              // v1.14.0 T4 (B1/B2/B5): real time-scale geometry.
              // The 52px label column stays fixed; the lane
              // content lives in ONE pixel space (seconds × pps)
              // and shifts by the scroll offset when zoomed past
              // fit. At fit (the default) nothing scrolls and the
              // zone looks exactly as it always has.
              final viewportW = constraints.maxWidth - 52;
              _nsViewportW = viewportW;
              final fitPps =
                  layoutTotal > 0 ? viewportW / layoutTotal : 42.0;
              final pps = (_nsPps ?? fitPps).clamp(4.0, 400.0);
              var contentW = layoutTotal * pps;
              if (contentW < viewportW) contentW = viewportW;
              var maxScroll = contentW - viewportW;
              if (maxScroll < 0) maxScroll = 0;
              final scrollX = _nsScrollX.clamp(0.0, maxScroll);
              Widget laneViewport(double height, Widget child) {
                return SizedBox(
                  height: height,
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned(
                        left: -scrollX,
                        top: 0,
                        width: contentW,
                        child: child,
                      ),
                    ],
                  ),
                );
              }

              final playheadLeft = 52 + shownPos * pps - scrollX;
              // B10: hidden lanes collapse to a slim strip.
              final v1Hidden = _nsLaneHidden.contains('v1');
              final a1Hidden = _nsLaneHidden.contains('a1');
              final a2Hidden = _nsLaneHidden.contains('a2');
              final tcHidden = _nsLaneHidden.contains('tc');
              return GestureDetector(
                // Dragging the lanes scrolls a zoomed timeline;
                // lane/block taps are unaffected (a drag only
                // wins after the touch slop, like every editor).
                onHorizontalDragUpdate: maxScroll > 0
                    ? (d) => setState(() => _nsScrollX =
                        (_nsScrollX - d.delta.dx).clamp(0.0, maxScroll))
                    : null,
                child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!compact && layoutTotal > 0) ...[
                        Row(
                          children: [
                            const SizedBox(width: 52),
                            Expanded(
                              child: GestureDetector(
                                key: const Key('tlRuler'),
                                behavior: HitTestBehavior.opaque,
                                // B2: tap or drag on the ruler
                                // scrubs the playhead.
                                onTapDown: (d) => _scrubTo(project,
                                    (d.localPosition.dx + scrollX) / pps),
                                onHorizontalDragStart: (d) => _scrubTo(
                                    project,
                                    (d.localPosition.dx + scrollX) / pps),
                                onHorizontalDragUpdate: (d) => _scrubTo(
                                    project,
                                    (d.localPosition.dx + scrollX) / pps),
                                child: SizedBox(
                                  height: 16,
                                  child: Stack(
                                    clipBehavior: Clip.hardEdge,
                                    children: [
                                      Positioned(
                                        left: -scrollX,
                                        top: 0,
                                        width: contentW,
                                        child: CustomPaint(
                                          size: Size(contentW, 16),
                                          painter: _NsRulerPainter(
                                            pps: pps,
                                            totalSec: layoutTotal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                      _laneRow(
                        'V1',
                        laneViewport(
                            v1Hidden ? 12.0 : (compact ? 38.0 : 50.0),
                            v1Hidden
                                ? _nsLaneHiddenStrip()
                                : _videoLane(project, compact, pps)),
                        laneId: 'v1',
                      ),
                      const SizedBox(height: 4),
                      _laneRow(
                        'A1',
                        laneViewport(
                          a1Hidden ? 12 : 24,
                          a1Hidden
                              ? _nsLaneHiddenStrip()
                              : InkWell(
                          onTap: () => setState(() {
                            _activeTool = 'voice';
                            _timelineTab = 'voice';
                          }),
                          // v1.16.0 G5 (B7): the voiceover's real
                          // waveform under the label, spanning the
                          // voiceover's own duration on the scale.
                          child: Stack(
                            children: [
                              Container(
                                height: 24,
                                decoration: BoxDecoration(
                                  color: hasVoice
                                      ? const Color(0x1AFFC800)
                                      : const Color(0x0DFFFFFF),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: hasVoice
                                        ? const Color(0x40FFC800)
                                        : const Color(0x14FFFFFF),
                                  ),
                                ),
                              ),
                              if (hasVoice &&
                                  project.voiceoverDurationSec != null &&
                                  (_nsWaveCache[
                                              'vo|${project.voiceoverPath}'] ??
                                          '')
                                      .isNotEmpty)
                                Positioned(
                                  left: 0,
                                  top: 0,
                                  bottom: 0,
                                  width: project.voiceoverDurationSec! *
                                      pps,
                                  child: Opacity(
                                    opacity: 0.85,
                                    child: Image.file(
                                      File(_nsWaveCache[
                                          'vo|${project.voiceoverPath}']!),
                                      fit: BoxFit.fill,
                                      errorBuilder: (_, _, _) =>
                                          const SizedBox.shrink(),
                                    ),
                                  ),
                                ),
                              Container(
                                height: 24,
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                                child: Text(
                                  hasVoice
                                      ? 'VO \u2022 Voiceover'
                                          '${project.voiceoverDurationSec != null ? ' \u2022 ${_fmtDur(project.voiceoverDurationSec!)}' : ''}'
                                      : 'No voiceover — create one from the Voice tool',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: hasVoice
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: hasVoice
                                        ? const Color(0xFFFFC800)
                                        : const Color(0xFF5E646F),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          ),
                        ),
                        laneId: 'a1',
                      ),
                      const SizedBox(height: 4),
                      _laneRow(
                        'A2',
                        laneViewport(
                          a2Hidden ? 12 : 24,
                          a2Hidden
                              ? _nsLaneHiddenStrip()
                              : InkWell(
                          onTap: () => setState(() => _activeTool = 'audio'),
                          // v1.16.0 G5 (B7): the store music's
                          // waveform under the label (built-in
                          // asset music has no file to render —
                          // the label alone shows, as before).
                          child: Stack(
                            children: [
                              Container(
                                height: 24,
                                decoration: BoxDecoration(
                                  color: const Color(0x0DFFFFFF),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                      color: const Color(0x14FFFFFF)),
                                ),
                              ),
                              if (project.storeMusicPath != null &&
                                  (_nsWaveCache[
                                              'mu|${project.storeMusicPath}'] ??
                                          '')
                                      .isNotEmpty)
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: 0,
                                  bottom: 0,
                                  child: Opacity(
                                    opacity: 0.55,
                                    child: Image.file(
                                      File(_nsWaveCache[
                                          'mu|${project.storeMusicPath}']!),
                                      fit: BoxFit.fill,
                                      errorBuilder: (_, _, _) =>
                                          const SizedBox.shrink(),
                                    ),
                                  ),
                                ),
                              Container(
                                height: 24,
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                                child: Text(
                                  _selectedMusicLabel(project),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: Color(0xFFC4C9D0),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          ),
                        ),
                        laneId: 'a2',
                        musicMuted: !project.voiceMusicEnabled,
                        onToggleMusic: () {
                          setState(() => project.voiceMusicEnabled =
                              !project.voiceMusicEnabled);
                          _scheduleSave();
                        },
                      ),
                      const SizedBox(height: 4),
                      _laneRow(
                        'TC',
                        laneViewport(
                          tcHidden ? 12 : 24,
                          tcHidden
                              ? _nsLaneHiddenStrip()
                              : InkWell(
                          onTap: () => setState(() {
                            _activeTool = 'ticker';
                            _timelineTab = 'ticker';
                          }),
                          child: Container(
                            height: 24,
                            alignment: Alignment.centerLeft,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: const Color(0x0DFFFFFF),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                  color: const Color(0x14FFFFFF)),
                            ),
                            child: Text(
                              tickerText.isEmpty
                                  ? 'Ticker is empty'
                                  : tickerText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: tickerText.isEmpty
                                    ? const Color(0xFF5E646F)
                                    : const Color(0xFFC4C9D0),
                              ),
                            ),
                          ),
                          ),
                        ),
                        laneId: 'tc',
                      ),
                    ],
                  ),
                  // The gold playhead at the EFFECTIVE position,
                  // across the lanes (label column included — the
                  // reference draws it across the whole panel).
                  // Time-scale: left = 52 + sec × pps − scroll;
                  // it hides while scrolled out of view.
                  if (layoutTotal > 0 &&
                      playheadLeft >= 51 &&
                      playheadLeft <= constraints.maxWidth - 2)
                    Positioned(
                      left: playheadLeft,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        key: const Key('tlPlayhead'),
                        width: 2,
                        color: const Color(0xFFFFC800),
                      ),
                    ),
                  // v1.15.0 G5 (B9): timeline markers — gold flag
                  // lines across the lanes at their saved seconds
                  // (same pixel math as the playhead). Tap a
                  // marker to remove it.
                  for (var mi = 0;
                      mi < project.timelineMarkers.length;
                      mi++)
                    if (52 + project.timelineMarkers[mi] * pps - scrollX >=
                            46 &&
                        52 + project.timelineMarkers[mi] * pps - scrollX <=
                            constraints.maxWidth - 4)
                      Positioned(
                        left: 52 +
                            project.timelineMarkers[mi] * pps -
                            scrollX -
                            5,
                        top: 0,
                        bottom: 0,
                        child: GestureDetector(
                          key: Key('nsMarker-$mi'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            setState(() {
                              project.timelineMarkers =
                                  NewsProject.toggledTimelineMarkers(
                                project.timelineMarkers,
                                project.timelineMarkers[mi],
                              );
                            });
                            _scheduleSave();
                          },
                          child: SizedBox(
                            width: 12,
                            child: Stack(
                              children: [
                                Center(
                                  child: Container(
                                    width: 2,
                                    color: const Color(0xFFFFC800),
                                  ),
                                ),
                                const Positioned(
                                  top: 0,
                                  left: 1,
                                  child: Icon(
                                    Icons.bookmark,
                                    size: 11,
                                    color: Color(0xFFFFC800),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// One timeline lane row: the fixed 52 px label column + the
  /// lane viewport. v1.15.0 G5 (B10): the label cell also carries
  /// the lane's own controls — an eye (show/hide this lane;
  /// view-only, the project and export are untouched) and, for
  /// A2, the music mute: the project's own [NewsProject]
  /// voiceMusicEnabled switch — the same one the Voice panel
  /// owns and the export honours (OFF = no music bed in the
  /// export). No fake controls: A1/V1/TC get the eye only,
  /// because no real per-lane lever exists for them.
  Widget _laneRow(
    String label,
    Widget child, {
    String? laneId,
    bool? musicMuted,
    VoidCallback? onToggleMusic,
  }) {
    final hidden = laneId != null && _nsLaneHidden.contains(laneId);
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF8A919C),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (laneId != null)
                IconButton(
                  key: Key('nsLaneEye-$laneId'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  constraints:
                      const BoxConstraints(minWidth: 15, minHeight: 15),
                  icon: Icon(
                    hidden ? Icons.visibility_off : Icons.visibility,
                    size: 12,
                  ),
                  color: const Color(0xFF8A919C),
                  tooltip: hidden ? 'Lane dikhayein' : 'Lane chhupayein',
                  onPressed: () => setState(() {
                    if (hidden) {
                      _nsLaneHidden.remove(laneId);
                    } else {
                      _nsLaneHidden.add(laneId);
                    }
                  }),
                ),
              if (onToggleMusic != null)
                IconButton(
                  key: const Key('nsLaneMute-a2'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  constraints:
                      const BoxConstraints(minWidth: 15, minHeight: 15),
                  icon: Icon(
                    musicMuted! ? Icons.volume_off : Icons.volume_up,
                    size: 12,
                  ),
                  color: musicMuted
                      ? const Color(0xFFE5484D)
                      : const Color(0xFF8A919C),
                  tooltip: musicMuted
                      ? 'Music is off — it will not come in the export either'
                      : 'Music is on',
                  onPressed: onToggleMusic,
                ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  /// The slim strip shown in place of a hidden lane (B10).
  Widget _nsLaneHiddenStrip() => Container(
        height: 12,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0x14FFFFFF)),
          borderRadius: BorderRadius.circular(4),
        ),
      );

  Widget _videoLane(NewsProject project, bool compact, double pps) {
    final h = compact ? 38.0 : 50.0;
    if (project.clipPaths.isEmpty) {
      return InkWell(
        onTap: () => setState(() => _activeTool = 'media'),
        child: Container(
          height: h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0x14FFFFFF)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'Add a clip from + Media',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF5E646F)),
          ),
        ),
      );
    }
    // T4 (B1): blocks sit at their cumulative-second position
    // with true duration widths — no flex, no gaps — so the
    // ruler ticks and the playhead line up with the clips
    // exactly. An unprobed clip takes the nominal 3 s the
    // scale total also uses.
    final starts = _nsClipStarts(project);
    return SizedBox(
      height: h,
      child: Stack(
        children: [
          for (var i = 0; i < project.clipPaths.length; i++)
            Positioned(
              left: starts[i] * pps,
              top: 0,
              height: h,
              width: ((_entryDurationSec(project, i) ?? 3.0) * pps)
                  .clamp(24.0, double.infinity),
              child: GestureDetector(
                // v1.15.0 G5 (B4): long-press + drag reorders the
                // clip (live pair swap in the model).
                onLongPressStart: (d) => _nsReorderStart(project, i, d),
                onLongPressMoveUpdate: (d) =>
                    _nsReorderMove(project, d, pps),
                onLongPressEnd: (_) => _nsReorderEnd(),
                onLongPressCancel: () => _nsReorderEnd(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    InkWell(
                key: Key('tlClip-$i'),
                // P1-3: tapping a clip SELECTS it (gold border)
                // and opens the Media panel, whose Trim & Split
                // controls act on this entry.
                onTap: () => setState(() {
                  _selectedClipIndex = i;
                  _activeTool = 'media';
                  _timelineTab = 'clips';
                }),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: _selectedClipIndex == i
                          ? const Color(0xFFFFC800)
                          : const Color(0x00000000),
                      width: _nsDragIndex == i ? 2.5 : 1.5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // v1.16.0 G5 (B7): a filmstrip of frames
                        // across the clip when it was generated;
                        // otherwise the single first-frame thumb.
                        if (_clipStrips[project.clipPaths[i]] != null)
                          Row(
                            children: [
                              for (final f
                                  in _clipStrips[project.clipPaths[i]]!)
                                Expanded(
                                  child: Image.file(
                                    File(f),
                                    fit: BoxFit.cover,
                                    height: h,
                                    errorBuilder: (_, _, _) =>
                                        Container(
                                            color:
                                                const Color(0xFF171B24)),
                                  ),
                                ),
                            ],
                          )
                        else if (_clipThumbs[project.clipPaths[i]] != null)
                          Image.file(
                            File(_clipThumbs[project.clipPaths[i]]!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                Container(color: const Color(0xFF171B24)),
                          )
                        else
                          Container(color: const Color(0xFF171B24)),
                        Positioned(
                          left: 5,
                          bottom: 3,
                          right: 5,
                          child: Text(
                            '${p.basename(project.clipPaths[i])}'
                            '${_entryDurationSec(project, i) != null ? ' • ${_fmtDur(_entryDurationSec(project, i)!)}' : ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9.5,
                              color: Color(0xFFD8DCE2),
                              shadows: [
                                Shadow(color: Colors.black, blurRadius: 3),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                    ),
                    // v1.15.0 G5 (B3): drag-trim handles on the
                    // SELECTED clip's two edges (file seconds ==
                    // timeline seconds inside the used range).
                    if (_selectedClipIndex == i) ...[
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: 16,
                        child: GestureDetector(
                          key: Key('nsTrimL-$i'),
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragUpdate: (d) => _nsDragTrim(
                              project, i, true, d.delta.dx, pps),
                          child: Container(
                            color: const Color(0x40FFC800),
                            child: const Icon(Icons.drag_indicator,
                                size: 11, color: Color(0xFFFFC800)),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: 16,
                        child: GestureDetector(
                          key: Key('nsTrimR-$i'),
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragUpdate: (d) => _nsDragTrim(
                              project, i, false, d.delta.dx, pps),
                          child: Container(
                            color: const Color(0x40FFC800),
                            child: const Icon(Icons.drag_indicator,
                                size: 11, color: Color(0xFFFFC800)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// P1-2: the subtitle line active at the transport position
  /// (the preview's own player position — the Maker's subtitles
  /// are reel-timeline based and the transport drives the first
  /// clip, so while it plays this tracks the reel position).
  /// Null when the project has no subtitles or none is active.
  SubtitleLine? _activeCaptionLine(NewsProject project) {
    if (project.subtitles.isEmpty) return null;
    // T4: follows the EFFECTIVE position, so scrubbing the
    // playhead also previews the caption at that point.
    final pos = _effectivePosSec;
    for (final line in project.subtitles) {
      if (pos >= line.startSec && pos < line.endSec) return line;
    }
    return null;
  }

  Widget _buildBody(ChannelPreset preset, NewsProject project) {
    final previewPreset = _previewPreset();
    // v1.5.2 (coherence): the label comes from the ONE derivation
    // (kind + variant) — never from the kind alone.
    final templateLabel = _templateLabel(project);
    // v1.5.1 (#51/#52): the resolved preview inputs — a Text
    // Style's font ref wins over the surface's own font choice.
    final headlineStyle =
        _libraryById(_textStyles, project.headlineStyleId);
    final tickerStyle = _libraryById(_textStyles, project.tickerStyleId);
    final headlineFamily = newsFontFamilyForId(
      headlineStyle?.recipe.styleFontRef ?? project.headlineFontId,
    );
    final tickerFamily = newsFontFamilyForId(
      tickerStyle?.recipe.styleFontRef ?? project.tickerFontId,
    );
    final headlineShadows = headlineStyle == null
        ? null
        : libraryStyleShadows(headlineStyle.recipe);
    final tickerShadows = tickerStyle == null
        ? null
        : libraryStyleShadows(tickerStyle.recipe);
    final effectItem = _libraryById(_effects, project.effectId);
    final gradeEffect = (effectItem != null &&
            effectItem.recipe.kind == 'grade' &&
            !effectItem.recipe.grade.isIdentity)
        ? effectItem.recipe.grade
        : null;
    final reporterFamily = newsFontFamilyForId(project.reporterFontId);
    // v1.5.2 (fixes #58/#60/#64 + the same-interface law): the
    // Maker now uses the EDITORS' screen system, exactly like the
    // Photo Editor — a one-line header strip, a big preview region
    // (the preview takes 60% of the screen height, the user's
    // standing rule, capped by the region the layout leaves), and
    // ONE bottom zone: the tool line, or the open tool's panel in
    // the shared scrollable host. The old quick-row buttons
    // (Add Video / Templates / Ribbons) are gone — every one of
    // those actions lives in its tool (Media / Template /
    // Ribbons), the editors' single-bottom-line pattern. The
    // bottom info card (#64) is deleted.
    return Column(
      key: const Key('makerList'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _projectBar(preset, project, templateLabel),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0E1118),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x1FFFFFFF)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: LayoutBuilder(
            builder: (context, constraints) {
              // Build 12 (point #14b): the EXPANDED hero
              // preview — the canvas takes the WHOLE region the
              // layout leaves it (the old 60%-of-screen cap is
              // gone for News Studio), still width-fitted so
              // the full template — ribbons, ticker, logo —
              // is always fully visible, never cropped.
              var previewH = constraints.maxHeight;
              if (previewH * 9 / 16 > constraints.maxWidth) {
                previewH = constraints.maxWidth * 16 / 9;
              }
              return Container(
                color: Colors.black,
                alignment: Alignment.center,
                child: _withElementGestures(
                  project,
                  previewPreset,
                  height: previewH,
                  project.templateKind == 'nigraanFinal'
                      ? project.clipPaths.isEmpty
                          ? NigraanFinalPreview(
                              preset: previewPreset,
                              fontReady: _fontReady,
                              height: previewH,
                              elementOverrides: project.elementOverrides,
                              tickerLabel: project.tickerLabel.isEmpty
                                  ? null
                                  : project.tickerLabel,
                              headlineFontFamily: headlineFamily,
                              tickerFontFamily: tickerFamily,
                              headlineTextColor:
                                  headlineStyle?.recipe.styleColor,
                              tickerTextColor:
                                  tickerStyle?.recipe.styleColor,
                              tickerLabelColor:
                                  tickerStyle?.recipe.styleLabelBackground,
                              headlineShadows: headlineShadows,
                              tickerShadows: tickerShadows,
                              reporterPhotoPath: project.reporterPhotoPath,
                              reporterName: project.reporterName,
                              reporterFontFamily: reporterFamily,
                              logoRotate: previewPreset.logoRotate,
                            )
                          // The user's own video/photo sits in the
                          // template's main area — the same
                          // composite the export renders.
                          : TemplateMediaPreview(
                              key: const Key('makerMediaPreview'),
                              onPlayerController: _onTransportController,
                              preset: previewPreset,
                              mediaPaths: project.clipPaths,
                              fontReady: _fontReady,
                              height: previewH,
                              elementOverrides: project.elementOverrides,
                              tickerLabel: project.tickerLabel.isEmpty
                                  ? null
                                  : project.tickerLabel,
                              headlineFontFamily: headlineFamily,
                              tickerFontFamily: tickerFamily,
                              headlineTextColor:
                                  headlineStyle?.recipe.styleColor,
                              tickerTextColor:
                                  tickerStyle?.recipe.styleColor,
                              tickerLabelColor:
                                  tickerStyle?.recipe.styleLabelBackground,
                              headlineShadows: headlineShadows,
                              tickerShadows: tickerShadows,
                              reporterPhotoPath: project.reporterPhotoPath,
                              reporterName: project.reporterName,
                              reporterFontFamily: reporterFamily,
                              logoRotate: previewPreset.logoRotate,
                              gradeEffect: gradeEffect,
                            )
                      : project.templateKind == 'breaking'
                          ? BreakingTemplatePreview(
                              key: const Key('makerBreakingPreview'),
                              template: BreakingTemplate.fromProject(
                                project,
                                previewPreset,
                                tickerText: previewPreset.topRibbon.text,
                              ),
                              preset: previewPreset,
                              fontReady: _fontReady,
                              height: previewH,
                            )
                          : ClassicPreview(
                              key: const Key('makerClassicPreview'),
                              preset: previewPreset,
                              fontReady: _fontReady,
                              height: previewH,
                            ),
                ),
              );
            },
                    ),
                  ),
                  // P1-2 (tools-fix wave): the CAPTIONS layer of
                  // the composed preview. Before this, the caption
                  // style/position/size choices were invisible in
                  // the Maker — the fields were read only by the
                  // export's ASS builder, so the panel was blind.
                  // The overlay renders the active subtitle line
                  // with the SAME style values the export uses
                  // (the Caption Studio's exact argument pattern),
                  // positioned on the same centred 9:16 box the
                  // preview widgets render into.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final line = _activeCaptionLine(project);
                          if (line == null) {
                            return const SizedBox.shrink();
                          }
                          var boxH = constraints.maxHeight;
                          if (boxH * 9 / 16 > constraints.maxWidth) {
                            boxH = constraints.maxWidth * 16 / 9;
                          }
                          final boxW = boxH * 9 / 16;
                          final style = StudioCaptionStyles.byId(
                            project.captionStyleId,
                          );
                          return Center(
                            child: SizedBox(
                              key: const Key('makerCaptionOverlay'),
                              width: boxW,
                              height: boxH,
                              child: Align(
                                alignment: switch (project.captionPosition) {
                                  CaptionPosition.top =>
                                    Alignment.topCenter,
                                  CaptionPosition.middle =>
                                    Alignment.center,
                                  CaptionPosition.bottom =>
                                    Alignment.bottomCenter,
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: StyledCaptionPreview(
                                    line: line,
                                    style: style,
                                    positionSec: _transportPosition
                                            .inMilliseconds /
                                        1000.0,
                                    highlightColor:
                                        project.captionHighlight,
                                    fontFamily: CaptionFonts.byId(
                                      project.captionFontId,
                                    ).family,
                                    fontSizePx: style.fontSizePx *
                                        StudioCaptionStyles.sizeScale(
                                          project.captionSize,
                                        ) *
                                        (boxW / 360).clamp(0.6, 1.2),
                                    showBackground:
                                        project.captionBackground,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  // v1.13.0 (G4): safe-area guides over the
                  // preview frame — the Video Editor's
                  // StageGridPainter reused as-is (thirds +
                  // 90% action-safe + 80% title-safe), fitted to
                  // the same centred 9:16 box the preview renders
                  // into (the captions overlay's fit). Painted
                  // ONLY here in the preview stack; the export
                  // renders from the project/preset via ffmpeg
                  // and never receives this flag.
                  if (_nsShowGuides)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            var boxH = constraints.maxHeight;
                            if (boxH * 9 / 16 > constraints.maxWidth) {
                              boxH = constraints.maxWidth * 16 / 9;
                            }
                            final boxW = boxH * 9 / 16;
                            return Center(
                              child: SizedBox(
                                key: const Key('nsSafeGuides'),
                                width: boxW,
                                height: boxH,
                                child: const CustomPaint(
                                  painter: StageGridPainter(),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  // v1.13.0 (G4): the guides toggle — the Video
                  // Editor's stage-corner pattern (grid_on /
                  // grid_off, gold while on), top-right corner;
                  // the top-left belongs to the PREVIEW chip.
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton(
                      key: const Key('nsGuidesToggle'),
                      tooltip: 'Grid / safe zones',
                      icon: Icon(
                        _nsShowGuides ? Icons.grid_on : Icons.grid_off,
                        color: _nsShowGuides
                            ? const Color(0xFFF5C542)
                            : Colors.white54,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _nsShowGuides = !_nsShowGuides),
                    ),
                  ),
                  // Stage chips (display only, gesture-transparent):
                  // the live-preview dot + the active template.
                  Positioned(
                    left: 10,
                    top: 8,
                    child: IgnorePointer(
                      child: _stageChip('PREVIEW', goldDot: true),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    bottom: 8,
                    child: IgnorePointer(
                      child: _stageChip(templateLabel.toUpperCase()),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // P0-4 (Point #27 — the user's layout correction,
        // amending Build 13's point #19 arrangement): the zone
        // under the preview has ONE fixed height in EVERY state
        // ([_lowerZoneHeight] — the panel host's own height), so
        // the preview above it is the SAME BIG SIZE whether a
        // tool is open or not, and the composed preview widget
        // stays mounted + live while any panel is open. States:
        //   - no tool: the timeline + summary inspector (the
        //     timeline's home state);
        //   - tool open: the timeline COLLAPSES AWAY and only
        //     that tool's panel shows. It comes back only when
        //     the user closes the tool (the panel's ✓, or
        //     tapping the tool again) — never automatically.
        // The tool dock stays at the very bottom in all states.
        SizedBox(
          key: const Key('makerLowerZone'),
          height: _lowerZoneHeight,
          child: _activeTool == null
              ? SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _timelineZone(project),
                      _summaryInspector(preset, project, templateLabel),
                    ],
                  ),
                )
              : switch (_activeTool) {
                  'template' => _templatePanel(preset, project),
                  'media' => _mediaPanel(project),
                  'elements' => _panelShell(
                      'Elements',
                      [_elementsPanel(project)],
                    ),
                  'tehreer' => _tehreerPanel(project),
                  'ticker' => _tickerPanel(project),
                  'ribbons' => _ribbonsPanel(preset, project),
                  'logo' => _logoPanel(preset, project),
                  'reporter' => _reporterPanel(project),
                  'audio' => _audioPanel(project),
                  'voice' => _voicePanel(project),
                  'captions' => _captionsPanel(project),
                  'export' => _exportPanel(preset, project),
                  _ => const SizedBox.shrink(),
                },
        ),
        Container(
          decoration: const BoxDecoration(
            color: Color(0xFF12151C),
            border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
          ),
          child: _toolLine(),
        ),
      ],
    );
  }

  /// Template panel (v1.5.2, fixes #63a/#63b): the designs as ONE
  /// rail of visual cards (the shared picker rail — the same
  /// cards the Templates sheet shows), applied through the ONE
  /// coherence path [_applyTemplatePick] (kind + variant
  /// together). The Store / Library cards in the rail are the
  /// only navigation — the old separate 'Templates — Store /
  /// Library' button duplicated them and is gone.
  ///
  /// Build 5 (v1.5.7): the retired Template & Studio SCREEN's
  /// unique controls are absorbed BELOW the rail, in this same
  /// panel — channel preset selection, the Kasheeda font state +
  /// download, lower third, breaking banner, category, interview
  /// plate, PIP, chroma key and the intro/outro switches. Every
  /// one writes the working PRESET and persists it immediately
  /// (the Logo panel's rotate switch pattern), so the preview —
  /// which renders from the preset — updates live. The full
  /// preset ribbon editors live in the Ribbons panel (the one
  /// ribbon home); preset create/delete lives in the Templates
  /// Library (the rail's Library card).
  Widget _templatePanel(ChannelPreset preset, NewsProject project) {
    return _panelShell('Template', [
      templateDesignRail(
        currentKind: project.templateKind,
        currentIsFinal3: preset.finalIs3Ribbon,
        onPick: (pick) => unawaited(_applyTemplatePick(pick)),
      ),
      if (project.templateKind == 'breaking') ...[
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final variant in BreakingVariant.values) ...[
                ChoiceChip(
                  key: Key('makerBreakingVariant-${variant.id}'),
                  label: Text(variant.label),
                  selected: project.breakingVariant == variant.id,
                  onSelected: (_) {
                    setState(() => project.breakingVariant = variant.id);
                    _scheduleSave();
                  },
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
      const SizedBox(height: 16),
      _studioPresetSection(preset),
      const SizedBox(height: 16),
      _studioFontSection(),
      const SizedBox(height: 16),
      _studioLowerThirdSection(preset),
      const SizedBox(height: 16),
      _studioCategorySection(preset),
      const SizedBox(height: 16),
      _studioInterviewSection(preset),
      const SizedBox(height: 16),
      _studioPipSection(preset),
      const SizedBox(height: 16),
      _studioChromaSection(preset),
      const SizedBox(height: 16),
      _studioIntroOutroSection(preset),
    ]);
  }

  /// One preset mutation from the absorbed Studio sections:
  /// apply + repaint + persist (fire-and-forget, fail-soft store).
  void _updatePreset(void Function() change) {
    final preset = _preset;
    if (preset == null) return;
    setState(change);
    unawaited(persistPresetChange(preset));
  }

  Widget _studioSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold),
    );
  }

  /// Channel preset selection (preset management): one chip per
  /// stored preset; the working preset is the selected one.
  Widget _studioPresetSection(ChannelPreset preset) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _studioSectionTitle('Channel preset'),
        const SizedBox(height: 6),
        if (_allPresets.length <= 1)
          Text(
            '${preset.name} preset',
            style: const TextStyle(color: Colors.grey, fontSize: 12.5),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in _allPresets) ...[
                  ChoiceChip(
                    key: Key('makerPreset-${p.id}'),
                    label: Text(p.name),
                    selected: p.id == preset.id,
                    onSelected: (_) => unawaited(_switchPreset(p)),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        const SizedBox(height: 4),
        const Text(
          'To create or delete a preset: Templates above '
          'Library card se.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  /// Kasheeda font state + manual download (the retired screen's
  /// font row, same status strings).
  Widget _studioFontSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _studioSectionTitle('Urdu font'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                _fontStatus,
                key: const Key('kasheedaStatus'),
                style: const TextStyle(color: Colors.grey, fontSize: 12.5),
              ),
            ),
            if (_fontUrlAvailable && !_fontReady) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                key: const Key('kasheedaDownloadButton'),
                onPressed: () => unawaited(_downloadKasheedaFont()),
                child: const Text('Download'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// Lower third + breaking banner (preset-level, as in the
  /// retired screen).
  Widget _studioLowerThirdSection(ChannelPreset preset) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _studioSectionTitle('Lower third')),
            Switch(
              key: const Key('studioLowerThirdSwitch'),
              value: preset.showLowerThird,
              onChanged: (v) =>
                  _updatePreset(() => preset.showLowerThird = v),
            ),
          ],
        ),
        TextField(
          key: const Key('studioLowerTitleField'),
          controller: _ltTitleController,
          decoration: const InputDecoration(
            labelText: 'Title (naam / ohda)',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => _updatePreset(() => preset.lowerThirdTitle = v),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('studioLowerSubtitleField'),
          controller: _ltSubtitleController,
          decoration: const InputDecoration(
            labelText: 'Subtitle (city / detail)',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) =>
              _updatePreset(() => preset.lowerThirdSubtitle = v),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _studioSectionTitle('Breaking banner')),
            Switch(
              key: const Key('studioBreakingBannerSwitch'),
              value: preset.showBreakingBanner,
              onChanged: (v) =>
                  _updatePreset(() => preset.showBreakingBanner = v),
            ),
          ],
        ),
      ],
    );
  }

  /// Category label (preset-level).
  Widget _studioCategorySection(ChannelPreset preset) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _studioSectionTitle('Category'),
        const SizedBox(height: 6),
        TextField(
          key: const Key('studioCategoryField'),
          controller: _categoryController,
          decoration: const InputDecoration(
            hintText: 'POLITICS',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => _updatePreset(() => preset.categoryLabel = v),
        ),
      ],
    );
  }

  /// Interview name plate (preset-level).
  Widget _studioInterviewSection(ChannelPreset preset) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _studioSectionTitle('Interview plate')),
            Switch(
              key: const Key('studioInterviewSwitch'),
              value: preset.showInterviewPlate,
              onChanged: (v) =>
                  _updatePreset(() => preset.showInterviewPlate = v),
            ),
          ],
        ),
        TextField(
          key: const Key('studioInterviewNameField'),
          controller: _interviewNameController,
          decoration: const InputDecoration(
            labelText: 'Mehman ka naam',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => _updatePreset(() => preset.interviewName = v),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('studioInterviewDesigField'),
          controller: _interviewDesigController,
          decoration: const InputDecoration(
            labelText: 'Ohda (designation)',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) =>
              _updatePreset(() => preset.interviewDesignation = v),
        ),
      ],
    );
  }

  /// PIP (preset-level): enable, position, scale.
  Widget _studioPipSection(ChannelPreset preset) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _studioSectionTitle('Picture in Picture (PIP)'),
            ),
            Switch(
              key: const Key('studioPipSwitch'),
              value: preset.pipEnabled,
              onChanged: (v) => _updatePreset(() => preset.pipEnabled = v),
            ),
          ],
        ),
        if (preset.pipEnabled) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final id in ChannelPreset.pipPositionIds) ...[
                  ChoiceChip(
                    key: Key('studioPipPos-$id'),
                    label: Text(
                      ChannelPreset.pipPositionLabels[id] ?? id,
                    ),
                    selected: preset.pipPosition == id,
                    onSelected: (_) =>
                        _updatePreset(() => preset.pipPosition = id),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Size'),
              Expanded(
                child: Slider(
                  key: const Key('studioPipScaleSlider'),
                  value: preset.pipScale,
                  min: 0.15,
                  max: 0.5,
                  onChanged: (v) =>
                      _updatePreset(() => preset.pipScale = v),
                ),
              ),
              Text('${(preset.pipScale * 100).toInt()}%'),
            ],
          ),
          // P0-3 (tools-fix wave): the PIP VIDEO SOURCE. Before
          // this, the section had enable/position/scale but no
          // way to choose which video goes in the inset — the
          // switch could never show anything in the export. The
          // pick lives on the PROJECT (it is this story's inset),
          // and ReelExportService composites it at the preset's
          // position/scale.
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  _project?.pipVideoPath == null
                      ? 'PIP video: none chosen — PIP will not come '
                          'will not come'
                      : 'PIP video: '
                          '${p.basename(_project!.pipVideoPath!)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: const Key('studioPipPickButton'),
                onPressed: _pickPipVideo,
                child: const Text('Choose a video'),
              ),
              if (_project?.pipVideoPath != null)
                IconButton(
                  key: const Key('studioPipRemoveButton'),
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Remove PIP video',
                  onPressed: () {
                    setState(() => _project?.pipVideoPath = null);
                    _scheduleSave();
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// P0-3: pick the PIP inset's video (any gallery/files video).
  Future<void> _pickPipVideo() async {
    final project = _project;
    if (project == null) return;
    final picked = await FilePicker.pickFiles(type: FileType.video);
    if (picked.isEmpty || picked.first.path == null) return;
    if (!mounted) return;
    setState(() => project.pipVideoPath = picked.first.path);
    _scheduleSave();
    _showMessage('PIP video chosen — the inset will come in the export.');
  }

  /// Chroma key (preset-level): enable, background kind (the
  /// gallery kind picks an image), sensitivity.
  Widget _studioChromaSection(ChannelPreset preset) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _studioSectionTitle('Chroma Key')),
            Switch(
              key: const Key('studioChromaSwitch'),
              value: preset.chromaEnabled,
              onChanged: (v) =>
                  _updatePreset(() => preset.chromaEnabled = v),
            ),
          ],
        ),
        const Text(
          'Green screen hata ke background badlein',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        if (preset.chromaEnabled) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final kind in ChromaBackgroundKind.values) ...[
                  ChoiceChip(
                    key: Key('studioChromaBg-${kind.id}'),
                    label: Text(kind.label),
                    selected: preset.chromaBackground == kind,
                    onSelected: (_) =>
                        unawaited(_pickChromaBackground(kind)),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          if (preset.chromaBackground == ChromaBackgroundKind.gallery &&
              preset.chromaBackgroundPath != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Picked: ${preset.chromaBackgroundPath!.split('/').last}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Sensitivity'),
              Expanded(
                child: Slider(
                  key: const Key('studioChromaSensitivitySlider'),
                  value: preset.chromaSensitivity,
                  min: 0.05,
                  max: 1.0,
                  onChanged: (v) =>
                      _updatePreset(() => preset.chromaSensitivity = v),
                ),
              ),
              Text(preset.chromaSensitivity.toStringAsFixed(2)),
            ],
          ),
          const Text(
            'The visual chroma effect applies in the reel export — '
            'a chroma key export costs 50 coins '
            '(resolution ke ilawa).',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Future<void> _pickChromaBackground(ChromaBackgroundKind kind) async {
    final preset = _preset;
    if (preset == null) return;
    if (kind == ChromaBackgroundKind.gallery) {
      final picked = await FilePicker.pickFiles(type: FileType.image);
      if (picked.isEmpty || picked.first.path == null) return;
      _updatePreset(() {
        preset.chromaBackground = kind;
        preset.chromaBackgroundPath = picked.first.path;
      });
    } else {
      _updatePreset(() {
        preset.chromaBackground = kind;
        preset.chromaBackgroundPath = null;
      });
    }
  }

  /// Intro / Outro defaults (preset-level) — their ONE home
  /// (Channel Branding's duplicate switches are gone, Build 5).
  Widget _studioIntroOutroSection(ChannelPreset preset) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _studioSectionTitle('Intro / Outro'),
        SwitchListTile(
          key: const Key('studioIntroSwitch'),
          title: const Text('Intro (10s)'),
          value: preset.showIntro,
          onChanged: (v) => _updatePreset(() => preset.showIntro = v),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          key: const Key('studioOutroSwitch'),
          title: const Text('Outro (3s end card)'),
          value: preset.showOutro,
          onChanged: (v) => _updatePreset(() => preset.showOutro = v),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  /// Media panel: the clip list (the quick-row Add Video sheet
  /// edits the SAME list) + the Library Effect picker (#52 — the
  /// effect lands on the main media; a grade shows in the
  /// preview, an overlay blends in the export).
  Widget _mediaPanel(NewsProject project) {
    return _panelShell('Media', [
      // Build 12 (point #14d): ONE unified media picker — the
      // old three separate add buttons (gallery video / files /
      // photo) are one "Add media" entry that opens the
      // source sheet; every source capability is unchanged.
      ClipPickerList(
        unifiedPicker: true,
        paths: project.clipPaths,
        onChanged: (next) {
          // P1-3: setClipPaths keeps each clip's trim attached
          // through add/remove/reorder (the picker returns paths
          // only).
          setState(() {
            project.setClipPaths(next);
            if (_selectedClipIndex >= project.clipPaths.length) {
              _selectedClipIndex =
                  project.clipPaths.isEmpty ? 0 : project.clipPaths.length - 1;
            }
          });
          _scheduleSave();
          unawaited(_probeClips());
        },
      ),
      _clipEditSection(project),
      const SizedBox(height: 16),
      const Text(
        'Effect (Library)',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      _libraryPicker(
        keyPrefix: 'effectPick',
        items: _effects,
        selectedId: project.effectId,
        onChanged: (id) {
          setState(() => project.effectId = id);
          _scheduleSave();
        },
        emptyNote: 'No Library effect yet.',
      ),
    ]);
  }

  /// P1-3 (tools-fix wave): Trim & Split for the SELECTED clip
  /// entry — the News Studio had NO clip trim and NO split at
  /// all before this (the parked gap in NS-CURRENT-TOOLS). A
  /// trim only records the used range of the file (the export's
  /// normalise step honours it); a split inserts a second entry
  /// for the SAME file with the adjoining range — no media is
  /// copied or re-encoded. Both write through the project's
  /// parallel clipTrims list and autosave.
  Widget _clipEditSection(NewsProject project) {
    if (project.clipPaths.isEmpty) return const SizedBox.shrink();
    final i = _selectedClipIndex.clamp(0, project.clipPaths.length - 1);
    final path = project.clipPaths[i];
    final isPhoto = isPhotoMediaPath(path);
    final fileDur = _clipDurations[path];
    final trim = project.trimAt(i);
    final effDur = fileDur == null ? null : trim.effectiveDuration(fileDur);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text(
          'Clip edit — Trim / Split',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var c = 0; c < project.clipPaths.length; c++) ...[
                ChoiceChip(
                  key: Key('nsClipChip-$c'),
                  label: Text('Clip ${c + 1}'),
                  selected: c == i,
                  onSelected: (_) =>
                      setState(() => _selectedClipIndex = c),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        Text(
          p.basename(path),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 6),
        if (isPhoto)
          const Text(
            'A photo clip has no trim/split — a photo always '
            'a 5-second segment is made.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          )
        else if (fileDur == null)
          const Text(
            'The clip\'s duration is not known yet — wait a moment '
            'wait and open the panel again.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          )
        else ...[
          Row(
            children: [
              const SizedBox(width: 52, child: Text('Start')),
              Expanded(
                child: Slider(
                  key: const Key('nsClipTrimStartSlider'),
                  value: trim.startSec.clamp(0.0, fileDur - 0.2),
                  min: 0,
                  max: fileDur - 0.2,
                  onChanged: (v) {
                    var start = v;
                    final end = trim.endSec;
                    if (end != null && start > end - 0.2) {
                      start = end - 0.2;
                    }
                    _setNsClipTrim(
                      project,
                      i,
                      trim.copyWith(startSec: start),
                    );
                  },
                ),
              ),
              Text(_fmtDur(trim.startSec)),
            ],
          ),
          Row(
            children: [
              const SizedBox(width: 52, child: Text('End')),
              Expanded(
                child: Slider(
                  key: const Key('nsClipTrimEndSlider'),
                  value: (trim.endSec ?? fileDur)
                      .clamp(trim.startSec + 0.2, fileDur),
                  min: 0.2,
                  max: fileDur,
                  onChanged: (v) {
                    var end = v;
                    if (end < trim.startSec + 0.2) {
                      end = trim.startSec + 0.2;
                    }
                    _setNsClipTrim(
                      project,
                      i,
                      end >= fileDur
                          ? trim.copyWith(clearEnd: true)
                          : trim.copyWith(endSec: end),
                    );
                  },
                ),
              ),
              Text(_fmtDur(trim.endSec ?? fileDur)),
            ],
          ),
          Text(
            'Used portion: ${_fmtDur(trim.startSec)} — '
            '${_fmtDur(trim.endSec ?? fileDur)} '
            '(${_fmtDur(effDur ?? 0)} lamba)',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.icon(
                key: const Key('nsClipSplitButton'),
                onPressed: () => _splitNsClip(project, i),
                icon: const Icon(Icons.call_split, size: 18),
                label: const Text('Split'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: const Key('nsClipTrimResetButton'),
                onPressed: () {
                  _setNsClipTrim(project, i, ClipTrim.full);
                  setState(
                    () => _clipEditStatus = 'Trim reset — poora clip '
                        'will be used.',
                  );
                },
                child: const Text('Trim reset'),
              ),
            ],
          ),
        ],
        if (_clipEditStatus.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            _clipEditStatus,
            style: const TextStyle(
              color: Color(0xFFFFC800),
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  /// Cumulative start seconds of the timeline clips (the same
  /// math [_videoLane] draws with: an unprobed clip counts the
  /// nominal 3 s). Computed fresh from the model so the drag
  /// handlers never read a stale build's geometry.
  List<double> _nsClipStarts(NewsProject project) {
    final starts = <double>[];
    var acc = 0.0;
    for (var i = 0; i < project.clipPaths.length; i++) {
      starts.add(acc);
      acc += _entryDurationSec(project, i) ?? 3.0;
    }
    return starts;
  }

  /// B3 (v1.15.0 G5): drag-trim one edge of clip [i] by [dxPx]
  /// screen pixels at [pps] — the math is the pure
  /// [nsDragTrimmed]; this only wires it to the probed duration
  /// and the project. Without a probed file duration there is
  /// nothing honest to clamp against, so the handles do nothing
  /// (the Media panel's sliders need it too).
  void _nsDragTrim(
      NewsProject project, int i, bool leftEdge, double dxPx, double pps) {
    if (pps <= 0) return;
    final fileDur = _clipDurations[project.clipPaths[i]];
    if (fileDur == null) return;
    final trim = project.trimAt(i);
    final next = nsDragTrimmed(trim, fileDur, leftEdge, dxPx / pps);
    if (next.startSec == trim.startSec && next.endSec == trim.endSec) {
      return;
    }
    _setNsClipTrim(project, i, next);
  }

  /// B4 (v1.15.0 G5): long-press reorder — drag start.
  void _nsReorderStart(NewsProject project, int i, LongPressStartDetails d) {
    setState(() {
      _nsDragIndex = i;
      _selectedClipIndex = i;
      _nsDragRefGlobalX = d.globalPosition.dx;
      _nsDragRefStartSec = _nsClipStarts(project)[i];
    });
  }

  /// B4: the live swap — when the dragged clip's proposed centre
  /// crosses into a neighbour's span, the (path, trim) PAIR moves
  /// in the model immediately. Pairs move together, NOT via
  /// setClipPaths: its occurrence matching would mis-attach the
  /// trims of split halves (same path, different trims).
  void _nsReorderMove(
      NewsProject project, LongPressMoveUpdateDetails d, double pps) {
    final cur = _nsDragIndex;
    if (cur == null || pps <= 0) return;
    final starts = _nsClipStarts(project);
    if (cur >= starts.length || starts.isEmpty) return;
    final effs = [
      for (var j = 0; j < project.clipPaths.length; j++)
        _entryDurationSec(project, j) ?? 3.0
    ];
    final centre = _nsDragRefStartSec +
        (d.globalPosition.dx - _nsDragRefGlobalX) / pps +
        effs[cur] / 2;
    var target = cur;
    for (var j = 0; j < starts.length; j++) {
      if (centre >= starts[j] && centre < starts[j] + effs[j]) {
        target = j;
        break;
      }
    }
    if (centre < 0) target = 0;
    if (centre >= starts.last + effs.last) target = starts.length - 1;
    if (target == cur) return;
    setState(() {
      final paths = List<String>.from(project.clipPaths);
      final trims = List<ClipTrim>.from(project.clipTrims);
      final p = paths.removeAt(cur);
      final t = trims.removeAt(cur);
      paths.insert(target, p);
      trims.insert(target, t);
      project.clipPaths = paths;
      project.clipTrims = trims;
      _selectedClipIndex = target;
      _nsDragIndex = target;
      _nsDragRefStartSec = _nsClipStarts(project)[target];
      _nsDragRefGlobalX = d.globalPosition.dx;
    });
  }

  /// B4: drag end — persist the new order.
  void _nsReorderEnd() {
    if (_nsDragIndex == null) return;
    setState(() => _nsDragIndex = null);
    _scheduleSave();
  }

  void _setNsClipTrim(NewsProject project, int i, ClipTrim trim) {
    setState(() {
      final trims = List<ClipTrim>.from(project.clipTrims);
      if (i >= 0 && i < trims.length) {
        trims[i] = trim;
        project.clipTrims = trims;
      }
    });
    _scheduleSave();
  }

  /// Split entry [i] at the timeline playhead's position inside
  /// it (the Maker's transport position is the global timeline
  /// position); when the playhead is not inside this entry, the
  /// split falls back to its midpoint AND says so — never a
  /// silent different cut (the VE Split lesson).
  void _splitNsClip(NewsProject project, int i) {
    final fileDur = _clipDurations[project.clipPaths[i]];
    if (fileDur == null) {
      setState(
        () => _clipEditStatus = 'The clip\'s duration is not known '
            'no — the split could not happen. Wait a moment and again '
            'try again.',
      );
      return;
    }
    final trim = project.trimAt(i);
    final effDur = trim.effectiveDuration(fileDur);
    if (effDur < 0.3) {
      setState(
        () => _clipEditStatus = 'The clip\'s used portion is very '
            'is small (${_fmtDur(effDur)}) — the split cannot '
            'happen.',
      );
      return;
    }
    var startOffset = 0.0;
    for (var j = 0; j < i; j++) {
      startOffset += _entryDurationSec(project, j) ?? 0;
    }
    // T4: split follows the EFFECTIVE position — scrub the
    // playhead onto a later clip and Split cuts THERE (before,
    // the raw transport position only ever pointed into clip 1,
    // so later clips always split at their midpoint).
    final globalPos = _effectivePosSec;
    final inside = globalPos - startOffset;
    final atPlayhead = inside > 0.15 && inside < effDur - 0.15;
    final cut = trim.startSec + (atPlayhead ? inside : effDur / 2);
    final paths = List<String>.from(project.clipPaths);
    final trims = List<ClipTrim>.from(project.clipTrims);
    paths.insert(i + 1, paths[i]);
    trims[i] = ClipTrim(startSec: trim.startSec, endSec: cut);
    trims.insert(i + 1, ClipTrim(startSec: cut, endSec: trim.endSec));
    setState(() {
      project.clipPaths = paths;
      project.clipTrims = trims;
      _selectedClipIndex = i + 1;
      _clipEditStatus = atPlayhead
          ? 'Split done — cut at the playhead, 2 clips created.'
          : 'Split done — the playhead was not inside this clip, '
              'so it was cut from the middle (midpoint).';
    });
    _scheduleSave();
  }

  /// Tehreer panel: the script field + headline font (#51) +
  /// headline Text Style (#52).
  Widget _tehreerPanel(NewsProject project) {
    final tehreer = _tehreerController.text;
    final langLabel =
        GeminiVoiceService.detectLang(tehreer) == 'ur' ? 'Urdu' : 'English';
    return _panelShell('Tehreer', [
      Align(
        alignment: Alignment.centerRight,
        child: Text(
          '$langLabel • ${countWords(tehreer)} alfaz',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        key: const Key('tehreerField'),
        controller: _tehreerController,
        maxLines: 5,
        minLines: 5,
        textAlign: TextAlign.right,
        textDirection: TextDirection.rtl,
        decoration: const InputDecoration(
          hintText: 'Write or paste the script here…',
          border: OutlineInputBorder(),
        ),
        // P2: debounced rebuild (see _textFieldChanged) — the
        // whole Maker no longer rebuilds on every keystroke.
        onChanged: (_) => _textFieldChanged(),
      ),
      const SizedBox(height: 14),
      const Text(
        'Headline font',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      NewsFontPicker(
        selectedId: project.headlineFontId,
        onChanged: (id) {
          setState(() => project.headlineFontId = id);
          _warmFont(id);
          _scheduleSave();
        },
      ),
      const SizedBox(height: 14),
      const Text(
        'Headline Text Style (Library)',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      _libraryPicker(
        keyPrefix: 'headlineStylePick',
        items: _textStyles,
        selectedId: project.headlineStyleId,
        onChanged: (id) {
          setState(() => project.headlineStyleId = id);
          _scheduleSave();
        },
        emptyNote: 'No Library text style yet.',
      ),
    ]);
  }

  /// Ticker panel (v1.5.2, fix #65): BOTH tickers get their own
  /// clearly labelled text box — the Urdu ticker (top ribbon)
  /// and the English ticker (bottom ribbon) — then the controls
  /// both tickers share: side label (chip), scroll direction,
  /// font and Text Style. (Speed is NOT here: the parity export
  /// renders its fixed design speed and the preset ribbons'
  /// speed lives in the Ribbons panel's preset editors — a
  /// project-level speed slider would promise what the export
  /// does not do.)
  Widget _tickerPanel(NewsProject project) {
    return _panelShell('Ticker', [
      const Text(
        'Urdu ticker',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('tickerField'),
              controller: _tickerController,
              decoration: const InputDecoration(
                hintText: 'Paste Urdu ticker text…',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _textFieldChanged(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('pasteTickerButton'),
            onPressed: _pasteTicker,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFC800),
              foregroundColor: Colors.black,
            ),
            child: const Text('Paste'),
          ),
        ],
      ),
      const SizedBox(height: 14),
      const Text(
        'English ticker',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('englishTickerField'),
              controller: _englishTickerController,
              decoration: const InputDecoration(
                hintText: 'Paste English ticker text…',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _textFieldChanged(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('pasteEnglishTickerButton'),
            onPressed: _pasteEnglishTicker,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFC800),
              foregroundColor: Colors.black,
            ),
            child: const Text('Paste'),
          ),
        ],
      ),
      const SizedBox(height: 14),
      const Text(
        'Side label (chip) — dono tickers',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      TextField(
        key: const Key('tickerLabelField'),
        controller: _tickerLabelController,
        decoration: const InputDecoration(
          hintText: 'BREAKING NEWS',
          border: OutlineInputBorder(),
        ),
        onChanged: (v) {
          // P2: the model write stays immediate; the screen
          // rebuild is debounced like the other text fields.
          project.tickerLabel = v.trim();
          _textFieldChanged();
        },
      ),
      const SizedBox(height: 14),
      const Text(
        'Ticker direction',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              key: const Key('tickerDirection-auto'),
              label: const Text('Auto (zuban se)'),
              selected: project.tickerDirection == null,
              onSelected: (_) {
                setState(() => project.tickerDirection = null);
                _scheduleSave();
              },
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              key: const Key('tickerDirection-rtl'),
              label: const Text('Right se Left'),
              selected: project.tickerDirection == 'rtl',
              onSelected: (_) {
                setState(() => project.tickerDirection = 'rtl');
                _scheduleSave();
              },
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              key: const Key('tickerDirection-ltr'),
              label: const Text('Left se Right'),
              selected: project.tickerDirection == 'ltr',
              onSelected: (_) {
                setState(() => project.tickerDirection = 'ltr');
                _scheduleSave();
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        'Ticker font — dono tickers',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      NewsFontPicker(
        selectedId: project.tickerFontId,
        onChanged: (id) {
          setState(() => project.tickerFontId = id);
          _warmFont(id);
          _scheduleSave();
        },
      ),
      const SizedBox(height: 14),
      const Text(
        'Ticker Text Style (Library)',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      _libraryPicker(
        keyPrefix: 'tickerStylePick',
        items: _textStyles,
        selectedId: project.tickerStyleId,
        onChanged: (id) {
          setState(() => project.tickerStyleId = id);
          _scheduleSave();
        },
        emptyNote: 'No Library text style yet.',
      ),
      // Build 13 (point #19): the ticker's motion + geometry
      // controls, in this same linear panel — project-level
      // SPEED (new: it did not exist before), LOOP on/off, the
      // text SIZE + POSITION (the ticker element's override —
      // the same one the parity export consumes), and the
      // bottom band's COLOUR (the preset's english ribbon; the
      // Ribbons panel remains the full ribbon editor).
      const SizedBox(height: 14),
      const Text(
        'Ticker speed',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      _elementSlider(
        label: 'Speed (${project.tickerSpeed.toStringAsFixed(2)}x)',
        value: project.tickerSpeed,
        min: 0.25,
        max: 3.0,
        onChanged: (v) {
          setState(() => project.tickerSpeed = v);
          _scheduleSave();
        },
      ),
      SwitchListTile(
        key: const Key('tickerLoopSwitch'),
        title: const Text('Ticker loop (keeps rotating continuously)'),
        subtitle: const Text('Off = the ticker plays once and stops'),
        value: project.tickerLoop,
        onChanged: (v) {
          setState(() => project.tickerLoop = v);
          _scheduleSave();
        },
      ),
      const Text(
        'Ticker size / position',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      _elementSlider(
        label: 'Text size',
        value: _elementOv(project, NewsElement.tickerText).scale,
        min: 0.5,
        max: 2.0,
        onChanged: (v) => _setElementOverride(
          NewsElement.tickerText,
          _elementOv(project, NewsElement.tickerText).copyWith(scale: v),
        ),
      ),
      _elementSlider(
        label: 'Left / Right',
        value: _elementOv(project, NewsElement.tickerText).dx,
        min: -0.3,
        max: 0.3,
        onChanged: (v) => _setElementOverride(
          NewsElement.tickerText,
          _elementOv(project, NewsElement.tickerText).copyWith(dx: v),
        ),
      ),
      _elementSlider(
        label: 'Up / Down',
        value: _elementOv(project, NewsElement.tickerText).dy,
        min: -0.3,
        max: 0.3,
        onChanged: (v) => _setElementOverride(
          NewsElement.tickerText,
          _elementOv(project, NewsElement.tickerText).copyWith(dy: v),
        ),
      ),
      const Text(
        'Ticker band colour (the bottom strip)',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final c in _ribbonSwatches)
            InkWell(
              key: Key('tickerBandSwatch-$c'),
              onTap: () {
                final preset = _preset;
                if (preset == null) return;
                _updatePreset(() => preset.englishRibbon.color = c);
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _preset?.englishRibbon.color == c
                        ? Colors.white
                        : Colors.white24,
                    width: _preset?.englishRibbon.color == c ? 3 : 1,
                  ),
                ),
                child: _preset?.englishRibbon.color == c
                    ? const Icon(Icons.check, size: 15, color: Colors.white)
                    : null,
              ),
            ),
        ],
      ),
    ]);
  }

  /// Ribbons panel (#48): per-band HEIGHT sliders — they write
  /// the band elements' override scale, which the parity
  /// geometry multiplies into the band heights (preview AND
  /// export) — plus the shared Ribbons sheet (designs/colours).
  Widget _ribbonsPanel(ChannelPreset preset, NewsProject project) {
    final isFinal3 = preset.finalIs3Ribbon &&
        project.templateKind == 'nigraanFinal';
    final bands = isFinal3
        ? const [
            (NewsElement.topRibbon, 'Top ribbon (yellow)'),
            (NewsElement.middleRibbon, 'Middle ribbon (red)'),
            (NewsElement.bottomRibbon, 'Bottom ribbon (ticker)'),
          ]
        : const [
            (NewsElement.middleRibbon, 'Urdu ribbon'),
            (NewsElement.bottomRibbon, 'English ribbon'),
          ];
    return _panelShell('Ribbons', [
      // v1.5.2 (fix #62a): the designs as visual cards in a line,
      // inline — the old sheet-opening button duplicated this
      // rail and is gone. Design picks go through the coherence
      // path (kind + variant together). The Studio card is
      // hidden here: the Studio card's destination (the Template
      // panel) is one tap away in the tool line.
      ribbonDesignRail(
        currentKind: project.templateKind,
        currentIsFinal3: preset.finalIs3Ribbon,
        includeStudio: false,
        onPick: (pick) => unawaited(_applyRibbonDesignPick(pick)),
      ),
      const SizedBox(height: 12),
      const Text(
        'Ribbon height',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      for (final (id, label) in bands)
        _elementSlider(
          label: label,
          value: _elementOv(project, id).scale,
          min: 0.6,
          max: 1.8,
          onChanged: (v) => _setElementOverride(
            id,
            _elementOv(project, id).copyWith(scale: v),
          ),
        ),
      // Build 5 (v1.5.7): the retired Template & Studio screen's
      // FULL preset ribbon editors — the ONE ribbon home (audit
      // D4): text, colour, speed, direction, size and the on/off
      // switch for each of the three channel ribbons, writing the
      // PRESET (new projects inherit them). The project's own
      // ticker texts stay in the Ticker panel — project values,
      // a different thing, each in its single home.
      const SizedBox(height: 16),
      _studioSectionTitle('Channel ribbons (preset)'),
      const SizedBox(height: 4),
      const Text(
        'Channel ke default ribbons — naye projects inhi se '
        'are created.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const SizedBox(height: 8),
      _presetRibbonEditor(
        keyId: 'top',
        title: 'Top ribbon',
        kindLabel: 'Current story',
        ribbon: preset.topRibbon,
        controller: _presetTopTextController,
      ),
      _presetRibbonEditor(
        keyId: 'urdu',
        title: 'Middle ribbon (Urdu)',
        kindLabel: 'National news (Urdu)',
        ribbon: preset.urduRibbon,
        controller: _presetUrduTextController,
      ),
      _presetRibbonEditor(
        keyId: 'english',
        title: 'Bottom ribbon (English)',
        kindLabel: 'International (English)',
        ribbon: preset.englishRibbon,
        controller: _presetEnglishTextController,
      ),
    ]);
  }

  /// The house ribbon swatches (the retired screen's set).
  static const _ribbonSwatches = <int>[
    0xFF01B0FF,
    0xFFD50000,
    0xFF3D5AFE,
    0xFFEF0017,
    0xFF1E88E5,
    0xFF00C853,
    0xFFFFC107,
    0xFFFFFFFF,
    0xFF000000,
  ];

  /// ONE preset ribbon's full editor (Build 5 absorption of the
  /// retired screen's ribbon card, minus its collapse header —
  /// the panel itself scrolls): on/off, text, colour swatches,
  /// speed, direction, font size. Every change writes the preset
  /// and persists it.
  Widget _presetRibbonEditor({
    required String keyId,
    required String title,
    required String kindLabel,
    required RibbonConfig ribbon,
    required TextEditingController controller,
  }) {
    final hex = '#${ribbon.color.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Color(ribbon.color),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$title • $kindLabel',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Switch(
                key: Key('ribbonEnabled-$keyId'),
                value: ribbon.enabled,
                onChanged: (v) => _updatePreset(() => ribbon.enabled = v),
              ),
            ],
          ),
          TextField(
            key: Key('ribbonText-$keyId'),
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Text',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => _updatePreset(() => ribbon.text = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Color'),
              const SizedBox(width: 10),
              Text(hex, style: const TextStyle(color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _ribbonSwatches.map((c) {
              final selected = ribbon.color == c;
              return InkWell(
                key: Key('swatch-$keyId-$c'),
                onTap: () => _updatePreset(() => ribbon.color = c),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.white : Colors.white24,
                      width: selected ? 3 : 1,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 15, color: Colors.white)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Speed'),
              Expanded(
                child: Slider(
                  key: Key('ribbonSpeed-$keyId'),
                  value: ribbon.speed,
                  min: 0.25,
                  max: 2.5,
                  divisions: 45,
                  onChanged: (v) => _updatePreset(() => ribbon.speed = v),
                ),
              ),
              Text('${ribbon.speed.toStringAsFixed(1)}×'),
            ],
          ),
          Row(
            children: [
              const Text('Direction'),
              const SizedBox(width: 10),
              Expanded(
                child: SegmentedButton<RibbonDirection>(
                  segments: const [
                    ButtonSegment(
                      value: RibbonDirection.rtl,
                      label: Text('RTL'),
                      icon: Icon(Icons.arrow_back, size: 16),
                    ),
                    ButtonSegment(
                      value: RibbonDirection.ltr,
                      label: Text('LTR'),
                      icon: Icon(Icons.arrow_forward, size: 16),
                    ),
                  ],
                  selected: {ribbon.direction},
                  onSelectionChanged: (selected) =>
                      _updatePreset(() => ribbon.direction = selected.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('Size'),
              const SizedBox(width: 8),
              IconButton(
                key: Key('sizeDown-$keyId'),
                icon: const Icon(Icons.remove, size: 18),
                onPressed: () => _updatePreset(
                  () => ribbon.fontSize =
                      (ribbon.fontSize - 1).clamp(10, 40).toDouble(),
                ),
              ),
              Text(
                ribbon.fontSize.toInt().toString(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              IconButton(
                key: Key('sizeUp-$keyId'),
                icon: const Icon(Icons.add, size: 18),
                onPressed: () => _updatePreset(
                  () => ribbon.fontSize =
                      (ribbon.fontSize + 1).clamp(10, 40).toDouble(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Logo panel (#47; v1.5.2 fix #68a): the REPLACE action is
  /// the FIRST thing in the panel — logo thumbnail + the
  /// pick/replace button at the very top, impossible to miss —
  /// then remove, the rotate switch, and the position/size
  /// sliders. (On the user's phone the button sat under a long
  /// status paragraph and he could not find it.)
  Widget _logoPanel(ChannelPreset preset, NewsProject project) {
    final logoOv = _elementOv(project, NewsElement.logo);
    final isVideo = preset.logoMediaKind == 'video';
    final logoPath = preset.logoPath;
    final hasLogo =
        !isVideo && logoPath != null && File(logoPath).existsSync();
    final hasVideo = isVideo &&
        preset.logoVideoPath != null &&
        File(preset.logoVideoPath!).existsSync();
    final stillPath = preset.logoVideoStillPath;
    final hasStill = stillPath != null && File(stillPath).existsSync();
    final String statusText;
    if (isVideo) {
      if (_logoVideoBusy) {
        statusText = _logoVideoStatus;
      } else if (!hasVideo) {
        statusText =
            'Logo video (MP4 / MOV) — the solid background itself '
            'will be detected and removed.';
      } else if (preset.logoVideoKeyColor != null) {
        statusText =
            'Background removed — colour '
            '${LogoKeyService.displayHex(preset.logoVideoKeyColor!)} '
            'was auto-detected; in the preview the keyed logo runs '
            'is in progress.';
      } else {
        statusText =
            'No solid background found — the video without key '
            'will be applied.';
      }
    } else {
      statusText = hasLogo
          ? '3D Cube logo — this picture becomes a cube and '
              'full 360° ghoomegi.'
          : 'Default channel logo (cube) — give your own picture '
              'to wohi cube banegi.';
    }
    return _panelShell('Logo', [
      // Build 12 (points #12/#13): the logo SOURCE — a picked
      // image becomes the rotating 3D CUBE logo; a picked
      // VIDEO is auto-keyed (background removed).
      SegmentedButton<String>(
        key: const Key('logoSourceToggle'),
        segments: const [
          ButtonSegment(
            value: 'image',
            icon: Icon(Icons.view_in_ar_outlined, size: 17),
            label: Text('3D Cube'),
          ),
          ButtonSegment(
            value: 'video',
            icon: Icon(Icons.movie_outlined, size: 17),
            label: Text('Video logo'),
          ),
        ],
        selected: {isVideo ? 'video' : 'image'},
        // The editors' shared pattern (_updatePreset):
        // synchronous setState, persistence unawaited — the
        // toggle responds instantly.
        onSelectionChanged: (s) =>
            _updatePreset(() => preset.logoMediaKind = s.first),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF181828),
              borderRadius: BorderRadius.circular(8),
            ),
            child: isVideo
                ? (hasStill
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(stillPath),
                          fit: BoxFit.contain,
                        ),
                      )
                    : const Icon(
                        Icons.movie_outlined,
                        color: Colors.grey,
                      ))
                : (hasLogo
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(logoPath),
                          fit: BoxFit.contain,
                        ),
                      )
                    : const Icon(
                        Icons.image_outlined,
                        color: Colors.grey,
                      )),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isVideo)
                  FilledButton.icon(
                    key: const Key('logoVideoPickButton'),
                    onPressed: _logoVideoBusy ? null : _pickLogoVideo,
                    icon: const Icon(Icons.movie_outlined, size: 18),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _logoVideoBusy
                            ? 'Checking…'
                            : hasVideo
                                ? 'Video badlein'
                                : 'Choose logo video',
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC800),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  )
                else
                  FilledButton.icon(
                    key: const Key('logoPickButton'),
                    onPressed: _pickLogo,
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        hasLogo ? 'Logo badlein' : 'Choose logo',
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC800),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  statusText,
                  key: const Key('logoStatusText'),
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (logoPath != null || preset.logoVideoPath != null) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              key: const Key('logoRemoveButton'),
              onPressed: _removeLogo,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Remove'),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 6),
      SwitchListTile(
        key: const Key('logoRotateSwitch'),
        title: const Text('Logo rotate (full 3D rotation)'),
        value: preset.logoRotate,
        onChanged: (v) async {
          preset.logoRotate = v;
          await persistPresetChange(preset);
          if (mounted) setState(() {});
        },
      ),
      // Build 13 (point #19): the cube's own controls — VIEW
      // (Samne / Upar Se / Neeche Se + tilt), speed, direction,
      // pedestal, and a picture per face. All of them write the
      // preset, so preview and export render the same cube.
      const Text(
        'Cube View — how the cube appears',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (id, label, tilt) in const [
              ('samne', 'Front', 0.0),
              ('upar', 'From Above', 0.85),
              ('neeche', 'From Below', -0.85),
            ]) ...[
              ChoiceChip(
                key: Key('logoView-$id'),
                label: Text(label),
                selected: (preset.logoCubeTilt - tilt).abs() < 0.01,
                onSelected: (_) =>
                    _updatePreset(() => preset.logoCubeTilt = tilt),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
      _elementSlider(
        label: 'Tilt (up / down)',
        value: preset.logoCubeTilt,
        min: -1.2,
        max: 1.2,
        onChanged: (v) =>
            _updatePreset(() => preset.logoCubeTilt = v),
      ),
      _elementSlider(
        label:
            'Rotate Speed (${preset.logoCubeSpeedSec.toStringAsFixed(1)}s / round)',
        value: preset.logoCubeSpeedSec,
        min: 2,
        max: 12,
        onChanged: (v) =>
            _updatePreset(() => preset.logoCubeSpeedSec = v),
      ),
      const SizedBox(height: 4),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              key: const Key('logoDir-cw'),
              label: const Text('Clockwise'),
              selected: preset.logoCubeDirection != 'ccw',
              onSelected: (_) =>
                  _updatePreset(() => preset.logoCubeDirection = 'cw'),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              key: const Key('logoDir-ccw'),
              label: const Text('Anti-clockwise'),
              selected: preset.logoCubeDirection == 'ccw',
              onSelected: (_) =>
                  _updatePreset(() => preset.logoCubeDirection = 'ccw'),
            ),
          ],
        ),
      ),
      SwitchListTile(
        key: const Key('logoPedestalSwitch'),
        title: const Text('Pedestal (base under the cube)'),
        value: preset.logoCubePedestal,
        onChanged: (v) =>
            _updatePreset(() => preset.logoCubePedestal = v),
      ),
      const Text(
        'Cube Faces — a separate picture for each side (empty = main logo)',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final face in const [
            'front',
            'back',
            'left',
            'right',
            'top',
            'bottom',
          ])
            _logoFaceTile(preset, face),
        ],
      ),
      const SizedBox(height: 10),
      const Text(
        'Position / size',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      _elementSlider(
        label: 'Left / Right',
        value: logoOv.dx,
        min: -0.3,
        max: 0.3,
        onChanged: (v) => _setElementOverride(
          NewsElement.logo,
          logoOv.copyWith(dx: v),
        ),
      ),
      _elementSlider(
        label: 'Up / Down',
        value: logoOv.dy,
        min: -0.3,
        max: 0.3,
        onChanged: (v) => _setElementOverride(
          NewsElement.logo,
          logoOv.copyWith(dy: v),
        ),
      ),
      _elementSlider(
        label: 'Size',
        value: logoOv.scale,
        min: 0.5,
        max: 2.0,
        onChanged: (v) => _setElementOverride(
          NewsElement.logo,
          logoOv.copyWith(scale: v),
        ),
      ),
      const Divider(height: 26),
      ..._logoPartsSection(preset),
      const Divider(height: 26),
      ..._permanentLogoSection(preset),
    ]);
  }

  /// Logo Parts — ELEMENT MODEL (redesign Build 1): the parts
  /// tool inside the Logo panel, laid out by the user's
  /// interface law — a BIG fixed preview on top (tap selects
  /// a part; every control's effect shows live in it), a dock
  /// of buttons in work order (Logo → Hisay → Ghumao → Waqt →
  /// Glow → Save), and only the selected button's controls
  /// below. Working settings are session-only; the paid save
  /// (300 coins) keeps them usable for exactly 7 days
  /// (logo_parts.dart). Build 2: the Glow tab (glow layer +
  /// base plate + preview background) and the Ghumao Andaaz
  /// (Swing / Pulse).
  List<Widget> _logoPartsSection(ChannelPreset preset) {
    final parts = preset.logoParts;
    final now = DateTime.now().millisecondsSinceEpoch;
    final saveState = logoPartsSaveState(preset.logoPartsSavedAtMs, now);
    final savedCurrent = saveState == LogoPartsSaveState.active &&
        preset.logoPartsSavedJson ==
            encodeLogoPartsSave(parts, preset.logoPartsScene);
    final selIdx = _selectedPartIndex(preset);
    final selPart = selIdx >= 0 ? parts[selIdx] : null;
    return [
      const Text(
        'Logo Parts — the logo\'s own parts (elements)',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      const Text(
        'Each part = one box + the design inside it (text with its own box '
        'is one part). Each part, from its own centre (pivot), at its own speed '
        'and style (Flat / 3D) — just like professional '
        'like logos.',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      ),
      const SizedBox(height: 8),
      if (preset.logoPath == null)
        const Text(
          'Select the logo from above first — the parts will be made of that logo.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        )
      else ...[
        // --- BARA preview (sabit size; tap = hissa select) ---
        LayoutBuilder(
          builder: (context, constraints) {
            final side =
                constraints.maxWidth > 248 ? 248.0 : constraints.maxWidth;
            return Center(
              child: Container(
                key: const Key('logoPartsCombinedPreview'),
                width: side,
                height: side,
                decoration: BoxDecoration(
                  // Option 35: the preview's background —
                  // kala (default), green screen, or the
                  // checker the Glow tab paints in the Stack.
                  color: switch (_partsPreviewBg) {
                    'green' => const Color(0xFF00B140),
                    'checker' => const Color(0xFF2A2A35),
                    _ => const Color(0xFF181828),
                  },
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Stack(
                  children: [
                    if (_partsPreviewBg == 'checker')
                      const Positioned.fill(
                        child: CustomPaint(painter: _CheckerboardPainter()),
                      ),
                    if (parts.isEmpty)
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Image.file(
                            File(preset.logoPath!),
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.image_outlined,
                                    color: Colors.grey),
                          ),
                        ),
                      )
                    else if (selPart != null && _isolatePartId == selPart.id)
                      // ISOLATE (Option 9): sirf chuna hissa, akela —
                      // box ne sahi cheez pakri hai ya nahi, check.
                      Positioned.fill(
                        child: Center(
                          child: LogoPartPreview(part: selPart, size: side),
                        ),
                      )
                    else
                      LogoPartsEditorPreview(
                        parts: parts,
                        size: side,
                        selectedId: selPart?.id,
                        editable: _partsTab == 'hisay',
                        drawMode: _partsDrawMode && _partsTab == 'hisay',
                        animate: _partsPlaying,
                        scene: preset.logoPartsScene,
                        onSelect: (id) => setState(() {
                          _selectedPartId = id;
                          _partsDrawMode = false;
                        }),
                        onBoxChanged: (id, box) => setState(() {
                          preset.logoParts = [
                            for (final part in preset.logoParts)
                              part.id == id
                                  ? part.copyWith(box: box)
                                  : part,
                          ];
                        }),
                        onBoxDrawn: (box) => setState(() {
                          final part = LogoPart(
                            id: 'part${DateTime.now().millisecondsSinceEpoch}',
                            name: 'Part ${preset.logoParts.length + 1}',
                            sourcePath: preset.logoPath!,
                            box: box,
                          );
                          preset.logoParts = [...preset.logoParts, part];
                          preset.logoPartsSourcePath = preset.logoPath;
                          _selectedPartId = part.id;
                          _partsDrawMode = false;
                        }),
                      ),
                    if (selPart != null && _isolatePartId == selPart.id)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFC800),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Isolate — only this part',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: IconButton(
                        key: const Key('logoPartsPlayPause'),
                        icon: Icon(
                          _partsPlaying ? Icons.pause : Icons.play_arrow,
                          size: 18,
                        ),
                        color: Colors.white,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                        ),
                        onPressed: () =>
                            setState(() => _partsPlaying = !_partsPlaying),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        // --- Chuna hua hissa (har tab mein waisa hi) ---
        if (selPart != null)
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF181828),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: LogoPartPreview(
                  key: Key('logoPartsSelectedPreview-${selPart.id}'),
                  part: selPart,
                  size: 44,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Chosen part: ${selPart.name}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        // --- DOCK: buttons tarteeb se ---
        Row(
          key: const Key('logoPartsDock'),
          children: [
            for (final (id, icon, label) in const [
              ('logo', Icons.image_outlined, 'Logo'),
              ('hisay', Icons.call_split, 'Hisay'),
              ('ghumao', Icons.rotate_right, 'Rotate'),
              ('waqt', Icons.schedule, 'Timing'),
              ('glow', Icons.auto_awesome, 'Glow'),
              ('save', Icons.save_outlined, 'Save'),
            ]) ...[
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    key: Key('logoPartsTab-$id'),
                    avatar: Icon(icon, size: 16),
                    label: Text(label),
                    selected: _partsTab == id,
                    selectedColor: const Color(0xFFFFC800),
                    onSelected: (_) => setState(() {
                      _partsTab = id;
                      if (id != 'hisay') _partsDrawMode = false;
                    }),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // --- Sirf chune huay button ke controls ---
        switch (_partsTab) {
          'logo' => _partsLogoTab(preset),
          'ghumao' => _partsGhumaoTab(preset, selIdx),
          'waqt' => _partsWaqtTab(preset),
          'glow' => _partsGlowTab(preset),
          'save' => _partsSaveTab(preset, saveState, savedCurrent, now),
          _ => _partsHisayTab(preset),
        },
      ],
    ];
  }

  /// The selected part's index — the user's tap selection, or
  /// the first part when nothing was tapped yet (-1: no parts).
  int _selectedPartIndex(ChannelPreset preset) {
    final parts = preset.logoParts;
    if (parts.isEmpty) return -1;
    final idx = parts.indexWhere((e) => e.id == _selectedPartId);
    return idx >= 0 ? idx : 0;
  }

  void _updatePartAt(
    ChannelPreset preset,
    int i,
    LogoPart Function(LogoPart) change,
  ) {
    setState(() {
      preset.logoParts = [
        for (var j = 0; j < preset.logoParts.length; j++)
          j == i ? change(preset.logoParts[j]) : preset.logoParts[j],
      ];
    });
  }

  /// Dock tab 1 — LOGO: the master the parts look into.
  Widget _partsLogoTab(ChannelPreset preset) {
    final stale = preset.logoPartsSourcePath != null &&
        preset.logoPartsSourcePath != preset.logoPath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF181828),
                borderRadius: BorderRadius.circular(6),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(preset.logoPath!),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.broken_image_outlined, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                preset.logoParts.isEmpty
                    ? 'Parts will be made of this logo. Go to the Parts tab and '
                        'Tap Auto suggest or create a box yourself.'
                    : '${preset.logoParts.length} parts belong to this logo. '
                        'To change the logo, change it from the section above — '
                        'then the Parts will have to be created again.',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
        if (stale)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'The logo has changed — these parts belong to the old logo. '
              'Suggest again from the Parts tab.',
              style: TextStyle(fontSize: 12, color: Color(0xFFFFC800)),
            ),
          ),
        const SizedBox(height: 10),
        // --- KEYING MAZBOOTI (Option 3, Build 3): solid
        // background wale logo ki background keying kitni
        // sakht ho — Auto tajweez isi keying se hisay dhoondti
        // hai. Default wahi mazbooti hai jo hamesha thi. ---
        Text(
          'Keying strength: '
          '${(preset.logoPartsScene.keyingStrength * 100).round()}%',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        Row(
          children: [
            const Text('Light', style: TextStyle(fontSize: 11)),
            Expanded(
              child: Slider(
                key: const Key('logoKeyingStrength'),
                value: preset.logoPartsScene.keyingStrength,
                min: 0,
                max: 1,
                divisions: 20,
                onChanged: (v) => setState(
                  () => preset.logoPartsScene =
                      preset.logoPartsScene.copyWith(keyingStrength: v),
                ),
              ),
            ),
            const Text('Clearer', style: TextStyle(fontSize: 11)),
          ],
        ),
        const Text(
          'On a solid-background logo, Auto suggest first '
          'keys the background. Light = the edges stay safe '
          'stay; more = colours close to the background also '
          'are removed. Change the slider and from the Parts tab again '
          'suggest — the effect will show then.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  /// Dock tab 2 — HISAY: propose, draw, select, layer order.
  Widget _partsHisayTab(ChannelPreset preset) {
    final parts = preset.logoParts;
    final selIdx = _selectedPartIndex(preset);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('logoPartsProposeButton'),
              onPressed: _partsBusy ? null : _proposeLogoParts,
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: Text(
                _partsBusy
                    ? 'Suggesting…'
                    : parts.isEmpty
                        ? 'Suggest parts automatically'
                        : 'Suggest again',
              ),
            ),
            OutlinedButton.icon(
              key: const Key('logoPartsDrawButton'),
              onPressed: () =>
                  setState(() => _partsDrawMode = !_partsDrawMode),
              icon: const Icon(Icons.crop_free, size: 18),
              label: Text(_partsDrawMode ? 'Box banana band' : 'Create new box'),
              style: _partsDrawMode
                  ? OutlinedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC800),
                      foregroundColor: Colors.black,
                    )
                  : null,
            ),
            OutlinedButton.icon(
              key: const Key('logoPartsResetButton'),
              onPressed: parts.isEmpty || _partsBusy ? null : _resetLogoParts,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Saare saaf (Reset)'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _partsDrawMode
              ? 'Preview par ungli ghaseet kar box banayein — chorhte hi '
                  'will become a part.'
              : 'Tap a part on the preview to choose it. Drag the chosen '
                  'box to move it, drag its corner (bottom-right) '
                  'to change the size. The suggestion is only a start — '
                  'you can fix every box yourself.',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        if (parts.isEmpty)
          const Text(
            'No part yet.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          )
        else ...[
          for (var i = 0; i < parts.length; i++)
            _logoPartListRow(preset, i, selected: i == selIdx),
          const SizedBox(height: 4),
          // --- Chune huay hisay ke tools (Options 9–13) ---
          const Text(
            'Fix the chosen part:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('logoPartIsolateToggle'),
                onPressed: selIdx < 0
                    ? null
                    : () => setState(() {
                          _isolatePartId =
                              _isolatePartId == parts[selIdx].id
                                  ? null
                                  : parts[selIdx].id;
                        }),
                icon: const Icon(Icons.center_focus_strong, size: 16),
                label: Text(
                  selIdx >= 0 && _isolatePartId == parts[selIdx].id
                      ? 'Isolate band'
                      : 'Only this part (Isolate)',
                ),
                style: selIdx >= 0 && _isolatePartId == parts[selIdx].id
                    ? OutlinedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC800),
                        foregroundColor: Colors.black,
                      )
                    : null,
              ),
              OutlinedButton.icon(
                key: const Key('logoPartMergeButton'),
                onPressed:
                    parts.length < 2 ? null : () => _mergeSelectedPart(preset),
                icon: const Icon(Icons.merge_type, size: 16),
                label: const Text('Join the neighbour (Merge)'),
              ),
              OutlinedButton.icon(
                key: const Key('logoPartSplitButton'),
                onPressed: selIdx < 0 ? null : () => _splitSelectedPart(preset),
                icon: const Icon(Icons.vertical_split, size: 16),
                label: const Text('Do hisay (Split)'),
              ),
              OutlinedButton.icon(
                key: const Key('logoPartRenameButton'),
                onPressed:
                    selIdx < 0 ? null : () => _renameSelectedPart(preset),
                icon: const Icon(Icons.drive_file_rename_outline, size: 16),
                label: const Text('Naam badlein'),
              ),
              OutlinedButton.icon(
                key: const Key('logoPartDeleteButton'),
                onPressed: selIdx < 0 ? null : () => _deleteSelectedPart(preset),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete part'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Merge = the chosen part and the neighbouring box become one element. '
            'become. Split = the box is cut left-right into two parts. '
            'it is. Deleting a part does nothing to the original logo.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ],
    );
  }

  /// One part's row in the Hisay list: live preview, name,
  /// tap-to-select, layer up/down (list order = layer order —
  /// pehla sab se peeche, aakhri sab se upar).
  Widget _logoPartListRow(ChannelPreset preset, int i, {required bool selected}) {
    final part = preset.logoParts[i];
    final last = preset.logoParts.length - 1;
    return Container(
      key: Key('logoPartRow-$i'),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF12151C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? const Color(0xFFFFC800) : const Color(0x1FFFFFFF),
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            key: Key('logoPartSelect-$i'),
            onTap: () => setState(() {
              _selectedPartId = part.id;
              _partsDrawMode = false;
            }),
            child: Container(
              width: 52,
              height: 52,
              margin: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF181828),
                borderRadius: BorderRadius.circular(6),
              ),
              child: LogoPartPreview(part: part, size: 52),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedPartId = part.id;
                _partsDrawMode = false;
              }),
              child: Text(
                part.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          IconButton(
            key: Key('logoPartLayerDown-$i'),
            tooltip: 'Back (lower layer)',
            icon: const Icon(Icons.arrow_downward, size: 18),
            onPressed: i == 0
                ? null
                : () => setState(() {
                      final list = [...preset.logoParts];
                      final tmp = list[i - 1];
                      list[i - 1] = list[i];
                      list[i] = tmp;
                      preset.logoParts = list;
                    }),
          ),
          IconButton(
            key: Key('logoPartLayerUp-$i'),
            tooltip: 'Forward (upper layer)',
            icon: const Icon(Icons.arrow_upward, size: 18),
            onPressed: i == last
                ? null
                : () => setState(() {
                      final list = [...preset.logoParts];
                      final tmp = list[i + 1];
                      list[i + 1] = list[i];
                      list[i] = tmp;
                      preset.logoParts = list;
                    }),
          ),
        ],
      ),
    );
  }

  /// Dock tab 3 — GHUMAO: the selected part's own animation
  /// (on/off, Flat/3D, direction, speed) — the same controls
  /// the old per-row UI had, now acting on the selected part.
  Widget _partsGhumaoTab(ChannelPreset preset, int selIdx) {
    if (selIdx < 0) {
      return const Text(
        'No parts yet — create parts from the Parts tab first.',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    }
    final part = preset.logoParts[selIdx];
    final i = selIdx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('${part.name} — rotation')),
            Switch(
              key: Key('logoPartRotate-$i'),
              value: part.rotate,
              onChanged: (v) =>
                  _updatePartAt(preset, i, (e) => e.copyWith(rotate: v)),
            ),
          ],
        ),
        // ANDAAZ (Option 20, Build 2): Poora chakkar ya
        // Jhoolna (Swing — ghari ke pendulum ki tarah).
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const Text('Andaaz:', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              ChoiceChip(
                key: Key('logoPartMotion-$i-spin'),
                label: const Text('Poora chakkar'),
                selected: part.motionMode != kLogoPartMotionSwing,
                onSelected: (_) => _updatePartAt(
                  preset,
                  i,
                  (e) => e.copyWith(motionMode: kLogoPartMotionSpin),
                ),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                key: Key('logoPartMotion-$i-swing'),
                label: const Text('Jhoolna (Swing)'),
                selected: part.motionMode == kLogoPartMotionSwing,
                onSelected: (_) => _updatePartAt(
                  preset,
                  i,
                  (e) => e.copyWith(motionMode: kLogoPartMotionSwing),
                ),
              ),
            ],
          ),
        ),
        if (part.motionMode == kLogoPartMotionSwing) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Jhoolne ka zawiya: ${part.swingDeg.round()}°',
                style: const TextStyle(fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  key: Key('logoPartSwingDeg-$i'),
                  value: part.swingDeg,
                  min: 10,
                  max: 60,
                  divisions: 10,
                  onChanged: (v) => _updatePartAt(
                    preset,
                    i,
                    (e) => e.copyWith(swingDeg: v),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const Text('Style:', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              ChoiceChip(
                key: Key('logoPartStyle-$i-flat'),
                label: const Text('Flat'),
                selected: part.rotationStyle != kLogoPartStyle3d,
                onSelected: (_) => _updatePartAt(
                  preset,
                  i,
                  (e) => e.copyWith(rotationStyle: kLogoPartStyleFlat),
                ),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                key: Key('logoPartStyle-$i-3d'),
                label: const Text('3D'),
                selected: part.rotationStyle == kLogoPartStyle3d,
                onSelected: (_) => _updatePartAt(
                  preset,
                  i,
                  (e) => e.copyWith(rotationStyle: kLogoPartStyle3d),
                ),
              ),
              const SizedBox(width: 12),
              ChoiceChip(
                key: Key('logoPartDir-$i-cw'),
                label: const Text('Clockwise'),
                selected: part.direction != 'ccw',
                onSelected: (_) => _updatePartAt(
                  preset,
                  i,
                  (e) => e.copyWith(direction: 'cw'),
                ),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                key: Key('logoPartDir-$i-ccw'),
                label: const Text('Anti'),
                selected: part.direction == 'ccw',
                onSelected: (_) => _updatePartAt(
                  preset,
                  i,
                  (e) => e.copyWith(direction: 'ccw'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              const Text('Speed:', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              for (final s in kLogoPartSpeeds) ...[
                ChoiceChip(
                  key: Key('logoPartSpeed-$i-${s.toInt()}'),
                  label: Text('${s.toInt()}s'),
                  selected: part.speedSec == s,
                  onSelected: (_) => _updatePartAt(
                    preset,
                    i,
                    (e) => e.copyWith(speedSec: s),
                  ),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Flat = in its own plane like a wheel; 3D = shrinking from the side '
          'from the side. Each part rotates from its own centre (pivot). '
          'In Swing, Speed is the duration of one swing (forward-back = one cycle).',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 10),
        // --- PULSE (Option 23, Build 2): saans ki tarah
        // halka bara-chhota hona — ghumao se alag, ghumao
        // band ho tab bhi chalta hai. ---
        Row(
          children: [
            const Expanded(
              child: Text(
                'Pulse (bara-chhota)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            Switch(
              key: Key('logoPartPulse-$i'),
              value: part.pulseOn,
              onChanged: (v) =>
                  _updatePartAt(preset, i, (e) => e.copyWith(pulseOn: v)),
            ),
          ],
        ),
        if (part.pulseOn)
          Row(
            children: [
              Text(
                'Pulse ki taqat: ${(part.pulseStrength * 100).round()}%',
                style: const TextStyle(fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  key: Key('logoPartPulseStrength-$i'),
                  value: part.pulseStrength,
                  min: 0.1,
                  max: 1,
                  divisions: 9,
                  onChanged: (v) => _updatePartAt(
                    preset,
                    i,
                    (e) => e.copyWith(pulseStrength: v),
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 6),
        // --- PIVOT (Option 22): ghumne ka markaz ---
        const Text(
          'Ghumne ka markaz (Pivot):',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (context) {
                const boxSide = 110.0;
                final fracX = (part.pivotX - part.box.x) / part.box.w;
                final fracY = (part.pivotY - part.box.y) / part.box.h;
                void setPivot(Offset local) {
                  final fx = (local.dx / boxSide).clamp(0.0, 1.0);
                  final fy = (local.dy / boxSide).clamp(0.0, 1.0);
                  _updatePartAt(
                    preset,
                    i,
                    (e) => e.copyWith(
                      pivotDx: (fx - 0.5) * e.box.w,
                      pivotDy: (fy - 0.5) * e.box.h,
                    ),
                  );
                }

                return GestureDetector(
                  key: Key('logoPartPivotPicker-$i'),
                  onTapDown: (d) => setPivot(d.localPosition),
                  onPanUpdate: (d) => setPivot(d.localPosition),
                  child: Container(
                    width: boxSide,
                    height: boxSide,
                    decoration: BoxDecoration(
                      color: const Color(0xFF181828),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFC800)),
                    ),
                    child: Stack(
                      children: [
                        LogoPartPreview(
                          part: part.copyWith(rotate: false),
                          size: boxSide,
                        ),
                        Positioned(
                          left: fracX * boxSide - 8,
                          top: fracY * boxSide - 8,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFC800),
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.black, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Drag the gold dot and place it where the '
                    'the part rotates from — usually the centre is right. '
                    'The effect will show immediately in the big preview.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton(
                    key: Key('logoPartPivotReset-$i'),
                    onPressed: part.pivotDx == 0 && part.pivotDy == 0
                        ? null
                        : () => _updatePartAt(
                              preset,
                              i,
                              (e) => e.copyWith(pivotDx: 0, pivotDy: 0),
                            ),
                    child: const Text('Back to centre'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // --- SETTINGS COPY (Option 40, Build 3): is hisay
        // ki poori animation (ghumao, andaaz, pulse, narmi,
        // waqfa, pivot) copy karke kisi doosre hisay par
        // lagana. Box aur naam kabhi copy nahi hote — har
        // hissa apna hi rehta hai, sirf harkat aik jaisi
        // ho jati hai. ---
        const Text(
          'Settings copy:',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: Key('logoPartAnimCopy-$i'),
              onPressed: () {
                setState(() => _copiedPartAnimId = part.id);
                _showMessage(
                  '${part.name} ki animation settings copy ho gayin — '
                  'now choose the second part and apply here.',
                );
              },
              icon: const Icon(Icons.copy_all_outlined, size: 16),
              label: const Text('Copy this part\'s settings'),
            ),
            if (_copiedPartAnimId != null &&
                _copiedPartAnimId != part.id &&
                preset.logoParts.any((e) => e.id == _copiedPartAnimId))
              OutlinedButton.icon(
                key: Key('logoPartAnimPaste-$i'),
                onPressed: () {
                  final source = preset.logoParts
                      .firstWhere((e) => e.id == _copiedPartAnimId);
                  _updatePartAt(
                    preset,
                    i,
                    (e) => copyLogoPartAnimation(source, e),
                  );
                  _showMessage(
                    '${source.name} ki settings ${part.name} par lag gayin.',
                  );
                },
                icon: const Icon(Icons.content_paste, size: 16),
                label: Text(
                  'Apply the copied settings here '
                  '(${preset.logoParts.firstWhere((e) => e.id == _copiedPartAnimId).name})',
                ),
              ),
          ],
        ),
        const Text(
          'Only the movement is copied — rotation, style, speed, style-mode, '
          'pulse, easing, delay and pivot. The part\'s box and name '
          'stays its own.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  /// Dock tab 4 — WAQT: har hisay ka start waqfa (delay),
  /// Sequence (aik tap stagger) aur Sync (sab aik sath).
  Widget _partsWaqtTab(ChannelPreset preset) {
    final parts = preset.logoParts;
    if (parts.isEmpty) {
      return const Text(
        'No parts yet — create parts from the Parts tab first.',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    }
    const delays = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.5, 2.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'When each part starts its turn — this is the mark of professional '
          'logos\' identity: first the frame, then the text, then the ribbon. '
          'The delay is counted inside the 12-second loop, so '
          'the loop never breaks.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('logoPartsSequenceButton'),
              onPressed: () => setState(
                () => preset.logoParts = staggerLogoPartDelays(parts),
              ),
              icon: const Icon(Icons.format_list_numbered, size: 16),
              label: const Text('Apply sequence (0.2s gap)'),
            ),
            OutlinedButton.icon(
              key: const Key('logoPartsSyncButton'),
              onPressed: () => setState(
                () => preset.logoParts = syncLogoPartDelays(parts),
              ),
              icon: const Icon(Icons.groups, size: 16),
              label: const Text('All together (Sync)'),
            ),
          ],
        ),
        // --- GLOW KI NARMI (Option 27, Build 3): scene ki
        // narmi sirf glow ki Pulse harkat par lagti hai —
        // is liye ye row tab hi dikhti hai jab glow ki
        // harkat Pulse ho. ---
        if (preset.logoPartsScene.glowOn &&
            preset.logoPartsScene.glowMotion == kLogoGlowMotionPulse) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Glow easing:', style: TextStyle(fontSize: 12)),
              for (final (id, label) in const [
                (kLogoEasingLinear, 'Barabar'),
                (kLogoEasingSmooth, 'Narm'),
              ])
                ChoiceChip(
                  key: Key('logoGlowEasing-$id'),
                  label: Text(label),
                  selected: preset.logoPartsScene.easing == id,
                  onSelected: (_) => setState(
                    () => preset.logoPartsScene =
                        preset.logoPartsScene.copyWith(easing: id),
                  ),
                ),
            ],
          ),
          const Text(
            'How the glow\'s breathing (Pulse) should be — Even (uniform speed) '
            'or Soft (soft at the edges). The parts\' own easing below '
            'is with every part.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
        const SizedBox(height: 10),
        for (var i = 0; i < parts.length; i++) ...[
          Text(
            '${parts[i].name} — delay '
            '${parts[i].delaySec == 0 ? 'nahi (foran)' : '${parts[i].delaySec}s'}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final v in delays) ...[
                  ChoiceChip(
                    key: Key('logoPartDelay-$i-${(v * 10).round()}'),
                    label: Text(v == 0
                        ? 'Instant'
                        : v == v.roundToDouble()
                            ? '${v.toInt()}s'
                            : '${v}s'),
                    selected: parts[i].delaySec == v,
                    onSelected: (_) => _updatePartAt(
                      preset,
                      i,
                      (e) => e.copyWith(delaySec: v),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          // --- NARMI (Option 27, Build 3): is hisay ke
          // Jhoolay (Swing) aur Pulse ki harkat kaisi ho.
          // Poora chakkar hamesha aik si raftaar se ghoomta
          // hai — narmi sirf doolnay wali harkaton par hai. ---
          Row(
            children: [
              const Text('Easing:', style: TextStyle(fontSize: 12)),
              const SizedBox(width: 6),
              for (final (id, label) in const [
                (kLogoEasingLinear, 'Barabar'),
                (kLogoEasingSmooth, 'Narm'),
              ]) ...[
                ChoiceChip(
                  key: Key('logoPartEasing-$i-$id'),
                  label: Text(label),
                  selected: parts[i].easing == id,
                  onSelected: (_) => _updatePartAt(
                    preset,
                    i,
                    (e) => e.copyWith(easing: id),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              const Expanded(
                child: Text(
                  'Swing/Pulse movement — Even or Soft',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  /// Dock tab 5 — GLOW (redesign Build 2): the GENERATED
  /// glow layer behind the whole logo (Options 28–32), the
  /// base plate under the parts (Option 33) and the big
  /// preview's background (Option 35 — preview-only, export
  /// par koi asar nahi). Glow hison wale logo ke peeche
  /// lagta hai (bina hison ke logo cube par chalta hai —
  /// wahan glow nahi hota).
  Widget _partsGlowTab(ChannelPreset preset) {
    final scene = preset.logoPartsScene;
    void setScene(LogoPartsScene next) =>
        setState(() => preset.logoPartsScene = next);
    const swatches = <(String, int)>[
      ('Gold', 0xFFFFC800),
      ('Safed', 0xFFFFFFFF),
      ('Surkh', 0xFFE53935),
      ('Neela', 0xFF2979FF),
      ('Jamni', 0xFF8E24AA),
      ('Ferozi', 0xFF00BCD4),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Glow — shine behind the logo',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            Switch(
              key: const Key('logoGlowOn'),
              value: scene.glowOn,
              onChanged: (v) => setScene(scene.copyWith(glowOn: v)),
            ),
          ],
        ),
        const Text(
          'The glow is not cut from the picture — the app blurs the logo\'s shape '
          'and makes a glowing layer behind it, '
          'just like channel logos.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        if (preset.logoParts.isEmpty) ...[
          const SizedBox(height: 6),
          const Text(
            'Note: the glow applies behind a logo with parts — first '
            'Create parts from the Parts tab; then the settings here '
            'will run with them (and will also be saved with them).',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
        if (scene.glowOn) ...[
          const SizedBox(height: 8),
          const Text('Glow colour:', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  key: const Key('logoGlowColor-auto'),
                  label: const Text('Auto (logo colour)'),
                  selected: scene.glowColorArgb == null,
                  onSelected: (_) =>
                      setScene(scene.copyWith(clearGlowColor: true)),
                ),
                const SizedBox(width: 6),
                for (final (name, argb) in swatches) ...[
                  ChoiceChip(
                    key: Key('logoGlowColor-$argb'),
                    label: Text(name),
                    selected: scene.glowColorArgb == argb,
                    onSelected: (_) =>
                        setScene(scene.copyWith(glowColorArgb: argb)),
                  ),
                  const SizedBox(width: 6),
                ],
                OutlinedButton(
                  key: const Key('logoGlowColorCustom'),
                  onPressed: () async {
                    final picked = await _pickGlowColor(
                      scene.glowColorArgb ?? 0xFFFFC800,
                    );
                    if (picked != null) {
                      setScene(scene.copyWith(glowColorArgb: picked));
                    }
                  },
                  child: const Text('Your colour…'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Shadeed: ${(scene.glowIntensity * 100).round()}%',
                style: const TextStyle(fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  key: const Key('logoGlowIntensity'),
                  value: scene.glowIntensity,
                  min: 0.1,
                  max: 1,
                  divisions: 18,
                  onChanged: (v) =>
                      setScene(scene.copyWith(glowIntensity: v)),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                'Phailao: ${(scene.glowSpread * 100).round()}%',
                style: const TextStyle(fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  key: const Key('logoGlowSpread'),
                  value: scene.glowSpread,
                  min: 0,
                  max: 1,
                  divisions: 20,
                  onChanged: (v) => setScene(scene.copyWith(glowSpread: v)),
                ),
              ),
            ],
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text('Movement:', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 6),
                for (final (id, label) in const [
                  (kLogoGlowMotionStatic, 'Sabit'),
                  (kLogoGlowMotionPulse, 'Pulse (saans)'),
                  (kLogoGlowMotionSpin, 'Aahista ghoomti'),
                ]) ...[
                  ChoiceChip(
                    key: Key('logoGlowMotion-$id'),
                    label: Text(label),
                    selected: scene.glowMotion == id,
                    onSelected: (_) =>
                        setScene(scene.copyWith(glowMotion: id)),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        // --- ROSHNI KI LEHAR (Option 34, Build 3): poore
        // logo ke upar se guzarti chamak ki lehar — channel
        // idents ki pehchan. Glow se alag hai: ye lehar logo
        // ki shakal ke ANDAR hi chamakti hai. ---
        Row(
          children: [
            const Expanded(
              child: Text(
                'Light Sweep',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            Switch(
              key: const Key('logoSweepOn'),
              value: scene.sweepOn,
              onChanged: (v) => setScene(scene.copyWith(sweepOn: v)),
            ),
          ],
        ),
        const Text(
          'A wave of shine keeps passing over the whole logo '
          'stays — just like TV channel idents. '
          'The wave shines only on the logo\'s shape, not outside.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        if (scene.sweepOn)
          Row(
            children: [
              Text(
                'Wave speed: ${(scene.sweepSpeed * 100).round()}%',
                style: const TextStyle(fontSize: 12),
              ),
              Expanded(
                child: Slider(
                  key: const Key('logoSweepSpeed'),
                  value: scene.sweepSpeed,
                  min: 0,
                  max: 1,
                  divisions: 10,
                  onChanged: (v) => setScene(scene.copyWith(sweepSpeed: v)),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        const Text(
          'Bottom plate (Base):',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (id, label) in const [
                (kLogoPartsBaseCut, 'Cut-out base'),
                (kLogoPartsBaseNone, 'No base'),
                (kLogoPartsBaseGhost, 'Full logo below'),
              ]) ...[
                ChoiceChip(
                  key: Key('logoPartsBase-$id'),
                  label: Text(label),
                  selected: scene.baseMode == id,
                  onSelected: (_) => setScene(scene.copyWith(baseMode: id)),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const Text(
          'Cut-out base: when a rotating part lifts, the video behind '
          'video shows. Full logo below (ghost): the original logo stays fixed '
          'stays below and the parts rotate above it — a double effect.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        const Text(
          'Preview ka pas-manzar:',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (id, label) in const [
                ('checker', 'Checker'),
                ('green', 'Green'),
                ('black', 'Kala'),
              ]) ...[
                ChoiceChip(
                  key: Key('logoPartsPreviewBg-$id'),
                  label: Text(label),
                  selected: _partsPreviewBg == id,
                  onSelected: (_) => setState(() => _partsPreviewBg = id),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const Text(
          'This is only for the preview — no effect on the export. '
          'On Checker, the logo\'s real state (empty areas) shows clearly.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  /// The custom glow colour picker: three RGB sliders in a
  /// dialog (no new dependency). Returns the picked ARGB, or
  /// null when cancelled.
  Future<int?> _pickGlowColor(int initialArgb) {
    var r = (initialArgb >> 16) & 0xFF;
    var g = (initialArgb >> 8) & 0xFF;
    var b = initialArgb & 0xFF;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final argb = (0xFF << 24) | (r << 16) | (g << 8) | b;
          Widget channel(String label, int value, ValueChanged<int> set) =>
              Row(
                children: [
                  SizedBox(width: 28, child: Text(label)),
                  Expanded(
                    child: Slider(
                      value: value.toDouble(),
                      min: 0,
                      max: 255,
                      divisions: 255,
                      onChanged: (v) => setLocal(() => set(v.round())),
                    ),
                  ),
                  SizedBox(
                    width: 30,
                    child: Text('$value', textAlign: TextAlign.right),
                  ),
                ],
              );
          return AlertDialog(
            title: const Text('The glow\'s own colour'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Color(argb),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey),
                  ),
                ),
                const SizedBox(height: 8),
                channel('R', r, (v) => r = v),
                channel('G', g, (v) => g = v),
                channel('B', b, (v) => b = v),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, argb),
                child: const Text('This colour'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Dock tab 6 — SAVE: the paid save, exactly the flow that
  /// was here before (300 coins / 7 days, remote-priced).
  Widget _partsSaveTab(
    ChannelPreset preset,
    LogoPartsSaveState saveState,
    bool savedCurrent,
    int now,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          saveState == LogoPartsSaveState.active
              ? (savedCurrent
                  ? 'Saved — ${logoPartsSaveDaysLeft(preset.logoPartsSavedAtMs, now)} days remaining.'
                  : 'The settings have changed from the saved ones — saving again will cost ${PricingService.coinsOr(PricingService.keyLogoPartsSave, kLogoPartsSavePriceCoins)} coins.')
              : 'These settings are only for this session. If you save them, they stay safe for 7 days — after that they end and you will have to create them again.',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 6),
        OutlinedButton.icon(
          key: const Key('logoPartsSaveButton'),
          onPressed: _partsBusy || preset.logoParts.isEmpty
              ? null
              : _saveLogoParts,
          icon: const Icon(Icons.save_outlined, size: 18),
          label: Text(_logoPartsSaveButtonLabel()),
        ),
        const SizedBox(height: 12),
        // --- EXPORT SIZE (Option 39, Build 3): green-screen
        // (Permanent Logo) export ke frames kitne bare hon.
        // Default 512 wahi hai jo hamesha tha. ---
        const Text(
          'Export size (green-screen export ke frames):',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (size, label) in const [
              (kLogoPartsExportSizeDefault, '512 — Light'),
              (kLogoPartsExportSizeLarge, '1024 — Saaf'),
            ])
              ChoiceChip(
                key: Key('logoExportSize-$size'),
                label: Text(label),
                selected: preset.logoPartsScene.exportSize == size,
                onSelected: (_) => setState(
                  () => preset.logoPartsScene =
                      preset.logoPartsScene.copyWith(exportSize: size),
                ),
              ),
          ],
        ),
        const Text(
          'At 1024 the frames are clearer but the export '
          'is a bit heavy; 512 is light and fast.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  /// Auto tajweez: propose element boxes for the preset's
  /// logo. Re-proposing replaces the working parts (settings
  /// start fresh) — the same honesty the old re-split had.
  Future<void> _proposeLogoParts() async {
    final preset = _preset;
    if (preset == null || preset.logoPath == null) return;
    setState(() => _partsBusy = true);
    try {
      final parts = await LogoPartsService.proposePartsForFile(
        File(preset.logoPath!),
        keyingStrength: preset.logoPartsScene.keyingStrength,
      );
      if (!mounted) return;
      setState(() {
        preset.logoParts = parts;
        preset.logoPartsSourcePath = preset.logoPath;
        _selectedPartId = parts.isEmpty ? null : parts.first.id;
        _partsDrawMode = false;
        _partsBusy = false;
      });
      _showMessage(
        parts.isEmpty
            ? 'Parts could not be suggested — draw a box yourself with "Create new box" to make a part.'
            : '${parts.length} parts suggested — drag the boxes to fix them, then set the rotation.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _partsBusy = false);
      _showMessage('Suggestion failed: $e');
    }
  }

  /// Point #20: the Logo Parts save button label follows the
  /// remote price (price_logo_parts_save, fallback 300).
  String _logoPartsSaveButtonLabel() {
    final PriceSpec s = PricingService.specOr(
      PricingService.keyLogoPartsSave,
      fallbackCoins: kLogoPartsSavePriceCoins,
    );
    switch (s.kind) {
      case PriceKind.coins:
        return 'Save — ${s.coins} coins (7 days)';
      case PriceKind.free:
        return 'Save — FREE (7 days)';
      case PriceKind.pro:
        return 'Save — Pro only (7 days)';
      case PriceKind.ad:
        return 'Save — watch an ad (7 days)';
    }
  }

  /// Point 6: the paid save — confirm, charge ONLY on the
  /// success path, then persist the payload + timestamp
  /// (usable exactly 7 days; expiry removes it — no renewal).
  /// Point #20: the price is remote (price_logo_parts_save,
  /// fallback [kLogoPartsSavePriceCoins] = 300) and every kind
  /// resolves through PricingService — coins (dialog + spend
  /// below), free (save at once), Pro-only and ad-unlock.
  /// MERGE (Option 10): the selected part and its neighbour
  /// become ONE element (union box, the selected part's
  /// settings lead). Pure geometry — no file work.
  void _mergeSelectedPart(ChannelPreset preset) {
    final parts = preset.logoParts;
    final i = _selectedPartIndex(preset);
    if (i < 0 || parts.length < 2) return;
    final other = i + 1 < parts.length ? i + 1 : i - 1;
    final merged = mergeLogoParts(parts[i], parts[other]);
    final at = i < other ? i : other;
    setState(() {
      final list = [...parts];
      list[at] = merged;
      list.removeAt(i < other ? other : i);
      preset.logoParts = list;
      _selectedPartId = merged.id;
    });
    _showMessage('Two parts joined into one element: ${merged.name}');
  }

  /// SPLIT (Option 11): the selected box is cut into
  /// left/right halves, both keeping its settings.
  void _splitSelectedPart(ChannelPreset preset) {
    final i = _selectedPartIndex(preset);
    if (i < 0) return;
    final halves = splitLogoPart(preset.logoParts[i]);
    setState(() {
      final list = [...preset.logoParts];
      list.replaceRange(i, i + 1, halves);
      preset.logoParts = list;
      _selectedPartId = halves.first.id;
    });
  }

  /// DELETE (Option 12): the part goes away — the master logo
  /// file is never touched, so nothing is lost.
  void _deleteSelectedPart(ChannelPreset preset) {
    final i = _selectedPartIndex(preset);
    if (i < 0) return;
    setState(() {
      final list = [...preset.logoParts]..removeAt(i);
      preset.logoParts = list;
      _selectedPartId = list.isEmpty
          ? null
          : list[i >= list.length ? list.length - 1 : i].id;
      if (_isolatePartId != null &&
          !list.any((e) => e.id == _isolatePartId)) {
        _isolatePartId = null;
      }
    });
  }

  /// NAAM (Option 13): rename the selected part.
  Future<void> _renameSelectedPart(ChannelPreset preset) async {
    final i = _selectedPartIndex(preset);
    if (i < 0) return;
    final controller =
        TextEditingController(text: preset.logoParts[i].name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hisay ka naam'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Masalan: NEWS box, Globe, Ribbon',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Naam rakho'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    _updatePartAt(preset, i, (e) => e.copyWith(name: name));
  }

  /// RESET (Option 15): saare boxes saaf — the master logo
  /// stays exactly as it was; only the parts list clears.
  Future<void> _resetLogoParts() async {
    final preset = _preset;
    if (preset == null || preset.logoParts.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear all parts?'),
        content: const Text(
          'All boxes will be removed. The original logo will stay safe — '
          'you can suggest or draw the parts again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      preset.logoParts = [];
      preset.logoPartsSourcePath = null;
      _selectedPartId = null;
      _isolatePartId = null;
      _partsDrawMode = false;
    });
  }

  Future<void> _saveLogoParts() async {
    final preset = _preset;
    if (preset == null || preset.logoParts.isEmpty) return;
    if (CoinService.instance.isAdminNow) {
      _applyPartsSave(preset);
      return;
    }
    final PriceSpec spec = PricingService.specOr(
      PricingService.keyLogoPartsSave,
      fallbackCoins: kLogoPartsSavePriceCoins,
    );
    switch (spec.kind) {
      case PriceKind.free:
        _applyPartsSave(preset);
        return;
      case PriceKind.pro:
        if (PricingService.passesPro) {
          _applyPartsSave(preset);
        } else {
          _showMessage('Logo Parts save is for Pro users only.');
        }
        return;
      case PriceKind.ad:
        final bool? goAd = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Logo Parts Save'),
            content: const Text(
              'Watch a rewarded ad to save the parts.\n'
              'The save will stay valid for 7 days — after that the settings '
              'will end.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Later'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Watch Ad — Save'),
              ),
            ],
          ),
        );
        if (goAd != true || !mounted) return;
        final bool watched = await PricingService.watchUnlockAd();
        if (!mounted) return;
        if (!watched) {
          _showMessage('The ad did not complete — the parts were not saved.');
          return;
        }
        _applyPartsSave(preset);
        return;
      case PriceKind.coins:
        break; // confirm dialog + spend below, at the resolved price
    }
    final int price = spec.coins;
    final balance = CoinService.instance.balance.value;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logo Parts Save'),
        content: Text(
          '$price coins will be charged to save the parts settings. '
          'will be charged.\nThe save will stay valid for 7 days — after that the settings '
          'will end.\nYour balance: $balance coins.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Save — $price coins'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final res = await CoinService.instance.spendAmount(
      price,
      reason: kLogoPartsSaveReason,
      idempotencyKey: 'logo_parts_save:${preset.id}:$now',
    );
    if (!mounted) return;
    if (!res.ok) {
      _showMessage(
        res.error == 'insufficient_balance'
            ? AiToolCharge.insufficientMessage
            : 'Payment could not be completed — try again.',
      );
      return;
    }
    _applyPartsSave(preset, nowMs: now);
  }

  void _applyPartsSave(ChannelPreset preset, {int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    setState(() {
      // Build 2: the payload carries the parts AND their
      // scene (glow + base) — the flow (price/validity) is
      // unchanged.
      preset.logoPartsSavedJson =
          encodeLogoPartsSave(preset.logoParts, preset.logoPartsScene);
      preset.logoPartsSavedAtMs = now;
    });
    unawaited(persistPresetChange(preset));
    _showMessage('Parts saved — valid for 7 days.');
  }

  /// Build 13 (point 6): the Permanent Logo section — a
  /// standalone green-screen export of the configured animated
  /// logo, sold MANUALLY (Rs 200 Easypaisa, the Pro pattern)
  /// and gated by the owner-granted entitlement.
  List<Widget> _permanentLogoSection(ChannelPreset preset) {
    final config = RemoteConfigService.instance.config;
    final email = SupabaseService.currentUser?.email;
    return [
      const Text(
        'Permanent Logo (Green Screen Export)',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      ValueListenableBuilder<bool>(
        valueListenable: PermanentLogoService.instance.entitled,
        builder: (context, entitled, _) {
          if (entitled) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Permanent Logo is ON — your animated logo alone '
                  'can be exported on a green screen.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('permanentLogoExportButton'),
                  onPressed: _permBusy ? null : _exportPermanentLogo,
                  icon: const Icon(Icons.movie_creation_outlined, size: 18),
                  label: Text(
                    _permBusy
                        ? 'Exporting…'
                        : 'Green Screen Logo Export',
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Price: Rs ${PermanentLogoService.priceRupees} (one-time)\n'
                'Easypaisa: ${config.easypaisaNumber} (${config.easypaisaTitle})\n'
                'Aap ka login email: ${email ?? '— (pehle login karein)'}',
                style: const TextStyle(fontSize: 12.5, height: 1.5),
              ),
              const SizedBox(height: 6),
              const Text(
                'Method: send Rs 200 to this Easypaisa number and '
                'write your login email in the reference. Then after the payment '
                'WhatsApp its screenshot to this number — the owner '
                'is verified, your Permanent Logo will be turned on.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                key: const Key('permanentLogoRecheckButton'),
                onPressed: () =>
                    unawaited(PermanentLogoService.instance.refresh()),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Check again'),
              ),
            ],
          );
        },
      ),
    ];
  }

  /// Point 6: renders the configured animated logo BY ITSELF on
  /// a green screen (parts when configured, else the cube) and
  /// saves the MP4 to the gallery.
  Future<void> _exportPermanentLogo() async {
    final preset = _preset;
    if (preset == null) return;
    if (preset.logoPath == null && preset.logoParts.isEmpty) {
      _showMessage('Select the logo first.');
      return;
    }
    setState(() => _permBusy = true);
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(
        p.join(
          docs.path,
          'permanent_logo_${DateTime.now().millisecondsSinceEpoch}',
        ),
      );
      await dir.create(recursive: true);
      final framesDir = Directory(p.join(dir.path, 'frames'));
      final outFile = p.join(dir.path, 'permanent_logo.mp4');
      final String command;
      if (preset.logoParts.isNotEmpty) {
        await LogoPartsService.generatePartsFrames(
          parts: preset.logoParts,
          outDir: framesDir,
          size: preset.logoPartsScene.exportSize,
          greenScreen: true,
          scene: preset.logoPartsScene,
        );
        command = FfmpegService.logoGreenScreenCommand(
          framesDir: framesDir.path,
          output: outFile,
          durationSec: kLogoPartsLoopSec,
        );
      } else {
        await LogoLoopService.generateFrames(
          logoFile: File(preset.logoPath!),
          outDir: framesDir,
          facePaths: preset.logoCubeFacePaths,
          tiltX: preset.logoCubeTilt,
          speedSec: preset.logoCubeSpeedSec,
          clockwise: preset.logoCubeDirection != 'ccw',
          pedestal: preset.logoCubePedestal,
        );
        command = FfmpegService.logoGreenCompositeCommand(
          framesDir: framesDir.path,
          output: outFile,
          durationSec: preset.logoCubeSpeedSec,
        );
      }
      final res = await FfmpegService.run(command);
      if (!mounted) return;
      if (!res.ok) {
        setState(() => _permBusy = false);
        _showMessage('Export failed — try again.');
        return;
      }
      await Gal.putVideo(outFile);
      if (!mounted) return;
      setState(() => _permBusy = false);
      _showMessage('Permanent logo saved in the gallery.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _permBusy = false);
      _showMessage('Export failed: $e');
    }
  }

  /// Build 13 (point #19): one cube-face tile in the Logo
  /// panel — shows the face's own image when one is picked,
  /// otherwise the main logo (what the face will actually
  /// carry). Tap = pick this face's image; the small x clears
  /// it back to the main logo.
  Widget _logoFaceTile(ChannelPreset preset, String face) {
    final facePath = preset.logoCubeFacePaths[face];
    final shown = facePath ?? preset.logoPath;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          key: Key('logoFace-$face'),
          onTap: () => _pickCubeFace(face),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF181828),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: facePath != null
                    ? const Color(0xFFFFC800)
                    : const Color(0x1FFFFFFF),
              ),
            ),
            child: shown != null && File(shown).existsSync()
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(shown), fit: BoxFit.cover),
                  )
                : const Icon(Icons.image_outlined,
                    color: Colors.grey, size: 20),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              face.toUpperCase(),
              style: const TextStyle(fontSize: 9.5, color: Color(0xFF8A919C)),
            ),
            if (facePath != null)
              InkWell(
                key: Key('logoFaceClear-$face'),
                onTap: () => _updatePreset(() {
                  final next =
                      Map<String, String>.of(preset.logoCubeFacePaths);
                  next.remove(face);
                  preset.logoCubeFacePaths = next;
                }),
                child: const Icon(Icons.close, size: 12, color: Colors.grey),
              ),
          ],
        ),
      ],
    );
  }

  /// Build 13 (point #19): pick one cube face's image (copied
  /// into the app's logo folder, like the main logo pick).
  Future<void> _pickCubeFace(String face) async {
    final preset = _preset;
    if (preset == null) return;
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty || picked.first.path == null) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'news_logos'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final ext = p.extension(picked.first.path!);
      final dest = p.join(
        dir.path,
        'logo_face_${face}_${DateTime.now().millisecondsSinceEpoch}$ext',
      );
      await File(picked.first.path!).copy(dest);
      _updatePreset(() {
        preset.logoCubeFacePaths = {
          ...preset.logoCubeFacePaths,
          face: dest,
        };
      });
      _showMessage('The picture was placed on the cube\'s $face side.');
    } catch (e) {
      _showMessage('The face picture was not placed: $e');
    }
  }

  Future<void> _pickLogo() async {
    final preset = _preset;
    if (preset == null) return;
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty || picked.first.path == null) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'news_logos'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final ext = p.extension(picked.first.path!);
      final dest = p.join(
        dir.path,
        'logo_${DateTime.now().millisecondsSinceEpoch}$ext',
      );
      await File(picked.first.path!).copy(dest);
      preset.logoPath = dest;
      // Build 12: an image pick IS the cube source.
      preset.logoMediaKind = 'image';
      await persistPresetChange(preset);
      if (!mounted) return;
      setState(() {});
      _showMessage('Logo placed — see it in the preview.');
    } catch (e) {
      _showMessage('Logo was not placed: $e');
    }
  }

  /// Build 12 (point #13): pick a logo VIDEO, then detect +
  /// key its background automatically (green screen or ANY
  /// solid colour). Detection failure is honest: the video
  /// stays usable unkeyed and the status line says so.
  Future<void> _pickLogoVideo() async {
    final preset = _preset;
    if (preset == null) return;
    final picked = await FilePicker.pickFiles(type: FileType.video);
    if (picked.isEmpty || picked.first.path == null) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'news_logos'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final ext = p.extension(picked.first.path!);
      final dest = p.join(dir.path, 'logo_video_$stamp$ext');
      await File(picked.first.path!).copy(dest);
      preset.logoVideoPath = dest;
      preset.logoMediaKind = 'video';
      preset.logoVideoKeyColor = null;
      preset.logoKeyedFramesDir = null;
      preset.logoVideoStillPath = null;
      await persistPresetChange(preset);
      if (!mounted) return;
      setState(() {
        _logoVideoBusy = true;
        _logoVideoStatus = 'Checking the background…';
      });
      final videoFile = File(dest);
      final workDir = Directory(p.join(dir.path, 'keywork_$stamp'));
      final detection = await LogoKeyService.detectBackground(
        video: videoFile,
        workDir: workDir,
      );
      if (detection != null) {
        preset.logoVideoKeyColor = detection.argb;
        final framesDir = Directory(p.join(dir.path, 'keyed_$stamp'));
        final frames = await LogoKeyService.generateKeyedFrames(
          video: videoFile,
          outDir: framesDir,
          keyArgb: detection.argb,
        );
        if (frames.isNotEmpty) {
          preset.logoKeyedFramesDir = framesDir.path;
        }
        final still = await LogoKeyService.extractKeyedStill(
          video: videoFile,
          workDir: workDir,
          keyArgb: detection.argb,
        );
        if (still != null) preset.logoVideoStillPath = still.path;
        _logoVideoStatus =
            'Background removed '
            '(${LogoKeyService.displayHex(detection.argb)}) — '
            'the keyed logo is ready.';
      } else {
        final still = await LogoKeyService.extractStill(
          video: videoFile,
          workDir: workDir,
        );
        if (still != null) preset.logoVideoStillPath = still.path;
        _logoVideoStatus =
            'No solid background found — the video without key '
            'will be applied.';
      }
      await persistPresetChange(preset);
      if (!mounted) return;
      setState(() => _logoVideoBusy = false);
      _showMessage(_logoVideoStatus);
    } catch (e) {
      if (mounted) {
        setState(() => _logoVideoBusy = false);
      }
      _showMessage('Logo video was not placed: $e');
    }
  }

  Future<void> _removeLogo() async {
    final preset = _preset;
    if (preset == null) return;
    preset.logoPath = null;
    // Build 12: removing the logo clears BOTH sources (image
    // + video and its key state) — one remove, no leftovers.
    preset.logoVideoPath = null;
    preset.logoVideoKeyColor = null;
    preset.logoKeyedFramesDir = null;
    preset.logoVideoStillPath = null;
    await persistPresetChange(preset);
    if (!mounted) return;
    setState(() {});
  }

  /// Reporter panel (NS7, #50; v1.5.2 fix #68b): the NAME box
  /// is the FIRST control in the panel — obvious at first
  /// glance (on the user's phone it sat under the photo/BG
  /// section and he could not find it) — then the photo slot
  /// opposite the logo, BG Remove (BiRefNet) / BG Replace, the
  /// name font, and the position/size sliders.
  Widget _reporterPanel(NewsProject project) {
    final photo = project.reporterPhotoPath;
    final repOv = _elementOv(project, NewsElement.reporter);
    return _panelShell('Reporter', [
      const Text(
        'NUMAINDAY KA NAAM',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 0.6,
        ),
      ),
      const SizedBox(height: 6),
      TextField(
        key: const Key('reporterNameField'),
        controller: _reporterNameController,
        decoration: const InputDecoration(
          hintText: 'Write the reporter\'s name…',
          border: OutlineInputBorder(),
        ),
        onChanged: (v) {
          setState(() => project.reporterName = v);
          _scheduleSave();
        },
      ),
      const SizedBox(height: 10),
      // Build 13 (point 4): Teleprompter — the project's script
      // scrolls over the camera while the reporter records
      // (front camera, the Live Studio camera stack). The
      // finished recording joins the project's clips.
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const Key('reporterTeleprompterButton'),
          onPressed: _openTeleprompter,
          icon: Image.asset(
            'assets/ns_icons/teleprompter.png',
            width: 22,
            height: 22,
            errorBuilder: (context, error, stack) =>
                const Icon(Icons.subtitles_outlined, size: 20),
          ),
          label: const Text('Teleprompter — read the script and record'),
        ),
      ),
      const SizedBox(height: 14),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 64,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF181828),
              borderRadius: BorderRadius.circular(8),
            ),
            child: photo != null && File(photo).existsSync()
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(photo),
                      fit: BoxFit.cover,
                    ),
                  )
                : const Icon(
                    Icons.person_outline,
                    color: Colors.grey,
                    size: 30,
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  key: const Key('reporterPhotoButton'),
                  onPressed: _reporterBusy ? null : _pickReporterPhoto,
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      photo == null ? 'Attach photo' : 'Photo badlein',
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC800),
                    foregroundColor: Colors.black,
                  ),
                ),
                if (photo != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('reporterBgRemoveButton'),
                          onPressed:
                              _reporterBusy ? null : _reporterBgRemove,
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('BG Remove'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('reporterBgReplaceButton'),
                          onPressed: _reporterBusy
                              ? null
                              : () => setState(
                                    () => _reporterShowBgChoices =
                                        !_reporterShowBgChoices,
                                  ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('BG Replace'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      if (photo != null && _reporterShowBgChoices) ...[
        const SizedBox(height: 10),
        const Text(
          'Choose a background colour:',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, argb) in const [
              ('Kaala', 0xFF000000),
              ('Safed', 0xFFFFFFFF),
              ('Navy', 0xFF081E46),
              ('Sabz (chroma)', 0xFF00B140),
              ('Surkh', 0xFF880C03),
            ])
              ActionChip(
                key: Key('reporterBgColor-$argb'),
                avatar: CircleAvatar(
                  radius: 8,
                  backgroundColor: Color(argb),
                ),
                label: Text(label),
                onPressed: _reporterBusy
                    ? null
                    : () => _reporterBgReplaceColor(argb),
              ),
            ActionChip(
              key: const Key('reporterBgImageChip'),
              avatar: const Icon(Icons.wallpaper_outlined, size: 16),
              label: const Text('BG Photo'),
              onPressed: _reporterBusy ? null : _reporterBgReplaceImage,
            ),
          ],
        ),
      ],
      if (_reporterBusy) ...[
        const SizedBox(height: 10),
        const LinearProgressIndicator(
          key: Key('reporterBusyProgress'),
          minHeight: 3,
        ),
      ],
      if (_reporterStatus.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          _reporterStatus,
          key: const Key('reporterStatus'),
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
      const SizedBox(height: 12),
      const Text(
        'Naam ka font',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      NewsFontPicker(
        selectedId: project.reporterFontId,
        onChanged: (id) {
          setState(() => project.reporterFontId = id);
          _warmFont(id);
          _scheduleSave();
        },
      ),
      const SizedBox(height: 12),
      const Text(
        'Position / size',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      _elementSlider(
        label: 'Size',
        value: repOv.scale,
        min: 0.5,
        max: 2.0,
        onChanged: (v) => _setElementOverride(
          NewsElement.reporter,
          repOv.copyWith(scale: v),
        ),
      ),
      _elementSlider(
        label: 'Left / Right',
        value: repOv.dx,
        min: -0.3,
        max: 0.3,
        onChanged: (v) => _setElementOverride(
          NewsElement.reporter,
          repOv.copyWith(dx: v),
        ),
      ),
      _elementSlider(
        label: 'Up / Down',
        value: repOv.dy,
        min: -0.3,
        max: 0.3,
        onChanged: (v) => _setElementOverride(
          NewsElement.reporter,
          repOv.copyWith(dy: v),
        ),
      ),
      if (photo != null) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('reporterRemoveButton'),
          onPressed: _reporterBusy
              ? null
              : () {
                  setState(() {
                    project.reporterPhotoPath = null;
                    _reporterStatus = '';
                    _reporterShowBgChoices = false;
                  });
                  _scheduleSave();
                },
          icon: const Icon(Icons.person_remove_outlined, size: 18),
          label: const Text('Remove reporter'),
        ),
      ],
    ]);
  }

  /// Build 13 (point 4): opens the teleprompter with the
  /// project's tehreer as the scrolling script; a finished
  /// recording is added to the project's clips.
  Future<void> _openTeleprompter() async {
    final project = _project;
    if (project == null) return;
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) =>
            TeleprompterScreen(scriptText: project.tehreer),
      ),
    );
    if (path == null || !mounted) return;
    // P0-1 (tools-fix wave): addClips is a PURE function — it
    // returns the new list and changes nothing itself. The old
    // code discarded the result, then saved and announced
    // success: the recording never reached the project and was
    // lost. Now the result is assigned (with trims kept in sync
    // via setClipPaths), the project is saved IMMEDIATELY, and
    // the message only claims what actually happened.
    final wasAlreadyThere = project.clipPaths.contains(path);
    final res = project.addClips([path]);
    if (wasAlreadyThere) {
      _showMessage(
        'This recording is already in the clips — it was not added again.',
      );
      return;
    }
    if (res.droppedByCap > 0 || !res.clips.contains(path)) {
      _showMessage(
        'The recording was not added to the clips — the clips limit '
        '(${NewsProject.maxClips}) is full. First remove a clip '
        'remove one.',
      );
      return;
    }
    setState(() => project.setClipPaths(res.clips));
    await _saveNow();
    if (!mounted) return;
    if (project.clipPaths.contains(path)) {
      unawaited(_probeClips());
      _showMessage('The reporter recording joined the clips.');
    } else {
      _showMessage('The recording could not be added — try again.');
    }
  }

  Future<void> _pickReporterPhoto() async {
    final project = _project;
    if (project == null || _reporterBusy) return;
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty || picked.first.path == null) return;
    final copied = await copyReporterPhoto(picked.first.path!);
    if (!mounted) return;
    if (copied == null) {
      _showMessage('Photo could not be copied — try again.');
      return;
    }
    setState(() {
      project.reporterPhotoPath = copied;
      _reporterStatus = 'Photo placed — in the block preview '
          'has come opposite the logo.';
    });
    _scheduleSave();
  }

  Future<void> _reporterBgRemove() async {
    final project = _project;
    final photo = project?.reporterPhotoPath;
    if (project == null || photo == null || _reporterBusy) return;
    setState(() {
      _reporterBusy = true;
      _reporterStatus = 'Background is being removed — the first '
          'time the model pack will download; it will take a little time…';
    });
    try {
      final out = await reporterRemoveBackground(photo);
      if (!mounted) return;
      setState(() {
        project.reporterPhotoPath = out;
        _reporterStatus = 'Background removed.';
      });
      _scheduleSave();
    } on ReporterBgException catch (e) {
      if (mounted) setState(() => _reporterStatus = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _reporterStatus = 'BG remove failed: $e');
      }
    } finally {
      if (mounted) setState(() => _reporterBusy = false);
    }
  }

  Future<void> _reporterBgReplaceColor(int argb) async {
    final project = _project;
    final photo = project?.reporterPhotoPath;
    if (project == null || photo == null || _reporterBusy) return;
    setState(() {
      _reporterBusy = true;
      _reporterStatus = 'Changing the background…';
    });
    try {
      final out = await reporterReplaceBackground(
        photo,
        colorArgb: argb,
      );
      if (!mounted) return;
      setState(() {
        project.reporterPhotoPath = out;
        _reporterStatus = 'Background changed.';
        _reporterShowBgChoices = false;
      });
      _scheduleSave();
    } on ReporterBgException catch (e) {
      if (mounted) setState(() => _reporterStatus = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _reporterStatus = 'Background replace failed: $e');
      }
    } finally {
      if (mounted) setState(() => _reporterBusy = false);
    }
  }

  Future<void> _reporterBgReplaceImage() async {
    final project = _project;
    final photo = project?.reporterPhotoPath;
    if (project == null || photo == null || _reporterBusy) return;
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty || picked.first.path == null) return;
    setState(() {
      _reporterBusy = true;
      _reporterStatus = 'Applying the background photo…';
    });
    try {
      final out = await reporterReplaceBackground(
        photo,
        bgImagePath: picked.first.path!,
      );
      if (!mounted) return;
      setState(() {
        project.reporterPhotoPath = out;
        _reporterStatus = 'Background photo applied.';
        _reporterShowBgChoices = false;
      });
      _scheduleSave();
    } on ReporterBgException catch (e) {
      if (mounted) setState(() => _reporterStatus = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _reporterStatus = 'Background replace failed: $e');
      }
    } finally {
      if (mounted) setState(() => _reporterBusy = false);
    }
  }

  /// Audio panel (v1.5.2, fix #56): the trio — Record / Import /
  /// Text se Audio — as ONE row of full-width professional
  /// buttons in the editors' panel-button pattern (filled
  /// primary + outlined secondaries, scale-to-fit labels, so
  /// nothing ever clips off the edge — the old row's third
  /// button ran off the right side of the user's phone). All
  /// three land in the one voiceover slot. 'Text se Audio' no
  /// longer builds blind: it opens the Voice tool, where the
  /// text box, the voice choice and the generate button live
  /// together (#61) — the old behaviour (a SnackBar 'Pehle
  /// tehreer likhein.' and nothing else) read as an empty sheet.
  Widget _audioPanel(NewsProject project) {
    return _panelShell('Audio', [
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              key: const Key('audioRecordButton'),
              onPressed: _voiceBusy ? null : _toggleRecord,
              icon: Icon(_recording ? Icons.stop : Icons.mic, size: 19),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_recording ? 'Stop' : 'Record'),
              ),
              style: FilledButton.styleFrom(
                backgroundColor:
                    _recording ? Colors.redAccent : const Color(0xFFFFC800),
                foregroundColor: _recording ? Colors.white : Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('audioImportButton'),
              onPressed: _voiceBusy ? null : _importAudio,
              icon: const Icon(Icons.audio_file_outlined, size: 19),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Import'),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('audioTtsButton'),
              onPressed: _voiceBusy
                  ? null
                  : () => setState(() => _activeTool = 'voice'),
              icon: const Icon(Icons.record_voice_over_outlined, size: 19),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Text se Audio'),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
      if (_recording)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Icon(Icons.fiber_manual_record,
                  color: Colors.redAccent, size: 14),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Recording…',
                  style: TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 16),
      const Text(
        'Background Music',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      Text(
        _selectedMusicLabel(project),
        key: const Key('audioMusicStatus'),
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const SizedBox(height: 8),
      // Built-in tracks (the same selection the Export card
      // offers — ONE selection, two doors; picking here clears
      // any store pick and vice versa).
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              key: const Key('audioMusic-none'),
              label: const Text('None'),
              selected: project.backgroundMusicAsset == null &&
                  project.storeMusicPath == null,
              onSelected: (_) {
                setState(() {
                  project.backgroundMusicAsset = null;
                  project.storeMusicPath = null;
                  project.storeMusicName = null;
                });
                _scheduleSave();
              },
            ),
            const SizedBox(width: 8),
            for (final track in BuiltInNewsMusic.defaults()) ...[
              ChoiceChip(
                key: Key('audioMusic-${track.id}'),
                label: Text('${track.label} • FREE'),
                selected: project.backgroundMusicAsset ==
                        track.assetPath &&
                    project.storeMusicPath == null,
                onSelected: (_) {
                  setState(() {
                    project.backgroundMusicAsset = track.assetPath;
                    project.storeMusicPath = null;
                    project.storeMusicName = null;
                  });
                  _scheduleSave();
                },
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
      // Build 13 (point 5): Auto Ducking — the export ducks
      // the music bed under the voiceover (sidechain) instead
      // of holding it at a fixed level. Default ON; OFF keeps
      // the pre-Build-13 fixed-level mix exactly.
      SwitchListTile(
        key: const Key('audioDuckingSwitch'),
        secondary: Image.asset(
          'assets/ns_icons/ducking.png',
          width: 26,
          height: 26,
          errorBuilder: (context, error, stack) =>
              const Icon(Icons.graphic_eq, size: 22),
        ),
        title: const Text('Auto Ducking (music under the voice)'),
        subtitle: const Text(
          'The music under the voiceover lightens by itself',
        ),
        value: project.musicDucking,
        onChanged: (v) {
          setState(() => project.musicDucking = v);
          _scheduleSave();
        },
      ),
      const SizedBox(height: 14),
      const Text(
        'Store Music & Sounds',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      // Build 12 (point #9a): the user's owned Online Store
      // audio — playable here through the store's ONE preview
      // player (no second player) and selectable as the
      // project's background music.
      if (_storeAudioItems.isEmpty)
        Row(
          children: [
            const Expanded(
              child: Text(
                'No store audio owned yet — take music / sound effects '
                'take music / a sound effect from the Store; it will come here.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: const Key('audioStoreOpenButton'),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        const StoreScreen(initialCategory: 'Music'),
                  ),
                );
                unawaited(_loadStoreAudio());
              },
              child: const Text('Open Store'),
            ),
          ],
        )
      else
        for (final owned in _storeAudioItems)
          _storeAudioRow(project, owned),
    ]);
  }

  /// The Audio panel's current-music line: the store pick
  /// wins (it is also the export's precedence), then the
  /// built-in track, then none.
  String _selectedMusicLabel(NewsProject project) {
    if (project.storeMusicPath != null) {
      return 'Selected: ${project.storeMusicName ?? 'Store music'} '
          '(Store)';
    }
    final track =
        BuiltInNewsMusic.fromAsset(project.backgroundMusicAsset);
    if (track != null) return 'Selected: ${track.label} (built-in)';
    return 'Selected: no music';
  }

  /// One owned store-audio row in the Audio panel: play/pause
  /// through [StoreAudioPreviewPlayer] (the store's own
  /// one-at-a-time player) + select as background music.
  Widget _storeAudioRow(NewsProject project, StoreOwnedItem owned) {
    final item = StoreItem(
      id: owned.id,
      name: owned.name,
      category: owned.category,
    );
    final selected = project.storeMusicPath == owned.localPath;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          ValueListenableBuilder<StoreAudioPreviewState>(
            valueListenable: StoreAudioPreviewPlayer.instance.state,
            builder: (context, state, _) {
              final isThis = state.itemId == owned.id;
              final playing =
                  isThis && state.phase == StoreAudioPhase.playing;
              final loading =
                  isThis && state.phase == StoreAudioPhase.loading;
              return IconButton(
                key: Key('audioStorePlay-${owned.id}'),
                onPressed: loading
                    ? null
                    : () => unawaited(
                          StoreAudioPreviewPlayer.instance.toggle(item),
                        ),
                icon: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        playing
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                        color: const Color(0xFFFFC800),
                      ),
                tooltip: playing ? 'Pause' : 'Play',
              );
            },
          ),
          Expanded(
            child: Text(
              item.displayTitle,
              maxLines: 2,
              style: TextStyle(
                fontSize: 13,
                color: selected ? const Color(0xFFFFC800) : null,
                fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: Key('audioStoreSelect-${owned.id}'),
            onPressed: selected
                ? null
                : () {
                    setState(() {
                      project.storeMusicPath = owned.localPath;
                      project.storeMusicName = item.displayTitle;
                      project.backgroundMusicAsset = null;
                    });
                    _scheduleSave();
                  },
            child: Text(selected ? 'Applied' : 'Apply'),
          ),
        ],
      ),
    );
  }

  /// One Voice-panel slider row (Build 12): label, FLEXIBLE
  /// slider and a fixed-width value readout — the editors'
  /// thin-slider-with-value grammar, safe at 360 px.
  Widget _voiceSliderRow({
    required String label,
    required String valueText,
    required Widget slider,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(flex: 3, child: slider),
        SizedBox(
          width: 44,
          child: Text(
            valueText,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  /// Voice panel (v1.5.2, fix #61): the COMPLETE text-to-voice
  /// place, in the Magic Box TTS-studio shape — the text box,
  /// the voice choice and the generate button together, on top
  /// of the speed / pause / music controls, the status and the
  /// preview player. Generation runs the app's existing working
  /// paths (Gemini proxy via [_buildVoice], free Edge TTS via
  /// [_buildFreeTtsVoice] — the same engines AI Voice Studio
  /// uses). Before this fix the panel had NO text box and NO
  /// generate button at all.
  Widget _voicePanel(NewsProject project) {
    return _panelShell('Voice', [
      const Text(
        'Tehreer — voice isi se banegi',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      TextField(
        key: const Key('voiceTehreerField'),
        controller: _tehreerController,
        maxLines: 3,
        minLines: 3,
        textAlign: TextAlign.right,
        textDirection: TextDirection.rtl,
        decoration: const InputDecoration(
          hintText: 'Write or paste the script here…',
          border: OutlineInputBorder(),
        ),
        // P2: debounced rebuild (see _textFieldChanged) — the
        // whole Maker no longer rebuilds on every keystroke.
        onChanged: (_) => _textFieldChanged(),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          key: const Key('voiceBuildButton'),
          onPressed: _voiceBusy ? null : _buildSelectedVoice,
          icon: const Icon(Icons.record_voice_over, size: 19),
          label: Text(_voiceBusy ? 'Creating voice…' : 'Voice banayein'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFFC800),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        'Choose a voice',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      // v1.5.2 (fix #60): ONE horizontal rail of voice chips —
      // the old Wrap laid them out in uneven rows.
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final v in StudioVoice.all) ...[
              _studioVoiceChip(v),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
      const SizedBox(height: 8),
      // Build 12 (point #14h): the slider rows flex with the
      // panel width — the old fixed 200-wide slider squeezed
      // the label out on narrow phones.
      _voiceSliderRow(
        label: 'Speed',
        valueText: '${project.voiceSpeed.toStringAsFixed(2)}x',
        slider: Slider(
          key: const Key('voiceSpeedSlider'),
          value: project.voiceSpeed,
          min: 0.5,
          max: 2.0,
          divisions: 15,
          label: '${project.voiceSpeed.toStringAsFixed(2)}x',
          onChanged: (v) {
            setState(() => project.voiceSpeed = v);
            _scheduleSave();
          },
        ),
      ),
      _voiceSliderRow(
        label: 'Pause (between sentences)',
        valueText: '${project.voicePauseSec.toStringAsFixed(1)}s',
        slider: Slider(
          key: const Key('voicePauseSlider'),
          value: project.voicePauseSec,
          min: 0,
          max: 1.0,
          divisions: 10,
          label: '${project.voicePauseSec.toStringAsFixed(1)}s',
          onChanged: (v) {
            setState(() => project.voicePauseSec = v);
            _scheduleSave();
          },
        ),
      ),
      // Build 12 (point #14f): the BACKGROUND MUSIC toggle —
      // the Audio tool mein selected music (store item ya
      // built-in track) export mein voiceover ke neeche lage
      // ya na lage. Wired in ReelExportService step 2b.
      SwitchListTile(
        key: const Key('voiceMusicSwitch'),
        title: const Text('Background music (in export)'),
        subtitle: Text(
          project.storeMusicPath != null
              ? 'Music: ${project.storeMusicName ?? 'Store music'}'
              : BuiltInNewsMusic.fromAsset(
                        project.backgroundMusicAsset,
                      ) !=
                      null
                  ? 'Music: ${BuiltInNewsMusic.fromAsset(project.backgroundMusicAsset)!.label}'
                  : 'Music: none selected (choose from the Audio tool)',
          style: const TextStyle(fontSize: 12),
        ),
        value: project.voiceMusicEnabled,
        onChanged: (v) {
          setState(() => project.voiceMusicEnabled = v);
          _scheduleSave();
        },
      ),
      // The OLD soft-pad control, kept as its own switch (no
      // control removed): ye pad voice BANATE waqt TTS mix
      // mein lagta hai — export bed se alag cheez hai.
      SwitchListTile(
        key: const Key('voicePadSwitch'),
        title: const Text('Soft pad behind the AI voice'),
        subtitle: const Text(
          'Light music mixes while the voice is created',
          style: TextStyle(fontSize: 12),
        ),
        value: project.voiceMusic,
        onChanged: (v) {
          setState(() => project.voiceMusic = v);
          _scheduleSave();
        },
      ),
      if (_voiceBusy) ...[
        const SizedBox(height: 8),
        const LinearProgressIndicator(
          key: Key('voiceBusyProgress'),
          minHeight: 3,
        ),
      ],
      // v1.5.0 (#18): the status line renders ONLY for a real
      // status — the default 'No voice has been created yet.' text is NOT
      // repeated here; the VoicePreviewPlayer's empty card below
      // is the one place that message lives.
      if (_voiceStatus != 'No voice has been created yet.') ...[
        const SizedBox(height: 8),
        Text(
          _voiceStatus,
          key: const Key('voiceStatus'),
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
      if (_voiceRemaining != null && _voiceRemaining != -1)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            'Today\'s voice limit: $_voiceRemaining / 5 left',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      if (ProService.instance.proActive)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            'Pro active: AI voice ki roz limit '
            '${ProService.instance.limitFor(5, 25)}/day.',
            style: const TextStyle(color: Colors.amber, fontSize: 12),
          ),
        ),
      const SizedBox(height: 8),
      VoicePreviewPlayer(
        filePath: project.voiceoverPath,
        durationSec: project.voiceoverDurationSec,
        voiceLabel: _selectedStudioVoice.label,
        regenerating: _voiceBusy,
        onRegenerate: () {
          if (_selectedStudioVoice.engine == StudioTtsEngine.edge) {
            unawaited(_buildFreeTtsVoice());
          } else {
            unawaited(_buildVoice(regenerate: true));
          }
        },
      ),
    ]);
  }

  /// Captions panel: the karaoke-sync summary + the ONE
  /// Caption Studio entry + (Build 12, point #14g) the
  /// CapCut-style DYNAMIC caption styles — word highlight /
  /// pop styles jo export mein CaptionService ke styled ASS
  /// se burn hotay hain (the same engine Caption Studio uses;
  /// the pick here writes the project's ONE captionStyleId).
  Widget _captionsPanel(NewsProject project) {
    const dynamicIds = <String>[
      'nigraan',
      'karaoke_fill',
      'bold_pop',
      'pop_up',
      'one_word',
      'highlight_box',
      'typewriter',
      'urdu_kasheeda_gold',
    ];
    return _panelShell('Captions', [
      Row(
        children: [
          Expanded(
            child: Text(
              project.subtitles.isEmpty
                  ? 'No subtitles yet — create the voiceover, '
                      'then the subtitles will sync with its real length '
                      'will be.'
                  : 'Subtitles: ${project.subtitles.length} lines'
                      '${project.voiceoverDurationSec == null ? ' (basic split — voiceover se sync nahi)' : ' — voiceover se synced (${project.voiceoverDurationSec!.toStringAsFixed(1)}s)'}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: const Key('captionsButton'),
            onPressed: _openCaptions,
            child: const Text('Captions →'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      // Build 13 (point #16): the timing-source line — honest
      // labelling of WHERE the word timings came from, with the
      // stale badge when the script/voiceover changed after a
      // Whisper alignment.
      Row(
        children: [
          Icon(
            project.captionTimingSource == 'whisper'
                ? Icons.verified_outlined
                : Icons.timelapse_outlined,
            size: 15,
            color: project.captionTimingsStale
                ? const Color(0xFFFFC800)
                : const Color(0xFF8A919C),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              key: const Key('captionTimingStatus'),
              project.captionTimingsStale
                  ? 'Timings: they were REAL (Whisper) — the script or '
                      'the voiceover changed; apply Real '
                      'apply the timings.'
                  : project.captionTimingSource == 'whisper'
                      ? 'Timings: REAL (Whisper) — every word at its '
                          'at its real time.'
                      : 'Timings: ESTIMATE — voiceover ki length '
                          'has been estimated from it.',
              style: TextStyle(
                color: project.captionTimingsStale
                    ? const Color(0xFFFFC800)
                    : const Color(0xFF8A919C),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('captionsAlignButton'),
              onPressed: _alignBusy ||
                      project.voiceoverPath == null ||
                      project.subtitles.isEmpty
                  ? null
                  : () => _runCaptionAlignment(project),
              icon: _alignBusy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.hearing_outlined, size: 17),
              label: Text(
                _alignBusy
                    ? 'Whisper is listening…'
                    : 'Asal timings (Whisper)',
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      const Text(
        'Dynamic Captions (CapCut style)',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final id in dynamicIds) ...[
              ChoiceChip(
                key: Key('captionDyn-$id'),
                label: Text(StudioCaptionStyles.byId(id).nameEn),
                selected: project.captionStyleId == id,
                onSelected: (_) {
                  setState(() => project.captionStyleId = id);
                  _scheduleSave();
                },
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
      const SizedBox(height: 6),
      Text(
        project.voiceoverDurationSec == null
            ? 'Every word has its own time — after the voiceover is created '
                'after it, the subtitles sync with its REAL length '
                'happen, then this style will burn word-by-'
                'word burn. Right now the timings are estimates.'
            : 'Word timings voiceover ki real length se synced '
                'they are — in the export this style will highlight / pop every word at its '
                'time.',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
    ]);
  }

  /// Export panel: the Library Transition picker (#52 — applied
  /// between the clips in the export) + the real ReelExportCard
  /// + the ONE SEO entry (moved here from the old bottom row).
  Widget _exportPanel(ChannelPreset preset, NewsProject project) {
    return _panelShell('Export', [
      const Text(
        'Transition (Library) — between clips',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 6),
      _libraryPicker(
        keyPrefix: 'transitionPick',
        items: _transitions,
        selectedId: project.transitionId,
        onChanged: (id) {
          setState(() => project.transitionId = id);
          _scheduleSave();
        },
        emptyNote: 'No Library transition yet.',
      ),
      const SizedBox(height: 16),
      ReelExportCard(project: project, preset: preset),
      const SizedBox(height: 12),
      // Build 5 (v1.5.7): the retired Template & Studio screen's
      // bottom button, renamed to what it is (a template FRAME /
      // poster export, not the reel) and moved to the one export
      // door (audit D3/D6).
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          key: const Key('templateFrameExportButton'),
          onPressed: _frameExporting
              ? null
              : () => unawaited(_exportTemplateFrame()),
          icon: _frameExporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.image_outlined, size: 18),
          label: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('Save template frame (poster)'),
          ),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const Key('seoButton'),
        onPressed: _openSeo,
        icon: const Icon(Icons.trending_up_outlined, size: 18),
        label: const Text('SEO →'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFFFC800),
          foregroundColor: Colors.black,
        ),
      ),
    ]);
  }

  /// Template frame (poster) export (Build 5 absorption of the
  /// retired screen's export): renders the current template
  /// (final, breaking or classic) as a 720×1280 PNG frame from
  /// the working preset and saves it to the gallery.
  Future<void> _exportTemplateFrame() async {
    final preset = _preset;
    if (preset == null || _frameExporting) return;
    setState(() => _frameExporting = true);
    try {
      await _saveNow();
      final dir = await getApplicationDocumentsDirectory();
      final kind = preset.templateKind;
      final file = await renderLiveTemplateImage(
        template: NewsTemplate(),
        tickerPx: 0,
        now: DateTime.now(),
        dir: dir,
        templateKind: kind == kTemplateBreaking
            ? 'breaking'
            : kind == kTemplateClassic
                ? 'classic'
                : 'final',
        preset: preset,
        breakingTemplate: kind == kTemplateBreaking
            ? BreakingTemplate.fromPreset(preset)
            : null,
        tickerAtStart: true,
        includeLogo: true,
        fontReady: _fontReady,
        includeIntroMarker: true,
      );
      await Gal.putImage(file.path);
      _showMessage('Template frame saved in the gallery.');
    } catch (e) {
      _showMessage('Template frame could not be saved: $e');
    } finally {
      if (mounted) setState(() => _frameExporting = false);
    }
  }

  /// v1.5.1 (#51/#52): registers the user's uploaded fonts in
  /// this process, warms the project's three font choices (so
  /// google_fonts families are live for the preview + the parity
  /// export), and loads the Library listings (cache-first).
  Future<void> _initFontsAndLibrary() async {
    try {
      await UserFontService.instance.loadAll();
      await UserFontService.instance.syncIntoRegistry();
    } catch (e, s) {
      // Fonts are fail-soft — the pickers still show built-ins.
      // Build 7: recorded with its boundary tag (no banner).
      CrashGuard.captureHandled(e, s, source: 'maker.fonts');
    }
    final project = _project;
    if (project != null) {
      _warmFont(project.headlineFontId);
      _warmFont(project.tickerFontId);
      _warmFont(project.reporterFontId);
    }
    // Build 6 (v1.5.8, error-banner audit): the Library listings
    // read the Drive-backed store folders and can fail on a real
    // device (no cache yet, I/O error). This method is called
    // bare from initState, so an escape here became an unhandled
    // async error — a CrashGuard banner source. Fail-soft: the
    // pickers simply stay empty, like the font branch above.
    try {
      final styles =
          await LibraryService.instance.listItems(LibraryConfig.textStyles);
      final transitions =
          await LibraryService.instance.listItems(LibraryConfig.transitions);
      final effects =
          await LibraryService.instance.listItems(LibraryConfig.effects);
      if (!mounted) return;
      setState(() {
        _textStyles = styles;
        _transitions = transitions;
        _effects = effects;
      });
    } catch (e, s) {
      // Library listings only feed the pickers — never an error
      // path. Build 7: recorded with its boundary tag.
      CrashGuard.captureHandled(e, s, source: 'maker.store');
    }
  }

  /// Triggers a google_fonts family load for [id] (its apply()
  /// runs the package getter); built-in Kasheeda + user fonts
  /// are FontLoader-registered already, so this is a no-op for
  /// them beyond the lookup.
  void _warmFont(String id) {
    try {
      UrduFonts.byId(id).apply(const TextStyle());
    } catch (_) {}
  }

  /// One chip of the unified 8-voice catalogue (v1.5.0, #19).
  /// Selecting a Gemini voice also syncs [_voice] (the Gemini build
  /// path + project.voice); selecting Asad/Uzma routes the build to
  /// the free-TTS path via [_studioVoiceId] alone.
  Widget _studioVoiceChip(StudioVoice v) {
    final selected = _studioVoiceId == v.id;
    return InkWell(
      key: Key('voiceChoice-${v.label}'),
      onTap: () {
        setState(() {
          _studioVoiceId = v.id;
          if (v.engine == StudioTtsEngine.gemini) {
            _voice = GeminiVoice.values.firstWhere(
              (g) => g.name == v.id,
              orElse: () => GeminiVoice.aoede,
            );
          }
        });
        _scheduleSave();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          // Build 12 (design law): the selected voice chip
          // takes the gold accent with black text — the violet
          // selection fill is gone from the Maker.
          color: selected
              ? const Color(0xFFFFC800)
              : const Color(0xFF181828),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFFFFC800) : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${v.label} • ${v.gender}'
              '${v.engine == StudioTtsEngine.edge ? ' • Free' : ''}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: selected ? Colors.black : null,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 4),
              const Icon(Icons.check, size: 16, color: Colors.black),
            ],
          ],
        ),
      ),
    );
  }
}

/// The transparency checkerboard behind the Logo Parts big
/// preview (Option 35, redesign Build 2) — the classic
/// two-grey grid every graphics editor uses to show where
/// an image is empty.
class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 14.0;
    final light = Paint()..color = const Color(0xFF3A3A46);
    final dark = Paint()..color = const Color(0xFF26262F);
    canvas.drawRect(Offset.zero & size, dark);
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = 0; x * cell < size.width; x++) {
        if ((x + y).isEven) continue;
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell, cell),
          light,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerboardPainter oldDelegate) => false;
}

/// v1.14.0 T4 (B5): the Maker timeline ruler — adaptive ticks
/// (TimelineMath.rulerStepSec, the same ladder the Video Editor
/// uses) with second/m:ss labels, drawn in the timeline's own
/// pixel space so it scrolls and zooms together with the lanes.
class _NsRulerPainter extends CustomPainter {
  _NsRulerPainter({required this.pps, required this.totalSec});

  final double pps;
  final double totalSec;

  @override
  void paint(Canvas canvas, Size size) {
    final step = TimelineMath.rulerStepSec(pps);
    final tick = Paint()..color = const Color(0xFF3A4150);
    for (var s = 0.0; s <= totalSec + 0.001; s += step) {
      final x = s * pps;
      canvas.drawLine(
          Offset(x, size.height - 5), Offset(x, size.height), tick);
      final tp = TextPainter(
        text: TextSpan(
          text: _label(s, step),
          style: const TextStyle(fontSize: 9, color: Color(0xFF5E646F)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 3, 0));
    }
  }

  String _label(double s, double step) {
    if (step < 1) return s.toStringAsFixed(1);
    final r = s.round();
    return '${r ~/ 60}:${(r % 60).toString().padLeft(2, '0')}';
  }

  @override
  bool shouldRepaint(_NsRulerPainter oldDelegate) =>
      oldDelegate.pps != pps || oldDelegate.totalSec != totalSec;
}
