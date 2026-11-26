/// MOTION GRAPHICS STUDIO — Editor (Build M2, v1.14.0).
///
/// Opens from a Gallery template (via the Preview screen's
/// "Edit") or from a saved My Template. Everything here
/// edits the REAL scene model through copyWith: text, fonts,
/// colours, background, size/position, timing, entrance/exit
/// style, ticker speed/direction, counter numbers, and the
/// image on image layers. "Save Template" writes the scene to
/// the My Templates store; "Video par Lagao" renders the scene
/// to a transparent WebM (VP9 alpha — the format the M1 probe
/// verifies) and hands it to the Video Editor as a PIP overlay;
/// when the alpha encode fails it falls back to an MP4 on the
/// scene's own background and SAYS so — no fake buttons, no
/// silent format swap (the master prompt's honesty rule).
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/feature_gate.dart';
import '../services/ffmpeg_service.dart';
import '../video/video_editor_screen.dart';
import 'motion_my_templates.dart';
import 'motion_painter.dart';
import 'motion_render.dart';
import 'motion_scene.dart';
import 'motion_templates.dart';

const Color _kBg = Color(0xFF03040A);
const Color _kCyan = Color(0xFF00E5FF);
const Color _kBlue = Color(0xFF2979FF);
const Color _kPurple = Color(0xFF7C4DFF);
const Color _kCard = Color(0xFF0D1830);

/// Colour palette offered by every colour control.
const List<int> _kPalette = [
  0xFFFFFFFF,
  0xFF000000,
  0xFFFFC800,
  0xFF2979FF,
  0xFF00E5FF,
  0xFF7C4DFF,
  0xFFFF1744,
  0xFF880C03,
  0xFF00E676,
  0xFFFF9100,
  0xFF0B1026,
  0xFF081E46,
];

/// Entrance/exit style ids (AnimPresets) the Editor offers.
/// 'none' clears the preset.
const List<String> _kStyleIds = [
  'none',
  'fadeIn',
  'slideUp',
  'slideDown',
  'slideLeft',
  'slideRight',
  'popIn',
  'zoomIn',
  'bounceIn',
  'flashLabel',
  'pulse',
];

/// Font choices: null = the template's default rendering.
const List<(String?, String)> _kFonts = [
  (null, 'Default'),
  ('Noto Nastaliq Urdu', 'Nastaliq'),
  ('Noto Naskh Arabic', 'Naskh'),
  ('Gulzar', 'Gulzar'),
  ('Amiri', 'Amiri'),
];

class MotionEditorScreen extends StatefulWidget {
  const MotionEditorScreen({super.key, required this.template})
      : saved = null;

  const MotionEditorScreen.fromSaved({super.key, required this.saved})
      : template = null;

  final MotionTemplate? template;
  final MotionMyTemplate? saved;

  @override
  State<MotionEditorScreen> createState() => _MotionEditorScreenState();
}

