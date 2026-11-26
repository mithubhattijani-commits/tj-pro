/// Caption Translator (Phase 5, C14) — Magic Box's translator,
/// ported to TJ Pro (see `lib/services/caption_translator_service.dart`).
///
/// On-device ML Kit translation Urdu↔English: no server, no keys,
/// no coins. The language models (~30 MB per language) download
/// once on first use (mobile data allowed) and then work offline.
///
/// Flow: paste SRT text or pick an .srt file (or start from the
/// Caption Studio's lines) → download models if needed → translate
/// line by line, keeping every line's timing → edit any translated
/// line → save the translated SRT + styled ASS (Download folder) or
/// send the translations back to the Caption Studio (dual-language).
///
/// If the model download fails (offline / no Play services), the
/// screen says so plainly instead of pretending to translate.
library;

import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/caption_service.dart';
import '../services/caption_styles.dart';
import '../services/caption_translator_service.dart';
import '../services/download_service.dart';

class CaptionTranslatorScreen extends StatefulWidget {
  const CaptionTranslatorScreen({
    super.key,
    required this.initialSegments,
    required this.fromLang,
    required this.toLang,
  });

  /// Segments to translate (from the Caption Studio, or empty when
  /// the user pastes/picks SRT instead).
  final List<CaptionSegment> initialSegments;

  /// 'ur' or 'en'.
  final String fromLang;

  /// 'ur' or 'en'.
  final String toLang;

  @override
  State<CaptionTranslatorScreen> createState() =>
      _CaptionTranslatorScreenState();
}

class _CaptionTranslatorScreenState extends State<CaptionTranslatorScreen> {
  late List<CaptionSegment> _segments;
  late List<TextEditingController> _controllers;
  late String _fromLang;
  late String _toLang;
  final _srtController = TextEditingController();

  bool _busy = false;
  String _status = '';
  int _done = 0;
  int _total = 0;
  bool _translated = false;

  @override
  void initState() {
    super.initState();
    _segments = List<CaptionSegment>.from(widget.initialSegments);
    _fromLang = widget.fromLang;
    _toLang = widget.toLang;
    _controllers = _segments
        .map((s) => TextEditingController(text: s.text))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    _srtController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String get _directionLabel =>
      _fromLang == 'ur' ? 'Urdu → English' : 'English → Urdu';

  void _swapDirection() {
    setState(() {
      final tmp = _fromLang;
      _fromLang = _toLang;
      _toLang = tmp;
      _translated = false;
    });
  }

  void _loadFromSrtText(String srt) {
    try {
      final segments = CaptionService.parseSrt(srt);
      setState(() {
        for (final c in _controllers) {
          c.dispose();
        }
        _segments = segments;
        _controllers =
            segments.map((s) => TextEditingController(text: s.text)).toList();
        _translated = false;
        _status = '${segments.length} lines loaded.';
      });
    } catch (_) {
      _showMessage('No caption found in the SRT — check again.');
    }
  }

  Future<void> _pickSrtFile() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['srt'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      _loadFromSrtText(utf8.decode(bytes));
    } catch (e) {
      _showMessage('SRT file did not open: $e');
    }
  }

  Future<void> _translate() async {
    if (_segments.isEmpty) {
      _showMessage('Paste the SRT first or choose a file.');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _done = 0;
      _total = _segments.length;
      _status = 'Checking the translation model… (the first time ~30 MB downloads)';
    });
    try {
      await CaptionTranslatorService.ensureModels(
        fromLang: _fromLang,
        toLang: _toLang,
      );
      final translated = await CaptionTranslatorService.translateSegments(
        segments: _segments,
        fromLang: _fromLang,
        toLang: _toLang,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
              _done = done;
              _total = total;
              _status = 'Translating… $done/$total';
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < translated.length; i++) {
          _controllers[i].text = translated[i].text;
        }
        _busy = false;
        _translated = true;
        _status = 'Translated — you can edit any line.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Translation failed: $e';
      });
    }
  }

  List<CaptionSegment> _currentTranslated() {
    return [
      for (var i = 0; i < _segments.length; i++)
        CaptionSegment(
          _controllers[i].text.trim(),
          _segments[i].start,
          _segments[i].end,
          words: _segments[i].words,
        ),
    ];
  }

  Future<void> _saveTranslated(String kind) async {
    if (!_translated) {
      _showMessage('Translate first.');
      return;
    }
    final segments = _currentTranslated();
    final (fileName, content) = switch (kind) {
      'srt' => (
          'tj_pro_translated.srt',
          CaptionService.buildSrt(segments),
        ),
      'ass' => (
          'tj_pro_translated.ass',
          CaptionService.buildStyledAss(
            segments,
            StudioCaptionStyles.byId('nigraan'),
            fontFamily: 'Arial',
          ),
        ),
      _ => ('tj_pro_translated.srt', ''),
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
          title: const Text('Caption Translator'),
          backgroundColor: const Color(0xFF080810),
        ),
        body: ListView(
          key: const Key('translatorList'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _directionLabel,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('swapDirectionButton'),
                  icon: const Icon(Icons.swap_horiz),
                  tooltip: 'Direction badlein',
                  onPressed: _busy ? null : _swapDirection,
                ),
              ],
            ),
            const Text(
              'On-device ML Kit translation — no server, no coins. Model '
              'the first time ~30 MB downloads, then it runs offline.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (_segments.isEmpty) ...[
              TextField(
                key: const Key('srtPasteField'),
                controller: _srtController,
                maxLines: 6,
                minLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Paste SRT text here…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('loadSrtButton'),
                      onPressed: () =>
                          _loadFromSrtText(_srtController.text),
                      child: const Text('Load SRT'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('pickSrtButton'),
                      onPressed: _pickSrtFile,
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: const Text('Choose a .srt file'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(
                '${_segments.length} lines — the timings stay the same, '
                'only the text is translated.',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('translateButton'),
                  onPressed: _busy ? null : _translate,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.translate),
                  label: Text(_busy ? 'Translating…' : 'Translate'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (_busy && _total > 0) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: _done / _total),
              ],
              const SizedBox(height: 8),
              Text(
                _status,
                key: const Key('translatorStatus'),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 12),
              ...List.generate(_segments.length, (index) {
                final seg = _segments[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${CaptionService.formatClock(seg.start)} – '
                          '${CaptionService.formatClock(seg.end)} • '
                          'Original: ${seg.text}',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          key: Key('translatedLine-$index'),
                          controller: _controllers[index],
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'Translated line (you can edit)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      key: const Key('saveTranslatedSrtButton'),
                      onPressed: _translated ? () => _saveTranslated('srt') : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                      ),
                      child: const Text('Save translated SRT'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      key: const Key('saveTranslatedAssButton'),
                      onPressed: _translated ? () => _saveTranslated('ass') : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED),
                      ),
                      child: const Text('Save translated ASS'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const Key('applyTranslationsButton'),
                  onPressed: _translated
                      ? () => Navigator.of(context).pop(_currentTranslated())
                      : null,
                  child: const Text(
                    'Apply as dual-language in Caption Studio',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
