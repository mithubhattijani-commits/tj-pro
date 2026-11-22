/// Photo editor screen — v1.4.0 rebuild to the InShot layout
/// (requirements #2/#4, mockup S3): back arrow top-left, Export
/// top-right, big preview centre, floating side buttons, undo/redo
/// pill on the preview, ONE horizontal icon+label toolbar at the
/// bottom (Canvas, Filter, Adjust, Effect, Background, Portrait,
/// Sticker, Text, PIP, Remove, Enhance, Cutout, Doodle, Makeup,
/// Crop, Expand, Frame, Rotate). Tapping a tool swaps the toolbar
/// for that tool's panel (header = tool name + ✓); the preview
/// stays visible and every control applies LIVE where the pipeline
/// is non-destructive, or bakes through the undo history where it
/// is destructive. NOTHING from the v1.3.0 editor is removed: crop/
/// rotate/flip/straighten, 6 filters + 5 LUTs + intensity, the 12
/// Adjust sliders, HSL, the full text styling set, Sharpen/Denoise/
/// Enlarge/Color Fix and the ML Kit AI tools (BG remove/blur/
/// replace, Beautify, Auto-enhance) are all still here, re-homed
/// into the new toolbar. New in v1.4.0: the InShot text system
/// (multi-layer, on-canvas handles, style/colour/font panels),
/// Canvas, classic Effects, Sticker, PIP overlays, Doodle, Frame,
/// Expand, Makeup, and the ONNX pack tools (Remove via Mi-GAN,
/// AI Enhance HD via Real-ESRGAN, HQ Cutout via BiRefNet, Portrait
/// Bokeh via Depth Anything, Artistic Styles via fast-neural-style)
/// wired to OnnxImageService / ModelPackService.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_config.dart';
import '../services/ai_service.dart';
import '../services/caption_styles.dart';
import '../services/coin_service.dart';
import '../services/font_registry.dart';
import '../services/model_pack_service.dart';
import '../services/onnx_image_service.dart';
import '../services/photo_pipeline.dart';

/// Round-2 theme unification (P13): violet identity, same as the
/// rest of the app. The Export pill wears the approved mockup's
/// coral red (S3).
const _accent = Color(0xFF7C3AED);
const _accentLight = Color(0xFFA78BFA);
const _exportRed = Color(0xFFFF4D5E);

const _filterLabels = {
  PhotoFilter.normal: 'Normal',
  PhotoFilter.warm: 'Warm',
  PhotoFilter.cool: 'Cool',
  PhotoFilter.blackWhite: 'B&W',
  PhotoFilter.vivid: 'Vivid',
  PhotoFilter.sepia: 'Sepia',
};

/// Filter category chips (requirements #2). Each category lists the
/// look keys it shows: `f:<PhotoFilter name>` or `lut:<LUT name>`.
const _filterCategories = <String, List<String>>{
  'Feature': [
    'f:normal', 'f:warm', 'f:cool', 'f:blackWhite', 'f:vivid',
    'f:sepia', 'lut:TealOrange', 'lut:Vintage', 'lut:Noir',
    'lut:Golden', 'lut:CoolNight',
  ],
  'Lunar': ['f:blackWhite', 'f:cool', 'lut:Noir', 'lut:CoolNight'],
  'Skin': ['f:warm', 'f:sepia', 'lut:Golden'],
  'Jade': ['f:cool', 'lut:TealOrange', 'lut:CoolNight'],
  'Foodie': ['f:warm', 'f:vivid', 'lut:Golden'],
  'Clear': ['f:normal', 'f:vivid', 'f:cool'],
  'Bright': ['f:vivid', 'f:warm', 'lut:Golden'],
  'Retro': ['f:sepia', 'f:blackWhite', 'lut:Vintage', 'lut:Noir'],
  'Moss': ['f:cool', 'f:sepia', 'lut:TealOrange'],
};

const _palette = <Color>[
  Colors.white,
  Colors.black,
  Color(0xFFFFD60A),
  Colors.amber,
  Colors.orange,
  Colors.red,
  Colors.pink,
  Color(0xFF9C27B0),
  Colors.blue,
  Colors.cyan,
  Colors.teal,
  Colors.green,
  Colors.lime,
  Colors.brown,
  Colors.grey,
  Color(0xFFFFD76A),
];

const _stickerGlyphs = <String>[
  '★', '♥', '⚡', '☀', '☾', '♠', '♣', '♦',
  '😊', '😂', '🔥', '👍', '🎉', '✨', '🌟', '💛',
];

/// Top-level size probe for compute() (same pattern as AiService).
List<int> _decodeSizeOf(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return [0, 0];
  return [decoded.width, decoded.height];
}

/// One editable text layer (v1.4.0 Text system). The screen's single
/// set of text fields always mirrors the ACTIVE layer; layers are
/// saved/loaded through _saveActiveLayer/_loadLayer and every layer
/// is composited at export via exportPhotoWithLayers.
class _TextLayerData {
  _TextLayerData();

  String text = '';
  int colorArgb = 0xFFFFFFFF;
  double size = 42;
  Offset offset = const Offset(0.5, 0.8); // normalized centre
  double boxWidth = 0.7; // fraction of photo width
  double rotation = 0; // degrees, clockwise
  String font = 'default';
  bool bold = false;
  bool italic = false;
  double opacity = 1.0;
  double letterSpacing = 0.0;
  double lineSpacing = 1.0;
  int alignIndex = 1; // 0 left, 1 centre, 2 right
  bool shadow = true;
  int shadowArgb = 0xDD000000;
  double shadowDx = 2;
  double shadowDy = 3;
  double shadowBlur = 6;
  bool glow = false;
  int glowArgb = 0xFFFFFFFF;
  double glowBlur = 16;
  bool outline = false;
  int outlineArgb = 0xFF000000;
  double outlineWidth = 2.0;
  bool bg = false;
  int bgArgb = 0x8A000000;

  _TextLayerData clone() {
    final c = _TextLayerData();
    c.text = text;
    c.colorArgb = colorArgb;
    c.size = size;
    c.offset = offset;
    c.boxWidth = boxWidth;
    c.rotation = rotation;
    c.font = font;
    c.bold = bold;
    c.italic = italic;
    c.opacity = opacity;
    c.letterSpacing = letterSpacing;
    c.lineSpacing = lineSpacing;
    c.alignIndex = alignIndex;
    c.shadow = shadow;
    c.shadowArgb = shadowArgb;
    c.shadowDx = shadowDx;
    c.shadowDy = shadowDy;
    c.shadowBlur = shadowBlur;
    c.glow = glow;
    c.glowArgb = glowArgb;
    c.glowBlur = glowBlur;
    c.outline = outline;
    c.outlineArgb = outlineArgb;
    c.outlineWidth = outlineWidth;
    c.bg = bg;
    c.bgArgb = bgArgb;
    return c;
  }
}

/// One PIP photo / sticker-glyph overlay layer.
class _OverlayData {
  _OverlayData({this.path, this.glyph});

  String? path; // gallery photo (PIP)
  String? glyph; // sticker character
  Offset center = const Offset(0.5, 0.5); // normalized
  double scaleFrac = 0.35; // width as a fraction of photo width
  double rotation = 0; // degrees
}

