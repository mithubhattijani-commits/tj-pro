/// Animation presets (v1.2.0, plan §4) — a DATA-ONLY registry of
/// entrance / emphasis / exit motions for text, headline and ribbon
/// elements.
///
/// No widget code lives here on purpose: pickers (grids of preset
/// chips), preview players and exporters (ASS \move / \fad tags,
/// FFmpeg xfade chains) each interpret the same preset data in their
/// own way. A preset is therefore just:
///
///   - [AnimPreset.id] — stable id for saved settings.
///   - [AnimPreset.name] — picker display name.
///   - [AnimPreset.duration] — default duration of the motion.
///   - [AnimPreset.curveName] — the Flutter curve name the motion
///     follows ('easeOut', 'bounceOut', …), kept as a string so this
///     file stays pure Dart and serialisable.
///   - [AnimPreset.params] — motion parameters (start/end offsets in
///     logical px, scales, opacities, scroll speed, characters per
///     second…) with the exact keys documented per preset below.
///
/// Pure Dart (no Flutter import), like `caption_styles.dart`, so the
/// data can be unit-checked with plain `dart`.
library;

/// One animation preset.
class AnimPreset {
  const AnimPreset({
    required this.id,
    required this.name,
    required this.duration,
    required this.curveName,
    this.params = const {},
    this.nameUr,
  });

  /// Stable id ('fadeIn', 'slideUp', …).
  final String id;

  /// Display name (Latin) for pickers.
  final String name;

  /// Display name in Urdu script, when known.
  final String? nameUr;

  /// Default duration of the motion.
  final Duration duration;

  /// Name of the easing curve ('linear', 'easeOut', 'easeOutBack',
  /// 'bounceOut', …) — a string so this registry stays pure data.
  final String curveName;

  /// Motion parameters. Keys used across the presets:
  ///   - fromOpacity / toOpacity (0..1)
  ///   - dx / dy — start offset in logical px (slides)
  ///   - fromScale / toScale — scale factor (pop / zoom / pulse peak
  ///     is `toScale` on the first half, see `pulse`)
  ///   - charsPerSecond — typewriter reveal rate
  ///   - flashes — flashLabel blink count
  ///   - speedPxPerSecond — ticker scroll speed (scrollLeft/Right)
  ///   - cycles — pulse repeat count within the element's lifetime
  final Map<String, double> params;
}

/// The preset registry, in picker order.
class AnimPresets {
  AnimPresets._();

  static const AnimPreset none = AnimPreset(
    id: 'none',
    name: 'None',
    nameUr: 'کوئی نہیں',
    duration: Duration.zero,
    curveName: 'linear',
  );

  static const AnimPreset fadeIn = AnimPreset(
    id: 'fadeIn',
    name: 'Fade In',
    nameUr: 'فیڈ اِن',
    duration: Duration(milliseconds: 400),
    curveName: 'easeOut',
    params: {'fromOpacity': 0, 'toOpacity': 1},
  );

  static const AnimPreset fadeOut = AnimPreset(
    id: 'fadeOut',
    name: 'Fade Out',
    nameUr: 'فیڈ آؤٹ',
    duration: Duration(milliseconds: 400),
    curveName: 'easeIn',
    params: {'fromOpacity': 1, 'toOpacity': 0},
  );

  static const AnimPreset slideUp = AnimPreset(
    id: 'slideUp',
    name: 'Slide Up',
    nameUr: 'سلائیڈ اپ',
    duration: Duration(milliseconds: 450),
    curveName: 'easeOutCubic',
    params: {'dx': 0, 'dy': 40, 'fromOpacity': 0, 'toOpacity': 1},
  );

  static const AnimPreset slideDown = AnimPreset(
    id: 'slideDown',
    name: 'Slide Down',
    nameUr: 'سلائیڈ ڈاؤن',
    duration: Duration(milliseconds: 450),
    curveName: 'easeOutCubic',
    params: {'dx': 0, 'dy': -40, 'fromOpacity': 0, 'toOpacity': 1},
  );

  static const AnimPreset slideLeft = AnimPreset(
    id: 'slideLeft',
    name: 'Slide Left',
    nameUr: 'سلائیڈ لیفٹ',
    duration: Duration(milliseconds: 450),
    curveName: 'easeOutCubic',
    params: {'dx': 60, 'dy': 0, 'fromOpacity': 0, 'toOpacity': 1},
  );

