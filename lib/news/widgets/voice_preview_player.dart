/// Voiceover preview player (Phase 4).
///
/// Plays the cached voiceover WAV back with play/pause. No new audio
/// package was added (app size rule): playback uses `video_player`,
/// already a dependency — ExoPlayer/AVPlayer both handle WAV audio.
/// The duration shown comes from the WAV header
/// ([wavDurationSeconds]) so it is correct before the player even
/// initialises; the controller is created lazily on the first play
/// tap, never at build time (so screens without a voiceover never
/// touch a platform channel — widget tests included).
///
/// "Dobara" re-generates: the caller deletes the cached file and
/// re-synthesises, which costs new proxy request(s) against the
/// 5/day cap — the button label says so in the screens that use it.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../news_project.dart';

/// Formats seconds as m:ss (e.g. 42 → "0:42").
String formatVoiceDuration(double seconds) {
  final total = seconds.round();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

class VoicePreviewPlayer extends StatefulWidget {
  const VoicePreviewPlayer({
    super.key,
    required this.filePath,
    required this.durationSec,
    required this.onRegenerate,
    this.regenerating = false,
    this.voiceLabel = 'Voice',
  });

  /// Cached voiceover WAV path, or null = no voiceover yet.
  final String? filePath;

  /// Length in seconds (WAV header), or null when unknown.
  final double? durationSec;

  /// "Dobara" tap — the caller re-generates (new proxy request(s)).
  final VoidCallback onRegenerate;

  /// True while a re-generation is running (button disabled).
  final bool regenerating;

  /// Label shown next to the duration, e.g. 'Aoede'.
  final String voiceLabel;

  @override
  State<VoicePreviewPlayer> createState() => _VoicePreviewPlayerState();
}

class _VoicePreviewPlayerState extends State<VoicePreviewPlayer> {
  VideoPlayerController? _controller;
  bool _playing = false;
  bool _initialising = false;
  String? _playError;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final path = widget.filePath;
    if (path == null || _initialising) return;
    if (_controller == null) {
      setState(() {
        _initialising = true;
        _playError = null;
      });
      try {
        final controller = VideoPlayerController.file(File(path));
        await controller.initialize();
        controller.addListener(_onControllerUpdate);
        if (!mounted) {
          await controller.dispose();
          return;
        }
        setState(() {
          _controller = controller;
          _initialising = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _initialising = false;
          _playError = 'Voice play nahi hui: $e';
        });
        return;
      }
    }
    final controller = _controller!;
    if (controller.value.isPlaying) {
      await controller.pause();
      if (mounted) setState(() => _playing = false);
    } else {
      if (controller.value.position >= controller.value.duration &&
          controller.value.duration > Duration.zero) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
      if (mounted) setState(() => _playing = true);
    }
  }

  void _onControllerUpdate() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final finished = controller.value.position >=
            controller.value.duration &&
        controller.value.duration > Duration.zero &&
        !controller.value.isPlaying;
    if (finished && _playing) {
      setState(() => _playing = false);
    } else if (controller.value.isPlaying != _playing &&
        controller.value.isPlaying) {
      setState(() => _playing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.filePath;
    if (path == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.music_note, color: Colors.grey),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  // v1.5.0 (#18 dedupe): this card is the ONE
                  // no-voice message (the screen's status line no
                  // longer repeats it); the generate action it names
                  // is the trio's "Text se Audio" pill.
                  'Abhi voice nahi bani — upar "Text se Audio" se '
                  'banayein, ya Record / Import karein.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final durationLabel = widget.durationSec == null
        ? ''
        : ' • ${formatVoiceDuration(widget.durationSec!)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  key: const Key('voicePlayPause'),
                  icon: Icon(
                    _playing ? Icons.pause : Icons.play_arrow,
                  ),
                  tooltip: _playing ? 'Pause' : 'Suno',
                  onPressed: _initialising ? null : _togglePlay,
                ),
                Expanded(
                  child: Text(
                    '♪ ${widget.voiceLabel}$durationLabel',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    // v1.5.1 (overflow sweep): a long voice label
                    // ellipsizes instead of pushing the Dobara
                    // button off the row.
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  key: const Key('voiceRegenerate'),
                  onPressed:
                      widget.regenerating ? null : widget.onRegenerate,
                  icon: widget.regenerating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 16),
                  label: Text(
                    widget.regenerating ? 'Ban rahi hai…' : 'Dobara',
                  ),
                ),
              ],
            ),
            if (_playError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  _playError!,
                  style: const TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
