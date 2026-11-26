/// Channel presets for News Studio (v1).
///
/// A preset is one channel's whole broadcast identity — its logo, its
/// ribbon colours, which ribbons show, and which template it uses — so the
/// user can switch between channels (Nigraan TV, ARY, Geo, …) without
/// re-typing anything. Nigraan TV ships as the built-in default; the user
/// creates/edits/deletes the rest. Stored as plain JSON in the app
/// documents directory, same pattern as `NewsTemplate` (`news_template.json`).
///
/// RIBBON-CONTENT RULE (user, 20 Nov 2026 — binds every phase that touches
/// the 3-ribbon template):
///   TOP ribbon    = CURRENT khabar (us waqt ki story — the story being made).
///   MIDDLE (Urdu) = NATIONAL NEWS (doosri qomi khabrein — NEVER the
///                     current story).
///   BOTTOM (English) = INTERNATIONAL news.
/// Encoded here as [RibbonContentKind] on every ribbon: top defaults to
/// `current`, middle Urdu to `national`, bottom English to `international`.
/// The Breaking + Ticker combo template follows the same rule (see
/// lib/news/breaking_templates.dart). A ribbon's `text` is the text that
/// scrolls; its `contentKind` is WHERE that text comes from — the renderer
/// and the ticker engine (Phase 3) must fill each ribbon from its own
/// source and must never put the current story on the middle ribbon.
///
/// TICKER PASTE-TO-RUN (user, 20 Nov 2026 — v1 MUST-HAVE):
/// pasting text into the ticker field must make the ticker run AT ONCE —
/// no extra step. Contract for the screens (Phase 3): the ticker text is
/// a plain mutable field, read LIVE on every preview frame / render call
/// and never cached by the model. A screen's `onChanged` must rebuild
/// immediately (setState / ValueNotifier) so the preview scrolls the new
/// text the moment it is pasted. Export renders the same ticker text
/// (Phase 3/7). Urdu ticker text renders in Jameel Noori Nastaleeq
/// Kasheeda, direction/speed from the ribbon's own settings.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/asset_download_service.dart';
import 'logo_parts.dart';

/// What a ribbon's text IS — which news feed fills it.
///
/// See the RIBBON-CONTENT RULE in the file header. This is the rule the
/// user ordered on 20 Nov 2026; do not reassign the kinds.
enum RibbonContentKind {
  /// The story being made right now (top ribbon only).
  current('current'),

  /// Other national news — never the current story (middle Urdu ribbon).
  national('national'),

  /// International news (bottom English ribbon).
  international('international');

  const RibbonContentKind(this.id);
  final String id;

  static RibbonContentKind fromId(String? id) {
    for (final v in RibbonContentKind.values) {
      if (v.id == id) return v;
    }
    return RibbonContentKind.current;
  }
}

/// Scroll direction of one ribbon.
enum RibbonDirection {
  /// Right-to-left (Urdu default).
  rtl('rtl'),

  /// Left-to-right (English default).
  ltr('ltr');

  const RibbonDirection(this.id);
  final String id;

  static RibbonDirection fromId(String? id) {
    for (final v in RibbonDirection.values) {
      if (v.id == id) return v;
    }
    return RibbonDirection.rtl;
  }
}

/// The two Final-template designs (user, 22 Nov 2026): 'final3' is
/// the DEFAULT — the PUBLIC-News-style THREE-ribbon bottom stack
/// (top = current/related Urdu, middle = national Urdu, bottom =
/// international English ticker, logo + date capsule at the right).
/// 'classic2' keeps the v1.3.0 two-ribbon parity design (Urdu
/// #3D5AFE over English #EF0017, gold chips) selectable.
const String kFinalVariant3 = 'final3';
const String kFinalVariantClassic2 = 'classic2';

/// The three template-kind ids a preset/project can carry
/// (Build 5: moved here from the retired Template & Studio
/// screen, which used to define them).
const String kTemplateFinal = 'nigraanFinal';
const String kTemplateBreaking = 'breaking';
const String kTemplateClassic = 'classic';

/// Factory ribbon colours (the values a preset carried when the
/// user had never customised them, up to v1.5.0). Kept as the
/// classic2 design colours and as the migration keys for fix #40:
/// the Final 3-Ribbon design now renders its FIXED design colours
/// regardless of the stored values (see [finalDesignRibbonColor]),
/// and [ChannelPresetStore.loadAll] rewrites stored factory values
/// on the built-in preset to the Final colours.
const int kFactoryTopRibbonColor = 0xFF01B0FF;
const int kFactoryUrduRibbonColor = 0xFF3D5AFE;
const int kFactoryEnglishRibbonColor = 0xFFEF0017;

/// Final 3-Ribbon design colours (user-declared FINAL, demo v4,
/// 22 Nov 2026): top YELLOW (255,200,0) with BLACK headline text,
/// middle red (136,12,3), bottom dark navy-black (8,30,70).
const int kFinal3TopColor = 0xFFFFC800;
const int kFinal3UrduColor = 0xFF880C03;
const int kFinal3EnglishColor = 0xFF081E46;

/// Text colour for the final3 top ribbon: BLACK on the yellow
/// design colour, WHITE when the user picked a custom top colour
/// (the colour pickers in Template Studio / Channel Branding stay
/// live — a custom colour always wins and takes white text, the
/// same rule as the other ribbons).
const int kFinal3TopTextColor = 0xFF000000;

