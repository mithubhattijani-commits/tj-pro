/// Breaking News templates for News Studio (v1).
///
/// Four variants, all shown in the Templates Library. Every variant is
/// fully customizable per template (headline/ticker text, ribbon colours,
/// speed, direction, font size, show/hide per ribbon) with a per-ribbon
/// colour picker (swatches). Stored per channel preset + per project, same
/// JSON pattern as `NewsTemplate` (`news_template.json`); rendered via the
/// PNG-overlay path (extend `renderLiveTemplateImage`).
///
/// RIBBON-CONTENT RULE (user, 20 Nov 2026 — same rule as ChannelPreset,
/// binds every phase that touches the 3-ribbon template):
///   TOP ribbon    = CURRENT khabar (us waqt ki story).
///   MIDDLE (Urdu) = NATIONAL NEWS (doosri qomi khabrein — NEVER the
///                     current story).
///   BOTTOM (English) = INTERNATIONAL news.
/// Encoded as [RibbonContentKind] per ribbon (imported from
/// channel_preset.dart). The Breaking + Ticker combo variant carries the
/// full 3-ribbon set below its breaking banner, so the rule applies to it
/// exactly as it applies to the final 3-ribbon template.
///
/// v1.2.0 — VIDEO INTRO TEMPLATES + BUILT-IN MUSIC:
/// two bundled video intro templates ([VideoIntroTemplate]:
/// "Studio Breaking News" + "Globe Breaking News") join the Templates
/// Library as optional, FREE, one-tap-apply entries — they are NOT
/// [BreakingVariant] values on purpose: the PNG renderer in
/// lib/live/news_template.dart switches exhaustively over
/// [BreakingVariant], so new variants would break that file. The
/// library registers them through its existing item registry (kind
/// 'videoIntro'); their headline / ticker text / ticker direction /
/// background music persist per project (see [NewsProject]) and the
/// headline + ticker + direction also sync into the channel preset's
/// top ribbon, so the existing breaking export path
/// ([BreakingTemplate.fromProject] → renderLiveTemplateImage) renders
/// the same headline + ticker on exported reels. The four bundled
/// news-music MP3s are registered as [BuiltInNewsMusic] (FREE).
///
/// TICKER PASTE-TO-RUN (user, 20 Nov 2026 — v1 MUST-HAVE):
/// pasting text into the ticker field must make the ticker run AT ONCE —
/// no extra step. `tickerText` is a plain mutable field, read LIVE on
/// every preview frame / render call and never cached by the model. A
/// screen's `onChanged` must rebuild immediately (setState /
/// ValueNotifier) so the preview scrolls the new text the moment it is
/// pasted. Export renders the same ticker text (Phase 3/7). Urdu ticker
/// text renders in Jameel Noori Nastaleeq Kasheeda, direction/speed from
/// the template's own settings.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'channel_preset.dart';
import 'news_project.dart';

export 'channel_preset.dart'
    show RibbonContentKind, RibbonDirection;

/// The four breaking-news template variants (v1).
enum BreakingVariant {
  /// Full-width red banner (#D50000) top, big white "BREAKING NEWS" chip,
  /// black scrolling ticker bottom, logo bug + time capsule.
  /// FREE (built-in).
  breakingRedBanner('breakingRedBanner', 'Breaking Red Banner', 0),

  /// Blue/white banner (#1E88E5 top bar, white ticker strip),
  /// "LATEST NEWS" chip. Calmer than red. 25 coins.
  latestNews('latestNews', 'Latest News', 25),

  /// White headline bar (headline text, dark) top + blue scrolling ticker
  /// bottom + logo bug. No red. 25 coins.
  topHeadlineBar('topHeadlineBar', 'Top Headline Bar', 25),

  /// Red breaking banner + the final 3-ribbon template below it
  /// (ticker #01B0FF, Urdu #3D5AFE, English #EF0017 half-thickness).
  /// The breaking version of the Nigraan final template — the
  /// RIBBON-CONTENT RULE applies to its three ribbons. 25 coins.
  breakingTickerCombo('breakingTickerCombo', 'Breaking + Ticker Combo', 25);

  const BreakingVariant(this.id, this.label, this.coinCost);
  final String id;
  final String label;

  /// Coin cost to use this template (0 = free, built-in).
  final int coinCost;

  static BreakingVariant fromId(String? id) {
    for (final v in BreakingVariant.values) {
      if (v.id == id) return v;
    }
    return BreakingVariant.breakingRedBanner;
  }
}

