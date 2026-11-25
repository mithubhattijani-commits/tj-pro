/// Logo Parts — ELEMENT-BASED MODEL (redesign Build 1,
/// 2026-11-25; spec: LOGO-PARTS-REDESIGN-2026-11-25.md).
///
/// The user REJECTED the old automatic split (colour clusters
/// cutting the whole picture into slices that all turned
/// together). The professional model — and the user's own
/// words — is: **a part is one of the logo's own DESIGN
/// ELEMENTS**: a text block WITH its background/box is one
/// part (the "NEWS" box, the "HD" box, "UTV", the frame),
/// and every element animates around ITS OWN centre.
///
/// So in this model a [LogoPart] is a BOX over the master
/// logo plus the pixels inside that box. The master image is
/// never cut or modified; a part's texture is its box region
/// of the master, and its pivot is the box's centre. Boxes
/// come from an automatic PROPOSAL ([proposeLogoBoxes] —
/// connected regions + a word-joining rule + a container
/// rule) that is only a starting point, and from boxes the
/// user draws and adjusts himself.
///
/// Paid save (unchanged): working settings are session-only;
/// saving costs [kLogoPartsSavePriceCoins] coins once and
/// stays usable exactly [kLogoPartsSaveValidity] (7 days),
/// then it is gone. Saves written by the OLD slice model
/// carry no box and cannot map to elements — [decodeLogoParts]
/// drops them, so an old save simply starts with no parts
/// (the logo itself and everything else stay intact).
library;

import 'dart:convert';
import 'dart:typed_data';

/// Coins charged per parts save (one charge per save action).
const int kLogoPartsSavePriceCoins = 300;

/// How long a paid save stays usable.
const Duration kLogoPartsSaveValidity = Duration(days: 7);

/// Coin ledger reason for the parts save.
const String kLogoPartsSaveReason = 'logo_parts_save';

/// The master animation loop for parts (seconds). Part speeds
/// snap to its divisors so every part completes whole
/// revolutions inside one loop and the loop is seamless.
const double kLogoPartsLoopSec = 12;

/// Speed choices (seconds per revolution) — divisors of the
/// master loop.
const List<double> kLogoPartSpeeds = [2, 3, 4, 6, 12];

/// Rotation styles (point #23): 'flat' is the in-plane 2D
/// spin (the part turns like a wheel around its own centre);
/// '3d' turns the part around its vertical axis, cube-style —
/// it thins out edge-on and comes back, so even a round part's
/// rotation is clearly visible. Both styles are honoured by
/// the previews and the export frame renderer through the one
/// shared painter (LogoPartsService.paintParts).
const String kLogoPartStyleFlat = 'flat';
const String kLogoPartStyle3d = '3d';

/// Normalises a stored style value — anything unknown reads
/// as 'flat'.
String normalizeLogoPartStyle(String? raw) =>
    raw == kLogoPartStyle3d ? kLogoPartStyle3d : kLogoPartStyleFlat;

/// Motion modes (Option 20, redesign Build 2): 'spin' is the
/// Poora chakkar — whole revolutions at [LogoPart.speedSec]
/// per turn; 'swing' is the Jhoolna — a pendulum swinging
/// ±[LogoPart.swingDeg] around the pivot, one full
/// back-and-forth per [LogoPart.speedSec].
const String kLogoPartMotionSpin = 'spin';
const String kLogoPartMotionSwing = 'swing';

/// Normalises a stored motion value — anything unknown
/// reads as 'spin' (the Build 1 behaviour).
String normalizeLogoPartMotion(String? raw) =>
    raw == kLogoPartMotionSwing ? kLogoPartMotionSwing : kLogoPartMotionSpin;

/// Pulse (Option 23, redesign Build 2): a part breathes —
/// its scale swells and settles on this fixed period
/// (a divisor of the 12s master loop, so the loop stays
/// seamless). Independent of the rotate switch: a still
/// part can still breathe.
const double kLogoPartPulsePeriodSec = 3;

/// The strongest pulse swell (scale fraction at strength 1).
const double kLogoPartPulseMaxAmp = 0.18;

/// Base plate modes (Option 33): what shows UNDER the parts.
/// 'cut' (Build 1's default) — the master stays as a base
/// with every part's box erased, so a part that turns away
/// reveals whatever is behind the logo; 'none' — no base at
/// all, only parts (+ glow); 'ghost' — the whole original
/// logo sits still underneath and the parts turn on top of
/// it (a deliberate double image).
const String kLogoPartsBaseCut = 'cut';
const String kLogoPartsBaseNone = 'none';
const String kLogoPartsBaseGhost = 'ghost';

/// Normalises a stored base value — anything unknown reads
/// as 'cut' (the Build 1 behaviour).
String normalizeLogoPartsBase(String? raw) => raw == kLogoPartsBaseNone
    ? kLogoPartsBaseNone
    : raw == kLogoPartsBaseGhost
        ? kLogoPartsBaseGhost
        : kLogoPartsBaseCut;

/// Glow motion modes (Option 32): 'static' — the glow just
/// sits there; 'pulse' — it breathes (its strength swells
/// and settles); 'spin' — it turns very slowly around the
/// logo's centre (one turn per master loop).
const String kLogoGlowMotionStatic = 'static';
const String kLogoGlowMotionPulse = 'pulse';
const String kLogoGlowMotionSpin = 'spin';

/// Normalises a stored glow-motion value — anything unknown
/// reads as 'static'.
String normalizeLogoGlowMotion(String? raw) => raw == kLogoGlowMotionPulse
    ? kLogoGlowMotionPulse
    : raw == kLogoGlowMotionSpin
        ? kLogoGlowMotionSpin
        : kLogoGlowMotionStatic;

/// Narmi (Easing, Option 27 — redesign Build 3): how an
/// OSCILLATING motion (a part's Swing and Pulse, and the
/// glow's Pulse) moves through its cycle. 'smooth' (Narm)
/// is the gentle sine — slow at the turnarounds, the
/// professional default, and EXACTLY the motion Builds 1–2
/// shipped, so it is the default everywhere. 'linear'
/// (Barabar) is the constant-speed triangle — mechanical,
/// no softening at the ends. Whole revolutions (Poora
/// chakkar) are never eased: a looped spin must turn at a
/// constant rate or the loop itself would pulse.
const String kLogoEasingLinear = 'linear';
const String kLogoEasingSmooth = 'smooth';