/// Resolves one ribbon's render colour for a Final design.
///
/// v1.5.1 (fix #40): the Final 3-Ribbon design has FIXED identity
/// colours — it ALWAYS renders [final3Color], whatever colour is
/// stored on the preset. (Before this fix the resolver let any
/// stored non-factory colour win, and the user's saved v1.4-era
/// preset kept the old cyan/blue/red scheme, so the declared-FINAL
/// colours never reached his phone.) The colour pickers in
/// Template Studio / Channel Branding still edit the preset's
/// stored colours — those drive the Breaking / Classic templates
/// and the classic2 variant, never the final3 identity.
///
/// classic2: the design colour IS the factory colour. A stored
/// colour equal to the factory value — or to the final3 value
/// (the #40 migration rewrites stored factory values to the final
/// colours on the built-in preset) — counts as un-customised and
/// renders the factory colour, so classic2's look is unchanged by
/// the migration; any other stored colour is a real user pick and
/// wins, exactly as before.
int finalDesignRibbonColor({
  required int presetColor,
  required int factoryColor,
  required int final3Color,
  required bool isFinal3,
}) {
  if (isFinal3) return final3Color;
  if (presetColor == factoryColor || presetColor == final3Color) {
    return factoryColor;
  }
  return presetColor;
}

/// Text colour for the final3 top ribbon: BLACK on the yellow
/// design colour. v1.5.1 (fix #40): final3's top is ALWAYS the
/// yellow design colour (see [finalDesignRibbonColor]), so its
/// text is always black; every other variant takes white text.
int finalDesignTopTextColor({
  required int presetColor,
  required int factoryColor,
  required bool isFinal3,
}) =>
    isFinal3 ? kFinal3TopTextColor : 0xFFFFFFFF;

/// Chroma-key (green screen) background choice (Phase 3, Template &
/// Studio). The toggle + picker + sensitivity persist on the channel
/// preset for real; the visual chroma effect itself is wired into the
/// export filter graph in Phase 7 (ProChroma / chromaFilterComplex —
/// see lib/services/pro_editor.dart), NOT here.
enum ChromaBackgroundKind {
  /// Bundled studio backdrop (assets/backgrounds/newsroom.jpg).
  newsroom('newsroom', 'Newsroom', 'assets/backgrounds/newsroom.jpg'),

  /// Bundled studio-desk backdrop (assets/backgrounds/studio_desk.jpg).
  studioDesk('studioDesk', 'Studio Desk',
      'assets/backgrounds/studio_desk.jpg'),

  /// A gallery-picked image — its path lives in
  /// [ChannelPreset.chromaBackgroundPath].
  gallery('gallery', 'Your background', null);

  const ChromaBackgroundKind(this.id, this.label, this.assetPath);
  final String id;
  final String label;

  /// Bundled asset path, or null for [gallery] (uses a picked file).
  final String? assetPath;

  static ChromaBackgroundKind fromId(String? id) {
    for (final v in ChromaBackgroundKind.values) {
      if (v.id == id) return v;
    }
    return ChromaBackgroundKind.newsroom;
  }
}

/// Per-ribbon settings — EVERY ribbon has its own (user order 20 Nov 2026):
/// text, colour, speed, direction, font size, show/hide toggle, and which
/// news kind fills it. Tapping a ribbon in Template & Studio opens its
/// settings panel; changing `text` must update the preview immediately
/// (see the paste-to-run contract in the file header).
class RibbonConfig {
  RibbonConfig({
    this.text = '',
    this.color = 0xFF01B0FF,
    this.speed = 1.0,
    this.direction = RibbonDirection.rtl,
    this.fontSize = 20,
    this.enabled = true,
    this.contentKind = RibbonContentKind.current,
  });

  /// Scrolling text. Plain mutable field — read live, never cached, so a
  /// paste updates the preview on the next rebuild (paste-to-run).
  String text;

  /// Ribbon background colour as ARGB (e.g. 0xFF01B0FF).
  int color;

  /// Scroll speed multiplier (1.0 = template default).
  double speed;

  RibbonDirection direction;

  /// Font size in logical pixels (Kasheeda for Urdu, system font for Latin).
  double fontSize;

  /// Show/hide toggle — 0–3 ribbons allowed.
  bool enabled;

  /// Which news fills this ribbon (see RIBBON-CONTENT RULE above).
  RibbonContentKind contentKind;

