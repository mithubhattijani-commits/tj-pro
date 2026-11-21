/// Caption styles for News Studio (Phase 5) — ported from Magic Box
/// (`audio-box-ref`, `lib/services/caption_styles.dart`, v1.0.13),
/// adapted to TJ Pro:
///
///   - `CaptionStyle` is renamed [StudioCaptionStyle]: TJ Pro already
///     has a `CaptionStyle` enum in `lib/services/caption_service.dart`
///     (6 styles for the live video editor) and the two must not
///     collide. The 11 Magic Box styles live here; the editor's 6
///     stay where they are.
///   - Voice labels are NOT ported: Magic Box calls Aoede "Billo"
///     and Charon "Jaani" — TJ Pro keeps Aoede/Charon (see
///     `lib/services/gemini_voice_service.dart`).
///   - No coin/ad rules are ported (TJ Pro voiceover = 5 requests/day
///     cap, admins exempt — see `magic-box-port.md` §6C).
///
/// Pure Dart (no Flutter import) so the timing + colour maths can be
/// unit-checked with plain `dart`.
///
/// The 11 styles, picker order, `nigraan` first = default: the spoken
/// word turns Nigraan green (#3AEC70), like the channel's own reels.
/// Animations: karaoke (whole line visible, spoken word highlighted),
/// pop (one word at a time), typewriter (words appear and stay),
/// flash (whole line at once).
library;

/// How the words of one line are shown over time.
enum CaptionAnimation {
  /// Whole line visible; the spoken word is highlighted.
  karaoke,

  /// One word at a time, big, with a pop scale.
  pop,

  /// Words appear one by one and stay (typewriter).
  typewriter,

  /// Whole line appears at once, no word animation.
  flash,
}

enum CaptionPosition { top, middle, bottom }

enum CaptionSize { small, medium, large }

/// One caption style preset. Colours are 0xAARRGGBB ints.
class StudioCaptionStyle {
  final String id;
  final String nameEn;
  final String nameUr;
  final CaptionAnimation animation;

  /// Colour of the not-yet-spoken / plain words.
  final int textColor;

  /// Colour of the spoken word (karaoke / pop highlight).
  final int highlightColor;

  /// Background behind the HIGHLIGHTED word only (0 = none).
  /// Used by the Highlight Box style. NOTE: this has no ASS
  /// equivalent — ASS export drops the box (see
  /// `CaptionService.buildStyledAss`).
  final int highlightBg;

  /// Background behind the whole line (0 = none).
  final int backgroundColor;

  /// Black outline around the letters (Bold Pop / Classic).
  final bool outline;

  /// Soft drop shadow behind the letters (FX toggle).
  final bool shadow;

  final bool bold;

  /// Upper-case the words (Bold Pop / One Word English look).
  final bool uppercase;

  /// Base font size in logical px (medium size, preview + player).
  final double fontSizePx;

  /// Base font size in points for the ASS export (720p canvas).
  final int fontSizePt;

  /// Default on-screen position.
  final CaptionPosition position;

  /// Scale of the highlighted word (Spotlight = 1.25).
  final double highlightScale;

  const StudioCaptionStyle({
    required this.id,
    required this.nameEn,
    required this.nameUr,
    required this.animation,
    required this.textColor,
    required this.highlightColor,
    this.highlightBg = 0,
    this.backgroundColor = 0,
    this.outline = false,
    this.shadow = false,
    this.bold = true,
    this.uppercase = false,
    required this.fontSizePx,
    required this.fontSizePt,
    required this.position,
    this.highlightScale = 1.0,
  });
}

class StudioCaptionStyles {
  // Palette (0xAARRGGBB).
  static const int white = 0xFFFFFFFF;
  static const int white50 = 0x80FFFFFF;
  static const int black = 0xFF000000;
  static const int black70 = 0xB3000000;
  static const int green = 0xFF3AEC70; // Nigraan reel spoken-word green
  static const int yellow = 0xFFFFD60A; // CapCut bold-pop yellow
  static const int red = 0xFFEF0017; // Nigraan red
  static const int blue = 0xFF3D5AFE; // Nigraan ticker blue
  static const int cyan = 0xFF00E5FF;

