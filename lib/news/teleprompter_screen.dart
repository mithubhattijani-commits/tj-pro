/// Build 13 (point 4) — TELEPROMPTER (Reporter flow).
///
/// The Reporter tool itself only ever handled a still photo
/// (import + background replace); it never recorded in-app.
/// This screen adds the recording surface the prompter needs,
/// built on the app's EXISTING camera stack — the
/// rtmp_streaming [CameraController] the Live Studio uses
/// (same initialise / audio / video settings pattern as
/// LiveService, front camera preferred here because a reporter
/// talks to the front camera). No new dependency.
///
/// The project's script (tehreer) scrolls in a translucent band
/// over the camera preview while recording. Controls: scroll
/// speed, text size, a 3-2-1 countdown before record + scroll
/// start, and a mirror toggle (for mirror-rig users — it flips
/// the SCRIPT TEXT only; the recorded video is never mirrored).
///
/// Returns the recorded file's path (Navigator result) or null
/// when the user leaves without a finished recording. Every
/// camera failure is fail-soft: the screen stays usable and the
/// status line says honestly what happened.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';

class TeleprompterScreen extends StatefulWidget {
  const TeleprompterScreen({super.key, required this.scriptText});

  /// The project's tehreer / script text.
  final String scriptText;

  @override
  State<TeleprompterScreen> createState() => _TeleprompterScreenState();
}

class _TeleprompterScreenState extends State<TeleprompterScreen> {
  CameraController? _controller;
  bool _cameraReady = false;
  String _status = 'Camera start ho raha hai…';
  final ScrollController _scrollController = ScrollController();
  Timer? _scrollTimer;
  Timer? _countdownTimer;
  bool _recording = false;
  int _countdown = 0;
  double _speedPxPerSec = 42;
  double _fontSize = 26;
  bool _mirror = false;
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
    unawaited(_initCamera());
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _countdownTimer?.cancel();
    _scrollController.dispose();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _status = 'Koi camera nahi mila.');
        }
        return;
      }
      // A reporter talks to the FRONT camera (LiveService
      // prefers back for scene streaming — different job).
      final selected = cameras.firstWhere(
        (c) => c.lensDirection.toString().contains('front'),
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        ResolutionPreset.high,
        enableAudio: true,
      );
      await controller.initialize(selected);
      await controller.setAudioSettings(128 * 1024);
      await controller.setVideoSettings(
        bitrate: 2500 * 1024,
        width: 720,
        height: 1280,
      );
      await controller.setFrameRate(30);
      if (!mounted) {
        unawaited(controller.dispose());
        return;
      }
      setState(() {
        _controller = controller;
        _cameraReady = true;
        _status = 'Camera ready — Record dabayein, pehle 3-2-1 countdown hoga.';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _cameraReady = false;
          _status = 'Camera start nahi ho saka: $e';
        });
      }
    }
  }

  void _startScroll() {
    _scrollTimer?.cancel();
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (pos.pixels >= pos.maxScrollExtent) {
        _scrollTimer?.cancel();
        return;
      }
      _scrollController.jumpTo(
        (pos.pixels + _speedPxPerSec * 0.05)
            .clamp(0.0, pos.maxScrollExtent),
      );
    });
  }

  void _stopScroll() => _scrollTimer?.cancel();

  Future<void> _toggleRecord() async {
    if (_recording) {
      await _stopRecording();
      return;
    }
    final controller = _controller;
    if (controller == null || !_cameraReady || _countdown > 0) return;
    // 3-2-1 countdown, THEN record + scroll start together.
    setState(() => _countdown = 3);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_countdown > 1) {
        setState(() => _countdown -= 1);
        return;
      }
      t.cancel();
      setState(() => _countdown = 0);
      await _beginRecording();
    });
  }

  Future<void> _beginRecording() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'news_reporter'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final path = p.join(
        dir.path,
        'prompter_${DateTime.now().millisecondsSinceEpoch}.mp4',
      );
      await controller.startVideoRecording(path);
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordingPath = path;
        _status = 'Recording… script chal raha hai.';
      });
      _startScroll();
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Recording start nahi ho saki: $e');
      }
    }
  }

  Future<void> _stopRecording() async {
    final controller = _controller;
    _stopScroll();
    if (controller == null) return;
    try {
      await controller.stopVideoRecording();
    } catch (e) {
      if (mounted) {
        setState(() {
          _recording = false;
          _status = 'Recording stop nahi ho saki: $e';
        });
      }
      return;
    }
    final path = _recordingPath;
    if (!mounted) return;
    setState(() {
      _recording = false;
      _status = 'Recording mukammal.';
    });
    if (path != null) {
      Navigator.of(context).pop(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final script = widget.scriptText.trim();
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0D12),
        title: const Text('Teleprompter'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_cameraReady && _controller != null)
                  CameraPreview(_controller!)
                else
                  const ColoredBox(color: Color(0xFF14161C)),
                // Script band: lower third of the preview.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 190,
                  child: Container(
                    key: const Key('prompterScriptBand'),
                    color: const Color(0xB3000000),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.diagonal3Values(
                        _mirror ? -1.0 : 1.0,
                        1.0,
                        1.0,
                      ),
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        child: Text(
                          script.isEmpty
                              ? 'Tehreer khaali hai — pehle Tehreer tool '
                                  'mein script likhein, phir yahan parhein.'
                              : script,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: _fontSize,
                            height: 1.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_countdown > 0)
                  Center(
                    child: Text(
                      '$_countdown',
                      style: const TextStyle(
                        fontSize: 110,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFFC800),
                      ),
                    ),
                  ),
                if (_recording)
                  const Positioned(
                    top: 12,
                    right: 12,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 12, color: Colors.red),
                        SizedBox(width: 6),
                        Text(
                          'REC',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
            child: Text(
              _status,
              key: const Key('prompterStatus'),
              style: const TextStyle(fontSize: 12, color: Color(0xFFAEB4BD)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                const Text('Speed', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    key: const Key('prompterSpeedSlider'),
                    value: _speedPxPerSec,
                    min: 10,
                    max: 120,
                    onChanged: (v) => setState(() => _speedPxPerSec = v),
                  ),
                ),
                const Text('Size', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    key: const Key('prompterTextSizeSlider'),
                    value: _fontSize,
                    min: 18,
                    max: 44,
                    onChanged: (v) => setState(() => _fontSize = v),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Row(
              children: [
                const Text('Mirror', style: TextStyle(fontSize: 12)),
                Switch(
                  key: const Key('prompterMirrorSwitch'),
                  value: _mirror,
                  onChanged: (v) => setState(() => _mirror = v),
                ),
                const Spacer(),
                FilledButton.icon(
                  key: const Key('prompterRecordButton'),
                  onPressed: _cameraReady ? _toggleRecord : null,
                  icon: Icon(_recording ? Icons.stop : Icons.fiber_manual_record),
                  label: Text(_recording ? 'Stop' : 'Record'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