  static const AnimPreset slideRight = AnimPreset(
    id: 'slideRight',
    name: 'Slide Right',
    nameUr: 'سلائیڈ رائٹ',
    duration: Duration(milliseconds: 450),
    curveName: 'easeOutCubic',
    params: {'dx': -60, 'dy': 0, 'fromOpacity': 0, 'toOpacity': 1},
  );

  static const AnimPreset popIn = AnimPreset(
    id: 'popIn',
    name: 'Pop In',
    nameUr: 'پاپ اِن',
    duration: Duration(milliseconds: 350),
    curveName: 'easeOutBack',
    params: {'fromScale': 0.6, 'toScale': 1, 'fromOpacity': 0, 'toOpacity': 1},
  );

  static const AnimPreset zoomIn = AnimPreset(
    id: 'zoomIn',
    name: 'Zoom In',
    nameUr: 'زوم اِن',
    duration: Duration(milliseconds: 500),
    curveName: 'easeOutCubic',
    params: {'fromScale': 1.4, 'toScale': 1, 'fromOpacity': 0, 'toOpacity': 1},
  );

  static const AnimPreset bounceIn = AnimPreset(
    id: 'bounceIn',
    name: 'Bounce In',
    nameUr: 'باؤنس اِن',
    duration: Duration(milliseconds: 700),
    curveName: 'bounceOut',
    params: {'fromScale': 0.3, 'toScale': 1, 'fromOpacity': 0, 'toOpacity': 1},
  );

  /// Words/characters appear one by one and stay — pairs with the
  /// caption `typewriter` animation in `caption_styles.dart`.
  static const AnimPreset typewriter = AnimPreset(
    id: 'typewriter',
    name: 'Typewriter',
    nameUr: 'ٹائپ رائٹر',
    duration: Duration(milliseconds: 1200),
    curveName: 'linear',
    params: {'charsPerSecond': 14},
  );

  /// Breaking-news label blink: opacity flashes before settling —
  /// the rotating/flashing "BREAKING NEWS" label look from the
  /// approved template spec.
  static const AnimPreset flashLabel = AnimPreset(
    id: 'flashLabel',
    name: 'Flash Label',
    nameUr: 'فلیش لیبل',
    duration: Duration(milliseconds: 900),
    curveName: 'linear',
    params: {'flashes': 3, 'fromOpacity': 0, 'toOpacity': 1},
  );

  /// Continuous ticker scroll toward the left (Latin tickers).
  static const AnimPreset scrollLeft = AnimPreset(
    id: 'scrollLeft',
    name: 'Scroll Left',
    nameUr: 'اسکرول لیفٹ',
    duration: Duration(seconds: 10),
    curveName: 'linear',
    params: {'speedPxPerSecond': 90},
  );

  /// Continuous ticker scroll toward the right (Urdu tickers — the
  /// direction choice from the approved template spec).
  static const AnimPreset scrollRight = AnimPreset(
    id: 'scrollRight',
    name: 'Scroll Right',
    nameUr: 'اسکرول رائٹ',
    duration: Duration(seconds: 10),
    curveName: 'linear',
    params: {'speedPxPerSecond': 90},
  );

  /// Gentle scale pulse for emphasis (live bugs, "LIVE" labels).
  static const AnimPreset pulse = AnimPreset(
    id: 'pulse',
    name: 'Pulse',
    nameUr: 'پلس',
    duration: Duration(milliseconds: 900),
    curveName: 'easeInOut',
    params: {'fromScale': 1, 'toScale': 1.08, 'cycles': 3},
  );

  /// Every preset, in picker order (`none` last — it is the
  /// absence of a motion, not a look).
  static const List<AnimPreset> all = [
    fadeIn,
    fadeOut,
    slideUp,
    slideDown,
    slideLeft,
    slideRight,
    popIn,
    zoomIn,
    bounceIn,
    typewriter,
    flashLabel,
    scrollLeft,
    scrollRight,
    pulse,
    none,
  ];

  /// Lookup by [AnimPreset.id]; unknown ids fall back to [none].
  static AnimPreset byId(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => none);
}
