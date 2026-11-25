/// Build 13 (point 6) — LOGO PARTS ENGINE: model + pure split.
///
/// A logo brought into the Logo tool can be split into PARTS
/// (like engine parts); each part gets its own rotation
/// controls (rotate on/off, direction, speed) and the parts
/// animate independently in preview and export through the
/// shared renderers (LogoPartsView / LogoPartsService frames).
///
/// The split is AUTOMATIC (background keying + colour clusters
/// + connected regions, all on raw RGBA bytes in this file —
/// pure Dart, host-testable) and ADJUSTABLE: the user can merge
/// parts and re-split with a different part count. A perfect
/// semantic split of an arbitrary flat logo cannot be
/// guaranteed — that is exactly why the adjust controls exist.
///
/// PAID SAVE (the user's model, corrected 2026-11-25): the
/// working part settings are SESSION-ONLY (they live in the
/// preset's transient fields and are never serialised). Saving
/// costs [kLogoPartsSavePriceCoins] coins, charged once per
/// save, and the saved settings stay usable for exactly
/// [kLogoPartsSaveValidity] (7 days). On expiry the saved entry
/// is DEAD — removed, settings gone; the user redoes the
/// settings and pays again to save anew. There is deliberately
/// NO renewal-keeps-settings path.
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

/// One logo part: its own alpha-cut bitmap file plus its own
/// rotation settings. Serialisable (the saved payload is a JSON
/// list of these).
class LogoPart {
  LogoPart({
    required this.id,
    required this.name,
    required this.imagePath,
    this.rotate = true,
    this.direction = 'cw',
    double speedSec = 6,
    this.centreX = 0.5,
    this.centreY = 0.5,
  }) : speedSec = snapLogoPartSpeed(speedSec);

  final String id;
  String name;

  /// PNG with alpha — ONLY this part's pixels are opaque.
  final String imagePath;

  bool rotate;

  /// 'cw' or 'ccw'.
  String direction;

  /// Seconds per revolution (snapped to [kLogoPartSpeeds]).
  double speedSec;

  /// The part's centroid, as fractions of the logo frame —
  /// the point the part rotates around.
  double centreX;
  double centreY;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imagePath': imagePath,
        'rotate': rotate,
        'direction': direction,
        'speedSec': speedSec,
        'centreX': centreX,
        'centreY': centreY,
      };

  factory LogoPart.fromJson(Map<String, dynamic> j) => LogoPart(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? 'Part',
        imagePath: j['imagePath'] as String? ?? '',
        rotate: j['rotate'] as bool? ?? true,
        direction: j['direction'] as String? ?? 'cw',
        speedSec: (j['speedSec'] as num?)?.toDouble() ?? 6,
        centreX: (j['centreX'] as num?)?.toDouble() ?? 0.5,
        centreY: (j['centreY'] as num?)?.toDouble() ?? 0.5,
      );

  LogoPart copyWith({
    String? name,
    bool? rotate,
    String? direction,
    double? speedSec,
  }) =>
      LogoPart(
        id: id,
        name: name ?? this.name,
        imagePath: imagePath,
        rotate: rotate ?? this.rotate,
        direction: direction ?? this.direction,
        speedSec: speedSec ?? this.speedSec,
        centreX: centreX,
        centreY: centreY,
      );
}

/// Serialises the working parts list (the paid-save payload).
String encodeLogoParts(List<LogoPart> parts) =>
    jsonEncode(parts.map((e) => e.toJson()).toList());

