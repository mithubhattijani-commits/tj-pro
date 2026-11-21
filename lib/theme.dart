import 'package:flutter/material.dart';

/// Dark premium + gold theme (Jaani, 2 Nov 2026) — matches the TJ Pro
/// promo poster mockup: deep-dark surfaces with gold accents and gold
/// selection highlights (e.g. the video timeline's selected clip).
class TjProTheme {
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
