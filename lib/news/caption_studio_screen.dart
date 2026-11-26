/// Caption Studio (Phase 5) — Magic Box's Caption Studio, ported
/// to TJ Pro (see `lib/services/caption_styles.dart` for the port
/// notes): 11 styles (Nigraan Karaoke green #3AEC70 default), 6
/// fonts, 3 one-tap presets, 6 highlight colours, position / size /
/// FX controls, editable/deletable lines, split/merge, re-time
/// (shift all ±0.5s, nudge), add manual line, undo/redo, draft
/// auto-save/restore, dual-language lines, SRT + VTT + TXT + styled
/// ASS export, copy, and video burn-in (720p/1080p).
///
/// The screen edits a [NewsProject]'s subtitles + caption settings
/// (the shared project JSON) — so News Maker and the AI News Maker
/// see the same lines and the same style. A draft is auto-saved
/// alongside (crash safety); on open, a differing draft offers a
/// one-tap restore instead of silently overwriting the project.
///
/// Karaoke preview: when the project has a voiceover, the preview
/// plays it back and highlights the word actually being spoken
/// (timings from `karaoke_sync.dart` — derived from the real WAV
/// duration). Without a voiceover, a scrub slider drives the same
/// highlight. "Sync with voiceover" re-times edited lines to the
/// real voiceover length.
///
/// Transcription is NOT here: TJ Pro transcribes on-device with
/// Whisper (see `caption_service.dart` — the live video editor's
/// captions). This studio edits the tehreer-derived lines; the
/// translator (ML Kit, on-device) opens from here.
///
/// Look: dark navy/black + purple #7C3AED (mockups).
///
/// v1.2.0 restyle (approved mockup `k-captions.png`): the style
/// picker is now a CapCut-style grouped card grid — category tabs
/// (All / Karaoke / Pop / Typewriter / Flash / Urdu) over cards with
/// live preview thumbnails — and the Urdu styles from
/// `caption_styles.dart` (built on the `font_registry.dart` fonts)
/// join the original 11, with the registry fonts in the Urdu font
/// list and two Urdu one-tap presets. NO control, entry point or
/// engine behaviour was removed: every pre-existing key, button,
/// switch, export and burn-in path below is unchanged.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../services/caption_draft_service.dart';
import '../services/caption_service.dart';
import '../services/caption_styles.dart';
import '../services/download_service.dart';
import '../services/font_registry.dart';
import '../services/video_export_service.dart';
import '../theme.dart';
import 'caption_editor.dart';
import 'caption_translator_screen.dart';
import 'caption_alignment.dart';
import 'karaoke_sync.dart';
import 'news_project.dart';
import 'widgets/styled_caption_preview.dart';

class CaptionStudioScreen extends StatefulWidget {
  /// Test/deep-link seam: when given, the screen edits that project
  /// directly instead of loading the latest one. Production passes
  /// null from the home tile (latest project) or a project from the
  /// News Maker / AI News Maker.
  const CaptionStudioScreen({super.key, this.initialProject});

  final NewsProject? initialProject;

  @override
  State<CaptionStudioScreen> createState() => _CaptionStudioScreenState();
}

class _CaptionStudioScreenState extends State<CaptionStudioScreen> {
  NewsProject? _project;
  CaptionEditor? _editor;
  bool _loaded = false;

  CaptionDraft? _pendingDraft;
  // True once the initial draft read finished. Autosave must not
  // overwrite a not-yet-read draft with the current lines, so the
  // draft write waits for this flag.
  bool _draftLoaded = false;
  VideoExportQuality _burnQuality = VideoExportQuality.p720;

  // Karaoke preview state.
  VideoPlayerController? _voiceController;
  bool _voicePlaying = false;
  bool _voiceInitialising = false;
  String? _voiceError;
  double _previewPosition = 0.0;
  int _activeLine = -1;
  int _selectedLine = 0;

  // Style picker state (v1.2.0 restyle): the selected CapCut-style
  // category tab. Purely a view filter — every style stays reachable
  // under 'All' and under its own category.
  String _styleCategory = 'All';

  // Burn-in state.
  String? _burnVideoPath;
  bool _burnBusy = false;

  /// Build 13 (point #16): the "Asal timings" (Whisper word
  /// alignment) run state.
  bool _alignBusy = false;
  double _burnProgress = 0;
  String _status = '';

