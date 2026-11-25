/// MOTION GRAPHICS STUDIO — template registry (Build M1).
///
/// Every Gallery template is pure scene DATA (plan §5): a
/// [MotionScene] the engine renders live — no video files, no
/// bundled previews, so the whole v1 set costs kilobytes, not
/// megabytes. Prices are NOT baked into this data beyond the
/// tier defaults: the effective price is resolved at runtime
/// from remote config (`motion_price_<id>`, see
/// `motion_access.dart`) so the owner can reprice any template
/// without a build (user order, point #20).
///
/// M1 ships the plan's 8 seed templates (the ★ rows of §5);
/// M4/M6 add the rest of the ~34.
library;

import 'motion_scene.dart';

/// A template's designed tier. The tier sets the DEFAULT price
/// behaviour; remote config can override per template.
enum MotionTier { free, pro, coins }

/// One Gallery template: identity + tier + its scene.
class MotionTemplate {
  const MotionTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.tier,
    required this.scene,
    this.coinPrice = 0,
    this.slots = const [],
  });

  /// Stable id — also the remote-price key suffix
  /// (`motion_price_<id>`) and the ownership record key.
  final String id;

  final String name;

  /// Category key (see [MotionCategories]).
  final String category;

  final MotionTier tier;

  /// The listed coin price: for [MotionTier.coins] templates
  /// this IS the default price; for [MotionTier.pro] templates
  /// it is the non-Pro coin unlock price used when remote
  /// config does not override (plan §6).
  final int coinPrice;

  final MotionScene scene;

  /// Human labels of what the Editor (M2) will let the user
  /// change — shown on the preview screen as "editable" info.
  final List<String> slots;

  double get durationSec => scene.durationSec;
}

/// Category keys + display labels, in Gallery rail order (the
/// master prompt's category list; only categories that have
/// templates appear in the rail).
class MotionCategories {
  MotionCategories._();

  static const String titles = 'titles';
  static const String logo = 'logo';
  static const String naam = 'naam';
  static const String intro = 'intro';
  static const String points = 'points';
  static const String numbers = 'numbers';
  static const String social = 'social';
  static const String quotes = 'quotes';
  static const String subscribe = 'subscribe';
  static const String countdown = 'countdown';
  static const String effects = 'effects';
  static const String news = 'news';

  static const Map<String, String> labels = {
    titles: 'Titles',
    logo: 'Logo',
    naam: 'Naam Strip',
    intro: 'Intro',
    points: 'Points',
    numbers: 'Ginti / Charts',
    social: 'Social',
    quotes: 'Quotes',
    subscribe: 'Subscribe',
    countdown: 'Countdown',
    effects: 'Effects',
    news: 'News Pack',
  };
}

// Reference palette (the user's 4-panel visual): deep navy,
// electric blue, purple, cyan — with broadcast red/gold where
// the news language needs them.
const int _bgA = 0xFF050914;
const int _bgB = 0xFF0B1B3F;
const int _blue = 0xFF2979FF;
const int _cyan = 0xFF00E5FF;
const int _purple = 0xFF7C4DFF;
const int _red = 0xFFE53935;
const int _redDeep = 0xFF8E1414;
const int _gold = 0xFFFFC800;
const int _white = 0xFFFFFFFF;
const int _white70 = 0xB3FFFFFF;
const String _nastaliq = 'Noto Nastaliq Urdu';

/// The M1 seed set (plan §5, ★ rows).
class MotionTemplates {
  MotionTemplates._();

  static final List<MotionTemplate> all = [
    kineticHeadline,
    logoReveal,
    naamStripClassic,
    pointsList,
    counterGinti,
    subscribePop,
    breakingNewsIntro,
    liveNewsIntro,
  ];

  static MotionTemplate? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Categories that actually have templates, in rail order.
  static List<String> get presentCategories {
    final present = <String>{for (final t in all) t.category};
    return MotionCategories.labels.keys
        .where(present.contains)
        .toList(growable: false);
  }

