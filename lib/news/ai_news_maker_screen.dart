/// One Click AI News Maker (Phase 4, mockup 8 + master prompt §3).
///
/// Paste tehreer → 13-step checklist with REAL implementations — no
/// fake steps. Every auto element has a manual edit control (tap a
/// step to expand it):
///
///   1.  Analyze — rules-based topic extraction (Urdu stopwords +
///       frequency + proper nouns, §13 — zero quota).
///   2.  Headline — extractive (strongest first line, editable).
///   3.  Summary — extractive (2 lines, editable).
///   4.  Voiceover — real [GeminiVoiceService] (same as News Maker).
///   5.  Subtitles — tehreer split into timed lines (BASIC split
///       until the voiceover exists; then karaoke sync re-times
///       them against the REAL voiceover duration — Phase 5).
///   6.  Media — topic keywords shown + gallery clip picker. The
///       "suggestion" IS the extracted keywords; a full AI media
///       search (stock/AI footage matched to the story) is a later
///       phase — the code comment on the step says so honestly.
///   7.  Graphics — template apply (nigraanFinal / breaking variant).
///   8.  Branding — preset logo/colours applied (from the channel
///       preset; edit in the News Maker's Template panel).
///   9.  Ticker — paste-to-run text (same contract as Phase 3).
///   10. Breaking — toggle → breaking template.
///   11. Timeline — project assembly (same project JSON as News Maker)
///       + a real "Open in Timeline" button (Phase 7 handoff).
///   12. Preview — voice + clips + template preview.
///   13. Export — the real reel export card (Phase 7): quality
///       selector + "Export Reel" (FFmpeg) + intro state. No fake
///       Export: the button runs the real export or is absent.
///
/// Fact-check card: the user attaches sources (URL/text, add/remove)
/// and the card lists them. The app does NOT auto-verify anything —
/// no verification call exists; the card says so.
///
/// One click runs steps 1–12 (voiceover included — it costs proxy
/// request(s) against the 5/day cap, and the button says so; a cached
/// tehreer costs 0). "Manual Edit" opens the same project in the
/// News Maker editor.
///
/// COINS (Phase 10): one run costs 100 coins ([CoinFeature.oneClick])
/// — spent BEFORE the run starts, and it COVERS the run's voiceover
/// step (no separate 50-coin voiceover charge inside a run). A
/// standalone "Voice banao" tap costs 50 coins unless the voice is
/// cached (see [_buildVoice]). Admins are waived server-side.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/asset_download_service.dart';
import '../services/coin_service.dart';
import '../services/gemini_voice_service.dart';
import '../video/video_editor_screen.dart';
import 'breaking_templates.dart';
import 'caption_studio_screen.dart';
import 'channel_preset.dart';
import 'karaoke_sync.dart';
import 'news_analysis.dart';
import 'news_maker_screen.dart';
// Build 5 (v1.5.7): the template_studio_screen import is gone —
// that screen is retired (see brandingEditButton below).
import 'news_project.dart';
import 'widgets/breaking_preview.dart';
import 'widgets/clip_picker.dart';
import 'widgets/studio_pickers.dart';
import 'widgets/nigraan_final_preview.dart';
import 'widgets/reel_export_card.dart';
import 'widgets/voice_preview_player.dart';

/// The 13 AI Maker steps, in mockup-8 order.
const List<(String, String)> aiMakerSteps = [
  ('analyze', 'Analyze text'),
  ('headline', 'Headline'),
  ('summary', 'Summary'),
  ('voiceover', 'Voiceover'),
  ('subtitles', 'Subtitles'),
  ('media', 'Images & video'),
  ('graphics', 'News graphics'),
  ('branding', 'Branding'),
  ('ticker', 'Ticker'),
  ('breaking', 'Breaking graphics'),
  ('timeline', 'Timeline'),
  ('preview', 'Preview'),
  ('export', 'Export'),
];

class AiNewsMakerScreen extends StatefulWidget {
  /// Test/deep-link seams (same pattern as NewsMakerScreen).
  const AiNewsMakerScreen({super.key, this.initialPreset, this.initialProject});

  final ChannelPreset? initialPreset;
  final NewsProject? initialProject;