  Timer? _saveTimer;
  final _draftStore = CaptionDraftStore();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _voiceController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final project = widget.initialProject ??
        await NewsProjectStore.loadLatest() ??
        NewsProject.create();
    if (!mounted) return;
    // Show the project immediately — the draft restore is a
    // convenience banner, not a gate: it loads in the background
    // and appears when the read finishes. (Blocking the whole
    // screen on a file read also made the screen untestable: widget
    // tests never flush real dart:io work — Phase 4 note.)
    setState(() {
      _project = project;
      _editor = CaptionEditor(project.subtitles);
      _loaded = true;
    });
    final draft = await _draftStore.load(project.id);
    if (!mounted) return;
    _draftLoaded = true;
    final draftDiffers = draft != null &&
        jsonEncode(draft.lines.map((l) => l.toJson()).toList()) !=
            jsonEncode(project.subtitles.map((l) => l.toJson()).toList());
    if (draftDiffers) {
      setState(() => _pendingDraft = draft);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  NewsProject get _p => _project!;
  CaptionEditor get _e => _editor!;

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveNow);
  }

  Future<void> _saveNow() async {
    final project = _project;
    final editor = _editor;
    if (project == null || editor == null) return;
    project.subtitles = editor.lines;
    await NewsProjectStore.save(project);
    // The draft write waits for the initial draft read (see
    // _draftLoaded): an edit in the first milliseconds must not
    // clobber a pending restore.
    if (_draftLoaded) {
      await _draftStore.save(project.id, _currentDraft());
    }
    if (!mounted) return;
    setState(() => _status = 'Saved.');
  }

  CaptionDraft _currentDraft() {
    return CaptionDraft(
      lines: _e.lines,
      styleId: _p.captionStyleId,
      position: _p.captionPosition,
      size: _p.captionSize,
      highlightColor: _p.captionHighlight,
      fontId: _p.captionFontId,
      outline: _p.captionOutline,
      shadow: _p.captionShadow,
      background: _p.captionBackground,
      dualLanguage: _p.captionDualLanguage,
    );
  }

  void _applyDraft() {
    final draft = _pendingDraft;
    if (draft == null) return;
    setState(() {
      _editor = CaptionEditor(draft.lines);
      _p.captionStyleId = draft.styleId;
      _p.captionPosition = draft.position;
      _p.captionSize = draft.size;
      _p.captionHighlight = draft.highlightColor;
      _p.captionFontId = draft.fontId;
      _p.captionOutline = draft.outline;
      _p.captionShadow = draft.shadow;
      _p.captionBackground = draft.background;
      _p.captionDualLanguage = draft.dualLanguage;
      _pendingDraft = null;
      _selectedLine = 0;
    });
    _scheduleSave();
    _showMessage('Draft restored.');
  }

  Future<void> _dismissDraft() async {
    await _draftStore.clear(_p.id);
    if (!mounted) return;
    setState(() => _pendingDraft = null);
  }

  // ---- Editing ops (all real, all undoable) ----

  void _edit(void Function() func) {
    setState(() => func());
    _scheduleSave();
  }

  /// Index of the line field currently being typed in (-1 = none).
  /// One undo snapshot is taken when typing STARTS in a field
  /// ([CaptionEditor.beginEdit]), so a whole typing session is one
  /// undo step.
  int _editingIndex = -1;

  void _beginFieldEdit(int index) {
    if (_editingIndex != index) {
      _e.beginEdit();
      _editingIndex = index;
    }
  }

  void _syncWithVoiceover() {
    final duration = _p.voiceoverDurationSec;
    if (duration == null || duration <= 0) {
      _showMessage('Create the voiceover first — sync will use its length.');
      return;
    }
    if (_e.lines.isEmpty) {
      _showMessage('Create subtitles first (from the script).');
      return;
    }
    setState(() {
      _editor = CaptionEditor(resyncExistingLines(_e.lines, duration));
      // Build 13: this re-time is the ESTIMATOR — stamp the
      // source honestly (the "Asal timings" action upgrades).
      _p.captionTimingSource = 'estimate';
      _p.captionAlignedHash = '';
    });
    _scheduleSave();
    _showMessage(
      'Subtitles synced with the voiceover (${duration.toStringAsFixed(1)}s).',
    );
  }

  /// Build 13 (point #16): the "Asal timings" action — the same
  /// shared alignment the News Maker's Captions panel runs
  /// (caption_alignment.dart). On success the editor reloads
  /// from the re-timed project lines; on failure nothing changes
  /// and the message says why.
  Future<void> _alignWithWhisper() async {
    if (_alignBusy) return;
    setState(() => _alignBusy = true);
    try {
      final temp = await getTemporaryDirectory();
      final workDir = Directory(p.join(temp.path, 'caption_align'));
      if (!await workDir.exists()) {
        await workDir.create(recursive: true);
      }
      final outcome = await alignProjectCaptionsToVoiceover(
        _p,
        workDir: workDir,
      );
      if (!mounted) return;
      if (outcome.applied) {
        setState(() {
          _editor = CaptionEditor(_p.subtitles);
          _editingIndex = -1;
        });
        _scheduleSave();
      }
      _showMessage(outcome.message);
    } catch (e) {
      if (mounted) _showMessage('Real timings could not be applied: $e');
    } finally {
      if (mounted) setState(() => _alignBusy = false);
    }
  }

  void _applyPreset(CaptionPreset preset) {
    final lang = tehreerLangOf(_p.tehreer);
    final fonts = CaptionFonts.forLang(lang);
    setState(() {
      _p.captionStyleId = preset.styleId;
      _p.captionPosition = preset.position;
      _p.captionSize = preset.size;
      if (fonts.any((f) => f.id == preset.fontId)) {
        _p.captionFontId = preset.fontId;
      }
      _p.captionHighlight = preset.highlightColor;
      _p.captionOutline = preset.outline;
      _p.captionShadow = preset.shadow;
      _p.captionBackground = preset.background;
    });
    _scheduleSave();
  }

  // ---- Karaoke preview (voiceover playback) ----

  Future<void> _toggleVoicePreview() async {
    final path = _p.voiceoverPath;
    if (path == null || _voiceInitialising) return;
    if (_voiceController == null) {
      setState(() {
        _voiceInitialising = true;
        _voiceError = null;
      });
      try {
        final controller = VideoPlayerController.file(File(path));
        await controller.initialize();
        controller.addListener(_onVoiceUpdate);
        if (!mounted) {
          await controller.dispose();
          return;
        }
        setState(() {
          _voiceController = controller;
          _voiceInitialising = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _voiceInitialising = false;
          _voiceError = 'Voice could not play: $e';
        });
        return;
      }
    }
    final controller = _voiceController!;
    if (controller.value.isPlaying) {
      await controller.pause();
      if (mounted) setState(() => _voicePlaying = false);
    } else {
      if (controller.value.position >= controller.value.duration &&
          controller.value.duration > Duration.zero) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
      if (mounted) setState(() => _voicePlaying = true);
    }
  }

  void _onVoiceUpdate() {
    final controller = _voiceController;
    if (controller == null || !mounted) return;
    final pos = controller.value.position.inMilliseconds / 1000.0;
    final lineIdx = subtitleLineAt(_e.lines, pos);
    final finished = controller.value.position >=
            controller.value.duration &&
        controller.value.duration > Duration.zero &&
        !controller.value.isPlaying;
    if (finished && _voicePlaying) {
      setState(() => _voicePlaying = false);
    }
    if (lineIdx != _activeLine || (pos - _previewPosition).abs() > 0.05) {
      setState(() {
        _previewPosition = pos;
        _activeLine = lineIdx;
      });
    }
  }

  // ---- Exports ----

  List<CaptionSegment> _toCaptionSegments() {
    return _e.lines
        .map(
          (l) => CaptionSegment(
            l.text,
            l.startSec,
            l.endSec,
            words: l.words
                .map(
                  (w) => CaptionWord(word: w.word, start: w.startSec, end: w.endSec),
                )
                .toList(),
            translation: l.translation,
          ),
        )
        .toList();
  }

  StudioCaptionStyle get _style =>
      StudioCaptionStyles.byId(_p.captionStyleId);

  String _buildAss() {
    final segments = _toCaptionSegments();
    // News reels are 9:16 portrait.
    return CaptionService.buildStyledAss(
      segments,
      _style,
      position: _p.captionPosition,
      size: _p.captionSize,
      highlightColor: _p.captionHighlight,
      fontFamily:
          CaptionFonts.byId(_p.captionFontId).family ?? 'Arial',
      playResX: 1080,
      playResY: 1920,
      outline: _p.captionOutline,
      shadow: _p.captionShadow,
      background: _p.captionBackground,
      dualLanguage: _p.captionDualLanguage,
    );
  }

  Future<void> _exportTextFile(String kind) async {
    if (_e.lines.isEmpty) {
      _showMessage('Create subtitles first (from the script).');
      return;
    }
    final segments = _toCaptionSegments();
    final (fileName, content) = switch (kind) {
      'srt' => (
          'tj_pro_captions.srt',
          CaptionService.buildSrt(segments, dualLanguage: _p.captionDualLanguage),
        ),
      'vtt' => (
          'tj_pro_captions.vtt',
          CaptionService.buildVtt(segments, dualLanguage: _p.captionDualLanguage),
        ),
      'txt' => (
          'tj_pro_captions.txt',
          CaptionService.buildTxt(segments, dualLanguage: _p.captionDualLanguage),
        ),
      'ass' => ('tj_pro_captions.ass', _buildAss()),
      _ => ('tj_pro_captions.txt', ''),
    };
    try {
      final path = await DownloadService.saveBytes(
        fileName,
        utf8.encode(content),
      );
      _showMessage('$kind saved to the Downloads folder:\n$path');
    } catch (e) {
      _showMessage('$kind could not be saved: $e');
    }
  }

  Future<void> _copyText() async {
    if (_e.lines.isEmpty) {
      _showMessage('Create subtitles first (from the script).');
      return;
    }
    await Clipboard.setData(
      ClipboardData(
        text: CaptionService.buildPlainText(
          _toCaptionSegments(),
          dualLanguage: _p.captionDualLanguage,
        ),
      ),
    );
    _showMessage('Captions copied (clipboard).');
  }

  Future<void> _pickBurnVideo() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.video,
      );
      if (file == null) return;
      final path = file.path;
      if (path == null) return;
      setState(() => _burnVideoPath = path);
    } catch (e) {
      _showMessage('Video could not be picked: $e');
    }
  }

  Future<void> _burnIn() async {
    final videoPath = _burnVideoPath;
    if (videoPath == null) {
      _showMessage('Choose a video first (for Burn-in).');
      return;
    }
    if (_e.lines.isEmpty) {
      _showMessage('Create subtitles first (from the script).');
      return;
    }
    setState(() {
      _burnBusy = true;
      _burnProgress = 0;
      _status = 'Burn-in in progress…';
    });
    try {
      final ass = _buildAss();
      final result = await VideoExportService.exportVideo(
        inputVideo: File(videoPath),
        assContent: ass,
        quality: _burnQuality,
        baseName: pBaseName(videoPath),
        onProgress: (p) {
          if (mounted) setState(() => _burnProgress = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _burnBusy = false;
        _burnProgress = result.success ? 1.0 : 0.0;
        _status = result.success
            ? 'Burn-in done: ${result.outputPath}'
            : result.cancelled
                ? 'Burn-in cancelled.'
                : 'Burn-in fail: ${result.error}';
      });
      if (result.success) _showMessage('Captioned video saved.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _burnBusy = false;
        _status = 'Burn-in fail: $e';
      });
    }
  }

  Future<void> _openTranslator() async {
    final fromLang = tehreerLangOf(_p.tehreer);
    final toLang = fromLang == 'ur' ? 'en' : 'ur';
    final result = await Navigator.of(context).push<List<CaptionSegment>>(
      MaterialPageRoute(
        builder: (_) => CaptionTranslatorScreen(
          initialSegments: _toCaptionSegments(),
          fromLang: fromLang,
          toLang: toLang,
        ),
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    setState(() {
      for (var i = 0; i < result.length && i < _e.lines.length; i++) {
        _e.setTranslation(i, result[i].text);
      }
      _p.captionDualLanguage = true;
    });
    _scheduleSave();
    _showMessage('Translations applied (dual-language ON).');
  }

  Future<void> _addLineDialog() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New caption line'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Write the line…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    _edit(() => _e.addManualLine(text));
  }

  // ---- Style picker (v1.2.0 CapCut-style card grid) ----

  /// Category tabs for the style grid, in mockup order (the mockup's
  /// Trending / Highlight / Glow / Aesthetic / Urdu become the
  /// animation groups + Urdu, which is what the styles actually are).
  static const List<String> _styleCategories = [
    'All',
    'Karaoke',
    'Pop',
    'Typewriter',
    'Flash',
    'Urdu',
  ];

  bool _inStyleCategory(StudioCaptionStyle style, String category) {
    return switch (category) {
      'All' => true,
      'Urdu' => style.fontId != null,
      'Karaoke' => style.animation == CaptionAnimation.karaoke,
      'Pop' => style.animation == CaptionAnimation.pop,
      'Typewriter' => style.animation == CaptionAnimation.typewriter,
      'Flash' => style.animation == CaptionAnimation.flash,
      _ => true,
    };
  }

  /// One style card: a live preview thumbnail (sample words rendered
  /// in the style's own colours / typeface) over the style name.
  /// Tapping selects the style — the same action the old ChoiceChip
  /// performed, with the same key.
  Widget _styleCard(StudioCaptionStyle style, bool selected) {
    final isUrdu = style.fontId != null;
    final sample = isUrdu ? 'تازہ ترین خبر' : 'THE QUICK BROWN';
    final words = sample.split(' ');
    var previewStyle = TextStyle(
      color: Color(style.textColor),
      fontSize: (style.fontSizePx * 0.55).clamp(11.0, 16.0),
      fontWeight: style.bold ? FontWeight.bold : FontWeight.normal,
      shadows: style.shadow
          ? const [
              Shadow(color: Colors.black54, offset: Offset(1, 1), blurRadius: 2),
            ]
          : null,
    );
    if (isUrdu) {
      // Registry-driven preview: the card renders in the style's own
      // Urdu typeface (google_fonts download / Kasheeda FontLoader).
      previewStyle = UrduFonts.byId(style.fontId!).apply(previewStyle);
    }
    final highlightStyle = previewStyle.copyWith(
      color: Color(
        style.highlightBg != 0 ? style.textColor : style.highlightColor,
      ),
    );
    return InkWell(
      key: Key('captionStyle-${style.id}'),
      onTap: () {
        setState(() => _p.captionStyleId = style.id);
        _scheduleSave();
      },
      borderRadius: BorderRadius.circular(TjProTheme.cardRadius),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF181828),
          borderRadius: BorderRadius.circular(TjProTheme.cardRadius),
          border: Border.all(
            color: selected ? TjProTheme.violet : Colors.white12,
            width: selected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: style.backgroundColor != 0
                      ? Color(style.backgroundColor)
                      : Colors.black,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                alignment: Alignment.center,
                child: RichText(
                  textAlign: TextAlign.center,
                  textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    children: [
                      for (var i = 0; i < words.length; i++)
                        TextSpan(
                          text: i == words.length - 1
                              ? (style.uppercase
                                  ? words[i].toUpperCase()
                                  : words[i])
                              : '${style.uppercase ? words[i].toUpperCase() : words[i]} ',
                          style: i == 0 ? highlightStyle : previewStyle,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    style.nameEn,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle,
                    size: 16,
                    color: TjProTheme.violetBright,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
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
          title: const Text('Caption Studio'),
          backgroundColor: const Color(0xFF080810),
        ),
        body: !_loaded || _project == null || _editor == null
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final project = _p;
    final totalDuration = _e.lines.isEmpty
        ? 0.0
        : _e.lines.map((l) => l.endSec).reduce((a, b) => a > b ? a : b);
    final previewLine = _activeLine >= 0
        ? _e.lines[_activeLine]
        : (_e.lines.isEmpty
            ? null
            : _e.lines[_selectedLine.clamp(0, _e.lines.length - 1)]);
    final previewPos = _previewPosition;
    return ListView(
      key: const Key('captionStudioList'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        if (_pendingDraft != null)
          Card(
            color: const Color(0xFF2A1A4A),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Draft found — a previous editing session was saved.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        key: const Key('restoreDraftButton'),
                        onPressed: _applyDraft,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                        ),
                        child: const Text('Restore draft'),
                      ),
                      TextButton(
                        onPressed: _dismissDraft,
                        child: const Text('Delete draft'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const Text(
          'Karaoke preview',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(TjProTheme.cardRadius),
            border: Border.all(color: Colors.white24),
          ),
          child: Stack(
            children: [
              if (previewLine != null)
                Align(
                  alignment: switch (project.captionPosition) {
                    CaptionPosition.top => Alignment.topCenter,
                    CaptionPosition.middle => Alignment.center,
                    CaptionPosition.bottom => Alignment.bottomCenter,
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: StyledCaptionPreview(
                      line: previewLine,
                      style: _style,
                      positionSec: previewPos,
                      highlightColor: project.captionHighlight,
                      fontFamily: CaptionFonts.byId(project.captionFontId).family,
                      fontSizePx: _style.fontSizePx *
                          StudioCaptionStyles.sizeScale(project.captionSize),
                      showBackground: project.captionBackground,
                    ),
                  ),
                )
              else
                const Center(
                  child: Text(
                    'No subtitles yet — first in News Maker / AI News '
                    'Maker, create subtitles from the script.',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),
              Positioned(
                left: 8,
                bottom: 8,
                child: project.voiceoverPath == null
                    ? const Text(
                        'No voiceover — see the highlight with the scrub slider.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      )
                    : Row(
                        children: [
                          IconButton(
                            key: const Key('karaokePlayPause'),
                            icon: Icon(
                              _voicePlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                            ),
                            onPressed:
                                _voiceInitialising ? null : _toggleVoicePreview,
                          ),
                          Text(
                            '${_previewPosition.toStringAsFixed(1)}s'
                            '${project.voiceoverDurationSec == null ? '' : ' / ${project.voiceoverDurationSec!.toStringAsFixed(1)}s'}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        if (_voiceError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _voiceError!,
              style: const TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ),
        if (project.voiceoverPath == null && totalDuration > 0) ...[
          const SizedBox(height: 8),
          Slider(
            key: const Key('karaokeScrubSlider'),
            value: _previewPosition.clamp(0.0, totalDuration),
            min: 0,
            max: totalDuration,
            onChanged: (v) {
              setState(() {
                _previewPosition = v;
                _activeLine = subtitleLineAt(_e.lines, v);
              });
            },
          ),
          Text(
            'Scrub: ${_previewPosition.toStringAsFixed(1)}s / ${totalDuration.toStringAsFixed(1)}s — '
            'the spoken word turns green (#3AEC70).',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
        const SizedBox(height: 20),
        Text(
          'Style — ${StudioCaptionStyles.all.length} looks',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        // CapCut-style category tabs (scrollable on narrow screens).
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _styleCategories.map((category) {
              final selected = _styleCategory == category;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  key: Key('captionStyleCategory-$category'),
                  label: Text(category),
                  selected: selected,
                  onSelected: (_) =>
                      setState(() => _styleCategory = category),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 10),
        // Style cards with live preview thumbnails. The grid is a
        // view over ALL styles — the category only filters which
        // cards are visible, nothing is removed.
        Builder(
          builder: (context) {
            final visible = StudioCaptionStyles.all
                .where((s) => _inStyleCategory(s, _styleCategory))
                .toList();
            return LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 560
                    ? 4
                    : constraints.maxWidth >= 360
                        ? 3
                        : 2;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: TjProTheme.gridGap,
                    mainAxisSpacing: TjProTheme.gridGap,
                    childAspectRatio: 0.92,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (context, i) => _styleCard(
                    visible[i],
                    project.captionStyleId == visible[i].id,
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 12),
        const Text(
          'One-tap presets',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: CaptionPresets.all
              .map(
                (preset) => OutlinedButton(
                  key: Key('captionPreset-${preset.id}'),
                  onPressed: () => _applyPreset(preset),
                  child: Text(preset.nameEn),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        const Text(
          'Controls',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            const Text('Position'),
            SegmentedButton<CaptionPosition>(
              segments: const [
                ButtonSegment(value: CaptionPosition.top, label: Text('Top')),
                ButtonSegment(
                  value: CaptionPosition.middle,
                  label: Text('Middle'),
                ),
                ButtonSegment(
                  value: CaptionPosition.bottom,
                  label: Text('Bottom'),
                ),
              ],
              selected: {project.captionPosition},
              onSelectionChanged: (s) {
                setState(() => project.captionPosition = s.first);
                _scheduleSave();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            const Text('Size'),
            SegmentedButton<CaptionSize>(
              segments: const [
                ButtonSegment(value: CaptionSize.small, label: Text('S')),
                ButtonSegment(value: CaptionSize.medium, label: Text('M')),
                ButtonSegment(value: CaptionSize.large, label: Text('L')),
              ],
              selected: {project.captionSize},
              onSelectionChanged: (s) {
                setState(() => project.captionSize = s.first);
                _scheduleSave();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Highlight colour'),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: StudioCaptionStyles.highlightChoices.map((color) {
            final selected = (project.captionHighlight ?? _style.highlightColor) ==
                color;
            return InkWell(
              key: Key('highlightColor-$color'),
              onTap: () {
                setState(() => project.captionHighlight = color);
                _scheduleSave();
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Color(color),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 16, color: Colors.black)
                    : null,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            const Text('Font'),
            DropdownButton<String>(
              key: const Key('captionFontDropdown'),
              value: CaptionFonts.forLang(tehreerLangOf(project.tehreer))
                      .any((f) => f.id == project.captionFontId)
                  ? project.captionFontId
                  : CaptionFonts.forLang(tehreerLangOf(project.tehreer)).first.id,
              items: CaptionFonts.forLang(tehreerLangOf(project.tehreer))
                  .map(
                    (f) => DropdownMenuItem(value: f.id, child: Text(f.nameEn)),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => project.captionFontId = v);
                _scheduleSave();
              },
            ),
          ],
        ),
        const Text(
          'Bebas / Anton / Montserrat / Poppins are not bundled in the app — '
          'a system font will show in the preview; the family name is written in the ASS.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const Text(
          'Urdu fonts: along with Jameel Noori (house font), Noto Nastaliq, '
          'Gulzar and Noto Naskh — these are downloaded at runtime from google_fonts + '
          'are downloaded at runtime from google_fonts and cached (font registry: UrduFonts).',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        SwitchListTile(
          title: const Text('Outline'),
          value: project.captionOutline,
          onChanged: (v) {
            setState(() => project.captionOutline = v);
            _scheduleSave();
          },
        ),
        SwitchListTile(
          title: const Text('Shadow'),
          value: project.captionShadow,
          onChanged: (v) {
            setState(() => project.captionShadow = v);
            _scheduleSave();
          },
        ),
        SwitchListTile(
          title: const Text('Background box'),
          value: project.captionBackground,
          onChanged: (v) {
            setState(() => project.captionBackground = v);
            _scheduleSave();
          },
        ),
        SwitchListTile(
          key: const Key('dualLanguageSwitch'),
          title: const Text('Dual-language captions'),
          subtitle: const Text(
            'Under each line, the other language\'s line (from the translator or by hand).',
          ),
          value: project.captionDualLanguage,
          onChanged: (v) {
            setState(() => project.captionDualLanguage = v);
            _scheduleSave();
          },
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Text(
              'Caption lines',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            IconButton(
              key: const Key('captionUndoButton'),
              icon: const Icon(Icons.undo),
              tooltip: 'Undo',
              onPressed: _e.canUndo
                  ? () => _edit(() => _e.undo())
                  : null,
            ),
            IconButton(
              key: const Key('captionRedoButton'),
              icon: const Icon(Icons.redo),
              tooltip: 'Redo',
              onPressed: _e.canRedo
                  ? () => _edit(() => _e.redo())
                  : null,
            ),
            IconButton(
              key: const Key('captionAddButton'),
              icon: const Icon(Icons.add),
              tooltip: 'New line',
              onPressed: _addLineDialog,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              key: const Key('shiftBackButton'),
              onPressed: _e.lines.isEmpty
                  ? null
                  : () => _edit(() => _e.shiftAll(-0.5)),
              child: const Text('−0.5s all'),
            ),
            OutlinedButton(
              key: const Key('shiftForwardButton'),
              onPressed: _e.lines.isEmpty
                  ? null
                  : () => _edit(() => _e.shiftAll(0.5)),
              child: const Text('+0.5s all'),
            ),
            OutlinedButton(
              key: const Key('syncVoiceoverButton'),
              onPressed: project.voiceoverDurationSec == null
                  ? null
                  : _syncWithVoiceover,
              child: const Text('Voiceover se sync'),
            ),
            OutlinedButton.icon(
              key: const Key('alignWhisperButton'),
              onPressed: _alignBusy || project.voiceoverDurationSec == null
                  ? null
                  : _alignWithWhisper,
              icon: _alignBusy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.hearing_outlined, size: 16),
              label: Text(
                _alignBusy ? 'Whisper is listening…' : 'Asal timings (Whisper)',
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          key: const Key('studioTimingStatus'),
          project.captionTimingsStale
              ? 'Timings: they were REAL (Whisper) — the script or voiceover '
                  'has changed; apply Real timings again.'
              : project.captionTimingSource == 'whisper'
                  ? 'Timings: REAL (Whisper) — every word at its real '
                      'time.'
                  : 'Timings: ESTIMATE — "Voiceover se sync" length '
                      'estimates from it; "Real timings" from Whisper '
                      'applies the real word timings.',
          style: TextStyle(
            color: project.captionTimingsStale
                ? const Color(0xFFFFC800)
                : Colors.grey,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        if (_e.lines.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No subtitles yet — in News Maker / AI News Maker '
                'write the script and create the voiceover, then come here.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ...List.generate(_e.lines.length, (index) {
            final line = _e.lines[index];
            final words = StudioCaptionStyles.wordsOf(line.text);
            return Card(
              key: Key('captionLine-$index'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          '${line.startSec.toStringAsFixed(1)}s – ${line.endSec.toStringAsFixed(1)}s',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                          key: Key('captionNudgeBack-$index'),
                          icon: const Icon(Icons.remove, size: 18),
                          tooltip: '−0.5s',
                          onPressed: () =>
                              _edit(() => _e.nudgeLine(index, -0.5)),
                        ),
                        IconButton(
                          key: Key('captionNudgeForward-$index'),
                          icon: const Icon(Icons.add, size: 18),
                          tooltip: '+0.5s',
                          onPressed: () =>
                              _edit(() => _e.nudgeLine(index, 0.5)),
                        ),
                        IconButton(
                          key: Key('captionSplit-$index'),
                          icon: const Icon(Icons.call_split, size: 18),
                          tooltip: 'Split the line (from the middle)',
                          onPressed: words.length < 2
                              ? null
                              : () => _edit(
                                    () => _e.splitLine(
                                      index,
                                      (words.length ~/ 2) - 1,
                                    ),
                                  ),
                        ),
                        IconButton(
                          key: Key('captionMerge-$index'),
                          icon: const Icon(Icons.merge_type, size: 18),
                          tooltip: 'Agli line se jodein',
                          onPressed: index >= _e.lines.length - 1
                              ? null
                              : () => _edit(() => _e.mergeWithNext(index)),
                        ),
                            IconButton(
                              key: Key('captionDelete-$index'),
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Remove line',
                              onPressed: () =>
                                  _edit(() => _e.deleteLine(index)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    TextFormField(
                      key: Key('captionText-$index'),
                      initialValue: line.text,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      onTap: () {
                        _beginFieldEdit(index);
                        setState(() => _selectedLine = index);
                      },
                      onChanged: (value) {
                        // Live edit without rebuilding the field on
                        // every keystroke: update the editor directly
                        // (no undo snapshot per keystroke — one was
                        // taken when typing started) and save
                        // debounced.
                        _e.setLineText(index, value);
                        _scheduleSave();
                      },
                    ),
                    if (project.captionDualLanguage) ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        key: Key('captionTranslation-$index'),
                        initialValue: line.translation,
                        decoration: const InputDecoration(
                          labelText: 'Doosri zuban ki line',
                          border: OutlineInputBorder(),
                        ),
                        onTap: () => _beginFieldEdit(index),
                        onChanged: (value) {
                          _e.setTranslationText(index, value);
                          _scheduleSave();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('translatorButton'),
                onPressed: _openTranslator,
                icon: const Icon(Icons.translate, size: 18),
                label: const Text('Translator (Urdu↔English)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Export',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              key: const Key('exportSrtButton'),
              onPressed: () => _exportTextFile('srt'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
              ),
              child: const Text('SRT'),
            ),
            FilledButton(
              key: const Key('exportVttButton'),
              onPressed: () => _exportTextFile('vtt'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
              ),
              child: const Text('VTT'),
            ),
            FilledButton(
              key: const Key('exportTxtButton'),
              onPressed: () => _exportTextFile('txt'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
              ),
              child: const Text('TXT'),
            ),
            FilledButton(
              key: const Key('exportAssButton'),
              onPressed: () => _exportTextFile('ass'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
              ),
              child: const Text('Styled ASS'),
            ),
            OutlinedButton(
              key: const Key('exportCopyButton'),
              onPressed: _copyText,
              child: const Text('Copy text'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'The Highlight Box style\'s yellow box does not come in ASS (ASS has '
          'it has no equivalent) — the line\'s colours stay the same.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 20),
        const Text(
          'Video burn-in — burn captions into the video',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('pickBurnVideoButton'),
                onPressed: _burnBusy ? null : _pickBurnVideo,
                icon: const Icon(Icons.video_library, size: 18),
                label: Text(
                  _burnVideoPath == null
                      ? 'Choose a video'
                      : _burnVideoPath!.split('/').last,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SegmentedButton<VideoExportQuality>(
              segments: const [
                ButtonSegment(
                  value: VideoExportQuality.p720,
                  label: Text('720p'),
                ),
                ButtonSegment(
                  value: VideoExportQuality.p1080,
                  label: Text('1080p'),
                ),
              ],
              selected: {_burnQuality},
              onSelectionChanged: (s) =>
                  setState(() => _burnQuality = s.first),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('burnInButton'),
            onPressed: _burnBusy ? null : _burnIn,
            icon: _burnBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.local_fire_department),
            label: Text(_burnBusy ? 'Burn-in in progress…' : 'Burn into the video'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        if (_burnBusy || _burnProgress > 0) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(value: _burnProgress),
        ],
        if (_burnBusy) ...[
          const SizedBox(height: 4),
          // Phase 0: burn-in CANCEL — kills the in-flight ffmpeg
          // pass through VideoExportService's session registry;
          // the export then returns a cancelled result instead of
          // running its drawtext retry.
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: const Key('burnInCancelButton'),
              onPressed: () =>
                  unawaited(VideoExportService.cancelCurrentExport()),
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: const Text('Cancel'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          _status,
          key: const Key('captionStatus'),
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        const Text(
          'Burn-in first tries with styled ASS (full style: '
          'colours, karaoke, outline, position); fail ho to per-line '
          'the drawtext fallback runs (Urdu does not shape in it — '
          'that is drawtext\'s limit).',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }
}

/// Language of the tehreer ('ur' when it has Arabic-script chars,
/// else 'en') — the caption font list + translator direction follow
/// it. (Same rule as `GeminiVoiceService.detectLang`, duplicated
/// here so this screen does not import the voice service.)
String tehreerLangOf(String text) =>
    RegExp(r'[\u0600-\u06FF]').hasMatch(text) ? 'ur' : 'en';

/// Base name of a path without its extension (for the burn-in output
/// file name).
String pBaseName(String path) {
  final base = path.split('/').last;
  final dot = base.lastIndexOf('.');
  return dot > 0 ? base.substring(0, dot) : base;
}