  RibbonConfig copyWith({
    String? text,
    int? color,
    double? speed,
    RibbonDirection? direction,
    double? fontSize,
    bool? enabled,
    RibbonContentKind? contentKind,
  }) {
    return RibbonConfig(
      text: text ?? this.text,
      color: color ?? this.color,
      speed: speed ?? this.speed,
      direction: direction ?? this.direction,
      fontSize: fontSize ?? this.fontSize,
      enabled: enabled ?? this.enabled,
      contentKind: contentKind ?? this.contentKind,
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'color': color,
        'speed': speed,
        'direction': direction.id,
        'fontSize': fontSize,
        'enabled': enabled,
        'contentKind': contentKind.id,
      };

  static RibbonConfig fromJson(Map<String, dynamic> json) {
    return RibbonConfig(
      text: (json['text'] as String?) ?? '',
      color: (json['color'] as int?) ?? 0xFF01B0FF,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      direction: RibbonDirection.fromId(json['direction'] as String?),
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 20,
      enabled: (json['enabled'] as bool?) ?? true,
      contentKind: RibbonContentKind.fromId(json['contentKind'] as String?),
    );
  }
}

/// One channel's broadcast identity.
class ChannelPreset {
  ChannelPreset({
    required this.id,
    required this.name,
    this.logoPath,
    this.logoRotate = true,
    this.logoMediaKind = 'image',
    this.logoVideoPath,
    this.logoVideoKeyColor,
    this.logoKeyedFramesDir,
    this.logoVideoStillPath,
    Map<String, String>? logoCubeFacePaths,
    this.logoCubeSpeedSec = 6.0,
    this.logoCubeDirection = 'cw',
    this.logoCubeTilt = 0.0,
    this.logoCubePedestal = false,
    this.logoPartsSavedJson = '',
    this.logoPartsSavedAtMs = 0,
    this.logoMakerSettingsJson = '',
    RibbonConfig? topRibbon,
    RibbonConfig? urduRibbon,
    RibbonConfig? englishRibbon,
    this.templateKind = 'nigraanFinal',
    this.finalVariant = kFinalVariant3,
    this.breakingVariant = 'breakingRedBanner',
    this.breakingTickerColor = 0xFF01B0FF,
    this.categoryLabel = '',
    this.showIntro = true,
    this.showOutro = true,
    this.lowerThirdTitle = '',
    this.lowerThirdSubtitle = '',
    this.showLowerThird = true,
    this.showBreakingBanner = true,
    this.interviewName = '',
    this.interviewDesignation = '',
    this.showInterviewPlate = false,
    this.pipEnabled = false,
    this.pipPosition = 'bottomRight',
    this.pipScale = 0.3,
    this.chromaEnabled = false,
    this.chromaBackground = ChromaBackgroundKind.newsroom,
    this.chromaBackgroundPath,
    this.chromaSensitivity = 0.35,
    this.brandColor = 0xFF7C3AED,
    this.socialFacebook = '',
    this.socialYoutube = '',
    this.socialTiktok = '',
    this.socialInstagram = '',
    this.socialX = '',
    this.watermarkEnabled = true,
    this.watermarkPosition = 'bottomRight',
    this.watermarkSize = 0.12,
    this.introAssetPath = AssetDownloadService.introAssetPath,
    this.logoGsAssetPath = AssetDownloadService.logoGsAssetPath,
    this.logoGsFrameAssetPath =
        AssetDownloadService.logoGsFrameAssetPath,
  })  : logoCubeFacePaths = logoCubeFacePaths ?? {},
        topRibbon = topRibbon ?? RibbonConfig(),
        urduRibbon = urduRibbon ??
            RibbonConfig(
              color: 0xFF3D5AFE,
              contentKind: RibbonContentKind.national,
            ),
        englishRibbon = englishRibbon ??
            RibbonConfig(
              color: 0xFFEF0017,
              direction: RibbonDirection.ltr,
              contentKind: RibbonContentKind.international,
            );

  /// Stable id (used as the selected-preset key in the store).
  String id;

  /// Channel name, e.g. 'Nigraan TV'.
  String name;

  /// Gallery-picked logo file path, or null = default channel logo.
  /// Used in the rotating logo-bug spot.
  String? logoPath;

  /// LOGO 3D ROTATION: the logo 3D-rotates in the template —
  /// preview AND export — and a user-replaced logo rotates the
  /// same way. Build 12 (v1.9.0, user order 2026-11-25,
  /// SUPERSEDING the 20 Nov 2026 swing decision): the rotation
  /// is a CONTINUOUS full 360° turn of a real 3D CUBE carrying
  /// the image on its faces (see lib/services/logo_cube.dart);
  /// preview paints the cube live, export renders the same
  /// geometry into a generated frame loop. This flag defaults
  /// to true; turning it off holds the cube at a still 3/4
  /// angle (never a flat static image).
  bool logoRotate;

  /// Build 12 (point #12/#13): the logo SOURCE kind —
  /// 'image' (a picked image, rendered as the rotating 3D
  /// cube; also the default channel tile) or 'video' (a logo
  /// VIDEO in [logoVideoPath], background-keyed — see
  /// [logoVideoKeyColor] / [logoKeyedFramesDir]).
  String logoMediaKind;

  /// The picked logo VIDEO file (kind 'video'), or null.
  String? logoVideoPath;

  /// The detected background colour (ARGB) of the logo video,
  /// auto-sampled from its frame edges by LogoKeyService.
  /// Null = no solid background could be detected (the video
  /// is then used unkeyed — the panel says so honestly).
  int? logoVideoKeyColor;

  /// Directory of alpha PNG frames keyed from the logo video
  /// (preview flipbook + export overlay share them).
  String? logoKeyedFramesDir;

  /// A still extracted from the logo video (keyed when a key
  /// colour exists, plain otherwise) — panel thumbnail and
  /// export fallback.
  String? logoVideoStillPath;

  /// Build 13 (point #19): Logo Cube per-face images — keys
  /// 'front' / 'back' / 'left' / 'right' / 'top' / 'bottom'
  /// (the logo_cube.dart face names) mapped to picked image
  /// paths. A face with no entry carries the main logo image
  /// ([logoPath] / the channel tile), exactly as before.
  Map<String, String> logoCubeFacePaths;

  /// Build 13 (point #19): seconds per full cube revolution
  /// (preview AND export — the shared painter + frame renderer
  /// both take it). Default 6 = the historic preview period.
  double logoCubeSpeedSec;

  /// Build 13 (point #19): cube spin direction — 'cw'
  /// (clockwise, the historic sense) or 'ccw'.
  String logoCubeDirection;

  /// Build 13 (point #19): the cube VIEW tilt (radians about
  /// the screen X axis, the painter's tilt). DEFAULT 0.0 =
  /// 'Front' — the cube faces the viewer squarely (the user's
  /// complaint was the old fixed 0.42 tilt showing the top
  /// face). Presets: Samne 0.0, Upar Se +0.85, Neeche Se -0.85;
  /// the slider range is -1.2..1.2.
  double logoCubeTilt;

  /// Build 13 (point #19): draw a base plate (pedestal) under
  /// the cube. Default FALSE — no pedestal existed before, so
  /// the default look is unchanged.
  bool logoCubePedestal;

  /// Build 13 (point #19): TRANSIENT (never serialised) ticker
  /// speed factor, set on the effective/preview preset clones
  /// from NewsProject.tickerSpeed — the parity geometry
  /// multiplies its strip speed by it. 1.0 = designed speed.
  double tickerSpeedFactor = 1.0;