/// Normalises a stored easing value — anything unknown
/// reads as 'smooth' (the Builds 1–2 behaviour).
String normalizeLogoEasing(String? raw) =>
    raw == kLogoEasingLinear ? kLogoEasingLinear : kLogoEasingSmooth;

/// Export frame sizes (Option 39 — redesign Build 3): the
/// parts green-screen export renders square frames at 512
/// (halka — the Builds 1–2 behaviour, the default) or 1024
/// (saaf — bigger, sharper frames).
const int kLogoPartsExportSizeDefault = 512;
const int kLogoPartsExportSizeLarge = 1024;

/// Normalises a stored export size — anything but 1024
/// reads as the 512 default.
int normalizeLogoPartsExportSize(int? raw) =>
    raw == kLogoPartsExportSizeLarge
        ? kLogoPartsExportSizeLarge
        : kLogoPartsExportSizeDefault;

/// Keying mazbooti (Option 3 — redesign Build 3): the Logo
/// tab's slider (0..1) drives the tolerance of the border
/// keying that [proposeLogoBoxes] runs on a solid-background
/// logo. Halka (low) = only near-exact background goes, the
/// element's edges stay safe; zyada (high) = more of the
/// near-background fringe goes too. The DEFAULT strength
/// maps to tolerance 42 — the exact tolerance Builds 1–2
/// always used — so nothing changes until the user moves
/// the slider.
const double kLogoKeyingStrengthDefault = 0.32;

/// The keying tolerance (RGB distance) for a strength.
double logoKeyingToleranceForStrength(double strength) =>
    10 + strength.clamp(0, 1).toDouble() * 100;

/// Snaps an arbitrary speed to the nearest allowed choice.
double snapLogoPartSpeed(double sec) {
  var best = kLogoPartSpeeds.first;
  var bestDiff = (sec - best).abs();
  for (final s in kLogoPartSpeeds.skip(1)) {
    final d = (sec - s).abs();
    if (d < bestDiff) {
      best = s;
      bestDiff = d;
    }
  }
  return best;
}

/// One part's BOX over the master logo, in fractions of the
/// logo frame (0..1). The box IS the element's definition:
/// everything inside it (text + its background block) is one
/// part, and the box's centre is the part's pivot.
class LogoBox {
  const LogoBox({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  /// A box forced inside the unit square with a sane minimum
  /// size — used when reading stored/user-dragged values.
  factory LogoBox.clamped({
    required double x,
    required double y,
    required double w,
    required double h,
  }) {
    final cw = w.clamp(0.02, 1.0);
    final ch = h.clamp(0.02, 1.0);
    return LogoBox(
      x: x.clamp(0.0, 1.0 - cw),
      y: y.clamp(0.0, 1.0 - ch),
      w: cw,
      h: ch,
    );
  }

  final double x;
  final double y;
  final double w;
  final double h;

  double get right => x + w;
  double get bottom => y + h;
  double get centreX => x + w / 2;
  double get centreY => y + h / 2;
  double get area => w * h;

  bool get isValid => w >= 0.02 && h >= 0.02;

  bool containsPoint(double px, double py) =>
      px >= x && px <= right && py >= y && py <= bottom;

  /// The fraction of THIS box's area that [other] covers
  /// (1.0 = this box lies entirely inside [other]).
  double coveredFractionBy(LogoBox other) {
    final ix = (right < other.right ? right : other.right) -
        (x > other.x ? x : other.x);
    final iy = (bottom < other.bottom ? bottom : other.bottom) -
        (y > other.y ? y : other.y);
    if (ix <= 0 || iy <= 0 || area <= 0) return 0;
    return (ix * iy) / area;
  }

  LogoBox union(LogoBox other) {
    final nx = x < other.x ? x : other.x;
    final ny = y < other.y ? y : other.y;
    final nr = right > other.right ? right : other.right;
    final nb = bottom > other.bottom ? bottom : other.bottom;
    return LogoBox(x: nx, y: ny, w: nr - nx, h: nb - ny);
  }

  /// Grows the box by [p] on every side, clamped to the unit
  /// square (proposal boxes get a hair of breathing room so a
  /// crop never shaves an element's edge).
  LogoBox pad(double p) => LogoBox.clamped(
        x: x - p,
        y: y - p,
        w: w + 2 * p,
        h: h + 2 * p,
      );

  LogoBox copyWith({double? x, double? y, double? w, double? h}) =>
      LogoBox(x: x ?? this.x, y: y ?? this.y, w: w ?? this.w, h: h ?? this.h);

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};

  /// Null when the stored value is not a usable box — old
  /// (slice-model) saves have no box at all and read as null.
  static LogoBox? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final x = (raw['x'] as num?)?.toDouble();
    final y = (raw['y'] as num?)?.toDouble();
    final w = (raw['w'] as num?)?.toDouble();
    final h = (raw['h'] as num?)?.toDouble();
    if (x == null || y == null || w == null || h == null) return null;
    final box = LogoBox.clamped(x: x, y: y, w: w, h: h);
    return box.isValid ? box : null;
  }

  @override
  bool operator ==(Object other) =>
      other is LogoBox &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);

  @override
  String toString() =>
      'LogoBox(x:${x.toStringAsFixed(3)}, y:${y.toStringAsFixed(3)}, '
      'w:${w.toStringAsFixed(3)}, h:${h.toStringAsFixed(3)})';
}

/// One logo part (element): a [box] over the master logo at
/// [sourcePath], plus its own rotation settings. The parts
/// list's order IS the layer order (first = painted first =
/// at the back). Serialisable (the paid-save payload).
class LogoPart {
  LogoPart({
    required this.id,
    required this.name,
    required this.sourcePath,
    required this.box,
    this.rotate = true,
    this.direction = 'cw',
    double speedSec = 6,
    String rotationStyle = kLogoPartStyleFlat,
    this.delaySec = 0,
    this.pivotDx = 0,
    this.pivotDy = 0,
    String motionMode = kLogoPartMotionSpin,
    double swingDeg = 30,
    this.pulseOn = false,
    double pulseStrength = 0.5,
    String easing = kLogoEasingSmooth,
  })  : speedSec = snapLogoPartSpeed(speedSec),
        rotationStyle = normalizeLogoPartStyle(rotationStyle),
        motionMode = normalizeLogoPartMotion(motionMode),
        swingDeg = swingDeg.clamp(5, 80).toDouble(),
        pulseStrength = pulseStrength.clamp(0, 1).toDouble(),
        easing = normalizeLogoEasing(easing);

