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
///
/// v1.18.0 (Motion reskin, user-approved from the
/// mockups-motion-style screens): a NEW skin layer lives below
/// (the `motion*` tokens + the enriched [dark] ThemeData) —
/// deep navy/glass surfaces with electric blue/purple/cyan
/// gradients for every screen EXCEPT Home. The gold tokens
/// above stay untouched: Home still reads them, and gold
/// remains the editors' selection colour where a screen pins
/// it explicitly. Skin only — no control, layout or behaviour
/// changed anywhere by this layer.
class TjProTheme {
  // ---- Surfaces (Build 7 consolidation) ----

  /// App-wide deep-dark background (the studio screens' navy).
  static const Color background = surfaceNavy;

  /// Panel/card fill (the [glassCard] base). v1.18.0: shifted
  /// into the Motion navy family (was 0xFF17172B).
  static const Color surface = Color(0xFF0D1734);

  /// Editor panel fill (tool panels, inspector zones).
  /// v1.18.0: the Motion panel navy (was 0xFF181828).
  static const Color panelSurface = Color(0xFF0C1428);

  /// Recessed wells (timeline surround, stage backing).
  /// v1.18.0: the Motion background's dark end (was 0xFF080810).
  static const Color surfaceDeep = Color(0xFF04060F);

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
  /// v1.18.0: the Motion mockups' background top (was 0xFF0D0D1A).
  static const Color surfaceNavy = Color(0xFF060A1C);

  /// Layered "3D" card decoration from the approved mockups: a soft
  /// vertical gradient, a subtle top-highlight border and a deep
  /// stacked shadow. Fake-glass (translucent solid + shadow) rather
  /// than real backdrop blur — the editors already run video preview
  /// + FFmpeg on mid-range phones (proposal §7).
  static BoxDecoration glassCard({
    Color base = const Color(0xFF0D1734),
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
          color: (glow ?? motionBlue).withValues(alpha: 0.18),
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

  // ---- Motion Graphics style tokens (v1.18.0 reskin) ----
  // The user-approved app-wide skin (mockups in
  // ~/workspace/tj-pro-build/mockups-motion-style/, values taken
  // from those HTML/CSS sources): deep navy/black surfaces,
  // electric blue + purple + cyan gradients, glassy cards and
  // glowing gradient buttons. HOME IS THE ONE EXCEPTION — Home
  // keeps its own glossy reference look and none of these tokens
  // feed it (Home paints its own explicit colours; [gold],
  // [homeGold] and [splashBackground] are untouched).

  /// Mockup page background, top (#060a1c in the CSS).
  static const Color motionBgTop = Color(0xFF060A1C);

  /// Mockup page background, bottom (#04060f in the CSS).
  static const Color motionBgBottom = Color(0xFF04060F);

  /// Electric violet (#7b2fff) — the gradient's start.
  static const Color motionViolet = Color(0xFF7B2FFF);

  /// Electric blue (#2f7bff) — the gradient's middle / primary.
  static const Color motionBlue = Color(0xFF2F7BFF);

  /// Electric cyan (#00c6ff) — the gradient's end / glow accent.
  static const Color motionCyan = Color(0xFF00C6FF);

  /// Deep blue (#0072ff) — the cyan gradient's end.
  static const Color motionBlueDeep = Color(0xFF0072FF);

  /// Bluish secondary text (#8fa8d8 in the CSS).
  static const Color motionTextSecondary = Color(0xFF8FA8D8);

  /// Solid panel fill — the opaque stand-in for the glass
  /// gradient's dark end, for large surfaces where a gradient
  /// would be noise (panels, sheets, timeline surrounds).
  static const Color motionPanel = Color(0xFF0C1428);

  /// Raised glass fill (chips, tiles, wells on [motionPanel]).
  static const Color motionPanelRaised = Color(0xFF14224A);

  /// Unselected chip / dock tile fill.
  static const Color motionChipFill = Color(0xFF101B38);

  /// Hairline border on glass surfaces (bluish white).
  static const Color motionBorder = Color(0x26FFFFFF);

  /// The full page background gradient (CSS 180deg:
  /// #060a1c -> #04060f).
  static const LinearGradient motionBackgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[motionBgTop, motionBgBottom],
  );

  /// The primary action gradient (CSS 90deg: #7b2fff,
  /// #2f7bff 55%, #00c6ff) — glowing buttons, play buttons,
  /// selected fills that can carry a gradient.
  static const LinearGradient motionGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: <Color>[motionViolet, motionBlue, motionCyan],
    stops: <double>[0, 0.55, 1],
  );

