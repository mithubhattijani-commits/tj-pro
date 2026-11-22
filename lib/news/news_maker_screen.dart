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
import 'news_project.dart';
import 'seo_screen.dart';
import 'template_studio_screen.dart';
import 'widgets/breaking_preview.dart';
import 'widgets/clip_picker.dart';
import 'widgets/nigraan_final_preview.dart';
import 'widgets/reel_export_card.dart';
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

  @override
  void initState() {
    super.initState();
    final preset = widget.initialPreset;
    final project = widget.initialProject;
    if (preset != null || project != null) {
      _preset = preset ?? ChannelPreset.nigraanTv();
      _project = project ?? NewsProject.create(presetId: _preset!.id);
      _voice = _project!.voice;
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
  /// Edge voices in [TtsStudioService] (Asad/Uzma, matched to the
  /// selected Gemini voice's gender). COSTS COINS like the Gemini
  /// path ([CoinFeature.voiceover], charged when the result is
  /// not a cache hit); a failed spend attaches nothing.
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
        voice: _voice == GeminiVoice.charon
            ? StudioVoice.asad
            : StudioVoice.uzma,
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

  /// Trio option 3 — chooser: Gemini AI voice (the existing flow
  /// below) or the free Edge TTS voices. Both cost coins for a new
  /// voice; both land in the same voiceover slot.
  Future<void> _showTextToAudioChooser() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Text se Audio — engine chunein'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'gemini'),
            child: const Text('Gemini AI voice (50 coins)'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'free'),
            child: const Text('Free TTS — Asad/Uzma (50 coins)'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'gemini') {
      await _buildVoice();
    } else if (choice == 'free') {
      await _buildFreeTtsVoice();
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
    await NewsProjectStore.save(project);
    if (!mounted) return;
    final now = DateTime.now();
    setState(
      () => _saveStatus =
          'Saved • ${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}',
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
          child: project.templateKind == 'nigraanFinal'
              ? NigraanFinalPreview(
                  preset: previewPreset,
                  fontReady: _fontReady,
                  height: 300,
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
                  hintText: 'Ticker text yahan paste karein…',
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
                label: Text(_recording ? 'Stop' : 'Record'),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      _recording ? Colors.redAccent : const Color(0xFF7C3AED),
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
                label: const Text('Import'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('audioTtsButton'),
                onPressed: _voiceBusy ? null : _showTextToAudioChooser,
                icon: const Icon(Icons.record_voice_over_outlined),
                label: const Text('Text se Audio'),
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
          'Text se Audio = tehreer se AI voice (nayi voice par '
          '50 coins). Teeno ka result neeche preview mein sun sakte hain.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 20),
        const Text(
          'Voiceover — Gemini',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _voiceChoice(
                voice: GeminiVoice.aoede,
                label: 'Aoede • Female',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _voiceChoice(
                voice: GeminiVoice.charon,
                label: 'Charon • Male',
              ),
            ),
          ],
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
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('voiceBuildButton'),
            onPressed: _voiceBusy ? null : () => _buildVoice(),
            icon: _voiceBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_voiceBusy ? 'Voice ban rahi hai…' : 'Voice banao'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _voiceStatus,
          key: const Key('voiceStatus'),
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
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
          voiceLabel: _voice.apiName,
          regenerating: _voiceBusy,
          onRegenerate: () => _buildVoice(regenerate: true),
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
          'Clips',
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
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

  Widget _voiceChoice({required GeminiVoice voice, required String label}) {
    final selected = _voice == voice;
    return InkWell(
      key: Key('voiceChoice-${voice.apiName}'),
      onTap: () {
        setState(() => _voice = voice);
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
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
