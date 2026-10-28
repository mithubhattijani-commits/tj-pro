/// Photo editor screen: pick, filters, crop, rotate, adjust, text,
/// AI tools (background remover, background blur, face beautify,
/// auto-enhance), export to gallery.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_config.dart';
import '../services/ad_service.dart';
import '../services/ai_service.dart';
import '../services/photo_pipeline.dart';

const _filterLabels = {
  PhotoFilter.normal: 'Normal',
  PhotoFilter.warm: 'Warm',
  PhotoFilter.cool: 'Cool',
  PhotoFilter.blackWhite: 'B&W',
  PhotoFilter.vivid: 'Vivid',
  PhotoFilter.sepia: 'Sepia',
};
const _textColors = [
  Colors.white,
  Colors.black,
  Colors.yellow,
  Colors.red,
  Colors.green,
  Colors.cyan,
  Colors.pink,
];

class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({super.key});

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  final _picker = ImagePicker();
  File? _workingFile;
  PhotoFilter _filter = PhotoFilter.normal;
  double _brightness = 0; // -100..100
  double _contrast = 1.0; // 0..2
  double _saturation = 1.0; // 0..2
  String _text = '';
  Color _textColor = Colors.white;
  double _textSize = 42;
  Offset _textOffset = const Offset(0.5, 0.8);
  bool _busy = false;
  bool _hasTransparency = false;
  String _status = 'Pick a photo to start.';
  // CapCut-style UI state: which single-row tool rail item is open.
  String _activePhotoTool = 'filters';


  void _setStatus(String s) => setState(() => _status = s);

  List<double> get _matrix => buildColorMatrix(
        filter: _filter,
        brightness: _brightness,
        contrast: _contrast,
        saturation: _saturation,
      );

  Future<void> _pick() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() {
      _workingFile = File(picked.path);
      _filter = PhotoFilter.normal;
      _brightness = 0;
      _contrast = 1.0;
      _saturation = 1.0;
      _text = '';
      _hasTransparency = false;
      _status = 'Photo loaded.';
    });
  }

  /// Working files are always PNG (preserves transparency after a
  /// background removal; crop/rotate re-encode through here too).
  Future<void> _replaceWorking(img.Image image) async {
    final dir = await getTemporaryDirectory();
    final f = File(
      p.join(
        dir.path,
        'pve_photo_${DateTime.now().millisecondsSinceEpoch}.png',
      ),
    );
    await f.writeAsBytes(img.encodePng(image));
    setState(() => _workingFile = f);
  }

  Future<img.Image> _decodeWorking() async {
    final file = _workingFile;
    if (file == null) throw Exception('No photo loaded.');
    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Could not read this photo.');
    return image;
  }

  Future<void> _crop() async {
    final file = _workingFile;
    if (file == null) return;
    final cropped = await ImageCropper().cropImage(
      sourcePath: file.path,
      // PNG keeps transparency after a background removal; JPG otherwise.
      compressFormat: _hasTransparency
          ? ImageCompressFormat.png
          : ImageCompressFormat.jpg,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop photo',
          lockAspectRatio: false,
        ),
      ],
    );
    if (cropped != null) {
      setState(() => _workingFile = File(cropped.path));
    }
  }

  Future<void> _rotate(int quarterTurns) async {
    final file = _workingFile;
    if (file == null || _busy) return;
    setState(() => _busy = true);
    try {
      final image = await _decodeWorking();
      // copyRotate(+90) is clockwise, so 1 = right, 3 = left.
      final rotated =
          img.copyRotate(image, angle: quarterTurns * 90);
      await _replaceWorking(rotated);
      _setStatus('Rotated.');
    } catch (e) {
      _setStatus('Rotate failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  /// Runs an AI job; returns true on success. Errors are shown in status.
  /// AI tools are Premium: they need a rewarded ad unlock first.
  Future<bool> _runAi(String label, Future<void> Function() job) async {
    final file = _workingFile;
    if (file == null || _busy) return false;
    if (!AdService.isPremiumUnlocked) {
      _setStatus(
        'AI tools are Premium. Unlock them with one short ad '
        'from the home screen, then try again.',
      );
      if (mounted) {
        final unlock = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Premium AI tools'),
            content: const Text(
              'Watch one short ad to unlock background remover, '
              'blur, beautify and auto-enhance.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Later'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Watch ad'),
              ),
            ],
          ),
        );
        if (unlock == true) {
          final ok = await AdService.showRewarded();
          _setStatus(
            ok
                ? 'Premium AI unlocked. Tap the AI tool again.'
                : 'No ad was available right now. Try again.',
          );
        }
      }
      return false;
    }
    setState(() {
      _busy = true;
      _status = '$label… (on-device, may take a few seconds)';
    });
    try {
      await job();
      _setStatus('$label done.');
      return true;
    } catch (e) {
      _setStatus('$label failed: $e');
      return false;
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _removeBackground() async {
    final file = _workingFile;
    if (file == null) return;
    final ok = await _runAi('Removing background', () async {
      final mask = await AiService.segmentSubject(file);
      final image = await _decodeWorking();
      final out = await applySegmentationMask(
        image,
        mask,
        removeBackground: true,
      );
      await _replaceWorking(out);
    });
    if (ok) setState(() => _hasTransparency = true);
  }

  Future<void> _blurBackground() async {
    final file = _workingFile;
    if (file == null) return;
    await _runAi('Blurring background', () async {
      final mask = await AiService.segmentSubject(file);
      final image = await _decodeWorking();
      final out = await applySegmentationMask(
        image,
        mask,
        removeBackground: false,
      );
      await _replaceWorking(out);
    });
  }

  Future<void> _beautify() async {
    final file = _workingFile;
    if (file == null) return;
    await _runAi('Beautifying', () async {
      final faces = await AiService.detectFaces(file);
      if (faces.isEmpty) {
        throw Exception('No face found in this photo.');
      }
      final image = await _decodeWorking();
      final out = await beautifyFaces(image, faces);
      await _replaceWorking(out);
    });
  }

  Future<void> _autoEnhance() async {
    await _runAi('Auto-enhancing', () async {
      final image = await _decodeWorking();
      final out = await autoEnhance(image);
      await _replaceWorking(out);
    });
  }

  Future<void> _export() async {
    final file = _workingFile;
    if (file == null || _busy) return;
    setState(() {
      _busy = true;
      _status = 'Exporting…';
    });
    try {
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) {
          throw Exception('Gallery access was denied.');
        }
      }
      final dir = await getTemporaryDirectory();
      final ext = _hasTransparency ? 'png' : 'jpg';
      final outPath = p.join(
        dir.path,
        'pve_export_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      final params = PhotoEditParams(
        filter: _filter,
        brightness: _brightness,
        contrast: _contrast,
        saturation: _saturation,
        text: _text,
        textArgb: _textColor.toARGB32(),
        textSize: _textSize,
        textOffsetX: _textOffset.dx,
        textOffsetY: _textOffset.dy,
      );
      final outFile = await exportPhoto(
        workingFile: file,
        params: params,
        outPath: outPath,
        keepAlpha: _hasTransparency,
      );
      await Gal.putImage(outFile.path);
      _setStatus('Saved to gallery: ${p.basename(outFile.path)}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo saved to gallery.')),
        );
      }
    } catch (e) {
      _setStatus('Export failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Widget _photoRailButton(String key, String label, IconData icon) {
    final selected = _activePhotoTool == key;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _activePhotoTool = key),
        child: Container(
          width: 76,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? Colors.teal.shade700 : const Color(0xFF232323),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: Colors.white),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _photoPanelChildren() {
    final file = _workingFile;
    switch (_activePhotoTool) {
      case 'crop':
        return [
          const Text('Crop',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: file == null || _busy ? null : _crop,
              icon: const Icon(Icons.crop),
              label: const Text('Crop'),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Crop opens the system cropper on the photo.',
              style: TextStyle(color: Colors.grey)),
        ];
      case 'rotate':
        return [
          const Text('Rotate',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: file == null || _busy ? null : () => _rotate(3),
                  icon: const Icon(Icons.rotate_left),
                  label: const Text('Rotate left'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: file == null || _busy ? null : () => _rotate(1),
                  icon: const Icon(Icons.rotate_right),
                  label: const Text('Rotate right'),
                ),
              ),
            ],
          ),
        ];
      case 'filters':
        return [
const Text('Filters', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filterLabels.entries.map((e) {
                final selected = e.key == _filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: selected,
                    onSelected: (_) => setState(() => _filter = e.key),
                  ),
                );
              }).toList(),
            ),
          ),
        ];
      case 'adjust':
        return [
          const Text('Adjust',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
_SliderRow(
            label: 'Brightness',
            value: _brightness,
            min: -100,
            max: 100,
            onChanged: (v) => setState(() => _brightness = v),
          ),
          _SliderRow(
            label: 'Contrast',
            value: _contrast,
            min: 0,
            max: 2,
            onChanged: (v) => setState(() => _contrast = v),
          ),
          _SliderRow(
            label: 'Saturation',
            value: _saturation,
            min: 0,
            max: 2,
            onChanged: (v) => setState(() => _saturation = v),
          ),
          const Divider(height: 32),
        ];
      case 'text':
        return [
const Text('Text overlay (drag it on the photo)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Text',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _text = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Color:'),
              const SizedBox(width: 8),
              ..._textColors.map((c) {
                return GestureDetector(
                  onTap: () => setState(() => _textColor = c),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _textColor == c
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                        width: _textColor == c ? 3 : 1,
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
          _SliderRow(
            label: 'Text size',
            value: _textSize,
            min: 20,
            max: 110,
            onChanged: (v) => setState(() => _textSize = v),
          ),
        ];
      case 'ai':
        return [
if (AppConfig.aiToolsEnabled) ...[
            const Divider(height: 32),
            const Text('AI tools (on-device, offline)',
                style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: file == null || _busy ? null : _removeBackground,
                icon: const Icon(Icons.person_off),
                label: const Text('Remove background'),
              ),
              ElevatedButton.icon(
                onPressed: file == null || _busy ? null : _blurBackground,
                icon: const Icon(Icons.blur_on),
                label: const Text('Blur background'),
              ),
              ElevatedButton.icon(
                onPressed: file == null || _busy ? null : _beautify,
                icon: const Icon(Icons.face_retouching_natural),
                label: const Text('Beautify'),
              ),
              ElevatedButton.icon(
                onPressed: file == null || _busy ? null : _autoEnhance,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Auto-enhance'),
              ),
            ],
          ),
          ],
          const SizedBox(height: 16),
        ];
      case 'save':
        return [
SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: file == null || _busy ? null : _export,
              icon: const Icon(Icons.save),
              label: Text(_busy ? 'Working…' : 'Save to gallery'),
            ),
          ),
          const SizedBox(height: 12),
          Text(_status),
          const SizedBox(height: 8),
          const Text(
            'Note: filters and sliders preview live; crop, rotate and AI '
            'tools change the photo itself. Auto-enhance is an automatic '
            'levels/color adjustment (algorithmic, not ML).',
            style: TextStyle(color: Colors.grey),
          ),
        ];
      case 'pick':
      default:
        return [
          const Text('Pick a photo',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Pick photo'),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: file == null || _busy ? null : _crop,
                icon: const Icon(Icons.crop),
                label: const Text('Crop'),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Rotate left',
                onPressed: file == null || _busy ? null : () => _rotate(3),
                icon: const Icon(Icons.rotate_left),
              ),
              IconButton(
                tooltip: 'Rotate right',
                onPressed: file == null || _busy ? null : () => _rotate(1),
                icon: const Icon(Icons.rotate_right),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_status, style: const TextStyle(color: Colors.grey)),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _workingFile;
    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('TJ Pro — Photo Editor'),
          actions: [
            IconButton(
              tooltip: 'Save to gallery',
              onPressed: file == null || _busy ? null : _export,
              icon: const Icon(Icons.save),
            ),
          ],
        ),
        // LAYOUT (Jaani spec 28 Oct 12:02 PKT, top to bottom):
        // 1. preview on top (large)  2. filter strip beneath it
        // 3. tool panel  4. ONE single-row tool rail at the bottom.
        body: Column(
          children: [
            Expanded(
              flex: 5,
              child: Container(
                color: Colors.black,
                padding: const EdgeInsets.all(8),
                child: Center(
                  child: file == null
                      ? const Text('No photo selected',
                          style: TextStyle(color: Colors.white70))
                      : Container(
            color: Colors.black12,
            constraints: const BoxConstraints(maxHeight: 420),
            child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          ColorFiltered(
                            colorFilter: ColorFilter.matrix(_matrix),
                            child: Image.file(file, fit: BoxFit.contain),
                          ),
                          if (_text.isNotEmpty)
                            Positioned(
                              left: _textOffset.dx * w - 100,
                              top: _textOffset.dy * 360 - 20,
                              child: GestureDetector(
                                onPanUpdate: (d) {
                                  setState(() {
                                    _textOffset = Offset(
                                      (_textOffset.dx + d.delta.dx / w)
                                          .clamp(0.1, 0.9),
                                      (_textOffset.dy + d.delta.dy / 360)
                                          .clamp(0.1, 0.95),
                                    );
                                  });
                                },
                                child: Container(
                                  width: 200,
                                  alignment: Alignment.center,
                                  child: Text(
                                    _text,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: _textColor,
                                      fontSize: _textSize * 0.6,
                                      fontWeight: FontWeight.bold,
                                      shadows: const [
                                        Shadow(
                                          color: Colors.black,
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
                ),
              ),
            ),
            Container(
              color: const Color(0xFF1B1B1B),
              padding:
                  const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
const Text('Filters', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filterLabels.entries.map((e) {
                final selected = e.key == _filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: selected,
                    onSelected: (_) => setState(() => _filter = e.key),
                  ),
                );
              }).toList(),
            ),
          ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Container(
                color: const Color(0xFF121212),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: ListView(
                  padding: const EdgeInsets.only(top: 4),
                  children: _photoPanelChildren(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(_status,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            // ONE single horizontal tool row (scrollable) — never a grid,
            // never two rows.
            Container(
              height: 76,
              color: const Color(0xFF1B1B1B),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  _photoRailButton('pick', 'Pick', Icons.photo_library),
                  _photoRailButton('crop', 'Crop', Icons.crop),
                  _photoRailButton('rotate', 'Rotate', Icons.rotate_right),
                  _photoRailButton('filters', 'Filters', Icons.filter_vintage),
                  _photoRailButton('adjust', 'Adjust', Icons.tune),
                  _photoRailButton('text', 'Text', Icons.text_fields),
                  _photoRailButton('ai', 'AI Tools', Icons.auto_fix_high),
                  _photoRailButton('save', 'Save', Icons.save),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 96, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(value.toStringAsFixed(1), textAlign: TextAlign.right),
        ),
      ],
    );
  }
}