  final String id;
  String name;

  /// The master logo file this part's box looks into. Every
  /// part of one logo shares the same master — the image
  /// itself is never modified.
  final String sourcePath;

  /// The element's box over the master (fractions).
  LogoBox box;

  bool rotate;

  /// 'cw' or 'ccw'.
  String direction;

  /// Seconds per revolution (snapped to [kLogoPartSpeeds]).
  double speedSec;

  /// Rotation style: [kLogoPartStyleFlat] or [kLogoPartStyle3d].
  String rotationStyle;

  /// Start waqfa (Option 24): the part's cycle is offset by
  /// this many seconds — in the seamless 12s loop a delay is
  /// a phase offset, so parts start their chakkar staggered
  /// and the loop never jumps.
  double delaySec;

  /// Pivot offset from the box centre (frame fractions,
  /// Option 22). Zero = the pivot IS the box centre (the
  /// professional default). The offset rides along when the
  /// box moves, so the pivot stays glued to the same point
  /// of the element.
  double pivotDx;
  double pivotDy;

  /// Motion mode (Option 20, Build 2): [kLogoPartMotionSpin]
  /// (Poora chakkar) or [kLogoPartMotionSwing] (Jhoolna).
  String motionMode;

  /// Swing amplitude in degrees (Option 21) — the pendulum
  /// swings ±this around the pivot. Only used in swing mode.
  double swingDeg;

  /// Pulse (Option 23, Build 2): the part gently breathes
  /// (scale swell on [kLogoPartPulsePeriodSec]) — on/off.
  bool pulseOn;

  /// Pulse strength 0..1 — how big the breathing swell is.
  double pulseStrength;

  /// Narmi (Option 27, Build 3): [kLogoEasingSmooth] (Narm —
  /// the default, the Builds 1–2 sine) or
  /// [kLogoEasingLinear] (Barabar — constant speed). Applies
  /// to this part's Swing and Pulse; the Poora chakkar spin
  /// is never eased.
  String easing;

  /// The pivot — the box's centre plus the user's offset.
  double get centreX => box.centreX + pivotDx;
  double get centreY => box.centreY + pivotDy;
  double get pivotX => centreX;
  double get pivotY => centreY;

  Map<String, dynamic> toJson() => {
        'model': 2,
        'id': id,
        'name': name,
        'sourcePath': sourcePath,
        'box': box.toJson(),
        'rotate': rotate,
        'direction': direction,
        'speedSec': speedSec,
        'rotationStyle': rotationStyle,
        'delaySec': delaySec,
        'pivotDx': pivotDx,
        'pivotDy': pivotDy,
        'motionMode': motionMode,
        'swingDeg': swingDeg,
        'pulseOn': pulseOn,
        'pulseStrength': pulseStrength,
        'easing': easing,
      };

  factory LogoPart.fromJson(Map<String, dynamic> j) => LogoPart(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? 'Part',
        sourcePath: j['sourcePath'] as String? ?? '',
        box: LogoBox.fromJson(j['box']) ?? const LogoBox(x: 0, y: 0, w: 0, h: 0),
        rotate: j['rotate'] as bool? ?? true,
        direction: j['direction'] as String? ?? 'cw',
        speedSec: (j['speedSec'] as num?)?.toDouble() ?? 6,
        rotationStyle: j['rotationStyle'] as String? ?? kLogoPartStyleFlat,
        delaySec: (j['delaySec'] as num?)?.toDouble() ?? 0,
        pivotDx: (j['pivotDx'] as num?)?.toDouble() ?? 0,
        pivotDy: (j['pivotDy'] as num?)?.toDouble() ?? 0,
        // Build 2 fields — Build 1 saves do not carry them,
        // so they land on the defaults: Poora chakkar, pulse
        // off (the Build 1 behaviour, exactly).
        motionMode: j['motionMode'] as String? ?? kLogoPartMotionSpin,
        swingDeg: (j['swingDeg'] as num?)?.toDouble() ?? 30,
        pulseOn: j['pulseOn'] as bool? ?? false,
        pulseStrength: (j['pulseStrength'] as num?)?.toDouble() ?? 0.5,
        // Build 3 field — Build 1/2 saves do not carry it,
        // so it lands on 'smooth' (their exact motion).
        easing: j['easing'] as String? ?? kLogoEasingSmooth,
      );

  LogoPart copyWith({
    String? name,
    LogoBox? box,
    bool? rotate,
    String? direction,
    double? speedSec,
    String? rotationStyle,
    double? delaySec,
    double? pivotDx,
    double? pivotDy,
    String? motionMode,
    double? swingDeg,
    bool? pulseOn,
    double? pulseStrength,
    String? easing,
  }) =>
      LogoPart(
        id: id,
        name: name ?? this.name,
        sourcePath: sourcePath,
        box: box ?? this.box,
        rotate: rotate ?? this.rotate,
        direction: direction ?? this.direction,
        speedSec: speedSec ?? this.speedSec,
        rotationStyle: rotationStyle ?? this.rotationStyle,
        delaySec: delaySec ?? this.delaySec,
        pivotDx: pivotDx ?? this.pivotDx,
        pivotDy: pivotDy ?? this.pivotDy,
        motionMode: motionMode ?? this.motionMode,
        swingDeg: swingDeg ?? this.swingDeg,
        pulseOn: pulseOn ?? this.pulseOn,
        pulseStrength: pulseStrength ?? this.pulseStrength,
        easing: easing ?? this.easing,
      );
}

/// Serialises the working parts list (the paid-save payload).
String encodeLogoParts(List<LogoPart> parts) =>
    jsonEncode(parts.map((e) => e.toJson()).toList());

/// Parses a saved payload back; corrupt/absent → empty.
///
/// ELEMENT-MODEL RULE: an entry is only a part when it has a
/// source AND a valid box. Payloads saved by the old slice
/// model have neither a box nor a source — they are dropped,
/// so an old save loads as NO parts (never a crash, never a
/// phantom part); the user simply proposes/draws boxes anew.
List<LogoPart> decodeLogoParts(String json) {
  if (json.isEmpty) return const [];
  try {
    final raw = jsonDecode(json);
    if (raw is! List) return const [];
    return _partsFromRawList(raw);
  } catch (_) {
    return const [];
  }
}

