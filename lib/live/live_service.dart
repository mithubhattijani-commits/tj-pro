/// Live Studio streaming engine (TJ Pro v2).
///
/// Publishes ONE camera feed to Facebook AND/OR YouTube at the same time
/// via the rtmp_streaming plugin's multi-destination RTMP support
/// (v2.0.1: goLive takes an `only` filter for the per-live platform
/// choice; with no filter it still publishes to every saved key).
/// (RootEncoder on Android). No relay server is involved in v2: the
/// phone encodes once and the plugin fans the stream out to both
/// RTMP endpoints. That costs extra battery and mobile data versus a
/// single stream — the UI says so honestly, and a relay server stays
/// a future option if dual publish ever proves too heavy.
///
/// Overlays: the news template is composited into ONE transparent PNG
/// (see renderLiveTemplateImage) and pushed through the streamer's
/// overlay-image slot on a timer while live. The breaking headline
/// travels inside that same image, so the broadcast always shows the
/// full template — banner, lower-third, ticker, clock, logo — not
/// just the camera feed. Overlay refresh failures are swallowed: a
/// failed refresh must never kill a live stream.
///
/// Stream keys are NEVER logged here. They arrive from
/// StreamKeyStore, are used only to build RTMP URLs, and are dropped
/// as soon as the stream stops.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rtmp_streaming/rtmp_streaming.dart';

import 'news_template.dart';
import 'stream_key_store.dart';

/// Per-platform live state shown in the UI.
enum LiveDestinationState { stopped, starting, live, failed }

class LiveService {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _ready = false;
  bool _live = false;
  Timer? _overlayTimer;
  Timer? _statsTimer;
  double _tickerPx = 0;
  NewsTemplate _template = NewsTemplate();

  /// Human-readable status line for the Live screen.
  final ValueNotifier<String> status = ValueNotifier<String>('Not live');

  /// Live state per destination id ('facebook' / 'youtube').
  final ValueNotifier<Map<String, LiveDestinationState>> destinations =
      ValueNotifier<Map<String, LiveDestinationState>>({});

  /// Latest encoder stats line (fps/bitrate), best-effort.
  final ValueNotifier<String> statsLine = ValueNotifier<String>('');

  bool get isReady => _ready;
  bool get isLive => _live;
  NewsTemplate get template => _template;

  void setTemplate(NewsTemplate template) {
    _template = template;
  }

  /// Camera preview widget for the Live screen. Returns null until the
  /// camera is initialized.
  Widget? previewWidget() {
    final controller = _controller;
    if (controller == null || !_ready) return null;
    return CameraPreview(controller);
  }