  /// Build 13 (point #19): TRANSIENT (never serialised) ticker
  /// loop flag, set on the clones from NewsProject.tickerLoop.
  bool tickerLoop = true;

  /// Build 13 (point 6 — Logo Parts Engine): the PAID-SAVED
  /// parts payload (a JSON list of LogoPart) and when it was
  /// saved. The save costs 300 coins and stays usable exactly
  /// 7 days; on expiry the Maker clears both fields — the
  /// settings are gone and saving again costs another 300
  /// (the user's model — no renewal path).
  String logoPartsSavedJson;
  int logoPartsSavedAtMs;

  /// v1.19.0 (Logo Maker integration): the full-screen Logo
  /// Maker section's settings (presets / material / depth /
  /// bevel / shadow / glow / spin) as a JSON string in
  /// LogoMakerSettings' own format. Empty = the maker's
  /// defaults. Rides the same preset JSON as every other logo
  /// setting (cube speed/tilt/pedestal above), so it survives
  /// restarts with the channel preset.
  String logoMakerSettingsJson;

  /// Transient (never serialised): the WORKING parts list —
  /// session-only until paid-saved. Preview/export clones copy
  /// it explicitly (the ticker transients' pattern), and the
  /// Maker restores it from [logoPartsSavedJson] on load while
  /// the save is active.
  List<LogoPart> logoParts = const [];

  /// Transient: the logo file the working parts were split
  /// from (switching to another logo must not silently reuse
  /// them — the panel compares and warns).
  String? logoPartsSourcePath;

  /// Transient (never serialised on its own): the WORKING
  /// Logo Parts SCENE (redesign Build 2) — the glow layer
  /// (Options 28–32) and base plate (Option 33) around
  /// [logoParts]. It rides the same lifecycle as the working
  /// parts: session-only, restored from the paid save payload
  /// ([logoPartsSavedJson], which carries the scene since
  /// Build 2) while the save is active, and copied onto
  /// preview/export clones with the parts.
  LogoPartsScene logoPartsScene = LogoPartsScene();

  /// Top ticker ribbon — CURRENT story (contentKind `current`).
  RibbonConfig topRibbon;

  /// Middle Urdu ribbon — NATIONAL news (contentKind `national`).
  RibbonConfig urduRibbon;

  /// Bottom English ribbon — INTERNATIONAL news (contentKind
  /// `international`).
  RibbonConfig englishRibbon;

  /// Template variant id, e.g. 'nigraanFinal' (final 3-ribbon template).
  String templateKind;

  /// Which Final-template design renders when [templateKind] is
  /// 'nigraanFinal': [kFinalVariant3] (default — the 3-ribbon
  /// PUBLIC-style stack) or [kFinalVariantClassic2] (the v1.3.0
  /// 2-ribbon parity design). Selected in Template Studio next to
  /// the template cards; ignored by the other template kinds.
  String finalVariant;

  /// True when this preset renders the Final 3-Ribbon design.
  bool get finalIs3Ribbon => finalVariant != kFinalVariantClassic2;

  /// Resolved render colours of the three Final-design ribbons
  /// (see [finalDesignRibbonColor]): for the Final 3-Ribbon design
  /// these are ALWAYS the fixed design colours (fix #40); for
  /// classic2 they are the factory colours unless the user picked
  /// a custom colour.
  int get designTopColor => finalDesignRibbonColor(
        presetColor: topRibbon.color,
        factoryColor: kFactoryTopRibbonColor,
        final3Color: kFinal3TopColor,
        isFinal3: finalIs3Ribbon,
      );
  int get designUrduColor => finalDesignRibbonColor(
        presetColor: urduRibbon.color,
        factoryColor: kFactoryUrduRibbonColor,
        final3Color: kFinal3UrduColor,
        isFinal3: finalIs3Ribbon,
      );
  int get designEnglishColor => finalDesignRibbonColor(
        presetColor: englishRibbon.color,
        factoryColor: kFactoryEnglishRibbonColor,
        final3Color: kFinal3EnglishColor,
        isFinal3: finalIs3Ribbon,
      );

  /// Resolved text colour for the Final top ribbon (see
  /// [finalDesignTopTextColor]): BLACK on the yellow design top,
  /// WHITE when the user picked a custom top colour.
  int get designTopTextColor => finalDesignTopTextColor(
        presetColor: topRibbon.color,
        factoryColor: kFactoryTopRibbonColor,
        isFinal3: finalIs3Ribbon,
      );

  /// Which of the four breaking variants this preset uses when
  /// [templateKind] is 'breaking' (a [BreakingVariant] id — see
  /// lib/news/breaking_templates.dart). Phase 6.
  String breakingVariant;

  /// Top ticker strip colour for the Breaking + Ticker combo variant
  /// (house ticker blue #01B0FF by default). The combo's banner uses
  /// the top ribbon's colour, so its ticker strip needs its own
  /// slot — otherwise the banner colour would swallow it.
  int breakingTickerColor;

  /// News category label shown as a small chip on the template
  /// (e.g. 'PAKISTAN', 'SPORTS') — master prompt §5, Phase 6.
  /// Empty = no chip. The user types it; it is never invented.
  String categoryLabel;

  /// 10s intro asset on/off; 3s outro end card on/off.
  bool showIntro;
  bool showOutro;

  /// Lower third (reporter name + place) defaults for this channel.
  String lowerThirdTitle;
  String lowerThirdSubtitle;
  bool showLowerThird;

  bool showBreakingBanner;

  /// Interview name plate (master prompt §5, Phase 6): the
  /// interviewee's name + designation, rendered as a plate above
  /// the lower third when [showInterviewPlate] is on and [interviewName]
  /// is non-empty. A separate plate from the reporter's lower third —
  /// both can be on at once (the plate stacks above it).
  String interviewName;
  String interviewDesignation;
  bool showInterviewPlate;