class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({super.key, this.initialImagePath});

  /// v1.4.0 (Workstream B addition): when the Projects hub hands
  /// over a picked photo, it arrives here and is loaded on init
  /// through the exact same path as a gallery pick. Null (every
  /// existing call site) keeps the old pick-to-start behaviour.
  final String? initialImagePath;

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
  // Pixel size of the working photo (for exact normalized geometry).
  int _imgWidth = 0;
  int _imgHeight = 0;
  PhotoFilter _filter = PhotoFilter.normal;
  // Round-2 Filters: strength of the chosen filter look + the LUT row.
  double _filterIntensity = 1.0; // 0..1
  String _selectedLut = ''; // '' = no LUT, else a photoLuts name
  String _filterCategory = 'Feature';
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
  // v1.4.0 Adjust additions: global hue, grain, tone curve, and the
  // one selected control of the InShot-style icon row.
  double _hueShift = 0; // -180..180
  double _grain = 0; // 0..100
  String _adjSel = 'lightness';
  final Map<String, List<Offset>> _curvePoints = {
    'rgb': [const Offset(0, 0), const Offset(1, 1)],
    'r': [const Offset(0, 0), const Offset(1, 1)],
    'g': [const Offset(0, 0), const Offset(1, 1)],
    'b': [const Offset(0, 0), const Offset(1, 1)],
  };
  String _curveChannel = 'rgb';
  // Round-2 Crop panel state.
  String _cropPreset = 'free'; // free, 9:16, 1:1, 16:9, 4:5, 3:4
  double _straighten = 0; // -45..45 degrees, applied on button tap
  // Round-2 Enhance intensity sliders (defaults = the old hard-coded
  // strengths: Sharpen 0.8 -> 80, Denoise 0.6 -> 60).
  double _sharpenAmount = 80; // 0..100
  double _denoiseAmount = 60; // 0..100
  // Round-2 AI tab: solid colour used by Replace Background.
  Color _replaceBgColor = Colors.white;
  // Pixel-preview (LUT / HSL / non-linear Adjust / curve / effect):
  // a downscaled, fully-processed copy of the photo, debounce-
  // refreshed on change.
  Uint8List? _previewBytes;
  String? _previewKey; // working-file path _previewBytes belongs to
  Timer? _previewTimer;
  // ---- Text system state (mirrors the ACTIVE layer) ----
  final List<_TextLayerData> _layers = [];
  int _activeLayer = -1;
  String _text = '';
  Color _textColor = Colors.white;
  double _textSize = 42;
  Offset _textOffset = const Offset(0.5, 0.8);
  double _textBoxWidth = 0.7;
  double _textRotation = 0;
  // Font keys: the pipeline keys ('default', 'nastaliq', 'naskh',
  // 'kufi', 'gulzar', 'roboto', 'merriweather', 'dancing', 'bebas',
  // 'pacifico') plus every font_registry id (UrduFonts).
  String _textFont = 'default';
  bool _textShadow = true; // subtle drop shadow by default
  Color _textShadowColor = Colors.black;
  double _shadowOpacity = 0.85;
  double _shadowDx = 2;
  double _shadowDy = 3;
  double _shadowBlur = 6;
  bool _textGlow = false;
  Color _textGlowColor = Colors.white;
  double _glowBlur = 16;
  bool _textOutline = false;
  Color _textOutlineColor = Colors.black;
  double _textOutlineWidth = 2.0;
  bool _textBg = false; // ribbon/label background behind text
  Color _textBgColor = Colors.black54;
  bool _textBold = false;
  bool _textItalic = false;
  double _textOpacity = 1.0; // 0..1
  double _textLetterSpacing = 0.0; // -2..10
  TextAlign _textAlign = TextAlign.center;
  double _textLineSpacing = 1.0; // 0.8..2.0
  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _textFocus = FocusNode();
  String _textTab = 'type'; // type | style | colour | font
  String _styleTab = 'SPECIAL'; // SPECIAL | CAPTIONS | LABEL | TITLE
  String _colourTab = 'TEXT'; // TEXT|BORDER|SHADOW|GLOW|LABEL|OPACITY
  bool _textHintShown = false;
  // ---- Overlay (PIP / Sticker) state ----
  final List<_OverlayData> _overlays = [];
  int _activeOverlay = -1;
  // ---- Canvas / Expand / Frame state ----
  (String, int, int) _canvasRatio = ('Original', 0, 0);
  double _canvasZoom = 100; // % — photo scale inside the canvas
  (String, int, int) _expandRatio = ('9:16', 9, 16);
  String _expandFill = 'blur'; // blur | mirror
  Color _frameColor = Colors.white;
  double _frameWidthPct = 4; // % of photo width
  Color _outlineColor = Colors.white;
  double _outlineWidth = 10; // px at export scale / 10 ≈ image px
  // ---- Effect state ----
  String? _effectSel; // classic effect key, preview-only until Apply
  double _effectValue = 70; // 0..100
  // ---- Painting (Remove / Cutout eraser / Doodle) state ----
  String? _paintMode; // remove | erase | doodle
  final List<StrokePath> _strokes = [];
  StrokePath? _currentStroke;
  double _brushSize = 0.08; // diameter, fraction of photo width
  bool _maskErase = false; // Remove panel's mask-eraser toggle
  Color _doodleColor = Colors.red;
  // ---- Makeup state ----
  String _makeupMode = 'lips'; // lips | blush
  Color _makeupColor = const Color(0xFFD81B60);
  double _makeupIntensity = 55; // 0..100
  bool _busy = false;
  bool _hasTransparency = false;
  String _status = 'Pick a photo to start.';
  // The open tool's panel key, null = toolbar visible.
  String? _activePhotoTool;
  // InShot-style HSL state: 8 colors × [hue, sat, light].
  // Colors: Red, Orange, Yellow, Green, Cyan, Blue, Purple, Magenta.
  List<List<double>> _hslAdjustments =
      List.generate(8, (_) => [0.0, 1.0, 0.0]);
  int _hslSelectedColor = 0;
  final GlobalKey _previewKey2 = GlobalKey();
  // Rotate/scale handle drag bookkeeping (text box handle).
  double _handleStartAngle = 0;
  double _handleStartDist = 1;
  double _handleStartRot = 0;
  double _handleStartSize = 42;

  @override
  void initState() {
    super.initState();
    _ensureLuts();
    // Projects hub hand-off: load the given photo exactly like a
    // gallery pick (same history/params reset path).
    final initial = widget.initialImagePath;
    if (initial != null) {
      unawaited(_loadInitial(initial));
    }
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _statusTimer?.cancel();
    _textCtrl.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  // v1.3.0 (§5B): the status shows as a transient overlay chip on
  // the preview (auto-hides), never as a permanent line.
  bool _statusVisible = false;
  Timer? _statusTimer;
  // §8: this session's AI-tools coin unlock (charged once).
  bool _aiCoinsPaid = false;

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

  /// P15: failures must be SEEN — every user-action failure also
  /// raises a SnackBar. The status string is still set.
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

  bool get _curveIsNeutral => _curvePoints.values.every(
        (pts) =>
            pts.length == 2 &&
            pts.first == const Offset(0, 0) &&
            pts.last == const Offset(1, 1),
      );

  /// Build the four 256-entry curve LUTs ([rgb, r, g, b]) from the
  /// editor's control points (sorted by x, linear interpolation,
  /// endpoints pinned) — the exact tables applyToneCurve consumes.
  List<List<int>> _buildCurveLuts() {
    List<int> lutFor(String ch) {
      final pts = [..._curvePoints[ch]!]
        ..sort((a, b) => a.dx.compareTo(b.dx));
      final lut = List<int>.filled(256, 0);
      for (var i = 0; i < 256; i++) {
        final x = i / 255;
        var y = pts.last.dy;
        if (x <= pts.first.dx) {
          y = pts.first.dy;
        } else {
          for (var k = 0; k < pts.length - 1; k++) {
            final a = pts[k];
            final b = pts[k + 1];
            if (x >= a.dx && x <= b.dx) {
              final span = b.dx - a.dx;
              final t = span <= 0 ? 0.0 : (x - a.dx) / span;
              y = a.dy + (b.dy - a.dy) * t;
              break;
            }
          }
        }
        lut[i] = (y.clamp(0.0, 1.0) * 255).round();
      }
      return lut;
    }

    return [lutFor('rgb'), lutFor('r'), lutFor('g'), lutFor('b')];
  }

  /// True when the preview needs the per-pixel pass (LUT, HSL,
  /// non-linear Adjust, curve/hue/grain, or a classic Effect
  /// preview) — the ColorFilter matrix alone cannot express those.
  bool get _needsPixelPreview =>
      _selectedLut.isNotEmpty ||
      !_hslIsNeutral ||
      _highlights != 0 ||
      _shadows != 0 ||
      _vignette != 0 ||
      _sharpenDetail != 0 ||
      !_curveIsNeutral ||
      _hueShift != 0 ||
      _grain != 0 ||
      _effectSel != null;

  /// Debounced pixel-preview refresh (250 ms). Builds a downscaled
  /// (max 720 px wide) copy with matrix + LUT + pixel Adjust + HSL
  /// + curve/hue/grain + the selected classic Effect baked in, so
  /// every one of those controls previews LIVE.
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
      if (!_curveIsNeutral) {
        image = await applyToneCurve(image, _buildCurveLuts());
      }
      if (_hueShift != 0) {
        image = await adjustHSL(
          image,
          List.generate(8, (_) => [_hueShift, 1.0, 0.0]),
        );
      }
      if (_grain != 0) {
        image = await applyGrain(image, _grain);
      }
      if (_effectSel != null) {
        image = await applyClassicEffect(
          image,
          _effectSel!,
          intensity: _effectValue / 100,
        );
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

  /// Load the 5 bundled .cube LUTs once and parse them for the
  /// photo pipeline. Failures leave the LUT row empty, never crash.
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

  /// Filter/LUT thumbnails: each look rendered onto a downscaled
  /// copy of the CURRENT photo (cached per working file).
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
    _filterCategory = 'Feature';
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
    _hueShift = 0;
    _grain = 0;
    _curvePoints.updateAll(
      (_, _) => [const Offset(0, 0), const Offset(1, 1)],
    );
    _straighten = 0;
    _cropPreset = 'free';
    _hslAdjustments = List.generate(8, (_) => [0.0, 1.0, 0.0]);
    _hslSelectedColor = 0;
    _effectSel = null;
    _previewBytes = null;
    _previewKey = null;
  }

  Future<void> _loadInitial(String path) async {
    final f = File(path);
    if (await f.exists()) {
      _adoptPickedFile(f);
    }
  }

  Future<void> _pick() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    _adoptPickedFile(File(picked.path));
  }

  /// The one path every new photo enters through (gallery pick AND
  /// the Projects hub's initialImagePath): history restarts from
  /// the photo and every edit control resets.
  void _adoptPickedFile(File f) {
    setState(() {
      _workingFile = f;
      _originalFile = f;
      _history
        ..clear()
        ..add(f);
      _historyIndex = 0;
      _resetEditParams();
      _layers.clear();
      _activeLayer = -1;
      _overlays.clear();
      _activeOverlay = -1;
      _strokes.clear();
      _hasTransparency = false;
      _thumbKey = null;
      _filterThumbs = {};
      _lutThumbs = {};
      _status = 'Photo loaded.';
    });
    _buildFilterThumbs();
    unawaited(_updateImageSize());
  }

  Future<void> _updateImageSize() async {
    final file = _workingFile;
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      final size = await compute(_decodeSizeOf, bytes);
      if (!mounted || _workingFile?.path != file.path) return;
      setState(() {
        _imgWidth = size[0];
        _imgHeight = size[1];
      });
    } catch (_) {
      // Geometry falls back to container-relative positioning.
    }
  }

  /// The single choke point for changing the working photo: pushes
  /// the new state onto the undo history (max 10 states kept) and
  /// refreshes the per-photo caches.
  void _setWorkingFile(File f) {
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
    unawaited(_updateImageSize());
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
    unawaited(_updateImageSize());
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
    unawaited(_updateImageSize());
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
      _layers.clear();
      _activeLayer = -1;
      _overlays.clear();
      _activeOverlay = -1;
      _hasTransparency = false;
      _thumbKey = null;
      _filterThumbs = {};
      _lutThumbs = {};
      _status = 'Reset — original photo restored.';
    });
    _buildFilterThumbs();
    unawaited(_updateImageSize());
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

  /// The full preset list handed to the system cropper (P10).
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
      final cropped = await ImageCropper().cropImage(
        sourcePath: file.path,
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

  /// One-tap centre crop to an exact ratio (9:16, 1:1, 16:9, 4:5,
  /// 3:4). Goes through the history stack, so it is undoable.
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

  Future<void> _flipHorizontal() async {
    await _runEnhance('Flipping', () async {
      final image = await _decodeWorking();
      await _replaceWorking(flipHorizontalPhoto(image));
    });
  }

  Future<void> _flipVertical() async {
    await _runEnhance('Flipping', () async {
      final image = await _decodeWorking();
      await _replaceWorking(flipVerticalPhoto(image));
    });
  }

  /// Bake the straighten slider's angle into the photo, then
  /// re-centre the slider so a second Apply starts from "level".
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
      final rotated = img.copyRotate(image, angle: quarterTurns * 90);
      await _replaceWorking(rotated);
      _setStatus('Rotated.');
    } catch (e) {
      _fail('Rotate failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  /// Runs an AI job; returns true on success. AI tools are Premium:
  /// v1.3.0 (§8) the unlock is COINS ONLY — the first AI use in a
  /// session charges CoinFeature.aiEnhance (50 coins) after a
  /// confirm dialog; admins are waived by CoinService itself.
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
            ? 'AI tools unlock ho gaye.'
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

  /// Runs a FREE enhance job (no coin gate). Shows busy state.
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

  /// Download a model pack with a progress dialog (the pack is
  /// never bundled — ModelPackService owns the download). Returns
  /// the ensurePack result; false = the caller shows a plain error
  /// and the user can simply try again (never a dead end).
  Future<bool> _ensurePackWithDialog(String packId) async {
    final progress = ValueNotifier<double>(0);
    final future = ModelPackService.instance.ensurePack(
      packId,
      onProgress: (v) => progress.value = v,
    );
    if (!mounted) return future;
    unawaited(future.whenComplete(() {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }));
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('AI pack download ho raha hai'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: v > 0 ? v : null),
              const SizedBox(height: 10),
              Text('${(v * 100).round()}% — pehli dafa hi download '
                  'hota hai, phir offline chalta hai.'),
            ],
          ),
        ),
      ),
    );
    try {
      return await future;
    } catch (_) {
      return false;
    }
  }

  /// Run an ONNX image op: ensure its pack first (progress dialog
  /// when missing), then run the service on the decoded photo and
  /// push the result through the undo history.
  Future<bool> _runOnnx(
    String label,
    String packId,
    Future<img.Image?> Function(img.Image image) run,
  ) async {
    if (_workingFile == null || _busy) return false;
    bool ready;
    try {
      ready = await ModelPackService.instance.isReady(packId);
    } catch (_) {
      ready = false;
    }
    if (!ready) {
      final ok = await _ensurePackWithDialog(packId);
      if (!ok) {
        // v1.5.0 (#27): the TRUE typed reason — a hosting/size
        // problem is never misreported as the user's internet.
        _fail(ModelPackService.describeFailure(
            ModelPackService.instance.lastFailure));
        return false;
      }
    }
    return _runEnhance(label, () async {
      final image = await _decodeWorking();
      final out = await run(image);
      if (out == null) {
        throw Exception('AI model se result nahi mila.');
      }
      await _replaceWorking(out);
    });
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

  /// HQ Cutout (v1.4.0): BiRefNet fp16 matte via ONNX — a sharper
  /// edge than ML Kit segmentation, which stays the default.
  Future<void> _hqCutout() async {
    final ok = await _runOnnx('HQ Cutout', 'birefnet_fp16', (image) async {
      final matte = await OnnxImageService.instance.alphaMatte(
        'birefnet_fp16',
        image,
      );
      if (matte == null) return null;
      return applyAlphaMatte(image, matte);
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

  /// Replace Background with the picked solid colour (AI). Subject
  /// kept, everything else becomes the colour. Result is opaque.
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

  /// Replace Background with a gallery image (AI).
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

  /// Background tool, free path: flatten an existing transparent
  /// cutout onto a solid colour (no segmentation needed).
  Future<void> _flattenOnColor() async {
    final ok = await _runEnhance('Applying colour background', () async {
      final image = await _decodeWorking();
      await _replaceWorking(
        flattenOnColor(image, _replaceBgColor.toARGB32()),
      );
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

  /// Portrait > Light fix: the same algorithmic auto-levels as
  /// Auto-enhance, offered free inside the Portrait panel.
  Future<void> _lightFix() async {
    await _runEnhance('Fixing light', () async {
      final image = await _decodeWorking();
      final out = await autoEnhance(image);
      await _replaceWorking(out);
    });
  }

  /// Portrait > Bokeh (v1.4.0): Depth Anything V2 Small depth-
  /// guided background blur via ONNX.
  Future<void> _portraitBokeh() async {
    await _runOnnx('Applying bokeh', 'depth_v2_small', (image) {
      return OnnxImageService.instance.depthBokeh(image);
    });
  }

  Future<void> _sharpen() async {
    final amount = _sharpenAmount / 100;
    await _runEnhance('Sharpening', () async {
      final image = await _decodeWorking();
      final out = await sharpenImage(image, amount: amount);
      await _replaceWorking(out);
    });
  }

  Future<void> _denoise() async {
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

  /// Enhance > AI Enhance HD (v1.4.0): Real-ESRGAN via ONNX.
  /// Test verdict: it is a PHOTO enhancer — text in the image can
  /// distort, so the user is warned before it runs.
  Future<void> _aiEnhanceHd() async {
    if (_workingFile == null || _busy) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI Enhance HD'),
        content: const Text(
          'Ye enhancer photos ke liye hai — photo mein maujood '
          'TEXT distort ho sakta hai. Continue karein?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enhance HD'),
          ),
        ],
      ),
    );
    if (go != true) return;
    await _runOnnx('AI Enhance HD', 'esrgan', (image) {
      return OnnxImageService.instance.enhanceEsrgan(image);
    });
  }

  /// InShot-style HSL apply. After a successful Apply the sliders
  /// return to neutral, so a second Apply can never silently
  /// double-apply the same shift (P7).
  Future<void> _applyHSL() async {
    final ok = await _runEnhance('Applying HSL', () async {
      final image = await _decodeWorking();
      final out = await adjustHSL(image, _hslAdjustments);
      await _replaceWorking(out);
    });
    if (ok) _resetHSL();
  }

  void _resetHSL() {
    setState(() {
      _hslAdjustments = List.generate(8, (_) => [0.0, 1.0, 0.0]);
      _hslSelectedColor = 0;
    });
    _schedulePixelPreview();
  }

  /// Effect > Apply: bake the previewed classic effect at full
  /// resolution, then clear the preview-only selection.
  Future<void> _applyEffect() async {
    final effect = _effectSel;
    if (effect == null) return;
    final value = _effectValue / 100;
    final ok = await _runEnhance('Applying effect', () async {
      final image = await _decodeWorking();
      final out = await applyClassicEffect(
        image,
        effect,
        intensity: value,
      );
      await _replaceWorking(out);
    });
    if (ok) {
      setState(() => _effectSel = null);
      _closePanel();
    }
  }

  /// Effect > Artistic Styles (v1.4.0): fast-neural-style ONNX
  /// packs — Udnie / Mosaic / Rain Princess. (Candy is banned —
  /// eye artifact, per the tool-test verdict.)
  Future<void> _applyArtisticStyle(String packId, String label) async {
    await _runOnnx(label, packId, (image) {
      return OnnxImageService.instance.artisticStyle(packId, image);
    });
  }

  /// Canvas > Apply: extend the canvas to the chosen ratio with a
  /// blurred cover fill; the zoom slider scales the photo inside.
  Future<void> _applyCanvas() async {
    final ratio = _canvasRatio;
    if (ratio.$2 == 0) return;
    final zoom = _canvasZoom / 100;
    await _runEnhance('Applying canvas', () async {
      final image = await _decodeWorking();
      await _replaceWorking(
        expandCanvas(image, ratio.$2, ratio.$3, scale: zoom),
      );
    });
  }

  /// Expand > Apply: canvas-extend with the chosen edge fill. This
  /// is blur/mirror compositing, NOT AI outpainting — the panel
  /// says so, honestly.
  Future<void> _applyExpand() async {
    final ratio = _expandRatio;
    final fill = _expandFill;
    await _runEnhance('Extending canvas', () async {
      final image = await _decodeWorking();
      await _replaceWorking(
        expandCanvas(image, ratio.$2, ratio.$3, fill: fill),
      );
    });
  }

  /// Frame > Apply: solid border at the chosen width/colour.
  Future<void> _applyFrame() async {
    await _runEnhance('Adding frame', () async {
      final image = await _decodeWorking();
      final widthPx =
          math.max(2, (image.width * _frameWidthPct / 100).round());
      await _replaceWorking(
        addBorder(image, widthPx, _frameColor.toARGB32()),
      );
    });
  }

  /// Cutout > Eraser Apply: bake the painted alpha-erase strokes.
  Future<void> _applyEraser() async {
    if (_strokes.isEmpty) return;
    final strokes = List<StrokePath>.from(_strokes);
    final ok = await _runEnhance('Erasing', () async {
      final image = await _decodeWorking();
      await _replaceWorking(applyAlphaErase(image, strokes));
    });
    if (ok) {
      setState(() {
        _hasTransparency = true;
        _strokes.clear();
        _paintMode = null;
      });
    }
  }

  /// Cutout > Outline Apply: stroke around the subject's alpha
  /// edge (needs a cutout first).
  Future<void> _applyOutline() async {
    if (!_hasTransparency) {
      _fail('Pehle Cutout karein — outline transparent edge par '
          'lagta hai.');
      return;
    }
    await _runEnhance('Adding outline', () async {
      final image = await _decodeWorking();
      final widthPx =
          math.max(2, (image.width * _outlineWidth / 1000).round());
      await _replaceWorking(
        await outlineFromAlpha(
          image,
          widthPx: widthPx,
          argb: _outlineColor.toARGB32(),
        ),
      );
    });
  }

  /// Remove > Remove object: build the Mi-GAN mask from the
  /// painted strokes (WHITE = remove; the service flips to the
  /// model's convention) and inpaint via ONNX.
  Future<void> _applyRemove() async {
    if (_strokes.isEmpty) {
      _fail('Pehle object par brush se paint karein.');
      return;
    }
    final strokes = List<StrokePath>.from(_strokes);
    final ok = await _runOnnx('Removing object', 'migan', (image) async {
      final mask = maskFromStrokes(image.width, image.height, strokes);
      return OnnxImageService.instance.removeWithMigan(image, mask);
    });
    if (ok) {
      setState(() {
        _strokes.clear();
        _paintMode = null;
      });
    }
  }

  /// Doodle > Apply: bake the freehand strokes into the photo.
  Future<void> _applyDoodle() async {
    if (_strokes.isEmpty) return;
    final strokes = List<StrokePath>.from(_strokes);
    final ok = await _runEnhance('Applying doodle', () async {
      final image = await _decodeWorking();
      await _replaceWorking(drawDoodle(image, strokes));
    });
    if (ok) {
      setState(() {
        _strokes.clear();
        _paintMode = null;
      });
    }
  }

  /// Makeup > Apply. HONEST IMPLEMENTATION NOTE: the ML Kit face
  /// detector configured in AiService returns face BOUNDS, not
  /// landmarks — so the lip/cheek tint regions are oval
  /// approximations derived from the face box (lips ≈ lower-centre
  /// of the box, cheeks ≈ two ovals at mid-height), feather-blended
  /// by the pipeline's tintEllipses. Good enough for a tint, not a
  /// precision lipstick mask.
  Future<void> _applyMakeup() async {
    final file = _workingFile;
    if (file == null || _busy) return;
    await _runEnhance('Applying makeup', () async {
      final faces = await AiService.detectFaces(file);
      if (faces.isEmpty) {
        throw Exception('No face found in this photo.');
      }
      final image = await _decodeWorking();
      final w = image.width.toDouble();
      final h = image.height.toDouble();
      final ellipses = <List<double>>[];
      for (final r in faces) {
        if (_makeupMode == 'lips') {
          ellipses.add([
            (r.left + r.width / 2) / w,
            (r.top + r.height * 0.76) / h,
            (r.width * 0.17) / w,
            (r.height * 0.055) / h,
          ]);
        } else {
          ellipses.add([
            (r.left + r.width * 0.24) / w,
            (r.top + r.height * 0.56) / h,
            (r.width * 0.14) / w,
            (r.height * 0.10) / h,
          ]);
          ellipses.add([
            (r.left + r.width * 0.76) / w,
            (r.top + r.height * 0.56) / h,
            (r.width * 0.14) / w,
            (r.height * 0.10) / h,
          ]);
        }
      }
      final out = await tintEllipses(
        image,
        ellipses,
        argb: _makeupColor.toARGB32(),
        strength: (_makeupIntensity / 100) * 0.85,
      );
      await _replaceWorking(out);
    });
  }

  /// PIP > Add overlay: gallery photo becomes a draggable overlay
  /// layer (composited at export through the pipeline).
  Future<void> _addPipOverlay() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() {
      _overlays.add(_OverlayData(path: picked.path));
      _activeOverlay = _overlays.length - 1;
    });
  }

  /// Sticker tap: a glyph overlay layer at the photo centre.
  void _addSticker(String glyph) {
    setState(() {
      _overlays.add(_OverlayData(glyph: glyph));
      _activeOverlay = _overlays.length - 1;
    });
    _setStatus('Sticker lag gaya — preview par drag karein.');
  }

  Future<void> _export() async {
    final file = _workingFile;
    if (file == null || _busy) return;
    _saveActiveLayer();
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
        hueShift: _hueShift,
        grain: _grain,
        curveLuts: _curveIsNeutral ? null : _buildCurveLuts(),
      );
      // Overlays: photos go as files; sticker glyphs are rasterized
      // here (main isolate) and go as PNG bytes.
      final overlayParams = <PhotoOverlayLayerParams>[];
      for (final o in _overlays) {
        if (o.glyph != null) {
          final png = await rasterizeText(
            text: o.glyph!,
            argb: 0xFFFFFFFF,
            size: 220,
            shadow: false,
            bold: false,
          );
          overlayParams.add(PhotoOverlayLayerParams(
            pngBytes: png,
            centerX: o.center.dx,
            centerY: o.center.dy,
            scaleFrac: o.scaleFrac,
            rotationDegrees: o.rotation,
          ));
        } else if (o.path != null) {
          overlayParams.add(PhotoOverlayLayerParams(
            imagePath: o.path,
            centerX: o.center.dx,
            centerY: o.center.dy,
            scaleFrac: o.scaleFrac,
            rotationDegrees: o.rotation,
          ));
        }
      }
      final layerParams = _layers
          .where((l) => l.text.trim().isNotEmpty)
          .map(
            (l) => PhotoTextLayerParams(
              text: l.text,
              argb: l.colorArgb,
              size: l.size,
              centerX: l.offset.dx,
              centerY: l.offset.dy,
              boxWidthFrac: l.boxWidth,
              rotationDegrees: l.rotation,
              shadow: l.shadow,
              shadowArgb: l.shadowArgb,
              shadowDx: l.shadowDx,
              shadowDy: l.shadowDy,
              shadowBlur: l.shadowBlur,
              glow: l.glow,
              glowArgb: l.glowArgb,
              glowBlur: l.glowBlur,
              bg: l.bg,
              bgArgb: l.bgArgb,
              lineHeight: l.lineSpacing,
              fontKey: l.font,
              bold: l.bold,
              italic: l.italic,
              opacity: l.opacity,
              letterSpacing: l.letterSpacing,
              outline: l.outline,
              outlineArgb: l.outlineArgb,
              outlineWidth: l.outlineWidth,
              textAlign: l.alignIndex == 0
                  ? TextAlign.left
                  : l.alignIndex == 2
                      ? TextAlign.right
                      : TextAlign.center,
            ),
          )
          .toList();
      final outFile = await exportPhotoWithLayers(
        workingFile: file,
        params: params,
        layers: layerParams,
        overlays: overlayParams,
        outPath: outPath,
        keepAlpha: _hasTransparency,
      );
      await Gal.putImage(outFile.path);
      _setStatus('Saved to gallery: ${p.basename(outFile.path)}');
      if (mounted) {
        // Existing export flow + the share sheet (requirements #2):
        // WhatsApp / Instagram / Facebook targets ride the system
        // share sheet via share_plus.
        unawaited(_showShareSheet(outFile.path));
      }
    } catch (e) {
      _fail('Export failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _showShareSheet(String path) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              leading: Icon(Icons.check_circle, color: Colors.green),
              title: Text('Photo saved to gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share…'),
              subtitle: const Text(
                'WhatsApp, Instagram, Facebook — jahan bhejna ho',
              ),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await SharePlus.instance.share(
                    ShareParams(files: [XFile(path)]),
                  );
                } catch (e) {
                  _fail('Share nahi hua: $e');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.done),
              title: const Text('Done'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Text system: layer save/load + font/style application.
  // ------------------------------------------------------------------

  int get _shadowArgbEffective =>
      (_textShadowColor.toARGB32() & 0x00FFFFFF) |
      ((_shadowOpacity.clamp(0.0, 1.0) * 255).round() << 24);

  /// Write the editing fields into the active layer.
  void _saveActiveLayer() {
    if (_activeLayer < 0 || _activeLayer >= _layers.length) return;
    final l = _layers[_activeLayer];
    l.text = _text;
    l.colorArgb = _textColor.toARGB32();
    l.size = _textSize;
    l.offset = _textOffset;
    l.boxWidth = _textBoxWidth;
    l.rotation = _textRotation;
    l.font = _textFont;
    l.bold = _textBold;
    l.italic = _textItalic;
    l.opacity = _textOpacity;
    l.letterSpacing = _textLetterSpacing;
    l.lineSpacing = _textLineSpacing;
    l.alignIndex = _textAlign == TextAlign.left
        ? 0
        : _textAlign == TextAlign.right
            ? 2
            : 1;
    l.shadow = _textShadow;
    l.shadowArgb = _shadowArgbEffective;
    l.shadowDx = _shadowDx;
    l.shadowDy = _shadowDy;
    l.shadowBlur = _shadowBlur;
    l.glow = _textGlow;
    l.glowArgb = _textGlowColor.toARGB32();
    l.glowBlur = _glowBlur;
    l.outline = _textOutline;
    l.outlineArgb = _textOutlineColor.toARGB32();
    l.outlineWidth = _textOutlineWidth;
    l.bg = _textBg;
    l.bgArgb = _textBgColor.toARGB32();
  }

  /// Load a layer into the editing fields (typing bar included).
  void _loadLayer(int index) {
    if (index < 0 || index >= _layers.length) return;
    final l = _layers[index];
    _activeLayer = index;
    _text = l.text;
    _textCtrl.text = l.text;
    _textColor = Color(l.colorArgb);
    _textSize = l.size;
    _textOffset = l.offset;
    _textBoxWidth = l.boxWidth;
    _textRotation = l.rotation;
    _textFont = l.font;
    _textBold = l.bold;
    _textItalic = l.italic;
    _textOpacity = l.opacity;
    _textLetterSpacing = l.letterSpacing;
    _textLineSpacing = l.lineSpacing;
    _textAlign = l.alignIndex == 0
        ? TextAlign.left
        : l.alignIndex == 2
            ? TextAlign.right
            : TextAlign.center;
    _textShadow = l.shadow;
    _textShadowColor = Color(l.shadowArgb & 0x00FFFFFF | 0xFF000000);
    _shadowOpacity = ((l.shadowArgb >> 24) & 0xFF) / 255;
    _shadowDx = l.shadowDx;
    _shadowDy = l.shadowDy;
    _shadowBlur = l.shadowBlur;
    _textGlow = l.glow;
    _textGlowColor = Color(l.glowArgb);
    _glowBlur = l.glowBlur;
    _textOutline = l.outline;
    _textOutlineColor = Color(l.outlineArgb);
    _textOutlineWidth = l.outlineWidth;
    _textBg = l.bg;
    _textBgColor = Color(l.bgArgb);
  }

  void _addTextLayer() {
    _saveActiveLayer();
    setState(() {
      _layers.add(_TextLayerData());
      _loadLayer(_layers.length - 1);
      _textTab = 'type';
    });
    _textFocus.requestFocus();
  }

  void _deleteActiveLayer() {
    if (_activeLayer < 0) return;
    setState(() {
      _layers.removeAt(_activeLayer);
      if (_layers.isEmpty) {
        _activeLayer = -1;
        _text = '';
        _textCtrl.clear();
      } else {
        _loadLayer(math.min(_activeLayer, _layers.length - 1));
      }
    });
  }

  void _duplicateActiveLayer() {
    _saveActiveLayer();
    if (_activeLayer < 0) return;
    setState(() {
      final c = _layers[_activeLayer].clone();
      c.offset = Offset(
        (c.offset.dx + 0.05).clamp(0.1, 0.9),
        (c.offset.dy + 0.05).clamp(0.1, 0.95),
      );
      _layers.add(c);
      _loadLayer(_layers.length - 1);
    });
  }

  /// Apply a font key to a base style: font_registry entries render
  /// through their own apply(); the Latin/legacy keys go through
  /// google_fonts getters (the pre-v1.4.0 behaviour).
  TextStyle _applyFontKey(String key, TextStyle base) {
    if (UrduFonts.all.any((f) => f.id == key)) {
      return UrduFonts.byId(key).apply(base);
    }
    try {
      switch (key) {
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

  /// One-tap text style templates (daily upgrade 2026-10-31,
  /// preserved). Each sets the font/colour/weight/effect combo on
  /// the ACTIVE layer; the user can fine-tune afterwards.
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
          _textGlowColor = Colors.cyanAccent;
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
          _textFont = 'noto_nastaliq_urdu';
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
          _textGlowColor = Colors.pinkAccent;
          _textOutline = false;
          _textBg = false;
          _textLetterSpacing = 1.0;
          _textOpacity = 1.0;
      }
      _saveActiveLayer();
    });
  }

  /// Apply a StudioCaptionStyle (caption_styles.dart) to the
  /// active layer: colours, outline, shadow, label background and
  /// the style's registry font all map onto layer fields.
  void _applyStudioStyle(StudioCaptionStyle s, {bool label = false}) {
    setState(() {
      _textColor = Color(s.textColor);
      _textBold = s.bold;
      _textItalic = false;
      _textOutline = s.outline;
      _textOutlineColor = Colors.black;
      _textShadow = s.shadow;
      final bgArgb = s.backgroundColor != 0
          ? s.backgroundColor
          : (label ? s.highlightBg : 0);
      _textBg = bgArgb != 0;
      if (bgArgb != 0) _textBgColor = Color(bgArgb);
      _textGlow = false;
      if (s.fontId != null) _textFont = s.fontId!;
      _textSize = (s.fontSizePx * 2.2).clamp(20, 110);
      _saveActiveLayer();
    });
  }

  // ------------------------------------------------------------------
  // Shared UI helpers.
  // ------------------------------------------------------------------

  /// One bottom-toolbar item (icon + label). The open tool is
  /// highlighted; tapping it again closes its panel.
  Widget _toolItem(String key, String label, IconData icon) {
    final selected = _activePhotoTool == key;
    return InkWell(
      onTap: () {
        if (_workingFile == null) {
          unawaited(_pick());
          return;
        }
        if (selected) {
          _closePanel();
        } else {
          _openTool(key);
        }
      },
      child: Container(
        width: 64,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: selected ? _exportRed : Colors.white,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                color: selected ? _exportRed : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One icon+label choice item inside a panel — the global UI
  /// rule: every choice is an icon above a label in a horizontal
  /// swipeable row, never bare text.
  Widget _photoIconChoiceItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback? onTap,
    Color? iconColor,
    TextStyle? labelStyle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
            decoration: BoxDecoration(
              color: selected ? _accent : const Color(0xFF232323),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 21, color: iconColor ?? Colors.white),
                const SizedBox(height: 3),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle ??
                      const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _photoIconChoiceRail(List<Widget> items) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: items),
    );
  }

  /// Panel header: tool name + hold-to-compare chip + ✓ top-right
  /// to confirm/close (universal panel behaviour, requirements #2).
  /// v1.5.0 (#4): the compare chip moved here from its floating
  /// pill on the preview — same press-and-hold behaviour, no
  /// preview clutter.
  Widget _photoPanelHeader(String toolKey) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
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
          GestureDetector(
            onTapDown: (_) => setState(() => _comparing = true),
            onTapUp: (_) => setState(() => _comparing = false),
            onTapCancel: () => setState(() => _comparing = false),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _comparing ? _accent : Colors.white12,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.compare, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Compare (hold)',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Confirm',
            onPressed: _closePanel,
            icon: const Icon(Icons.check, color: _accentLight),
          ),
        ],
      ),
    );
  }

  String _photoToolDisplayName(String key) {
    const names = <String, String>{
      'canvas': 'Canvas',
      'filter': 'Filter',
      'adjust': 'Adjust',
      'effect': 'Effect',
      'background': 'Background',
      'portrait': 'Portrait',
      'sticker': 'Sticker',
      'text': 'Text',
      'pip': 'PIP',
      'remove': 'Remove',
      'enhance': 'Enhance',
      'cutout': 'Cutout',
      'doodle': 'Doodle',
      'makeup': 'Makeup',
      'crop': 'Crop',
      'expand': 'Expand',
      'frame': 'Frame',
      'rotate': 'Rotate',
    };
    return names[key] ?? key;
  }

  void _openTool(String key) {
    setState(() {
      _activePhotoTool = key;
      if (key == 'remove') {
        _paintMode = 'remove';
        _strokes.clear();
        _currentStroke = null;
      } else if (key == 'doodle') {
        _paintMode = 'doodle';
        _strokes.clear();
        _currentStroke = null;
      } else if (key != 'cutout') {
        _paintMode = null;
      }
      if (key == 'text') {
        if (_layers.isEmpty) {
          _layers.add(_TextLayerData());
          _loadLayer(0);
        } else if (_activeLayer < 0) {
          _loadLayer(_layers.length - 1);
        }
        _textTab = 'type';
      }
    });
    if (key == 'text' && !_textHintShown) {
      _textHintShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Text box ke dono taraf white dots drag karke width '
            'adjust karein — box ko drag karke kahin bhi le jayein.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  void _closePanel() {
    setState(() {
      _activePhotoTool = null;
      _paintMode = null;
      _currentStroke = null;
      // An un-applied classic Effect preview is discarded on close
      // (Apply is what bakes it) so preview == export again.
      _effectSel = null;
    });
    _schedulePixelPreview();
  }

  /// One AI action with its Premium badge ON the button (P3).
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

  Widget _plainAction({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }

  /// Colour swatch row bound to a colour value.
  Widget _swatchRow({
    required Color value,
    required ValueChanged<Color> onChanged,
    List<Color> colors = _palette,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: colors.map((c) {
          final selected = value.toARGB32() == c.toARGB32();
          return GestureDetector(
            onTap: () => onChanged(c),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? _accentLight : Colors.grey,
                  width: selected ? 3 : 1,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// One filter/LUT thumbnail tile: the look rendered on the
  /// user's own photo, with a violet selected ring.
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

  /// Single H/S/L slider row for the HSL editor.
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

  // ------------------------------------------------------------------
  // Tool panels.
  // ------------------------------------------------------------------

  static const _ratioTiles = <(String, int, int)>[
    ('Original', 0, 0),
    ('1:1', 1, 1),
    ('4:5', 4, 5),
    ('9:16', 9, 16),
    ('16:9', 16, 9),
    ('Wallpaper', 9, 19),
    ('3:4', 3, 4),
    ('4:3', 4, 3),
    ('2:3', 2, 3),
    ('3:2', 3, 2),
    ('2.35:1', 47, 20),
    ('2:1', 2, 1),
    ('1:2', 1, 2),
  ];

  Widget _ratioRail({
    required (String, int, int) selected,
    required ValueChanged<(String, int, int)> onSelect,
    bool includeOriginal = true,
  }) {
    return _photoIconChoiceRail([
      for (final r in _ratioTiles)
        if (includeOriginal || r.$2 != 0)
          _photoIconChoiceItem(
            icon: r.$2 == 0
                ? Icons.crop_original
                : r.$2 > r.$3
                    ? Icons.crop_landscape
                    : r.$2 == r.$3
                        ? Icons.crop_square
                        : Icons.crop_portrait,
            label: r.$1,
            selected: selected.$1 == r.$1,
            onTap: () => onSelect(r),
          ),
    ]);
  }

  Widget _canvasPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ratio chunein — photo crop nahi hogi, canvas barh jayega '
          '(blur fill). Zoom se photo canvas ke andar chhoti/bari.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _ratioRail(
          selected: _canvasRatio,
          onSelect: (r) => setState(() => _canvasRatio = r),
        ),
        _SliderRow(
          label: 'Zoom',
          value: _canvasZoom,
          min: 40,
          max: 100,
          onChanged: (v) => setState(() => _canvasZoom = v),
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed:
                _busy || _canvasRatio.$2 == 0 ? null : _applyCanvas,
            icon: const Icon(Icons.check),
            label: const Text('Apply canvas'),
          ),
        ),
      ],
    );
  }

  Widget _filterPanel() {
    final catKeys = _filterCategories[_filterCategory]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category chips.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final cat in _filterCategories.keys)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: _filterCategory == cat,
                    onSelected: (_) =>
                        setState(() => _filterCategory = cat),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Thumbnail strip: every thumbnail is the ACTUAL current
        // photo with that look applied (ORIGINAL first = Normal).
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final key in catKeys)
                if (key.startsWith('f:'))
                  _lookThumb(
                    label: _filterLabels[PhotoFilter.values.firstWhere(
                      (f) => f.name == key.substring(2),
                    )]!,
                    selected: _selectedLut.isEmpty &&
                        _filter.name == key.substring(2),
                    thumb: _filterThumbs[PhotoFilter.values.firstWhere(
                      (f) => f.name == key.substring(2),
                    )],
                    onTap: () {
                      setState(() {
                        _filter = PhotoFilter.values.firstWhere(
                          (f) => f.name == key.substring(2),
                        );
                        _selectedLut = '';
                      });
                      _schedulePixelPreview();
                    },
                  )
                else
                  _lookThumb(
                    label: key.substring(4),
                    selected: _selectedLut == key.substring(4),
                    thumb: _lutThumbs[key.substring(4)],
                    onTap: () {
                      setState(() => _selectedLut = key.substring(4));
                      _schedulePixelPreview();
                    },
                  ),
            ],
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
      ],
    );
  }

  // ---- Adjust ----

  /// The InShot Adjust icon row: (key, label, icon). 'auto',
  /// 'curve' and 'hsl' open their own sub-editors instead of the
  /// shared slider.
  static const _adjControls = <(String, String, IconData)>[
    ('auto', 'Auto', Icons.auto_fix_high),
    ('lightness', 'Lightness', Icons.light_mode),
    // v1.5.0 (#3): Exposure lives in the icon row like every other
    // control — it used to ALSO render as an unconditional second
    // slider under the shared one (two sliders open at once).
    ('exposure', 'Exposure', Icons.exposure),
    ('contrast', 'Contrast', Icons.contrast),
    ('warmth', 'Warmth', Icons.thermostat),
    ('tint', 'Tint', Icons.format_color_fill),
    ('saturation', 'Saturation', Icons.water_drop),
    ('curve', 'Curve', Icons.show_chart),
    ('hsl', 'HSL', Icons.palette),
    ('fade', 'Fade', Icons.blur_on),
    ('highlight', 'Highlight', Icons.highlight),
    ('shadow', 'Shadow', Icons.dark_mode),
    ('color', 'Color', Icons.color_lens),
    ('hue', 'Hue', Icons.colorize),
    ('vignette', 'Vignette', Icons.vignette),
    ('sharpen', 'Sharpen', Icons.details),
    ('grain', 'Grain', Icons.grain),
  ];

  double _adjValue(String key) {
    switch (key) {
      case 'lightness':
        return _brightness;
      case 'exposure':
        return _exposure;
      case 'contrast':
        return (_contrast - 1) * 100;
      case 'warmth':
        return _temperature;
      case 'tint':
        return _tint;
      case 'saturation':
        return (_saturation - 1) * 100;
      case 'fade':
        return _fade;
      case 'highlight':
        return _highlights;
      case 'shadow':
        return _shadows;
      case 'color':
        return _vibrance;
      case 'hue':
        return _hueShift;
      case 'vignette':
        return _vignette;
      case 'sharpen':
        return _sharpenDetail;
      case 'grain':
        return _grain;
      default:
        return 0;
    }
  }

  void _adjSet(String key, double v) {
    switch (key) {
      case 'lightness':
        _brightness = v;
      case 'exposure':
        _exposure = v;
      case 'contrast':
        _contrast = 1 + v / 100;
      case 'warmth':
        _temperature = v;
      case 'tint':
        _tint = v;
      case 'saturation':
        _saturation = 1 + v / 100;
      case 'fade':
        _fade = v;
      case 'highlight':
        _highlights = v;
      case 'shadow':
        _shadows = v;
      case 'color':
        _vibrance = v;
      case 'hue':
        _hueShift = v;
      case 'vignette':
        _vignette = v;
      case 'sharpen':
        _sharpenDetail = v;
      case 'grain':
        _grain = v;
    }
    _schedulePixelPreview();
  }

  (double, double) _adjRange(String key) {
    switch (key) {
      case 'fade':
      case 'vignette':
      case 'sharpen':
      case 'grain':
        return (0, 100);
      case 'hue':
        return (-180, 180);
      default:
        return (-100, 100);
    }
  }

  Widget _adjustPanel() {
    final file = _workingFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // v1.5.0 (#2): the hint is Expanded + ellipsis — as a
            // bare Text + Spacer it overflowed the row and painted
            // the yellow/black stripe.
            const Expanded(
              child: Text(
                'Ek control chunein — neeche ek hi shared slider hai.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
                  _hueShift = 0;
                  _grain = 0;
                  _curvePoints.updateAll(
                    (_, _) => [const Offset(0, 0), const Offset(1, 1)],
                  );
                });
                _schedulePixelPreview();
              },
              child: const Text('Reset'),
            ),
          ],
        ),
        _photoIconChoiceRail([
          for (final c in _adjControls)
            _photoIconChoiceItem(
              icon: c.$3,
              label: c.$2,
              selected: _adjSel == c.$1,
              onTap: () {
                if (c.$1 == 'auto') {
                  unawaited(_autoEnhance());
                } else {
                  setState(() => _adjSel = c.$1);
                }
              },
            ),
        ]),
        const SizedBox(height: 6),
        if (_adjSel == 'curve')
          _curveEditor()
        else if (_adjSel == 'hsl')
          _hslEditor()
        else
          _SliderRow(
            label: _adjControls
                .firstWhere((c) => c.$1 == _adjSel)
                .$2,
            value: _adjValue(_adjSel),
            min: _adjRange(_adjSel).$1,
            max: _adjRange(_adjSel).$2,
            onChanged: (v) => setState(() => _adjSet(_adjSel, v)),
          ),
        if (file == null)
          const Text(
            'Pehle photo chunein.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
      ],
    );
  }

  /// Channel curve editor: tap/drag on the graph moves the nearest
  /// control point (or adds one); channels RGB / R / G / B.
  Widget _curveEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _photoIconChoiceRail([
          for (final ch in const [
            ('rgb', 'RGB', Icons.show_chart, Colors.white),
            ('r', 'Red', Icons.circle, Colors.red),
            ('g', 'Green', Icons.circle, Colors.green),
            ('b', 'Blue', Icons.circle, Colors.blue),
          ])
            _photoIconChoiceItem(
              icon: ch.$3,
              iconColor: ch.$4,
              label: ch.$2,
              selected: _curveChannel == ch.$1,
              onTap: () => setState(() => _curveChannel = ch.$1),
            ),
          _photoIconChoiceItem(
            icon: Icons.restart_alt,
            label: 'Reset',
            selected: false,
            onTap: () {
              setState(() {
                _curvePoints[_curveChannel] = [
                  const Offset(0, 0),
                  const Offset(1, 1),
                ];
              });
              _schedulePixelPreview();
            },
          ),
        ]),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (ctx, cons) {
            final side = math.min(cons.maxWidth, 190.0);
            return Center(
              child: GestureDetector(
                onPanStart: (d) => _curveTouch(d.localPosition, side),
                onPanUpdate: (d) => _curveTouch(d.localPosition, side),
                child: CustomPaint(
                  size: Size(side, side),
                  painter: _CurvePainter(
                    points: _curvePoints[_curveChannel]!,
                    channel: _curveChannel,
                  ),
                ),
              ),
            );
          },
        ),
        const Text(
          'Graph par drag karke curve banayein — preview live hai.',
          style: TextStyle(color: Colors.grey, fontSize: 11),
        ),
      ],
    );
  }

  void _curveTouch(Offset local, double side) {
    final nx = (local.dx / side).clamp(0.0, 1.0);
    final ny = (1 - local.dy / side).clamp(0.0, 1.0);
    setState(() {
      final pts = _curvePoints[_curveChannel]!;
      // Move the nearest interior point; endpoints only move in Y.
      var best = -1;
      var bestDist = 0.14;
      for (var i = 0; i < pts.length; i++) {
        final d = (pts[i] - Offset(nx, ny)).distance;
        if (d < bestDist) {
          bestDist = d;
          best = i;
        }
      }
      if (best < 0) {
        pts.add(Offset(nx, ny));
      } else if (best == 0) {
        pts[0] = Offset(0, ny);
      } else if (best == pts.length - 1) {
        pts[pts.length - 1] = Offset(1, ny);
      } else {
        pts[best] = Offset(nx, ny);
      }
      pts.sort((a, b) => a.dx.compareTo(b.dx));
    });
    _schedulePixelPreview();
  }

  /// The HSL editor (8 colours × H/S/L) — the pre-v1.4.0 panel,
  /// re-homed inside Adjust (and still fully live + Apply).
  Widget _hslEditor() {
    final file = _workingFile;
    const colorNames = <String>[
      'Red', 'Orange', 'Yellow', 'Green',
      'Cyan', 'Blue', 'Purple', 'Magenta',
    ];
    const colorDots = <Color>[
      Colors.red, Colors.orange, Colors.yellow, Colors.green,
      Colors.cyan, Colors.blue, Colors.purple, Colors.pink,
    ];
    final adj = _hslAdjustments[_hslSelectedColor];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('HSL', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(onPressed: _resetHSL, child: const Text('Reset')),
          ],
        ),
        _photoIconChoiceRail([
          for (var i = 0; i < 8; i++)
            _photoIconChoiceItem(
              icon: Icons.circle,
              iconColor: colorDots[i],
              label: colorNames[i],
              selected: _hslSelectedColor == i,
              onTap: () => setState(() => _hslSelectedColor = i),
            ),
        ]),
        _hslSlider(
          label: 'Hue',
          value: adj[0],
          min: -180,
          max: 180,
          onChanged: (v) {
            setState(() => _hslAdjustments[_hslSelectedColor][0] = v);
            _schedulePixelPreview();
          },
        ),
        _hslSlider(
          label: 'Saturation',
          value: adj[1],
          min: 0,
          max: 2,
          onChanged: (v) {
            setState(() => _hslAdjustments[_hslSelectedColor][1] = v);
            _schedulePixelPreview();
          },
        ),
        _hslSlider(
          label: 'Lightness',
          value: adj[2],
          min: -100,
          max: 100,
          onChanged: (v) {
            setState(() => _hslAdjustments[_hslSelectedColor][2] = v);
            _schedulePixelPreview();
          },
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: file == null || _busy ? null : _applyHSL,
            icon: const Icon(Icons.check),
            label: const Text('Apply HSL'),
          ),
        ),
      ],
    );
  }

  // ---- Effect ----

  static const _classicEffects = <(String, String, IconData)>[
    ('glitch', 'Glitch', Icons.bolt),
    ('rgb', 'RGB', Icons.looks),
    ('noise', 'Noise', Icons.grain),
    ('tv', 'TV', Icons.tv),
    ('ghost', 'Ghost', Icons.copy),
    ('strobe', 'Strobe', Icons.flash_on),
    ('tilt', 'Tilt', Icons.blur_linear),
    ('warp', 'Warp', Icons.waves),
  ];

  Widget _effectPanel() {
    final file = _workingFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Effect chunein — preview live hai, Apply par full '
          'quality bake hota hai.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _photoIconChoiceRail([
          _photoIconChoiceItem(
            icon: Icons.block,
            label: 'None',
            selected: _effectSel == null,
            onTap: () {
              setState(() => _effectSel = null);
              _schedulePixelPreview();
            },
          ),
          for (final e in _classicEffects)
            _photoIconChoiceItem(
              icon: e.$3,
              label: e.$2,
              selected: _effectSel == e.$1,
              onTap: () {
                setState(() => _effectSel = e.$1);
                _schedulePixelPreview();
              },
            ),
        ]),
        _SliderRow(
          label: 'Value',
          value: _effectValue,
          min: 0,
          max: 100,
          onChanged: (v) {
            setState(() => _effectValue = v);
            _schedulePixelPreview();
          },
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: file == null || _busy || _effectSel == null
                ? null
                : _applyEffect,
            icon: const Icon(Icons.check),
            label: const Text('Apply effect'),
          ),
        ),
        const Divider(height: 24),
        const Text(
          'Artistic Styles',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'ONNX painterly styles (pack download hota hai, phir '
          'offline).',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final s in const [
                ('fns_udnie', 'Udnie'),
                ('fns_mosaic', 'Mosaic'),
                ('fns_rain', 'Rain Princess'),
              ])
                _lookThumb(
                  label: s.$2,
                  selected: false,
                  thumb: _filterThumbs[PhotoFilter.normal],
                  onTap: () {
                    if (file != null && !_busy) {
                      unawaited(_applyArtisticStyle(s.$1, s.$2));
                    }
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---- Background ----

  Widget _backgroundPanel() {
    final file = _workingFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (AppConfig.aiToolsEnabled) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _aiAction(
                label: 'Blur background',
                icon: Icons.blur_on,
                onPressed: file == null || _busy ? null : _blurBackground,
              ),
              _aiAction(
                label: 'Replace with image',
                icon: Icons.image,
                onPressed:
                    file == null || _busy ? null : _replaceBackgroundImage,
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        const Text('Replace with colour',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        _swatchRow(
          value: _replaceBgColor,
          onChanged: (c) => setState(() => _replaceBgColor = c),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (AppConfig.aiToolsEnabled)
              _aiAction(
                label: 'Replace (subject)',
                icon: Icons.format_color_fill,
                onPressed:
                    file == null || _busy ? null : _replaceBackgroundColor,
              ),
            if (_hasTransparency)
              _plainAction(
                label: 'Flatten on colour',
                icon: Icons.layers,
                onPressed: file == null || _busy ? null : _flattenOnColor,
              ),
          ],
        ),
        if (!_hasTransparency && AppConfig.aiToolsEnabled)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Cutout ke baad "Flatten on colour" se transparent '
              'photo kisi bhi rang par rakhi ja sakti hai.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
      ],
    );
  }

  // ---- Portrait ----

  Widget _portraitPanel() {
    final file = _workingFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (AppConfig.aiToolsEnabled)
              _aiAction(
                label: 'AI Retouch',
                icon: Icons.face_retouching_natural,
                onPressed: file == null || _busy ? null : _beautify,
              ),
            _plainAction(
              label: 'Bokeh',
              icon: Icons.blur_circular,
              onPressed: file == null || _busy ? null : _portraitBokeh,
            ),
            _plainAction(
              label: 'Light fix',
              icon: Icons.light_mode,
              onPressed: file == null || _busy ? null : _lightFix,
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'AI Retouch = face smoothing (ML Kit). Bokeh = Depth '
          'Anything ONNX pack se depth-guided blur. Light fix = '
          'auto levels.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  // ---- Sticker / PIP overlays ----

  Widget _overlayControls() {
    if (_activeOverlay < 0 || _activeOverlay >= _overlays.length) {
      return const Text(
        'Overlay select karein — preview par drag karke position '
        'badlein.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      );
    }
    final o = _overlays[_activeOverlay];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SliderRow(
          label: 'Size',
          value: o.scaleFrac * 100,
          min: 8,
          max: 120,
          onChanged: (v) =>
              setState(() => o.scaleFrac = v / 100),
        ),
        _SliderRow(
          label: 'Rotate',
          value: o.rotation,
          min: -180,
          max: 180,
          onChanged: (v) => setState(() => o.rotation = v),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() {
              _overlays.removeAt(_activeOverlay);
              _activeOverlay = -1;
            }),
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            label: const Text('Delete overlay'),
          ),
        ),
      ],
    );
  }

  Widget _stickerPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final g in _stickerGlyphs)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _addSticker(g),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFF232323),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(g, style: const TextStyle(fontSize: 24)),
                  ),
                ),
              ),
          ],
        ),
        const Divider(height: 20),
        _overlayControls(),
      ],
    );
  }

  Widget _pipPanel() {
    final file = _workingFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: file == null || _busy ? null : _addPipOverlay,
            icon: const Icon(Icons.photo_library),
            label: const Text('Add photo overlay (gallery)'),
          ),
        ),
        const SizedBox(height: 8),
        _overlayControls(),
      ],
    );
  }

  // ---- Remove ----

  Widget _removePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Jo cheez hatani hai us par brush se paint karein — '
          'Mi-GAN (ONNX pack) gap bhar dega. Chhoti cheezon '
          '(wires, spots, date stamp) par sab se saaf result.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _SliderRow(
          label: 'Brush size',
          value: _brushSize * 100,
          min: 2,
          max: 25,
          onChanged: (v) => setState(() => _brushSize = v / 100),
        ),
        Row(
          children: [
            _photoIconChoiceItem(
              icon: Icons.brush,
              label: 'Brush',
              selected: !_maskErase,
              onTap: () => setState(() => _maskErase = false),
            ),
            _photoIconChoiceItem(
              icon: Icons.auto_fix_off,
              label: 'Eraser',
              selected: _maskErase,
              onTap: () => setState(() => _maskErase = true),
            ),
            _photoIconChoiceItem(
              icon: Icons.clear_all,
              label: 'Clear',
              selected: false,
              onTap: () => setState(() => _strokes.clear()),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _busy || _strokes.isEmpty ? null : _applyRemove,
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Remove object'),
          ),
        ),
      ],
    );
  }

  // ---- Enhance ----

  Widget _enhancePanel() {
    final file = _workingFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'One-tap photo improvements — on-device. AI Enhance HD '
          'ke ilawa sab FREE hain.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _plainAction(
              label: 'Sharpen',
              icon: Icons.blur_off,
              onPressed: file == null || _busy ? null : _sharpen,
            ),
            _plainAction(
              label: 'Denoise',
              icon: Icons.grain,
              onPressed: file == null || _busy ? null : _denoise,
            ),
            _plainAction(
              label: 'Enlarge 2x',
              icon: Icons.zoom_out_map,
              onPressed: file == null || _busy ? null : _enlarge,
            ),
            _plainAction(
              label: 'Color Fix',
              icon: Icons.color_lens,
              onPressed: file == null || _busy ? null : _colorFix,
            ),
            if (AppConfig.aiToolsEnabled)
              _aiAction(
                label: 'Auto-enhance',
                icon: Icons.auto_fix_high,
                onPressed: file == null || _busy ? null : _autoEnhance,
              ),
            _plainAction(
              label: 'AI Enhance HD',
              icon: Icons.high_quality,
              onPressed: file == null || _busy ? null : _aiEnhanceHd,
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Tip: Denoise pehle, phir Sharpen. AI Enhance HD '
          'Real-ESRGAN pack hai — photos ke liye best, text distort '
          'ho sakta hai.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  // ---- Cutout ----

  Widget _cutoutPanel() {
    final file = _workingFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (AppConfig.aiToolsEnabled)
              _aiAction(
                label: 'Cutout',
                icon: Icons.content_cut,
                onPressed:
                    file == null || _busy ? null : _removeBackground,
              ),
            _plainAction(
              label: 'HQ Cutout',
              icon: Icons.high_quality,
              onPressed: file == null || _busy ? null : _hqCutout,
            ),
            _photoIconChoiceItem(
              icon: Icons.auto_fix_off,
              label: 'Eraser',
              selected: _paintMode == 'erase',
              onTap: () => setState(() {
                _paintMode = _paintMode == 'erase' ? null : 'erase';
                _strokes.clear();
              }),
            ),
            _photoIconChoiceItem(
              icon: Icons.image,
              label: 'Replace BG',
              selected: false,
              onTap: () => _openTool('background'),
            ),
          ],
        ),
        if (_paintMode == 'erase') ...[
          _SliderRow(
            label: 'Eraser size',
            value: _brushSize * 100,
            min: 2,
            max: 25,
            onChanged: (v) => setState(() => _brushSize = v / 100),
          ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  _busy || _strokes.isEmpty ? null : _applyEraser,
              icon: const Icon(Icons.check),
              label: const Text('Apply eraser'),
            ),
          ),
        ],
        const Divider(height: 22),
        const Text('Outline',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        _swatchRow(
          value: _outlineColor,
          onChanged: (c) => setState(() => _outlineColor = c),
        ),
        _SliderRow(
          label: 'Width',
          value: _outlineWidth,
          min: 2,
          max: 30,
          onChanged: (v) => setState(() => _outlineWidth = v),
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: file == null || _busy ? null : _applyOutline,
            icon: const Icon(Icons.border_outer),
            label: const Text('Apply outline'),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Cutout = ML Kit (default). HQ Cutout = BiRefNet ONNX '
          'pack — kinare zyada saaf. Transparency preview mein '
          'checkerboard dikhta hai.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  // ---- Doodle ----

  Widget _doodlePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Preview par ungli se draw karein — Apply par photo mein '
          'bake ho jayega (Undo maujood hai).',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _swatchRow(
          value: _doodleColor,
          onChanged: (c) => setState(() => _doodleColor = c),
        ),
        _SliderRow(
          label: 'Brush size',
          value: _brushSize * 100,
          min: 1,
          max: 20,
          onChanged: (v) => setState(() => _brushSize = v / 100),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _strokes.clear()),
                icon: const Icon(Icons.clear_all),
                label: const Text('Clear'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed:
                    _busy || _strokes.isEmpty ? null : _applyDoodle,
                icon: const Icon(Icons.check),
                label: const Text('Apply doodle'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---- Makeup ----

  Widget _makeupPanel() {
    final file = _workingFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _photoIconChoiceRail([
          _photoIconChoiceItem(
            icon: Icons.circle,
            iconColor: const Color(0xFFD81B60),
            label: 'Lips',
            selected: _makeupMode == 'lips',
            onTap: () => setState(() {
              _makeupMode = 'lips';
              _makeupColor = const Color(0xFFD81B60);
            }),
          ),
          _photoIconChoiceItem(
            icon: Icons.face,
            iconColor: const Color(0xFFF48FB1),
            label: 'Blush',
            selected: _makeupMode == 'blush',
            onTap: () => setState(() {
              _makeupMode = 'blush';
              _makeupColor = const Color(0xFFF48FB1);
            }),
          ),
        ]),
        const SizedBox(height: 8),
        _swatchRow(
          value: _makeupColor,
          onChanged: (c) => setState(() => _makeupColor = c),
          colors: const [
            Color(0xFFD81B60),
            Color(0xFFC21807),
            Color(0xFFAD1457),
            Color(0xFFF48FB1),
            Color(0xFFFF8A65),
            Color(0xFF8E24AA),
            Color(0xFF6D4C41),
            Colors.white,
          ],
        ),
        _SliderRow(
          label: 'Intensity',
          value: _makeupIntensity,
          min: 0,
          max: 100,
          onChanged: (v) => setState(() => _makeupIntensity = v),
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: file == null || _busy ? null : _applyMakeup,
            icon: const Icon(Icons.check),
            label: const Text('Apply makeup'),
          ),
        ),
        const Text(
          'Face bounds se lips/cheeks ke oval regions par feathered '
          'tint lagta hai.',
          style: TextStyle(color: Colors.grey, fontSize: 11),
        ),
      ],
    );
  }

  // ---- Crop ----

  Widget _cropPanel() {
    final file = _workingFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        _photoIconChoiceRail([
          _photoIconChoiceItem(
            icon: Icons.crop_free,
            label: 'Free',
            selected: false,
            onTap: file == null || _busy
                ? null
                : () {
                    setState(() => _cropPreset = 'free');
                    unawaited(_crop());
                  },
          ),
          for (final e in const [
            ('9:16', 9, 16, Icons.crop_portrait),
            ('1:1', 1, 1, Icons.crop_square),
            ('16:9', 16, 9, Icons.crop_landscape),
            ('4:5', 4, 5, Icons.crop_portrait),
            ('3:4', 3, 4, Icons.crop_portrait),
          ])
            _photoIconChoiceItem(
              icon: e.$4,
              label: e.$1,
              selected: false,
              onTap: file == null || _busy
                  ? null
                  : () => _quickRatioCrop(e.$1, e.$2, e.$3),
            ),
        ]),
        const Divider(height: 22),
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
      ],
    );
  }

  // ---- Expand ----

  Widget _expandPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Canvas ko naye ratio tak barhayein — kinare blur ya '
          'mirror fill se bharte hain. Ye AI outpainting NAHI hai, '
          'saada compositing hai.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _ratioRail(
          selected: _expandRatio,
          includeOriginal: false,
          onSelect: (r) => setState(() => _expandRatio = r),
        ),
        const SizedBox(height: 6),
        _photoIconChoiceRail([
          _photoIconChoiceItem(
            icon: Icons.blur_on,
            label: 'Blur fill',
            selected: _expandFill == 'blur',
            onTap: () => setState(() => _expandFill = 'blur'),
          ),
          _photoIconChoiceItem(
            icon: Icons.flip,
            label: 'Mirror fill',
            selected: _expandFill == 'mirror',
            onTap: () => setState(() => _expandFill = 'mirror'),
          ),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _applyExpand,
            icon: const Icon(Icons.open_in_full),
            label: const Text('Expand canvas'),
          ),
        ),
      ],
    );
  }

  // ---- Frame ----

  Widget _framePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _swatchRow(
          value: _frameColor,
          onChanged: (c) => setState(() => _frameColor = c),
        ),
        _SliderRow(
          label: 'Width %',
          value: _frameWidthPct,
          min: 1,
          max: 15,
          onChanged: (v) => setState(() => _frameWidthPct = v),
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : _applyFrame,
            icon: const Icon(Icons.border_outer),
            label: const Text('Apply frame'),
          ),
        ),
      ],
    );
  }

  // ---- Rotate ----

  Widget _rotatePanel() {
    final file = _workingFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed:
                    file == null || _busy ? null : () => _rotate(3),
                icon: const Icon(Icons.rotate_left),
                label: const Text('Rotate left'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed:
                    file == null || _busy ? null : () => _rotate(1),
                icon: const Icon(Icons.rotate_right),
                label: const Text('Rotate right'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    file == null || _busy ? null : _flipHorizontal,
                icon: const Icon(Icons.flip),
                label: const Text('Flip horizontal'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: file == null || _busy ? null : _flipVertical,
                icon: const Icon(Icons.swap_vert),
                label: const Text('Flip vertical'),
              ),
            ),
          ],
        ),
        const Divider(height: 22),
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
      ],
    );
  }

  /// Panel switch — the open tool's controls.
  Widget _panelFor(String key) {
    switch (key) {
      case 'canvas':
        return _canvasPanel();
      case 'filter':
        return _filterPanel();
      case 'adjust':
        return _adjustPanel();
      case 'effect':
        return _effectPanel();
      case 'background':
        return _backgroundPanel();
      case 'portrait':
        return _portraitPanel();
      case 'sticker':
        return _stickerPanel();
      case 'pip':
        return _pipPanel();
      case 'remove':
        return _removePanel();
      case 'enhance':
        return _enhancePanel();
      case 'cutout':
        return _cutoutPanel();
      case 'doodle':
        return _doodlePanel();
      case 'makeup':
        return _makeupPanel();
      case 'crop':
        return _cropPanel();
      case 'expand':
        return _expandPanel();
      case 'frame':
        return _framePanel();
      case 'rotate':
        return _rotatePanel();
      default:
        return const SizedBox.shrink();
    }
  }

  // ------------------------------------------------------------------
  // Text editor zone (replaces the generic panel for the Text tool):
  // above-bar toolbar + typing bar / Style / Colour / Font panels.
  // ------------------------------------------------------------------

  String get _styleSample =>
      _text.isEmpty ? 'Nigraan TV' : (_text.length > 16 ? _text.substring(0, 16) : _text);

  Widget _textZone() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Above-bar toolbar: keyboard, STYLE, COLOUR, Aa FONT,
        // alignment, ✓ (requirements #2).
        Row(
          children: [
            IconButton(
              tooltip: 'Keyboard',
              onPressed: () {
                setState(() => _textTab = 'type');
                _textFocus.requestFocus();
              },
              icon: Icon(
                Icons.keyboard,
                color: _textTab == 'type' ? _accentLight : Colors.white,
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _textTab = 'style'),
              child: Text(
                'STYLE',
                style: TextStyle(
                  color: _textTab == 'style'
                      ? _accentLight
                      : Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Colour',
              onPressed: () => setState(() => _textTab = 'colour'),
              icon: Icon(
                Icons.color_lens,
                color:
                    _textTab == 'colour' ? _accentLight : Colors.white,
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _textTab = 'font'),
              child: Text(
                'Aa',
                style: TextStyle(
                  color: _textTab == 'font'
                      ? _accentLight
                      : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Alignment',
              onPressed: () {
                setState(() {
                  _textAlign = _textAlign == TextAlign.left
                      ? TextAlign.center
                      : _textAlign == TextAlign.center
                          ? TextAlign.right
                          : TextAlign.left;
                });
                _saveActiveLayer();
              },
              icon: Icon(
                _textAlign == TextAlign.left
                    ? Icons.format_align_left
                    : _textAlign == TextAlign.right
                        ? Icons.format_align_right
                        : Icons.format_align_center,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Confirm',
              onPressed: _closePanel,
              icon: const Icon(Icons.check, color: _accentLight),
            ),
          ],
        ),
        Expanded(
          child: switch (_textTab) {
            'style' => _textStylePanel(),
            'colour' => _textColourPanel(),
            'font' => _textFontPanel(),
            _ => _textTypePanel(),
          },
        ),
      ],
    );
  }

  Widget _textTypePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Layer chips: tap to select the layer being edited.
        if (_layers.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < _layers.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('Text ${i + 1}'),
                      selected: _activeLayer == i,
                      onSelected: (_) => setState(() {
                        _saveActiveLayer();
                        _loadLayer(i);
                      }),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        // Bottom typing bar — every letter updates the canvas LIVE.
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textCtrl,
                focusNode: _textFocus,
                decoration: const InputDecoration(
                  hintText: 'Yahan likhein — canvas par live ayega',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) {
                  setState(() => _text = v);
                  _saveActiveLayer();
                },
              ),
            ),
            IconButton(
              tooltip: 'Add text layer',
              onPressed: _addTextLayer,
              icon: const Icon(Icons.add_circle, color: _accentLight),
            ),
            IconButton(
              tooltip: 'Delete this text',
              onPressed: _activeLayer < 0 ? null : _deleteActiveLayer,
              icon: const Icon(Icons.delete, color: Colors.redAccent),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _SliderRow(
          label: 'Text size',
          value: _textSize,
          min: 20,
          max: 110,
          onChanged: (v) {
            setState(() => _textSize = v);
            _saveActiveLayer();
          },
        ),
        Row(
          children: [
            _photoIconChoiceItem(
              icon: Icons.format_bold,
              label: 'Bold',
              selected: _textBold,
              onTap: () {
                setState(() => _textBold = !_textBold);
                _saveActiveLayer();
              },
            ),
            _photoIconChoiceItem(
              icon: Icons.format_italic,
              label: 'Italic',
              selected: _textItalic,
              onTap: () {
                setState(() => _textItalic = !_textItalic);
                _saveActiveLayer();
              },
            ),
            _photoIconChoiceItem(
              icon: Icons.copy,
              label: 'Copy',
              selected: false,
              onTap: _activeLayer < 0 ? null : _duplicateActiveLayer,
            ),
          ],
        ),
        _SliderRow(
          label: 'Letter spacing',
          value: _textLetterSpacing,
          min: -2,
          max: 10,
          onChanged: (v) {
            setState(() => _textLetterSpacing = v);
            _saveActiveLayer();
          },
        ),
        _SliderRow(
          label: 'Line spacing',
          value: _textLineSpacing,
          min: 0.8,
          max: 2.0,
          onChanged: (v) {
            setState(() => _textLineSpacing = v);
            _saveActiveLayer();
          },
        ),
      ],
    );
  }

  Widget _styleTile({
    required String label,
    required Widget preview,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF232323),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            Expanded(child: Center(child: preview)),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _templatePreviewStyle(String key) {
    switch (key) {
      case 'neon':
        return _applyFontKey(
          'bebas',
          const TextStyle(
            color: Colors.cyanAccent,
            fontSize: 17,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.cyan, blurRadius: 12)],
          ),
        );
      case 'breaking':
        return _applyFontKey(
          'roboto',
          const TextStyle(
            color: Colors.yellow,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        );
      case 'elegant':
        return _applyFontKey(
          'merriweather',
          const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontStyle: FontStyle.italic,
          ),
        );
      case 'urdu':
        return _applyFontKey(
          'noto_nastaliq_urdu',
          const TextStyle(color: Color(0xFFFFD54F), fontSize: 15),
        );
      case 'script':
        return _applyFontKey(
          'dancing',
          const TextStyle(
            color: Colors.pinkAccent,
            fontSize: 17,
            shadows: [Shadow(color: Colors.pink, blurRadius: 10)],
          ),
        );
      default: // classic
        return const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        );
    }
  }

  Widget _textStylePanel() {
    final sample = _styleSample;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final t in const ['SPECIAL', 'CAPTIONS', 'LABEL', 'TITLE'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(t),
                    selected: _styleTab == t,
                    onSelected: (_) => setState(() => _styleTab = t),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.5,
            children: switch (_styleTab) {
              'CAPTIONS' => [
                  for (final s in StudioCaptionStyles.all)
                    _styleTile(
                      label: s.nameEn,
                      preview: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: s.backgroundColor != 0
                              ? Color(s.backgroundColor)
                              : null,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          sample,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: _applyFontKey(
                            s.fontId ?? 'default',
                            TextStyle(
                              color: Color(s.textColor),
                              fontSize: 13,
                              fontWeight: s.bold
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              shadows: s.shadow
                                  ? const [
                                      Shadow(
                                          color: Colors.black,
                                          blurRadius: 4)
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ),
                      onTap: () => _applyStudioStyle(s),
                    ),
                ],
              'LABEL' => [
                  for (final s in StudioCaptionStyles.all.where(
                    (s) => s.backgroundColor != 0 || s.highlightBg != 0,
                  ))
                    _styleTile(
                      label: s.nameEn,
                      preview: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Color(
                            s.backgroundColor != 0
                                ? s.backgroundColor
                                : s.highlightBg,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          sample,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      onTap: () => _applyStudioStyle(s, label: true),
                    ),
                  for (final v in const [
                    ('Message bubble', 0xFF37474F, 0xFFFFFFFF),
                    ('Sticky note', 0xFFFFF176, 0xFF000000),
                    ('Brush note', 0xFFFF7043, 0xFFFFFFFF),
                    ('Paper tape', 0xFFECEFF1, 0xFF000000),
                    ('Pixel bubble', 0xFF3D5AFE, 0xFFFFFFFF),
                  ])
                    _styleTile(
                      label: v.$1,
                      preview: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Color(v.$2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          sample,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(v.$3),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      onTap: () => setState(() {
                        _textBg = true;
                        _textBgColor = Color(v.$2);
                        _textColor = Color(v.$3);
                        _textBold = true;
                        _saveActiveLayer();
                      }),
                    ),
                ],
              'TITLE' => [
                  for (final s in StudioCaptionStyles.all.where(
                    (s) => const {
                      'bold_pop',
                      'one_word',
                      'spotlight',
                      'urdu_gulzar_headline',
                      'pop_up',
                    }.contains(s.id),
                  ))
                    _styleTile(
                      label: s.nameEn,
                      preview: Text(
                        sample,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: _applyFontKey(
                          s.fontId ?? 'default',
                          TextStyle(
                            color: Color(s.highlightColor),
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      onTap: () => _applyStudioStyle(s),
                    ),
                ],
              _ => [
                  for (final t in const [
                    ('classic', 'Classic'),
                    ('neon', 'Neon Lights'),
                    ('breaking', 'Breaking'),
                    ('elegant', 'Elegant'),
                    ('urdu', 'Urdu Gold'),
                    ('script', 'Script Glow'),
                  ])
                    _styleTile(
                      label: t.$2,
                      preview: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: t.$1 == 'breaking' ? Colors.red : null,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          sample,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: _templatePreviewStyle(t.$1),
                        ),
                      ),
                      onTap: () => _applyTextTemplate(t.$1),
                    ),
                ],
            },
          ),
        ),
      ],
    );
  }

  Widget _textColourPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final t in const [
                'TEXT', 'BORDER', 'SHADOW', 'GLOW', 'LABEL', 'OPACITY',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(t),
                    selected: _colourTab == t,
                    onSelected: (_) => setState(() => _colourTab = t),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: switch (_colourTab) {
              'BORDER' => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Outline'),
                        const Spacer(),
                        Switch(
                          value: _textOutline,
                          onChanged: (v) {
                            setState(() => _textOutline = v);
                            _saveActiveLayer();
                          },
                        ),
                      ],
                    ),
                    _swatchRow(
                      value: _textOutlineColor,
                      onChanged: (c) {
                        setState(() {
                          _textOutlineColor = c;
                          _textOutline = true;
                        });
                        _saveActiveLayer();
                      },
                    ),
                    _SliderRow(
                      label: 'Width',
                      value: _textOutlineWidth,
                      min: 1,
                      max: 8,
                      onChanged: (v) {
                        setState(() => _textOutlineWidth = v);
                        _saveActiveLayer();
                      },
                    ),
                  ],
                ),
              'SHADOW' => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Shadow'),
                        const Spacer(),
                        Switch(
                          value: _textShadow,
                          onChanged: (v) {
                            setState(() => _textShadow = v);
                            _saveActiveLayer();
                          },
                        ),
                      ],
                    ),
                    _swatchRow(
                      value: _textShadowColor,
                      onChanged: (c) {
                        setState(() {
                          _textShadowColor = c;
                          _textShadow = true;
                        });
                        _saveActiveLayer();
                      },
                    ),
                    _SliderRow(
                      label: 'X offset',
                      value: _shadowDx,
                      min: -20,
                      max: 20,
                      onChanged: (v) {
                        setState(() => _shadowDx = v);
                        _saveActiveLayer();
                      },
                    ),
                    _SliderRow(
                      label: 'Y offset',
                      value: _shadowDy,
                      min: -20,
                      max: 20,
                      onChanged: (v) {
                        setState(() => _shadowDy = v);
                        _saveActiveLayer();
                      },
                    ),
                    _SliderRow(
                      label: 'Blur',
                      value: _shadowBlur,
                      min: 0,
                      max: 30,
                      onChanged: (v) {
                        setState(() => _shadowBlur = v);
                        _saveActiveLayer();
                      },
                    ),
                    _SliderRow(
                      label: 'Opacity %',
                      value: _shadowOpacity * 100,
                      min: 0,
                      max: 100,
                      onChanged: (v) {
                        setState(() => _shadowOpacity = v / 100);
                        _saveActiveLayer();
                      },
                    ),
                  ],
                ),
              'GLOW' => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Glow'),
                        const Spacer(),
                        Switch(
                          value: _textGlow,
                          onChanged: (v) {
                            setState(() => _textGlow = v);
                            _saveActiveLayer();
                          },
                        ),
                      ],
                    ),
                    _swatchRow(
                      value: _textGlowColor,
                      onChanged: (c) {
                        setState(() {
                          _textGlowColor = c;
                          _textGlow = true;
                        });
                        _saveActiveLayer();
                      },
                    ),
                    _SliderRow(
                      label: 'Intensity',
                      value: _glowBlur,
                      min: 4,
                      max: 40,
                      onChanged: (v) {
                        setState(() => _glowBlur = v);
                        _saveActiveLayer();
                      },
                    ),
                  ],
                ),
              'LABEL' => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _photoIconChoiceRail([
                      _photoIconChoiceItem(
                        icon: Icons.block,
                        label: 'None',
                        selected: !_textBg,
                        onTap: () {
                          setState(() => _textBg = false);
                          _saveActiveLayer();
                        },
                      ),
                      _photoIconChoiceItem(
                        icon: Icons.bookmark,
                        label: 'Ribbon',
                        selected: _textBg,
                        onTap: () {
                          setState(() => _textBg = true);
                          _saveActiveLayer();
                        },
                      ),
                    ]),
                    const SizedBox(height: 8),
                    _swatchRow(
                      value: _textBgColor,
                      onChanged: (c) {
                        setState(() {
                          _textBgColor = c;
                          _textBg = true;
                        });
                        _saveActiveLayer();
                      },
                    ),
                  ],
                ),
              'OPACITY' => _SliderRow(
                  label: 'Opacity %',
                  value: _textOpacity * 100,
                  min: 0,
                  max: 100,
                  onChanged: (v) {
                    setState(() => _textOpacity = v / 100);
                    _saveActiveLayer();
                  },
                ),
              _ => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _swatchRow(
                      value: _textColor,
                      onChanged: (c) {
                        setState(() => _textColor = c);
                        _saveActiveLayer();
                      },
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Custom rang (rainbow):',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Slider(
                      value: HSVColor.fromColor(_textColor).hue,
                      min: 0,
                      max: 360,
                      onChanged: (v) {
                        setState(() {
                          _textColor = HSVColor.fromAHSV(
                            1,
                            v,
                            0.85,
                            1,
                          ).toColor();
                        });
                        _saveActiveLayer();
                      },
                    ),
                  ],
                ),
            },
          ),
        ),
      ],
    );
  }

  /// Font panel (Aa): a VERTICAL list — every font name rendered
  /// IN its own typeface (font_registry + the Latin google_fonts).
  Widget _textFontPanel() {
    final entries = <(String, String)>[
      ('default', 'Default'),
      ('roboto', 'Roboto'),
      ('merriweather', 'Merriweather'),
      ('dancing', 'Dancing Script'),
      ('bebas', 'Bebas Neue'),
      ('pacifico', 'Pacifico'),
      ('kufi', 'Noto Kufi Arabic'),
      for (final f in UrduFonts.all) (f.id, f.name),
    ];
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (ctx, i) {
        final e = entries[i];
        final selected = _textFont == e.$1;
        return ListTile(
          dense: true,
          title: Text(
            e.$2,
            style: _applyFontKey(
              e.$1,
              TextStyle(
                fontSize: 18,
                color: selected ? _accentLight : Colors.white,
              ),
            ),
          ),
          trailing: selected
              ? const Icon(Icons.check, color: _accentLight)
              : null,
          onTap: () {
            setState(() => _textFont = e.$1);
            _saveActiveLayer();
          },
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // Preview: image + overlays + text layers (with handles) + paint.
  // ------------------------------------------------------------------

  TextStyle _layerStyle(_TextLayerData layer, double fontPx, double s) {
    final shadows = <Shadow>[];
    if (layer.glow) {
      shadows.add(Shadow(
        color: Color(layer.glowArgb).withValues(alpha: 0.9),
        blurRadius: layer.glowBlur * s,
      ));
    }
    if (layer.shadow) {
      shadows.add(Shadow(
        color: Color(layer.shadowArgb),
        offset: Offset(layer.shadowDx * s, layer.shadowDy * s),
        blurRadius: layer.shadowBlur * s,
      ));
    }
    final base = TextStyle(
      color: Color(layer.colorArgb).withValues(alpha: layer.opacity),
      fontSize: fontPx,
      height: layer.lineSpacing,
      fontWeight: layer.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: layer.italic ? FontStyle.italic : FontStyle.normal,
      letterSpacing: layer.letterSpacing * s,
      shadows: shadows,
    );
    return _applyFontKey(layer.font, base);
  }

  Widget _layerTextWidget(_TextLayerData layer, double s) {
    final fontPx = layer.size * s;
    final style = _layerStyle(layer, fontPx, s);
    final align = layer.alignIndex == 0
        ? TextAlign.left
        : layer.alignIndex == 2
            ? TextAlign.right
            : TextAlign.center;
    Widget tw;
    if (layer.outline) {
      tw = Stack(
        alignment: Alignment.center,
        children: [
          Text(
            layer.text,
            textAlign: align,
            style: style.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = layer.outlineWidth * s
                ..color = Color(layer.outlineArgb),
              shadows: [],
            ),
          ),
          Text(layer.text, textAlign: align, style: style),
        ],
      );
    } else {
      tw = Text(layer.text, textAlign: align, style: style);
    }
    if (layer.bg) {
      tw = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Color(layer.bgArgb),
          borderRadius: BorderRadius.circular(10),
        ),
        child: tw,
      );
    }
    return tw;
  }

  Offset _toPreviewLocal(Offset global) {
    final rb = _previewKey2.currentContext?.findRenderObject();
    if (rb is RenderBox) return rb.globalToLocal(global);
    return Offset.zero;
  }

  Future<void> _layerMenu(int index) async {
    final action = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(100, 200, 100, 200),
      items: const [
        PopupMenuItem(value: 'copy', child: Text('Copy')),
        PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (action == null) return;
    setState(() {
      _saveActiveLayer();
      _loadLayer(index);
    });
    if (action == 'copy') {
      _duplicateActiveLayer();
    } else if (action == 'delete') {
      _deleteActiveLayer();
    } else if (action == 'edit') {
      setState(() => _textTab = 'type');
      _textFocus.requestFocus();
    }
  }

  Widget _textLayerWidget(_TextLayerData layer, int index, Size box) {
    final isActive = index == _activeLayer;
    final showHandles = isActive && _activePhotoTool == 'text';
    final s = _imgWidth > 0 ? box.width / _imgWidth : 0.6;
    final w = layer.boxWidth * box.width;
    final center = Offset(
      layer.offset.dx * box.width,
      layer.offset.dy * box.height,
    );
    return Positioned(
      left: center.dx,
      top: center.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.rotate(
          angle: layer.rotation * math.pi / 180,
          child: SizedBox(
            width: w,
            child: GestureDetector(
              onTap: () {
                if (_activePhotoTool == 'text' && !isActive) {
                  setState(() {
                    _saveActiveLayer();
                    _loadLayer(index);
                  });
                }
              },
              onLongPress:
                  _activePhotoTool == 'text' ? () => _layerMenu(index) : null,
              onPanUpdate: (d) {
                if (_activePhotoTool != 'text') return;
                if (!isActive) {
                  setState(() {
                    _saveActiveLayer();
                    _loadLayer(index);
                  });
                  return;
                }
                setState(() {
                  layer.offset = Offset(
                    (layer.offset.dx + d.delta.dx / box.width)
                        .clamp(0.05, 0.95),
                    (layer.offset.dy + d.delta.dy / box.height)
                        .clamp(0.05, 0.95),
                  );
                  _textOffset = layer.offset;
                });
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: w,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    decoration: showHandles
                        ? BoxDecoration(
                            border:
                                Border.all(color: Colors.white, width: 1.2),
                          )
                        : null,
                    child: _layerTextWidget(layer, s),
                  ),
                  if (showHandles) ...[
                    // Red ✕ delete handle (top-left).
                    Positioned(
                      left: -11,
                      top: -11,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _loadLayer(index);
                          });
                          _deleteActiveLayer();
                        },
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // Rotate/scale handle (bottom-right): circular
                    // drag around the box centre rotates; distance
                    // from the centre scales the font.
                    Positioned(
                      right: -11,
                      bottom: -11,
                      child: GestureDetector(
                        onPanStart: (d) {
                          final local = _toPreviewLocal(d.globalPosition);
                          final v = local - center;
                          _handleStartAngle = math.atan2(v.dy, v.dx);
                          _handleStartDist =
                              math.max(20, v.distance);
                          _handleStartRot = layer.rotation;
                          _handleStartSize = layer.size;
                        },
                        onPanUpdate: (d) {
                          final local = _toPreviewLocal(d.globalPosition);
                          final v = local - center;
                          setState(() {
                            layer.rotation = _handleStartRot +
                                (math.atan2(v.dy, v.dx) -
                                        _handleStartAngle) *
                                    180 /
                                    math.pi;
                            layer.size = (_handleStartSize *
                                    v.distance /
                                    _handleStartDist)
                                .clamp(14, 300);
                            _textRotation = layer.rotation;
                            _textSize = layer.size;
                          });
                        },
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.rotate_right,
                            size: 14,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    // White side dots: drag to change the box width.
                    Positioned(
                      left: -6,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: GestureDetector(
                          onPanUpdate: (d) => setState(() {
                            layer.boxWidth =
                                (layer.boxWidth - d.delta.dx * 2 / box.width)
                                    .clamp(0.15, 0.98);
                            _textBoxWidth = layer.boxWidth;
                          }),
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: -6,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: GestureDetector(
                          onPanUpdate: (d) => setState(() {
                            layer.boxWidth =
                                (layer.boxWidth + d.delta.dx * 2 / box.width)
                                    .clamp(0.15, 0.98);
                            _textBoxWidth = layer.boxWidth;
                          }),
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlayWidget(_OverlayData o, int index, Size box) {
    final w = o.scaleFrac * box.width;
    final selected = index == _activeOverlay &&
        (_activePhotoTool == 'sticker' || _activePhotoTool == 'pip');
    return Positioned(
      left: o.center.dx * box.width,
      top: o.center.dy * box.height,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Transform.rotate(
          angle: o.rotation * math.pi / 180,
          child: GestureDetector(
            onTap: () => setState(() => _activeOverlay = index),
            onPanUpdate: (d) => setState(() {
              _activeOverlay = index;
              o.center = Offset(
                (o.center.dx + d.delta.dx / box.width).clamp(0.05, 0.95),
                (o.center.dy + d.delta.dy / box.height).clamp(0.05, 0.95),
              );
            }),
            child: Container(
              decoration: selected
                  ? BoxDecoration(
                      border: Border.all(color: Colors.white, width: 1.2),
                    )
                  : null,
              child: o.glyph != null
                  ? Text(
                      o.glyph!,
                      style: TextStyle(fontSize: w * 0.85),
                    )
                  : Image.file(
                      File(o.path!),
                      width: w,
                      fit: BoxFit.contain,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  void _paintStart(Offset local, Size size) {
    final n = Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
    if (_paintMode == 'remove' && _maskErase) {
      _eraseMaskNear(n);
      return;
    }
    final argb = _paintMode == 'doodle'
        ? _doodleColor.toARGB32()
        : 0xFFFFFFFF;
    setState(() {
      _currentStroke = StrokePath(
        argb: argb,
        widthFrac: _brushSize,
        points: [n],
      );
    });
  }

  void _paintUpdate(Offset local, Size size) {
    final n = Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
    if (_paintMode == 'remove' && _maskErase) {
      _eraseMaskNear(n);
      return;
    }
    final cur = _currentStroke;
    if (cur == null) return;
    setState(() => cur.points.add(n));
  }

  void _paintEnd() {
    final cur = _currentStroke;
    if (cur == null) return;
    setState(() {
      _strokes.add(cur);
      _currentStroke = null;
    });
  }

  void _eraseMaskNear(Offset n) {
    setState(() {
      for (final s in _strokes) {
        s.points.removeWhere((pt) => (pt - n).distance < _brushSize);
      }
      _strokes.removeWhere((s) => s.points.isEmpty);
    });
  }

  Widget _previewArea(File file) {
    final aspect = (_imgWidth > 0 && _imgHeight > 0)
        ? _imgWidth / _imgHeight
        : 1.0;
    return Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: LayoutBuilder(
          builder: (ctx, cons) {
            final size = Size(cons.maxWidth, cons.maxHeight);
            return Stack(
              key: _previewKey2,
              clipBehavior: Clip.none,
              children: [
                if (_hasTransparency)
                  Positioned.fill(
                    child: CustomPaint(painter: _CheckerPainter()),
                  ),
                Positioned.fill(
                  child: _comparing && _originalFile != null
                      ? Image.file(_originalFile!, fit: BoxFit.fill)
                      : _previewBytes != null && _previewKey == file.path
                          ? Image.memory(_previewBytes!, fit: BoxFit.fill)
                          : ColorFiltered(
                              colorFilter: ColorFilter.matrix(_matrix),
                              child: Image.file(file, fit: BoxFit.fill),
                            ),
                ),
                for (var i = 0; i < _overlays.length; i++)
                  _overlayWidget(_overlays[i], i, size),
                for (var i = 0; i < _layers.length; i++)
                  if (_layers[i].text.isNotEmpty)
                    _textLayerWidget(_layers[i], i, size),
                if (_paintMode != null)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) => _paintStart(d.localPosition, size),
                      onPanUpdate: (d) =>
                          _paintUpdate(d.localPosition, size),
                      onPanEnd: (_) => _paintEnd(),
                      child: CustomPaint(
                        painter: _StrokePainter(
                          strokes: _strokes,
                          current: _currentStroke,
                          mode: _paintMode!,
                          doodleColor: _doodleColor,
                        ),
                        size: size,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  static const _toolbar = <(String, String, IconData)>[
    ('canvas', 'Canvas', Icons.aspect_ratio),
    ('filter', 'Filter', Icons.filter_vintage),
    ('adjust', 'Adjust', Icons.tune),
    ('effect', 'Effect', Icons.auto_awesome),
    ('background', 'Background', Icons.image),
    ('portrait', 'Portrait', Icons.face),
    ('sticker', 'Sticker', Icons.emoji_emotions),
    ('text', 'Text', Icons.text_fields),
    ('pip', 'PIP', Icons.picture_in_picture_alt),
    ('remove', 'Remove', Icons.auto_fix_off),
    ('enhance', 'Enhance', Icons.auto_fix_high),
    ('cutout', 'Cutout', Icons.content_cut),
    ('doodle', 'Doodle', Icons.gesture),
    ('makeup', 'Makeup', Icons.brush),
    ('crop', 'Crop', Icons.crop),
    ('expand', 'Expand', Icons.open_in_full),
    ('frame', 'Frame', Icons.border_outer),
    ('rotate', 'Rotate', Icons.rotate_right),
  ];

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
        body: SafeArea(
          child: Column(
            children: [
              // Top bar: back arrow left, Export right (S3 mockup).
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                  ),
                  const Text(
                    'Photo Editor',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Pick photo',
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.photo_library,
                        color: Colors.white),
                  ),
                  IconButton(
                    tooltip: 'Reset all',
                    onPressed: file == null || _busy ? null : _resetAll,
                    icon: const Icon(Icons.restart_alt,
                        color: Colors.white),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 8, 12, 8),
                    child: ElevatedButton(
                      onPressed: file == null || _busy ? null : _export,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _exportRed,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: const Text(
                        'Export',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              if (_busy)
                const LinearProgressIndicator(minHeight: 2),
              // Big preview centre, with floating controls.
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      color: Colors.black,
                      child: file == null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.photo_library,
                                      size: 64, color: Colors.white38),
                                  const SizedBox(height: 12),
                                  const Text('No photo selected',
                                      style: TextStyle(
                                          color: Colors.white70)),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: _pick,
                                    icon: const Icon(Icons.photo_library),
                                    label: const Text('Pick photo'),
                                  ),
                                ],
                              ),
                            )
                          : _previewArea(file),
                    ),
                    if (file != null) ...[
                      // v1.5.0 (#4): the floating flip + canvas side
                      // buttons are REMOVED — both duplicated real
                      // controls (Flip lives in the Rotate panel,
                      // Canvas is a toolbar tool) and cluttered the
                      // preview. The preview now carries only the
                      // undo/redo pill (bottom-left, per P1).
                      // Undo/redo pill, bottom-left of the preview.
                      Positioned(
                        left: 10,
                        bottom: 10,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Undo',
                                onPressed:
                                    _canUndo && !_busy ? _undo : null,
                                icon: const Icon(Icons.undo,
                                    color: Colors.white, size: 19),
                              ),
                              IconButton(
                                tooltip: 'Redo',
                                onPressed:
                                    _canRedo && !_busy ? _redo : null,
                                icon: const Icon(Icons.redo,
                                    color: Colors.white, size: 19),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // v1.5.0 (#4): the floating Compare pill is
                      // REMOVED from the preview — hold-to-compare
                      // itself is preserved as a press-and-hold chip
                      // in the panel header (see _photoPanelHeader).
                      if (_activePhotoTool == 'canvas')
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Text(
                              'Pinch to zoom',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ),
                    ],
                    if (_statusVisible)
                      Positioned(
                        top: 8,
                        left: 12,
                        right: 12,
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color:
                                  Colors.black.withValues(alpha: 0.75),
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
              // Bottom zone: the ONE toolbar, or the open tool's
              // panel (header + controls), or the Text editor zone.
              if (_activePhotoTool == 'text')
                Container(
                  height: 272,
                  color: const Color(0xFF1B1B1B),
                  padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
                  child: _textZone(),
                )
              else if (_activePhotoTool != null)
                Container(
                  height: 258,
                  color: const Color(0xFF1B1B1B),
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _photoPanelHeader(_activePhotoTool!),
                      Expanded(
                        child: SingleChildScrollView(
                          child: _panelFor(_activePhotoTool!),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  height: 84,
                  color: const Color(0xFF1B1B1B),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6),
                    children: [
                      for (final t in _toolbar)
                        _toolItem(t.$1, t.$2, t.$3),
                    ],
                  ),
                ),
            ],
          ),
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

/// Transparency checkerboard (Cutout preview).
class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 12.0;
    final light = Paint()..color = const Color(0xFFCCCCCC);
    final dark = Paint()..color = const Color(0xFF999999);
    canvas.drawRect(Offset.zero & size, light);
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = 0; x * cell < size.width; x++) {
        if ((x + y) % 2 == 0) continue;
        canvas.drawRect(
          Rect.fromLTWH(x * cell, y * cell, cell, cell),
          dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Painted strokes overlay (Remove mask / Cutout eraser / Doodle).
class _StrokePainter extends CustomPainter {
  _StrokePainter({
    required this.strokes,
    required this.current,
    required this.mode,
    required this.doodleColor,
  });

  final List<StrokePath> strokes;
  final StrokePath? current;
  final String mode;
  final Color doodleColor;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [...strokes, ?current];
    for (final s in all) {
      final color = mode == 'doodle'
          ? Color(s.argb)
          : mode == 'erase'
              ? Colors.white.withValues(alpha: 0.55)
              : Colors.red.withValues(alpha: 0.45);
      final paint = Paint()
        ..color = color
        ..strokeWidth = s.widthFrac * size.width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final dotPaint = Paint()..color = color;
      final radius = s.widthFrac * size.width / 2;
      for (var i = 0; i < s.points.length; i++) {
        final pt = Offset(
          s.points[i].dx * size.width,
          s.points[i].dy * size.height,
        );
        canvas.drawCircle(pt, radius, dotPaint);
        if (i > 0) {
          final prev = Offset(
            s.points[i - 1].dx * size.width,
            s.points[i - 1].dy * size.height,
          );
          canvas.drawLine(prev, pt, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) => true;
}

/// Tone-curve editor graph: grid + the channel's control polyline.
class _CurvePainter extends CustomPainter {
  _CurvePainter({required this.points, required this.channel});

  final List<Offset> points;
  final String channel;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF1E1E1E),
    );
    final grid = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final t = size.width * i / 4;
      canvas.drawLine(Offset(t, 0), Offset(t, size.height), grid);
      canvas.drawLine(Offset(0, t), Offset(size.width, t), grid);
    }
    final color = switch (channel) {
      'r' => Colors.red,
      'g' => Colors.green,
      'b' => Colors.blue,
      _ => Colors.white,
    };
    final sorted = [...points]..sort((a, b) => a.dx.compareTo(b.dx));
    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < sorted.length; i++) {
      final pt = Offset(
        sorted[i].dx * size.width,
        (1 - sorted[i].dy) * size.height,
      );
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(path, line);
    final dot = Paint()..color = color;
    for (final p in sorted) {
      canvas.drawCircle(
        Offset(p.dx * size.width, (1 - p.dy) * size.height),
        5,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter oldDelegate) => true;
}
