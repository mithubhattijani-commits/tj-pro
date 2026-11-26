/// Audio Tools — Converter + Trimmer (Phase 5, audio tools).
///
/// Magic Box's Audio Converter + Audio Trimmer, ported to TJ Pro
/// (see `lib/services/audio_tools_service.dart` for the port notes):
/// output formats MP3 / WAV / M4A / OGG, bitrate, sample rate,
/// channels, trim, speed, volume, loudnorm normalise, fade in/out,
/// ID3 title/artist, video-to-audio extraction, and trim/join of
/// WAV + MP3 files (pure Dart, no re-encode).
///
/// No coins, no ads: conversions run with on-device ffmpeg and cost
/// nothing. Batch convert and re-generate mode are NOT here (batch =
/// the same convert run per file; re-generate = the AI Voice
/// Studio's job).
///
/// Look: dark navy/black + purple #7C3AED (mockups).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../services/audio_tools_service.dart';

class AudioToolsScreen extends StatefulWidget {
  const AudioToolsScreen({super.key});

  @override
  State<AudioToolsScreen> createState() => _AudioToolsScreenState();
}

class _AudioToolsScreenState extends State<AudioToolsScreen> {
  String? _inputPath;
  Uint8List? _inputBytes;
  double? _inputDuration;
  bool _isVideo = false;

  ConvertFormat _format = ConvertFormat.mp3;
  int _bitrate = 192;
  int _sampleRate = 44100;
  int _channels = 2;
  double _speed = 1.0;
  double _volume = 1.0;
  bool _loudnorm = false;
  final _trimStartController = TextEditingController(text: '0');
  final _trimEndController = TextEditingController();
  final _fadeInController = TextEditingController(text: '0');
  final _fadeOutController = TextEditingController(text: '0');
  final _titleController = TextEditingController();
  final _artistController = TextEditingController();

  bool _busy = false;
  String _status = 'Choose an audio or video file first.';
  String? _outputPath;