  /// Picture-in-picture (master prompt §5, Phase 6): the PIP inset
  /// position + size the export will use. The toggle + settings
  /// persist here and the preview draws the inset where the export
  /// will put it; the visual PIP effect itself is wired into the
  /// export filter graph in Phase 7 ([pipOverlayFilter] in
  /// lib/services/fx_pack.dart already exists — the editor uses it
  /// today). [pipPosition] is a [PipPositionId] ('topLeft',
  /// 'topRight', 'bottomLeft', 'bottomRight'); [pipScale] is the
  /// inset width as a fraction of the frame width (0.15–0.5).
  bool pipEnabled;
  String pipPosition;
  double pipScale;

  /// PIP corner ids (mirror [PipPosition] in lib/services/fx_pack.dart;
  /// kept as plain strings here so this model stays UI-free — Phase 7
  /// maps them to the filter when wiring the export).
  static const List<String> pipPositionIds = [
    'topLeft',
    'topRight',
    'bottomLeft',
    'bottomRight',
  ];

  static const Map<String, String> pipPositionLabels = {
    'topLeft': 'Top left',
    'topRight': 'Top right',
    'bottomLeft': 'Bottom left',
    'bottomRight': 'Bottom right',
  };

  /// Chroma key (green screen) — Phase 3 persists the toggle, the
  /// background choice and the sensitivity on the preset; the visual
  /// effect is wired in the export graph in Phase 7. Defaults match
  /// mockup 3 (off, Newsroom, 0.35).
  bool chromaEnabled;
  ChromaBackgroundKind chromaBackground;

  /// Gallery-picked background image path (only when
  /// [chromaBackground] is [ChromaBackgroundKind.gallery]).
  String? chromaBackgroundPath;

  /// Chroma sensitivity 0.05..1.0 (ProChroma `similarity`).
  double chromaSensitivity;

  // --- Channel branding (Phase 8, master prompt §9) -----------------
  // The preset's brand identity: brand colour, social handles and the
  // watermark. These AUTO-APPLY: every new project renders from its
  // preset, so changing them here changes what new projects (and
  // template previews + the reel export) render — no per-project
  // copy step exists to go stale. [effectivePresetFor] copies the
  // preset through toJson/fromJson, so the branding travels with it.

  /// Primary brand colour (AR, e.g. 0xFF7C3AED) — used for the
  /// channel tile / initial tile and the branding screen accent.
  int brandColor;

  /// Social handles, one per platform. Empty = the channel has no
  /// handle there — and NO placeholder handle is ever shown or
  /// exported (see [socialHandles] / [socialHandleLines]).
  String socialFacebook;
  String socialYoutube;
  String socialTiktok;
  String socialInstagram;
  String socialX;

  /// Watermark on exported reels: the channel mark (logo file when
  /// set, else the channel-initial tile) overlaid in the export
  /// graph (see `FfmpegService.watermarkOverlayCommand` + the
  /// watermark step in `ReelExportService.exportReel`). Toggleable
  /// per preset; [watermarkPosition] is a [watermarkPositionIds] id;
  /// [watermarkSize] is the mark width as a fraction of the frame
  /// width (0.05–0.30).
  bool watermarkEnabled;
  String watermarkPosition;
  double watermarkSize;

  /// Build 7 (v1.5.9, Phase 8 generic branding): the channel's
  /// bundled media — intro video, green-screen logo video and
  /// its keyed still frame. These used to be Nigraan-only
  /// literals inside the export/preview; they now live on the
  /// preset (defaulting to the Nigraan TV assets, so the default
  /// channel's behaviour is byte-for-byte unchanged) and another
  /// channel's preset can point at its own files. Serialized;
  /// old preset JSON without the keys loads with the defaults.
  String introAssetPath;
  String logoGsAssetPath;
  String logoGsFrameAssetPath;

  /// Watermark corner ids + labels (mirror [pipPositionIds]).
  static const List<String> watermarkPositionIds = [
    'topLeft',
    'topRight',
    'bottomLeft',
    'bottomRight',
  ];

  static const Map<String, String> watermarkPositionLabels = {
    'topLeft': 'Top left',
    'topRight': 'Top right',
    'bottomLeft': 'Bottom left',
    'bottomRight': 'Bottom right',
  };

  /// Only the handles the user actually entered, keyed by platform
  /// ('facebook', 'youtube', 'tiktok', 'instagram', 'x'). Never a
  /// placeholder: an empty handle is simply absent.
  Map<String, String> get socialHandles {
    final handles = <String, String>{};
    if (socialFacebook.trim().isNotEmpty) {
      handles['facebook'] = socialFacebook.trim();
    }
    if (socialYoutube.trim().isNotEmpty) {
      handles['youtube'] = socialYoutube.trim();
    }
    if (socialTiktok.trim().isNotEmpty) {
      handles['tiktok'] = socialTiktok.trim();
    }
    if (socialInstagram.trim().isNotEmpty) {
      handles['instagram'] = socialInstagram.trim();
    }
    if (socialX.trim().isNotEmpty) {
      handles['x'] = socialX.trim();
    }
    return handles;
  }

  bool get hasSocialHandles => socialHandles.isNotEmpty;

  /// Display lines for the handles — 'Facebook: Nigraan TV' etc. —
  /// shown in the branding screen, the Templates Library card footer
  /// and the export end card. Empty when there are no handles (never
  /// a placeholder line).
  List<String> socialHandleLines() {
    const labels = {
      'facebook': 'Facebook',
      'youtube': 'YouTube',
      'tiktok': 'TikTok',
      'instagram': 'Instagram',
      'x': 'X',
    };
    return socialHandles.entries
        .map((e) => '${labels[e.key] ?? e.key}: ${e.value}')
        .toList();
  }