List<LogoPart> _partsFromRawList(List<dynamic> raw) => raw
    .whereType<Map>()
    .map((m) => LogoPart.fromJson(m.cast<String, dynamic>()))
    .where((p) => p.sourcePath.isNotEmpty && p.box.isValid)
    .toList();

/// The SCENE around the parts (redesign Build 2): the glow
/// layer behind the whole logo (Options 28–32) and the base
/// plate under the parts (Option 33). The glow is GENERATED
/// (the logo's silhouette, blurred + tinted) — never cut out
/// of the image. Every field has a Build-1-compatible
/// default, so a Build 1 save (which carries no scene at
/// all) loads as: glow off, base = cut.
class LogoPartsScene {
  LogoPartsScene({
    this.glowOn = false,
    this.glowColorArgb,
    double glowIntensity = 0.75,
    double glowSpread = 0.5,
    String glowMotion = kLogoGlowMotionStatic,
    String baseMode = kLogoPartsBaseCut,
    this.sweepOn = false,
    double sweepSpeed = 0.5,
    String easing = kLogoEasingSmooth,
    int exportSize = kLogoPartsExportSizeDefault,
    double keyingStrength = kLogoKeyingStrengthDefault,
  })  : glowIntensity = glowIntensity.clamp(0, 1).toDouble(),
        glowSpread = glowSpread.clamp(0, 1).toDouble(),
        glowMotion = normalizeLogoGlowMotion(glowMotion),
        baseMode = normalizeLogoPartsBase(baseMode),
        sweepSpeed = sweepSpeed.clamp(0, 1).toDouble(),
        easing = normalizeLogoEasing(easing),
        exportSize = normalizeLogoPartsExportSize(exportSize),
        keyingStrength = keyingStrength.clamp(0, 1).toDouble();

  /// Glow layer on/off (Option 28).
  bool glowOn;

  /// The glow's colour as ARGB (Option 29) — null = AUTO:
  /// the logo's own dominant colour, resolved at render time
  /// by [dominantLogoColorArgb].
  int? glowColorArgb;

  /// Glow strength 0..1 (Option 30) — how bright/opaque the
  /// glow layer is.
  double glowIntensity;

  /// Glow spread 0..1 (Option 31) — how far the glow reaches
  /// (blur + a slight growth of the silhouette).
  double glowSpread;

  /// Glow motion (Option 32): [kLogoGlowMotionStatic],
  /// [kLogoGlowMotionPulse] or [kLogoGlowMotionSpin].
  String glowMotion;

  /// Base plate (Option 33): [kLogoPartsBaseCut],
  /// [kLogoPartsBaseNone] or [kLogoPartsBaseGhost].
  String baseMode;

  /// Roshni ki lehar — Light Sweep (Option 34, Build 3): a
  /// band of light crosses the whole logo, channel-ident
  /// style. Drawn OVER the parts, masked to the logo's
  /// silhouette, through the same shared painter.
  bool sweepOn;

  /// The sweep's speed 0..1 (Option 34): how many passes
  /// cross the logo inside one 12s loop (1 at 0, 4 at 1 —
  /// always a whole number of passes, so the loop stays
  /// seamless at any slider position).
  double sweepSpeed;

  /// The scene's Narmi (Option 27, Build 3) — governs the
  /// GLOW's Pulse breathing (the scene-level oscillating
  /// motion). Per-part swing/pulse carry their own easing
  /// on [LogoPart.easing].
  String easing;

  /// Export frame size (Option 39, Build 3): 512 (halka,
  /// the default — the Builds 1–2 behaviour) or 1024
  /// (saaf). Honoured by the parts green-screen export.
  int exportSize;

  /// Keying mazbooti (Option 3, Build 3): the strength the
  /// Logo tab's slider sets — drives the tolerance of the
  /// border keying when parts are (re)proposed for a
  /// solid-background logo. The default reproduces the
  /// exact tolerance Builds 1–2 always used.
  double keyingStrength;

  LogoPartsScene copyWith({
    bool? glowOn,
    int? glowColorArgb,
    bool clearGlowColor = false,
    double? glowIntensity,
    double? glowSpread,
    String? glowMotion,
    String? baseMode,
    bool? sweepOn,
    double? sweepSpeed,
    String? easing,
    int? exportSize,
    double? keyingStrength,
  }) =>
      LogoPartsScene(
        glowOn: glowOn ?? this.glowOn,
        glowColorArgb:
            clearGlowColor ? null : (glowColorArgb ?? this.glowColorArgb),
        glowIntensity: glowIntensity ?? this.glowIntensity,
        glowSpread: glowSpread ?? this.glowSpread,
        glowMotion: glowMotion ?? this.glowMotion,
        baseMode: baseMode ?? this.baseMode,
        sweepOn: sweepOn ?? this.sweepOn,
        sweepSpeed: sweepSpeed ?? this.sweepSpeed,
        easing: easing ?? this.easing,
        exportSize: exportSize ?? this.exportSize,
        keyingStrength: keyingStrength ?? this.keyingStrength,
      );

  Map<String, dynamic> toJson() => {
        'glowOn': glowOn,
        'glowColorArgb': glowColorArgb,
        'glowIntensity': glowIntensity,
        'glowSpread': glowSpread,
        'glowMotion': glowMotion,
        'baseMode': baseMode,
        'sweepOn': sweepOn,
        'sweepSpeed': sweepSpeed,
        'easing': easing,
        'exportSize': exportSize,
        'keyingStrength': keyingStrength,
      };