  /// The cyan action gradient (CSS 135deg: #00c6ff, #0072ff) —
  /// Export-style buttons in the mockups.
  static const LinearGradient motionCyanGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[motionCyan, motionBlueDeep],
  );

  /// Glassy card decoration from the mockups (CSS 160deg:
  /// rgba(40,70,150,.42) -> rgba(9,14,34,.72), thin light border,
  /// soft deep shadow, optional blue glow). Fake glass — a
  /// translucent gradient + border, NO backdrop blur, so
  /// low-end phones stay smooth.
  static BoxDecoration motionGlass({
    double radius = 22,
    Color? borderColor,
    bool glow = false,
  }) {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[Color(0x6B284696), Color(0xB8090E22)],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? motionBorder),
      boxShadow: <BoxShadow>[
        if (glow)
          const BoxShadow(
            color: Color(0x662F7BFF),
            blurRadius: 24,
            offset: Offset(0, 6),
          ),
        const BoxShadow(
          color: Color(0x59000000),
          blurRadius: 16,
          offset: Offset(0, 8),
        ),
      ],
    );
  }

  /// Solid panel decoration (the glass family's opaque sibling):
  /// [motionPanel] fill, hairline border, soft shadow.
  static BoxDecoration motionPanelDeco({double radius = 20}) {
    return BoxDecoration(
      color: motionPanel,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: motionBorder),
      boxShadow: const <BoxShadow>[
        BoxShadow(
          color: Color(0x40000000),
          blurRadius: 12,
          offset: Offset(0, 6),
        ),
      ],
    );
  }

  /// Glowing gradient button decoration (the mockups' Export /
  /// Create buttons): [motionGradient] (or [motionCyanGradient])
  /// with a coloured glow shadow under it.
  static BoxDecoration motionGlowButton({
    double radius = 16,
    LinearGradient gradient = motionGradient,
    Color glowColor = motionCyan,
  }) {
    return BoxDecoration(
      gradient: gradient,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: glowColor.withValues(alpha: 0.45),
          blurRadius: 22,
          offset: const Offset(0, 6),
        ),
        const BoxShadow(
          color: Color(0x40000000),
          blurRadius: 10,
          offset: Offset(0, 4),
        ),
      ],
    );
  }

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

  /// The app-wide ThemeData. v1.18.0 (Motion reskin): the
  /// scheme is seeded from [motionBlue] and every Material
  /// chrome surface (scaffold, app bar, cards, dialogs, sheets,
  /// menus, sliders, chips, switches, inputs, snackbars) wears
  /// the Motion navy/glass skin, so screens built on stock
  /// Material widgets inherit the approved look without
  /// per-screen restyling. HOME EXCEPTION: Home paints its own
  /// explicit colours for its screen (header, hero, cards,
  /// bottom nav) and does not read these chrome values for its
  /// own rendering — its look is unchanged.
  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: motionBlue,
      brightness: Brightness.dark,
    ).copyWith(
      primary: motionBlue,
      onPrimary: Colors.white,
      secondary: motionCyan,
      onSecondary: Colors.black,
      tertiary: motionViolet,
      surface: const Color(0xFF0A1128),
      onSurface: Colors.white,
      surfaceContainerLowest: motionBgBottom,
      surfaceContainerLow: const Color(0xFF0A1128),
      surfaceContainer: motionPanel,
      surfaceContainerHigh: motionPanelRaised,
      surfaceContainerHighest: const Color(0xFF182A5C),
      onSurfaceVariant: motionTextSecondary,
      outline: const Color(0x2EFFFFFF),
      outlineVariant: const Color(0x1FFFFFFF),
    );
    const buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: motionBgBottom,
      appBarTheme: const AppBarTheme(
        backgroundColor: motionBgTop,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: motionPanel,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: motionBorder),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFF0B1327),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(
          color: Color(0xFFC9D6F2),
          fontSize: 14,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF0A1128),
        modalBackgroundColor: Color(0xFF0A1128),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        dragHandleColor: Color(0x3DFFFFFF),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: const Color(0xFF0D1734),
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: motionPanelRaised,
        contentTextStyle: TextStyle(color: Colors.white, fontSize: 14),
        actionTextColor: motionCyan,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 3,
        activeTrackColor: motionBlue,
        inactiveTrackColor: Color(0x2EFFFFFF),
        thumbColor: Colors.white,
        overlayColor: Color(0x2900C6FF),
        valueIndicatorColor: motionBlue,
        valueIndicatorTextStyle: TextStyle(color: Colors.white),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: motionChipFill,
        selectedColor: motionBlue,
        checkmarkColor: Colors.white,
        labelStyle: const TextStyle(color: Colors.white, fontSize: 13),
        secondaryLabelStyle:
            const TextStyle(color: Colors.white, fontSize: 13),
        side: const BorderSide(color: Color(0x1FFFFFFF)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(chipRadius),
        ),
        padding: chipPadding,
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0x1FFFFFFF),
        thickness: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: motionCyan,
        linearTrackColor: Color(0x1FFFFFFF),
        circularTrackColor: Color(0x1FFFFFFF),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: motionPanel,
        hintStyle: const TextStyle(color: motionTextSecondary),
        labelStyle: const TextStyle(color: motionTextSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x1FFFFFFF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0x1FFFFFFF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: motionBlue, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: motionBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: buttonShape,
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: motionBlue,
          foregroundColor: Colors.white,
          shape: buttonShape,
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0x3DFFFFFF)),
          shape: buttonShape,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF7FB2FF),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected)
              ? Colors.white
              : const Color(0xFF9AA7C7),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected)
              ? motionBlue
              : const Color(0xFF1B2A4D),
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected)
              ? const Color(0x7300C6FF)
              : const Color(0x1FFFFFFF),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected)
              ? motionBlue
              : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: const BorderSide(color: Color(0x61FFFFFF)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected)
              ? motionBlue
              : const Color(0x61FFFFFF),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: motionTextSecondary,
        indicatorColor: motionCyan,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Color(0x1FFFFFFF),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: motionBlue,
        foregroundColor: Colors.white,
      ),
      bottomAppBarTheme: const BottomAppBarThemeData(
        color: motionBgTop,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: motionBgTop,
        surfaceTintColor: Colors.transparent,
        indicatorColor: motionBlue.withValues(alpha: 0.25),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, color: Colors.white),
        ),
        iconTheme: WidgetStateProperty.all(
          const IconThemeData(color: Colors.white),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: motionTextSecondary,
        textColor: Colors.white,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        iconColor: motionTextSecondary,
        collapsedIconColor: motionTextSecondary,
        textColor: Colors.white,
        collapsedTextColor: Colors.white,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: motionCyan,
        selectionColor: Color(0x662F7BFF),
        selectionHandleColor: motionBlue,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: motionPanelRaised,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      datePickerTheme: const DatePickerThemeData(
        backgroundColor: Color(0xFF0B1327),
        surfaceTintColor: Colors.transparent,
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStateProperty.all(motionPanel),
        surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(
            const Color(0xFF0D1734),
          ),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
        ),
      ),
    );
  }
}