  // Convenience accessors for the three house colours.
  int get tickerColor => topRibbon.color;
  int get urduColor => urduRibbon.color;
  int get englishColor => englishRibbon.color;
  bool get showTicker => topRibbon.enabled;
  bool get showUrdu => urduRibbon.enabled;
  bool get showEnglish => englishRibbon.enabled;

  /// The built-in Nigraan TV preset — the default channel.
  /// Colours: ticker #01B0FF, Urdu #3D5AFE, English #EF0017.
  /// Ribbon texts start empty: the top ribbon is filled per story (the
  /// user pastes the current story's ticker text — paste-to-run), the
  /// middle ribbon is filled from the national-news feed and the bottom
  /// from the international feed (Phase 3 ticker engine). No invented
  /// headlines are ever baked in as defaults.
  static ChannelPreset nigraanTv() {
    return ChannelPreset(
      id: 'nigraan-tv',
      name: 'Nigraan TV',
      brandColor: 0xFF7C3AED,
      socialFacebook: 'Nigraan TV',
      socialYoutube: '@nigraantvxyz',
      socialTiktok: '@nigraantv',
      socialInstagram: '@nigraantv',
      socialX: '@nigraantv',
      watermarkEnabled: true,
      watermarkPosition: 'bottomRight',
      watermarkSize: 0.12,
      templateKind: 'nigraanFinal',
      // v1.3.0 (§9 parity): the REAL final template has NO top
      // ribbon and NO outro — the top ribbon stays available as an
      // option the user can switch on, and the outro likewise.
      // 22 Nov 2026 (Final 3-Ribbon rework): the default design is
      // now 'final3', whose TOP ribbon is the stack's first ribbon
      // (current story) — so its toggle defaults ON. Under
      // 'classic2' the same toggle is the optional frame-top
      // ticker; it stays live there too (switch it off in the
      // ribbon settings for the strict 2-ribbon look).
      finalVariant: kFinalVariant3,
      showOutro: false,
      // v1.5.1 (fix #40): the built-in preset ships with the
      // declared-FINAL design colours (yellow / red / navy), not
      // the old v1.4 factory scheme.
      topRibbon: RibbonConfig(
        text: '',
        color: kFinal3TopColor,
        speed: 1.0,
        direction: RibbonDirection.rtl,
        fontSize: 20,
        enabled: true,
        contentKind: RibbonContentKind.current,
      ),
      urduRibbon: RibbonConfig(
        text: '',
        color: kFinal3UrduColor,
        speed: 1.0,
        direction: RibbonDirection.rtl,
        fontSize: 20,
        enabled: true,
        contentKind: RibbonContentKind.national,
      ),
      englishRibbon: RibbonConfig(
        text: '',
        color: kFinal3EnglishColor,
        speed: 1.0,
        direction: RibbonDirection.ltr,
        fontSize: 18,
        enabled: true,
        contentKind: RibbonContentKind.international,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'logoPath': logoPath,
        'logoRotate': logoRotate,
        'logoMediaKind': logoMediaKind,
        'logoVideoPath': logoVideoPath,
        'logoVideoKeyColor': logoVideoKeyColor,
        'logoKeyedFramesDir': logoKeyedFramesDir,
        'logoVideoStillPath': logoVideoStillPath,
        'logoCubeFacePaths': logoCubeFacePaths,
        'logoCubeSpeedSec': logoCubeSpeedSec,
        'logoCubeDirection': logoCubeDirection,
        'logoCubeTilt': logoCubeTilt,
        'logoCubePedestal': logoCubePedestal,
        'logoPartsSavedJson': logoPartsSavedJson,
        'logoPartsSavedAtMs': logoPartsSavedAtMs,
        'logoMakerSettingsJson': logoMakerSettingsJson,
        'topRibbon': topRibbon.toJson(),
        'urduRibbon': urduRibbon.toJson(),
        'englishRibbon': englishRibbon.toJson(),
        'templateKind': templateKind,
        'finalVariant': finalVariant,
        'breakingVariant': breakingVariant,
        'breakingTickerColor': breakingTickerColor,
        'categoryLabel': categoryLabel,
        'showIntro': showIntro,
        'showOutro': showOutro,
        'lowerThirdTitle': lowerThirdTitle,
        'lowerThirdSubtitle': lowerThirdSubtitle,
        'showLowerThird': showLowerThird,
        'showBreakingBanner': showBreakingBanner,
        'interviewName': interviewName,
        'interviewDesignation': interviewDesignation,
        'showInterviewPlate': showInterviewPlate,
        'pipEnabled': pipEnabled,
        'pipPosition': pipPosition,
        'pipScale': pipScale,
        'chromaEnabled': chromaEnabled,
        'chromaBackground': chromaBackground.id,
        'chromaBackgroundPath': chromaBackgroundPath,
        'chromaSensitivity': chromaSensitivity,
        'brandColor': brandColor,
        'socialFacebook': socialFacebook,
        'socialYoutube': socialYoutube,
        'socialTiktok': socialTiktok,
        'socialInstagram': socialInstagram,
        'socialX': socialX,
        'watermarkEnabled': watermarkEnabled,
        'watermarkPosition': watermarkPosition,
        'watermarkSize': watermarkSize,
        'introAssetPath': introAssetPath,
        'logoGsAssetPath': logoGsAssetPath,
        'logoGsFrameAssetPath': logoGsFrameAssetPath,
      };

  static ChannelPreset fromJson(Map<String, dynamic> json) {
    RibbonConfig ribbon(String key, RibbonConfig fallback) {
      final raw = json[key];
      if (raw is Map<String, dynamic>) return RibbonConfig.fromJson(raw);
      return fallback;
    }

    return ChannelPreset(
      id: (json['id'] as String?) ?? 'custom',
      name: (json['name'] as String?) ?? 'Channel',
      logoPath: json['logoPath'] as String?,
      // Rotation defaults ON — an old saved preset without the flag
      // still rotates.
      logoRotate: (json['logoRotate'] as bool?) ?? true,
      // Build 12: absent on pre-v1.9.0 saves → the image source.
      logoMediaKind: (json['logoMediaKind'] as String?) ?? 'image',
      logoVideoPath: json['logoVideoPath'] as String?,
      logoVideoKeyColor: json['logoVideoKeyColor'] as int?,
      logoKeyedFramesDir: json['logoKeyedFramesDir'] as String?,
      logoVideoStillPath: json['logoVideoStillPath'] as String?,
      // Build 13: absent on pre-v1.10.0 saves -> defaults
      // (no per-face images, 6 s revolution, clockwise, Samne
      // view, no pedestal).
      logoCubeFacePaths: (json['logoCubeFacePaths'] as Map?)
              ?.map(
                (k, v) => MapEntry(k.toString(), v.toString()),
              ) ??
          const {},
      logoCubeSpeedSec:
          (json['logoCubeSpeedSec'] as num?)?.toDouble() ?? 6.0,
      logoCubeDirection:
          (json['logoCubeDirection'] as String?) ?? 'cw',
      logoCubeTilt: (json['logoCubeTilt'] as num?)?.toDouble() ?? 0.0,
      logoCubePedestal: (json['logoCubePedestal'] as bool?) ?? false,
      logoPartsSavedJson:
          (json['logoPartsSavedJson'] as String?) ?? '',
      logoPartsSavedAtMs:
          ((json['logoPartsSavedAtMs'] as num?) ?? 0).toInt(),
      logoMakerSettingsJson:
          (json['logoMakerSettingsJson'] as String?) ?? '',
      topRibbon: ribbon('topRibbon', RibbonConfig()),
      urduRibbon: ribbon(
        'urduRibbon',
        RibbonConfig(
          color: 0xFF3D5AFE,
          contentKind: RibbonContentKind.national,
        ),
      ),
      englishRibbon: ribbon(
        'englishRibbon',
        RibbonConfig(
          color: 0xFFEF0017,
          direction: RibbonDirection.ltr,
          contentKind: RibbonContentKind.international,
        ),
      ),
      templateKind: (json['templateKind'] as String?) ?? 'nigraanFinal',
      // Absent on pre-rework saves → the NEW default design.
      finalVariant:
          (json['finalVariant'] as String?) ?? kFinalVariant3,
      breakingVariant:
          (json['breakingVariant'] as String?) ?? 'breakingRedBanner',
      breakingTickerColor:
          (json['breakingTickerColor'] as int?) ?? 0xFF01B0FF,
      categoryLabel: (json['categoryLabel'] as String?) ?? '',
      showIntro: (json['showIntro'] as bool?) ?? true,
      // v1.3.0 (§9.10): no default end card for the final template
      // — stored values still win, but an ABSENT key on a
      // nigraanFinal preset means OFF (the reference has no outro).
      showOutro: (json['showOutro'] as bool?) ??
          (((json['templateKind'] as String?) ?? 'nigraanFinal') !=
              'nigraanFinal'),
      lowerThirdTitle: (json['lowerThirdTitle'] as String?) ?? '',
      lowerThirdSubtitle: (json['lowerThirdSubtitle'] as String?) ?? '',
      showLowerThird: (json['showLowerThird'] as bool?) ?? true,
      showBreakingBanner: (json['showBreakingBanner'] as bool?) ?? true,
      interviewName: (json['interviewName'] as String?) ?? '',
      interviewDesignation:
          (json['interviewDesignation'] as String?) ?? '',
      showInterviewPlate: (json['showInterviewPlate'] as bool?) ?? false,
      pipEnabled: (json['pipEnabled'] as bool?) ?? false,
      pipPosition: (json['pipPosition'] as String?) ?? 'bottomRight',
      pipScale: (json['pipScale'] as num?)?.toDouble() ?? 0.3,
      chromaEnabled: (json['chromaEnabled'] as bool?) ?? false,
      chromaBackground: ChromaBackgroundKind.fromId(
        json['chromaBackground'] as String?,
      ),
      chromaBackgroundPath: json['chromaBackgroundPath'] as String?,
      chromaSensitivity:
          (json['chromaSensitivity'] as num?)?.toDouble() ?? 0.35,
      brandColor: (json['brandColor'] as int?) ?? 0xFF7C3AED,
      socialFacebook: (json['socialFacebook'] as String?) ?? '',
      socialYoutube: (json['socialYoutube'] as String?) ?? '',
      socialTiktok: (json['socialTiktok'] as String?) ?? '',
      socialInstagram: (json['socialInstagram'] as String?) ?? '',
      socialX: (json['socialX'] as String?) ?? '',
      watermarkEnabled: (json['watermarkEnabled'] as bool?) ?? true,
      watermarkPosition:
          (json['watermarkPosition'] as String?) ?? 'bottomRight',
      watermarkSize:
          (json['watermarkSize'] as num?)?.toDouble() ?? 0.12,
      // Build 7 generic branding: absent on old saves → the
      // Nigraan TV assets (the constructor defaults).
      introAssetPath: (json['introAssetPath'] as String?) ??
          AssetDownloadService.introAssetPath,
      logoGsAssetPath: (json['logoGsAssetPath'] as String?) ??
          AssetDownloadService.logoGsAssetPath,
      logoGsFrameAssetPath:
          (json['logoGsFrameAssetPath'] as String?) ??
              AssetDownloadService.logoGsFrameAssetPath,
    );
  }
}

/// JSON store for channel presets (same pattern as `NewsTemplate.save/load`).
class ChannelPresetStore {
  static const _fileName = 'channel_presets.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// Loads all saved presets; returns just the built-in Nigraan TV preset
  /// when nothing is saved yet (or the file is unreadable).
  static Future<List<ChannelPreset>> loadAll() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map<String, dynamic>) {
          final raw = data['presets'];
          if (raw is List) {
            final presets = <ChannelPreset>[];
            for (final item in raw) {
              if (item is Map<String, dynamic>) {
                presets.add(ChannelPreset.fromJson(item));
              }
            }
            if (presets.isNotEmpty) {
              // v1.5.1 (fix #40) migration: a built-in Nigraan TV
              // preset saved by an older version still carries the
              // OLD factory ribbon colours — rewrite any band that
              // still holds its old factory value to the Final
              // design colour and persist once, so every surface
              // that reads the preset's own colours (Template &
              // Studio, Channel Branding, swatches) shows the
              // Final scheme. A band the user deliberately set to
              // any other colour is left untouched.
              var migrated = false;
              for (final preset in presets) {
                if (preset.id != 'nigraan-tv') continue;
                if (preset.topRibbon.color == kFactoryTopRibbonColor) {
                  preset.topRibbon.color = kFinal3TopColor;
                  migrated = true;
                }
                if (preset.urduRibbon.color == kFactoryUrduRibbonColor) {
                  preset.urduRibbon.color = kFinal3UrduColor;
                  migrated = true;
                }
                if (preset.englishRibbon.color ==
                    kFactoryEnglishRibbonColor) {
                  preset.englishRibbon.color = kFinal3EnglishColor;
                  migrated = true;
                }
              }
              if (migrated) {
                await saveAll(
                  presets,
                  selectedId: data['selectedId'] as String?,
                );
              }
              return presets;
            }
          }
        }
      }
    } catch (_) {}
    return [ChannelPreset.nigraanTv()];
  }

  /// Id of the selected preset, or null = first preset.
  static Future<String?> loadSelectedId() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map<String, dynamic>) {
          return data['selectedId'] as String?;
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> saveAll(
    List<ChannelPreset> presets, {
    String? selectedId,
  }) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode({
        'presets': presets.map((e) => e.toJson()).toList(),
        'selectedId': selectedId,
      }));
    } catch (_) {
      // Preset persistence is a convenience; a failed save must never
      // block editing or exporting with the in-memory presets.
    }
  }

  /// Deletes a saved custom preset by [id]. The built-in Nigraan TV
  /// preset cannot be deleted (its id never starts with 'custom_').
  /// The selected preset falls back to the first remaining preset.
  static Future<void> deletePreset(String id) async {
    if (!id.startsWith('custom_')) return;
    final presets = await loadAll();
    presets.removeWhere((p) => p.id == id);
    if (presets.isEmpty) presets.add(ChannelPreset.nigraanTv());
    final selectedId = await loadSelectedId();
    await saveAll(
      presets,
      selectedId: selectedId == id ? presets.first.id : selectedId,
    );
  }

  /// SAVE CUSTOM TEMPLATE (user order 20 Nov 2026, v1 MUST-HAVE):
  /// saves the given preset's current settings — ribbons, colours, speed,
  /// direction, size, logo, intro/outro, lower third — as a NEW named
  /// preset entry that shows up in the preset picker / Templates Library
  /// and is reusable in every project. Returns the saved copy.
  static Future<ChannelPreset> saveCustomTemplate({
    required String name,
    required ChannelPreset preset,
  }) async {
    final saved = ChannelPreset(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Custom Template' : name.trim(),
      logoPath: preset.logoPath,
      logoRotate: preset.logoRotate,
      logoMediaKind: preset.logoMediaKind,
      logoVideoPath: preset.logoVideoPath,
      logoVideoKeyColor: preset.logoVideoKeyColor,
      logoKeyedFramesDir: preset.logoKeyedFramesDir,
      logoVideoStillPath: preset.logoVideoStillPath,
      topRibbon: preset.topRibbon.copyWith(),
      urduRibbon: preset.urduRibbon.copyWith(),
      englishRibbon: preset.englishRibbon.copyWith(),
      templateKind: preset.templateKind,
      finalVariant: preset.finalVariant,
      breakingVariant: preset.breakingVariant,
      breakingTickerColor: preset.breakingTickerColor,
      categoryLabel: preset.categoryLabel,
      showIntro: preset.showIntro,
      showOutro: preset.showOutro,
      lowerThirdTitle: preset.lowerThirdTitle,
      lowerThirdSubtitle: preset.lowerThirdSubtitle,
      showLowerThird: preset.showLowerThird,
      showBreakingBanner: preset.showBreakingBanner,
      interviewName: preset.interviewName,
      interviewDesignation: preset.interviewDesignation,
      showInterviewPlate: preset.showInterviewPlate,
      pipEnabled: preset.pipEnabled,
      pipPosition: preset.pipPosition,
      pipScale: preset.pipScale,
      chromaEnabled: preset.chromaEnabled,
      chromaBackground: preset.chromaBackground,
      chromaBackgroundPath: preset.chromaBackgroundPath,
      chromaSensitivity: preset.chromaSensitivity,
      brandColor: preset.brandColor,
      socialFacebook: preset.socialFacebook,
      socialYoutube: preset.socialYoutube,
      socialTiktok: preset.socialTiktok,
      socialInstagram: preset.socialInstagram,
      socialX: preset.socialX,
      watermarkEnabled: preset.watermarkEnabled,
      watermarkPosition: preset.watermarkPosition,
      watermarkSize: preset.watermarkSize,
      introAssetPath: preset.introAssetPath,
      logoGsAssetPath: preset.logoGsAssetPath,
      logoGsFrameAssetPath: preset.logoGsFrameAssetPath,
    );
    final presets = await loadAll();
    presets.add(saved);
    await saveAll(presets, selectedId: saved.id);
    return saved;
  }
}
