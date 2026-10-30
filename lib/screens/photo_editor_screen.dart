/// Photo editor screen: pick, filters, crop, rotate, adjust, text,
/// AI tools (background remover, background blur, face beautify,
/// auto-enhance), export to gallery.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
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
  // Text fonts & CapCut-style effects (Jaani 31 Oct 2026).
  // Font keys: 'default', 'nastaliq', 'naskh', 'kufi', 'gulzar',
  // 'roboto', 'merriweather', 'dancing', 'bebas', 'pacifico'.
  String _textFont = 'default';
  bool _textShadow = true; // subtle drop shadow by default
  bool _textGlow = false;
  bool _textOutline = false;
  Color _textOutlineColor = Colors.black;
  double _textOutlineWidth = 2.0;
  bool _textBg = false; // ribbon/background behind text
  Color _textBgColor = Colors.black54;
  // CapCut-style text extras (Jaani 31 Oct 2026, full delegation).
  bool _textBold = false;
  bool _textItalic = false;
  double _textOpacity = 1.0; // 0..1
  double _textLetterSpacing = 0.0; // -2..10
  TextAlign _textAlign = TextAlign.center;
  Offset _textOffset = const Offset(0.5, 0.8);
  bool _busy = false;
  bool _hasTransparency = false;
  String _status = 'Pick a photo to start.';
  // CapCut-style UI state (Jaani 31 Oct 2026): null = tool grid visible,
  // no panel open. Non-null = that tool's panel open, grid hidden.
  String? _activePhotoTool;
  // InShot-style HSL state (Jaani 31 Oct 2026): 8 colors × [hue, sat, light].
  // Colors: Red, Orange, Yellow, Green, Cyan, Blue, Purple, Magenta.
  List<List<double>> _hslAdjustments =
      List.generate(8, (_) => [0.0, 1.0, 0.0]);
  int _hslSelectedColor = 0;


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

  /// Runs a FREE enhance job (not Premium — no ad gate). Shows busy state.
  /// Remini-style Priority 1 tools (Jaani 31 Oct 2026): Sharpen, Denoise,
  /// Enlarge, Color Fix. All algorithmic, on-device.
  Future<void> _runEnhance(
      String label, Future<void> Function() job) async {
    final file = _workingFile;
    if (file == null || _busy) return;
    setState(() {
      _busy = true;
      _status = '$label… (on-device)';
    });
    try {
      await job();
      _setStatus('$label done.');
    } catch (e) {
      _setStatus('$label failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _sharpen() async {
    await _runEnhance('Sharpening', () async {
      final image = await _decodeWorking();
      final out = await sharpenImage(image, amount: 0.8);
      await _replaceWorking(out);
    });
  }

  Future<void> _denoise() async {
    await _runEnhance('Denoising', () async {
      final image = await _decodeWorking();
      final out = await denoiseImage(image, strength: 0.6);
      await _replaceWorking(out);
    });
  }

  Future<void> _enlarge() async {
    await _runEnhance('Enlarging to 2x', () async {
      final image = await _decodeWorking();
      final out = await enlargeImage(image, scale: 2.0);
      await _replaceWorking(out);
    });
  }

  Future<void> _colorFix() async {
    await _runEnhance('Fixing colors', () async {
      final image = await _decodeWorking();
      final out = await colorFixImage(image);
      await _replaceWorking(out);
    });
  }

  /// InShot-style HSL apply (Jaani 31 Oct 2026). Applies the current
  /// per-color adjustments. FREE, on-device.
  Future<void> _applyHSL() async {
    await _runEnhance('Applying HSL', () async {
      final image = await _decodeWorking();
      final out = await adjustHSL(image, _hslAdjustments);
      await _replaceWorking(out);
    });
  }

  /// Reset all HSL adjustments to neutral.
  void _resetHSL() {
    setState(() {
      _hslAdjustments = List.generate(8, (_) => [0.0, 1.0, 0.0]);
      _hslSelectedColor = 0;
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
        textShadow: _textShadow,
        textGlow: _textGlow,
        textBg: _textBg,
        textBgArgb: _textBgColor.toARGB32(),
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

  /// Display name for a photo tool key (used in the panel header).
  String _photoToolDisplayName(String key) {
    const Map<String, String> names = <String, String>{
      'pick': 'Pick Photo',
      'crop': 'Crop',
      'rotate': 'Rotate',
      'filters': 'Filters',
      'adjust': 'Adjust',
      'text': 'Text',
      'ai': 'AI Tools',
      'bgremover': 'BG Remover',
      'enhance': 'Enhance',
      'hsl': 'HSL',
      'save': 'Save',
    };
    return names[key] ?? key;
  }

  /// Header for the open photo tool panel: Back + tool name + Done.
  /// CapCut-style: Back/Done closes the panel and returns to the tool grid.
  Widget _photoPanelHeader(String toolKey) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back to tools',
            onPressed: () => setState(() => _activePhotoTool = null),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          Expanded(
            child: Text(
              _photoToolDisplayName(toolKey),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _activePhotoTool = null),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  /// Single H/S/L slider row for the HSL panel.
  Widget _hslSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
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
            child: Text(
              value.toStringAsFixed(1),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  /// Returns a TextStyle for the selected font key, with the given
  /// color/size. Uses google_fonts; falls back to default on error.
  /// Urdu fonts: nastaliq (traditional), naskh (clean), kufi (geometric),
  /// gulzar (decorative). English: roboto, merriweather (serif),
  /// dancing (script), bebas (display), pacifico (script).
  TextStyle _fontStyle(String fontKey,
      {required Color color, required double fontSize}) {
    final base = TextStyle(
      color: color.withOpacity(_textOpacity),
      fontSize: fontSize,
      fontWeight: _textBold ? FontWeight.bold : FontWeight.normal,
      fontStyle: _textItalic ? FontStyle.italic : FontStyle.normal,
      letterSpacing: _textLetterSpacing,
      shadows: _textShadows(),
    );
    try {
      switch (fontKey) {
        case 'nastaliq':
          return GoogleFonts.notoNastaliqUrdu(textStyle: base);
        case 'naskh':
          return GoogleFonts.notoNaskhArabic(textStyle: base);
        case 'kufi':
          return GoogleFonts.notoKufiArabic(textStyle: base);
        case 'gulzar':
          return GoogleFonts.gulzar(textStyle: base);
        case 'roboto':
          return GoogleFonts.roboto(textStyle: base);
        case 'merriweather':
          return GoogleFonts.merriweather(textStyle: base);
        case 'dancing':
          return GoogleFonts.dancingScript(textStyle: base);
        case 'bebas':
          return GoogleFonts.bebasNeue(textStyle: base);
        case 'pacifico':
          return GoogleFonts.pacifico(textStyle: base);
        default:
          return base;
      }
    } catch (_) {
      return base; // offline or font not cached yet
    }
  }

  /// Font selection chip with a live preview of the font style.
  Widget _fontChip(String key, String label) {
    final bool selected = _textFont == key;
    return ChoiceChip(
      label: Text(
        label,
        style: _fontStyle(key, color: Colors.white, fontSize: 13),
      ),
      selected: selected,
      onSelected: (_) => setState(() => _textFont = key),
    );
  }

  /// Builds the preview text widget with all current style settings:
  /// font, shadow/glow, outline (stroked layer behind), ribbon background,
  /// alignment. Used in the photo preview.
  Widget _buildPreviewText() {
    final TextStyle style = _fontStyle(
      _textFont,
      color: _textColor,
      fontSize: _textSize * 0.6,
    );
    Widget textWidget;
    if (_textOutline) {
      // Outline: stroked text behind the filled text.
      textWidget = Stack(
        alignment: Alignment.center,
        children: [
          Text(
            _text,
            textAlign: _textAlign,
            style: style.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = _textOutlineWidth
                ..color = _textOutlineColor,
              shadows: [],
            ),
          ),
          Text(_text, textAlign: _textAlign, style: style),
        ],
      );
    } else {
      textWidget = Text(_text, textAlign: _textAlign, style: style);
    }
    if (_textBg) {
      // Ribbon: rounded background behind the text.
      textWidget = Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _textBgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: textWidget,
      );
    }
    return Container(
      width: 220,
      alignment: Alignment.center,
      child: textWidget,
    );
  }

  /// Builds the list of shadows for the current text effect settings.
  List<Shadow> _textShadows() {
    final List<Shadow> shadows = [];
    if (_textGlow) {
      shadows.add(Shadow(
        color: _textColor.withOpacity(0.9),
        blurRadius: 16,
      ));
      shadows.add(Shadow(
        color: _textColor.withOpacity(0.6),
        blurRadius: 32,
      ));
    }
    if (_textShadow) {
      shadows.add(const Shadow(
        color: Colors.black87,
        offset: Offset(2, 3),
        blurRadius: 6,
      ));
    }
    return shadows;
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
        // Full CapCut-style text editor (Jaani 31 Oct 2026, full delegation):
        // fonts (Urdu + English), shadow/glow/outline/ribbon, spacing,
        // bold/italic, opacity, alignment.
        return [
          const Text('Text overlay (drag it on the photo)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Text',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _text = v),
          ),
          const SizedBox(height: 12),
          // ---- Font picker ----
          const Text('Font', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Urdu',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _fontChip('default', 'Default'),
              _fontChip('nastaliq', 'Nastaliq'),
              _fontChip('naskh', 'Naskh'),
              _fontChip('kufi', 'Kufi'),
              _fontChip('gulzar', 'Gulzar'),
            ],
          ),
          const SizedBox(height: 8),
          const Text('English',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _fontChip('roboto', 'Roboto'),
              _fontChip('merriweather', 'Serif'),
              _fontChip('dancing', 'Script'),
              _fontChip('bebas', 'Display'),
              _fontChip('pacifico', 'Pacifico'),
            ],
          ),
          const SizedBox(height: 12),
          // ---- Color ----
          Row(
            children: [
              const Text('Color:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 2,
                  children: _textColors.map((c) {
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
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _SliderRow(
            label: 'Text size',
            value: _textSize,
            min: 20,
            max: 110,
            onChanged: (v) => setState(() => _textSize = v),
          ),
          // ---- Bold / Italic / Alignment ----
          Row(
            children: [
              FilterChip(
                label: const Text('B',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                selected: _textBold,
                onSelected: (v) => setState(() => _textBold = v),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('I',
                    style: TextStyle(fontStyle: FontStyle.italic)),
                selected: _textItalic,
                onSelected: (v) => setState(() => _textItalic = v),
              ),
              const SizedBox(width: 8),
              const Text('Align:'),
              IconButton(
                tooltip: 'Left',
                onPressed: () =>
                    setState(() => _textAlign = TextAlign.left),
                icon: Icon(Icons.format_align_left,
                    color: _textAlign == TextAlign.left
                        ? Colors.tealAccent
                        : Colors.grey),
              ),
              IconButton(
                tooltip: 'Center',
                onPressed: () =>
                    setState(() => _textAlign = TextAlign.center),
                icon: Icon(Icons.format_align_center,
                    color: _textAlign == TextAlign.center
                        ? Colors.tealAccent
                        : Colors.grey),
              ),
              IconButton(
                tooltip: 'Right',
                onPressed: () =>
                    setState(() => _textAlign = TextAlign.right),
                icon: Icon(Icons.format_align_right,
                    color: _textAlign == TextAlign.right
                        ? Colors.tealAccent
                        : Colors.grey),
              ),
            ],
          ),
          _SliderRow(
            label: 'Opacity',
            value: _textOpacity,
            min: 0.1,
            max: 1.0,
            onChanged: (v) => setState(() => _textOpacity = v),
          ),
          _SliderRow(
            label: 'Letter spacing',
            value: _textLetterSpacing,
            min: -2,
            max: 10,
            onChanged: (v) => setState(() => _textLetterSpacing = v),
          ),
          const Divider(height: 24),
          // ---- Effects: Shadow / Glow / Outline / Ribbon ----
          const Text('Effects',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilterChip(
                label: const Text('Shadow'),
                selected: _textShadow,
                onSelected: (v) => setState(() => _textShadow = v),
              ),
              FilterChip(
                label: const Text('Glow'),
                selected: _textGlow,
                onSelected: (v) => setState(() => _textGlow = v),
              ),
              FilterChip(
                label: const Text('Outline'),
                selected: _textOutline,
                onSelected: (v) => setState(() => _textOutline = v),
              ),
              FilterChip(
                label: const Text('Ribbon'),
                selected: _textBg,
                onSelected: (v) => setState(() => _textBg = v),
              ),
            ],
          ),
          if (_textOutline) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Outline color:'),
                const SizedBox(width: 8),
                ...[Colors.black, Colors.white, Colors.red, Colors.blue]
                    .map((c) => GestureDetector(
                          onTap: () =>
                              setState(() => _textOutlineColor = c),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _textOutlineColor == c
                                    ? Colors.tealAccent
                                    : Colors.grey,
                                width: _textOutlineColor == c ? 3 : 1,
                              ),
                            ),
                          ),
                        )),
              ],
            ),
            _SliderRow(
              label: 'Outline width',
              value: _textOutlineWidth,
              min: 1,
              max: 8,
              onChanged: (v) => setState(() => _textOutlineWidth = v),
            ),
          ],
          if (_textBg) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Ribbon color:'),
                const SizedBox(width: 8),
                ...[
                  Colors.black54,
                  Colors.red,
                  Colors.blue,
                  Colors.green,
                  Colors.orange
                ]
                    .map((c) => GestureDetector(
                          onTap: () => setState(() => _textBgColor = c),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _textBgColor == c
                                    ? Colors.tealAccent
                                    : Colors.grey,
                                width: _textBgColor == c ? 3 : 1,
                              ),
                            ),
                          ),
                        )),
              ],
            ),
          ],
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
      case 'enhance':
        // Remini-style Enhance section (Jaani 31 Oct 2026, Priority 1).
        // All FREE, on-device, one-tap: Sharpen, Denoise, Enlarge, Color Fix.
        return [
          const Text('Enhance',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
            'One-tap photo improvements — 100% on-device, no upload. FREE.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: file == null || _busy ? null : _sharpen,
                icon: const Icon(Icons.blur_off),
                label: const Text('Sharpen'),
              ),
              ElevatedButton.icon(
                onPressed: file == null || _busy ? null : _denoise,
                icon: const Icon(Icons.grain),
                label: const Text('Denoise'),
              ),
              ElevatedButton.icon(
                onPressed: file == null || _busy ? null : _enlarge,
                icon: const Icon(Icons.zoom_out_map),
                label: const Text('Enlarge 2x'),
              ),
              ElevatedButton.icon(
                onPressed: file == null || _busy ? null : _colorFix,
                icon: const Icon(Icons.color_lens),
                label: const Text('Color Fix'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Tip: Denoise pehle, phir Sharpen — behtareen result ke liye.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ];
      case 'hsl':
        // InShot-style HSL panel (Jaani 31 Oct 2026): per-color
        // Hue/Saturation/Lightness. 8 colors, 3 sliders each.
        return [
          Row(
            children: [
              const Text('HSL',
                  style:
                      TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Spacer(),
              TextButton(
                onPressed: _resetHSL,
                child: const Text('Reset'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Rang select karein, phir Hue / Saturation / Lightness adjust karein.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          // Color selector chips.
          Builder(
            builder: (BuildContext context) {
              const List<String> colorNames = <String>[
                'Red', 'Orange', 'Yellow', 'Green',
                'Cyan', 'Blue', 'Purple', 'Magenta',
              ];
              const List<Color> colorDots = <Color>[
                Colors.red, Colors.orange, Colors.yellow, Colors.green,
                Colors.cyan, Colors.blue, Colors.purple, Colors.pink,
              ];
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List<Widget>.generate(8, (int i) {
                  final bool selected = _hslSelectedColor == i;
                  return ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: colorDots[i],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(colorNames[i],
                            style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    selected: selected,
                    onSelected: (_) =>
                        setState(() => _hslSelectedColor = i),
                  );
                }),
              );
            },
          ),
          const SizedBox(height: 16),
          // H/S/L sliders for the selected color.
          Builder(
            builder: (BuildContext context) {
              final List<double> adj =
                  _hslAdjustments[_hslSelectedColor];
              return Column(
                children: [
                  _hslSlider(
                    label: 'Hue',
                    value: adj[0],
                    min: -180,
                    max: 180,
                    onChanged: (double v) => setState(
                        () => _hslAdjustments[_hslSelectedColor][0] = v),
                  ),
                  _hslSlider(
                    label: 'Saturation',
                    value: adj[1],
                    min: 0,
                    max: 2,
                    onChanged: (double v) => setState(
                        () => _hslAdjustments[_hslSelectedColor][1] = v),
                  ),
                  _hslSlider(
                    label: 'Lightness',
                    value: adj[2],
                    min: -100,
                    max: 100,
                    onChanged: (double v) => setState(
                        () => _hslAdjustments[_hslSelectedColor][2] = v),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: file == null || _busy ? null : _applyHSL,
              icon: const Icon(Icons.check),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Apply HSL', style: TextStyle(fontSize: 16)),
              ),
            ),
          ),
        ];
      case 'bgremover':
        // Dedicated BG Remover panel (Jaani 31 Oct 2026): prominent,
        // one-tap background removal. Uses the same on-device
        // _removeBackground() as the AI Tools section.
        return [
          const Text('Background Remover',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
            'Ek tap mein photo ka background hataein. '
            '100% on-device — koi upload nahi.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: file == null || _busy ? null : _removeBackground,
              icon: const Icon(Icons.person_off, size: 28),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Remove Background', style: TextStyle(fontSize: 16)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_hasTransparency)
            const Text(
              'Background hata diya gaya hai — ab Save karein.',
              style: TextStyle(color: Colors.tealAccent),
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
                                child: _buildPreviewText(),
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
                // InShot-style smooth transitions between tools (Jaani 31 Oct
                // 2026: "aur smooth"). AnimatedSwitcher fades/slides panels.
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.08),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: _activePhotoTool == null
                      // No tool selected: hint to pick one from the rail.
                      ? const Center(
                          key: ValueKey<String>('photo-hint'),
                          child: Text(
                            'Neeche se koi tool select karein',
                            style:
                                TextStyle(color: Colors.grey, fontSize: 14),
                          ),
                        )
                      // Tool open: CapCut-style header (Back/Done)
                      // + that tool's options only.
                      : ListView(
                          key: ValueKey<String>(
                              'photo-tool-${_activePhotoTool!}'),
                          padding: const EdgeInsets.only(top: 4),
                          children: [
                            _photoPanelHeader(_activePhotoTool!),
                            ..._photoPanelChildren(),
                          ],
                        ),
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
            // CapCut-style (Jaani 31 Oct 2026): hidden while a tool's
            // panel is open — only that tool's options show, with
            // Back/Done in the panel header to return here.
            // Height 88: fits icon (24) + gap (4) + 2-line label (~28)
            // + button padding (16) + container padding (12) with margin.
            if (_activePhotoTool == null)
              Container(
                height: 88,
                color: const Color(0xFF1B1B1B),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    _photoRailButton('pick', 'Pick', Icons.photo_library),
                    _photoRailButton('crop', 'Crop', Icons.crop),
                    _photoRailButton('rotate', 'Rotate', Icons.rotate_right),
                    _photoRailButton(
                        'filters', 'Filters', Icons.filter_vintage),
                    _photoRailButton('adjust', 'Adjust', Icons.tune),
                    _photoRailButton('text', 'Text', Icons.text_fields),
                    _photoRailButton(
                        'bgremover', 'BG Remover', Icons.person_off),
                    _photoRailButton(
                        'enhance', 'Enhance', Icons.auto_fix_high),
                    _photoRailButton('hsl', 'HSL', Icons.palette),
                    _photoRailButton('ai', 'AI Tools', Icons.psychology),
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
