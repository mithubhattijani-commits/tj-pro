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
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../services/caption_draft_service.dart';
import '../services/caption_service.dart';
import '../services/caption_styles.dart';
import '../services/download_service.dart';
import '../services/video_export_service.dart';
import 'caption_editor.dart';
import 'caption_translator_screen.dart';
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

  // Burn-in state.
  String? _burnVideoPath;
  bool _burnBusy = false;
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
    _showMessage('Draft restore ho gaya.');
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
      _showMessage('Pehle voiceover banayein — us ki length se sync hoga.');
      return;
    }
    if (_e.lines.isEmpty) {
      _showMessage('Pehle subtitles banayein (tehreer se).');
      return;
    }
    setState(() {
      _editor = CaptionEditor(resyncExistingLines(_e.lines, duration));
    });
    _scheduleSave();
    _showMessage(
      'Subtitles voiceover se sync ho gaye (${duration.toStringAsFixed(1)}s).',
    );
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
          _voiceError = 'Voice play nahi hui: $e';
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
      _showMessage('Pehle subtitles banayein (tehreer se).');
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
      _showMessage('$kind Download folder mein save ho gaya:\n$path');
    } catch (e) {
      _showMessage('$kind save nahi hua: $e');
    }
  }

  Future<void> _copyText() async {
    if (_e.lines.isEmpty) {
      _showMessage('Pehle subtitles banayein (tehreer se).');
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
    _showMessage('Captions copy ho gaye (clipboard).');
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
      _showMessage('Video pick nahi hui: $e');
    }
  }

  Future<void> _burnIn() async {
    final videoPath = _burnVideoPath;
    if (videoPath == null) {
      _showMessage('Pehle video chunein (Burn-in ke liye).');
      return;
    }
    if (_e.lines.isEmpty) {
      _showMessage('Pehle subtitles banayein (tehreer se).');
      return;
    }
    setState(() {
      _burnBusy = true;
      _burnProgress = 0;
      _status = 'Burn-in chal raha hai…';
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
            ? 'Burn-in ho gaya: ${result.outputPath}'
            : 'Burn-in fail: ${result.error}';
      });
      if (result.success) _showMessage('Captioned video save ho gaya.');
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
    _showMessage('Translations lag gaye (dual-language ON).');
  }

  Future<void> _addLineDialog() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nayi caption line'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Line likhein…',
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
            child: const Text('Add karein'),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    _edit(() => _e.addManualLine(text));
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
                    'Draft mila — pichli editing session save hui thi.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton(
                        key: const Key('restoreDraftButton'),
                        onPressed: _applyDraft,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                        ),
                        child: const Text('Draft restore karein'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _dismissDraft,
                        child: const Text('Draft hatayein'),
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
            borderRadius: BorderRadius.circular(12),
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
                    'Abhi koi subtitles nahi — pehle News Maker / AI News '
                    'Maker mein tehreer se subtitles banayein.',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),
              Positioned(
                left: 8,
                bottom: 8,
                child: project.voiceoverPath == null
                    ? const Text(
                        'Voiceover nahi — scrub slider se highlight dekhein.',
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
            'bola hua lafz green (#3AEC70) hota hai.',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          'Style — 11 looks',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: StudioCaptionStyles.all.map((style) {
            final selected = project.captionStyleId == style.id;
            return ChoiceChip(
              key: Key('captionStyle-${style.id}'),
              label: Text(style.nameEn),
              selected: selected,
              onSelected: (_) {
                setState(() => project.captionStyleId = style.id);
                _scheduleSave();
              },
            );
          }).toList(),
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
        Row(
          children: [
            const Text('Position'),
            const Spacer(),
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
        Row(
          children: [
            const Text('Size'),
            const Spacer(),
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
        Row(
          children: [
            const Text('Font'),
            const Spacer(),
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
          'Bebas / Anton / Montserrat / Poppins app mein bundle nahi — '
          'preview mein system font dikhega, ASS mein family name likha jayega.',
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
            'Har line ke neeche doosri zuban ki line (translator se ya haath se).',
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
              tooltip: 'Nayi line',
              onPressed: _addLineDialog,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton(
              key: const Key('shiftBackButton'),
              onPressed: _e.lines.isEmpty
                  ? null
                  : () => _edit(() => _e.shiftAll(-0.5)),
              child: const Text('−0.5s sab'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: const Key('shiftForwardButton'),
              onPressed: _e.lines.isEmpty
                  ? null
                  : () => _edit(() => _e.shiftAll(0.5)),
              child: const Text('+0.5s sab'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: const Key('syncVoiceoverButton'),
              onPressed: project.voiceoverDurationSec == null
                  ? null
                  : _syncWithVoiceover,
              child: const Text('Voiceover se sync'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_e.lines.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Abhi koi subtitles nahi — News Maker / AI News Maker mein '
                'tehreer likh kar voiceover banayein, phir yahan aayein.',
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${line.startSec.toStringAsFixed(1)}s – ${line.endSec.toStringAsFixed(1)}s',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ),
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
                          tooltip: 'Line split karein (beech se)',
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
                          tooltip: 'Line hatayein',
                          onPressed: () => _edit(() => _e.deleteLine(index)),
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
          'Highlight Box style ka peela box ASS mein nahi aata (ASS mein '
          'us ka equivalent nahi) — line ke colours wahi rehte hain.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 20),
        const Text(
          'Video burn-in — captions video mein jalayein',
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
                      ? 'Video chunein'
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
            label: Text(_burnBusy ? 'Burn-in chal raha hai…' : 'Video mein burn karein'),
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
        const SizedBox(height: 8),
        Text(
          _status,
          key: const Key('captionStatus'),
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        const Text(
          'Burn-in pehle styled ASS se koshish karta hai (poora style: '
          'colours, karaoke, outline, position); fail ho to per-line '
          'drawtext fallback chalta hai (Urdu us mein shape nahi hoti — '
          'drawtext ki limit hai).',
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
