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
import '../services/gemini_voice_service.dart';
import '../services/pro_service.dart';
import '../services/tts_processing.dart';
import '../services/tts_studio_service.dart';
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
import 'widgets/nigraan_final_preview.dart';
import 'widgets/reel_export_card.dart';
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
      _loaded = true;
      _refreshVoiceStatus();
      _checkFont();
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
      _loaded = true;
    });
    await _refreshVoiceStatus();
    await _checkFont();
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
    if (hit != null) setState(() => _selectedElement = hit);
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
  /// corner-handle resize), hide/show (= remove), reset, and the
  /// Add row (video/photo via the clips sheet, text, watermark).
  Widget _elementsPanel(NewsProject project) {
    final sel = _selectedElement;
    final ov = _elementOv(project, sel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Elements — manual control',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (project.elementOverrides.isNotEmpty)
              TextButton(
                onPressed: () {
                  setState(() => project.elementOverrides.clear());
                  _scheduleSave();
                },
                child: const Text('Reset all'),
              ),
          ],
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
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _showClipsSheet(project),
                icon: const Icon(Icons.video_call_outlined, size: 18),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Add Video'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  _setElementOverride(
                    NewsElement.headlineText,
                    _elementOv(project, NewsElement.headlineText)
                        .copyWith(hidden: false),
                  );
                  setState(
                    () => _selectedElement = NewsElement.headlineText,
                  );
                  _showMessage(
                    'Headline text select ho gaya — Tehreer se '
                    'headline aati hai.',
                  );
                },
                icon: const Icon(Icons.text_fields, size: 18),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Add Text'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final preset = _preset;
                  if (preset == null) return;
                  preset.watermarkEnabled = true;
                  await persistPresetChange(preset);
                  _setElementOverride(
                    NewsElement.overlay,
                    _elementOv(project, NewsElement.overlay)
                        .copyWith(hidden: false),
                  );
                  setState(
                    () => _selectedElement = NewsElement.overlay,
                  );
                },
                icon: const Icon(Icons.branding_watermark, size: 18),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Add Watermark'),
                ),
              ),
            ),
          ],
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

  Widget _buildBody(ChannelPreset preset, NewsProject project) {
    final previewPreset = _previewPreset();
    final tehreer = _tehreerController.text;
    final langLabel =
        GeminiVoiceService.detectLang(tehreer) == 'ur' ? 'Urdu' : 'English';
    final templateLabel = project.templateKind == 'nigraanFinal'
        ? 'Final 3-Ribbon'
        : project.templateKind == 'breaking'
            ? 'Breaking • ${BreakingVariant.fromId(project.breakingVariant).label}'
            : 'Classic';
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
        const Text(
          'Template',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
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
        const Text(
          'Preview',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
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
                    )
                  // v1.5.0 (#32): the user's own video/photo sits in
                  // the template's main area — the same composite
                  // the export renders.
                  : TemplateMediaPreview(
                      key: const Key('makerMediaPreview'),
                      preset: previewPreset,
                      mediaPaths: project.clipPaths,
                      fontReady: _fontReady,
                      height: 300,
                      elementOverrides: project.elementOverrides,
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
        const SizedBox(height: 20),
        _elementsPanel(project),
        const SizedBox(height: 20),
        Row(
          children: [
            const Text(
              'Tehreer',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
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
        const SizedBox(height: 20),
        const Text(
          'Ticker text — paste karein, chal jaye ga',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('tickerField'),
                controller: _tickerController,
                decoration: const InputDecoration(
                  // v1.5.0 (#22): shorter hint — the long one was
                  // truncated mid-word in the field.
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
                // v1.5.0 (#22): explicit white label — the theme
                // default left it washed out on the violet fill.
                foregroundColor: Colors.white,
              ),
              child: const Text('Paste'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // v1.4.0 audio trio (requirements #6): Record / Import /
        // Text se Audio — teeno ek hi voiceover slot mein jate
        // hain; jo bhi source ho, neeche wala preview player aur
        // export usi ko use karte hain.
        const Text(
          'Audio — 3 options',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const Key('audioRecordButton'),
                onPressed: _voiceBusy ? null : _toggleRecord,
                icon: Icon(_recording ? Icons.stop : Icons.mic),
                // v1.5.0 (#17): labels scale down to fit the pill —
                // never clipped, never wrapped.
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
                // v1.5.0: this pill IS the generate action now —
                // it builds with the voice selected in the chips
                // below (the chooser dialog is gone).
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
                Text(
                  'Recording ho rahi hai… Stop dabane par voiceover lag jayega.',
                  style: TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
            ),
          ),
        const Text(
          'Record = apni awaz, Import = phone se audio file, '
          'Text se Audio = tehreer se AI voice — neeche chuni hui '
          'awaz mein (nayi voice par 50 coins). Teeno ka result '
          'neeche preview mein sun sakte hain.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 20),
        const Text(
          'Voiceover — awaz chunein',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        // v1.5.0 (#19): the ONE unified 8-voice catalogue — the
        // same StudioVoice.all the AI Voice Studio shows (6 Gemini
        // + Asad/Uzma free TTS). One selection drives both build
        // paths; there is no second voice list anywhere.
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
        // v1.5.0 (dedupe): the separate "Voice banao" button is
        // REMOVED — it duplicated the trio's "Text se Audio" pill
        // (two controls, one action). Building shows progress here;
        // the pill above is the one generate control.
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
        // Cap line: non-admins only. Admins get -1 (unlimited)
        // from remainingToday() and see nothing here.
        if (_voiceRemaining != null && _voiceRemaining != -1)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Aaj ki voice limit: $_voiceRemaining / 5 baaki',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
        // v1.4.0 PRO: Pro users get the raised daily AI-voice cap
        // (ProService.limitFor — free 5/day, Pro 25/day).
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
          // "Dobara" rebuilds with the SELECTED voice's engine —
          // Gemini regenerates (cache deleted, costs again); the
          // Edge path rebuilds through free TTS.
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
        const SizedBox(height: 20),
        const Text(
          'Subtitles — karaoke sync',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                project.subtitles.isEmpty
                    ? 'Abhi koi subtitles nahi — voiceover banayein, phir '
                        'subtitles us ki real length se sync honge.'
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
        const SizedBox(height: 20),
        const Text(
          // v1.5.0 (#32): named for what it is — the user's own
          // footage for the template's main area.
          'Add Video — clips & photos',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ClipPickerList(
          paths: project.clipPaths,
          onChanged: (next) {
            setState(() => project.clipPaths = next);
            _scheduleSave();
          },
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
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
                child: const Text('Template & Studio →'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                key: const Key('seoButton'),
                onPressed: _openSeo,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                ),
                child: const Text('SEO →'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Phase 7 — real export + timeline handoff (no fake buttons):
        // "Export Reel" runs the FFmpeg reel export, "Open in
        // Timeline" opens the video editor with this project loaded.
        ReelExportCard(project: project, preset: preset),
      ],
    );
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