  @override
  void dispose() {
    _trimStartController.dispose();
    _trimEndController.dispose();
    _fadeInController.dispose();
    _fadeOutController.dispose();
    _titleController.dispose();
    _artistController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool get _hasInput => _inputPath != null;

  double _parseDouble(TextEditingController c, double fallback) {
    final v = double.tryParse(c.text.trim());
    return (v == null || v < 0) ? fallback : v;
  }

  Future<void> _pickFile() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: [
          'mp3',
          'wav',
          'm4a',
          'aac',
          'ogg',
          'flac',
          'mp4',
          'mov',
          'mkv',
          'webm',
        ],
      );
      if (file == null) return;
      final path = file.path;
      if (path == null) return;
      final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
      final isVideo = ['mp4', 'mov', 'mkv', 'webm'].contains(ext);
      Uint8List? bytes;
      double? duration;
      if (!isVideo) {
        try {
          bytes = await File(path).readAsBytes();
          duration = AudioToolsService.audioDurationSeconds(bytes);
        } catch (_) {}
      }
      setState(() {
        _inputPath = path;
        _inputBytes = bytes;
        _inputDuration = duration;
        _isVideo = isVideo;
        _outputPath = null;
        _trimEndController.text =
            duration == null ? '' : duration.toStringAsFixed(1);
        _status = isVideo
            ? 'Video chosen — you can extract the audio.'
            : duration == null
                ? 'Audio chosen (duration could not be read).'
                : 'Audio chosen — ${duration.toStringAsFixed(1)}s.';
      });
    } catch (e) {
      _showMessage('File could not be picked: $e');
    }
  }

  ConvertOptions _currentOptions() {
    final trimStart = _parseDouble(_trimStartController, 0);
    final trimEndText = _trimEndController.text.trim();
    final trimEnd =
        trimEndText.isEmpty ? null : double.tryParse(trimEndText);
    return ConvertOptions(
      format: _format,
      bitrateKbps: _bitrate,
      sampleRate: _sampleRate,
      channels: _channels,
      trimStartSec: trimStart > 0 ? trimStart : null,
      trimEndSec: trimEnd,
      speed: _speed,
      volume: _volume,
      loudnorm: _loudnorm,
      fadeInSec: _parseDouble(_fadeInController, 0),
      fadeOutSec: _parseDouble(_fadeOutController, 0),
      title: _titleController.text.trim().isEmpty
          ? null
          : _titleController.text.trim(),
      artist: _artistController.text.trim().isEmpty
          ? null
          : _artistController.text.trim(),
    );
  }

  Future<void> _convert() async {
    if (!_hasInput || _busy) return;
    setState(() {
      _busy = true;
      _status = 'Converting…';
      _outputPath = null;
    });
    try {
      final result = await AudioToolsService.convertFile(
        input: File(_inputPath!),
        options: _currentOptions(),
        inputDurationSec: _inputDuration,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _outputPath = result.outputPath;
        _status = 'Converted — ${result.bytes} bytes.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Convert fail: $e';
      });
    }
  }

  Future<void> _extractAudio() async {
    if (!_hasInput || _busy) return;
    setState(() {
      _busy = true;
      _status = 'Extracting audio…';
      _outputPath = null;
    });
    try {
      final result = await AudioToolsService.extractAudioFromVideo(
        video: File(_inputPath!),
        format: _format,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _outputPath = result.outputPath;
        _status = 'Audio extracted — ${result.bytes} bytes.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Audio could not be extracted: $e';
      });
    }
  }

  Future<void> _trimOnly() async {
    if (!_hasInput || _busy) return;
    final bytes = _inputBytes;
    if (bytes == null) {
      _showMessage('Trim needs an audio file (not a video).');
      return;
    }
    final start = _parseDouble(_trimStartController, 0);
    final endText = _trimEndController.text.trim();
    final end = endText.isEmpty
        ? _inputDuration
        : double.tryParse(endText);
    if (end == null || end <= start) {
      _showMessage('The trim range is wrong — the end must be greater than the start.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Trimming…';
      _outputPath = null;
    });
    try {
      final trimmed = AudioToolsService.trimAudio(bytes, start, end);
      final ext = p.extension(_inputPath!).toLowerCase();
      final outPath = p.join(
        p.dirname(_inputPath!),
        '${p.basenameWithoutExtension(_inputPath!)}_trimmed$ext',
      );
      await File(outPath).writeAsBytes(trimmed);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _outputPath = outPath;
        _status = 'Trimmed — ${trimmed.length} bytes (no re-encode).';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Trim fail: $e';
      });
    }
  }

  Future<void> _joinFiles() async {
    if (_busy) return;
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav'],
      );
      if (picked.length < 2) {
        _showMessage('Choose at least 2 files to join.');
        return;
      }
      setState(() {
        _busy = true;
        _status = 'Joining…';
        _outputPath = null;
      });
      final files = <Uint8List>[];
      var firstPath = '';
      for (final f in picked) {
        if (f.path == null) continue;
        if (firstPath.isEmpty) firstPath = f.path!;
        files.add(await File(f.path!).readAsBytes());
      }
      final joined = AudioToolsService.joinAudio(files);
      final ext = p.extension(firstPath).toLowerCase();
      final outPath = p.join(
        p.dirname(firstPath),
        'tj_pro_joined$ext',
      );
      await File(outPath).writeAsBytes(joined);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _outputPath = outPath;
        _status = 'Joined — ${joined.length} bytes.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Join fail: $e';
      });
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
          title: const Text('Audio Tools'),
          backgroundColor: const Color(0xFF080810),
        ),
        body: ListView(
          key: const Key('audioToolsList'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('pickAudioButton'),
                onPressed: _busy ? null : _pickFile,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.audio_file, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _inputPath == null
                            ? 'Choose an audio / video file'
                            : _inputPath!.split('/').last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_inputDuration != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Duration: ${_inputDuration!.toStringAsFixed(1)}s'
                  '${_isVideo ? ' • video (extract ke liye)' : ''}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            const SizedBox(height: 20),
            const Text(
              'Converter',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Format'),
                const SizedBox(width: 12),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: SegmentedButton<ConvertFormat>(
                      segments: const [
                        ButtonSegment(
                            value: ConvertFormat.mp3, label: Text('MP3')),
                        ButtonSegment(
                            value: ConvertFormat.wav, label: Text('WAV')),
                        ButtonSegment(
                            value: ConvertFormat.m4a, label: Text('M4A')),
                        ButtonSegment(
                            value: ConvertFormat.ogg, label: Text('OGG')),
                      ],
                      selected: {_format},
                      onSelectionChanged: (s) =>
                          setState(() => _format = s.first),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Bitrate'),
                const Spacer(),
                DropdownButton<int>(
                  key: const Key('bitrateDropdown'),
                  value: _bitrate,
                  items: [128, 192, 320]
                      .map((b) => DropdownMenuItem(
                            value: b,
                            child: Text('$b kbps'),
                          ))
                      .toList(),
                  onChanged: _format.isLossy
                      ? (v) {
                          if (v != null) setState(() => _bitrate = v);
                        }
                      : null,
                ),
              ],
            ),
            if (!_format.isLossy)
              const Text(
                'WAV is lossless — bitrate does not apply.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            Row(
              children: [
                const Text('Sample rate'),
                const Spacer(),
                DropdownButton<int>(
                  key: const Key('sampleRateDropdown'),
                  value: _sampleRate,
                  items: [44100, 48000]
                      .map((r) => DropdownMenuItem(
                            value: r,
                            child: Text('$r Hz'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _sampleRate = v);
                  },
                ),
              ],
            ),
            Row(
              children: [
                const Text('Channels'),
                const SizedBox(width: 12),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 1, label: Text('Mono')),
                        ButtonSegment(value: 2, label: Text('Stereo')),
                      ],
                      selected: {_channels},
                      onSelectionChanged: (s) =>
                          setState(() => _channels = s.first),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: Text('Trim start (s)')),
                SizedBox(
                  width: 90,
                  child: TextField(
                    key: const Key('trimStartField'),
                    controller: _trimStartController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Trim end (s)')),
                SizedBox(
                  width: 90,
                  child: TextField(
                    key: const Key('trimEndField'),
                    controller: _trimEndController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Expanded(child: Text('Speed')),
                SizedBox(
                  width: 200,
                  child: Slider(
                    key: const Key('convertSpeedSlider'),
                    value: _speed,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label: '${_speed.toStringAsFixed(2)}x',
                    onChanged: (v) => setState(() => _speed = v),
                  ),
                ),
                Text('${_speed.toStringAsFixed(2)}x'),
              ],
            ),
            const Text(
              'Speed also changes the pitch (resample — not a true pitch-shift).',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            Row(
              children: [
                const Expanded(child: Text('Volume')),
                SizedBox(
                  width: 200,
                  child: Slider(
                    key: const Key('volumeSlider'),
                    value: _volume,
                    min: 0.0,
                    max: 2.0,
                    divisions: 20,
                    label: '${_volume.toStringAsFixed(2)}x',
                    onChanged: _loudnorm
                        ? null
                        : (v) => setState(() => _volume = v),
                  ),
                ),
                Text('${_volume.toStringAsFixed(2)}x'),
              ],
            ),
            SwitchListTile(
              key: const Key('loudnormSwitch'),
              title: const Text('Loudnorm normalise'),
              subtitle: const Text(
                'More than volume gain — if loudnorm is on, the volume is ignored.',
              ),
              value: _loudnorm,
              onChanged: (v) => setState(() => _loudnorm = v),
            ),
            Row(
              children: [
                const Expanded(child: Text('Fade in (s)')),
                SizedBox(
                  width: 90,
                  child: TextField(
                    key: const Key('fadeInField'),
                    controller: _fadeInController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Fade out (s)')),
                SizedBox(
                  width: 90,
                  child: TextField(
                    key: const Key('fadeOutField'),
                    controller: _fadeOutController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('audioTitleField'),
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title (ID3 metadata, optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('audioArtistField'),
              controller: _artistController,
              decoration: const InputDecoration(
                labelText: 'Artist (ID3 metadata, optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('convertButton'),
                onPressed: !_hasInput || _busy ? null : _convert,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.transform),
                label: Text(_busy ? 'Running…' : 'Convert'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('extractAudioButton'),
                    onPressed: !_hasInput || !_isVideo || _busy
                        ? null
                        : _extractAudio,
                    child: const Text('Extract audio from video'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const Key('trimOnlyButton'),
                    onPressed: !_hasInput || _isVideo || _busy
                        ? null
                        : _trimOnly,
                    child: const Text('Trim only'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('joinAudioButton'),
                onPressed: _busy ? null : _joinFiles,
                icon: const Icon(Icons.merge_type, size: 18),
                label: const Text('Join 2+ audio files'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _status,
              key: const Key('audioToolsStatus'),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            if (_outputPath != null) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Output',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _outputPath!,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        key: const Key('openOutputButton'),
                        onPressed: () => OpenFilex.open(_outputPath!),
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Open file'),
                      ),
                    ],
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