  @override
  State<AiNewsMakerScreen> createState() => _AiNewsMakerScreenState();
}

class _AiNewsMakerScreenState extends State<AiNewsMakerScreen> {
  ChannelPreset? _preset;
  NewsProject? _project;
  bool _loaded = false;
  bool _fontReady = false;

  final _tehreerController = TextEditingController();
  final _headlineController = TextEditingController();
  final _summaryController = TextEditingController();
  final _tickerController = TextEditingController();
  final _topicAddController = TextEditingController();
  final _sourceLabelController = TextEditingController();
  final _sourceValueController = TextEditingController();
  String _sourceKind = 'url';

  List<String> _topics = [];
  List<TextEditingController> _subtitleControllers = [];

  GeminiVoice _voice = GeminiVoice.aoede;
  bool _voiceBusy = false;
  String _voiceStatus = 'Abhi voice nahi bani.';
  int? _voiceRemaining;

  bool _analysisRunning = false;
  bool _analysisRun = false;
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
      _applyProjectToControllers();
      _loaded = true;
      _refreshVoiceStatus();
      _checkFont();
    } else {
      _load();
    }
  }

  void _applyProjectToControllers() {
    final project = _project!;
    _voice = project.voice;
    _tehreerController.text = project.tehreer;
    _headlineController.text = project.headline;
    _summaryController.text = project.summary;
    _tickerController.text = project.tickerText;
    if (project.tehreer.trim().isNotEmpty) {
      _topics = extractTopics(project.tehreer);
    }
    if (project.headline.isNotEmpty ||
        project.summary.isNotEmpty ||
        project.subtitles.isNotEmpty) {
      _analysisRun = true;
    }
    _syncSubtitleControllers();
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
    });
    _applyProjectToControllers();
    setState(() => _loaded = true);
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
    _tehreerController.dispose();
    _headlineController.dispose();
    _summaryController.dispose();
    _tickerController.dispose();
    _topicAddController.dispose();
    _sourceLabelController.dispose();
    _sourceValueController.dispose();
    for (final c in _subtitleControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _syncSubtitleControllers() {
    final project = _project;
    if (project == null) return;
    for (final c in _subtitleControllers) {
      c.dispose();
    }
    _subtitleControllers = project.subtitles
        .map((s) => TextEditingController(text: s.text))
        .toList();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveNow);
  }

  Future<void> _saveNow() async {
    final project = _project;
    if (project == null) return;
    project.tehreer = _tehreerController.text;
    project.headline = _headlineController.text;
    project.summary = _summaryController.text;
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

  /// Runs steps 1–3 + 5–12 synchronously (rules only, zero quota),
  /// then step 4 (voiceover — real proxy call, cached = 0 calls).
  /// Step 13 (Export) is never run — it is Phase 7.
  Future<void> _runAnalysis() async {
    final project = _project;
    if (project == null || _analysisRunning) return;
    final text = _tehreerController.text.trim();
    if (text.isEmpty) {
      _showMessage('Pehle tehreer paste karein.');
      return;
    }
    // COINS (Phase 10): the 100-coin One Click charge lands BEFORE
    // the run — it covers the whole 13-step flow including the
    // voiceover step, so _buildVoice is called with skipCoinSpend.
    final spendResult =
        await CoinService.instance.spend(CoinFeature.oneClick);
    if (!spendResult.ok) {
      _showMessage(
        'Coins kam hain — One Click AI News Maker ke liye 100 coins '
        'chahiye. Watch Ads se kamayein.',
      );
      return;
    }
    setState(() => _analysisRunning = true);
    try {
      final topics = extractTopics(text);
      final headline = extractHeadline(text);
      final summary = extractSummary(text);
      final subtitles = splitSubtitles(text);
      project.tehreer = text;
      project.headline = headline;
      project.summary = summary;
      project.subtitles = subtitles;
      if (_tickerController.text.trim().isEmpty) {
        project.tickerText = headline;
        _tickerController.text = headline;
      }
      project.templateKind =
          project.breaking ? 'breaking' : 'nigraanFinal';
      setState(() {
        _topics = topics;
        _headlineController.text = headline;
        _summaryController.text = summary;
        _analysisRun = true;
      });
      _syncSubtitleControllers();
      // Fire-and-forget: the analysis must not stall on disk I/O
      // (the debounced autosave covers persistence).
      _saveNow();
      // Step 4 — the only quota-costing step. A cached tehreer
      // returns with 0 new calls. The One Click charge already
      // covered this voiceover, so no second spend here.
      await _buildVoice(skipCoinSpend: true);
    } finally {
      if (mounted) setState(() => _analysisRunning = false);
    }
  }

  /// Real voiceover build (same as News Maker — see its file header).
  ///
  /// COINS (Phase 10): a standalone build costs 50 coins
  /// ([CoinFeature.voiceover]) unless the voice is already cached
  /// (same tehreer + voice → [GeminiVoiceService.hasCachedVoice]).
  /// [skipCoinSpend] is true only when the caller already charged
  /// for the voiceover — the One Click run, whose 100-coin charge
  /// covers this step.
  Future<void> _buildVoice({
    bool regenerate = false,
    bool skipCoinSpend = false,
  }) async {
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
      final cached = regenerate
          ? false
          : await GeminiVoiceService().hasCachedVoice(
              text,
              voice: _voice,
            );
      if (!cached && !skipCoinSpend) {
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
      );
      final duration = wavDurationSeconds(result.file);
      final remaining = await GeminiVoiceService().remainingToday();
      if (!mounted) return;
      // Karaoke sync (Phase 5): the real voiceover duration re-times
      // the subtitles (translations survive the re-time).
      var syncNote = '';
      if (duration != null &&
          duration > 0 &&
          project.subtitles.isNotEmpty) {
        project.subtitles =
            resyncExistingLines(project.subtitles, duration);
        _syncSubtitleControllers();
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

  Future<void> _pasteTehreer() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _showMessage('Clipboard khaali hai — pehle text copy karein.');
      return;
    }
    setState(() => _tehreerController.text = text);
    _scheduleSave();
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

  /// Per-step status, derived live from the project state — never a
  /// stored flag that can drift from the real data.
  ({bool done, bool running, bool blocked}) _stepState(String id) {
    final project = _project;
    if (project == null) return (done: false, running: false, blocked: false);
    switch (id) {
      case 'analyze':
        return (done: _topics.isNotEmpty, running: false, blocked: false);
      case 'headline':
        return (
          done: _headlineController.text.trim().isNotEmpty,
          running: false,
          blocked: false,
        );
      case 'summary':
        return (
          done: _summaryController.text.trim().isNotEmpty,
          running: false,
          blocked: false,
        );
      case 'voiceover':
        return (
          done: project.voiceoverPath != null,
          running: _voiceBusy,
          blocked: false,
        );
      case 'subtitles':
        return (
          done: project.subtitles.isNotEmpty,
          running: false,
          blocked: false,
        );
      case 'media':
        // Done when the topic keywords exist — the "suggestion" is
        // the extracted keywords; clips themselves are optional.
        return (done: _topics.isNotEmpty, running: false, blocked: false);
      case 'graphics':
      case 'branding':
      case 'ticker':
        return (
          done: id == 'ticker'
              ? _tickerController.text.trim().isNotEmpty
              : _analysisRun,
          running: false,
          blocked: false,
        );
      case 'breaking':
        return (done: _analysisRun, running: false, blocked: false);
      case 'timeline':
      case 'preview':
        return (done: _analysisRun, running: false, blocked: false);
      case 'export':
        // Phase 7 — deliberately never "done" and never tappable.
        return (done: false, running: false, blocked: true);
      default:
        return (done: false, running: false, blocked: false);
    }
  }

  ChannelPreset _previewPreset() {
    final preset = ChannelPreset.fromJson(_preset!.toJson());
    final ticker = _tickerController.text.trim();
    preset.topRibbon.text =
        ticker.isEmpty ? _headlineController.text.trim() : ticker;
    preset.templateKind = _project!.templateKind;
    preset.showBreakingBanner = _project!.breaking;
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
          title: const Text('One Click AI News Maker'),
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
    final tehreer = _tehreerController.text;
    final langLabel =
        GeminiVoiceService.detectLang(tehreer) == 'ur' ? 'Urdu' : 'English';
    return ListView(
      key: const Key('aiMakerList'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        const Text(
          'Paste news → AI karta hai baaki',
          style: TextStyle(color: Colors.grey, fontSize: 13),
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
        Row(
          children: [
            const Text(
              'Paste news / tehreer',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TextButton(
              key: const Key('pasteTehreerButton'),
              onPressed: _pasteTehreer,
              child: const Text('Paste'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('aiTehreerField'),
          controller: _tehreerController,
          maxLines: 5,
          minLines: 5,
          textAlign: TextAlign.right,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(
            hintText: 'Tehreer yahan paste karein…',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) {
            setState(() {});
            _scheduleSave();
          },
        ),
        const SizedBox(height: 4),
        Text(
          '${countWords(tehreer)} alfaz • $langLabel',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('runAnalysisButton'),
            onPressed: _analysisRunning ? null : _runAnalysis,
            icon: _analysisRunning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
              _analysisRunning
                  ? 'AI Analysis chal rahi hai…'
                  : 'AI Analysis chalao (13 steps)',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Voiceover step mein proxy request(s) lagti hain'
          // Cap line: non-admins only. Admins get -1 (unlimited)
          // from remainingToday() and see no counter here.
          '${_voiceRemaining == null || _voiceRemaining == -1 ? '' : ' — Aaj ki voice limit: $_voiceRemaining / 5 baaki'}'
          ' — cached tehreer = 0 nayi calls.',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 16),
        const Text(
          'AI Analysis — 13 steps',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...aiMakerSteps.map((step) => _stepTile(step.$1, step.$2, project)),
        const SizedBox(height: 16),
        _factCheckCard(project),
        const SizedBox(height: 16),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Workflow',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 4),
                Text(
                  'Paste → Analyze → Headline → Voice → Ticker → '
                  'Subtitles → Graphics → Preview → Export',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('manualEditButton'),
                onPressed: () async {
                  await _saveNow();
                  if (!mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => NewsMakerScreen(
                        initialPreset: _preset,
                        initialProject: project,
                      ),
                    ),
                  );
                  final reloaded =
                      await NewsProjectStore.load(project.id);
                  if (reloaded != null && mounted) {
                    setState(() {
                      _project = reloaded;
                      _applyProjectToControllers();
                    });
                  }
                },
                child: const Text('Manual Edit'),
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Export • Phase 7 mein aayega',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _stepTile(String id, String label, NewsProject project) {
    final state = _stepState(id);
    final leading = state.blocked
        ? const Icon(Icons.hourglass_empty, color: Colors.grey)
        : state.running
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : state.done
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.radio_button_unchecked,
                    color: Colors.grey);
    return Card(
      key: Key('aiStep-$id'),
      margin: const EdgeInsets.only(bottom: 6),
      child: ExpansionTile(
        leading: leading,
        title: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: state.blocked ? Colors.grey : Colors.white,
          ),
        ),
        subtitle: state.blocked
            ? const Text(
                'Phase 7 mein aayega',
                style: TextStyle(color: Colors.grey),
              )
            : state.done
                ? const Text('Done', style: TextStyle(color: Colors.grey))
                : const Text(
                    'Abhi nahi hua — "AI Analysis chalao" dabayein',
                    style: TextStyle(color: Colors.grey),
                  ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _stepBody(id, project),
          ),
        ],
      ),
    );
  }

  Widget _stepBody(String id, NewsProject project) {
    switch (id) {
      case 'analyze':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Topics — rules-based extraction (zero quota). '
              'Chip hatayein ya apna topic add karein.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._topics.map(
                  (topic) => InputChip(
                    key: Key('topic-$topic'),
                    label: Text(topic),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () =>
                        setState(() => _topics.remove(topic)),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: TextField(
                    key: const Key('topicAddField'),
                    controller: _topicAddController,
                    decoration: const InputDecoration(
                      hintText: '+ topic',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (value) {
                      final topic = value.trim();
                      if (topic.isEmpty) return;
                      setState(() {
                        if (!_topics.contains(topic)) {
                          _topics.add(topic);
                        }
                        _topicAddController.clear();
                      });
                    },
                  ),
                ),
              ],
            ),
            if (_topics.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Abhi koi topic nahi — tehreer paste kar ke '
                  '"AI Analysis chalao" dabayein.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
          ],
        );
      case 'headline':
        return TextField(
          key: const Key('aiHeadlineField'),
          controller: _headlineController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Headline (auto — edit kar sakte hain)',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _scheduleSave(),
        );
      case 'summary':
        return TextField(
          key: const Key('aiSummaryField'),
          controller: _summaryController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Summary — 2 lines (auto — edit kar sakte hain)',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _scheduleSave(),
        );
      case 'voiceover':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('aiVoiceBuildButton'),
                onPressed: _voiceBusy ? null : () => _buildVoice(),
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  _voiceBusy ? 'Voice ban rahi hai…' : 'Voice banao',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _voiceStatus,
              key: const Key('aiVoiceStatus'),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            VoicePreviewPlayer(
              filePath: project.voiceoverPath,
              durationSec: project.voiceoverDurationSec,
              voiceLabel: _voice.apiName,
              regenerating: _voiceBusy,
              onRegenerate: () => _buildVoice(regenerate: true),
            ),
          ],
        );
      case 'subtitles':
        if (project.subtitles.isEmpty) {
          return const Text(
            'Abhi koi subtitles nahi — "AI Analysis chalao" dabayein '
            '(pehle basic split, phir voiceover se karaoke sync).',
            style: TextStyle(color: Colors.grey),
          );
        }
        final synced = project.voiceoverDurationSec != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    synced
                        ? 'Voiceover se synced — har line ki timing real '
                            'voiceover length se hai.'
                        : 'Basic split — voiceover bante hi timings us ki '
                            'real length se sync honge.',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('captionsButton'),
                  onPressed: () async {
                    await _saveNow();
                    if (!mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CaptionStudioScreen(
                          initialProject: project,
                        ),
                      ),
                    );
                    final reloaded =
                        await NewsProjectStore.load(project.id);
                    if (reloaded != null && mounted) {
                      setState(() => _project = reloaded);
                      _syncSubtitleControllers();
                    }
                  },
                  child: const Text('Captions →'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...List.generate(project.subtitles.length, (index) {
              final line = project.subtitles[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        key: Key('subtitleLine-$index'),
                        controller: _subtitleControllers[index],
                        decoration: InputDecoration(
                          labelText:
                              '${line.startSec.toStringAsFixed(1)}s – ${line.endSec.toStringAsFixed(1)}s',
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          // Text edit drops stale word timings (they no
                          // longer match the words), but the translation
                          // survives — same rule as CaptionEditor.
                          project.subtitles[index] = SubtitleLine(
                            text: value,
                            startSec: line.startSec,
                            endSec: line.endSec,
                            translation: line.translation,
                          );
                          _scheduleSave();
                        },
                      ),
                    ),
                    IconButton(
                      key: Key('subtitleDelete-$index'),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Line hatayein',
                      onPressed: () {
                        setState(() {
                          project.subtitles.removeAt(index);
                          _syncSubtitleControllers();
                        });
                        _scheduleSave();
                      },
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      case 'media':
        // HONEST LIMITATION: the "suggestion" here is the extracted
        // topic keywords (step 1) — the user picks matching gallery
        // clips against them. A full AI media search (stock/AI
        // footage auto-matched to the story) is a later phase; this
        // step never pretends to search anything.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Suggested media — tehreer se nikle topics. In keywords '
              'se match karte clips gallery se chunein. Full AI media '
              'search baad ki phase mein aayega.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _topics
                  .map((t) => Chip(label: Text(t)))
                  .toList(),
            ),
            if (_topics.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Abhi koi keywords nahi — pehle analysis chalao.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            const SizedBox(height: 12),
            ClipPickerList(
              paths: project.clipPaths,
              onChanged: (next) {
                setState(() => project.clipPaths = next);
                _scheduleSave();
              },
            ),
          ],
        );
      case 'graphics':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // v1.5.2 (coherence, fixes #57/#62b/#63b): the Final
            // family is TWO choices — Final 3-Ribbon and Classic
            // 2-Ribbon — and each sets the preset variant along
            // with the kind, so this screen can never label a
            // Classic render as 'Final 3-Ribbon' either.
            Row(
              children: [
                Expanded(
                  child: _templateChoice(
                    kind: 'nigraanFinal',
                    label: 'Final 3-Ribbon',
                    project: project,
                    finalVariant: kFinalVariant3,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _templateChoice(
                    kind: 'nigraanFinal',
                    label: 'Classic 2-Ribbon',
                    project: project,
                    finalVariant: kFinalVariantClassic2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _templateChoice(
                    kind: 'breaking',
                    label: 'Breaking',
                    project: project,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _templateChoice(
                    kind: 'classic',
                    label: 'Classic',
                    project: project,
                  ),
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
                    key: Key('aiBreakingVariant-${variant.id}'),
                    label: Text(variant.label),
                    selected: selected,
                    onSelected: (_) {
                      setState(
                        () => project.breakingVariant = variant.id,
                      );
                      _scheduleSave();
                    },
                  );
                }).toList(),
              ),
            ],
          ],
        );
      case 'branding':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Channel: ${_preset!.name}'),
            const SizedBox(height: 8),
            Row(
              children: [
                _colorDot(_preset!.topRibbon.color, 'Ticker'),
                const SizedBox(width: 12),
                _colorDot(_preset!.urduRibbon.color, 'Urdu'),
                const SizedBox(width: 12),
                _colorDot(_preset!.englishRibbon.color, 'English'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _preset!.logoPath == null
                  ? 'Logo: default (3D rotate on)'
                  : 'Logo: custom (3D rotate on)',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('brandingEditButton'),
              onPressed: () async {
                await _saveNow();
                if (!mounted) return;
                // Build 5 (v1.5.7): Template & Studio is retired —
                // its controls live in the News Maker's Template
                // panel, so the edit opens the workspace.
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NewsMakerScreen(
                      initialPreset: _preset,
                      initialProject: _project,
                    ),
                  ),
                );
                await _reloadPreset();
              },
              child: const Text('News Maker ke Template panel mein badlein'),
            ),
          ],
        );
      case 'ticker':
        return Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('aiTickerField'),
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
              key: const Key('aiPasteTickerButton'),
              onPressed: _pasteTicker,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
              ),
              child: const Text('Paste'),
            ),
          ],
        );
      case 'breaking':
        return SwitchListTile(
          key: const Key('breakingToggle'),
          title: const Text('Breaking graphics'),
          subtitle: const Text(
            'On = breaking template + breaking banner',
          ),
          value: project.breaking,
          onChanged: (value) {
            setState(() {
              project.breaking = value;
              project.templateKind =
                  value ? 'breaking' : 'nigraanFinal';
            });
            _scheduleSave();
          },
        );
      case 'timeline':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Clips: ${project.clipPaths.length}'),
            Text(
              'Voiceover: ${project.voiceoverPath == null ? 'nahi bani' : '${project.voiceoverDurationSec == null ? '' : '${formatVoiceDuration(project.voiceoverDurationSec!)} • '}${_voice.apiName}'}',
            ),
            Text(
              'Template: ${templateDisplayLabel(templateKind: project.templateKind, isFinal3: _preset?.finalIs3Ribbon ?? true, breakingVariantLabel: BreakingVariant.fromId(project.breakingVariant).label)}',
            ),
            Text('Ticker: ${project.tickerText.isEmpty && _tickerController.text.trim().isEmpty ? 'off' : 'on'}'),
            Text('Subtitles: ${project.subtitles.length} lines'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('timelineSaveButton'),
                    onPressed: () async {
                      await _saveNow();
                      _showMessage('Project save ho gaya.');
                    },
                    child: const Text('Project save karein'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const Key('timelineOpenButton'),
                    onPressed: () async {
                      await _saveNow();
                      if (!mounted) return;
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => VideoEditorScreen(
                            project: project,
                            preset: _previewPreset(),
                          ),
                        ),
                      );
                    },
                    child: const Text('Open in Timeline'),
                  ),
                ),
              ],
            ),
          ],
        );
      case 'preview':
        final previewPreset = _previewPreset();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Headline (auto): ${_headlineController.text.isEmpty ? '—' : _headlineController.text}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Summary: ${project.subtitles.length} subtitle lines • '
              'Voice: ${_voice.apiName}${project.voiceoverDurationSec == null ? '' : ' ${formatVoiceDuration(project.voiceoverDurationSec!)}'} • '
              'Ticker: ${_tickerController.text.trim().isEmpty ? 'off' : 'on'}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Center(
              child: project.templateKind == 'nigraanFinal'
                  ? NigraanFinalPreview(
                      preset: previewPreset,
                      fontReady: _fontReady,
                      height: 280,
                    )
                  : project.templateKind == 'breaking'
                      ? BreakingTemplatePreview(
                          key: const Key('aiBreakingPreview'),
                          template: BreakingTemplate.fromProject(
                            project,
                            previewPreset,
                            tickerText: previewPreset.topRibbon.text,
                          ),
                          preset: previewPreset,
                          fontReady: _fontReady,
                          height: 280,
                        )
                      : ClassicPreview(
                          key: const Key('aiClassicPreview'),
                          preset: previewPreset,
                          fontReady: _fontReady,
                          height: 280,
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
          ],
        );
      case 'export':
        // Phase 7 — the real reel export card (quality + Export Reel +
        // Open in Timeline + intro state). No fake button.
        return ReelExportCard(
          project: project,
          preset: _previewPreset(),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _factCheckCard(NewsProject project) {
    return Card(
      color: const Color(0xFF0F2A1A),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '✓ Fact check — ${project.sources.length} source(s) attached',
                    key: const Key('factCheckTitle'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Koi invented fact nahi — publish se pehle aap khud check '
              'karein. App sources ko verify NAHI karta, sirf list karta hai.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            ...project.sources.asMap().entries.map((entry) {
              final index = entry.key;
              final source = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      source.kind == 'url' ? Icons.link : Icons.article,
                      size: 16,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        source.label.isEmpty
                            ? source.value
                            : '${source.label} — ${source.value}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      key: Key('sourceDelete-$index'),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: 'Source hatayein',
                      onPressed: () {
                        setState(() => project.sources.removeAt(index));
                        _scheduleSave();
                      },
                    ),
                  ],
                ),
              );
            }),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    key: const Key('sourceLabelField'),
                    controller: _sourceLabelController,
                    decoration: const InputDecoration(
                      hintText: 'Label (e.g. Dawn)',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextField(
                    key: const Key('sourceValueField'),
                    controller: _sourceValueController,
                    decoration: const InputDecoration(
                      hintText: 'URL ya text',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  key: const Key('sourceKindDropdown'),
                  value: _sourceKind,
                  items: const [
                    DropdownMenuItem(value: 'url', child: Text('URL')),
                    DropdownMenuItem(value: 'text', child: Text('Text')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _sourceKind = value);
                  },
                ),
                IconButton(
                  key: const Key('sourceAddButton'),
                  icon: const Icon(Icons.add_circle),
                  tooltip: 'Source add karein',
                  onPressed: () {
                    final value = _sourceValueController.text.trim();
                    if (value.isEmpty) return;
                    setState(() {
                      project.sources.add(
                        NewsSource(
                          kind: _sourceKind,
                          value: value,
                          label: _sourceLabelController.text.trim(),
                        ),
                      );
                      _sourceLabelController.clear();
                      _sourceValueController.clear();
                    });
                    _scheduleSave();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorDot(int color, String label) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: Color(color),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  Widget _voiceChoice({required GeminiVoice voice, required String label}) {
    final selected = _voice == voice;
    return InkWell(
      key: Key('aiVoiceChoice-${voice.apiName}'),
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

  Widget _templateChoice({
    required String kind,
    required String label,
    required NewsProject project,
    String? finalVariant,
  }) {
    // v1.5.2 (coherence): a Final-family choice is selected only
    // when BOTH the kind and the preset variant match, and
    // tapping it sets both — the same rule as the News Maker.
    final selected = finalVariant == null
        ? project.templateKind == kind
        : project.templateKind == kind &&
            (_preset?.finalVariant ?? kFinalVariant3) == finalVariant;
    return InkWell(
      key: Key('aiTemplateChoice-$kind-${finalVariant ?? 'plain'}'),
      onTap: () {
        setState(() {
          project.templateKind = kind;
          project.breaking = kind == 'breaking';
        });
        if (finalVariant != null && _preset != null) {
          _preset!.finalVariant = finalVariant;
          unawaited(persistPresetChange(_preset!));
        }
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
        child: Center(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