class _MotionEditorScreenState extends State<MotionEditorScreen>
    with SingleTickerProviderStateMixin {
  late MotionScene _scene;
  late String _name;
  late String _category;
  String? _baseId;
  String? _savedId;
  Map<String, String> _imagePaths = {};
  final Map<String, ui.Image> _images = {};

  String _selId = '';
  Ticker? _ticker;
  Duration _last = Duration.zero;
  double _t = 0;
  bool _playing = true;
  bool _lagaoBusy = false;
  String _status = '';

  MotionLayer? get _layer {
    for (final l in _scene.layers) {
      if (l.id == _selId) return l;
    }
    return _scene.layers.isEmpty ? null : _scene.layers.first;
  }

  @override
  void initState() {
    super.initState();
    final saved = widget.saved;
    if (saved != null) {
      _scene = saved.scene;
      _name = saved.name;
      _category = saved.category;
      _baseId = saved.baseTemplateId;
      _savedId = saved.id;
      _imagePaths = Map<String, String>.from(saved.imagePaths);
    } else {
      final t = widget.template!;
      _scene = t.scene;
      _name = t.name;
      _category = t.category;
      _baseId = t.id;
    }
    _selId = _scene.layers.isEmpty ? '' : _scene.layers.first.id;
    _ticker = createTicker(_onTick)..start();
    for (final e in _imagePaths.entries) {
      _decodeImage(e.key, e.value);
    }
  }

  void _onTick(Duration elapsed) {
    final delta = elapsed - _last;
    _last = elapsed;
    if (!_playing || _scene.durationSec <= 0) return;
    setState(() {
      _t = (_t + delta.inMicroseconds / 1000000.0) % _scene.durationSec;
    });
  }

  @override
  void dispose() {
    _ticker?.dispose();
    for (final img in _images.values) {
      img.dispose();
    }
    super.dispose();
  }

  Future<void> _decodeImage(String key, String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _images[key]?.dispose();
        _images[key] = frame.image;
      });
    } catch (_) {
      // A missing file keeps the honest placeholder badge.
    }
  }

  void _updateLayer(MotionLayer Function(MotionLayer) f) {
    final sel = _layer;
    if (sel == null) return;
    setState(() {
      _scene = _scene.copyWith(
        layers: [
          for (final l in _scene.layers) l.id == sel.id ? f(l) : l,
        ],
      );
    });
  }

  // ── Save / Duplicate / Delete ─────────────────────────────

  MotionMyTemplate _record(String id, String name) => MotionMyTemplate(
        id: id,
        name: name,
        category: _category,
        baseTemplateId: _baseId,
        scene: _scene,
        imagePaths: Map<String, String>.from(_imagePaths),
        savedAtMs: DateTime.now().millisecondsSinceEpoch,
      );

  Future<void> _save() async {
    final id = _savedId ?? MotionMyTemplates.newId();
    await MotionMyTemplates.save(_record(id, _name));
    if (!mounted) return;
    setState(() {
      _savedId = id;
      _status = 'Saved — in the Gallery\'s "My Templates" '
          'category.';
    });
  }

  Future<void> _duplicate() async {
    final id = MotionMyTemplates.newId();
    final name = '$_name (copy)';
    await MotionMyTemplates.save(_record(id, name));
    if (!mounted) return;
    setState(() {
      _savedId = id;
      _name = name;
      _status = 'A copy was made and saved.';
    });
  }

  Future<void> _delete() async {
    final id = _savedId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kCard,
        title: const Text('Delete template?',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          '"$_name" will be deleted forever from My Templates.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            key: const Key('motionDeleteConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFFF5252))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await MotionMyTemplates.delete(id);
    if (!mounted) return;
    Navigator.pop(context);
  }

  // ── Video par Lagao ───────────────────────────────────────

  /// Renders the scene to frames, encodes WebM VP9 with alpha;
  /// on failure falls back to MP4 on the scene background and
  /// reports which format was made. The result opens in the
  /// Video Editor as the PIP overlay (its initState applies
  /// [VideoEditorScreen.initialPipVideoPath]).
  Future<void> _lagao() async {
    if (FeatureGate.isKilled(KillableFeature.motion)) {
      setState(() => _status = 'Motion is off right now (kill switch).');
      return;
    }
    setState(() {
      _lagaoBusy = true;
      _status = 'Creating frames…';
    });
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory(p.join(
        tmp.path,
        'motion_lagao_${DateTime.now().millisecondsSinceEpoch}',
      ));
      await dir.create(recursive: true);
      final frames = await renderMotionFrames(
        _scene,
        fps: 24,
        images: _images,
      );
      for (var i = 0; i < frames.length; i++) {
        await File(p.join(
                dir.path, 'f${i.toString().padLeft(4, '0')}.png'))
            .writeAsBytes(frames[i]);
      }
      final pattern = p.join(dir.path, 'f%04d.png');
      final webmPath = p.join(dir.path, 'motion.webm');
      final webm = await FfmpegService.run(
        '-y -framerate 24 -i ${FfmpegService.q(pattern)} '
        '-c:v libvpx-vp9 -pix_fmt yuva420p -b:v 2M '
        '${FfmpegService.q(webmPath)}',
      );
      String? outPath;
      var note = '';
      if (webm.ok && await File(webmPath).exists()) {
        outPath = webmPath;
        note = 'Transparent (WebM) overlay created — in the Video '
            'the PIP layer has been placed in the Editor.';
      } else {
        final mp4Path = p.join(dir.path, 'motion.mp4');
        final mp4 = await FfmpegService.run(
          '-y -framerate 24 -i ${FfmpegService.q(pattern)} '
          '-c:v libx264 -pix_fmt yuv420p '
          '${FfmpegService.q(mp4Path)}',
        );
        if (mp4.ok && await File(mp4Path).exists()) {
          outPath = mp4Path;
          note = 'Transparent encode failed — MP4 (with the scene\'s '
              'background) the PIP layer has been placed in the Editor.';
        }
      }
      if (!mounted) return;
      if (outPath == null) {
        setState(() => _status =
            'Video could not be created — try again.');
        return;
      }
      setState(() => _status = note);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              VideoEditorScreen(initialPipVideoPath: outPath),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _status =
            'Video could not be created — try again.');
      }
    } finally {
      if (mounted) setState(() => _lagaoBusy = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (FeatureGate.isKilled(KillableFeature.motion)) {
      return Scaffold(
        backgroundColor: _kBg,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text('Motion Editor', style: TextStyle(fontSize: 16)),
        ),
        body: const KilledFeatureNotice(),
      );
    }
    final layer = _layer;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Motion Editor',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            key: const Key('motionEditorDuplicate'),
            tooltip: 'Duplicate',
            onPressed: _duplicate,
            icon: const Icon(Icons.copy, size: 20),
          ),
          if (_savedId != null)
            IconButton(
              key: const Key('motionEditorDelete'),
              tooltip: 'Delete',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline, size: 20),
            ),
          TextButton(
            key: const Key('motionEditorSave'),
            onPressed: _save,
            child: const Text(
              'SAVE',
              style: TextStyle(
                color: _kCyan,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: CustomPaint(
                  key: const Key('motionEditorCanvas'),
                  painter: MotionScenePainter(
                    scene: _scene,
                    t: _t,
                    images: _images,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Row(
              children: [
                IconButton(
                  key: const Key('motionEditorPlayPause'),
                  onPressed: () =>
                      setState(() => _playing = !_playing),
                  icon: Icon(
                    _playing ? Icons.pause_circle : Icons.play_circle,
                    color: _kCyan,
                    size: 30,
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _t = 0),
                  icon: const Icon(Icons.replay,
                      color: Colors.white70, size: 22),
                ),
                Expanded(
                  child: Slider(
                    key: const Key('motionEditorScrubber'),
                    value: _t.clamp(0, _scene.durationSec),
                    min: 0,
                    max: _scene.durationSec,
                    onChanged: (v) => setState(() {
                      _t = v;
                      _playing = false;
                    }),
                  ),
                ),
                Text(
                  '${_t.toStringAsFixed(1)} / '
                  '${_scene.durationSec.toStringAsFixed(1)}s',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          _layerChips(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
              children: [
                _nameField(),
                const SizedBox(height: 10),
                _lagaoButton(),
                if (_status.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _status,
                    key: const Key('motionEditorStatus'),
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12.5),
                  ),
                ],
                if (layer != null) ..._layerControls(layer),
                ..._sceneControls(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _layerChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        itemCount: _scene.layers.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final l = _scene.layers[i];
          final selected = _layer?.id == l.id;
          return GestureDetector(
            key: Key('motionLayerChip-${l.id}'),
            onTap: () => setState(() => _selId = l.id),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                gradient: selected
                    ? const LinearGradient(colors: [_kBlue, _kPurple])
                    : null,
                color: selected ? null : _kCard,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected ? Colors.transparent : Colors.white12,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_layerIcon(l.type),
                      size: 14,
                      color: selected ? Colors.white : Colors.white54),
                  const SizedBox(width: 6),
                  Text(
                    _layerLabel(l),
                    style: TextStyle(
                      color: selected ? Colors.white : Colors.white70,
                      fontSize: 12,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _layerIcon(MotionLayerType type) => switch (type) {
        MotionLayerType.text => Icons.text_fields,
        MotionLayerType.shape => Icons.square_outlined,
        MotionLayerType.image => Icons.image_outlined,
        MotionLayerType.counter => Icons.numbers,
        MotionLayerType.ticker => Icons.short_text,
        MotionLayerType.chart => Icons.bar_chart,
      };

  String _layerLabel(MotionLayer l) {
    final text = l.text?.trim();
    if (text != null && text.isNotEmpty) {
      return text.length > 14 ? '${text.substring(0, 14)}…' : text;
    }
    return switch (l.type) {
      MotionLayerType.text => 'Text',
      MotionLayerType.shape => 'Shape ${l.shape ?? ''}'.trim(),
      MotionLayerType.image => 'Logo/Image',
      MotionLayerType.counter => 'Counter',
      MotionLayerType.ticker => 'Ticker',
      MotionLayerType.chart => 'Chart',
    };
  }

  Widget _nameField() {
    return TextFormField(
      key: const Key('motionNameField'),
      initialValue: _name,
      onChanged: (v) => _name = v,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: const InputDecoration(
        labelText: 'Template naam',
        labelStyle: TextStyle(color: Colors.white54, fontSize: 12),
        filled: true,
        fillColor: _kCard,
        border: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white12),
        ),
        contentPadding:
            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _lagaoButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        key: const Key('motionEditorLagao'),
        onPressed: _lagaoBusy ? null : _lagao,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: _lagaoBusy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.video_library_outlined, size: 19),
        label: const Text(
          'Place on Video',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
    );
  }

  // ── Controls ──────────────────────────────────────────────

  List<Widget> _layerControls(MotionLayer layer) {
    final dur = _scene.durationSec;
    return [
      _sectionTitle('Layer — ${_layerLabel(layer)}'),
      // Type-specific controls first: they are what the user
      // came to change.
      ..._typeControls(layer),
      _sectionTitle('Position / Size'),
      _slider(
        'Left-right (X)',
        layer.x / _scene.width,
        0,
        1,
        (v) => _updateLayer((l) => l.copyWith(x: v * _scene.width)),
        format: (v) => '${(v * 100).round()}%',
      ),
      _slider(
        'Up-down (Y)',
        layer.y / _scene.height,
        0,
        1,
        (v) => _updateLayer((l) => l.copyWith(y: v * _scene.height)),
        format: (v) => '${(v * 100).round()}%',
      ),
      _slider(
        'Scale',
        layer.scale,
        0.2,
        3,
        (v) => _updateLayer((l) => l.copyWith(scale: v)),
        format: (v) => '${(v * 100).round()}%',
      ),
      _slider(
        'Opacity',
        layer.opacity,
        0,
        1,
        (v) => _updateLayer((l) => l.copyWith(opacity: v)),
        format: (v) => '${(v * 100).round()}%',
      ),
      _slider(
        'Rotation',
        layer.rotation,
        -180,
        180,
        (v) => _updateLayer((l) => l.copyWith(rotation: v)),
        format: (v) => '${v.round()}°',
      ),
      _sectionTitle('Timing'),
      _slider(
        'Start',
        layer.start,
        0,
        dur,
        (v) => _updateLayer((l) => l.copyWith(start: v)),
        format: (v) => '${v.toStringAsFixed(1)}s',
      ),
      _slider(
        'End',
        layer.end ?? dur,
        0,
        dur,
        (v) => _updateLayer(
            (l) => l.copyWith(end: v >= dur ? null : v)),
        format: (v) => '${v.toStringAsFixed(1)}s',
      ),
      _sectionTitle('Animation Style'),
      _styleChips(
        layer.entrance,
        layer.type == MotionLayerType.text
            ? [..._kStyleIds, 'typewriter']
            : _kStyleIds,
        (id) => _updateLayer(
            (l) => l.copyWith(entrance: id == 'none' ? null : id)),
      ),
      _slider(
        'Style speed',
        layer.entranceSec,
        0.1,
        2.5,
        (v) => _updateLayer((l) => l.copyWith(entranceSec: v)),
        format: (v) => '${v.toStringAsFixed(1)}s',
      ),
      const Padding(
        padding: EdgeInsets.only(top: 6, bottom: 2),
        child: Text('Exit style',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
      ),
      _styleChips(
        layer.exit,
        _kStyleIds,
        (id) => _updateLayer(
            (l) => l.copyWith(exit: id == 'none' ? null : id)),
      ),
    ];
  }

  List<Widget> _typeControls(MotionLayer layer) {
    switch (layer.type) {
      case MotionLayerType.text:
        return [
          _textField(
            'motionTextField',
            'Text',
            layer.text ?? '',
            (v) => _updateLayer((l) => l.copyWith(text: v)),
          ),
          _slider(
            'Font size',
            layer.fontSize,
            20,
            160,
            (v) => _updateLayer((l) => l.copyWith(fontSize: v)),
            format: (v) => v.round().toString(),
          ),
          _slider(
            'Letter spacing',
            layer.letterSpacing,
            0,
            20,
            (v) => _updateLayer((l) => l.copyWith(letterSpacing: v)),
            format: (v) => v.toStringAsFixed(1),
          ),
          _swatches(
            'Text colour',
            layer.color,
            (c) => _updateLayer((l) => l.copyWith(color: c)),
          ),
          _fontChips(layer),
          SwitchListTile(
            key: const Key('motionBoldSwitch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Bold',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            value: layer.bold,
            onChanged: (v) =>
                _updateLayer((l) => l.copyWith(bold: v)),
          ),
        ];
      case MotionLayerType.shape:
        return [
          _swatches(
            'Fill colour',
            layer.fill,
            (c) => _updateLayer((l) => l.copyWith(fill: c)),
          ),
          _swatches(
            'Gradient end (second colour)',
            layer.fill2,
            (c) => _updateLayer((l) => l.copyWith(fill2: c)),
            allowNone: true,
          ),
          _slider(
            'Corner radius',
            layer.cornerRadius,
            0,
            80,
            (v) => _updateLayer((l) => l.copyWith(cornerRadius: v)),
            format: (v) => v.round().toString(),
          ),
          _swatches(
            'Glow colour',
            layer.glowColor,
            (c) => _updateLayer((l) => l.copyWith(glowColor: c)),
            allowNone: true,
          ),
          _slider(
            'Glow blur',
            layer.glowBlur,
            0,
            60,
            (v) => _updateLayer((l) => l.copyWith(glowBlur: v)),
            format: (v) => v.round().toString(),
          ),
        ];
      case MotionLayerType.image:
        return [
          const Text(
            'Attach your logo or photo to this layer — the file '
            'is saved with the template.',
            style: TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('motionPickImage'),
              onPressed: () => _pickImage(layer),
              icon: const Icon(Icons.image_outlined, size: 18),
              label: Text(
                _imagePaths[layer.imageKey] != null
                    ? 'Photo badlein'
                    : 'Choose logo / photo',
              ),
            ),
          ),
          if (_imagePaths[layer.imageKey] != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                p.basename(_imagePaths[layer.imageKey]!),
                style: const TextStyle(
                    color: Colors.white38, fontSize: 11.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ];
      case MotionLayerType.counter:
        return [
          _textField(
            'motionCounterFrom',
            'Start number',
            layer.from.round().toString(),
            (v) => _updateLayer(
                (l) => l.copyWith(from: double.tryParse(v) ?? l.from)),
            numeric: true,
          ),
          _textField(
            'motionCounterTo',
            'Last number',
            layer.to.round().toString(),
            (v) => _updateLayer(
                (l) => l.copyWith(to: double.tryParse(v) ?? l.to)),
            numeric: true,
          ),
          _textField(
            'motionCounterPrefix',
            'Before (prefix)',
            layer.prefix,
            (v) => _updateLayer((l) => l.copyWith(prefix: v)),
          ),
          _textField(
            'motionCounterSuffix',
            'After (suffix)',
            layer.suffix,
            (v) => _updateLayer((l) => l.copyWith(suffix: v)),
          ),
          _textField(
            'motionCounterLabel',
            'Bottom label',
            layer.label ?? '',
            (v) => _updateLayer((l) => l.copyWith(label: v)),
          ),
          _slider(
            'Font size',
            layer.fontSize,
            20,
            160,
            (v) => _updateLayer((l) => l.copyWith(fontSize: v)),
            format: (v) => v.round().toString(),
          ),
          _swatches(
            'Number colour',
            layer.color,
            (c) => _updateLayer((l) => l.copyWith(color: c)),
          ),
        ];
      case MotionLayerType.ticker:
        return [
          _textField(
            'motionTickerText',
            'Ticker text',
            layer.text ?? '',
            (v) => _updateLayer((l) => l.copyWith(text: v)),
          ),
          _slider(
            'Speed',
            layer.speedPxPerSecond,
            40,
            400,
            (v) =>
                _updateLayer((l) => l.copyWith(speedPxPerSecond: v)),
            format: (v) => '${v.round()} px/s',
          ),
          SwitchListTile(
            key: const Key('motionTickerDirSwitch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Urdu direction (right se scroll)',
                style: TextStyle(color: Colors.white, fontSize: 13)),
            value: layer.scrollRight,
            onChanged: (v) =>
                _updateLayer((l) => l.copyWith(scrollRight: v)),
          ),
          _swatches(
            'Band colour',
            layer.bandColor,
            (c) => _updateLayer((l) => l.copyWith(bandColor: c)),
          ),
          _swatches(
            'Text colour',
            layer.color,
            (c) => _updateLayer((l) => l.copyWith(color: c)),
          ),
          _fontChips(layer),
        ];
      case MotionLayerType.chart:
        return [
          _swatches(
            'Bar colour',
            layer.barColor,
            (c) => _updateLayer((l) => l.copyWith(barColor: c)),
          ),
          const Text(
            'Bar values stay the template\'s at this stage '
            'are (values editor in the next stage).',
            style: TextStyle(color: Colors.white38, fontSize: 11.5),
          ),
        ];
    }
  }

  Future<void> _pickImage(MotionLayer layer) async {
    final key = layer.imageKey;
    if (key == null) return;
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    // Copy into the app's documents so the saved template keeps
    // working after the gallery cache moves on.
    var path = picked.path;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dest = p.join(
        docs.path,
        'motion_img_${DateTime.now().millisecondsSinceEpoch}'
        '${p.extension(picked.path)}',
      );
      await File(picked.path).copy(dest);
      path = dest;
    } catch (_) {
      // The original path still works for this session.
    }
    if (!mounted) return;
    setState(() => _imagePaths[key] = path);
    await _decodeImage(key, path);
  }

  List<Widget> _sceneControls() {
    return [
      _sectionTitle('Scene'),
      _slider(
        'Duration',
        _scene.durationSec,
        2,
        12,
        (v) => setState(() => _scene = _scene.copyWith(durationSec: v)),
        format: (v) => '${v.toStringAsFixed(1)}s',
      ),
      _swatches(
        'Background colour',
        _scene.bgColor,
        (c) => setState(() => _scene = _scene.copyWith(bgColor: c)),
      ),
      _swatches(
        'Background gradient end',
        _scene.bgColor2,
        (c) => setState(() => _scene = _scene.copyWith(bgColor2: c)),
        allowNone: true,
      ),
    ];
  }

  // ── Small building blocks ─────────────────────────────────

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: _kCyan,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.4,
        ),
      ),
    );
  }

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    required String Function(double) format,
  }) {
    final v = value.clamp(min, max);
    return Row(
      children: [
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: Slider(
            value: v,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            format(v),
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _swatches(
    String label,
    int? current,
    ValueChanged<int?> onPick, {
    bool allowNone = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(color: Colors.white70, fontSize: 12.5)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (allowNone)
                GestureDetector(
                  onTap: () => onPick(null),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: current == null ? _kCyan : Colors.white24,
                        width: current == null ? 2.4 : 1,
                      ),
                    ),
                    child: const Icon(Icons.block,
                        size: 15, color: Colors.white54),
                  ),
                ),
              for (final c in _kPalette)
                GestureDetector(
                  onTap: () => onPick(c),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(c),
                      border: Border.all(
                        color: current == c ? _kCyan : Colors.white24,
                        width: current == c ? 2.6 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _styleChips(
    String? current,
    List<String> ids,
    ValueChanged<String> onPick,
  ) {
    final value = current ?? 'none';
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final id in ids)
          GestureDetector(
            onTap: () => onPick(id),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                gradient: value == id
                    ? const LinearGradient(colors: [_kBlue, _kPurple])
                    : null,
                color: value == id ? null : _kCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: value == id ? Colors.transparent : Colors.white12,
                ),
              ),
              child: Text(
                id,
                style: TextStyle(
                  color: value == id ? Colors.white : Colors.white70,
                  fontSize: 12,
                  fontWeight:
                      value == id ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _fontChips(MotionLayer layer) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Font',
              style: TextStyle(color: Colors.white70, fontSize: 12.5)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final f in _kFonts)
                GestureDetector(
                  onTap: () =>
                      _updateLayer((l) => l.copyWith(fontFamily: f.$1)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: layer.fontFamily == f.$1
                          ? const LinearGradient(
                              colors: [_kBlue, _kPurple])
                          : null,
                      color: layer.fontFamily == f.$1 ? null : _kCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: layer.fontFamily == f.$1
                            ? Colors.transparent
                            : Colors.white12,
                      ),
                    ),
                    child: Text(
                      f.$2,
                      style: TextStyle(
                        color: layer.fontFamily == f.$1
                            ? Colors.white
                            : Colors.white70,
                        fontSize: 12,
                        fontWeight: layer.fontFamily == f.$1
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _textField(
    String key,
    String label,
    String initial,
    ValueChanged<String> onChanged, {
    bool numeric = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: TextFormField(
        // Keyed by field + selected layer: switching layers
        // rebuilds the field with that layer's value (no shared
        // controller to leak or dispose early).
        key: Key('$key-${_layer?.id ?? ''}'),
        initialValue: initial,
        onChanged: onChanged,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        style: const TextStyle(color: Colors.white, fontSize: 13.5),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
          filled: true,
          fillColor: _kCard,
          border: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white12),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }
}