  /// Highlight colour choices offered in the style controls.
  static const List<int> highlightChoices = [
    green,
    yellow,
    white,
    cyan,
    red,
    blue,
  ];

  /// The 11 styles, in picker order. `nigraan` first = the default.
  static const List<StudioCaptionStyle> all = [
    StudioCaptionStyle(
      id: 'nigraan',
      nameEn: 'Nigraan Karaoke',
      nameUr: 'نگران کیروکی',
      animation: CaptionAnimation.karaoke,
      textColor: white,
      highlightColor: green,
      fontSizePx: 20,
      fontSizePt: 48,
      position: CaptionPosition.bottom,
    ),
    StudioCaptionStyle(
      id: 'bold_pop',
      nameEn: 'Bold Pop',
      nameUr: 'بولڈ پاپ',
      animation: CaptionAnimation.pop,
      textColor: white,
      highlightColor: yellow,
      outline: true,
      uppercase: true,
      fontSizePx: 26,
      fontSizePt: 56,
      position: CaptionPosition.middle,
    ),
    StudioCaptionStyle(
      id: 'pop_up',
      nameEn: 'Pop Up',
      nameUr: 'پاپ اپ',
      animation: CaptionAnimation.pop,
      textColor: white,
      highlightColor: yellow,
      fontSizePx: 30,
      fontSizePt: 64,
      position: CaptionPosition.middle,
    ),
    StudioCaptionStyle(
      id: 'karaoke_fill',
      nameEn: 'Karaoke Fill',
      nameUr: 'کیروکی فل',
      animation: CaptionAnimation.karaoke,
      textColor: white50,
      highlightColor: yellow,
      fontSizePx: 22,
      fontSizePt: 52,
      position: CaptionPosition.middle,
    ),
    StudioCaptionStyle(
      id: 'highlight_box',
      nameEn: 'Highlight Box',
      nameUr: 'ہائی لائٹ باکس',
      animation: CaptionAnimation.karaoke,
      textColor: white,
      highlightColor: black,
      highlightBg: yellow,
      outline: true,
      fontSizePx: 22,
      fontSizePt: 52,
      position: CaptionPosition.middle,
    ),
    StudioCaptionStyle(
      id: 'typewriter',
      nameEn: 'Typewriter',
      nameUr: 'ٹائپ رائٹر',
      animation: CaptionAnimation.typewriter,
      textColor: white,
      highlightColor: white,
      backgroundColor: black70,
      fontSizePx: 18,
      fontSizePt: 44,
      position: CaptionPosition.bottom,
    ),
    StudioCaptionStyle(
      id: 'one_word',
      nameEn: 'One Word',
      nameUr: 'ایک لفظ',
      animation: CaptionAnimation.pop,
      textColor: yellow,
      highlightColor: yellow,
      outline: true,
      uppercase: true,
      fontSizePx: 34,
      fontSizePt: 72,
      position: CaptionPosition.middle,
    ),
    StudioCaptionStyle(
      id: 'classic',
      nameEn: 'Classic',
      nameUr: 'کلاسک',
      animation: CaptionAnimation.flash,
      textColor: white,
      highlightColor: white,
      outline: true,
      bold: false,
      fontSizePx: 16,
      fontSizePt: 40,
      position: CaptionPosition.bottom,
    ),
    StudioCaptionStyle(
      id: 'news_ticker',
      nameEn: 'News Ticker',
      nameUr: 'نیوز ٹکر',
      animation: CaptionAnimation.flash,
      textColor: white,
      highlightColor: white,
      backgroundColor: blue,
      fontSizePx: 18,
      fontSizePt: 44,
      position: CaptionPosition.bottom,
    ),
    StudioCaptionStyle(
      id: 'spotlight',
      nameEn: 'Spotlight',
      nameUr: 'اسپاٹ لائٹ',
      animation: CaptionAnimation.karaoke,
      textColor: white,
      highlightColor: red,
      highlightScale: 1.25,
      fontSizePx: 22,
      fontSizePt: 52,
      position: CaptionPosition.middle,
    ),
    StudioCaptionStyle(
      id: 'minimal',
      nameEn: 'Minimal',
      nameUr: 'منیمل',
      animation: CaptionAnimation.flash,
      textColor: white,
      highlightColor: white,
      bold: false,
      fontSizePx: 14,
      fontSizePt: 36,
      position: CaptionPosition.bottom,
    ),
  ];

