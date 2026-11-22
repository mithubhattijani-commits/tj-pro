/// Photo editor screen: pick, filters, crop, rotate, adjust, text,
/// AI tools (background remover, background blur, face beautify,
/// auto-enhance), export to gallery.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_config.dart';
import '../services/ai_service.dart';
import '../services/photo_pipeline.dart';
import '../services/coin_service.dart';
import '../theme.dart';

/// Round-2 theme unification (P13): the photo editor now wears the
/// app's violet identity instead of its old private gold theme.
const _accent = Color(0xFF7C3AED);
const _accentLight = Color(0xFFA78BFA);

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
  // Round-2 history (P6): the originally picked photo + a stack of
  // working-file states (max 10 undo steps) around _replaceWorking.
  File? _originalFile;
  final List<File> _history = [];
  int _historyIndex = -1;
  bool _comparing = false; // hold-to-compare: show the original
  PhotoFilter _filter = PhotoFilter.normal;
  // Round-2 Filters: strength of the chosen filter look + the LUT row.
  double _filterIntensity = 1.0; // 0..1
  String _selectedLut = ''; // '' = no LUT, else a photoLuts name
  final Map<String, CubeLut> _luts = {};
  bool _lutsLoading = false;
  Map<PhotoFilter, Uint8List> _filterThumbs = {};
  Map<String, Uint8List> _lutThumbs = {};
  String? _thumbKey; // working-file path the thumbs were built for
  // Round-2 Adjust panel: 12 sliders (Light / Colour / Detail).
  double _exposure = 0; // -100..100
  double _brightness = 0; // -100..100
  double _contrast = 1.0; // 0..2
  double _highlights = 0; // -100..100
  double _shadows = 0; // -100..100
  double _saturation = 1.0; // 0..2
  double _vibrance = 0; // -100..100
  double _temperature = 0; // -100..100
  double _tint = 0; // -100..100
  double _sharpenDetail = 0; // 0..100 (Adjust > Detail)
  double _vignette = 0; // 0..100
  double _fade = 0; // 0..100
  // Round-2 Crop panel state.
  String _cropPreset = 'free'; // free, 9:16, 1:1, 16:9, 4:5, 3:4
  double _straighten = 0; // -45..45 degrees, applied on button tap
  // Round-2 Enhance intensity sliders (defaults = the old hard-coded
  // strengths: Sharpen 0.8 -> 80, Denoise 0.6 -> 60).
  double _sharpenAmount = 80; // 0..100
  double _denoiseAmount = 60; // 0..100
  // Round-2 AI tab: solid colour used by Replace Background.
  Color _replaceBgColor = Colors.white;
  // Pixel-preview (LUT / HSL / non-linear Adjust): a downscaled,
  // fully-processed copy of the photo, debounce-refreshed on change.
  Uint8List? _previewBytes;
  String? _previewKey; // working-file path _previewBytes belongs to
  Timer? _previewTimer;
  String _text = '';
  Color _textColor = Colors.white;
  double _textSize = 42;
  Offset _textOffset = const Offset(0.5, 0.8);
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
  // Daily upgrade 2026-10-31: line spacing for multi-line text.
  double _textLineSpacing = 1.0; // 0.8..2.0
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


  @override
  void initState() {
    super.initState();
    _ensureLuts();
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    super.dispose();
  }

  // v1.3.0 (§5B): the status shows as a transient overlay chip on
  // the preview (auto-hides), never as a permanent line.
  bool _statusVisible = false;
  Timer? _statusTimer;
  // §8: this session's AI-tools coin unlock (charged once).
  bool _aiCoinsPaid = false;
  // §5B: the active sub-tab inside the open photo tool.
  String? _photoTab;

  void _setStatus(String s) {
    setState(() => _status = s);
    _flashStatus();
  }

  void _flashStatus() {
    if (!mounted) return;
    setState(() => _statusVisible = true);
    _statusTimer?.cancel();
    _statusTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_busy) setState(() => _statusVisible = false);
    });
  }

  /// P15: failures must be SEEN, not just whispered into the small grey
  /// status line — every user-action failure also raises a SnackBar.
  /// The status string is still set (other code reads it).
  void _fail(String s) {
    _setStatus(s);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s)),
      );
    }
  }

  List<double> get _matrix => buildColorMatrix(
        filter: _filter,
        brightness: _brightness,
        contrast: _contrast,
        saturation: _saturation,
        filterIntensity: _filterIntensity,
        exposure: _exposure,
        temperature: _temperature,
        tint: _tint,
        vibrance: _vibrance,
        fade: _fade,
      );

  bool get _hslIsNeutral => _hslAdjustments.every(
        (a) => a[0] == 0 && a[1] == 1.0 && a[2] == 0,
      );

  /// True when the preview needs the per-pixel pass (LUT selected, HSL
  /// touched, or a non-linear Adjust control moved) — the ColorFilter
  /// matrix alone cannot express those.
  bool get _needsPixelPreview =>
      _selectedLut.isNotEmpty ||
      !_hslIsNeutral ||
      _highlights != 0 ||
      _shadows != 0 ||
      _vignette != 0 ||
      _sharpenDetail != 0;

  /// Debounced pixel-preview refresh (250 ms). Builds a downscaled
  /// (max 720 px wide) copy with matrix + LUT + pixel Adjust + HSL
  /// baked in, so Filters/LUT/HSL/Adjust all preview LIVE.
  void _schedulePixelPreview() {
    _previewTimer?.cancel();
    if (_workingFile == null || !_needsPixelPreview) {
      if (_previewBytes != null) {
        setState(() {
          _previewBytes = null;
          _previewKey = null;
        });
      }
      return;
    }
    _previewTimer = Timer(
      const Duration(milliseconds: 250),
      _buildPixelPreview,
    );
  }

  Future<void> _buildPixelPreview() async {
    final file = _workingFile;
    if (file == null || !_needsPixelPreview) return;
    final key = file.path;
    try {
      var image = await _decodeWorking();
      if (image.width > 720) {
        image = img.copyResize(image, width: 720);
      }
      image = await applyColorMatrix(image, _matrix);
      final lut = _luts[_selectedLut];
      if (lut != null) {
        image = await applyLut(image, lut);
      }
      if (_highlights != 0 ||
          _shadows != 0 ||
          _vignette != 0 ||
          _sharpenDetail != 0) {
        image = await applyAdjustments(
          image,
          highlights: _highlights,
          shadows: _shadows,
          vignette: _vignette,
          sharpenDetail: _sharpenDetail,
        );
      }
      if (!_hslIsNeutral) {
        image = await adjustHSL(image, _hslAdjustments);
      }
      final bytes = _hasTransparency
          ? img.encodePng(image)
          : img.encodeJpg(image, quality: 85);
      if (!mounted || _workingFile?.path != key) return;
      setState(() {
        _previewBytes = bytes;
        _previewKey = key;
      });
    } catch (_) {
      // Preview is best-effort: the matrix preview stays on screen.
    }
  }

  /// Load the 5 bundled .cube LUTs once (assets declared in pubspec,
  /// same files as the video editor) and parse them for the photo
  /// pipeline. Failures leave the LUT row empty, never crash.
  Future<void> _ensureLuts() async {
    if (_luts.isNotEmpty || _lutsLoading) return;
    _lutsLoading = true;
    try {
      for (final e in photoLuts) {
        final name = e['name']!;
        try {
          final src = await rootBundle.loadString(e['asset']!);
          final lut = parseCubeLut(src);
          if (lut != null) _luts[name] = lut;
        } catch (_) {
          // One bad/missing asset must not block the others.
        }
      }
    } finally {
      _lutsLoading = false;
    }
    if (mounted) {
      setState(() {});
      _buildFilterThumbs();
    }
  }

  /// Filter/LUT thumbnails: each look rendered onto a downscaled copy
  /// of the CURRENT photo (cached per working file) — no more blind
  /// text chips (P8).
  Future<void> _buildFilterThumbs() async {
    final file = _workingFile;
    if (file == null) return;
    final key = file.path;
    if (_thumbKey == key && _filterThumbs.isNotEmpty) return;
    try {
      var base = await _decodeWorking();
      base = img.copyResize(base, width: 144);
      final map = <PhotoFilter, Uint8List>{};
      for (final pf in PhotoFilter.values) {
        final m = buildColorMatrix(
          filter: pf,
          brightness: 0,
          contrast: 1,
          saturation: 1,
        );
        final im = await applyColorMatrix(base, m);
        map[pf] = img.encodeJpg(im, quality: 80);
      }
      final lutMap = <String, Uint8List>{};
      for (final e in _luts.entries) {
        final im = await applyLut(base, e.value);
        lutMap[e.key] = img.encodeJpg(im, quality: 80);
      }
      if (!mounted || _workingFile?.path != key) return;
      setState(() {
        _filterThumbs = map;
        _lutThumbs = lutMap;
        _thumbKey = key;
      });
    } catch (_) {
      // Thumbnails are best-effort; the panel falls back to chips.
    }
  }

  /// Reset every non-destructive edit control to its default.
  void _resetEditParams() {
    _filter = PhotoFilter.normal;
    _filterIntensity = 1.0;
    _selectedLut = '';
    _exposure = 0;
    _brightness = 0;
    _contrast = 1.0;
    _highlights = 0;
    _shadows = 0;
    _saturation = 1.0;
    _vibrance = 0;
    _temperature = 0;
    _tint = 0;
    _sharpenDetail = 0;
    _vignette = 0;
    _fade = 0;
    _straighten = 0;
    _cropPreset = 'free';
    _hslAdjustments = List.generate(8, (_) => [0.0, 1.0, 0.0]);
    _hslSelectedColor = 0;
    _previewBytes = null;
    _previewKey = null;
  }

  Future<void> _pick() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final f = File(picked.path);
    setState(() {
      _workingFile = f;
      _originalFile = f;
      _history
        ..clear()
        ..add(f);
      _historyIndex = 0;
      _resetEditParams();
      _text = '';
      _hasTransparency = false;
      _thumbKey = null;
      _filterThumbs = {};
      _lutThumbs = {};
      _status = 'Photo loaded.';
    });
    _buildFilterThumbs();
  }

  /// The single choke point for changing the working photo: pushes the
  /// new state onto the undo history (max 10 states kept) and refreshes
  /// the per-photo caches. Every destructive op flows through here or
  /// through _replaceWorking (which ends here too).
  void _setWorkingFile(File f) {
    // Drop any redo tail, then append the new state.
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    if (_history.isEmpty || _history.last.path != f.path) {
      _history.add(f);
    }
    while (_history.length > 10) {
      _history.removeAt(0);
    }
    _historyIndex = _history.length - 1;
    setState(() {
      _workingFile = f;
      _previewBytes = null;
      _previewKey = null;
      _thumbKey = null;
    });
    _buildFilterThumbs();
    _schedulePixelPreview();
  }

  bool get _canUndo => _historyIndex > 0;
  bool get _canRedo => _historyIndex < _history.length - 1;

  void _undo() {
    if (!_canUndo || _busy) return;
    setState(() {
      _historyIndex--;
      _workingFile = _history[_historyIndex];
      _previewBytes = null;
      _previewKey = null;
      _thumbKey = null;
      _status = 'Undo.';
    });
    _buildFilterThumbs();
    _schedulePixelPreview();
  }

  void _redo() {
    if (!_canRedo || _busy) return;
    setState(() {
      _historyIndex++;
      _workingFile = _history[_historyIndex];
      _previewBytes = null;
      _previewKey = null;
      _thumbKey = null;
      _status = 'Redo.';
    });
    _buildFilterThumbs();
    _schedulePixelPreview();
  }

  /// Reset-all (P6): restore the originally picked photo and every
  /// default param; history restarts from the original.
  void _resetAll() {
    final orig = _originalFile;
    if (orig == null || _busy) return;
    setState(() {
      _workingFile = orig;
      _history
        ..clear()
        ..add(orig);
      _historyIndex = 0;
      _resetEditParams();
      _text = '';
      _hasTransparency = false;
      _thumbKey = null;
      _filterThumbs = {};
      _lutThumbs = {};
      _status = 'Reset — original photo restored.';
    });
    _buildFilterThumbs();
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
    _setWorkingFile(f);
  }

  Future<img.Image> _decodeWorking() async {
    final file = _workingFile;
    if (file == null) throw Exception('No photo loaded.');
    final bytes = await file.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Could not read this photo.');
    return image;
  }

  /// The full preset list handed to the system cropper (P10). The
  /// package's enum has no portrait 9:16 / 4:5 / 3:4 entries, so those
  /// exact ratios are ALSO offered as one-tap centre crops in the Crop
  /// panel (see _quickRatioCrop) — every promised preset works.
  List<CropAspectRatioPreset> _cropPresets() {
    const all = [
      CropAspectRatioPreset.original,
      CropAspectRatioPreset.square,
      CropAspectRatioPreset.ratio16x9,
      CropAspectRatioPreset.ratio5x4,
      CropAspectRatioPreset.ratio4x3,
      CropAspectRatioPreset.ratio3x2,
      CropAspectRatioPreset.ratio5x3,
      CropAspectRatioPreset.ratio7x5,
    ];
    // The selected panel preset opens first in the cropper where the
    // enum can express it.
    final first = switch (_cropPreset) {
      '1:1' => CropAspectRatioPreset.square,
      '16:9' => CropAspectRatioPreset.ratio16x9,
      '4:5' => CropAspectRatioPreset.ratio5x4,
      '3:4' => CropAspectRatioPreset.ratio4x3,
      _ => CropAspectRatioPreset.original,
    };
    return [first, ...all.where((e) => e != first)];
  }

  Future<void> _crop() async {
    final file = _workingFile;
    if (file == null) return;
    try {
      // image_cropper v13: presets live inside AndroidUiSettings
      // (the top-level aspectRatioPresets arg no longer exists).
      // Portrait ratios the enum lacks (9:16 / 4:5 / 3:4) are covered
      // by the in-panel one-tap centre crops.
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
            aspectRatioPresets: _cropPresets(),
          ),
        ],
      );
      if (cropped != null) {
        _setWorkingFile(File(cropped.path));
        _setStatus('Cropped.');
      }
    } catch (e) {
      _fail('Crop failed: $e');
    }
  }

  /// One-tap centre crop to an exact ratio (9:16, 1:1, 16:9, 4:5, 3:4).
  /// Goes through the history stack, so it is undoable like any op.
  Future<void> _quickRatioCrop(String label, int rx, int ry) async {
    if (_workingFile == null || _busy) return;
    setState(() => _cropPreset = label);
    await _runEnhance('Cropping to $label', () async {
      final image = await _decodeWorking();
      final target = rx / ry;
      final current = image.width / image.height;
      int w = image.width, h = image.height;
      if (current > target) {
        w = (image.height * target).round();
      } else {
        h = (image.width / target).round();
      }
      if (w == image.width && h == image.height) return;
      final x = (image.width - w) ~/ 2;
      final y = (image.height - h) ~/ 2;
      final out = img.copyCrop(image, x: x, y: y, width: w, height: h);
      await _replaceWorking(out);
    });
  }

  /// Mirror the photo horizontally (Crop panel — its only home now).
  Future<void> _flipHorizontal() async {
    await _runEnhance('Flipping', () async {
      final image = await _decodeWorking();
      await _replaceWorking(flipHorizontalPhoto(image));
    });
  }

  /// Bake the straighten slider's angle into the photo, then re-centre
  /// the slider so a second Apply starts from the new "level".
  Future<void> _applyStraighten() async {
    if (_straighten == 0) return;
    final angle = _straighten;
    await _runEnhance('Straightening', () async {
      final image = await _decodeWorking();
      await _replaceWorking(straightenPhoto(image, angle));
    });
    if (mounted) setState(() => _straighten = 0);
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
      _fail('Rotate failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  /// Runs an AI job; returns true on success. Errors surface as a
  /// status line AND a SnackBar (P15).
  /// AI tools are Premium: v1.3.0 (§8) the unlock is COINS ONLY —
  /// the first AI use in a session charges CoinFeature.aiEnhance
  /// (50 coins) after a confirm dialog showing cost + balance;
  /// the ad-unlock path is gone from the whole app. Admins are
  /// waived by CoinService itself.
  Future<bool> _runAi(String label, Future<void> Function() job) async {
    final file = _workingFile;
    if (file == null || _busy) return false;
    if (!_aiCoinsPaid && !CoinService.instance.isAdminNow) {
      final cost = CoinCosts.costFor(CoinFeature.aiEnhance);
      final balance = CoinService.instance.balance.value;
      if (!mounted) return false;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Premium AI tools'),
          content: Text(
            'AI tools is session mein $cost coins se unlock honge.\n'
            'Aap ka balance: $balance coins.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Later'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Unlock — $cost coins'),
            ),
          ],
        ),
      );
      if (confirm != true) return false;
      final res = await CoinService.instance.spend(CoinFeature.aiEnhance);
      if (!res.ok) {
        _fail(
          res.error == 'insufficient_balance'
              ? 'Coins kam hain — Coins section se rewarded ads '
                  'dekh kar coins kamayein.'
              : 'Unlock nahi hua (${res.error ?? 'error'}).',
        );
        return false;
      }
      _aiCoinsPaid = true;
      _setStatus(
        res.adminFree
            ? 'Admin — AI tools free unlock ho gaye.'
            : 'AI tools unlock ho gaye ($cost coins).',
      );
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
      _fail('$label failed: $e');
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

  /// Replace Background with the picked solid colour (AI tab). The
  /// segmentation mask supports this directly — subject kept,
  /// everything else becomes the colour. Result is opaque.
  Future<void> _replaceBackgroundColor() async {
    final file = _workingFile;
    if (file == null) return;
    final ok = await _runAi('Replacing background', () async {
      final mask = await AiService.segmentSubject(file);
      final image = await _decodeWorking();
      final out = await replaceBackground(
        image,
        mask,
        bgArgb: _replaceBgColor.toARGB32(),
      );
      await _replaceWorking(out);
    });
    if (ok) setState(() => _hasTransparency = false);
  }

  /// Replace Background with a gallery image (AI tab).
  Future<void> _replaceBackgroundImage() async {
    final file = _workingFile;
    if (file == null || _busy) return;
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final ok = await _runAi('Replacing background', () async {
      final mask = await AiService.segmentSubject(file);
      final image = await _decodeWorking();
      final bgBytes = await File(picked.path).readAsBytes();
      final bgImage = img.decodeImage(bgBytes);
      if (bgImage == null) {
        throw Exception('Background photo could not be read.');
      }
      final out = await replaceBackground(image, mask, bgImage: bgImage);
      await _replaceWorking(out);
    });
    if (ok) setState(() => _hasTransparency = false);
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
  Future<bool> _runEnhance(
      String label, Future<void> Function() job) async {
    final file = _workingFile;
    if (file == null || _busy) return false;
    setState(() {
      _busy = true;
      _status = '$label… (on-device)';
    });
    try {
      await job();
      _setStatus('$label done.');
      return true;
    } catch (e) {
      _fail('$label failed: $e');
      return false;
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _sharpen() async {
    // Intensity slider 0..100 -> unsharp amount 0..1 (80 = old 0.8).
    final amount = _sharpenAmount / 100;
    await _runEnhance('Sharpening', () async {
      final image = await _decodeWorking();
      final out = await sharpenImage(image, amount: amount);
      await _replaceWorking(out);
    });
  }

  Future<void> _denoise() async {
    // Intensity slider 0..100 -> strength 0..1 (60 = old 0.6).
    final strength = _denoiseAmount / 100;
    await _runEnhance('Denoising', () async {
      final image = await _decodeWorking();
      final out = await denoiseImage(image, strength: strength);
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
    final ok = await _runEnhance('Applying HSL', () async {
      final image = await _decodeWorking();
      final out = await adjustHSL(image, _hslAdjustments);
      await _replaceWorking(out);
    });
    // P7: after a successful Apply the sliders return to neutral, so
    // a second Apply can never silently double-apply the same shift.
    if (ok) _resetHSL();
  }

  /// Reset all HSL adjustments to neutral.
  void _resetHSL() {
    setState(() {
      _hslAdjustments = List.generate(8, (_) => [0.0, 1.0, 0.0]);
      _hslSelectedColor = 0;
    });
    _schedulePixelPreview();
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
      final lut = _luts[_selectedLut];
      final params = PhotoEditParams(
        filter: _filter,
        filterIntensity: _filterIntensity,
        lutName: _selectedLut,
        lutSize: lut?.size ?? 0,
        lutTable: lut?.table,
        brightness: _brightness,
        contrast: _contrast,
        saturation: _saturation,
        exposure: _exposure,
        highlights: _highlights,
        shadows: _shadows,
        vibrance: _vibrance,
        temperature: _temperature,
        tint: _tint,
        sharpenDetail: _sharpenDetail,
        vignette: _vignette,
        fade: _fade,
        text: _text,
        textArgb: _textColor.toARGB32(),
        textSize: _textSize,
        textOffsetX: _textOffset.dx,
        textOffsetY: _textOffset.dy,
        textShadow: _textShadow,
        textGlow: _textGlow,
        textBg: _textBg,
        textBgArgb: _textBgColor.toARGB32(),
        textLineHeight: _textLineSpacing,
        // P9: the full Text panel state — font, weight, italic,
        // opacity, spacing, outline and alignment all reach export.
        textFont: _textFont,
        textBold: _textBold,
        textItalic: _textItalic,
        textOpacity: _textOpacity,
        textLetterSpacing: _textLetterSpacing,
        textOutline: _textOutline,
        textOutlineArgb: _textOutlineColor.toARGB32(),
        textOutlineWidth: _textOutlineWidth,
        textAlignIndex: _textAlign == TextAlign.left
            ? 0
            : _textAlign == TextAlign.right
                ? 2
                : 1,
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
      _fail('Export failed: $e');
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
        onTap: () => setState(() {
              _activePhotoTool = key;
              _photoTab = null;
            }),
        child: Container(
          width: 76,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? _accent : const Color(0xFF232323),
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
      'crop': 'Crop',
      'filters': 'Filters',
      'adjust': 'Adjust',
      'text': 'Text',
      'hsl': 'HSL',
      'enhance': 'Enhance',
      'ai': 'AI Tools',
    };
    return names[key] ?? key;
  }

  /// One AI-tab action with its Premium badge ON the button (P3: the
  /// user sees the gate before tapping, not after).
  Widget _aiAction({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Premium',
              style: TextStyle(color: Colors.white, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  /// Section header inside the Adjust panel (Light / Colour / Detail).
  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Text(
        text,
        style: const TextStyle(
          color: _accentLight,
          fontWeight: FontWeight.bold,
          fontSize: 12,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  /// One filter/LUT thumbnail tile in the Filters panel: the look
  /// rendered on the user's own photo, with a violet selected ring.
  Widget _lookThumb({
    required String label,
    required bool selected,
    required Uint8List? thumb,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? _accent : Colors.white24,
                  width: selected ? 3 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: thumb != null
                    ? Image.memory(thumb, fit: BoxFit.cover)
                    : Container(
                        color: const Color(0xFF2A2A2A),
                        child: const Icon(Icons.image, color: Colors.grey),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 66,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? _accentLight : Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
            onPressed: () => setState(() {
                  _activePhotoTool = null;
                  _photoTab = null;
                }),
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
            onPressed: () => setState(() {
                  _activePhotoTool = null;
                  _photoTab = null;
                }),
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
    final TextStyle base = TextStyle(
      color: color.withValues(alpha: _textOpacity),
      fontSize: fontSize,
      height: _textLineSpacing,
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

  /// One-tap text style templates (daily upgrade 2026-10-31). Each template
  /// sets the font, color, weight and effect combo; the user can fine-tune
  /// afterwards. Pure state change — safe by construction.
  void _applyTextTemplate(String key) {
    setState(() {
      switch (key) {
        case 'classic':
          _textFont = 'default';
          _textColor = Colors.white;
          _textBold = true;
          _textItalic = false;
          _textShadow = true;
          _textGlow = false;
          _textOutline = false;
          _textBg = false;
          _textLetterSpacing = 0.0;
          _textOpacity = 1.0;
        case 'neon':
          _textFont = 'bebas';
          _textColor = Colors.cyanAccent;
          _textBold = true;
          _textItalic = false;
          _textShadow = false;
          _textGlow = true;
          _textOutline = false;
          _textBg = false;
          _textLetterSpacing = 2.0;
          _textOpacity = 1.0;
        case 'breaking':
          _textFont = 'roboto';
          _textColor = Colors.yellow;
          _textBold = true;
          _textItalic = false;
          _textShadow = true;
          _textGlow = false;
          _textOutline = false;
          _textBg = true;
          _textBgColor = Colors.red;
          _textLetterSpacing = 1.0;
          _textOpacity = 1.0;
        case 'elegant':
          _textFont = 'merriweather';
          _textColor = Colors.white;
          _textBold = false;
          _textItalic = true;
          _textShadow = true;
          _textGlow = false;
          _textOutline = false;
          _textBg = false;
          _textLetterSpacing = 0.5;
          _textOpacity = 1.0;
        case 'urdu':
          _textFont = 'nastaliq';
          _textColor = const Color(0xFFFFD54F);
          _textBold = false;
          _textItalic = false;
          _textShadow = true;
          _textGlow = false;
          _textOutline = false;
          _textBg = false;
          _textLetterSpacing = 0.0;
          _textOpacity = 1.0;
        case 'script':
          _textFont = 'dancing';
          _textColor = Colors.pinkAccent;
          _textBold = false;
          _textItalic = false;
          _textShadow = false;
          _textGlow = true;
          _textOutline = false;
          _textBg = false;
          _textLetterSpacing = 1.0;
          _textOpacity = 1.0;
      }
    });
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
        color: _textColor.withValues(alpha: 0.9),
        blurRadius: 16,
      ));
      shadows.add(Shadow(
        color: _textColor.withValues(alpha: 0.6),
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

  /// v1.3.0 (§5B): sub-tabs inside the multi-section photo tools.
  /// Only the active sub-tab's controls render — the full tool
  /// list is partitioned at its section anchors, so every control
  /// is preserved exactly (nothing removed, only re-homed).
  List<(String, String)> _photoTabs() {
    switch (_activePhotoTool) {
      case 'crop':
        return const [('ratio', 'Ratio'), ('straighten', 'Straighten')];
      case 'adjust':
        return const [
          ('light', 'Light'),
          ('colour', 'Colour'),
          ('detail', 'Detail'),
        ];
      case 'text':
        return const [
          ('write', 'Write'),
          ('style', 'Style'),
          ('effects', 'Effects'),
        ];
      default:
        return const [];
    }
  }

  String get _currentPhotoTab {
    final tabs = _photoTabs();
    if (tabs.isEmpty) return '';
    final t = _photoTab;
    if (t != null && tabs.any((e) => e.$1 == t)) return t;
    return tabs.first.$1;
  }

  Widget _photoTabRow() {
    final tabs = _photoTabs();
    if (tabs.length < 2) return const SizedBox.shrink();
    final current = _currentPhotoTab;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final t in tabs)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(t.$2),
                  selected: current == t.$1,
                  onSelected: (_) => setState(() => _photoTab = t.$1),
                ),
              ),
          ],
        ),
      ),
    );
  }

  int _anchorIdx(List<Widget> items, bool Function(Widget) test) {
    for (var i = 0; i < items.length; i++) {
      if (test(items[i])) return i;
    }
    return -1;
  }

  bool _isSectionLabel(Widget w, String text) =>
      w is Padding && w.child is Text && (w.child as Text).data == text;

  /// The visible slice of the open tool's panel (§5B partitions).
  List<Widget> _photoVisibleChildren() {
    final all = _photoPanelChildren();
    switch (_activePhotoTool) {
      case 'crop':
        final idx = _anchorIdx(
          all,
          (w) => w is Text && w.data == 'Straighten',
        );
        if (idx < 0) return all;
        return _currentPhotoTab == 'straighten'
            ? all.sublist(idx)
            : all.sublist(0, idx);
      case 'adjust':
        final colourIdx =
            _anchorIdx(all, (w) => _isSectionLabel(w, 'COLOUR'));
        final detailIdx =
            _anchorIdx(all, (w) => _isSectionLabel(w, 'DETAIL'));
        if (colourIdx < 0 || detailIdx < 0 || all.isEmpty) return all;
        // The header row (title + Reset) rides on every tab.
        final header = all.first;
        switch (_currentPhotoTab) {
          case 'colour':
            return [header, ...all.sublist(colourIdx, detailIdx)];
          case 'detail':
            return [header, ...all.sublist(detailIdx)];
          default:
            return [header, ...all.sublist(1, colourIdx)];
        }
      case 'text':
        final sizeIdx = _anchorIdx(
          all,
          (w) => w is _SliderRow && w.label == 'Text size',
        );
        final fxIdx = _anchorIdx(
          all,
          (w) => w is Text && w.data == 'Effects',
        );
        if (sizeIdx < 2 || fxIdx < 0 || fxIdx <= sizeIdx - 2) return all;
        final styleStart = sizeIdx - 2;
        switch (_currentPhotoTab) {
          case 'style':
            return all.sublist(styleStart, fxIdx);
          case 'effects':
            return all.sublist(fxIdx);
          default:
            return all.sublist(0, styleStart);
        }
      default:
        return all;
    }
  }

  List<Widget> _photoPanelChildren() {
    final file = _workingFile;
    switch (_activePhotoTool) {
      case 'crop':
        // Round-2: Crop is the ONLY home for crop + rotate (P2) and
        // gains aspect presets, flip and straighten (P10).
        return [
          const Text('Crop',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: file == null || _busy ? null : _crop,
              icon: const Icon(Icons.crop),
              label: const Text('Crop (system)'),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ratio presets — tap for an instant centre crop '
            '(Undo se wapas ho sakta hai):',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('Free'),
                onPressed: file == null || _busy
                    ? null
                    : () {
                        setState(() => _cropPreset = 'free');
                        _crop();
                      },
              ),
              ActionChip(
                label: const Text('9:16'),
                onPressed: file == null || _busy
                    ? null
                    : () => _quickRatioCrop('9:16', 9, 16),
              ),
              ActionChip(
                label: const Text('1:1'),
                onPressed: file == null || _busy
                    ? null
                    : () => _quickRatioCrop('1:1', 1, 1),
              ),
              ActionChip(
                label: const Text('16:9'),
                onPressed: file == null || _busy
                    ? null
                    : () => _quickRatioCrop('16:9', 16, 9),
              ),
              ActionChip(
                label: const Text('4:5'),
                onPressed: file == null || _busy
                    ? null
                    : () => _quickRatioCrop('4:5', 4, 5),
              ),
              ActionChip(
                label: const Text('3:4'),
                onPressed: file == null || _busy
                    ? null
                    : () => _quickRatioCrop('3:4', 3, 4),
              ),
            ],
          ),
          const Divider(height: 24),
          const Text('Rotate & flip',
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
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: file == null || _busy ? null : _flipHorizontal,
              icon: const Icon(Icons.flip),
              label: const Text('Flip horizontal'),
            ),
          ),
          const Divider(height: 24),
          const Text('Straighten',
              style: TextStyle(fontWeight: FontWeight.bold)),
          _SliderRow(
            label: 'Angle',
            value: _straighten,
            min: -45,
            max: 45,
            onChanged: (v) => setState(() => _straighten = v),
          ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  file == null || _busy || _straighten == 0
                      ? null
                      : _applyStraighten,
              icon: const Icon(Icons.check),
              label: const Text('Apply straighten'),
            ),
          ),
        ];
      case 'filters':
        // Round-2 (P1/P8): filters live ONLY here (the permanent strip
        // under the preview is gone), as thumbnails rendered on the
        // user's own photo, plus an intensity slider and the 5 LUTs.
        return [
          const Text('Filters', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filterLabels.entries.map((e) {
                return _lookThumb(
                  label: e.value,
                  selected: e.key == _filter,
                  thumb: _filterThumbs[e.key],
                  onTap: () {
                    setState(() => _filter = e.key);
                    _schedulePixelPreview();
                  },
                );
              }).toList(),
            ),
          ),
          _SliderRow(
            label: 'Intensity',
            value: _filterIntensity * 100,
            min: 0,
            max: 100,
            onChanged: (v) {
              setState(() => _filterIntensity = v / 100);
              _schedulePixelPreview();
            },
          ),
          const Divider(height: 24),
          const Text('LUT looks',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _lookThumb(
                  label: 'None',
                  selected: _selectedLut.isEmpty,
                  thumb: _filterThumbs[PhotoFilter.normal],
                  onTap: () {
                    setState(() => _selectedLut = '');
                    _schedulePixelPreview();
                  },
                ),
                ...photoLuts.map((e) {
                  final name = e['name']!;
                  return _lookThumb(
                    label: name,
                    selected: _selectedLut == name,
                    thumb: _lutThumbs[name],
                    onTap: () {
                      setState(() => _selectedLut = name);
                      _schedulePixelPreview();
                    },
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'LUTs video editor wale hi 5 looks hain — photo par bhi '
            'ab full quality apply hote hain.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ];
      case 'adjust':
        // Round-2 (P5): 12 sliders in 3 labelled sections. Matrix
        // controls preview through the ColorFilter; Highlights /
        // Shadows / Vignette / Sharpen ride the debounced pixel
        // preview — all live, all exported identically.
        return [
          Row(
            children: [
              const Text('Adjust',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    _exposure = 0;
                    _brightness = 0;
                    _contrast = 1.0;
                    _highlights = 0;
                    _shadows = 0;
                    _saturation = 1.0;
                    _vibrance = 0;
                    _temperature = 0;
                    _tint = 0;
                    _sharpenDetail = 0;
                    _vignette = 0;
                    _fade = 0;
                  });
                  _schedulePixelPreview();
                },
                child: const Text('Reset'),
              ),
            ],
          ),
          _sectionLabel('LIGHT'),
          _SliderRow(
            label: 'Exposure',
            value: _exposure,
            min: -100,
            max: 100,
            onChanged: (v) {
              setState(() => _exposure = v);
              _schedulePixelPreview();
            },
          ),
          _SliderRow(
            label: 'Brightness',
            value: _brightness,
            min: -100,
            max: 100,
            onChanged: (v) {
              setState(() => _brightness = v);
              _schedulePixelPreview();
            },
          ),
          _SliderRow(
            label: 'Contrast',
            value: _contrast,
            min: 0,
            max: 2,
            onChanged: (v) {
              setState(() => _contrast = v);
              _schedulePixelPreview();
            },
          ),
          _SliderRow(
            label: 'Highlights',
            value: _highlights,
            min: -100,
            max: 100,
            onChanged: (v) {
              setState(() => _highlights = v);
              _schedulePixelPreview();
            },
          ),
          _SliderRow(
            label: 'Shadows',
            value: _shadows,
            min: -100,
            max: 100,
            onChanged: (v) {
              setState(() => _shadows = v);
              _schedulePixelPreview();
            },
          ),
          _sectionLabel('COLOUR'),
          _SliderRow(
            label: 'Saturation',
            value: _saturation,
            min: 0,
            max: 2,
            onChanged: (v) {
              setState(() => _saturation = v);
              _schedulePixelPreview();
            },
          ),
          _SliderRow(
            label: 'Vibrance',
            value: _vibrance,
            min: -100,
            max: 100,
            onChanged: (v) {
              setState(() => _vibrance = v);
              _schedulePixelPreview();
            },
          ),
          _SliderRow(
            label: 'Temperature',
            value: _temperature,
            min: -100,
            max: 100,
            onChanged: (v) {
              setState(() => _temperature = v);
              _schedulePixelPreview();
            },
          ),
          _SliderRow(
            label: 'Tint',
            value: _tint,
            min: -100,
            max: 100,
            onChanged: (v) {
              setState(() => _tint = v);
              _schedulePixelPreview();
            },
          ),
          _sectionLabel('DETAIL'),
          _SliderRow(
            label: 'Sharpen',
            value: _sharpenDetail,
            min: 0,
            max: 100,
            onChanged: (v) {
              setState(() => _sharpenDetail = v);
              _schedulePixelPreview();
            },
          ),
          _SliderRow(
            label: 'Vignette',
            value: _vignette,
            min: 0,
            max: 100,
            onChanged: (v) {
              setState(() => _vignette = v);
              _schedulePixelPreview();
            },
          ),
          _SliderRow(
            label: 'Fade',
            value: _fade,
            min: 0,
            max: 100,
            onChanged: (v) {
              setState(() => _fade = v);
              _schedulePixelPreview();
            },
          ),
          const SizedBox(height: 8),
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
          // ---- One-tap style templates (daily upgrade 2026-10-31) ----
          const Text('Templates',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Classic'),
                selected: false,
                onSelected: (_) => _applyTextTemplate('classic'),
              ),
              ChoiceChip(
                label: const Text('Neon'),
                selected: false,
                onSelected: (_) => _applyTextTemplate('neon'),
              ),
              ChoiceChip(
                label: const Text('Breaking'),
                selected: false,
                onSelected: (_) => _applyTextTemplate('breaking'),
              ),
              ChoiceChip(
                label: const Text('Elegant'),
                selected: false,
                onSelected: (_) => _applyTextTemplate('elegant'),
              ),
              ChoiceChip(
                label: const Text('Urdu'),
                selected: false,
                onSelected: (_) => _applyTextTemplate('urdu'),
              ),
              ChoiceChip(
                label: const Text('Script'),
                selected: false,
                onSelected: (_) => _applyTextTemplate('script'),
              ),
            ],
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
                onPressed: () => setState(() => _textAlign = TextAlign.left),
                icon: Icon(Icons.format_align_left,
                    color: _textAlign == TextAlign.left
                        ? _accentLight
                        : Colors.grey),
              ),
              IconButton(
                tooltip: 'Center',
                onPressed: () => setState(() => _textAlign = TextAlign.center),
                icon: Icon(Icons.format_align_center,
                    color: _textAlign == TextAlign.center
                        ? _accentLight
                        : Colors.grey),
              ),
              IconButton(
                tooltip: 'Right',
                onPressed: () => setState(() => _textAlign = TextAlign.right),
                icon: Icon(Icons.format_align_right,
                    color: _textAlign == TextAlign.right
                        ? _accentLight
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
          _SliderRow(
            label: 'Line spacing',
            value: _textLineSpacing,
            min: 0.8,
            max: 2.0,
            onChanged: (v) => setState(() => _textLineSpacing = v),
          ),
          const Divider(height: 24),
          // ---- Effects: Shadow / Glow / Outline / Ribbon ----
          const Text('Effects', style: TextStyle(fontWeight: FontWeight.bold)),
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
                          onTap: () => setState(() => _textOutlineColor = c),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _textOutlineColor == c
                                    ? _accentLight
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
                                    ? _accentLight
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
            // Round-2: ONE AI home (P3) — the old BG Remover rail tool
            // is gone; Remove/Blur/Replace Background, Beautify and
            // Auto-enhance all live here, each badged Premium (P3/P4).
            const Text('AI tools (on-device, offline)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              'Har AI tool Premium hai — pehli dafa ek short ad se '
              'unlock hoga.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _aiAction(
                  label: 'Remove background',
                  icon: Icons.person_off,
                  onPressed: file == null || _busy ? null : _removeBackground,
                ),
                _aiAction(
                  label: 'Blur background',
                  icon: Icons.blur_on,
                  onPressed: file == null || _busy ? null : _blurBackground,
                ),
                _aiAction(
                  label: 'Beautify',
                  icon: Icons.face_retouching_natural,
                  onPressed: file == null || _busy ? null : _beautify,
                ),
                _aiAction(
                  label: 'Auto-enhance',
                  icon: Icons.auto_fix_high,
                  onPressed: file == null || _busy ? null : _autoEnhance,
                ),
              ],
            ),
            const Divider(height: 24),
            const Text('Replace background',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Colour:'),
                const SizedBox(width: 8),
                ...[
                  Colors.white,
                  Colors.black,
                  Colors.red,
                  Colors.blue,
                  Colors.green,
                  Colors.yellow,
                ].map((c) => GestureDetector(
                      onTap: () => setState(() => _replaceBgColor = c),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _replaceBgColor == c
                                ? _accentLight
                                : Colors.grey,
                            width: _replaceBgColor == c ? 3 : 1,
                          ),
                        ),
                      ),
                    )),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _aiAction(
                  label: 'Replace with colour',
                  icon: Icons.format_color_fill,
                  onPressed:
                      file == null || _busy ? null : _replaceBackgroundColor,
                ),
                _aiAction(
                  label: 'Replace with image',
                  icon: Icons.image,
                  onPressed:
                      file == null || _busy ? null : _replaceBackgroundImage,
                ),
              ],
            ),
            if (_hasTransparency) ...[
              const SizedBox(height: 12),
              const Text(
                'Background hata diya gaya hai — ab Save karein.',
                style: TextStyle(color: _accentLight),
              ),
            ],
          ],
          const SizedBox(height: 16),
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
          // Round-2 (P11): Sharpen/Denoise strengths are sliders now,
          // not hard-coded constants (defaults unchanged: 80 / 60).
          _SliderRow(
            label: 'Sharpen',
            value: _sharpenAmount,
            min: 0,
            max: 100,
            onChanged: (v) => setState(() => _sharpenAmount = v),
          ),
          _SliderRow(
            label: 'Denoise',
            value: _denoiseAmount,
            min: 0,
            max: 100,
            onChanged: (v) => setState(() => _denoiseAmount = v),
          ),
          const SizedBox(height: 8),
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
            'Rang select karein, phir Hue / Saturation / Lightness '
            'adjust karein — preview live update hota hai, Apply par '
            'photo mein bake ho jata hai.',
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
                    onChanged: (double v) {
                      setState(
                          () => _hslAdjustments[_hslSelectedColor][0] = v);
                      _schedulePixelPreview(); // P7: live preview
                    },
                  ),
                  _hslSlider(
                    label: 'Saturation',
                    value: adj[1],
                    min: 0,
                    max: 2,
                    onChanged: (double v) {
                      setState(
                          () => _hslAdjustments[_hslSelectedColor][1] = v);
                      _schedulePixelPreview();
                    },
                  ),
                  _hslSlider(
                    label: 'Lightness',
                    value: adj[2],
                    min: -100,
                    max: 100,
                    onChanged: (double v) {
                      setState(
                          () => _hslAdjustments[_hslSelectedColor][2] = v);
                      _schedulePixelPreview();
                    },
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
      default:
        // Round-2: no 'pick' rail tool anymore — Pick lives in the
        // empty state + the AppBar. This fallback only shows when no
        // photo is loaded yet (or an unknown key slips through).
        return [
          const Text('Pick a photo',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.photo_library),
              label: const Text('Pick photo'),
            ),
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
      // P13: violet identity, same as the rest of the app.
      data: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
            seedColor: _accent, brightness: Brightness.dark),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text('Photo Editor'),
          actions: [
            IconButton(
              tooltip: 'Pick photo',
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.photo_library),
            ),
            IconButton(
              tooltip: 'Undo',
              onPressed: _canUndo && !_busy ? _undo : null,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Redo',
              onPressed: _canRedo && !_busy ? _redo : null,
              icon: const Icon(Icons.redo),
            ),
            IconButton(
              tooltip: 'Reset all',
              onPressed: file == null || _busy ? null : _resetAll,
              icon: const Icon(Icons.restart_alt),
            ),
            // v1.3.0 (§5B): Save is a labelled GOLD pill in the
            // AppBar, not a bare icon.
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
              child: ElevatedButton.icon(
                onPressed: file == null || _busy ? null : _export,
                style: ElevatedButton.styleFrom(
                  backgroundColor: TjProTheme.gold,
                  foregroundColor: Colors.black,
                ),
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Save'),
              ),
            ),
          ],
        ),
        // LAYOUT (Round-2): 1. preview on top (large, with the Compare
        // chip)  2. tool panel  3. ONE single-row 7-tool rail at the
        // bottom. The old permanent filter strip is GONE (P1) — filters
        // live only in the Filters panel, and the space went back to
        // the preview/panel.
        // v1.3.0 (§5B): the status is a transient chip OVERLAYING
        // the preview (top of the body), not a permanent line.
        body: Stack(
          children: [
            Column(
              children: [
            Expanded(
              child: Container(
                color: Colors.black,
                padding: const EdgeInsets.all(8),
                child: Center(
                  child: file == null
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.photo_library,
                                size: 64, color: Colors.white38),
                            const SizedBox(height: 12),
                            const Text('No photo selected',
                                style: TextStyle(color: Colors.white70)),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _pick,
                              icon: const Icon(Icons.photo_library),
                              label: const Text('Pick photo'),
                            ),
                          ],
                        )
                      : Container(
            color: Colors.black12,
            constraints: const BoxConstraints(maxHeight: 420),
            child: LayoutBuilder(
                    builder: (context, constraints) {
                      final w = constraints.maxWidth;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // Preview source priority: hold-Compare shows
                          // the untouched original; the pixel preview
                          // (LUT/HSL/non-linear Adjust baked in) wins
                          // over the plain matrix preview.
                          if (_comparing && _originalFile != null)
                            Image.file(_originalFile!, fit: BoxFit.contain)
                          else if (_previewBytes != null &&
                              _previewKey == file.path)
                            Image.memory(_previewBytes!,
                                fit: BoxFit.contain)
                          else
                            ColorFiltered(
                              colorFilter: ColorFilter.matrix(_matrix),
                              child: Image.file(file, fit: BoxFit.contain),
                            ),
                          // Hold-to-compare (P6): press and hold the
                          // chip to see the original, release to return.
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTapDown: (_) =>
                                  setState(() => _comparing = true),
                              onTapUp: (_) =>
                                  setState(() => _comparing = false),
                              onTapCancel: () =>
                                  setState(() => _comparing = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _comparing
                                      ? _accent
                                      : Colors.black54,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.compare,
                                        size: 14, color: Colors.white),
                                    SizedBox(width: 4),
                                    Text('Compare',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11)),
                                  ],
                                ),
                              ),
                            ),
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
            // Tool zone (§5B): fixed height — the rail, or ONLY
            // the open tool's panel (header + sub-tabs + its
            // controls) in the rail's place.
            SizedBox(
              height: 218,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                transitionBuilder:
                    (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.05),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                          parent: animation, curve: Curves.easeOut)),
                      child: child,
                    ),
                  );
                },
                child: _activePhotoTool == null
                    ? Container(
                        key: const ValueKey<String>('photo-rail'),
                        color: const Color(0xFF1B1B1B),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(12, 10, 12, 2),
                              child: Text(
                                'Tools — koi tool chunein, sirf usi ke '
                                'controls khulenge.',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 12),
                              ),
                            ),
                            SizedBox(
                              height: 88,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                children: [
                                  // Round-2 rail: 7 tools. Pick lives
                                  // in the empty state + AppBar;
                                  // Rotate lives in Crop; BG Remover
                                  // lives in AI; Save in the AppBar.
                                  _photoRailButton(
                                      'crop', 'Crop', Icons.crop),
                                  _photoRailButton('filters', 'Filters',
                                      Icons.filter_vintage),
                                  _photoRailButton(
                                      'adjust', 'Adjust', Icons.tune),
                                  _photoRailButton(
                                      'text', 'Text', Icons.text_fields),
                                  _photoRailButton(
                                      'hsl', 'HSL', Icons.palette),
                                  _photoRailButton('enhance', 'Enhance',
                                      Icons.auto_fix_high),
                                  _photoRailButton(
                                      'ai', 'AI Tools', Icons.psychology),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        key: ValueKey<String>(
                            'photo-panel-${_activePhotoTool!}'),
                        color: const Color(0xFF121212),
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _photoPanelHeader(_activePhotoTool!),
                            _photoTabRow(),
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.only(top: 4),
                                children: _photoVisibleChildren(),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
              ],
            ),
            if (_statusVisible)
              Positioned(
                top: 10,
                left: 12,
                right: 12,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _status,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12),
                    ),
                  ),
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
