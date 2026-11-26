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
import '../theme.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'photo_models.dart';
import 'photo_editor_controller.dart';
import 'panels/adjust_panel.dart';
import 'panels/background_panel.dart';
import 'panels/canvas_panel.dart';
import 'panels/crop_panel.dart';
import 'panels/cutout_panel.dart';
import 'panels/doodle_panel.dart';
import 'panels/effect_panel.dart';
import 'panels/enhance_panel.dart';
import 'panels/expand_panel.dart';
import 'panels/filter_panel.dart';
import 'panels/frame_panel.dart';
import 'panels/makeup_panel.dart';
import 'panels/pip_panel.dart';
import 'panels/portrait_panel.dart';
import 'panels/remove_panel.dart';
import 'panels/rotate_panel.dart';
import 'panels/sticker_panel.dart';
import 'panels/text_panels.dart';
import 'widgets/panel_helpers.dart';
import 'widgets/photo_stage.dart';

import '../services/ai_service.dart';
import '../services/ai_tool_charge.dart';
import '../services/caption_styles.dart';
import '../services/crash_guard.dart';
import '../services/feature_gate.dart';
import '../services/model_pack_service.dart';
import '../services/onnx_isolate.dart';
import '../services/photo_pipeline.dart';
import '../services/photo_pipeline.dart' as photo_pipeline;