  static StudioCaptionStyle byId(String id) =>
      all.firstWhere((s) => s.id == id, orElse: () => all.first);

  // ---- word timing (even-split fallback) ----
  //
  // Used ONLY when a line carries no real word timings (no Whisper
  // words and no karaoke-sync words — e.g. a manually typed line).
  // Real timings live on the line; see `CaptionService.wordStartOf`
  // / `wordEndOf` / `activeWordIndexOf`, which prefer them.

  static List<String> wordsOf(String text) => text
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();

  /// Index of the word being spoken at [positionSeconds], or -1 when
  /// there is no text / the position is outside the line.
  static int activeWordIndex({
    required double start,
    required double end,
    required String text,
    required double positionSeconds,
  }) {
    final words = wordsOf(text);
    if (words.isEmpty) return -1;
    if (positionSeconds < start) return -1;
    final dur = end - start;
    if (dur <= 0) return 0;
    var i = ((positionSeconds - start) / (dur / words.length)).floor();
    if (i < 0) i = 0;
    if (i >= words.length) i = words.length - 1;
    return i;
  }

  /// Even-split start of word [index] in seconds.
  static double wordStart({
    required double start,
    required double end,
    required String text,
    required int index,
  }) {
    final words = wordsOf(text);
    if (words.isEmpty) return start;
    final dur = end - start;
    if (dur <= 0) return start;
    return start + (dur / words.length) * index;
  }

  /// Even-split end of word [index] in seconds.
  static double wordEnd({
    required double start,
    required double end,
    required String text,
    required int index,
  }) {
    final words = wordsOf(text);
    if (words.isEmpty) return end;
    final dur = end - start;
    if (dur <= 0) return end;
    return start + (dur / words.length) * (index + 1);
  }

  // ---- size / colour helpers ----

  /// Size scale for the S/M/L control.
  static double sizeScale(CaptionSize size) => switch (size) {
        CaptionSize.small => 0.8,
        CaptionSize.medium => 1.0,
        CaptionSize.large => 1.3,
      };

  /// ASS colour: &HAABBGGRR (alpha inverted: 00 = opaque).
  static String assColor(int argb) {
    final a = 255 - ((argb >> 24) & 0xFF);
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    String h(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '&H${h(a)}${h(b)}${h(g)}${h(r)}';
  }

  /// Position → ASS alignment (8 = top-centre, 5 = middle-centre,
  /// 2 = bottom-centre).
  static int assAlignment(CaptionPosition position) => switch (position) {
        CaptionPosition.top => 8,
        CaptionPosition.middle => 5,
        CaptionPosition.bottom => 2,
      };
}

/// One caption typeface. `family` is the Flutter font family name
/// declared in pubspec.yaml (or loaded at runtime via FontLoader for
/// the on-demand Kasheeda file); null = the phone's system font.
class CaptionFont {
  const CaptionFont({
    required this.id,
    required this.nameEn,
    required this.nameUr,
    required this.family,
    required this.isUrdu,
  });

  final String id;
  final String nameEn;
  final String nameUr;
  final String? family;
  final bool isUrdu;
}

class CaptionFonts {
  static const CaptionFont system = CaptionFont(
    id: 'system',
    nameEn: 'System',
    nameUr: 'سسٹم',
    family: null,
    isUrdu: false,
  );

  /// Jameel Noori Nastaleeq Kasheeda — the channel's own house font.
  /// Default for Urdu. Loaded on demand (see
  /// `AssetDownloadService.loadKasheedaFontFromFile`) — never bundled.
  static const CaptionFont jameelKasheeda = CaptionFont(
    id: 'jameel_kasheeda',
    nameEn: 'Jameel Noori Nastaleeq',
    nameUr: 'جمیل نوری نستعلیق',
    family: 'JameelNooriNastaleeqKasheeda',
    isUrdu: true,
  );

