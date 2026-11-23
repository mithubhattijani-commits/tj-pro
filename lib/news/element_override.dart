/// Per-project MANUAL element overrides (v1.5.0, fix #33).
///
/// Every element of the News Studio Final template — the main
/// video/photo, the logo, each ribbon band, the headline text, the
/// ticker text, the time/date capsule and the watermark overlay —
/// can be selected in the News Maker, moved (drag or sliders),
/// resized (corner handle or size slider) and removed (hidden).
/// The adjustment is stored as one of these overrides on the
/// project and applied ON TOP of the preset geometry in both the
/// preview and the export render.
///
/// An override is pure data: [dx]/[dy] are translations as
/// fractions of the frame width/height (0 = the designed
/// position), [scale] multiplies the element's designed size
/// (1 = designed), [hidden] removes the element. The DEFAULT
/// override (and a missing entry) is the identity — with no
/// overrides set, the Final template renders EXACTLY as finalised
/// (demo v4 geometry, byte-identical defaults in the parity
/// renderer).
library;

/// One element's manual adjustment. Immutable; the editor writes
/// a new value per change.
class ElementOverride {
  const ElementOverride({
    this.dx = 0,
    this.dy = 0,
    this.scale = 1,
    this.hidden = false,
  });

  /// Horizontal shift, fraction of the frame width (+ = right).
  final double dx;

  /// Vertical shift, fraction of the frame height (+ = down).
  final double dy;

  /// Size multiplier on the element's designed size.
  final double scale;

  /// Removed by the user (the element does not render).
  final bool hidden;

  static const ElementOverride identity = ElementOverride();

  bool get isIdentity =>
      dx == 0 && dy == 0 && scale == 1 && !hidden;

  ElementOverride copyWith({
    double? dx,
    double? dy,
    double? scale,
    bool? hidden,
  }) {
    return ElementOverride(
      dx: dx ?? this.dx,
      dy: dy ?? this.dy,
      scale: scale ?? this.scale,
      hidden: hidden ?? this.hidden,
    );
  }

  Map<String, dynamic> toJson() => {
        'dx': dx,
        'dy': dy,
        'scale': scale,
        'hidden': hidden,
      };

  static ElementOverride fromJson(Map<String, dynamic> json) {
    return ElementOverride(
      dx: (json['dx'] as num?)?.toDouble() ?? 0,
      dy: (json['dy'] as num?)?.toDouble() ?? 0,
      scale: ((json['scale'] as num?)?.toDouble() ?? 1).clamp(0.2, 4),
      hidden: (json['hidden'] as bool?) ?? false,
    );
  }
}

/// The element ids of the Final template (the keys of
/// [NewsProject.elementOverrides]).
class NewsElement {
  static const String media = 'media';
  static const String logo = 'logo';
  static const String capsule = 'capsule';
  static const String topRibbon = 'topRibbon';
  static const String middleRibbon = 'middleRibbon';
  static const String bottomRibbon = 'bottomRibbon';
  static const String headlineText = 'headlineText';
  static const String tickerText = 'tickerText';
  static const String overlay = 'overlay';

  /// v1.5.1 (fix #50): the Reporter (numainda) photo block — photo
  /// + name plate on the side OPPOSITE the logo. Its content lives
  /// on the project (reporterPhotoPath / reporterName); this id is
  /// only its manual position/size override slot, like every other
  /// element.
  static const String reporter = 'reporter';

  /// Every element, in selection-row order.
  static const List<String> all = [
    media,
    logo,
    reporter,
    topRibbon,
    middleRibbon,
    headlineText,
    bottomRibbon,
    tickerText,
    capsule,
    overlay,
  ];

  static const Map<String, String> labels = {
    media: 'Video / Photo',
    logo: 'Logo',
    reporter: 'Reporter',
    topRibbon: 'Top Ribbon',
    middleRibbon: 'Headline Ribbon',
    headlineText: 'Headline Text',
    bottomRibbon: 'Ticker Ribbon',
    tickerText: 'Ticker Text',
    capsule: 'Time / Date',
    overlay: 'Watermark',
  };
}

/// The override for [id] in [overrides] — the identity when the
/// element was never adjusted.
ElementOverride overrideFor(
  Map<String, ElementOverride> overrides,
  String id,
) =>
    overrides[id] ?? ElementOverride.identity;
