/// MOTION GRAPHICS STUDIO — full-screen template preview
/// (Build M1, v1.11.0; Editor button added in M2, v1.14.0).
///
/// What a Gallery tap opens: the template playing large
/// through the shared engine painter, with real transport
/// (play/pause, restart, scrub), the template's facts, and —
/// since M2 — the real "Edit" button into the Editor
/// (text/logo/rang/timing + Save + Video par Lagao).
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'motion_editor_screen.dart';
import 'motion_painter.dart';
import 'motion_templates.dart';

const Color _kBg = Color(0xFF04060F);
const Color _kCyan = Color(0xFF00C6FF);
const Color _kBlue = Color(0xFF2F7BFF);
const Color _kPurple = Color(0xFF7B2FFF);

class MotionPreviewScreen extends StatefulWidget {
  const MotionPreviewScreen({super.key, required this.template});

  final MotionTemplate template;

  @override
  State<MotionPreviewScreen> createState() => _MotionPreviewScreenState();
}

class _MotionPreviewScreenState extends State<MotionPreviewScreen>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _last = Duration.zero;
  double _t = 0;
  bool _playing = true;

  double get _duration => widget.template.durationSec;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final delta = elapsed - _last;
    _last = elapsed;
    if (!_playing || _duration <= 0) return;
    setState(() {
      _t = (_t + delta.inMicroseconds / 1000000.0) % _duration;
    });
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          t.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CustomPaint(
                    key: const Key('motionPreviewCanvas'),
                    painter: MotionScenePainter(
                      scene: t.scene,
                      t: _t,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(
                children: [
                  IconButton(
                    key: const Key('motionPlayPause'),
                    onPressed: () =>
                        setState(() => _playing = !_playing),
                    icon: Icon(
                      _playing ? Icons.pause_circle : Icons.play_circle,
                      color: _kCyan,
                      size: 34,
                    ),
                  ),
                  IconButton(
                    key: const Key('motionRestart'),
                    onPressed: () => setState(() => _t = 0),
                    icon: const Icon(
                      Icons.replay,
                      color: Colors.white70,
                      size: 24,
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: _kBlue,
                        inactiveTrackColor: Colors.white12,
                        thumbColor: _kCyan,
                        trackHeight: 3,
                      ),
                      child: Slider(
                        key: const Key('motionScrubber'),
                        value: _t.clamp(0, _duration),
                        min: 0,
                        max: _duration,
                        onChanged: (v) => setState(() {
                          _t = v;
                          _playing = false;
                        }),
                      ),
                    ),
                  ),
                  Text(
                    '${_t.toStringAsFixed(1)} / '
                    '${_duration.toStringAsFixed(1)}s',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${MotionCategories.labels[t.category] ?? t.category}'
                    ' • ${_duration.toStringAsFixed(0)} seconds'
                    ' • ${t.scene.layers.length} layers',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12.5,
                    ),
                  ),
                  if (t.slots.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'Change in the editor:',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in t.slots)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0C1428),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _kPurple.withValues(alpha: 0.55),
                              ),
                            ),
                            child: Text(
                              s,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  // M2: the real Editor — text/logo/rang/timing
                  // badlein, My Templates mein save karein, aur
                  // "Video par Lagao" se Video Editor mein PIP
                  // overlay lagayein.
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      key: const Key('motionEditButton'),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              MotionEditorScreen(template: t),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBlue,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.edit_outlined, size: 19),
                      label: const Text(
                        'Edit',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
