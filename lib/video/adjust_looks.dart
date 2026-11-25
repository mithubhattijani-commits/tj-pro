/// "My Looks" — user-saved Video Editor Adjust presets
/// (v1.13.0, G5).
///
/// A Look captures EXACTLY the state the Adjust panel controls:
/// the LUT choice, the nine Pro grade values (brightness,
/// contrast, saturation, vibrance, temperature, tint,
/// highlights, shadows, exposure) and the ten Adjust extras
/// (auto + brilliance / sharpen / clarity / whites / blacks /
/// hue / fade / vignette / grain — the [AdjustValues] set).
/// Nothing outside the Adjust panel is captured or applied —
/// the Filters tab and every other panel keep their own state.
///
/// Looks persist on-device in SharedPreferences (they survive
/// sessions and app restarts; they are NOT part of a project
/// and never leave the phone). Capture/apply are pure functions
/// over the controller's existing getters/setters, so the panel
/// and the tests exercise the very same code path.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'video_editor_controller.dart';

/// One saved Adjust preset.
class AdjustLook {
  const AdjustLook({
    required this.name,
    required this.lut,
    required this.auto,
    required this.brilliance,
    required this.sharpen,
    required this.clarity,
    required this.whites,
    required this.blacks,
    required this.hue,
    required this.fade,
    required this.vignette,
    required this.grain,
    required this.brightness,
    required this.contrast,
    required this.saturation,
    required this.vibrance,
    required this.temperature,
    required this.tint,
    required this.highlights,
    required this.shadows,
    required this.exposure,
  });

  final String name;

  /// The bundled LUT name ('' = None) — the Adjust panel's LUT rail.
  final String lut;

  /// One-tap normalize (the Adjust extras' `auto`).
  final bool auto;

  // The Adjust extras (see AdjustValues for ranges).
  final double brilliance;
  final double sharpen;
  final double clarity;
  final double whites;
  final double blacks;
  final double hue;
  final double fade;
  final double vignette;
  final double grain;

  // The Pro grade values (the shared grade slider's items).
  final double brightness;
  final double contrast;
  final double saturation;
  final double vibrance;
  final double temperature;
  final double tint;
  final double highlights;
  final double shadows;
  final double exposure;

  Map<String, Object?> toJson() => {
        'name': name,
        'lut': lut,
        'auto': auto,
        'brilliance': brilliance,
        'sharpen': sharpen,
        'clarity': clarity,
        'whites': whites,
        'blacks': blacks,
        'hue': hue,
        'fade': fade,
        'vignette': vignette,
        'grain': grain,
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'vibrance': vibrance,
        'temperature': temperature,
        'tint': tint,
        'highlights': highlights,
        'shadows': shadows,
        'exposure': exposure,
      };