  /// Initializes the camera (back camera preferred). Safe to call
  /// repeatedly; a second call is a no-op once ready.
  Future<bool> initCamera() async {
    if (_ready && _controller != null) return true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        status.value = 'No camera found.';
        return false;
      }
      final selected = cameras.firstWhere(
        (c) => c.lensDirection.toString().contains('back'),
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        ResolutionPreset.high,
        enableAudio: true,
      );
      await controller.initialize(selected);
      // News-live encode: 720x1280 portrait at ~2.5 Mbps, 30 fps,
      // 128 kbps AAC. Portrait matches phone-first news viewing.
      await controller.setAudioSettings(128 * 1024);
      await controller.setVideoSettings(
        bitrate: 2500 * 1024,
        width: 720,
        height: 1280,
      );
      await controller.setFrameRate(30);
      _controller = controller;
      _cameras = cameras;
      _cameraIndex = cameras.indexOf(selected);
      _ready = true;
      status.value = 'Camera ready.';
      return true;
    } catch (e) {
      status.value = 'Camera could not start: $e';
      return false;
    }
  }

  /// One-tap Live: publishes to the selected platforms. With no
  /// [only] filter it publishes to every platform whose key is saved
  /// (the v2.0.0 default); with a filter it publishes only to the
  /// platforms named there — the per-live choice from the Live
  /// Studio selector. Returns true when at least one destination
  /// started.
  Future<bool> goLive({Set<String>? only}) async {
    if (_live) return true;
    final keys = await StreamKeyStore.load();
    final targets = <StreamDestination>[];
    final states = <String, LiveDestinationState>{};
    if (keys.facebook != null &&
        (only == null || only.contains('facebook'))) {
      targets.add(
        StreamDestination(
          url: StreamKeyStore.facebookRtmpUrl(keys.facebook!),
          protocol: StreamingProtocol.rtmp,
          id: 'facebook',
        ),
      );
      states['facebook'] = LiveDestinationState.starting;
    }
    if (keys.youtube != null &&
        (only == null || only.contains('youtube'))) {
      targets.add(
        StreamDestination(
          url: StreamKeyStore.youTubeRtmpUrl(keys.youtube!),
          protocol: StreamingProtocol.rtmp,
          id: 'youtube',
        ),
      );
      states['youtube'] = LiveDestinationState.starting;
    }
    if (targets.isEmpty) {
      status.value =
          'Save the Facebook or YouTube stream key first.';
      return false;
    }
    if (!await initCamera()) return false;
    final controller = _controller;
    if (controller == null) return false;
    destinations.value = states;
    status.value = 'Live is connecting…';
    try {
      await controller.startMultiStreaming(targets);
      _live = true;
      for (final id in states.keys) {
        states[id] = LiveDestinationState.live;
      }
      destinations.value = Map.of(states);
      status.value = 'LIVE — ${targets.length} platform(s)';
      _startOverlayLoop();
      _startStatsLoop();
      return true;
    } catch (e) {
      // One failed start must not leave a half-live state behind.
      try {
        await controller.stopMultiStreaming();
      } catch (_) {}
      for (final id in states.keys) {
        states[id] = LiveDestinationState.failed;
      }
      destinations.value = Map.of(states);
      status.value = 'Live could not start: $e';
      return false;
    }
  }

  /// Stops every destination and the overlay loop.
  Future<void> stopLive() async {
    _overlayTimer?.cancel();
    _overlayTimer = null;
    _statsTimer?.cancel();
    _statsTimer = null;
    try {
      await _controller?.clearOverlay();
    } catch (_) {}
    try {
      await _controller?.stopMultiStreaming();
    } catch (_) {}
    _live = false;
    destinations.value = {};
    statsLine.value = '';
    status.value = 'Live has ended.';
  }

  /// Stops ONE platform, keeping the other live.
  Future<void> stopDestination(String id) async {
    try {
      await _controller?.stopStreamingDestination(id);
    } catch (_) {}
    final states = Map.of(destinations.value);
    states[id] = LiveDestinationState.stopped;
    destinations.value = states;
    if (!states.values.contains(LiveDestinationState.live)) {
      _live = false;
      _overlayTimer?.cancel();
      _overlayTimer = null;
      _statsTimer?.cancel();
      _statsTimer = null;
      status.value = 'Live has ended.';
    }
  }

  /// Switches front/back camera. While live it uses the plugin's
  /// native switch (takes the target camera's [CameraDescription.name]);
  /// before going live it re-initializes the preview with the other
  /// camera, which always works. A failed live switch never kills
  /// the stream — it only reports the failure.
  Future<void> switchCamera() async {
    if (_cameras.length < 2 || _controller == null) return;
    final next = (_cameraIndex + 1) % _cameras.length;
    final target = _cameras[next];
    if (_live) {
      // CameraDescription.name is nullable in 2.1.1; a null name
      // cannot be passed to the native switch — report, don't crash
      // or kill the live stream.
      final targetName = target.name;
      if (targetName == null) {
        status.value = 'Camera switch failed (camera name not found).';
        return;
      }
      try {
        await _controller?.switchCamera(targetName);
        _cameraIndex = next;
      } catch (_) {
        status.value = 'Camera switch failed (during live).';
      }
      return;
    }
    try {
      await _controller?.dispose();
      _controller = null;
      _ready = false;
      final controller = CameraController(
        ResolutionPreset.high,
        enableAudio: true,
      );
      await controller.initialize(target);
      await controller.setAudioSettings(128 * 1024);
      await controller.setVideoSettings(
        bitrate: 2500 * 1024,
        width: 720,
        height: 1280,
      );
      await controller.setFrameRate(30);
      _controller = controller;
      _cameraIndex = next;
      _ready = true;
    } catch (e) {
      status.value = 'Camera switch failed: $e';
    }
  }

  /// Mic mute. Uses setHasAudio (present in 2.1.1); the prose docs'
  /// setAudioMuted does NOT exist on 2.1.1's CameraController
  /// (first release build failed on exactly that name).
  Future<void> setMuted(bool muted) async {
    try {
      await _controller?.setHasAudio(!muted);
    } catch (_) {}
  }

  /// Refreshes the composited template image in the broadcast twice a
  /// second: the ticker slides, the clock ticks, the logo slowly
  /// rotates when enabled. Every refresh is best-effort — a failure
  /// only skips that frame, it never stops the stream.
  void _startOverlayLoop() {
    _overlayTimer?.cancel();
    _tickerPx = 0;
    _overlayTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) async {
        if (!_live) return;
        final controller = _controller;
        if (controller == null) return;
        try {
          final dir = await getTemporaryDirectory();
          _tickerPx += 45;
          final file = await renderLiveTemplateImage(
            template: _template,
            tickerPx: _tickerPx,
            now: DateTime.now(),
            dir: dir,
          );
          await controller.setOverlayImage(
            filePath: file.path,
            position: OverlayPosition.topLeft,
          );
        } catch (_) {
          // Skip this frame; the next refresh retries.
        }
      },
    );
  }

  void _startStatsLoop() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) async {
        if (!_live) return;
        try {
          final stats = await _controller?.getStreamStatistics();
          if (stats == null) return;
          final fps = stats.fps;
          final bitrate = stats.bitrate;
          if (fps != null || bitrate != null) {
            statsLine.value =
                '${fps ?? '?'} fps • ${bitrate != null ? (bitrate / 1024).round() : '?'} kbps';
          }
        } catch (_) {}
      },
    );
  }

  Future<void> dispose() async {
    _overlayTimer?.cancel();
    _statsTimer?.cancel();
    status.dispose();
    destinations.dispose();
    statsLine.dispose();
    try {
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
    _ready = false;
    _live = false;
  }
}