/// Parses a saved payload back; corrupt/absent → empty.
List<LogoPart> decodeLogoParts(String json) {
  if (json.isEmpty) return const [];
  try {
    final raw = jsonDecode(json);
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((m) => LogoPart.fromJson(m.cast<String, dynamic>()))
        .where((p) => p.imagePath.isNotEmpty)
        .toList();
  } catch (_) {
    return const [];
  }
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
/// whenever any part setting (or the source logo) changes.
String logoPartsVariantKey({
  required String sourceStamp,
  required List<LogoPart> parts,
}) {
  final b = StringBuffer(sourceStamp);
  for (final part in parts) {
    b.write(
      '|${part.id}:${part.rotate ? 1 : 0}:${part.direction}:${part.speedSec}',
    );
  }
  return b.toString();
}

/// One detected part in pixel space (the split's raw output —
/// the service turns these into PNG files + [LogoPart]s).
class LogoPartPixels {
  LogoPartPixels({
    required this.rgba,
    required this.width,
    required this.height,
    required this.pixelCount,
    required this.centreX,
    required this.centreY,
    required this.dominantColor,
  });

  /// Full-frame RGBA at the working resolution; only this
  /// part's pixels are opaque.
  final Uint8List rgba;
  final int width;
  final int height;
  final int pixelCount;

  /// Centroid as fractions of the frame.
  final double centreX;
  final double centreY;

  /// 0xAARRGGBB dominant colour of the part.
  final int dominantColor;
}

/// Splits a logo's RGBA pixels into parts:
///
/// 1. The background is keyed out by border colour sampling
///    (the same idea as the logo keying service — a solid
///    border colour within tolerance becomes transparent).
/// 2. Opaque pixels are clustered by colour (quantised
///    buckets, greedily separated centres).
/// 3. Each colour cluster is split into connected regions;
///    every region covering at least ~1% of the opaque pixels
///    becomes its own part (so same-colour but separate shapes
///    — letters vs a block — split apart), smaller regions fold
///    into their cluster's largest part.
/// 4. Parts are capped at [maxParts] (largest first; the rest
///    fold into the colour-nearest kept part).
///
/// Works at a downscaled working resolution (long side ≤ 256)
/// for speed; the returned part bitmaps are at that resolution
/// (plenty for a logo bug / cube-sized render).
List<LogoPartPixels> splitLogoRgba({
  required Uint8List rgba,
  required int width,
  required int height,
  int maxParts = 6,
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

  // --- 1. Background keying by border sampling. ---
  final borderColors = <int>[];
  void sampleBorder(int x, int y) {
    final i = (y * w + x) * 4;
    borderColors.add((px[i] << 16) | (px[i + 1] << 8) | px[i + 2]);
  }

  for (var x = 0; x < w; x += 4) {
    sampleBorder(x, 0);
    sampleBorder(x, h - 1);
  }
  for (var y = 0; y < h; y += 4) {
    sampleBorder(0, y);
    sampleBorder(w - 1, y);
  }
  borderColors.sort();
  final bg = borderColors[borderColors.length ~/ 2];
  final bgR = (bg >> 16) & 0xFF, bgG = (bg >> 8) & 0xFF, bgB = bg & 0xFF;
  const bgTol = 42;
  final opaque = Uint8List(w * h);
  var opaqueCount = 0;
  for (var i = 0; i < w * h; i++) {
    final o = i * 4;
    final a = px[o + 3];
    if (a < 128) continue;
    final dr = px[o] - bgR, dg = px[o + 1] - bgG, db = px[o + 2] - bgB;
    if (dr * dr + dg * dg + db * db <= bgTol * bgTol) continue;
    opaque[i] = 1;
    opaqueCount++;
  }
  if (opaqueCount < 16) return const [];

  // --- 2. Colour clusters (quantised buckets). ---
  int bucketOf(int i) {
    final o = i * 4;
    return ((px[o] >> 5) << 6) | ((px[o + 1] >> 5) << 3) | (px[o + 2] >> 5);
  }

  final bucketCounts = <int, int>{};
  final bucketSums = <int, List<int>>{};
  for (var i = 0; i < w * h; i++) {
    if (opaque[i] == 0) continue;
    final b = bucketOf(i);
    bucketCounts[b] = (bucketCounts[b] ?? 0) + 1;
    final o = i * 4;
    final sums = bucketSums.putIfAbsent(b, () => [0, 0, 0]);
    sums[0] += px[o];
    sums[1] += px[o + 1];
    sums[2] += px[o + 2];
  }
  final bucketsByCount = bucketCounts.keys.toList()
    ..sort((a, b) => bucketCounts[b]!.compareTo(bucketCounts[a]!));
  // Greedily pick cluster centres that are colour-far apart.
  final centres = <List<double>>[]; // [r, g, b] means
  for (final b in bucketsByCount) {
    if (bucketCounts[b]! < opaqueCount * 0.01) break;
    final n = bucketCounts[b]!;
    final s = bucketSums[b]!;
    final mean = [s[0] / n, s[1] / n, s[2] / n];
    var far = true;
    for (final c in centres) {
      final dr = mean[0] - c[0], dg = mean[1] - c[1], db = mean[2] - c[2];
      if (dr * dr + dg * dg + db * db < 60 * 60) {
        far = false;
        break;
      }
    }
    if (far) {
      centres.add(mean);
      if (centres.length >= 6) break;
    }
  }
  if (centres.isEmpty) return const [];
  final clusterOf = Int16List(w * h)..fillRange(0, w * h, -1);
  for (var i = 0; i < w * h; i++) {
    if (opaque[i] == 0) continue;
    final o = i * 4;
    var best = 0;
    var bestD = double.infinity;
    for (var c = 0; c < centres.length; c++) {
      final dr = px[o] - centres[c][0];
      final dg = px[o + 1] - centres[c][1];
      final db = px[o + 2] - centres[c][2];
      final d = dr * dr + dg * dg + db * db;
      if (d < bestD) {
        bestD = d;
        best = c;
      }
    }
    clusterOf[i] = best;
  }

  // --- 3. Connected regions per cluster. ---
  final regionOf = Int32List(w * h)..fillRange(0, w * h, -1);
  final regionSizes = <int>[];
  final regionClusters = <int>[];
  final queue = <int>[];
  var regionCount = 0;
  for (var start = 0; start < w * h; start++) {
    if (opaque[start] == 0 || regionOf[start] != -1) continue;
    final cluster = clusterOf[start];
    var size = 0;
    queue
      ..clear()
      ..add(start);
    regionOf[start] = regionCount;
    while (queue.isNotEmpty) {
      final cur = queue.removeLast();
      size++;
      final cx = cur % w, cy = cur ~/ w;
      for (final (nx, ny) in [
        (cx - 1, cy),
        (cx + 1, cy),
        (cx, cy - 1),
        (cx, cy + 1),
      ]) {
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final ni = ny * w + nx;
        if (opaque[ni] == 0 ||
            regionOf[ni] != -1 ||
            clusterOf[ni] != cluster) {
          continue;
        }
        regionOf[ni] = regionCount;
        queue.add(ni);
      }
    }
    regionSizes.add(size);
    regionClusters.add(cluster);
    regionCount++;
  }

  // Region → part assignment: regions ≥1% are their own part;
  // smaller ones join their cluster's largest region's part.
  final minRegion = (opaqueCount * 0.01).ceil();
  final largestRegionOfCluster = <int, int>{};
  for (var r = 0; r < regionCount; r++) {
    final c = regionClusters[r];
    final cur = largestRegionOfCluster[c];
    if (cur == null || regionSizes[r] > regionSizes[cur]) {
      largestRegionOfCluster[c] = r;
    }
  }
  final partOfRegion = <int, int>{};
  var partCount = 0;
  for (var r = 0; r < regionCount; r++) {
    if (regionSizes[r] >= minRegion) {
      partOfRegion[r] = partCount++;
    }
  }
  for (var r = 0; r < regionCount; r++) {
    partOfRegion[r] ??=
        partOfRegion[largestRegionOfCluster[regionClusters[r]]!] ?? 0;
  }

  // --- 4. Cap the part count: fold the smallest parts into
  // the colour-nearest kept part, at the REGION level (so the
  // per-pixel assignment below stays a pure lookup). ---
  final partSizes = List<int>.filled(partCount, 0);
  final partColorSums = List<List<int>>.generate(
    partCount,
    (_) => [0, 0, 0],
  );
  for (var i = 0; i < w * h; i++) {
    if (opaque[i] == 0) continue;
    final part = partOfRegion[regionOf[i]]!;
    partSizes[part]++;
    final o = i * 4;
    partColorSums[part][0] += px[o];
    partColorSums[part][1] += px[o + 1];
    partColorSums[part][2] += px[o + 2];
  }
  final cap = maxParts < 1 ? 1 : maxParts;
  if (partCount > cap) {
    final order = List<int>.generate(partCount, (i) => i)
      ..sort((a, b) => partSizes[b].compareTo(partSizes[a]));
    final keep = order.take(cap).toSet();
    List<double> meanOf(int part) => [
          partColorSums[part][0] / partSizes[part],
          partColorSums[part][1] / partSizes[part],
          partColorSums[part][2] / partSizes[part],
        ];
    final foldInto = <int, int>{};
    for (var oldIdx = 0; oldIdx < partCount; oldIdx++) {
      if (keep.contains(oldIdx)) continue;
      final m = meanOf(oldIdx);
      var best = keep.first;
      var bestD = double.infinity;
      for (final k in keep) {
        final km = meanOf(k);
        final dr = m[0] - km[0], dg = m[1] - km[1], db = m[2] - km[2];
        final d = dr * dr + dg * dg + db * db;
        if (d < bestD) {
          bestD = d;
          best = k;
        }
      }
      foldInto[oldIdx] = best;
    }
    for (var r = 0; r < regionCount; r++) {
      final folded = foldInto[partOfRegion[r]];
      if (folded != null) partOfRegion[r] = folded;
    }
    final keptSorted = keep.toList()
      ..sort((a, b) => partSizes[b].compareTo(partSizes[a]));
    final compact = <int, int>{};
    for (var n = 0; n < keptSorted.length; n++) {
      compact[keptSorted[n]] = n;
    }
    for (var r = 0; r < regionCount; r++) {
      partOfRegion[r] = compact[partOfRegion[r]]!;
    }
    partCount = keptSorted.length;
  }

  return _buildParts(
    px: px,
    w: w,
    h: h,
    opaque: opaque,
    pixelPart: _pixelParts(w, h, opaque, regionOf, partOfRegion),
    partCount: partCount,
  );
}

/// Per-pixel part index (or -1 for background).
Int16List _pixelParts(
  int w,
  int h,
  Uint8List opaque,
  Int32List regionOf,
  Map<int, int> partOfRegion,
) {
  final out = Int16List(w * h)..fillRange(0, w * h, -1);
  for (var i = 0; i < w * h; i++) {
    if (opaque[i] == 0) continue;
    out[i] = partOfRegion[regionOf[i]] ?? 0;
  }
  return out;
}

List<LogoPartPixels> _buildParts({
  required Uint8List px,
  required int w,
  required int h,
  required Uint8List opaque,
  required Int16List pixelPart,
  required int partCount,
}) {
  final parts = <LogoPartPixels>[];
  for (var part = 0; part < partCount; part++) {
    final out = Uint8List(w * h * 4);
    var count = 0;
    var sumX = 0.0, sumY = 0.0;
    var rS = 0, gS = 0, bS = 0;
    for (var i = 0; i < w * h; i++) {
      if (pixelPart[i] != part) continue;
      final o = i * 4;
      out[o] = px[o];
      out[o + 1] = px[o + 1];
      out[o + 2] = px[o + 2];
      out[o + 3] = 255;
      count++;
      sumX += i % w;
      sumY += i ~/ w;
      rS += px[o];
      gS += px[o + 1];
      bS += px[o + 2];
    }
    if (count == 0) continue;
    parts.add(
      LogoPartPixels(
        rgba: out,
        width: w,
        height: h,
        pixelCount: count,
        centreX: (sumX / count) / w,
        centreY: (sumY / count) / h,
        dominantColor: 0xFF000000 |
            ((rS ~/ count) << 16) |
            ((gS ~/ count) << 8) |
            (bS ~/ count),
      ),
    );
  }
  parts.sort((a, b) => b.pixelCount.compareTo(a.pixelCount));
  return parts;
}