  /// Tolerant decode: a missing/corrupt field falls back to its
  /// neutral value instead of dropping the whole Look (a hand-
  /// edited or older store must never crash the panel).
  factory AdjustLook.fromJson(Map<String, Object?> json) {
    double d(String key) {
      final v = json[key];
      return v is num ? v.toDouble() : 0;
    }

    return AdjustLook(
      name: json['name'] as String? ?? '',
      lut: json['lut'] as String? ?? '',
      auto: json['auto'] as bool? ?? false,
      brilliance: d('brilliance'),
      sharpen: d('sharpen'),
      clarity: d('clarity'),
      whites: d('whites'),
      blacks: d('blacks'),
      hue: d('hue'),
      fade: d('fade'),
      vignette: d('vignette'),
      grain: d('grain'),
      brightness: d('brightness'),
      contrast: d('contrast'),
      // Saturation / vibrance are multipliers — their neutral
      // is 1, not 0.
      saturation: json['saturation'] is num
          ? (json['saturation'] as num).toDouble()
          : 1,
      vibrance:
          json['vibrance'] is num ? (json['vibrance'] as num).toDouble() : 1,
      temperature: d('temperature'),
      tint: d('tint'),
      highlights: d('highlights'),
      shadows: d('shadows'),
      exposure: d('exposure'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AdjustLook &&
      other.name == name &&
      other.lut == lut &&
      other.auto == auto &&
      other.brilliance == brilliance &&
      other.sharpen == sharpen &&
      other.clarity == clarity &&
      other.whites == whites &&
      other.blacks == blacks &&
      other.hue == hue &&
      other.fade == fade &&
      other.vignette == vignette &&
      other.grain == grain &&
      other.brightness == brightness &&
      other.contrast == contrast &&
      other.saturation == saturation &&
      other.vibrance == vibrance &&
      other.temperature == temperature &&
      other.tint == tint &&
      other.highlights == highlights &&
      other.shadows == shadows &&
      other.exposure == exposure;

  @override
  int get hashCode => Object.hashAll([
        name,
        lut,
        auto,
        brilliance,
        sharpen,
        clarity,
        whites,
        blacks,
        hue,
        fade,
        vignette,
        grain,
        brightness,
        contrast,
        saturation,
        vibrance,
        temperature,
        tint,
        highlights,
        shadows,
        exposure,
      ]);
}

/// Capture the editor's CURRENT Adjust state as a Look named
/// [name] — reads only the Adjust panel's own controls.
AdjustLook captureAdjustLook(VideoEditorController host, String name) {
  return AdjustLook(
    name: name,
    lut: host.proLut,
    auto: host.adjAuto,
    brilliance: host.adjBrilliance,
    sharpen: host.adjSharpen,
    clarity: host.adjClarity,
    whites: host.adjWhites,
    blacks: host.adjBlacks,
    hue: host.adjHue,
    fade: host.adjFade,
    vignette: host.adjVignette,
    grain: host.adjGrain,
    brightness: host.proBrightness,
    contrast: host.proContrast,
    saturation: host.proSaturation,
    vibrance: host.proVibrance,
    temperature: host.proTemperature,
    tint: host.proTint,
    highlights: host.proHighlights,
    shadows: host.proShadows,
    exposure: host.proExposure,
  );
}

/// Apply [look] to the editor — writes only the Adjust panel's
/// own controls. The caller wraps this in `host.update(...)` so
/// the preview rebuilds once, exactly like a slider move.
void applyAdjustLook(VideoEditorController host, AdjustLook look) {
  host.proLut = look.lut;
  host.adjAuto = look.auto;
  host.adjBrilliance = look.brilliance;
  host.adjSharpen = look.sharpen;
  host.adjClarity = look.clarity;
  host.adjWhites = look.whites;
  host.adjBlacks = look.blacks;
  host.adjHue = look.hue;
  host.adjFade = look.fade;
  host.adjVignette = look.vignette;
  host.adjGrain = look.grain;
  host.proBrightness = look.brightness;
  host.proContrast = look.contrast;
  host.proSaturation = look.saturation;
  host.proVibrance = look.vibrance;
  host.proTemperature = look.temperature;
  host.proTint = look.tint;
  host.proHighlights = look.highlights;
  host.proShadows = look.shadows;
  host.proExposure = look.exposure;
}

/// SharedPreferences persistence for My Looks.
class AdjustLooksStore {
  static const String prefsKey = 've_my_looks_v1';

  /// Pure encode (unit-tested): the whole list as one JSON string.
  static String encode(List<AdjustLook> looks) =>
      jsonEncode([for (final l in looks) l.toJson()]);

  /// Pure decode: corrupt payloads read as an empty list, and
  /// entries without a name are dropped — the panel must never
  /// fail to open over a damaged store.
  static List<AdjustLook> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          if (e is Map)
            AdjustLook.fromJson(e.cast<String, Object?>()),
      ].where((l) => l.name.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<List<AdjustLook>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return decode(prefs.getString(prefsKey));
  }

  static Future<void> saveAll(List<AdjustLook> looks) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, encode(looks));
  }

  /// Add [look], replacing any existing Look with the same name
  /// (saving over a name is the expected "update my preset"
  /// gesture). Returns the new list.
  static Future<List<AdjustLook>> add(AdjustLook look) async {
    final looks = await load();
    final next = [
      for (final l in looks)
        if (l.name != look.name) l,
      look,
    ];
    await saveAll(next);
    return next;
  }

  /// Remove the Look named [name]. Returns the new list.
  static Future<List<AdjustLook>> remove(String name) async {
    final looks = await load();
    final next = [
      for (final l in looks)
        if (l.name != name) l,
    ];
    await saveAll(next);
    return next;
  }
}