  static const CaptionFont bebas = CaptionFont(
    id: 'bebas',
    nameEn: 'Bebas Neue',
    nameUr: 'بیباس نیو',
    family: 'BebasNeue',
    isUrdu: false,
  );

  static const CaptionFont anton = CaptionFont(
    id: 'anton',
    nameEn: 'Anton',
    nameUr: 'اینٹن',
    family: 'Anton',
    isUrdu: false,
  );

  static const CaptionFont montserrat = CaptionFont(
    id: 'montserrat',
    nameEn: 'Montserrat Black',
    nameUr: 'مونٹسیراٹ بلیک',
    family: 'Montserrat',
    isUrdu: false,
  );

  static const CaptionFont poppins = CaptionFont(
    id: 'poppins',
    nameEn: 'Poppins Bold',
    nameUr: 'پوپنز بولڈ',
    family: 'Poppins',
    isUrdu: false,
  );

  static const List<CaptionFont> all = [
    system,
    jameelKasheeda,
    bebas,
    anton,
    montserrat,
    poppins,
  ];

  static CaptionFont byId(String id) =>
      all.firstWhere((f) => f.id == id, orElse: () => system);

  /// Fonts offered for a language: Urdu gets Jameel Noori first
  /// (the house font), English gets the display fonts first.
  /// Display fonts (Bebas/Anton/Montserrat/Poppins) are NOT bundled
  /// in TJ Pro — the ASS export writes the family name and the
  /// on-screen preview falls back to the system font when the family
  /// is unavailable. Kasheeda + System always work.
  static List<CaptionFont> forLang(String lang) => lang == 'ur'
      ? const [jameelKasheeda, system]
      : const [system, bebas, anton, montserrat, poppins];
}

/// One-tap caption preset: a style + position + size + font +
/// highlight + FX bundle, so the user picks a whole look instead of
/// tuning each control. The font is applied only when it is offered
/// for the current language (see [CaptionFonts.forLang]); otherwise
/// the current font is kept.
class CaptionPreset {
  const CaptionPreset({
    required this.id,
    required this.nameEn,
    required this.nameUr,
    required this.styleId,
    required this.position,
    required this.size,
    required this.fontId,
    required this.highlightColor,
    this.outline = true,
    this.shadow = false,
    this.background = false,
  });

  final String id;
  final String nameEn;
  final String nameUr;
  final String styleId;
  final CaptionPosition position;
  final CaptionSize size;
  final String fontId;
  final int highlightColor;
  final bool outline;
  final bool shadow;
  final bool background;
}

class CaptionPresets {
  /// Nigraan News: the channel's own reel look — Nigraan Karaoke,
  /// green spoken word, Jameel Noori, bottom.
  static const CaptionPreset nigraanNews = CaptionPreset(
    id: 'nigraan_news',
    nameEn: 'Nigraan News',
    nameUr: 'نگران نیوز',
    styleId: 'nigraan',
    position: CaptionPosition.bottom,
    size: CaptionSize.medium,
    fontId: 'jameel_kasheeda',
    highlightColor: StudioCaptionStyles.green,
    outline: true,
    shadow: true,
  );

  /// TikTok Bold: big popping words, middle of frame, display font.
  static const CaptionPreset tiktokBold = CaptionPreset(
    id: 'tiktok_bold',
    nameEn: 'TikTok Bold',
    nameUr: 'ٹک ٹاک بولڈ',
    styleId: 'bold_pop',
    position: CaptionPosition.middle,
    size: CaptionSize.large,
    fontId: 'bebas',
    highlightColor: StudioCaptionStyles.yellow,
    outline: true,
    shadow: true,
  );

  /// Clean: small plain white captions, no outline, no effects.
  static const CaptionPreset clean = CaptionPreset(
    id: 'clean',
    nameEn: 'Clean',
    nameUr: 'سادہ',
    styleId: 'classic',
    position: CaptionPosition.bottom,
    size: CaptionSize.small,
    fontId: 'system',
    highlightColor: StudioCaptionStyles.white,
    outline: false,
    shadow: false,
    background: false,
  );

  static const List<CaptionPreset> all = [
    nigraanNews,
    tiktokBold,
    clean,
  ];

  static CaptionPreset byId(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => nigraanNews);
}