  /// Defaults for anything missing — a Build 1 payload has
  /// no scene map at all and reads as all-defaults; a
  /// Build 2 scene lacks the Build 3 fields and reads them
  /// as: sweep off, easing Narm (smooth), export 512,
  /// keying at the Builds 1–2 strength.
  factory LogoPartsScene.fromJson(Object? raw) {
    if (raw is! Map) return LogoPartsScene();
    final j = raw.cast<String, dynamic>();
    return LogoPartsScene(
      glowOn: j['glowOn'] as bool? ?? false,
      glowColorArgb: (j['glowColorArgb'] as num?)?.toInt(),
      glowIntensity: (j['glowIntensity'] as num?)?.toDouble() ?? 0.75,
      glowSpread: (j['glowSpread'] as num?)?.toDouble() ?? 0.5,
      glowMotion: j['glowMotion'] as String? ?? kLogoGlowMotionStatic,
      baseMode: j['baseMode'] as String? ?? kLogoPartsBaseCut,
      sweepOn: j['sweepOn'] as bool? ?? false,
      sweepSpeed: (j['sweepSpeed'] as num?)?.toDouble() ?? 0.5,
      easing: j['easing'] as String? ?? kLogoEasingSmooth,
      exportSize:
          (j['exportSize'] as num?)?.toInt() ?? kLogoPartsExportSizeDefault,
      keyingStrength: (j['keyingStrength'] as num?)?.toDouble() ??
          kLogoKeyingStrengthDefault,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LogoPartsScene &&
      other.glowOn == glowOn &&
      other.glowColorArgb == glowColorArgb &&
      other.glowIntensity == glowIntensity &&
      other.glowSpread == glowSpread &&
      other.glowMotion == glowMotion &&
      other.baseMode == baseMode &&
      other.sweepOn == sweepOn &&
      other.sweepSpeed == sweepSpeed &&
      other.easing == easing &&
      other.exportSize == exportSize &&
      other.keyingStrength == keyingStrength;

  @override
  int get hashCode => Object.hash(
        glowOn,
        glowColorArgb,
        glowIntensity,
        glowSpread,
        glowMotion,
        baseMode,
        sweepOn,
        sweepSpeed,
        easing,
        exportSize,
        keyingStrength,
      );
}

/// What a paid parts save holds (Build 2): the parts AND
/// their scene. [decodeLogoPartsSave] also reads the Build 1
/// payload (a bare parts list) — its parts load and the
/// scene lands on the defaults (glow off, base cut).
class LogoPartsSaveData {
  const LogoPartsSaveData({required this.parts, required this.scene});

  final List<LogoPart> parts;
  final LogoPartsScene scene;
}

/// Serialises a paid save (parts + scene) — the payload the
/// save flow stores. The price/validity flow itself is
/// unchanged (300 coins / 7 days).
String encodeLogoPartsSave(List<LogoPart> parts, LogoPartsScene scene) =>
    jsonEncode({
      'model': 2,
      'parts': parts.map((e) => e.toJson()).toList(),
      'scene': scene.toJson(),
    });

/// Parses a paid save of EITHER era:
/// - Build 2 object payload → parts + scene;
/// - Build 1 bare-list payload → parts + default scene;
/// - the old slice model / junk → no parts, default scene.
LogoPartsSaveData decodeLogoPartsSave(String json) {
  final fallback = LogoPartsSaveData(parts: const [], scene: LogoPartsScene());
  if (json.isEmpty) return fallback;
  try {
    final raw = jsonDecode(json);
    if (raw is List) {
      return LogoPartsSaveData(
        parts: _partsFromRawList(raw),
        scene: LogoPartsScene(),
      );
    }
    if (raw is Map) {
      final j = raw.cast<String, dynamic>();
      final rawParts = j['parts'];
      return LogoPartsSaveData(
        parts: rawParts is List ? _partsFromRawList(rawParts) : const [],
        scene: LogoPartsScene.fromJson(j['scene']),
      );
    }
    return fallback;
  } catch (_) {
    return fallback;
  }
}

/// The dominant colour of a logo's RGBA pixels, as ARGB —
/// the AUTO glow colour (Option 29). Opaque pixels vote with
/// their saturation as weight, so a vivid brand colour beats
/// a large dull background block; near-grey pixels still
/// count a little, so a grey logo still gets a colour. Null
/// when the image has no opaque pixels at all.
int? dominantLogoColorArgb(Uint8List rgba) {
  if (rgba.length < 4) return null;
  var wr = 0.0, wg = 0.0, wb = 0.0, wSum = 0.0;
  var sr = 0.0, sg = 0.0, sb = 0.0;
  var count = 0;
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    final r = rgba[i].toDouble();
    final g = rgba[i + 1].toDouble();
    final b = rgba[i + 2].toDouble();
    count++;
    sr += r;
    sg += g;
    sb += b;
    final mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
    final mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
    final sat = mx <= 0 ? 0.0 : (mx - mn) / mx;
    final w = 0.05 + sat;
    wr += r * w;
    wg += g * w;
    wb += b * w;
    wSum += w;
  }
  if (count == 0) return null;
  final r = wSum > 0 ? wr / wSum : sr / count;
  final g = wSum > 0 ? wg / wSum : sg / count;
  final b = wSum > 0 ? wb / wSum : sb / count;
  return (0xFF << 24) |
      (r.round().clamp(0, 255) << 16) |
      (g.round().clamp(0, 255) << 8) |
      b.round().clamp(0, 255);
}

/// The state of a paid parts save at [nowMs].
enum LogoPartsSaveState { never, active, expired }

LogoPartsSaveState logoPartsSaveState(int savedAtMs, int nowMs) {
  if (savedAtMs <= 0) return LogoPartsSaveState.never;
  final expiry = savedAtMs + kLogoPartsSaveValidity.inMilliseconds;
  return nowMs < expiry
      ? LogoPartsSaveState.active
      : LogoPartsSaveState.expired;
}

/// Whole days remaining on an active save (0 when not active).
int logoPartsSaveDaysLeft(int savedAtMs, int nowMs) {
  if (logoPartsSaveState(savedAtMs, nowMs) != LogoPartsSaveState.active) {
    return 0;
  }
  final leftMs =
      savedAtMs + kLogoPartsSaveValidity.inMilliseconds - nowMs;
  return (leftMs / Duration.millisecondsPerDay).ceil();
}

/// A cache variant string for parts frame generation — changes
/// whenever any part setting, box or the source logo changes.
String logoPartsVariantKey({
  required String sourceStamp,
  required List<LogoPart> parts,
  LogoPartsScene? scene,
}) {
  final b = StringBuffer(sourceStamp);
  for (final part in parts) {
    b.write(
      '|${part.id}:${part.sourcePath}:${part.box.x},${part.box.y},'
      '${part.box.w},${part.box.h}:${part.rotate ? 1 : 0}:${part.direction}'
      ':${part.speedSec}:${part.rotationStyle}:${part.delaySec}'
      ':${part.pivotDx},${part.pivotDy}:${part.motionMode}:${part.swingDeg}'
      ':${part.pulseOn ? 1 : 0}:${part.pulseStrength}:${part.easing}',
    );
  }
  if (scene != null) {
    b.write(
      '|scene:${scene.glowOn ? 1 : 0}:${scene.glowColorArgb}'
      ':${scene.glowIntensity}:${scene.glowSpread}:${scene.glowMotion}'
      ':${scene.baseMode}:${scene.sweepOn ? 1 : 0}:${scene.sweepSpeed}'
      ':${scene.easing}:${scene.exportSize}:${scene.keyingStrength}',
    );
  }
  return b.toString();
}

/// The index of the part hit by a tap at ([fx], [fy])
/// (fractions) — the TOPMOST part wins (the last one painted),
/// or -1 when the tap lands outside every box. Pure, so the
/// editor preview's tap-to-select is directly testable.
int logoPartIndexAtPoint(List<LogoPart> parts, double fx, double fy) {
  for (var i = parts.length - 1; i >= 0; i--) {
    if (parts[i].box.containsPoint(fx, fy)) return i;
  }
  return -1;
}

/// Wraps proposed/drawn [boxes] into parts with default
/// settings and names, all looking into the master at
/// [sourcePath].
List<LogoPart> logoPartsFromBoxes({
  required String sourcePath,
  required List<LogoBox> boxes,
}) => [
      for (var i = 0; i < boxes.length; i++)
        LogoPart(
          id: 'part$i',
          name: 'Part ${i + 1}',
          sourcePath: sourcePath,
          box: boxes[i],
        ),
    ];

/// MERGE (Option 10): two parts become ONE element — the
/// union of their boxes, [a]'s animation settings and name
/// joined with [b]'s. No files are composited (the old slice
/// model's file merge is gone): an element is a box, so a
/// merge is pure geometry.
LogoPart mergeLogoParts(LogoPart a, LogoPart b) => LogoPart(
      id: a.id,
      name: '${a.name} + ${b.name}',
      sourcePath: a.sourcePath,
      box: a.box.union(b.box),
      rotate: a.rotate,
      direction: a.direction,
      speedSec: a.speedSec,
      rotationStyle: a.rotationStyle,
      delaySec: a.delaySec,
      pivotDx: a.pivotDx,
      pivotDy: a.pivotDy,
      motionMode: a.motionMode,
      swingDeg: a.swingDeg,
      pulseOn: a.pulseOn,
      pulseStrength: a.pulseStrength,
    );

/// SPLIT (Option 11): one part becomes TWO — its box cut
/// into left/right halves that tile the original box
/// exactly, both halves keeping the part's settings.
List<LogoPart> splitLogoPart(LogoPart part) {
  final b = part.box;
  final half = b.w / 2;
  LogoPart halfPart(String suffix, LogoBox box) => LogoPart(
        id: '${part.id}$suffix',
        name: '${part.name} $suffix',
        sourcePath: part.sourcePath,
        box: box,
        rotate: part.rotate,
        direction: part.direction,
        speedSec: part.speedSec,
        rotationStyle: part.rotationStyle,
        delaySec: part.delaySec,
        pivotDx: part.pivotDx,
        pivotDy: part.pivotDy,
        motionMode: part.motionMode,
        swingDeg: part.swingDeg,
        pulseOn: part.pulseOn,
        pulseStrength: part.pulseStrength,
      );
  return [
    halfPart('1', LogoBox(x: b.x, y: b.y, w: half, h: b.h)),
    halfPart('2', LogoBox(x: b.x + half, y: b.y, w: half, h: b.h)),
  ];
}

/// SEQUENCE (Option 25): one tap staggers every part's start
/// waqfa — the first part starts at once, each next part
/// [step] seconds later, in list (layer) order. Delays are
/// rounded to tenths so the Waqt chips match them exactly.
List<LogoPart> staggerLogoPartDelays(List<LogoPart> parts, {double step = 0.2}) => [
      for (var i = 0; i < parts.length; i++)
        parts[i].copyWith(delaySec: (i * step * 10).round() / 10),
    ];

/// SYNC (Option 26): every start waqfa back to zero — all
/// parts start together.
List<LogoPart> syncLogoPartDelays(List<LogoPart> parts) => [
      for (final part in parts) part.copyWith(delaySec: 0),
    ];

/// SETTINGS COPY (Option 40, Build 3): [target] takes
/// [source]'s whole ANIMATION — rotate on/off, style,
/// direction, speed, motion mode + swing angle, pulse,
/// narmi (easing), start waqfa (delay) and the pivot offset.
/// The target's own identity NEVER changes: its box, name,
/// id and master stay its own — only how it moves is copied.
LogoPart copyLogoPartAnimation(LogoPart source, LogoPart target) =>
    target.copyWith(
      rotate: source.rotate,
      direction: source.direction,
      speedSec: source.speedSec,
      rotationStyle: source.rotationStyle,
      delaySec: source.delaySec,
      pivotDx: source.pivotDx,
      pivotDy: source.pivotDy,
      motionMode: source.motionMode,
      swingDeg: source.swingDeg,
      pulseOn: source.pulseOn,
      pulseStrength: source.pulseStrength,
      easing: source.easing,
    );

/// BACKGROUND KEYING (Options 2–3): keys the solid border
/// background out of a logo's RGBA pixels — every opaque
/// pixel within [tolerance] (RGB distance) of the median
/// border colour gets alpha 0; everything else is returned
/// untouched. This is THE keying the parts pipeline runs
/// when a solid-background logo is loaded: [proposeLogoBoxes]
/// builds its element mask from this function's output, and
/// the Logo tab's Keying mazbooti slider sets the tolerance
/// through [logoKeyingToleranceForStrength]. Pure — the
/// caller keeps ownership of the input (a copy is returned).
Uint8List keyLogoBackgroundRgba({
  required Uint8List rgba,
  required int width,
  required int height,
  required double tolerance,
}) {
  final out = Uint8List.fromList(rgba);
  if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
    return out;
  }
  // Median border colour (the same sampling the proposal
  // has always used: every 4th pixel along the four edges).
  final borderColors = <int>[];
  void sampleBorder(int x, int y) {
    final i = (y * width + x) * 4;
    borderColors.add((rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2]);
  }