/// True when [text] contains Arabic/Urdu-script characters.
bool tickerTextIsUrduScript(String text) =>
    RegExp(r'[\u0600-\u06FF]').hasMatch(text);

/// Default ticker scroll direction for [text] when the user has not
/// overridden it (v1.2.0 §2.2): Urdu-script text scrolls
/// right-to-left (toward the Left — the side that reads correctly
/// for RTL), Latin/English text scrolls left-to-right (toward the
/// Right). The user's toggle always wins over this default.
RibbonDirection defaultTickerDirectionForText(String text) =>
    tickerTextIsUrduScript(text)
        ? RibbonDirection.rtl
        : RibbonDirection.ltr;

/// One bundled VIDEO intro template (v1.2.0 §2.1): a ready-made MP4
/// intro (fixed broadcast labels baked into the video; the headline
/// zone + bottom ribbon band stay empty in the video itself — the
/// app renders the user's headline + scrolling ticker on top, in
/// preview via `VideoIntroPreview` and in export via the existing
/// breaking-template overlay path). FREE, built-in, optional —
/// applying one is always a user tap, never forced.
class VideoIntroTemplate {
  const VideoIntroTemplate({
    required this.id,
    required this.label,
    required this.assetPath,
    required this.description,
    required this.categories,
    this.coinCost = 0,
  });

  /// Stable id, stored on the project as `videoTemplateId`.
  final String id;

  /// Picker display name.
  final String label;

  /// Bundled asset path (registered in pubspec by the coordinator).
  final String assetPath;

  final String description;

  /// Templates Library categories this entry shows under.
  final List<String> categories;

  /// 0 = FREE (both built-in video intros are free).
  final int coinCost;

  bool get isFree => coinCost == 0;

  String get displayName => label;

  /// The two v1.2.0 built-in video intro templates.
  static List<VideoIntroTemplate> defaults() {
    return const [
      VideoIntroTemplate(
        id: 'studioBreakingNews',
        label: 'Studio Breaking News',
        assetPath: 'assets/templates/intro_studio.mp4',
        description:
            '3D news studio, BREAKING NEWS label, green-screen end card',
        categories: ['breaking', 'bulletins'],
      ),
      VideoIntroTemplate(
        id: 'globeBreakingNews',
        label: 'Globe Breaking News',
        assetPath: 'assets/templates/intro_globe.mp4',
        description: 'Dark/gold 3D globe breaking-news intro',
        categories: ['breaking', 'international'],
      ),
    ];
  }

