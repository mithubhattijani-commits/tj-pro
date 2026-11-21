/// AI Voice Studio — TTS Studio (Phase 5, mockup 1 tile 5).
///
/// Magic Box's TTS Studio, ported to TJ Pro (see
/// `lib/services/tts_studio_service.dart` for the port notes):
/// 8 voices (Aoede/Charon Gemini + Asad/Uzma Edge + Kore/Fenrir/
/// Puck/Zephyr), voice preview, auto language detect + manual
/// selector, long-text auto-split + join, Gemini↔Edge fallbacks,
/// speed 0.5–2.0x + pause between sentences, tone presets
/// (News/Story/Ad), generated background music, MP3/WAV download
/// format, live request estimate, cache-first repeats, sample texts,
/// TXT import, history (My Audio), download + share.
///
/// Economy — TJ Pro's, not Magic Box's: NO coins anywhere. Every
/// generation costs proxy requests against the SHARED 5/day cap
/// (same counter as the News Maker voiceover — admins exempt).
/// The cap line on this screen always shows the live remaining
/// count. When the cap is hit, the screen offers the on-device
/// voice (robotic, but the text still gets spoken) instead of a
/// dead end. Voice previews cost 1 request the first time per voice
/// (cached after that) — the button says so.
///
/// Look: dark navy/black + purple #7C3AED (mockups).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../services/download_service.dart';
import '../services/gemini_voice_service.dart';
import '../services/tts_history_service.dart';
import '../services/tts_processing.dart';
import '../services/tts_studio_service.dart';
import 'widgets/voice_preview_player.dart';

class TtsStudioScreen extends StatefulWidget {
  const TtsStudioScreen({super.key});

  @override
  State<TtsStudioScreen> createState() => _TtsStudioScreenState();
}

class _TtsStudioScreenState extends State<TtsStudioScreen> {
  final _service = TtsStudioService();
  final _historyService = TtsHistoryService();
  final _textController = TextEditingController();

  StudioVoice _voice = StudioVoice.aoede;
  String _langMode = 'auto'; // auto | ur | en
  TtsControls _controls = const TtsControls();
  String _tone = 'News';
  bool _music = false;
  String _format = 'wav';

  bool _busy = false;
  String _status = 'Abhi kuch nahi banaya.';
  int? _remaining;
  bool _capOfferDevice = false;

  TtsStudioResult? _result;
  double? _resultDuration;
  String? _previewPath;
  double? _previewDuration;
  bool _previewBusy = false;

  List<TtsHistoryEntry> _history = [];
  bool _historyLoaded = false;