  for (var x = 0; x < width; x += 4) {
    sampleBorder(x, 0);
    sampleBorder(x, height - 1);
  }
  for (var y = 0; y < height; y += 4) {
    sampleBorder(0, y);
    sampleBorder(width - 1, y);
  }
  if (borderColors.isEmpty) return out;
  borderColors.sort();
  final bg = borderColors[borderColors.length ~/ 2];
  final bgR = (bg >> 16) & 0xFF, bgG = (bg >> 8) & 0xFF, bgB = bg & 0xFF;
  final tolSq = tolerance * tolerance;
  for (var i = 0; i < width * height; i++) {
    final o = i * 4;
    if (out[o + 3] < 128) continue;
    final dr = out[o] - bgR, dg = out[o + 1] - bgG, db = out[o + 2] - bgB;
    if (dr * dr + dg * dg + db * db <= tolSq) {
      out[o + 3] = 0;
    }
  }
  return out;
}

/// A cropped region of a logo image (raw RGBA) — the pixels
/// of one box, at the resolution the crop was taken.
class LogoBoxCrop {
  LogoBoxCrop({
    required this.rgba,
    required this.width,
    required this.height,
    required this.pixelCount,
  });

  final Uint8List rgba;
  final int width;
  final int height;

  /// Opaque (alpha ≥ 128) pixels inside the crop.
  final int pixelCount;
}