List<int> _decodeSizeOf(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return [0, 0];
  return [decoded.width, decoded.height];
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

class _PhotoEditorScreenState extends State<PhotoEditorScreen>
    implements PhotoEditorController {
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
  final List<TextLayerData> _layers = [];
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
  final List<OverlayData> _overlays = [];
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
  List<List<double>> _hslAdjustments = List.generate(8, (_) => [0.0, 1.0, 0.0]);
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
    // Phase 7 (pipeline safety): clear temp files orphaned by
    // previous editing sessions (see _sweepStaleSessionTemps).
    unawaited(_sweepStaleSessionTemps());
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
    // Phase 7 (pipeline safety): this session's working PNGs go
    // with the session — nothing outside this screen references
    // them (exports are copied to the gallery / share targets).
    _discardSessionTemps(List<File>.of(_history));
    _textCtrl.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  // v1.3.0 (§5B): the status shows as a transient overlay chip on
  // the preview (auto-hides), never as a permanent line.
  bool _statusVisible = false;
  Timer? _statusTimer;
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
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

  // F3: the shared neutral test from the pipeline — preview,
  // params and export all judge the table the same way.
  bool get _hslIsNeutral => hslAdjustmentsAreNeutral(_hslAdjustments);

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
      final pts = [..._curvePoints[ch]!]..sort((a, b) => a.dx.compareTo(b.dx));
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
    _curvePoints.updateAll((_, _) => [const Offset(0, 0), const Offset(1, 1)]);
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
  // ---- Phase 7 (pipeline safety): session temp-file cleanup ----
  // _replaceWorking writes every applied edit as a NEW PNG in the
  // system temp dir (pve_photo_<millis>.png). Before this cleanup
  // those files were never deleted: states dropped by the redo
  // truncation, the 10-state cap, a reset or a new pick — and the
  // whole session on dispose — leaked full-size PNGs into temp
  // indefinitely. Only files with OUR prefix are ever touched;
  // the user's picked original never carries it.

  bool _isSessionTemp(File f) => p.basename(f.path).startsWith('pve_photo_');

  /// Fire-and-forget delete of [f] when it is a session temp file.
  void _discardSessionTemp(File f) {
    if (!_isSessionTemp(f)) return;
    unawaited(() async {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {
        // Temp cleanup is best-effort — the OS purges temp too.
      }
    }());
  }

  void _discardSessionTemps(Iterable<File> files) {
    for (final f in files) {
      _discardSessionTemp(f);
    }
  }

  /// Deletes pve_photo_*/pve_export_* files left in temp by
  /// PREVIOUS sessions. The one-hour cutoff protects this live
  /// session: its working files are minutes old, and an export
  /// file a share sheet may still be reading is never swept.
  Future<void> _sweepStaleSessionTemps() async {
    try {
      final dir = await getTemporaryDirectory();
      final cutoff = DateTime.now().subtract(const Duration(hours: 1));
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final name = p.basename(e.path);
        if (!name.startsWith('pve_photo_') &&
            !name.startsWith('pve_export_')) {
          continue;
        }
        try {
          final st = await e.stat();
          if (st.modified.isBefore(cutoff)) await e.delete();
        } catch (_) {
          // One bad file must not stop the sweep.
        }
      }
    } catch (_) {
      // Best-effort housekeeping only.
    }
  }

  void _adoptPickedFile(File f) {
    final dropped = List<File>.of(_history);
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
    _discardSessionTemps(dropped.where((old) => old.path != f.path));
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
    final dropped = <File>[];
    if (_historyIndex < _history.length - 1) {
      dropped.addAll(_history.getRange(_historyIndex + 1, _history.length));
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    if (_history.isEmpty || _history.last.path != f.path) {
      _history.add(f);
    }
    while (_history.length > 10) {
      dropped.add(_history.removeAt(0));
    }
    _historyIndex = _history.length - 1;
    _discardSessionTemps(dropped);
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
    final dropped = List<File>.of(_history);
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
    _discardSessionTemps(dropped.where((old) => old.path != orig.path));
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
  /// v1.3.0 (§8) the unlock is COINS ONLY; admins are waived by
  /// CoinService itself.
  ///
  /// Build 9 (v1.7.0, point #6B): the price model changed on the
  /// user's order — instead of a once-per-session 50-coin unlock,
  /// EVERY AI use now charges the remote-config price
  /// (`ai_tool_price_coins`, default 25) through [AiToolCharge].
  /// Build 9 (point #5): the remote kill switch is checked
  /// first — a killed AI tool shows the polite closed message
  /// and never charges.
  Future<bool> _runAi(String label, Future<void> Function() job) async {
    final file = _workingFile;
    if (file == null || _busy) return false;
    if (FeatureGate.isKilled(KillableFeature.photoAi)) {
      _fail(FeatureGate.killedMessage);
      return false;
    }
    final outcome = await AiToolCharge.chargeWithConfirm(
      context,
      toolLabel: 'Photo AI tools',
      reason: AiToolCharge.reasonPhotoAi,
    );
    if (!mounted) return false;
    switch (outcome) {
      case AiChargeOutcome.ok:
        break;
      case AiChargeOutcome.cancelled:
        return false;
      case AiChargeOutcome.insufficient:
        _fail(AiToolCharge.insufficientMessage);
        return false;
      case AiChargeOutcome.failed:
        _fail('Charge failed — try again.');
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
    } catch (e, s) {
      // Build 7 (v1.5.9): every AI photo operation flows through
      // here — failures are recorded with the boundary tag (no
      // banner) in addition to the status-line message.
      CrashGuard.captureHandled(e, s, source: 'photo.pipeline');
      _fail('$label failed: $e');
      return false;
    } finally {
      setState(() => _busy = false);
    }
  }

  /// Runs a FREE enhance job (no coin gate). Shows busy state.
  Future<bool> _runEnhance(String label, Future<void> Function() job) async {
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
    } catch (e, s) {
      // Build 7 (v1.5.9): every free enhance operation flows
      // through here — recorded with the boundary tag, as in
      // the AI runner above.
      CrashGuard.captureHandled(e, s, source: 'photo.pipeline');
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
    unawaited(
      future.whenComplete(() {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }),
    );
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('AI pack is downloading'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: v > 0 ? v : null),
              const SizedBox(height: 10),
              Text(
                '${(v * 100).round()}% — downloads only the first time, '
                'then it works offline.',
              ),
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

  /// Write PNG [bytes] as the new working file (the off-thread
  /// ops already encoded them — no UI-isolate encode here).
  Future<void> _replaceWorkingBytes(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final f = File(
      p.join(
        dir.path,
        'pve_photo_${DateTime.now().millisecondsSinceEpoch}.png',
      ),
    );
    await f.writeAsBytes(bytes);
    _setWorkingFile(f);
  }

  /// Run an ONNX image op: ensure its pack first (progress dialog
  /// when missing), then run the op OFF the UI thread
  /// (v1.17.0 G1, Point #37a — the old on-thread decode +
  /// synchronous inference + encode chain was the same ANR
  /// class as the Reporter BG freeze) and push the result
  /// through the undo history.
  Future<bool> _runOnnxOffThread(
    String label,
    String packId,
    String op, {
    List<StrokePath>? strokes,
  }) async {
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
        _fail(
          ModelPackService.describeFailure(
            ModelPackService.instance.lastFailure,
          ),
        );
        return false;
      }
    }
    return _runEnhance(label, () async {
      final bytes = await _workingFile!.readAsBytes();
      final out = await runOnnxOpOffThread(
        op: op,
        packId: packId,
        inputBytes: bytes,
        strokes: strokes,
      );
      if (out == null) {
        throw Exception('No result from the AI model.');
      }
      await _replaceWorkingBytes(out);
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
    // v1.17.0 (G1): matte + composite run in ONE background
    // isolate job (kOnnxOpMatteCutout) — previously this exact
    // chain ran on the UI isolate (Point #37a ANR class).
    final ok = await _runOnnxOffThread(
      'HQ Cutout',
      'birefnet_fp16',
      kOnnxOpMatteCutout,
    );
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
      await _replaceWorking(photo_pipeline.flattenOnColor(image, _replaceBgColor.toARGB32()));
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
      final out = await photo_pipeline.autoEnhance(image);
      await _replaceWorking(out);
    });
  }

  /// Portrait > Light fix: the same algorithmic auto-levels as
  /// Auto-enhance, offered free inside the Portrait panel.
  Future<void> _lightFix() async {
    await _runEnhance('Fixing light', () async {
      final image = await _decodeWorking();
      final out = await photo_pipeline.autoEnhance(image);
      await _replaceWorking(out);
    });
  }

  /// Portrait > Bokeh (v1.4.0): Depth Anything V2 Small depth-
  /// guided background blur via ONNX.
  Future<void> _portraitBokeh() async {
    await _runOnnxOffThread(
      'Applying bokeh',
      'depth_v2_small',
      kOnnxOpBokeh,
    );
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
          'This enhancer is for photos — the TEXT present in the photo '
          'TEXT may distort. Continue?',
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
    await _runOnnxOffThread('AI Enhance HD', 'esrgan', kOnnxOpEsrgan);
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
      final out = await applyClassicEffect(image, effect, intensity: value);
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
    await _runOnnxOffThread(label, packId, kOnnxOpStyle);
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
      final widthPx = math.max(2, (image.width * _frameWidthPct / 100).round());
      await _replaceWorking(addBorder(image, widthPx, _frameColor.toARGB32()));
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
      _fail(
        'Do Cutout first — the outline applies on the transparent edge '
        'applies.',
      );
      return;
    }
    await _runEnhance('Adding outline', () async {
      final image = await _decodeWorking();
      final widthPx = math.max(2, (image.width * _outlineWidth / 1000).round());
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
      _fail('Paint over the object with the brush first.');
      return;
    }
    final strokes = List<StrokePath>.from(_strokes);
    // The mask is built inside the isolate job from the strokes
    // (it needs the decoded size, which only exists there).
    final ok = await _runOnnxOffThread(
      'Removing object',
      'migan',
      kOnnxOpMigan,
      strokes: strokes,
    );
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
      _overlays.add(OverlayData(path: picked.path));
      _activeOverlay = _overlays.length - 1;
    });
  }

  /// Sticker tap: a glyph overlay layer at the photo centre.
  void _addSticker(String glyph) {
    setState(() {
      _overlays.add(OverlayData(glyph: glyph));
      _activeOverlay = _overlays.length - 1;
    });
    _setStatus('Sticker applied — drag it on the preview.');
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
        // F3: the per-color HSL table rides the export params
        // (deep-copied — later slider moves must not mutate an
        // in-flight export), so Save applies exactly what the
        // preview shows. 'Apply HSL' still exists as a bake,
        // but it is no longer required for the effect to save.
        hslAdjustments: _hslIsNeutral
            ? null
            : _hslAdjustments
                .map((a) => List<double>.from(a))
                .toList(),
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
          overlayParams.add(
            PhotoOverlayLayerParams(
              pngBytes: png,
              centerX: o.center.dx,
              centerY: o.center.dy,
              scaleFrac: o.scaleFrac,
              rotationDegrees: o.rotation,
            ),
          );
        } else if (o.path != null) {
          overlayParams.add(
            PhotoOverlayLayerParams(
              imagePath: o.path,
              centerX: o.center.dx,
              centerY: o.center.dy,
              scaleFrac: o.scaleFrac,
              rotationDegrees: o.rotation,
            ),
          );
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
    } catch (e, s) {
      // Build 7: recorded with its boundary tag (no banner).
      CrashGuard.captureHandled(e, s, source: 'photo.pipeline');
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
                  _fail('Could not share: $e');
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
      _layers.add(TextLayerData());
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
            Icon(icon, size: 24, color: selected ? kPhotoExportRed : Colors.white),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                color: selected ? kPhotoExportRed : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
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
          _layers.add(TextLayerData());
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
            'Drag the white dots on both sides of the text box to adjust the width '
            'adjust — drag the box to move it anywhere.',
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






  // ------------------------------------------------------------------
  // Tool panels.
  // ------------------------------------------------------------------





  // ---- Adjust ----









  // ---- Effect ----



  // ---- Background ----


  // ---- Portrait ----


  // ---- Sticker / PIP overlays ----




  // ---- Remove ----


  // ---- Enhance ----


  // ---- Cutout ----


  // ---- Doodle ----


  // ---- Makeup ----


  // ---- Crop ----


  // ---- Expand ----


  // ---- Frame ----


  // ---- Rotate ----


  /// Panel switch — the open tool's controls.
  Widget _panelFor(String key) {
    // Phase 7 split: each tool's panel is a real widget
    // in lib/photo/panels/ — this switch is the one
    // dispatch, exactly the pre-split mapping.
    switch (key) {
      case 'canvas':
        return CanvasPanel(this);
      case 'filter':
        return FilterPanel(this);
      case 'adjust':
        return AdjustPanel(this);
      case 'effect':
        return EffectPanel(this);
      case 'background':
        return BackgroundPanel(this);
      case 'portrait':
        return PortraitPanel(this);
      case 'sticker':
        return StickerPanel(this);
      case 'pip':
        return PipPanel(this);
      case 'remove':
        return RemovePanel(this);
      case 'enhance':
        return EnhancePanel(this);
      case 'cutout':
        return CutoutPanel(this);
      case 'doodle':
        return DoodlePanel(this);
      case 'makeup':
        return MakeupPanel(this);
      case 'crop':
        return CropPanel(this);
      case 'expand':
        return ExpandPanel(this);
      case 'frame':
        return FramePanel(this);
      case 'rotate':
        return RotatePanel(this);
      default:
        return const SizedBox.shrink();
    }
  }

  // ------------------------------------------------------------------
  // Text editor zone (replaces the generic panel for the Text tool):
  // above-bar toolbar + typing bar / Style / Colour / Font panels.
  // ------------------------------------------------------------------









  // ------------------------------------------------------------------
  // Preview: image + overlays + text layers (with handles) + paint.
  // ------------------------------------------------------------------







  void _paintStart(Offset local, Size size) {
    final n = Offset(
      (local.dx / size.width).clamp(0.0, 1.0),
      (local.dy / size.height).clamp(0.0, 1.0),
    );
    if (_paintMode == 'remove' && _maskErase) {
      _eraseMaskNear(n);
      return;
    }
    final argb = _paintMode == 'doodle' ? _doodleColor.toARGB32() : 0xFFFFFFFF;
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


  static const _toolbar = <(String, String, IconData)>[
    ('canvas', 'Canvas', Icons.aspect_ratio),
    ('filter', 'Filter', Icons.filter_vintage),
    ('adjust', 'Adjust', Icons.tune),
    ('effect', 'Effect', Icons.auto_awesome),
    ('background', 'Background', Icons.image),
    ('portrait', 'Portrait', Icons.face),
    ('sticker', 'Sticker', Icons.emoji_emotions),
    ('text', 'Text', Icons.text_fields),
    ('pip', 'PIP', Icons.add),
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
      // v1.18.0 (Motion reskin): the subtree wears the app-wide
      // Motion theme (navy/glass chrome, electric accents); the
      // panels' own violet accent (kPhotoAccent) belongs to the
      // same electric family and stays where panels pin it.
      // Skin only — every control and layout is unchanged.
      data: TjProTheme.dark,
      child: Scaffold(
        backgroundColor: TjProTheme.motionBgBottom,
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
                  // Flexible (v1.5.2, #69 sweep): the fixed
                  // title + 3 icon buttons + Export pill overflow
                  // narrow screens — the title ellipsizes first.
                  const Flexible(
                    child: Text(
                      'Photo Editor',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Pick photo',
                    onPressed: _busy ? null : _pick,
                    icon: const Icon(Icons.photo_library, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: 'Reset all',
                    onPressed: file == null || _busy ? null : _resetAll,
                    icon: const Icon(Icons.restart_alt, color: Colors.white),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 8, 12, 8),
                    child: ElevatedButton(
                      onPressed: file == null || _busy ? null : _export,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPhotoExportRed,
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
              if (_busy) const LinearProgressIndicator(minHeight: 2),
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
                                  const Icon(
                                    Icons.photo_library,
                                    size: 64,
                                    color: Colors.white38,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No photo selected',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: _pick,
                                    icon: const Icon(Icons.photo_library),
                                    label: const Text('Pick photo'),
                                  ),
                                ],
                              ),
                            )
                          : PhotoStage(this, file),
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
                                onPressed: _canUndo && !_busy ? _undo : null,
                                icon: const Icon(
                                  Icons.undo,
                                  color: Colors.white,
                                  size: 19,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Redo',
                                onPressed: _canRedo && !_busy ? _redo : null,
                                icon: const Icon(
                                  Icons.redo,
                                  color: Colors.white,
                                  size: 19,
                                ),
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
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Text(
                              'Pinch to zoom',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
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
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _status,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
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
                  // Build 6 (Part 4, tools tartib): keyed per tool
                  // so switching tools rebuilds the zone — the
                  // panel scroll restarts at the top and only the
                  // selected tool's controls exist on screen (the
                  // News Maker + Video Editor shells already key
                  // their panel hosts the same way).
                  key: const ValueKey('photo-panel-text'),
                  height: 272,
                  color: TjProTheme.motionPanel,
                  padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
                  child: TextZone(this),
                )
              else if (_activePhotoTool != null)
                Container(
                  key: ValueKey('photo-panel-$_activePhotoTool'),
                  height: 258,
                  color: TjProTheme.motionPanel,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      photoPanelHeader(_activePhotoTool!),
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
                  color: TjProTheme.motionPanel,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    children: [
                      for (final t in _toolbar) _toolItem(t.$1, t.$2, t.$3),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  // ---- Phase 7 split: PhotoEditorController forwards ----
  // Every member forwards to the private member of the
  // same (underscored) name — the split-out panels, text
  // zone, layer widgets and stage reach the editor state
  // ONLY through these (see photo_editor_controller.dart).

  @override
  void update(VoidCallback fn) => setState(fn);

  @override
  int get activeLayer => _activeLayer;
  @override
  set activeLayer(int value) => _activeLayer = value;

  @override
  int get activeOverlay => _activeOverlay;
  @override
  set activeOverlay(int value) => _activeOverlay = value;

  @override
  String? get activePhotoTool => _activePhotoTool;
  @override
  set activePhotoTool(String? value) => _activePhotoTool = value;

  @override
  Future<void> addPipOverlay() => _addPipOverlay();

  @override
  void addSticker(String glyph) => _addSticker(glyph);

  @override
  void addTextLayer() => _addTextLayer();

  @override
  String get adjSel => _adjSel;
  @override
  set adjSel(String value) => _adjSel = value;

  @override
  Future<void> aiEnhanceHd() => _aiEnhanceHd();

  @override
  Future<void> applyArtisticStyle(String packId, String label) => _applyArtisticStyle(packId, label);

  @override
  Future<void> applyCanvas() => _applyCanvas();

  @override
  Future<void> applyDoodle() => _applyDoodle();

  @override
  Future<void> applyEffect() => _applyEffect();

  @override
  Future<void> applyEraser() => _applyEraser();

  @override
  Future<void> applyExpand() => _applyExpand();

  @override
  Future<void> applyFrame() => _applyFrame();

  @override
  Future<void> applyHSL() => _applyHSL();

  @override
  Future<void> applyMakeup() => _applyMakeup();

  @override
  Future<void> applyOutline() => _applyOutline();

  @override
  Future<void> applyRemove() => _applyRemove();

  @override
  Future<void> applyStraighten() => _applyStraighten();

  @override
  void applyStudioStyle(StudioCaptionStyle s, {bool label = false}) => _applyStudioStyle(s, label: label);

  @override
  void applyTextTemplate(String key) => _applyTextTemplate(key);

  @override
  Future<void> autoEnhance() => _autoEnhance();

  @override
  Future<void> beautify() => _beautify();

  @override
  Future<void> blurBackground() => _blurBackground();

  @override
  double get brightness => _brightness;
  @override
  set brightness(double value) => _brightness = value;

  @override
  double get brushSize => _brushSize;
  @override
  set brushSize(double value) => _brushSize = value;

  @override
  bool get busy => _busy;
  @override
  set busy(bool value) => _busy = value;

  @override
  (String, int, int) get canvasRatio => _canvasRatio;
  @override
  set canvasRatio((String, int, int) value) => _canvasRatio = value;

  @override
  double get canvasZoom => _canvasZoom;
  @override
  set canvasZoom(double value) => _canvasZoom = value;

  @override
  void closePanel() => _closePanel();

  @override
  Future<void> colorFix() => _colorFix();

  @override
  String get colourTab => _colourTab;
  @override
  set colourTab(String value) => _colourTab = value;

  @override
  bool get comparing => _comparing;
  @override
  set comparing(bool value) => _comparing = value;

  @override
  double get contrast => _contrast;
  @override
  set contrast(double value) => _contrast = value;

  @override
  Future<void> crop() => _crop();

  @override
  String get cropPreset => _cropPreset;
  @override
  set cropPreset(String value) => _cropPreset = value;

  @override
  StrokePath? get currentStroke => _currentStroke;
  @override
  set currentStroke(StrokePath? value) => _currentStroke = value;

  @override
  String get curveChannel => _curveChannel;
  @override
  set curveChannel(String value) => _curveChannel = value;

  @override
  Map<String, List<Offset>> get curvePoints => _curvePoints;

  @override
  void deleteActiveLayer() => _deleteActiveLayer();

  @override
  Future<void> denoise() => _denoise();

  @override
  double get denoiseAmount => _denoiseAmount;
  @override
  set denoiseAmount(double value) => _denoiseAmount = value;

  @override
  Color get doodleColor => _doodleColor;
  @override
  set doodleColor(Color value) => _doodleColor = value;

  @override
  void duplicateActiveLayer() => _duplicateActiveLayer();

  @override
  String? get effectSel => _effectSel;
  @override
  set effectSel(String? value) => _effectSel = value;

  @override
  double get effectValue => _effectValue;
  @override
  set effectValue(double value) => _effectValue = value;

  @override
  Future<void> enlarge() => _enlarge();

  @override
  String get expandFill => _expandFill;
  @override
  set expandFill(String value) => _expandFill = value;

  @override
  (String, int, int) get expandRatio => _expandRatio;
  @override
  set expandRatio((String, int, int) value) => _expandRatio = value;

  @override
  double get exposure => _exposure;
  @override
  set exposure(double value) => _exposure = value;

  @override
  double get fade => _fade;
  @override
  set fade(double value) => _fade = value;

  @override
  PhotoFilter get filter => _filter;
  @override
  set filter(PhotoFilter value) => _filter = value;

  @override
  String get filterCategory => _filterCategory;
  @override
  set filterCategory(String value) => _filterCategory = value;

  @override
  double get filterIntensity => _filterIntensity;
  @override
  set filterIntensity(double value) => _filterIntensity = value;

  @override
  Map<PhotoFilter, Uint8List> get filterThumbs => _filterThumbs;
  @override
  set filterThumbs(Map<PhotoFilter, Uint8List> value) => _filterThumbs = value;

  @override
  Future<void> flattenOnColor() => _flattenOnColor();

  @override
  Future<void> flipHorizontal() => _flipHorizontal();

  @override
  Future<void> flipVertical() => _flipVertical();

  @override
  Color get frameColor => _frameColor;
  @override
  set frameColor(Color value) => _frameColor = value;

  @override
  double get frameWidthPct => _frameWidthPct;
  @override
  set frameWidthPct(double value) => _frameWidthPct = value;

  @override
  double get glowBlur => _glowBlur;
  @override
  set glowBlur(double value) => _glowBlur = value;

  @override
  double get grain => _grain;
  @override
  set grain(double value) => _grain = value;

  @override
  double get handleStartAngle => _handleStartAngle;
  @override
  set handleStartAngle(double value) => _handleStartAngle = value;

  @override
  double get handleStartDist => _handleStartDist;
  @override
  set handleStartDist(double value) => _handleStartDist = value;

  @override
  double get handleStartRot => _handleStartRot;
  @override
  set handleStartRot(double value) => _handleStartRot = value;

  @override
  double get handleStartSize => _handleStartSize;
  @override
  set handleStartSize(double value) => _handleStartSize = value;

  @override
  bool get hasTransparency => _hasTransparency;
  @override
  set hasTransparency(bool value) => _hasTransparency = value;

  @override
  double get highlights => _highlights;
  @override
  set highlights(double value) => _highlights = value;

  @override
  Future<void> hqCutout() => _hqCutout();

  @override
  List<List<double>> get hslAdjustments => _hslAdjustments;
  @override
  set hslAdjustments(List<List<double>> value) => _hslAdjustments = value;

  @override
  int get hslSelectedColor => _hslSelectedColor;
  @override
  set hslSelectedColor(int value) => _hslSelectedColor = value;

  @override
  double get hueShift => _hueShift;
  @override
  set hueShift(double value) => _hueShift = value;

  @override
  int get imgHeight => _imgHeight;
  @override
  set imgHeight(int value) => _imgHeight = value;

  @override
  int get imgWidth => _imgWidth;
  @override
  set imgWidth(int value) => _imgWidth = value;

  @override
  List<TextLayerData> get layers => _layers;

  @override
  Future<void> lightFix() => _lightFix();

  @override
  void loadLayer(int index) => _loadLayer(index);

  @override
  Map<String, Uint8List> get lutThumbs => _lutThumbs;
  @override
  set lutThumbs(Map<String, Uint8List> value) => _lutThumbs = value;

  @override
  Color get makeupColor => _makeupColor;
  @override
  set makeupColor(Color value) => _makeupColor = value;

  @override
  double get makeupIntensity => _makeupIntensity;
  @override
  set makeupIntensity(double value) => _makeupIntensity = value;

  @override
  String get makeupMode => _makeupMode;
  @override
  set makeupMode(String value) => _makeupMode = value;

  @override
  bool get maskErase => _maskErase;
  @override
  set maskErase(bool value) => _maskErase = value;

  @override
  List<double> get matrix => _matrix;

  @override
  void openTool(String key) => _openTool(key);

  @override
  File? get originalFile => _originalFile;
  @override
  set originalFile(File? value) => _originalFile = value;

  @override
  Color get outlineColor => _outlineColor;
  @override
  set outlineColor(Color value) => _outlineColor = value;

  @override
  double get outlineWidth => _outlineWidth;
  @override
  set outlineWidth(double value) => _outlineWidth = value;

  @override
  List<OverlayData> get overlays => _overlays;

  @override
  void paintEnd() => _paintEnd();

  @override
  String? get paintMode => _paintMode;
  @override
  set paintMode(String? value) => _paintMode = value;

  @override
  void paintStart(Offset local, Size size) => _paintStart(local, size);

  @override
  void paintUpdate(Offset local, Size size) => _paintUpdate(local, size);

  @override
  Future<void> portraitBokeh() => _portraitBokeh();

  @override
  Uint8List? get previewBytes => _previewBytes;
  @override
  set previewBytes(Uint8List? value) => _previewBytes = value;

  @override
  String? get previewKey => _previewKey;
  @override
  set previewKey(String? value) => _previewKey = value;

  @override
  GlobalKey get previewKey2 => _previewKey2;

  @override
  Future<void> quickRatioCrop(String label, int rx, int ry) => _quickRatioCrop(label, rx, ry);

  @override
  Future<void> removeBackground() => _removeBackground();

  @override
  Future<void> replaceBackgroundColor() => _replaceBackgroundColor();

  @override
  Future<void> replaceBackgroundImage() => _replaceBackgroundImage();

  @override
  Color get replaceBgColor => _replaceBgColor;
  @override
  set replaceBgColor(Color value) => _replaceBgColor = value;

  @override
  void resetHSL() => _resetHSL();

  @override
  Future<void> rotate(int quarterTurns) => _rotate(quarterTurns);

  @override
  double get saturation => _saturation;
  @override
  set saturation(double value) => _saturation = value;

  @override
  void saveActiveLayer() => _saveActiveLayer();

  @override
  void schedulePixelPreview() => _schedulePixelPreview();

  @override
  String get selectedLut => _selectedLut;
  @override
  set selectedLut(String value) => _selectedLut = value;

  @override
  double get shadowBlur => _shadowBlur;
  @override
  set shadowBlur(double value) => _shadowBlur = value;

  @override
  double get shadowDx => _shadowDx;
  @override
  set shadowDx(double value) => _shadowDx = value;

  @override
  double get shadowDy => _shadowDy;
  @override
  set shadowDy(double value) => _shadowDy = value;

  @override
  double get shadowOpacity => _shadowOpacity;
  @override
  set shadowOpacity(double value) => _shadowOpacity = value;

  @override
  double get shadows => _shadows;
  @override
  set shadows(double value) => _shadows = value;

  @override
  Future<void> sharpen() => _sharpen();

  @override
  double get sharpenAmount => _sharpenAmount;
  @override
  set sharpenAmount(double value) => _sharpenAmount = value;

  @override
  double get sharpenDetail => _sharpenDetail;
  @override
  set sharpenDetail(double value) => _sharpenDetail = value;

  @override
  double get straighten => _straighten;
  @override
  set straighten(double value) => _straighten = value;

  @override
  List<StrokePath> get strokes => _strokes;

  @override
  String get styleTab => _styleTab;
  @override
  set styleTab(String value) => _styleTab = value;

  @override
  double get temperature => _temperature;
  @override
  set temperature(double value) => _temperature = value;

  @override
  String get text => _text;
  @override
  set text(String value) => _text = value;

  @override
  TextAlign get textAlign => _textAlign;
  @override
  set textAlign(TextAlign value) => _textAlign = value;

  @override
  bool get textBg => _textBg;
  @override
  set textBg(bool value) => _textBg = value;

  @override
  Color get textBgColor => _textBgColor;
  @override
  set textBgColor(Color value) => _textBgColor = value;

  @override
  bool get textBold => _textBold;
  @override
  set textBold(bool value) => _textBold = value;

  @override
  double get textBoxWidth => _textBoxWidth;
  @override
  set textBoxWidth(double value) => _textBoxWidth = value;

  @override
  Color get textColor => _textColor;
  @override
  set textColor(Color value) => _textColor = value;

  @override
  TextEditingController get textCtrl => _textCtrl;

  @override
  FocusNode get textFocus => _textFocus;

  @override
  String get textFont => _textFont;
  @override
  set textFont(String value) => _textFont = value;

  @override
  bool get textGlow => _textGlow;
  @override
  set textGlow(bool value) => _textGlow = value;

  @override
  Color get textGlowColor => _textGlowColor;
  @override
  set textGlowColor(Color value) => _textGlowColor = value;

  @override
  bool get textItalic => _textItalic;
  @override
  set textItalic(bool value) => _textItalic = value;

  @override
  double get textLetterSpacing => _textLetterSpacing;
  @override
  set textLetterSpacing(double value) => _textLetterSpacing = value;

  @override
  double get textLineSpacing => _textLineSpacing;
  @override
  set textLineSpacing(double value) => _textLineSpacing = value;

  @override
  Offset get textOffset => _textOffset;
  @override
  set textOffset(Offset value) => _textOffset = value;

  @override
  double get textOpacity => _textOpacity;
  @override
  set textOpacity(double value) => _textOpacity = value;

  @override
  bool get textOutline => _textOutline;
  @override
  set textOutline(bool value) => _textOutline = value;

  @override
  Color get textOutlineColor => _textOutlineColor;
  @override
  set textOutlineColor(Color value) => _textOutlineColor = value;

  @override
  double get textOutlineWidth => _textOutlineWidth;
  @override
  set textOutlineWidth(double value) => _textOutlineWidth = value;

  @override
  double get textRotation => _textRotation;
  @override
  set textRotation(double value) => _textRotation = value;

  @override
  bool get textShadow => _textShadow;
  @override
  set textShadow(bool value) => _textShadow = value;

  @override
  Color get textShadowColor => _textShadowColor;
  @override
  set textShadowColor(Color value) => _textShadowColor = value;

  @override
  double get textSize => _textSize;
  @override
  set textSize(double value) => _textSize = value;

  @override
  String get textTab => _textTab;
  @override
  set textTab(String value) => _textTab = value;

  @override
  double get tint => _tint;
  @override
  set tint(double value) => _tint = value;

  @override
  double get vibrance => _vibrance;
  @override
  set vibrance(double value) => _vibrance = value;

  @override
  double get vignette => _vignette;
  @override
  set vignette(double value) => _vignette = value;

  @override
  File? get workingFile => _workingFile;
  @override
  set workingFile(File? value) => _workingFile = value;

}