  bool get _isEdge => _voice.engine == StudioTtsEngine.edge;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final remaining = await _service.remainingToday();
    final history = await _historyService.loadAll();
    if (!mounted) return;
    setState(() {
      _remaining = remaining;
      _history = history;
      _historyLoaded = true;
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String get _resolvedLang =>
      _langMode == 'auto' ? GeminiVoiceService.detectLang(_textController.text) : _langMode;

  int get _estimatedRequests =>
      TtsStudioService.estimatedRequests(_textController.text, _voice);

  void _applyTone(String name) {
    final controls = TtsStudioService.tonePresets[name];
    if (controls == null) return;
    setState(() {
      _tone = name;
      _controls = controls;
    });
  }

  void _onControlsChanged(TtsControls controls) {
    setState(() {
      _controls = controls;
      _tone = 'Custom';
    });
  }

  Future<void> _generate({bool deviceVoice = false}) async {
    if (_busy) return;
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showMessage('Pehle text likhein.');
      return;
    }
    setState(() {
      _busy = true;
      _capOfferDevice = false;
      _status = deviceVoice ? 'Device voice se ban rahi hai…' : 'Voice ban rahi hai…';
    });
    try {
      final result = deviceVoice
          ? await _service.generateWithDeviceVoice(
              text,
              lang: _langMode == 'auto' ? null : _langMode,
              controls: _isEdge ? const TtsControls() : _controls,
              music: _music,
              format: _format,
            )
          : await _service.generate(
              text,
              voice: _voice,
              lang: _langMode == 'auto' ? null : _langMode,
              controls: _isEdge ? const TtsControls() : _controls,
              music: _music,
              format: _format,
            );
      final remaining = await _service.remainingToday();
      if (result.filePath != null) {
        await _historyService.record(
          TtsHistoryEntry(
            id: 'tts_${DateTime.now().millisecondsSinceEpoch}',
            text: text,
            voiceId: deviceVoice ? 'device' : _voice.id,
            lang: _resolvedLang,
            ext: result.ext,
            filePath: result.filePath!,
            durationSec: result.durationSec,
            sizeBytes: result.sizeBytes,
            createdAt: DateTime.now(),
            fellBackToEdge: result.fellBackToEdge,
            fellBackToGemini: result.fellBackToGemini,
          ),
        );
      }
      final history = await _historyService.loadAll();
      if (!mounted) return;
      final notes = <String>[];
      if (result.cached) notes.add('Cached — 0 nayi requests');
      if (result.usedDeviceFallback) notes.add('Device voice use hui');
      if (result.fellBackToEdge) notes.add('Gemini fail → Edge voice use hui');
      if (result.fellBackToGemini) notes.add('Edge fail → Gemini voice use hui');
      if (result.controlsIgnored) {
        notes.add('Speed/pause Edge (MP3) par nahi lagte — audio waisa ka waisa hai');
      }
      setState(() {
        _busy = false;
        _result = result;
        _resultDuration = result.durationSec;
        _remaining = remaining;
        _history = history;
        _status = notes.isEmpty
            ? 'Nayi voice — ${result.proxyRequests} request(s) use hui.'
            : notes.join(' • ');
      });
    } on TtsStudioCapException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _capOfferDevice = true;
        _status =
            'Cap poora ho gaya — $e Same text dobara = cached (0 requests).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Voice nahi ban saki: $e';
      });
    }
  }

  Future<void> _previewVoice() async {
    if (_previewBusy) return;
    setState(() {
      _previewBusy = true;
      _status = 'Preview ban raha hai (pehli dafa 1 request)…';
    });
    try {
      final bytes = await _service.previewVoice(_voice);
      final tmp = await Directory.systemTemp.createTemp('tj_pro_preview_');
      final file = File(p.join(tmp.path, 'preview_${_voice.id}.wav'));
      await file.writeAsBytes(bytes);
      final duration = audioDurationSeconds(bytes, 'wav');
      final remaining = await _service.remainingToday();
      if (!mounted) return;
      setState(() {
        _previewBusy = false;
        _previewPath = file.path;
        _previewDuration = duration;
        _remaining = remaining;
        _status = 'Preview tayyar — ${_voice.label} ki awaz sunein.';
      });
    } on TtsStudioCapException catch (e) {
      if (!mounted) return;
      setState(() {
        _previewBusy = false;
        _status = 'Preview ke liye bhi cap chahiye: $e';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _previewBusy = false;
        _status = 'Preview nahi ban saka: $e';
      });
    }
  }

  Future<void> _importTxt() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final text = String.fromCharCodes(bytes).trim();
      if (text.isEmpty) {
        _showMessage('TXT file khaali hai.');
        return;
      }
      setState(() => _textController.text = text);
    } catch (e) {
      _showMessage('TXT import nahi hua: $e');
    }
  }

  Future<void> _downloadResult() async {
    final result = _result;
    if (result?.filePath == null) return;
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path = await DownloadService.copyFile(
        File(result!.filePath!),
        'tj_pro_voice_$stamp.${result.ext}',
      );
      _showMessage('Download folder mein save ho gaya:\n$path');
    } catch (e) {
      _showMessage('Download nahi hua: $e');
    }
  }

  Future<void> _downloadHistory(TtsHistoryEntry entry) async {
    try {
      final file = File(entry.filePath);
      if (!await file.exists()) {
        _showMessage('Ye file ab nahi hai (cache clear ho gaya).');
        return;
      }
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final path = await DownloadService.copyFile(
        file,
        'tj_pro_voice_$stamp.${entry.ext}',
      );
      _showMessage('Download folder mein save ho gaya:\n$path');
    } catch (e) {
      _showMessage('Download nahi hua: $e');
    }
  }

  Future<void> _shareFile(String path) async {
    try {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)]),
      );
    } catch (e) {
      _showMessage('Share nahi hua: $e');
    }
  }

  void _playHistory(TtsHistoryEntry entry) {
    final file = File(entry.filePath);
    if (!file.existsSync()) {
      _showMessage('Ye file ab nahi hai (cache clear ho gaya).');
      return;
    }
    setState(() {
      _result = TtsStudioResult(
        bytes: Uint8List(0),
        ext: entry.ext,
        cached: true,
        usedDeviceFallback: false,
        proxyRequests: 0,
        filePath: entry.filePath,
      );
      _resultDuration = entry.durationSec;
      _status = 'History se chala rahe hain: ${entry.summary}';
    });
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
          title: const Text('AI Voice Studio'),
          backgroundColor: const Color(0xFF080810),
        ),
        body: ListView(
          key: const Key('ttsStudioList'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            if (_remaining != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Aaj: $_remaining request(s) baaki (cap 5/day — News Maker '
                    'voiceover ke saath shared). Same text + voice = cached, '
                    '0 nayi requests. Admins (3 emails) exempt.',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'Text',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('ttsTextField'),
              controller: _textController,
              maxLines: 6,
              minLines: 5,
              decoration: const InputDecoration(
                hintText: 'Text likhein ya paste karein…',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 4),
            Text(
              '${_textController.text.length} chars • ~$_estimatedRequests request(s) • '
              '${_resolvedLang == 'ur' ? 'Urdu' : 'English'} (auto-detect)',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                ...TtsStudioService.sampleTexts.keys.map(
                  (name) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: OutlinedButton(
                      key: Key('sampleButton-$name'),
                      onPressed: () => setState(
                        () => _textController.text =
                            TtsStudioService.sampleTexts[name]!,
                      ),
                      child: Text(name),
                    ),
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  key: const Key('importTxtButton'),
                  onPressed: _importTxt,
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: const Text('TXT import'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                const Text(
                  'Language',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'auto', label: Text('Auto')),
                    ButtonSegment(value: 'ur', label: Text('اردو')),
                    ButtonSegment(value: 'en', label: Text('EN')),
                  ],
                  selected: {_langMode},
                  onSelectionChanged: (s) =>
                      setState(() => _langMode = s.first),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Voice — tap karein, phir preview sunein',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            GridView.count(
              key: const Key('voiceGrid'),
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.85,
              children: StudioVoice.all.map((voice) {
                final selected = _voice.id == voice.id;
                return InkWell(
                  key: Key('voiceCard-${voice.id}'),
                  onTap: () => setState(() => _voice = voice),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 8,
                      horizontal: 4,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF7C3AED)
                          : const Color(0xFF181828),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF7C3AED)
                            : Colors.white24,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          voice.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          voice.gender == 'Female' ? 'Female' : 'Male',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          voice.engine == StudioTtsEngine.gemini
                              ? 'Gemini'
                              : 'Edge • free',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                          ),
                        ),
                        if (selected)
                          const Icon(Icons.check, size: 16),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('voicePreviewButton'),
                onPressed: _previewBusy ? null : _previewVoice,
                icon: _previewBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow, size: 18),
                label: Text(
                  '▶ ${_voice.label} ki awaz suno (preview — pehli dafa 1 request)',
                ),
              ),
            ),
            if (_previewPath != null) ...[
              const SizedBox(height: 8),
              VoicePreviewPlayer(
                filePath: _previewPath,
                durationSec: _previewDuration,
                voiceLabel: '${_voice.label} (preview)',
                regenerating: _previewBusy,
                onRegenerate: _previewVoice,
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'Tone',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ...TtsStudioService.tonePresets.keys.map(
                  (name) => ChoiceChip(
                    key: Key('toneChip-$name'),
                    label: Text(name),
                    selected: _tone == name,
                    onSelected: (_) => _applyTone(name),
                  ),
                ),
                if (_tone == 'Custom')
                  const Chip(label: Text('Custom')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: Text('Speed')),
                SizedBox(
                  width: 200,
                  child: Slider(
                    key: const Key('speedSlider'),
                    value: _controls.speed,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label: '${_controls.speed.toStringAsFixed(2)}x',
                    onChanged: _isEdge
                        ? null
                        : (v) => _onControlsChanged(
                              TtsControls(
                                speed: v,
                                pauseSeconds: _controls.pauseSeconds,
                              ),
                            ),
                  ),
                ),
                Text('${_controls.speed.toStringAsFixed(2)}x'),
              ],
            ),
            Row(
              children: [
                const Expanded(child: Text('Pause (sentences ke beech)')),
                SizedBox(
                  width: 200,
                  child: Slider(
                    key: const Key('pauseSlider'),
                    value: _controls.pauseSeconds,
                    min: 0,
                    max: 1.0,
                    divisions: 10,
                    label: '${_controls.pauseSeconds.toStringAsFixed(1)}s',
                    onChanged: _isEdge
                        ? null
                        : (v) => _onControlsChanged(
                              TtsControls(
                                speed: _controls.speed,
                                pauseSeconds: v,
                              ),
                            ),
                  ),
                ),
                Text('${_controls.pauseSeconds.toStringAsFixed(1)}s'),
              ],
            ),
            if (_isEdge)
              const Text(
                'Edge voices (MP3) par speed/pause nahi lagte — MP3 ko '
                'decode kiye baghair resample nahi hota.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            const Text(
              'Speed resample pitch bhi badalta hai — ye normal hai '
              '(true pitch-shift ke liye phase vocoder chahiye, jo '
              'kisi bhi app mein nahi bana).',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              key: const Key('musicSwitch'),
              title: const Text('Background music (soft pad)'),
              subtitle: const Text(
                'Halki si ambient music voice ke neeche — awaz hamesha upar rehti hai.',
              ),
              value: _music,
              onChanged: (v) => setState(() => _music = v),
            ),
            Row(
              children: [
                const Text(
                  'Download format',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'wav', label: Text('WAV')),
                    ButtonSegment(value: 'mp3', label: Text('MP3')),
                  ],
                  selected: {_format},
                  onSelectionChanged: (s) =>
                      setState(() => _format = s.first),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('ttsGenerateButton'),
                onPressed: _busy ? null : () => _generate(),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.record_voice_over),
                label: Text(_busy ? 'Voice ban rahi hai…' : 'Voice banao'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _status,
              key: const Key('ttsStatus'),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            if (_capOfferDevice) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const Key('deviceVoiceButton'),
                  onPressed: _busy ? null : () => _generate(deviceVoice: true),
                  child: const Text(
                    'Device voice se banayein (robotic, par free — cap nahi lagta)',
                  ),
                ),
              ),
            ],
            if (_result?.filePath != null) ...[
              const SizedBox(height: 12),
              VoicePreviewPlayer(
                filePath: _result!.filePath,
                durationSec: _resultDuration != null && _resultDuration! > 0
                    ? _resultDuration
                    : null,
                voiceLabel: _voice.label,
                regenerating: _busy,
                onRegenerate: () => _generate(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('ttsDownloadButton'),
                      onPressed: _downloadResult,
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Download'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('ttsShareButton'),
                      onPressed: () => _shareFile(_result!.filePath!),
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            const Text(
              'My Audio — History',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (!_historyLoaded)
              const Center(child: CircularProgressIndicator())
            else if (_history.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Abhi koi history nahi — pehli voice banayein.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ..._history.map(
                (entry) => Card(
                  child: ListTile(
                    key: Key('historyEntry-${entry.id}'),
                    title: Text(
                      entry.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(entry.summary),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.play_arrow),
                          tooltip: 'Chalayein',
                          onPressed: () => _playHistory(entry),
                        ),
                        IconButton(
                          icon: const Icon(Icons.download),
                          tooltip: 'Download',
                          onPressed: () => _downloadHistory(entry),
                        ),
                        IconButton(
                          icon: const Icon(Icons.share),
                          tooltip: 'Share',
                          onPressed: () => _shareFile(entry.filePath),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'History se hatayein',
                          onPressed: () async {
                            await _historyService.remove(entry.id);
                            await _load();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'Coins: is Studio mein koi coins nahi — sirf 5/day cap. '
              'Magic Box ki coin economy yahan port nahi hui (user decision).',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