  static VideoIntroTemplate? fromId(String? id) {
    for (final t in defaults()) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// One bundled built-in background-music track (v1.2.0 §2.4).
/// Built-in music is always FREE (coinCost 0). The selection persists
/// per project as `NewsProject.backgroundMusicAsset` (and on
/// [BreakingTemplate.backgroundMusicAsset] for template snapshots).
class BuiltInNewsMusic {
  const BuiltInNewsMusic({
    required this.id,
    required this.label,
    required this.assetPath,
    this.coinCost = 0,
  });

  final String id;
  final String label;

  /// Bundled asset path (registered in pubspec by the coordinator).
  final String assetPath;

  /// 0 = FREE — built-in music never costs coins.
  final int coinCost;

  bool get isFree => coinCost == 0;

  /// The four v1.2.0 bundled news themes.
  static List<BuiltInNewsMusic> defaults() {
    return const [
      BuiltInNewsMusic(
        id: 'news_music_1',
        label: 'News Theme 1',
        assetPath: 'assets/music/news_music_1.mp3',
      ),
      BuiltInNewsMusic(
        id: 'news_music_2',
        label: 'News Theme 2',
        assetPath: 'assets/music/news_music_2.mp3',
      ),
      BuiltInNewsMusic(
        id: 'news_music_3',
        label: 'News Theme 3',
        assetPath: 'assets/music/news_music_3.mp3',
      ),
      BuiltInNewsMusic(
        id: 'news_music_4',
        label: 'News Theme 4',
        assetPath: 'assets/music/news_music_4.mp3',
      ),
    ];
  }

  static BuiltInNewsMusic? fromAsset(String? assetPath) {
    for (final m in defaults()) {
      if (m.assetPath == assetPath) return m;
    }
    return null;
  }
}

/// One breaking-news template instance (a variant + the user's edits).
class BreakingTemplate {
  BreakingTemplate({
    String? id,
    this.name,
    this.isCustom = false,
    required this.variant,
    this.headline = '',
    this.tickerText = '',
    this.middleText = '',
    this.bottomText = '',
    this.categoryLabel = '',
    this.topColor = 0xFFD50000,
    this.middleColor = 0xFF3D5AFE,
    this.bottomColor = 0xFFEF0017,
    this.tickerColor = 0xFF01B0FF,
    this.topContentKind = RibbonContentKind.current,
    this.middleContentKind = RibbonContentKind.national,
    this.bottomContentKind = RibbonContentKind.international,
    this.speed = 1.0,
    this.direction = RibbonDirection.rtl,
    this.fontSize = 20,
    this.showRibbons = true,
    this.showTop = true,
    this.showMiddle = true,
    this.showBottom = true,
    this.logoPath,
    this.logoRotate = true,
    this.logoMediaKind = 'image',
    this.logoVideoPath,
    this.logoVideoKeyColor,
    this.logoKeyedFramesDir,
    this.logoVideoStillPath,
    this.showIntro = true,
    this.showOutro = true,
    this.lowerThirdTitle = '',
    this.lowerThirdSubtitle = '',
    this.showLowerThird = true,
    this.interviewName = '',
    this.interviewDesignation = '',
    this.showInterviewPlate = false,
    this.pipEnabled = false,
    this.pipPosition = 'bottomRight',
    this.pipScale = 0.3,
    this.backgroundMusicAsset,
  }) : id = id ?? variant.id;

  /// Stable id. Built-ins use the variant id; saved customs get a
  /// `custom_<millis>` id.
  String id;

  /// Display name. Null for built-ins (the variant label is used);
  /// the user-given name for saved custom templates.
  String? name;

  /// True when this is a user-saved custom template (see
  /// [BreakingTemplateStore.saveCustomTemplate]).
  bool isCustom;

  BreakingVariant variant;

  /// Breaking headline text.
  String headline;

  /// Scrolling ticker text. Plain mutable field — read live, never cached,
  /// so a paste updates the preview on the next rebuild (paste-to-run).
  String tickerText;

  /// Middle Urdu ribbon text (national news) and bottom English ribbon
  /// text (international) — only the Breaking + Ticker combo variant
  /// has these ribbons. Empty = the ribbon draws its strip + chip
  /// with no text (never an invented headline). Filled from the
  /// channel preset's ribbons by [fromPreset]/[fromProject].
  String middleText;
  String bottomText;

  /// News category label chip (e.g. 'PAKISTAN', 'SPORTS') — master
  /// prompt §5, Phase 6. Empty = no chip. The user types it; it is
  /// never invented.
  String categoryLabel;

  /// Ribbon colours as ARGB. Top = banner/ticker, middle = Urdu ribbon,
  /// bottom = English ribbon. Changeable per ribbon via the swatch picker.
  ///
  /// Per-variant roles (the renderer documents them too):
  ///   breakingRedBanner — topColor = red banner, bottomColor = the
  ///     black scrolling ticker strip (default black).
  ///   latestNews — topColor = blue top bar, bottomColor = the white
  ///     ticker strip (default white, dark text).
  ///   topHeadlineBar — topColor = white headline bar, bottomColor =
  ///     the blue ticker strip.
  ///   breakingTickerCombo — topColor = red banner, middleColor = Urdu
  ///     ribbon, bottomColor = English ribbon; the top ticker strip
  ///     uses [tickerColor] (house ticker blue).
  int topColor;
  int middleColor;
  int bottomColor;

  /// Top ticker strip colour — only the Breaking + Ticker combo
  /// variant has a top ticker strip below its banner (house ticker
  /// blue #01B0FF by default, same as the final 3-ribbon template).
  int tickerColor;

  /// Which news fills each ribbon (RIBBON-CONTENT RULE — see file header).
  /// Defaults: top `current`, middle `national`, bottom `international`.
  RibbonContentKind topContentKind;
  RibbonContentKind middleContentKind;
  RibbonContentKind bottomContentKind;

  /// Ticker scroll speed multiplier (1.0 = template default).
  double speed;

  RibbonDirection direction;

  /// Headline/ticker font size in logical pixels.
  double fontSize;

  /// Master ribbon toggle — false hides all three ribbons.
  bool showRibbons;

  /// Per-ribbon show/hide toggles (0–3 ribbons allowed).
  bool showTop;
  bool showMiddle;
  bool showBottom;

  /// Logo snapshot for a saved custom template (null = the channel
  /// preset's logo). The logo 3D-rotates in preview AND export as a
  /// continuous full-turn 3D cube (Build 12, superseding the 20 Nov
  /// 2026 swing decision — see lib/services/logo_cube.dart).
  String? logoPath;
  bool logoRotate;

  /// Build 12 (points #12/#13): the logo source snapshot —
  /// mirrors [ChannelPreset.logoMediaKind] and friends so a
  /// saved breaking template carries a logo VIDEO + its key
  /// exactly like the preset does.
  String logoMediaKind;
  String? logoVideoPath;
  int? logoVideoKeyColor;
  String? logoKeyedFramesDir;
  String? logoVideoStillPath;

  /// Intro/outro + lower-third snapshot for a saved custom template.
  bool showIntro;
  bool showOutro;
  String lowerThirdTitle;
  String lowerThirdSubtitle;
  bool showLowerThird;

  /// Interview name plate (master prompt §5, Phase 6): interviewee
  /// name + designation, rendered above the lower third when
  /// [showInterviewPlate] is on and [interviewName] is non-empty.
  String interviewName;
  String interviewDesignation;
  bool showInterviewPlate;

  /// Picture-in-picture inset (master prompt §5, Phase 6): position
  /// + size the export will use (see [ChannelPreset.pipEnabled] —
  /// same contract: preview draws the inset, Phase 7 wires the
  /// export filter). [pipPosition] is a [ChannelPreset.pipPositionIds]
  /// id; [pipScale] is the inset width as a fraction of the frame
  /// (0.15–0.5).
  bool pipEnabled;
  String pipPosition;
  double pipScale;

  /// Bundled built-in background-music asset chosen for this
  /// template (v1.2.0 §2.4 — a [BuiltInNewsMusic] asset path, FREE),
  /// or null for none. Travels to the project via [applyToProject].
  String? backgroundMusicAsset;

  int get coinCost => variant.coinCost;
  bool get isFree => variant.coinCost == 0;

  /// Display name in the Templates Library: the custom name, or the
  /// built-in variant label.
  String get displayName => name ?? variant.label;

  /// Library categories this variant belongs to (master prompt §8 —
  /// the 13 v1 categories). The Templates Library filters on these;
  /// custom templates keep their base variant's categories.
  List<String> get categories => categoriesFor(variant);

  static List<String> categoriesFor(BreakingVariant variant) {
    switch (variant) {
      case BreakingVariant.breakingRedBanner:
        return const [
          'breaking',
          'pakistan',
          'international',
          'crime',
          'special',
        ];
      case BreakingVariant.latestNews:
        return const [
          'breaking',
          'pakistan',
          'international',
          'politics',
          'business',
        ];
      case BreakingVariant.topHeadlineBar:
        return const [
          'breaking',
          'bulletins',
          'politics',
          'pakistan',
          'international',
        ];
      case BreakingVariant.breakingTickerCombo:
        return const [
          'breaking',
          'pakistan',
          'international',
          'bulletins',
        ];
    }
  }

  /// Builds the breaking template the given channel preset currently
  /// describes (variant + colours + texts + lower third + logo +
  /// intro/outro + interview plate + PIP). The renderer and the
  /// preview both read through this, so the preset and the breaking
  /// render can never drift apart. Ribbon content kinds come from
  /// the preset's ribbons (read-only — never reassigned here).
  factory BreakingTemplate.fromPreset(ChannelPreset preset) {
    final variant = BreakingVariant.fromId(preset.breakingVariant);
    return BreakingTemplate(
      variant: variant,
      headline: '',
      tickerText: preset.topRibbon.text,
      middleText: preset.urduRibbon.text,
      bottomText: preset.englishRibbon.text,
      categoryLabel: preset.categoryLabel,
      topColor: preset.topRibbon.color,
      middleColor: preset.urduRibbon.color,
      bottomColor: preset.englishRibbon.color,
      tickerColor: preset.breakingTickerColor,
      topContentKind: preset.topRibbon.contentKind,
      middleContentKind: preset.urduRibbon.contentKind,
      bottomContentKind: preset.englishRibbon.contentKind,
      speed: preset.topRibbon.speed,
      direction: preset.topRibbon.direction,
      fontSize: preset.topRibbon.fontSize,
      showRibbons: preset.showTicker || preset.showUrdu || preset.showEnglish,
      showTop: preset.topRibbon.enabled,
      showMiddle: preset.urduRibbon.enabled,
      showBottom: preset.englishRibbon.enabled,
      logoPath: preset.logoPath,
      logoRotate: preset.logoRotate,
      logoMediaKind: preset.logoMediaKind,
      logoVideoPath: preset.logoVideoPath,
      logoVideoKeyColor: preset.logoVideoKeyColor,
      logoKeyedFramesDir: preset.logoKeyedFramesDir,
      logoVideoStillPath: preset.logoVideoStillPath,
      showIntro: preset.showIntro,
      showOutro: preset.showOutro,
      lowerThirdTitle: preset.lowerThirdTitle,
      lowerThirdSubtitle: preset.lowerThirdSubtitle,
      showLowerThird: preset.showLowerThird,
      interviewName: preset.interviewName,
      interviewDesignation: preset.interviewDesignation,
      showInterviewPlate: preset.showInterviewPlate,
      pipEnabled: preset.pipEnabled,
      pipPosition: preset.pipPosition,
      pipScale: preset.pipScale,
    );
  }

  /// Builds the breaking template for one project: the project's own
  /// headline / ticker / variant, everything else from the channel
  /// preset. The News Maker + AI News Maker previews render through
  /// this, so choosing a breaking template in a project actually
  /// changes its preview (Phase 6). [tickerText] overrides the
  /// project's stored ticker — the maker screens pass the live
  /// ticker-field value so a paste updates the preview at once.
  factory BreakingTemplate.fromProject(
    NewsProject project,
    ChannelPreset preset, {
    String? tickerText,
  }) {
    final template = BreakingTemplate.fromPreset(preset);
    template.variant = BreakingVariant.fromId(project.breakingVariant);
    template.id = template.variant.id;
    template.headline = project.headline;
    template.tickerText = tickerText ??
        (project.tickerText.isEmpty
            ? preset.topRibbon.text
            : project.tickerText);
    // v1.2.0 §2.2: the project's own ticker-direction override (set
    // by the video-template Direction toggle) wins over the preset's
    // ribbon direction in preview AND export.
    if (project.tickerDirection != null) {
      template.direction =
          RibbonDirection.fromId(project.tickerDirection);
    }
    template.backgroundMusicAsset = project.backgroundMusicAsset;
    return template;
  }

  /// Applies this template's settings to a channel preset: variant,
  /// ribbon colours + texts, lower third, logo, intro/outro,
  /// interview plate, PIP, category label. The ribbon CONTENT KINDS
  /// are deliberately NOT copied — they are read-only (top = current,
  /// middle = national, bottom = international) and a template must
  /// never reassign them.
  void applyToPreset(ChannelPreset preset) {
    preset.templateKind = 'breaking';
    preset.breakingVariant = variant.id;
    preset.breakingTickerColor = tickerColor;
    preset.categoryLabel = categoryLabel;
    preset.topRibbon.text = tickerText;
    preset.topRibbon.color = topColor;
    preset.topRibbon.speed = speed;
    preset.topRibbon.direction = direction;
    preset.topRibbon.fontSize = fontSize;
    preset.topRibbon.enabled = showTop;
    preset.urduRibbon.text = middleText;
    preset.urduRibbon.color = middleColor;
    preset.urduRibbon.enabled = showMiddle;
    preset.englishRibbon.text = bottomText;
    preset.englishRibbon.color = bottomColor;
    preset.englishRibbon.enabled = showBottom;
    preset.logoPath = logoPath;
    preset.logoRotate = logoRotate;
    preset.logoMediaKind = logoMediaKind;
    preset.logoVideoPath = logoVideoPath;
    preset.logoVideoKeyColor = logoVideoKeyColor;
    preset.logoKeyedFramesDir = logoKeyedFramesDir;
    preset.logoVideoStillPath = logoVideoStillPath;
    preset.showIntro = showIntro;
    preset.showOutro = showOutro;
    preset.lowerThirdTitle = lowerThirdTitle;
    preset.lowerThirdSubtitle = lowerThirdSubtitle;
    preset.showLowerThird = showLowerThird;
    preset.interviewName = interviewName;
    preset.interviewDesignation = interviewDesignation;
    preset.showInterviewPlate = showInterviewPlate;
    preset.pipEnabled = pipEnabled;
    preset.pipPosition = pipPosition;
    preset.pipScale = pipScale;
  }

  /// Applies this template to a project: template kind + variant +
  /// headline + ticker. The rest of the project travels through its
  /// channel preset (see [applyToPreset]).
  void applyToProject(NewsProject project) {
    project.templateKind = 'breaking';
    project.breakingVariant = variant.id;
    project.breaking = true;
    project.headline = headline;
    project.tickerText = tickerText;
    // v1.2.0 §2.2/§2.4: direction + built-in music travel with the
    // template, so the export renders the same ticker direction and
    // the chosen (free) music selection stays on the project.
    project.tickerDirection = direction.id;
    project.backgroundMusicAsset = backgroundMusicAsset;
  }

  /// The four v1 variant defaults. Per-variant colour roles (see the
  /// [topColor] doc above): the breaking banner's ticker strip is
  /// BLACK for Breaking Red Banner and WHITE for Latest News — those
  /// are the design constants from the plan (§7), not the English
  /// ribbon's red.
  static List<BreakingTemplate> defaults() {
    return [
      BreakingTemplate(
        variant: BreakingVariant.breakingRedBanner,
        topColor: 0xFFD50000,
        middleColor: 0xFF3D5AFE,
        bottomColor: 0xFF000000,
      ),
      BreakingTemplate(
        variant: BreakingVariant.latestNews,
        topColor: 0xFF1E88E5,
        middleColor: 0xFF3D5AFE,
        bottomColor: 0xFFFFFFFF,
      ),
      BreakingTemplate(
        variant: BreakingVariant.topHeadlineBar,
        topColor: 0xFFFFFFFF,
        middleColor: 0xFF3D5AFE,
        bottomColor: 0xFF01B0FF,
      ),
      // Breaking + Ticker combo: red breaking banner + the final
      // 3-ribbon template below it — same ribbon colours AND the same
      // ribbon-content rule as the Nigraan final template.
      BreakingTemplate(
        variant: BreakingVariant.breakingTickerCombo,
        topColor: 0xFFD50000,
        middleColor: 0xFF3D5AFE,
        bottomColor: 0xFFEF0017,
        topContentKind: RibbonContentKind.current,
        middleContentKind: RibbonContentKind.national,
        bottomContentKind: RibbonContentKind.international,
      ),
    ];
  }

  BreakingTemplate copyWith({
    String? id,
    String? name,
    bool? isCustom,
    BreakingVariant? variant,
    String? headline,
    String? tickerText,
    String? middleText,
    String? bottomText,
    String? categoryLabel,
    int? topColor,
    int? middleColor,
    int? bottomColor,
    int? tickerColor,
    RibbonContentKind? topContentKind,
    RibbonContentKind? middleContentKind,
    RibbonContentKind? bottomContentKind,
    double? speed,
    RibbonDirection? direction,
    double? fontSize,
    bool? showRibbons,
    bool? showTop,
    bool? showMiddle,
    bool? showBottom,
    String? logoPath,
    bool? logoRotate,
    String? logoMediaKind,
    String? logoVideoPath,
    int? logoVideoKeyColor,
    String? logoKeyedFramesDir,
    String? logoVideoStillPath,
    bool? showIntro,
    bool? showOutro,
    String? lowerThirdTitle,
    String? lowerThirdSubtitle,
    bool? showLowerThird,
    String? interviewName,
    String? interviewDesignation,
    bool? showInterviewPlate,
    bool? pipEnabled,
    String? pipPosition,
    double? pipScale,
    String? backgroundMusicAsset,
  }) {
    return BreakingTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      isCustom: isCustom ?? this.isCustom,
      variant: variant ?? this.variant,
      headline: headline ?? this.headline,
      tickerText: tickerText ?? this.tickerText,
      middleText: middleText ?? this.middleText,
      bottomText: bottomText ?? this.bottomText,
      categoryLabel: categoryLabel ?? this.categoryLabel,
      topColor: topColor ?? this.topColor,
      middleColor: middleColor ?? this.middleColor,
      bottomColor: bottomColor ?? this.bottomColor,
      tickerColor: tickerColor ?? this.tickerColor,
      topContentKind: topContentKind ?? this.topContentKind,
      middleContentKind: middleContentKind ?? this.middleContentKind,
      bottomContentKind: bottomContentKind ?? this.bottomContentKind,
      speed: speed ?? this.speed,
      direction: direction ?? this.direction,
      fontSize: fontSize ?? this.fontSize,
      showRibbons: showRibbons ?? this.showRibbons,
      showTop: showTop ?? this.showTop,
      showMiddle: showMiddle ?? this.showMiddle,
      showBottom: showBottom ?? this.showBottom,
      logoPath: logoPath ?? this.logoPath,
      logoRotate: logoRotate ?? this.logoRotate,
      logoMediaKind: logoMediaKind ?? this.logoMediaKind,
      logoVideoPath: logoVideoPath ?? this.logoVideoPath,
      logoVideoKeyColor: logoVideoKeyColor ?? this.logoVideoKeyColor,
      logoKeyedFramesDir: logoKeyedFramesDir ?? this.logoKeyedFramesDir,
      logoVideoStillPath: logoVideoStillPath ?? this.logoVideoStillPath,
      showIntro: showIntro ?? this.showIntro,
      showOutro: showOutro ?? this.showOutro,
      lowerThirdTitle: lowerThirdTitle ?? this.lowerThirdTitle,
      lowerThirdSubtitle: lowerThirdSubtitle ?? this.lowerThirdSubtitle,
      showLowerThird: showLowerThird ?? this.showLowerThird,
      interviewName: interviewName ?? this.interviewName,
      interviewDesignation:
          interviewDesignation ?? this.interviewDesignation,
      showInterviewPlate: showInterviewPlate ?? this.showInterviewPlate,
      pipEnabled: pipEnabled ?? this.pipEnabled,
      pipPosition: pipPosition ?? this.pipPosition,
      pipScale: pipScale ?? this.pipScale,
      backgroundMusicAsset:
          backgroundMusicAsset ?? this.backgroundMusicAsset,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isCustom': isCustom,
        'variant': variant.id,
        'headline': headline,
        'tickerText': tickerText,
        'middleText': middleText,
        'bottomText': bottomText,
        'categoryLabel': categoryLabel,
        'topColor': topColor,
        'middleColor': middleColor,
        'bottomColor': bottomColor,
        'tickerColor': tickerColor,
        'topContentKind': topContentKind.id,
        'middleContentKind': middleContentKind.id,
        'bottomContentKind': bottomContentKind.id,
        'speed': speed,
        'direction': direction.id,
        'fontSize': fontSize,
        'showRibbons': showRibbons,
        'showTop': showTop,
        'showMiddle': showMiddle,
        'showBottom': showBottom,
        'logoPath': logoPath,
        'logoRotate': logoRotate,
        'logoMediaKind': logoMediaKind,
        'logoVideoPath': logoVideoPath,
        'logoVideoKeyColor': logoVideoKeyColor,
        'logoKeyedFramesDir': logoKeyedFramesDir,
        'logoVideoStillPath': logoVideoStillPath,
        'showIntro': showIntro,
        'showOutro': showOutro,
        'lowerThirdTitle': lowerThirdTitle,
        'lowerThirdSubtitle': lowerThirdSubtitle,
        'showLowerThird': showLowerThird,
        'interviewName': interviewName,
        'interviewDesignation': interviewDesignation,
        'showInterviewPlate': showInterviewPlate,
        'pipEnabled': pipEnabled,
        'pipPosition': pipPosition,
        'pipScale': pipScale,
        'backgroundMusicAsset': backgroundMusicAsset,
      };

  static BreakingTemplate fromJson(Map<String, dynamic> json) {
    final variant = BreakingVariant.fromId(json['variant'] as String?);
    return BreakingTemplate(
      id: (json['id'] as String?) ?? variant.id,
      name: json['name'] as String?,
      isCustom: (json['isCustom'] as bool?) ?? false,
      variant: variant,
      headline: (json['headline'] as String?) ?? '',
      tickerText: (json['tickerText'] as String?) ?? '',
      middleText: (json['middleText'] as String?) ?? '',
      bottomText: (json['bottomText'] as String?) ?? '',
      categoryLabel: (json['categoryLabel'] as String?) ?? '',
      topColor: (json['topColor'] as int?) ?? 0xFFD50000,
      middleColor: (json['middleColor'] as int?) ?? 0xFF3D5AFE,
      bottomColor: (json['bottomColor'] as int?) ?? 0xFFEF0017,
      tickerColor: (json['tickerColor'] as int?) ?? 0xFF01B0FF,
      topContentKind:
          RibbonContentKind.fromId(json['topContentKind'] as String?),
      middleContentKind:
          RibbonContentKind.fromId(json['middleContentKind'] as String?),
      bottomContentKind:
          RibbonContentKind.fromId(json['bottomContentKind'] as String?),
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      direction: RibbonDirection.fromId(json['direction'] as String?),
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 20,
      showRibbons: (json['showRibbons'] as bool?) ?? true,
      showTop: (json['showTop'] as bool?) ?? true,
      showMiddle: (json['showMiddle'] as bool?) ?? true,
      showBottom: (json['showBottom'] as bool?) ?? true,
      logoPath: json['logoPath'] as String?,
      logoRotate: (json['logoRotate'] as bool?) ?? true,
      logoMediaKind: (json['logoMediaKind'] as String?) ?? 'image',
      logoVideoPath: json['logoVideoPath'] as String?,
      logoVideoKeyColor: json['logoVideoKeyColor'] as int?,
      logoKeyedFramesDir: json['logoKeyedFramesDir'] as String?,
      logoVideoStillPath: json['logoVideoStillPath'] as String?,
      showIntro: (json['showIntro'] as bool?) ?? true,
      showOutro: (json['showOutro'] as bool?) ?? true,
      lowerThirdTitle: (json['lowerThirdTitle'] as String?) ?? '',
      lowerThirdSubtitle: (json['lowerThirdSubtitle'] as String?) ?? '',
      showLowerThird: (json['showLowerThird'] as bool?) ?? true,
      interviewName: (json['interviewName'] as String?) ?? '',
      interviewDesignation:
          (json['interviewDesignation'] as String?) ?? '',
      showInterviewPlate: (json['showInterviewPlate'] as bool?) ?? false,
      pipEnabled: (json['pipEnabled'] as bool?) ?? false,
      pipPosition: (json['pipPosition'] as String?) ?? 'bottomRight',
      pipScale: (json['pipScale'] as num?)?.toDouble() ?? 0.3,
      backgroundMusicAsset: json['backgroundMusicAsset'] as String?,
    );
  }
}

/// JSON store for breaking templates (same pattern as `NewsTemplate`).
///
/// The file holds ONLY user-saved custom templates; the four built-in
/// variants are regenerated by [BreakingTemplate.defaults] on every load.
/// [loadAll] returns built-ins first, then customs — that is the list the
/// Templates Library screen (Phase 6) shows.
class BreakingTemplateStore {
  static const _fileName = 'breaking_templates.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// Loads the saved custom templates only (empty when none saved yet).
  static Future<List<BreakingTemplate>> loadCustom() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map<String, dynamic>) {
          final raw = data['templates'];
          if (raw is List) {
            final templates = <BreakingTemplate>[];
            for (final item in raw) {
              if (item is Map<String, dynamic>) {
                final t = BreakingTemplate.fromJson(item);
                if (t.isCustom) templates.add(t);
              }
            }
            return templates;
          }
        }
      }
    } catch (_) {}
    return [];
  }

  /// Loads all templates: the four built-in variant defaults + every
  /// user-saved custom template.
  static Future<List<BreakingTemplate>> loadAll() async {
    return [...BreakingTemplate.defaults(), ...await loadCustom()];
  }

  /// Persists the custom templates from [templates] (built-ins are
  /// regenerated, never stored).
  static Future<void> saveAll(List<BreakingTemplate> templates) async {
    try {
      final file = await _file();
      final customs = templates.where((t) => t.isCustom).toList();
      await file.writeAsString(jsonEncode({
        'templates': customs.map((e) => e.toJson()).toList(),
      }));
    } catch (_) {
      // Template persistence is a convenience; a failed save must never
      // block editing or exporting with the in-memory templates.
    }
  }

  /// SAVE CUSTOM TEMPLATE (user order 20 Nov 2026, v1 MUST-HAVE):
  /// saves [template]'s current settings — ribbons, colours, speed,
  /// direction, size, logo, intro/outro, lower third — as a NEW named
  /// template ([name]) that shows up in the Templates Library and is
  /// reusable in every project (per-channel presets included — the
  /// snapshot carries the logo + intro/outro + lower-third choices with
  /// it). Returns the saved copy.
  static Future<BreakingTemplate> saveCustomTemplate({
    required String name,
    required BreakingTemplate template,
  }) async {
    final saved = template.copyWith(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Custom Template' : name.trim(),
      isCustom: true,
    );
    final all = await loadAll();
    all.add(saved);
    await saveAll(all);
    return saved;
  }

  /// Deletes a saved custom template by [id]. Built-ins cannot be
  /// deleted (their ids are variant ids, never 'custom_…').
  static Future<void> deleteCustomTemplate(String id) async {
    if (!id.startsWith('custom_')) return;
    final customs = await loadCustom();
    customs.removeWhere((t) => t.id == id);
    await saveAll(customs);
  }
}
