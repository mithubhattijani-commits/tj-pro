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
///     "Dobara" deletes the cached file and re-synthesises (costs
///     new proxy request(s) — the status line says so).
///   - Voice controls (Phase 5): speed 0.5–2.0x + pause between
///     sentences + background music — applied on-device to the
///     voiceover (see `tts_processing.dart`) and saved on the
///     project, so "Dobara" re-applies them.
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
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../services/asset_download_service.dart';
import '../services/coin_service.dart';
import '../services/font_registry.dart';
import '../services/gemini_voice_service.dart';
import '../services/library_service.dart';
import '../services/pro_service.dart';
import '../services/tts_processing.dart';
import '../services/tts_studio_service.dart';
import '../services/user_font_service.dart';
import 'breaking_templates.dart';
import 'caption_studio_screen.dart';
import 'channel_preset.dart';
import 'karaoke_sync.dart';
import 'news_analysis.dart';
import 'element_override.dart';
import 'news_project.dart';
import 'seo_screen.dart';
import 'template_studio_screen.dart';
import 'widgets/breaking_preview.dart';
import 'widgets/clip_picker.dart';
import 'widgets/font_picker.dart';
import 'widgets/nigraan_final_preview.dart';
import 'widgets/reel_export_card.dart';
import 'widgets/reporter_overlay.dart';
import 'widgets/studio_pickers.dart';
import 'widgets/template_media_preview.dart';
import 'widgets/voice_preview_player.dart';

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

  /// v1.5.1 (#49/#50): controllers for the Ticker panel's side
  /// label and the Reporter panel's name field.
  final _tickerLabelController = TextEditingController();
  final _reporterNameController = TextEditingController();

  /// v1.5.1 (News Studio step, NS2): the open tool of the tool
  /// line (null = the summary card shows).
  String? _activeTool;

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
  String _voiceStatus = 'Abhi voice nahi bani.';
  int? _voiceRemaining;

  // v1.4.0 audio trio (requirements #6): Record / Import /
  // Text se Audio — all three land in the SAME project voiceover
  // slot (project.voiceoverPath) the Gemini flow already uses.
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;

  String _saveStatus = '';
  Timer? _saveTimer;

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
      _tickerLabelController.text = _project!.tickerLabel;
      _reporterNameController.text = _project!.reporterName;
      _loaded = true;
      _refreshVoiceStatus();
      _checkFont();
      _initFontsAndLibrary();
    } else {
      _load();
    }
  }

  Future<void> _load() async {
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
    setState(() {
      _preset = preset;
      _project = project;
      _voice = project.voice;
      _studioVoiceId = project.studioVoiceId.isNotEmpty
          ? project.studioVoiceId
          : project.voice.name;
      _tehreerController.text = project.tehreer;
      _tickerController.text = project.tickerText;
      _tickerLabelController.text = project.tickerLabel;
      _reporterNameController.text = project.reporterName;
      _loaded = true;
    });
    await _refreshVoiceStatus();
    await _checkFont();
    await _initFontsAndLibrary();
  }

  Future<void> _refreshVoiceStatus() async {
    final remaining = await GeminiVoiceService().remainingToday();
    if (!mounted) return;
    setState(() => _voiceRemaining = remaining);
  }

  Future<void> _checkFont() async {
    try {
      final cached = await const AssetDownloadService()
          .cachedFile(AssetDownloadService.kasheedaFileName);
      if (cached != null) {
        await AssetDownloadService.loadKasheedaFontFromFile(cached);
        if (!mounted) return;
        setState(() => _fontReady = true);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    unawaited(_recorder.dispose());
    _tehreerController.dispose();
    _tickerController.dispose();
    _tickerLabelController.dispose();
    _reporterNameController.dispose();
    super.dispose();
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
      syncNote = ' Subtitles voiceover se sync ho gaye.';
    }
    setState(() {
      project.voiceoverPath = path;
      project.voiceoverDurationSec = durationSec;
      _voiceStatus = '$sourceLabel tayyar hai.$syncNote';
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
        _showMessage('Recording save nahi hui.');
        return;
      }
      final bytes = await File(path).readAsBytes();
      final dur = audioDurationSeconds(bytes, 'wav');
      await _setProjectVoiceover(
        path,
        dur > 0 ? dur : null,
        'Apni recording',
      );
      return;
    }
    if (!await _recorder.hasPermission()) {
      _showMessage('Mic ki permission chahiye recording ke liye.');
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
      _voiceStatus = 'Recording ho rahi hai… Stop dabayein jab ho jaye.';
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
        'Import ki gayi audio (${p.basename(src.path)})',
      );
    } catch (e) {
      _showMessage('Audio import nahi hui: $e');
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
      _showMessage('Pehle tehreer likhein.');
      return;
    }
    setState(() {
      _voiceBusy = true;
      _voiceStatus = 'Free TTS se voice ban rahi hai…';
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
        final spendResult =
            await CoinService.instance.spend(CoinFeature.voiceover);
        if (!spendResult.ok) {
          if (!mounted) return;
          setState(() {
            _voiceBusy = false;
            _voiceStatus = 'Voiceover ke liye 50 coins chahiye — '
                'balance kam hai. Watch Ads se coins kamayein.';
          });
          _showMessage(
            'Coins kam hain — voiceover ke liye 50 coins chahiye.',
          );
          return;
        }
      }
      final path = result.filePath;
      if (path == null) {
        throw Exception('Audio file save nahi hui.');
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
        _voiceStatus = 'Free TTS voice nahi bani: $e';
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
    project.tehreer = _tehreerController.text;
    project.tickerText = _tickerController.text;
    project.tickerLabel = _tickerLabelController.text.trim();
    project.reporterName = _reporterNameController.text;
    project.voice = _voice;
    project.studioVoiceId = _studioVoiceId;
    await NewsProjectStore.save(project);
    if (!mounted) return;
    final now = DateTime.now();
    setState(
      () => _saveStatus =
          'Saved • ${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}',
    );
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
    Widget child,
  ) {
    if (project.templateKind != 'nigraanFinal') return child;
    const ph = 300.0;
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
        const Text(
          'Preview par tap karke element select karein, drag karke '
          'move karein, corner handle se size badlein. Neeche '
          'sliders bhi wohi kaam karte hain.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in NewsElement.all)
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
          ],
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
        Row(
          children: [
            OutlinedButton.icon(
              key: const Key('elementHideButton'),
              onPressed: () => _setElementOverride(
                sel,
                ov.copyWith(hidden: !ov.hidden),
              ),
              icon: Icon(
                ov.hidden ? Icons.visibility : Icons.visibility_off,
                size: 18,
              ),
              label: Text(ov.hidden ? 'Show (wapas)' : 'Remove (hide)'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: ov.isIdentity
                  ? null
                  : () => _setElementOverride(sel, ElementOverride.identity),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Reset element'),
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
                ? 'Watermark ON (band karein)'
                : 'Watermark OFF (lagayein)',
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

  /// Real voiceover build through the Gemini proxy (see the file
  /// header + GeminiVoiceService: chunked, cache-first, 5/day cap).
  /// [regenerate] ("Dobara") deletes the cached file first, so the
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
      _showMessage('Pehle tehreer likhein.');
      return;
    }
    setState(() {
      _voiceBusy = true;
      _voiceStatus = 'Voice ban rahi hai…';
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
        final spendResult =
            await CoinService.instance.spend(CoinFeature.voiceover);
        if (!spendResult.ok) {
          if (!mounted) return;
          setState(() {
            _voiceBusy = false;
            _voiceStatus = 'Voiceover ke liye 50 coins chahiye — '
                'balance kam hai. Watch Ads se coins kamayein.';
          });
          _showMessage(
            'Coins kam hain — voiceover ke liye 50 coins chahiye.',
          );
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
        syncNote = ' Subtitles voiceover se sync ho gaye.';
      }
      setState(() {
        _voiceBusy = false;
        project.voiceoverPath = result.file.path;
        project.voiceoverDurationSec = duration;
        _voiceRemaining = remaining;
        _voiceStatus = result.cached
            ? 'Cached voice — 0 nayi calls (same tehreer).$syncNote'
            : result.usedDeviceFallback
                ? 'Device voice use hui (proxy/cap issue) — 0 proxy calls.$syncNote'
                : 'Nayi voice — ${result.proxyRequests} request(s) use hui.$syncNote';
      });
      _scheduleSave();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _voiceBusy = false;
        _voiceStatus = 'Voice nahi ban saki: $e';
      });
    }
  }

  Future<void> _pasteTicker() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _showMessage('Clipboard khaali hai — pehle text copy karein.');
      return;
    }
    setState(() => _tickerController.text = text);
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
    setState(() => _preset = preset);
  }

  /// v1.5.0 (#32) — Add Video sheet: the SAME ClipPickerList as the
  /// Clips section below (one control, two entry points — the list
  /// in the sheet and the section share the project's clip list, so
  /// they can never disagree). Add / photo / reorder / remove all
  /// land in project.clipPaths and autosave.
  void _showClipsSheet(NewsProject project) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, sheetSetState) => SafeArea(
          child: SizedBox(
            height: 440,
            child: Column(
              children: [
                const ListTile(
                  title: Text(
                    'Apni video / photo — template ke main area ke liye',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Pehli clip preview mein dikhti hai; export mein '
                    'saari clips order se lagti hain.',
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: ClipPickerList(
                      paths: project.clipPaths,
                      onChanged: (next) {
                        setState(() => project.clipPaths = next);
                        sheetSetState(() {});
                        _scheduleSave();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// v1.5.0 (#32) — Templates sheet (shared picker): built-in
  /// designs set the project's template kind (+ the preset's Final
  /// variant for Final 3-Ribbon vs Classic 2-Ribbon); Store /
  /// Library picks navigate.
  Future<void> _showTemplatesSheet(NewsProject project) async {
    final preset = _preset;
    if (preset == null) return;
    final pick = await showTemplatesPicker(
      context,
      currentKind: project.templateKind,
      currentIsFinal3: preset.finalIs3Ribbon,
    );
    if (pick == null || !mounted) return;
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

  /// v1.5.0 (#32) — Ribbons sheet (shared picker): design picks
  /// mutate + persist the working preset; Studio / Store navigate.
  Future<void> _showRibbonsSheet() async {
    final preset = _preset;
    if (preset == null) return;
    final pick = await showRibbonsPicker(
      context,
      currentIsFinal3: preset.finalIs3Ribbon,
    );
    if (pick == null || !mounted) return;
    await handleRibbonPick(
      context,
      pick,
      preset: preset,
      persistPreset: () => persistPresetChange(preset),
    );
    await _reloadPreset();
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
    return preset;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C3AED),
          secondary: Color(0xFF7C3AED),
        ),
        scaffoldBackgroundColor: const Color(0xFF080810),
        cardColor: const Color(0xFF181828),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('News Maker'),
          backgroundColor: const Color(0xFF080810),
          actions: [
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Project save karein',
              onPressed: () async {
                await _saveNow();
                _showMessage('Project save ho gaya.');
              },
            ),
          ],
        ),
        body: !_loaded || _preset == null || _project == null
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(_preset!, _project!),
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
  ];

  Widget _toolLine() {
    return SizedBox(
      key: const Key('makerToolLine'),
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _toolDefs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (ctx, i) {
          final (id, icon, label) = _toolDefs[i];
          final active = _activeTool == id;
          final color =
              active ? const Color(0xFFF5C542) : Colors.white70;
          return InkWell(
            key: Key('makerTool-$id'),
            onTap: () =>
                setState(() => _activeTool = active ? null : id),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 64,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: active
                    ? const Color(0xFF2A2118)
                    : Colors.transparent,
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
                  Icon(icon, size: 22, color: color),
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

  /// Panel scaffold (editors' pattern): title + ONE gold ✓ that
  /// closes the panel back to the summary.
  Widget _panelShell(String title, List<Widget> children) {
    return Column(
      key: Key('makerPanel-$_activeTool'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
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
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }

  /// The no-tool summary card (NS2): preset + project + template
  /// + save state — the long card list is gone.
  Widget _summaryCard(
    ChannelPreset preset,
    NewsProject project,
    String templateLabel,
  ) {
    return Container(
      key: const Key('makerSummaryCard'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF181828),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Channel preset — ${preset.name}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            project.title.isEmpty ? 'Untitled Project' : project.title,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            '$templateLabel • Portrait 9:16 • '
            '${project.clipPaths.length} clips'
            '${_saveStatus.isEmpty ? '' : ' • $_saveStatus'}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 6),
          const Text(
            'Upar tool line se koi tool chunein — Template, Media, '
            'Tehreer, Ticker, Reporter, Voice, Export sab yahin '
            'hain.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
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
  /// 'Koi nahi' + one chip per valid Drive item. An empty library
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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          key: Key('$keyPrefix-none'),
          label: const Text('Koi nahi'),
          selected: selectedId.isEmpty,
          onSelected: (_) => onChanged(''),
        ),
        for (final item in items)
          ChoiceChip(
            key: Key('$keyPrefix-${item.folderId}'),
            label: Text(item.name),
            selected: selectedId == item.folderId,
            onSelected: (_) => onChanged(item.folderId),
          ),
      ],
    );
  }

  Widget _buildBody(ChannelPreset preset, NewsProject project) {
    final previewPreset = _previewPreset();
    final templateLabel = project.templateKind == 'nigraanFinal'
        ? 'Final 3-Ribbon'
        : project.templateKind == 'breaking'
            ? 'Breaking • ${BreakingVariant.fromId(project.breakingVariant).label}'
            : 'Classic';
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
    return ListView(
      key: const Key('makerList'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Text(
          '${preset.name} preset • $templateLabel',
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
        if (_saveStatus.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _saveStatus,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        const SizedBox(height: 12),
        Center(
          child: _withElementGestures(
            project,
            previewPreset,
            project.templateKind == 'nigraanFinal'
                ? project.clipPaths.isEmpty
                    ? NigraanFinalPreview(
                        preset: previewPreset,
                        fontReady: _fontReady,
                        height: 300,
                        elementOverrides: project.elementOverrides,
                        tickerLabel: project.tickerLabel.isEmpty
                            ? null
                            : project.tickerLabel,
                        headlineFontFamily: headlineFamily,
                        tickerFontFamily: tickerFamily,
                        headlineTextColor:
                            headlineStyle?.recipe.styleColor,
                        tickerTextColor: tickerStyle?.recipe.styleColor,
                        tickerLabelColor:
                            tickerStyle?.recipe.styleLabelBackground,
                        headlineShadows: headlineShadows,
                        tickerShadows: tickerShadows,
                        reporterPhotoPath: project.reporterPhotoPath,
                        reporterName: project.reporterName,
                        reporterFontFamily: reporterFamily,
                        logoRotate: previewPreset.logoRotate,
                      )
                    // v1.5.0 (#32): the user's own video/photo sits
                    // in the template's main area — the same
                    // composite the export renders.
                    : TemplateMediaPreview(
                        key: const Key('makerMediaPreview'),
                        preset: previewPreset,
                        mediaPaths: project.clipPaths,
                        fontReady: _fontReady,
                        height: 300,
                        elementOverrides: project.elementOverrides,
                        tickerLabel: project.tickerLabel.isEmpty
                            ? null
                            : project.tickerLabel,
                        headlineFontFamily: headlineFamily,
                        tickerFontFamily: tickerFamily,
                        headlineTextColor:
                            headlineStyle?.recipe.styleColor,
                        tickerTextColor: tickerStyle?.recipe.styleColor,
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
                        height: 300,
                      )
                    : ClassicPreview(
                        key: const Key('makerClassicPreview'),
                        preset: previewPreset,
                        fontReady: _fontReady,
                        height: 300,
                      ),
          ),
        ),
        const SizedBox(height: 10),
        // v1.5.0 (#32): the three controls the user asked for,
        // always visible right under the preview — Add Video (own
        // footage into the main area), Templates, Ribbons.
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('makerAddVideoButton'),
                onPressed: () => _showClipsSheet(project),
                icon: const Icon(Icons.add),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Add Video'),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('makerTemplatesButton'),
                onPressed: () => _showTemplatesSheet(project),
                icon: const Icon(Icons.dashboard_customize_outlined),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Templates'),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('makerRibbonsButton'),
                onPressed: _showRibbonsSheet,
                icon: const Icon(Icons.view_agenda_outlined),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Ribbons'),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _toolLine(),
        const SizedBox(height: 14),
        switch (_activeTool) {
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
          _ => _summaryCard(preset, project, templateLabel),
        },
      ],
    );
  }

  /// Template panel (NS3): the three template choices + Breaking
  /// variants + the shared Templates sheet + the ONE Template &
  /// Studio entry (moved here from the old bottom row — #45).
  Widget _templatePanel(ChannelPreset preset, NewsProject project) {
    return _panelShell('Template', [
      Row(
        children: [
          _templateChoice(
            kind: 'nigraanFinal',
            label: 'Final 3-Ribbon',
            project: project,
          ),
          const SizedBox(width: 8),
          _templateChoice(
            kind: 'breaking',
            label: 'Breaking',
            project: project,
          ),
          const SizedBox(width: 8),
          _templateChoice(
            kind: 'classic',
            label: 'Classic',
            project: project,
          ),
        ],
      ),
      if (project.templateKind == 'breaking') ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: BreakingVariant.values.map((variant) {
            final selected = project.breakingVariant == variant.id;
            return ChoiceChip(
              key: Key('makerBreakingVariant-${variant.id}'),
              label: Text(variant.label),
              selected: selected,
              onSelected: (_) {
                setState(() => project.breakingVariant = variant.id);
                _scheduleSave();
              },
            );
          }).toList(),
        ),
      ],
      const SizedBox(height: 12),
      OutlinedButton.icon(
        key: const Key('makerTemplatesSheetButton'),
        onPressed: () => _showTemplatesSheet(project),
        icon: const Icon(Icons.storefront_outlined, size: 18),
        label: const Text('Templates — Store / Library'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const Key('templateStudioButton'),
        onPressed: () async {
          await _saveNow();
          if (!mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const TemplateStudioScreen(),
            ),
          );
          await _reloadPreset();
        },
        icon: const Icon(Icons.tune_outlined, size: 18),
        label: const Text('Template & Studio →'),
      ),
      const SizedBox(height: 8),
      const Text(
        'Final 3-Ribbon = channel ka asal design (yellow / red / '
        'navy). Breaking aur Classic apni styles rakhte hain.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
    ]);
  }

  /// Media panel: the clip list (the quick-row Add Video sheet
  /// edits the SAME list) + the Library Effect picker (#52 — the
  /// effect lands on the main media; a grade shows in the
  /// preview, an overlay blends in the export).
  Widget _mediaPanel(NewsProject project) {
    return _panelShell('Media', [
      const Text(
        'Clips & photos — pehli clip preview mein dikhti hai; '
        'export mein saari order se lagti hain.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const SizedBox(height: 8),
      ClipPickerList(
        paths: project.clipPaths,
        onChanged: (next) {
          setState(() => project.clipPaths = next);
          _scheduleSave();
        },
      ),
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
        emptyNote: 'Abhi koi Library effect nahi — Store ke '
            '"Effects" folder mein recipe wala item dalte hi '
            'yahan aa jayega.',
      ),
      const SizedBox(height: 6),
      const Text(
        'Grade effect preview mein bhi dikhta hai; overlay '
        '(light leak waghera) export mein blend hota hai.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
    ]);
  }

  /// Tehreer panel: the script field + headline font (#51) +
  /// headline Text Style (#52).
  Widget _tehreerPanel(NewsProject project) {
    final tehreer = _tehreerController.text;
    final langLabel =
        GeminiVoiceService.detectLang(tehreer) == 'ur' ? 'Urdu' : 'English';
    return _panelShell('Tehreer', [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Khabar ki tehreer — voiceover isi se banta hai.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          Text(
            '$langLabel • ${countWords(tehreer)} alfaz',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
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
          hintText: 'Tehreer yahan likhein ya paste karein…',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) {
          setState(() {});
          _scheduleSave();
        },
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
        emptyNote: 'Abhi koi Library text style nahi — Store ke '
            '"Text Styles" folder mein recipe wala item dalte hi '
            'yahan aa jayega.',
      ),
    ]);
  }

  /// Ticker panel: ticker text + Paste + the EDITABLE side label
  /// (#49) + ticker font (#51) + ticker Text Style (#52).
  Widget _tickerPanel(NewsProject project) {
    return _panelShell('Ticker', [
      const Text(
        'Ticker text — paste karein, chal jaye ga',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const Key('tickerField'),
              controller: _tickerController,
              decoration: const InputDecoration(
                hintText: 'Ticker text paste karein…',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                setState(() {});
                _scheduleSave();
              },
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('pasteTickerButton'),
            onPressed: _pasteTicker,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
            ),
            child: const Text('Paste'),
          ),
        ],
      ),
      const SizedBox(height: 14),
      const Text(
        'Side label (chip)',
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
          setState(() => project.tickerLabel = v.trim());
          _scheduleSave();
        },
      ),
      const Text(
        'Ye label ticker ke left chip mein aata hai — khaali '
        'chhorne par chip nahi banta. Preview + export dono mein.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const SizedBox(height: 14),
      const Text(
        'Ticker font',
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
        emptyNote: 'Abhi koi Library text style nahi — Store ke '
            '"Text Styles" folder mein recipe wala item dalte hi '
            'yahan aa jayega.',
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
      const Text(
        'Har ribbon ki height (size) alag se badlein — preview '
        'aur export dono mein lagta hai.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
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
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const Key('makerRibbonsSheetButton'),
        onPressed: _showRibbonsSheet,
        icon: const Icon(Icons.palette_outlined, size: 18),
        label: const Text('Ribbons — design / colours'),
      ),
    ]);
  }

  /// Logo panel (#47): pick / remove the channel logo, the
  /// rotate switch (preset), and the logo element's own
  /// position/size sliders (the preview also takes tap + drag).
  Widget _logoPanel(ChannelPreset preset, NewsProject project) {
    final logoOv = _elementOv(project, NewsElement.logo);
    final logoPath = preset.logoPath;
    final hasLogo = logoPath != null && File(logoPath).existsSync();
    return _panelShell('Logo', [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF181828),
              borderRadius: BorderRadius.circular(8),
            ),
            child: hasLogo
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
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasLogo
                  ? 'Apna logo laga hua hai — preview + export '
                      'mein yehi (rotate on ho to) ghoomta hai.'
                  : 'Abhi default Nigraan logo hai (Final template '
                      'ka apna rotating logo). Apna logo lagayein '
                      'to wahi preview + export mein aayega.',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              key: const Key('logoPickButton'),
              onPressed: _pickLogo,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Logo chunein'),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
              ),
            ),
          ),
          if (logoPath != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('logoRemoveButton'),
                onPressed: _removeLogo,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Logo hatayein'),
                ),
              ),
            ),
          ],
        ],
      ),
      SwitchListTile(
        key: const Key('logoRotateSwitch'),
        title: const Text('Logo rotate (3D swing)'),
        subtitle: const Text(
          'Preview + export dono mein logo ghoomta hai.',
        ),
        value: preset.logoRotate,
        onChanged: (v) async {
          preset.logoRotate = v;
          await persistPresetChange(preset);
          if (mounted) setState(() {});
        },
      ),
      const Text(
        'Position / size — preview mein logo par tap + drag bhi '
        'chalta hai:',
        style: TextStyle(color: Colors.grey, fontSize: 12),
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
    ]);
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
      await persistPresetChange(preset);
      if (!mounted) return;
      setState(() {});
      _showMessage('Logo lag gaya — preview mein dekhein.');
    } catch (e) {
      _showMessage('Logo nahi laga: $e');
    }
  }

  Future<void> _removeLogo() async {
    final preset = _preset;
    if (preset == null) return;
    preset.logoPath = null;
    await persistPresetChange(preset);
    if (!mounted) return;
    setState(() {});
  }

  /// Reporter panel (NS7, #50): photo slot opposite the logo,
  /// BG Remove (BiRefNet) / BG Replace, the name plate field +
  /// its font, and the reporter element's position/size sliders.
  Widget _reporterPanel(NewsProject project) {
    final photo = project.reporterPhotoPath;
    final repOv = _elementOv(project, NewsElement.reporter);
    return _panelShell('Reporter', [
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
                      photo == null ? 'Photo lagayen' : 'Photo badlein',
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
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
          'Background colour chunein:',
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
      const SizedBox(height: 14),
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
          hintText: 'Reporter ka naam likhein…',
          border: OutlineInputBorder(),
        ),
        onChanged: (v) {
          setState(() => project.reporterName = v);
          _scheduleSave();
        },
      ),
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
        'Position / size — photo lagte hi block khud sahi jagah '
        'aa jata hai (logo ke opposite); sliders se fine-tune '
        'karein:',
        style: TextStyle(color: Colors.grey, fontSize: 12),
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
          label: const Text('Reporter hatayein'),
        ),
      ],
    ]);
  }

  Future<void> _pickReporterPhoto() async {
    final project = _project;
    if (project == null || _reporterBusy) return;
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty || picked.first.path == null) return;
    final copied = await copyReporterPhoto(picked.first.path!);
    if (!mounted) return;
    if (copied == null) {
      _showMessage('Photo copy nahi hui — dobara try karein.');
      return;
    }
    setState(() {
      project.reporterPhotoPath = copied;
      _reporterStatus = 'Photo lag gaya — block preview mein '
          'logo ke opposite aa gaya hai.';
    });
    _scheduleSave();
  }

  Future<void> _reporterBgRemove() async {
    final project = _project;
    final photo = project?.reporterPhotoPath;
    if (project == null || photo == null || _reporterBusy) return;
    setState(() {
      _reporterBusy = true;
      _reporterStatus = 'Background remove ho raha hai — pehli '
          'dafa model pack download hoga, thora waqt lagega…';
    });
    try {
      final out = await reporterRemoveBackground(photo);
      if (!mounted) return;
      setState(() {
        project.reporterPhotoPath = out;
        _reporterStatus = 'Background remove ho gaya.';
      });
      _scheduleSave();
    } on ReporterBgException catch (e) {
      if (mounted) setState(() => _reporterStatus = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _reporterStatus = 'BG remove nahi hua: $e');
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
      _reporterStatus = 'Background badla ja raha hai…';
    });
    try {
      final out = await reporterReplaceBackground(
        photo,
        colorArgb: argb,
      );
      if (!mounted) return;
      setState(() {
        project.reporterPhotoPath = out;
        _reporterStatus = 'Background badal gaya.';
        _reporterShowBgChoices = false;
      });
      _scheduleSave();
    } on ReporterBgException catch (e) {
      if (mounted) setState(() => _reporterStatus = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _reporterStatus = 'BG replace nahi hua: $e');
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
      _reporterStatus = 'Background photo lagayi ja rahi hai…';
    });
    try {
      final out = await reporterReplaceBackground(
        photo,
        bgImagePath: picked.first.path!,
      );
      if (!mounted) return;
      setState(() {
        project.reporterPhotoPath = out;
        _reporterStatus = 'Background photo lag gayi.';
        _reporterShowBgChoices = false;
      });
      _scheduleSave();
    } on ReporterBgException catch (e) {
      if (mounted) setState(() => _reporterStatus = e.message);
    } catch (e) {
      if (mounted) {
        setState(() => _reporterStatus = 'BG replace nahi hua: $e');
      }
    } finally {
      if (mounted) setState(() => _reporterBusy = false);
    }
  }

  /// Audio panel (NS4): the v1.4.0 trio — Record / Import /
  /// Text se Audio, all landing in the one voiceover slot.
  Widget _audioPanel(NewsProject project) {
    return _panelShell('Audio', [
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              key: const Key('audioRecordButton'),
              onPressed: _voiceBusy ? null : _toggleRecord,
              icon: Icon(_recording ? Icons.stop : Icons.mic),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_recording ? 'Stop' : 'Record'),
              ),
              style: FilledButton.styleFrom(
                backgroundColor:
                    _recording ? Colors.redAccent : const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('audioImportButton'),
              onPressed: _voiceBusy ? null : _importAudio,
              icon: const Icon(Icons.audio_file_outlined),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Import'),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('audioTtsButton'),
              onPressed: _voiceBusy ? null : _buildSelectedVoice,
              icon: const Icon(Icons.record_voice_over_outlined),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Text se Audio'),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
      if (_recording)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Icon(Icons.fiber_manual_record,
                  color: Colors.redAccent, size: 14),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Recording ho rahi hai… Stop dabane par '
                  'voiceover lag jayega.',
                  style: TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      const SizedBox(height: 8),
      const Text(
        'Record = apni awaz, Import = phone se audio file, '
        'Text se Audio = tehreer se AI voice — Voice tool mein '
        'chuni hui awaz mein (nayi voice par 50 coins). Teeno ka '
        'result Voice tool ke preview mein sun sakte hain.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
    ]);
  }

  /// Voice panel: the unified 8-voice catalogue (#19) + speed /
  /// pause / music controls + status + the preview player.
  Widget _voicePanel(NewsProject project) {
    return _panelShell('Voice', [
      const Text(
        'Awaz chunein — yahi selection "Text se Audio" use '
        'karti hai.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: StudioVoice.all
            .map((v) => _studioVoiceChip(v))
            .toList(),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          const Expanded(child: Text('Speed')),
          SizedBox(
            width: 200,
            child: Slider(
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
          Text('${project.voiceSpeed.toStringAsFixed(2)}x'),
        ],
      ),
      Row(
        children: [
          const Expanded(child: Text('Pause (sentences ke beech)')),
          SizedBox(
            width: 200,
            child: Slider(
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
          Text('${project.voicePauseSec.toStringAsFixed(1)}s'),
        ],
      ),
      SwitchListTile(
        key: const Key('voiceMusicSwitch'),
        title: const Text('Background music (soft pad)'),
        subtitle: const Text(
          'Halki si ambient music voice ke neeche.',
        ),
        value: project.voiceMusic,
        onChanged: (v) {
          setState(() => project.voiceMusic = v);
          _scheduleSave();
        },
      ),
      const Text(
        'Speed resample pitch bhi badalta hai — ye normal hai.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
      if (_voiceBusy) ...[
        const SizedBox(height: 8),
        const LinearProgressIndicator(
          key: Key('voiceBusyProgress'),
          minHeight: 3,
        ),
      ],
      // v1.5.0 (#18): the status line renders ONLY for a real
      // status — the default 'Abhi voice nahi bani.' text is NOT
      // repeated here; the VoicePreviewPlayer's empty card below
      // is the one place that message lives.
      if (_voiceStatus != 'Abhi voice nahi bani.') ...[
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
            'Aaj ki voice limit: $_voiceRemaining / 5 baaki',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      if (ProService.instance.proActive)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            'Pro active: AI voice ki roz limit '
            '${ProService.instance.limitFor(5, 25)}/day hai.',
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
      const SizedBox(height: 4),
      const Text(
        '"Dobara" cached voice delete kar ke nayi banata hai — '
        'nayi proxy request(s) lagti hain.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      ),
    ]);
  }

  /// Captions panel: the karaoke-sync summary + the ONE
  /// Caption Studio entry.
  Widget _captionsPanel(NewsProject project) {
    return _panelShell('Captions', [
      Row(
        children: [
          Expanded(
            child: Text(
              project.subtitles.isEmpty
                  ? 'Abhi koi subtitles nahi — voiceover banayein, '
                      'phir subtitles us ki real length se sync '
                      'honge.'
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
    ]);
  }

  /// Export panel: the Library Transition picker (#52 — applied
  /// between the clips in the export) + the real ReelExportCard
  /// + the ONE SEO entry (moved here from the old bottom row).
  Widget _exportPanel(ChannelPreset preset, NewsProject project) {
    return _panelShell('Export', [
      const Text(
        'Transition (Library) — clips ke beech',
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
        emptyNote: 'Abhi koi Library transition nahi — Store ke '
            '"Transitions" folder mein recipe wala item dalte '
            'hi yahan aa jayega. Baghair transition ke clips '
            'seedha join hote hain.',
      ),
      const SizedBox(height: 16),
      ReelExportCard(project: project, preset: preset),
      const SizedBox(height: 12),
      FilledButton.icon(
        key: const Key('seoButton'),
        onPressed: _openSeo,
        icon: const Icon(Icons.trending_up_outlined, size: 18),
        label: const Text('SEO →'),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF7C3AED),
          foregroundColor: Colors.white,
        ),
      ),
    ]);
  }

  /// v1.5.1 (#51/#52): registers the user's uploaded fonts in
  /// this process, warms the project's three font choices (so
  /// google_fonts families are live for the preview + the parity
  /// export), and loads the Library listings (cache-first).
  Future<void> _initFontsAndLibrary() async {
    try {
      await UserFontService.instance.loadAll();
      await UserFontService.instance.syncIntoRegistry();
    } catch (_) {
      // Fonts are fail-soft — the pickers still show built-ins.
    }
    final project = _project;
    if (project != null) {
      _warmFont(project.headlineFontId);
      _warmFont(project.tickerFontId);
      _warmFont(project.reporterFontId);
    }
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

  /// Template picker chip — persists the choice on the project
  /// (Phase 6: the preview above re-renders from it immediately).
  Widget _templateChoice({
    required String kind,
    required String label,
    required NewsProject project,
  }) {
    final selected = project.templateKind == kind;
    return Expanded(
      child: InkWell(
        key: Key('makerTemplateChoice-$kind'),
        onTap: () {
          setState(() {
            project.templateKind = kind;
            project.breaking = kind == 'breaking';
          });
          _scheduleSave();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFF7C3AED)
                : const Color(0xFF181828),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? const Color(0xFF7C3AED) : Colors.white24,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                // v1.5.0 (#21): scale-to-fit instead of ellipsis —
                // 'Final 3-Ribbon' was truncated to 'Final 3-Rib…'.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 4),
                const Icon(Icons.check, size: 16),
              ],
            ],
          ),
        ),
      ),
    );
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
          color: selected
              ? const Color(0xFF7C3AED)
              : const Color(0xFF181828),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF7C3AED) : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${v.label} • ${v.gender}'
              '${v.engine == StudioTtsEngine.edge ? ' • Free' : ''}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (selected) ...[
              const SizedBox(width: 4),
              const Icon(Icons.check, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}
