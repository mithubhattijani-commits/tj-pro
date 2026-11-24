import 'package:flutter/material.dart';

/// Dark premium + gold theme (Jaani, 2 Nov 2026) — matches the TJ Pro
/// promo poster mockup: deep-dark surfaces with gold accents and gold
/// selection highlights (e.g. the video timeline's selected clip).
///
/// Build 7 (v1.5.9, Phase 8) — THE DESIGN SYSTEM, consolidated.
/// This file is the single source for the app's approved look:
///
/// * Surfaces are deep-dark and professional ([background],
///   [surface], [panelSurface], [surfaceDeep]); icons are fine
///   monochrome line icons; sliders are thin with numeric values.
/// * Gold ([gold] in the editors, [homeGold] on Home) is for
///   SELECTION and ACCENT only — never decoration at large.
/// * Violet ([violet]) is the studio/editors' action accent.
/// * Glass ([glassCard]) is fake-glass for CHROME and PANELS
///   only — never over live video or a photo being edited.
/// * Home is the ONE glossy exception (user's same-to-same
///   reference): it keeps [homeGold] and its gradient cards.
///   That exception is Home-only; it does not leak into the
///   workspaces.
/// * Typography: English/Latin uses the section styles below;
///   Urdu uses [kasheedaFamily] via [urduTextStyle] — Nastaleeq
///   needs its natural line metrics, so Urdu styles must not be
///   given a tight fixed height.
///
/// Phase 8 is consolidation, NOT a redesign: every token below
/// is the exact value the approved screens already used (the
/// screens were surveyed, not re-styled), so nothing's look
/// changes — proven by the before/after widget-render comparison
/// in BUILD7-TOOL-TESTS.md.
class TjProTheme {
  // ---- Surfaces (Build 7 consolidation) ----

  /// App-wide deep-dark background (the studio screens' navy).
  static const Color background = surfaceNavy;

  /// Panel/card fill (the [glassCard] base).
  static const Color surface = Color(0xFF17172B);

  /// Editor panel fill (tool panels, inspector zones).
  static const Color panelSurface = Color(0xFF181828);

  /// Recessed wells (timeline surround, stage backing).
  static const Color surfaceDeep = Color(0xFF080810);

  /// Hairline border on dark surfaces (the [glassCard] border).
  static const Color borderSubtle = Color(0x14FFFFFF);

  /// Divider on dark surfaces.
  static const Color divider = Color(0x1FFFFFFF);

  /// Splash background — the in-app SplashGate and the native
  /// splash share this exact deep blue so startup is seamless.
  /// Build 8 (v1.6.0): the colour is sampled from the canonical
  /// splash poster's own edges (mean of its top-strip and
  /// bottom-strip medians, PIL-sampled 2026-11-24; the poster's
  /// edges are not uniform, but deep navy dominates) so the
  /// gate's contain-fit letterbox bands blend with the poster.
  static const Color splashBackground = Color(0xFF030E3F);

  // ---- Text colours (Build 7 consolidation) ----

  /// Primary text on dark surfaces.
  static const Color textPrimary = Color(0xFFFFFFFF);

  /// Secondary text (labels, values).
  static const Color textSecondary = Color(0xB3FFFFFF);

  /// Muted text (hints, timestamps).
  static const Color textMuted = Color(0x8AFFFFFF);

  /// Faint text (disabled, placeholders).
  static const Color textFaint = Color(0x61FFFFFF);

  /// Home's glossy gold (hero dots, Open pills, Premium pill).
  /// HOME ONLY — the editors use [gold]. The two golds are
  /// deliberately distinct: Home follows the user's glossy
  /// reference, the workspaces follow the professional rule.
  static const Color homeGold = Color(0xFFF5C542);

  // ---- Typography (Build 7 consolidation) ----

  /// The Jameel Noori Nastaleeq Kasheeda family name — the ONE
  /// source for it (AssetDownloadService registers the font
  /// under this name; renderers and pickers read it from here).
  static const String kasheedaFamily = 'JameelNooriNastaleeqKasheeda';

  /// Applies the Urdu typography rule to [base]: the Kasheeda
  /// family, with the style's own line metrics untouched (see
  /// the class doc — no tight fixed heights on Nastaleeq).
  static TextStyle urduTextStyle(TextStyle base) =>
      base.copyWith(fontFamily: kasheedaFamily);
  /// Primary gold accent (poster gold).
  static const Color gold = Color(0xFFFFD76A);

  /// Deeper gold for selected fills (timeline clips, tool buttons).
  static const Color goldDeep = Color(0xFF9C7A1F);

  /// Bright gold for selection borders and glints.
  static const Color goldBright = Color(0xFFFFE08A);

  /// Studio violet accent (News Studio / editors, mockup identity —
  /// the News Studio screens were built dark-navy + #7C3AED). The
  /// one-build UI polish pass uses this for the regrouped editor
  /// surfaces so the photo editor matches the studio identity
  /// instead of wearing its own gold uniform (study P13).
  static const Color violet = Color(0xFF7C3AED);

  /// Lighter violet for gradients and glows paired with [violet].
  static const Color violetBright = Color(0xFFA78BFA);

  /// Deep near-black navy surface used by the studio screens.
  static const Color surfaceNavy = Color(0xFF0D0D1A);

  /// Layered "3D" card decoration from the approved mockups: a soft
  /// vertical gradient, a subtle top-highlight border and a deep
  /// stacked shadow. Fake-glass (translucent solid + shadow) rather
  /// than real backdrop blur — the editors already run video preview
  /// + FFmpeg on mid-range phones (proposal §7).
  static BoxDecoration glassCard({
    Color base = const Color(0xFF17172B),
    double radius = 18,
    Color? glow,
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          base.withValues(alpha: 0.95),
          base.withValues(alpha: 0.75),
        ],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: (glow ?? violet).withValues(alpha: 0.18),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
        const BoxShadow(
          color: Color(0x66000000),
          blurRadius: 12,
          offset: Offset(0, 6),
        ),
      ],
    );
  }

  /// Gradient for primary actions (Export, Generate, Save) — the
  /// mockups' violet gradient button.
  static LinearGradient get primaryGradient => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[violetBright, violet],
      );

  // ---- CapCut-style design tokens (v1.2.0, additive) ----
  // Shared by the restyled picker surfaces (Caption Studio style
  // cards first): rounded cards, roomy chips and one section-title
  // style, so every CapCut-style sheet lines up. Existing tokens
  // above are unchanged.

  /// Corner radius of CapCut-style cards (style cards, sheets).
  static const double cardRadius = 16;

  /// Corner radius of CapCut-style chips / category tabs.
  static const double chipRadius = 12;

  /// Padding inside a CapCut-style chip / category tab.
  static const EdgeInsets chipPadding =
      EdgeInsets.symmetric(horizontal: 14, vertical: 8);

  /// Padding inside a CapCut-style card.
  static const EdgeInsets cardPadding = EdgeInsets.all(12);

  /// Gap between cards/chips in CapCut-style grids.
  static const double gridGap = 10;

  /// Section title style for CapCut-style sheets (e.g. the caption
  /// style categories: Trending / Karaoke / Urdu).
  static TextStyle get sectionTitleStyle => const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      );

  /// Secondary label style paired with [sectionTitleStyle].
  static TextStyle get sectionHintStyle => const TextStyle(
        fontSize: 12,
        color: Colors.white54,
      );

  static ThemeData get dark => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: gold,
          brightness: Brightness.dark,
        ),
      );
}