/// Crops [box] out of a logo's RGBA pixels. The crop contains
/// EXACTLY the box's pixel rectangle (box fractions × image
/// size, edges rounded outward) — nothing outside the box
/// leaks in, nothing inside is left out.
LogoBoxCrop cropLogoBoxRgba({
  required Uint8List rgba,
  required int width,
  required int height,
  required LogoBox box,
}) {
  var x0 = (box.x * width).floor();
  var y0 = (box.y * height).floor();
  var x1 = (box.right * width).ceil();
  var y1 = (box.bottom * height).ceil();
  if (x0 < 0) x0 = 0;
  if (y0 < 0) y0 = 0;
  if (x1 > width) x1 = width;
  if (y1 > height) y1 = height;
  final cw = x1 - x0;
  final ch = y1 - y0;
  if (cw <= 0 || ch <= 0 || rgba.length < width * height * 4) {
    return LogoBoxCrop(
      rgba: Uint8List(0),
      width: 0,
      height: 0,
      pixelCount: 0,
    );
  }
  final out = Uint8List(cw * ch * 4);
  var count = 0;
  for (var y = 0; y < ch; y++) {
    final srcRow = (y0 + y) * width + x0;
    final dstRow = y * cw;
    for (var x = 0; x < cw; x++) {
      final si = (srcRow + x) * 4;
      final di = (dstRow + x) * 4;
      out[di] = rgba[si];
      out[di + 1] = rgba[si + 1];
      out[di + 2] = rgba[si + 2];
      out[di + 3] = rgba[si + 3];
      if (rgba[si + 3] >= 128) count++;
    }
  }
  return LogoBoxCrop(rgba: out, width: cw, height: ch, pixelCount: count);
}

