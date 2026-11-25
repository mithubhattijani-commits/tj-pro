/// Keyed logo-video preview (Build 12, v1.9.0 — fix-list
/// point #13).
///
/// A logo VIDEO's background is removed by [LogoKeyService]
/// into a directory of alpha PNG frames. This widget plays
/// those frames as a flipbook, so the News Studio preview
/// shows the HONEST keyed result — the logo floating
/// background-free, moving exactly as the source video moves —
/// instead of pretending a chroma shader exists in the
/// preview. The export overlays the same frames (or keys the
/// video in-graph), so preview and export agree.
///
/// Fail-soft: a missing/empty frames directory shows
/// [fallback] (the keyed still, or the channel tile).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

class KeyedLogoFlipbook extends StatefulWidget {
  const KeyedLogoFlipbook({
    super.key,
    required this.framesDir,
    required this.fallback,
    this.width,
    this.height,
    this.fps = 12,
  });

  /// Directory holding `frame_*.png` keyed frames, or null.
  final String? framesDir;

  /// Shown when no keyed frames are available.
  final Widget fallback;

  final double? width;
  final double? height;
  final int fps;

  @override
  State<KeyedLogoFlipbook> createState() => _KeyedLogoFlipbookState();
}

class _KeyedLogoFlipbookState extends State<KeyedLogoFlipbook> {
  List<File> _frames = const [];
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(KeyedLogoFlipbook oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.framesDir != oldWidget.framesDir) {
      _timer?.cancel();
      _index = 0;
      _frames = const [];
      _load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _load() {
    final dirPath = widget.framesDir;
    if (dirPath == null || dirPath.isEmpty) return;
    final dir = Directory(dirPath);
    // Synchronous listing: the directory is small (≤96 frames)
    // and the widget must know on first build whether frames
    // exist at all (fallback vs flipbook).
    try {
      if (!dir.existsSync()) return;
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      if (files.isEmpty) return;
      _frames = files;
      _timer = Timer.periodic(
        Duration(milliseconds: (1000 / widget.fps).round()),
        (_) {
          if (!mounted) return;
          setState(() => _index = (_index + 1) % _frames.length);
        },
      );
    } catch (_) {
      // Unreadable directory → fallback shows.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_frames.isEmpty) return widget.fallback;
    final frame = _frames[_index % _frames.length];
    return Image.file(
      frame,
      width: widget.width,
      height: widget.height,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => widget.fallback,
    );
  }
}