  // --- 1. Kinetic Headline (Titles, FREE, 3s) -------------------
  static final MotionTemplate kineticHeadline = MotionTemplate(
    id: 'kinetic_headline',
    name: 'Kinetic Headline',
    category: MotionCategories.titles,
    tier: MotionTier.free,
    slots: const ['Line 1', 'Line 2', 'Rang', 'Font'],
    scene: const MotionScene(
      width: 1280,
      height: 720,
      durationSec: 3,
      bgColor: _bgA,
      bgColor2: _bgB,
      layers: [
        MotionLayer(
          id: 'line1',
          type: MotionLayerType.text,
          x: 640,
          y: 292,
          width: 1100,
          text: 'BREAKING',
          fontSize: 100,
          color: _white,
          letterSpacing: 2,
          entrance: 'slideLeft',
          entranceSec: 0.55,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
        MotionLayer(
          id: 'line2',
          type: MotionLayerType.text,
          x: 640,
          y: 398,
          width: 1100,
          start: 0.18,
          text: 'NEWS',
          fontSize: 100,
          color: _gold,
          letterSpacing: 10,
          entrance: 'slideRight',
          entranceSec: 0.55,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
        MotionLayer(
          id: 'bar',
          type: MotionLayerType.shape,
          x: 640,
          y: 466,
          width: 460,
          height: 10,
          start: 0.4,
          shape: 'rect',
          fill: _cyan,
          glowColor: _cyan,
          glowBlur: 18,
          entrance: 'fadeIn',
          entranceSec: 0.4,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
      ],
    ),
  );

  // --- 4. Logo Reveal — glow ring (Logo, FREE, 4s) --------------
  static final MotionTemplate logoReveal = MotionTemplate(
    id: 'logo_reveal',
    name: 'Logo Reveal',
    category: MotionCategories.logo,
    tier: MotionTier.free,
    slots: const ['Logo', 'Channel naam'],
    scene: const MotionScene(
      width: 1280,
      height: 720,
      durationSec: 4,
      bgColor: _bgA,
      bgColor2: _bgB,
      layers: [
        MotionLayer(
          id: 'ring',
          type: MotionLayerType.shape,
          x: 640,
          y: 322,
          width: 308,
          height: 308,
          shape: 'ring',
          fill: _cyan,
          strokeWidth: 9,
          glowColor: _cyan,
          glowBlur: 26,
          entrance: 'zoomIn',
          entranceSec: 0.9,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
        MotionLayer(
          id: 'logo',
          type: MotionLayerType.image,
          x: 640,
          y: 322,
          width: 216,
          height: 216,
          start: 0.15,
          cornerRadius: 108,
          imageKey: 'logo',
          placeholderText: 'TJ',
          entrance: 'popIn',
          entranceSec: 0.7,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
        MotionLayer(
          id: 'channel',
          type: MotionLayerType.text,
          x: 640,
          y: 548,
          width: 1000,
          start: 0.7,
          text: 'NIGRAAN TV',
          fontSize: 56,
          color: _white,
          letterSpacing: 5,
          entrance: 'fadeIn',
          entranceSec: 0.6,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
      ],
    ),
  );

  // --- 6. Naam Strip Classic (Naam Strip, FREE, 5s) -------------
  static final MotionTemplate naamStripClassic = MotionTemplate(
    id: 'naam_strip_classic',
    name: 'Naam Strip Classic',
    category: MotionCategories.naam,
    tier: MotionTier.free,
    slots: const ['Naam', 'Ohda', 'Rang'],
    scene: const MotionScene(
      width: 1280,
      height: 720,
      durationSec: 5,
      bgColor: _bgA,
      bgColor2: _bgB,
      layers: [
        MotionLayer(
          id: 'panel',
          type: MotionLayerType.shape,
          x: 440,
          y: 556,
          width: 720,
          height: 120,
          shape: 'rounded',
          cornerRadius: 16,
          fill: 0xFF0D2150,
          fill2: 0xFF12306E,
          strokeColor: _cyan,
          strokeWidth: 2,
          entrance: 'slideRight',
          entranceSec: 0.6,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
        MotionLayer(
          id: 'edge',
          type: MotionLayerType.shape,
          x: 92,
          y: 556,
          width: 14,
          height: 120,
          start: 0.05,
          shape: 'rect',
          fill: _cyan,
          glowColor: _cyan,
          glowBlur: 14,
          entrance: 'slideRight',
          entranceSec: 0.6,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
        MotionLayer(
          id: 'name',
          type: MotionLayerType.text,
          x: 470,
          y: 528,
          width: 620,
          start: 0.1,
          text: 'احمد خان',
          fontSize: 52,
          color: _white,
          fontFamily: _nastaliq,
          entrance: 'slideRight',
          entranceSec: 0.6,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
        MotionLayer(
          id: 'role',
          type: MotionLayerType.text,
          x: 470,
          y: 590,
          width: 620,
          start: 0.35,
          text: 'رپورٹر — نگران ٹی وی',
          fontSize: 32,
          color: _white70,
          fontFamily: _nastaliq,
          bold: false,
          entrance: 'fadeIn',
          entranceSec: 0.5,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
      ],
    ),
  );

  // --- 10. Points List 1-2-3 (Points, FREE, 6s) -----------------
  static final MotionTemplate pointsList = MotionTemplate(
    id: 'points_list',
    name: 'Points List 1-2-3',
    category: MotionCategories.points,
    tier: MotionTier.free,
    slots: const ['Point 1', 'Point 2', 'Point 3'],
    scene: MotionScene(
      width: 1280,
      height: 720,
      durationSec: 6,
      bgColor: _bgA,
      bgColor2: _bgB,
      layers: [
        const MotionLayer(
          id: 'title',
          type: MotionLayerType.text,
          x: 640,
          y: 108,
          width: 900,
          text: 'TOP 3',
          fontSize: 60,
          color: _cyan,
          letterSpacing: 6,
          entrance: 'fadeIn',
          entranceSec: 0.5,
        ),
        for (var i = 0; i < 3; i++) ...[
          MotionLayer(
            id: 'dot$i',
            type: MotionLayerType.shape,
            x: 300,
            y: 252.0 + i * 152,
            width: 86,
            height: 86,
            start: 0.2 + i * 0.9,
            shape: 'circle',
            fill: _blue,
            fill2: _purple,
            glowColor: _blue,
            glowBlur: 16,
            entrance: 'popIn',
            entranceSec: 0.45,
          ),
          MotionLayer(
            id: 'num$i',
            type: MotionLayerType.text,
            x: 300,
            y: 252.0 + i * 152,
            width: 86,
            start: 0.2 + i * 0.9,
            text: '${i + 1}',
            fontSize: 46,
            color: _white,
            entrance: 'popIn',
            entranceSec: 0.45,
          ),
          MotionLayer(
            id: 'point$i',
            type: MotionLayerType.text,
            x: 716,
            y: 252.0 + i * 152,
            width: 580,
            start: 0.35 + i * 0.9,
            text: const [
              'Pehla point yahan likhen',
              'Dusra point yahan likhen',
              'Teesra point yahan likhen',
            ][i],
            fontSize: 44,
            color: _white,
            entrance: 'slideLeft',
            entranceSec: 0.5,
          ),
        ],
      ],
    ),
  );

  // --- 12. Counter / Ginti (Numbers, FREE, 4s) ------------------
  static final MotionTemplate counterGinti = MotionTemplate(
    id: 'counter_ginti',
    name: 'Counter / Ginti',
    category: MotionCategories.numbers,
    tier: MotionTier.free,
    slots: const ['Akhri number', 'Label'],
    scene: const MotionScene(
      width: 1280,
      height: 720,
      durationSec: 4,
      bgColor: _bgA,
      bgColor2: _bgB,
      layers: [
        MotionLayer(
          id: 'halo',
          type: MotionLayerType.shape,
          x: 640,
          y: 330,
          width: 372,
          height: 372,
          shape: 'ring',
          fill: 0x6600E5FF,
          strokeWidth: 4,
          entrance: 'zoomIn',
          entranceSec: 1.2,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
        MotionLayer(
          id: 'count',
          type: MotionLayerType.counter,
          x: 640,
          y: 322,
          width: 980,
          from: 0,
          to: 100000,
          fontSize: 132,
          color: _white,
          label: 'VIEWS',
          labelColor: _cyan,
          entrance: 'fadeIn',
          entranceSec: 0.4,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
      ],
    ),
  );

  // --- 15. Subscribe Pop (Subscribe, FREE, 5s) ------------------
  static final MotionTemplate subscribePop = MotionTemplate(
    id: 'subscribe_pop',
    name: 'Subscribe Pop',
    category: MotionCategories.subscribe,
    tier: MotionTier.free,
    slots: const ['Channel naam'],
    scene: const MotionScene(
      width: 1280,
      height: 720,
      durationSec: 5,
      bgColor: _bgA,
      bgColor2: _bgB,
      layers: [
        MotionLayer(
          id: 'button',
          type: MotionLayerType.shape,
          x: 640,
          y: 340,
          width: 540,
          height: 128,
          shape: 'pill',
          fill: 0xFFFF3D3D,
          fill2: 0xFFD92323,
          glowColor: _red,
          glowBlur: 28,
          entrance: 'bounceIn',
          entranceSec: 0.7,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
        MotionLayer(
          id: 'cta',
          type: MotionLayerType.text,
          x: 640,
          y: 322,
          width: 500,
          text: 'SUBSCRIBE',
          fontSize: 56,
          color: _white,
          letterSpacing: 3,
          entrance: 'bounceIn',
          entranceSec: 0.7,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
        MotionLayer(
          id: 'channel',
          type: MotionLayerType.text,
          x: 640,
          y: 382,
          width: 500,
          start: 0.4,
          text: 'Nigraan TV',
          fontSize: 30,
          color: 0xE6FFFFFF,
          bold: false,
          entrance: 'fadeIn',
          entranceSec: 0.5,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
      ],
    ),
  );

  // --- 20. Breaking News Intro (News Pack, PRO, 6s) -------------
  static final MotionTemplate breakingNewsIntro = MotionTemplate(
    id: 'breaking_news_intro',
    name: 'Breaking News Intro',
    category: MotionCategories.news,
    tier: MotionTier.pro,
    coinPrice: 50,
    slots: const ['Channel naam', 'Logo', 'Ticker text'],
    scene: const MotionScene(
      width: 1280,
      height: 720,
      durationSec: 6,
      bgColor: _bgA,
      bgColor2: _bgB,
      layers: [
        MotionLayer(
          id: 'topbar',
          type: MotionLayerType.shape,
          x: 640,
          y: 82,
          width: 1280,
          height: 92,
          shape: 'rect',
          fill: _red,
          fill2: _redDeep,
          entrance: 'slideDown',
          entranceSec: 0.5,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
        MotionLayer(
          id: 'breaking',
          type: MotionLayerType.text,
          x: 640,
          y: 82,
          width: 1100,
          text: 'BREAKING NEWS',
          fontSize: 56,
          color: _white,
          letterSpacing: 6,
          entrance: 'flashLabel',
          entranceSec: 0.9,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
        MotionLayer(
          id: 'logo',
          type: MotionLayerType.image,
          x: 1086,
          y: 330,
          width: 156,
          height: 156,
          start: 0.5,
          cornerRadius: 24,
          imageKey: 'logo',
          placeholderText: 'TJ',
          entrance: 'popIn',
          entranceSec: 0.6,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
        MotionLayer(
          id: 'channel',
          type: MotionLayerType.text,
          x: 600,
          y: 330,
          width: 900,
          start: 0.3,
          text: 'NIGRAAN TV',
          fontSize: 112,
          color: _white,
          letterSpacing: 3,
          entrance: 'zoomIn',
          entranceSec: 0.8,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
        MotionLayer(
          id: 'rule',
          type: MotionLayerType.shape,
          x: 600,
          y: 418,
          width: 520,
          height: 8,
          start: 0.7,
          shape: 'rect',
          fill: _cyan,
          glowColor: _cyan,
          glowBlur: 14,
          entrance: 'slideLeft',
          entranceSec: 0.5,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
        MotionLayer(
          id: 'tagline',
          type: MotionLayerType.text,
          x: 600,
          y: 486,
          width: 900,
          start: 0.9,
          text: 'عوام کی آواز',
          fontSize: 56,
          color: _gold,
          fontFamily: _nastaliq,
          entrance: 'fadeIn',
          entranceSec: 0.6,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
        MotionLayer(
          id: 'ticker',
          type: MotionLayerType.ticker,
          x: 640,
          y: 652,
          width: 1280,
          start: 0.5,
          text: 'اہم خبر: یہاں اپنی ہیڈ لائن لکھیں • تازہ ترین اپڈیٹس • ',
          fontSize: 34,
          color: _white,
          fontFamily: _nastaliq,
          bandColor: 0xFF0B1026,
          bandHeight: 72,
          speedPxPerSecond: 150,
          scrollRight: true,
          cyclePx: 2500,
        ),
      ],
    ),
  );

  // --- 21. LIVE News Intro (News Pack, FREE, 5s) ----------------
  static final MotionTemplate liveNewsIntro = MotionTemplate(
    id: 'live_news_intro',
    name: 'LIVE News Intro',
    category: MotionCategories.news,
    tier: MotionTier.free,
    slots: const ['Channel naam'],
    scene: const MotionScene(
      width: 1280,
      height: 720,
      durationSec: 5,
      bgColor: _bgA,
      bgColor2: _bgB,
      layers: [
        MotionLayer(
          id: 'badge',
          type: MotionLayerType.shape,
          x: 246,
          y: 118,
          width: 216,
          height: 76,
          shape: 'pill',
          fill: _red,
          fill2: _redDeep,
          glowColor: _red,
          glowBlur: 20,
          entrance: 'pulse',
        ),
        MotionLayer(
          id: 'live',
          type: MotionLayerType.text,
          x: 246,
          y: 118,
          width: 200,
          text: 'LIVE',
          fontSize: 44,
          color: _white,
          letterSpacing: 4,
          entrance: 'pulse',
        ),
        MotionLayer(
          id: 'channel',
          type: MotionLayerType.text,
          x: 640,
          y: 318,
          width: 1050,
          start: 0.2,
          text: 'NIGRAAN TV',
          fontSize: 100,
          color: _white,
          letterSpacing: 3,
          entrance: 'slideUp',
          entranceSec: 0.6,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
        MotionLayer(
          id: 'urdu',
          type: MotionLayerType.text,
          x: 640,
          y: 424,
          width: 800,
          start: 0.6,
          text: 'براہ راست',
          fontSize: 56,
          color: _cyan,
          fontFamily: _nastaliq,
          entrance: 'fadeIn',
          entranceSec: 0.6,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
        MotionLayer(
          id: 'rule',
          type: MotionLayerType.shape,
          x: 640,
          y: 502,
          width: 620,
          height: 6,
          start: 0.8,
          shape: 'rect',
          fill: _cyan,
          glowColor: _cyan,
          glowBlur: 12,
          entrance: 'fadeIn',
          entranceSec: 0.5,
          exit: 'fadeOut',
          exitSec: 0.4,
        ),
      ],
    ),
  );
}