/// AUTO TAJWEEZ — proposes element BOXES for a logo's RGBA
/// pixels. This NEVER splits the image; it only suggests
/// boxes, and the user adjusts them (draw / move / resize).
///
/// 1. The background is keyed out by border-colour sampling
///    (a solid border colour within tolerance is background).
/// 2. Connected regions of the remaining opaque mask are
///    found (connectivity only — colour is NOT an element's
///    identity; a filled block and the text on it are one
///    opaque region, hence one box, exactly as designed).
/// 3. WORD RULE: small glyph-like regions sitting on one line
///    with small gaps join into ONE word box (the letters of
///    "NEWS" are one element, not four).
/// 4. CONTAINER RULE: a candidate lying ≥80% inside another
///    (non-frame) candidate merges into it — text inside its
///    own outline box is one element WITH that box. A
///    frame-sized candidate (≥80% of the logo's extent both
///    ways) is exempt: elements inside a frame stay their own
///    parts, layered above it.
/// 5. Order: frame first (back), then larger boxes before
///    smaller ones. Capped at [maxBoxes].
///
/// Honest limit (also stated in the app): on flat images a
/// proposal can be wrong (gradients, touching same-colour
/// elements) — that is why every box stays adjustable.
List<LogoBox> proposeLogoBoxes({
  required Uint8List rgba,
  required int width,
  required int height,
  int maxBoxes = 8,
  double keyTolerance = 42,
}) {
  if (width <= 0 || height <= 0 || rgba.length < width * height * 4) {
    return const [];
  }
  // --- Working resolution (nearest-neighbour downscale). ---
  const maxSide = 256;
  var scale = 1;
  while ((width / scale) > maxSide || (height / scale) > maxSide) {
    scale++;
  }
  final w = (width / scale).ceil();
  final h = (height / scale).ceil();
  final px = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final sx = (x * scale).clamp(0, width - 1);
      final sy = (y * scale).clamp(0, height - 1);
      final si = (sy * width + sx) * 4;
      final di = (y * w + x) * 4;
      px[di] = rgba[si];
      px[di + 1] = rgba[si + 1];
      px[di + 2] = rgba[si + 2];
      px[di + 3] = rgba[si + 3];
    }
  }

  // --- 1. Background keying by border sampling — the one
  // shared keying function; [keyTolerance] is what the
  // Logo tab's Keying mazbooti slider drives (the default
  // 42 is the exact tolerance Builds 1–2 always used). ---
  final keyed = keyLogoBackgroundRgba(
    rgba: px,
    width: w,
    height: h,
    tolerance: keyTolerance,
  );
  final opaque = Uint8List(w * h);
  var opaqueCount = 0;
  var oMinX = w, oMinY = h, oMaxX = -1, oMaxY = -1;
  for (var i = 0; i < w * h; i++) {
    final o = i * 4;
    if (keyed[o + 3] < 128) continue;
    opaque[i] = 1;
    opaqueCount++;
    final x = i % w, y = i ~/ w;
    if (x < oMinX) oMinX = x;
    if (x > oMaxX) oMaxX = x;
    if (y < oMinY) oMinY = y;
    if (y > oMaxY) oMaxY = y;
  }
  if (opaqueCount < 16 || oMaxX < 0) return const [];
  final oW = (oMaxX - oMinX + 1).toDouble();
  final oH = (oMaxY - oMinY + 1).toDouble();

  // --- 2. Connected regions (connectivity only). ---
  final regionOf = Int32List(w * h)..fillRange(0, w * h, -1);
  final rSize = <int>[];
  final rMinX = <int>[], rMinY = <int>[], rMaxX = <int>[], rMaxY = <int>[];
  final queue = <int>[];
  var regionCount = 0;
  for (var start = 0; start < w * h; start++) {
    if (opaque[start] == 0 || regionOf[start] != -1) continue;
    var size = 0;
    var minX = w, minY = h, maxX = -1, maxY = -1;
    queue
      ..clear()
      ..add(start);
    regionOf[start] = regionCount;
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      size++;
      final cx = cur % w, cy = cur ~/ w;
      if (cx < minX) minX = cx;
      if (cx > maxX) maxX = cx;
      if (cy < minY) minY = cy;
      if (cy > maxY) maxY = cy;
      for (final (nx, ny) in [
        (cx - 1, cy),
        (cx + 1, cy),
        (cx, cy - 1),
        (cx, cy + 1),
      ]) {
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final ni = ny * w + nx;
        if (opaque[ni] == 0 || regionOf[ni] != -1) continue;
        regionOf[ni] = regionCount;
        queue.add(ni);
      }
    }
    rSize.add(size);
    rMinX.add(minX);
    rMinY.add(minY);
    rMaxX.add(maxX);
    rMaxY.add(maxY);
    regionCount++;
  }
  final minRegion = opaqueCount * 0.0005 > 4 ? (opaqueCount * 0.0005).ceil() : 4;

  // Region bounding boxes in FRACTION space.
  LogoBox regionBox(int r) => LogoBox(
        x: rMinX[r] / w,
        y: rMinY[r] / h,
        w: (rMaxX[r] - rMinX[r] + 1) / w,
        h: (rMaxY[r] - rMinY[r] + 1) / h,
      );

  // --- 3. Word rule: glyph-like regions on one line join. ---
  // Glyph-like is judged against the FRAME (not the opaque
  // extent — a logo that is only one line of text has an
  // opaque height equal to its letters' height).
  bool glyphLike(int r) {
    final bw = rMaxX[r] - rMinX[r] + 1;
    final bh = rMaxY[r] - rMinY[r] + 1;
    return bh <= 0.35 * h && bw <= 0.35 * w;
  }

  final candidates = <LogoBox>[];
  final glyphs = <int>[];
  for (var r = 0; r < regionCount; r++) {
    if (rSize[r] < minRegion) continue;
    if (glyphLike(r)) {
      glyphs.add(r);
    } else {
      candidates.add(regionBox(r));
    }
  }
  // Group glyphs into lines (same line = strong vertical
  // overlap; joinable = horizontal gap below ~0.8 line height).
  glyphs.sort((a, b) {
    final ca = (rMinY[a] + rMaxY[a]) / 2;
    final cb = (rMinY[b] + rMaxY[b]) / 2;
    if (ca != cb) return ca.compareTo(cb);
    return rMinX[a].compareTo(rMinX[b]);
  });
  final lines = <List<int>>[];
  for (final g in glyphs) {
    var placed = false;
    for (final line in lines) {
      var lMinX = w, lMinY = h, lMaxX = -1, lMaxY = -1;
      for (final m in line) {
        if (rMinX[m] < lMinX) lMinX = rMinX[m];
        if (rMinY[m] < lMinY) lMinY = rMinY[m];
        if (rMaxX[m] > lMaxX) lMaxX = rMaxX[m];
        if (rMaxY[m] > lMaxY) lMaxY = rMaxY[m];
      }
      final lineH = lMaxY - lMinY + 1;
      final gH = rMaxY[g] - rMinY[g] + 1;
      // The line's span is inflated a little for membership:
      // dots and diacritics (Urdu/Arabic nuqtay) sit just
      // above/below their letters and belong to the same word.
      final iMinY = lMinY - 0.35 * lineH;
      final iMaxY = lMaxY + 0.35 * lineH;
      final vOverlap =
          (rMaxY[g] < iMaxY ? rMaxY[g].toDouble() : iMaxY) -
              (rMinY[g] > iMinY ? rMinY[g].toDouble() : iMinY) +
              1;
      final vNeed = 0.5 * (gH < lineH ? gH : lineH);
      if (vOverlap < vNeed) continue;
      final gapX = rMinX[g] > lMaxX
          ? rMinX[g] - lMaxX - 1
          : (lMinX > rMaxX[g] ? lMinX - rMaxX[g] - 1 : 0);
      if (gapX > 0.8 * lineH) continue;
      line.add(g);
      placed = true;
      break;
    }
    if (!placed) lines.add([g]);
  }
  for (final line in lines) {
    var box = regionBox(line.first);
    for (final m in line.skip(1)) {
      box = box.union(regionBox(m));
    }
    candidates.add(box);
  }
  if (candidates.isEmpty) return const [];

  // --- 4. Container rule (frames exempt). ---
  bool isFrame(LogoBox b) => b.w >= 0.8 * (oW / w) && b.h >= 0.8 * (oH / h);
  var changed = true;
  while (changed) {
    changed = false;
    outer:
    for (var i = 0; i < candidates.length; i++) {
      if (isFrame(candidates[i])) continue;
      for (var j = 0; j < candidates.length; j++) {
        if (i == j || isFrame(candidates[j])) continue;
        if (candidates[i].coveredFractionBy(candidates[j]) >= 0.8) {
          candidates.removeAt(i);
          changed = true;
          break outer;
        }
      }
    }
  }

  // --- 5. Order + pad + cap. ---
  candidates.sort((a, b) {
    final fa = isFrame(a) ? 0 : 1;
    final fb = isFrame(b) ? 0 : 1;
    if (fa != fb) return fa.compareTo(fb);
    return b.area.compareTo(a.area);
  });
  final cap = maxBoxes < 1 ? 1 : maxBoxes;
  return [
    for (final b in candidates.take(cap)) b.pad(0.006),
  ];
}
