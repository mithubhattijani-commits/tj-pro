/// Build 8 (v1.6.0, fix-list point #2) — Home hero frame math.
///
/// The hero carousel used to sit in a fixed 178dp frame (≈2.21:1)
/// with slide 1 cover-fit, so any banner whose own aspect
/// differed was cropped (the user's 1211×881 banner would have
/// lost ~38% of its height). The frame now ADAPTS to the active
/// slide's image aspect: these pure functions own the math so it
/// is unit-testable without pumping the carousel.
///
/// Rules:
/// * Before any slide's aspect is known, the frame keeps the
///   historical default height ([defaultHeroHeight]) — the
///   layout never jumps blank.
/// * Aspects are clamped to [minHeroAspect]..[maxHeroAspect] so
///   a pathological image (a sliver or a tower) cannot wreck
///   the Home layout.
/// * The frame height is additionally capped at
///   [heroMaxHeightFraction] of the screen height.
library;

/// Height (dp) of the hero frame before any image aspect is
/// known — identical to the pre-Build-8 fixed height.
const double defaultHeroHeight = 178;

/// Widest banner aspect the frame will follow (width / height).
const double maxHeroAspect = 2.65;

/// Tallest banner aspect the frame will follow (width / height).
const double minHeroAspect = 1.15;

/// The hero frame never exceeds this fraction of screen height.
const double heroMaxHeightFraction = 0.45;

/// Aspect (width / height) of an image of [width]×[height]
/// pixels; null when either dimension is unusable.
double? heroAspectFromSize(double width, double height) {
  if (width <= 0 || height <= 0) return null;
  final double aspect = width / height;
  if (!aspect.isFinite || aspect <= 0) return null;
  return aspect;
}

/// Clamp [aspect] into the frame's sane range. Non-finite or
/// non-positive input falls back to the aspect that reproduces
/// the historical default frame on a typical phone width
/// (2.21:1 — the old 178dp frame at ~393dp wide).
double clampHeroAspect(double aspect) {
  if (!aspect.isFinite || aspect <= 0) return 2.21;
  return aspect.clamp(minHeroAspect, maxHeroAspect).toDouble();
}

/// Frame height for a carousel of [width] showing an image of
/// the given [aspect] (null = not known yet), never exceeding
/// [maxHeight] (the screen-height cap computed by the caller).
double heroFrameHeight({
  required double width,
  required double? aspect,
  required double maxHeight,
}) {
  if (aspect == null) {
    return defaultHeroHeight < maxHeight ? defaultHeroHeight : maxHeight;
  }
  final double fitted = width / clampHeroAspect(aspect);
  return fitted < maxHeight ? fitted : maxHeight;
}
