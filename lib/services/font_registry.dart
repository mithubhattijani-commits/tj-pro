/// Urdu font registry (v1.2.0, plan §4) — the SINGLE list that drives
/// every Urdu font picker, preview and export in TJ Pro.
///
/// Before this file, Urdu typefaces were scattered: the Kasheeda house
/// font lived in `caption_styles.dart` (`CaptionFonts`), the template
/// renderer hard-coded `AssetDownloadService.kasheedaFamily`, and any
/// new font meant editing several pickers. Now:
///
///   - Pickers iterate [UrduFonts.all].
///   - Previews call [UrduFontOption.apply] (or
///     [UrduFonts.styleFor]) to build the [TextStyle].
///   - Exporters read [UrduFontOption.familyLabel] — the Flutter /
///     ASS font-family name — from the same entry, so what the user
///     picks is what the export writes.
///
/// Sources, all licensing-safe:
///   - google_fonts package (already a dependency): runtime download +
///     on-device cache of open-licensed (OFL / Apache) Google Fonts.
///     Each entry below maps to a real `GoogleFonts.<getter>`; the
///     fonts were verified against the Google Fonts catalogue
///     (Noto Nastaliq Urdu, Noto Naskh Arabic, Gulzar, Scheherazade
///     New, Amiri, Lateef, Harmattan, Mirza, Katibeh all ship there,
///     and google_fonts generates one getter per catalogue family).
///   - The bundled house font: Jameel Noori Nastaleeq Kasheeda. It is
///     NOT in pubspec assets — it is downloaded on demand and
///     registered at runtime via `FontLoader` under
///     [AssetDownloadService.kasheedaFamily] by
///     `AssetDownloadService.loadKasheedaFontFromFile` (the same
///     mechanism the News Studio / template renderer already use).
///     Its registry entry is marked [UrduFontOption.isBundled] in the
///     plan's sense — it is the app's own built-in house font, made
///     available by that loader; callers must ensure the loader ran
///     (as the existing screens already do) before relying on it.
///
/// RTL shaping is the renderer's job (existing discipline: previews
/// set `TextDirection.rtl` for Arabic-script text, ASS export writes
/// the family name). This file is only the list + style builders.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'asset_download_service.dart';

/// One Urdu-capable typeface option.
class UrduFontOption {
  const UrduFontOption({
    required this.id,
    required this.name,
    required this.familyLabel,
    required this.isBundled,
    required this.apply,
    this.nameUr,
    this.script,
  });

  /// Stable id used in saved settings / project JSON.
  final String id;

  /// Display name (Latin) for pickers.
  final String name;

  /// Display name in Urdu script, when known.
  final String? nameUr;

  /// The font-family name a renderer / exporter should use: for
  /// google_fonts entries this is the family name google_fonts
  /// registers after [apply] has run; for the bundled Kasheeda it is
  /// [AssetDownloadService.kasheedaFamily].
  final String familyLabel;

  /// True for the app's own house font (Jameel Noori Nastaleeq
  /// Kasheeda, registered via FontLoader — see the library doc);
  /// false for google_fonts runtime-downloaded fonts.
  final bool isBundled;

  /// Script flavour for picker grouping: 'Nastaliq', 'Naskh' or
  /// 'Display'. Null = ungrouped.
  final String? script;

  /// Builds the [TextStyle] for this font on top of [base] (size,
  /// colour, weight already set by the caller). For google_fonts
  /// entries this triggers the runtime download + cache; for the
  /// bundled font it simply sets the family name.
  final TextStyle Function(TextStyle base) apply;
}

/// The registry. Picker order: house font first (the channel's
/// default), then Nastaliq, then Naskh, then display faces.
class UrduFonts {
  UrduFonts._();

  /// Jameel Noori Nastaleeq Kasheeda — the channel's house font.
  /// Registered at runtime by
  /// `AssetDownloadService.loadKasheedaFontFromFile` under
  /// [AssetDownloadService.kasheedaFamily]; never a pubspec asset.
  static final UrduFontOption jameelKasheeda = UrduFontOption(
    id: 'jameel_kasheeda',
    name: 'Jameel Noori Nastaleeq',
    nameUr: 'جمیل نوری نستعلیق',
    familyLabel: AssetDownloadService.kasheedaFamily,
    isBundled: true,
    script: 'Nastaliq',
    apply: (base) =>
        base.copyWith(fontFamily: AssetDownloadService.kasheedaFamily),
  );

  static final UrduFontOption notoNastaliqUrdu = UrduFontOption(
    id: 'noto_nastaliq_urdu',
    name: 'Noto Nastaliq Urdu',
    nameUr: 'نوٹو نستعلیق اردو',
    familyLabel: 'Noto Nastaliq Urdu',
    isBundled: false,
    script: 'Nastaliq',
    apply: (base) => GoogleFonts.notoNastaliqUrdu(textStyle: base),
  );

  static final UrduFontOption gulzar = UrduFontOption(
    id: 'gulzar',
    name: 'Gulzar',
    nameUr: 'گلزار',
    familyLabel: 'Gulzar',
    isBundled: false,
    script: 'Nastaliq',
    apply: (base) => GoogleFonts.gulzar(textStyle: base),
  );

  static final UrduFontOption notoNaskhArabic = UrduFontOption(
    id: 'noto_naskh_arabic',
    name: 'Noto Naskh Arabic',
    nameUr: 'نوٹو نسخ عربی',
    familyLabel: 'Noto Naskh Arabic',
    isBundled: false,
    script: 'Naskh',
    apply: (base) => GoogleFonts.notoNaskhArabic(textStyle: base),
  );

  static final UrduFontOption scheherazadeNew = UrduFontOption(
    id: 'scheherazade_new',
    name: 'Scheherazade New',
    nameUr: 'شہر زاد نیو',
    familyLabel: 'Scheherazade New',
    isBundled: false,
    script: 'Naskh',
    apply: (base) => GoogleFonts.scheherazadeNew(textStyle: base),
  );

  static final UrduFontOption amiri = UrduFontOption(
    id: 'amiri',
    name: 'Amiri',
    nameUr: 'امیری',
    familyLabel: 'Amiri',
    isBundled: false,
    script: 'Naskh',
    apply: (base) => GoogleFonts.amiri(textStyle: base),
  );

  static final UrduFontOption lateef = UrduFontOption(
    id: 'lateef',
    name: 'Lateef',
    nameUr: 'لطیف',
    familyLabel: 'Lateef',
    isBundled: false,
    script: 'Naskh',
    apply: (base) => GoogleFonts.lateef(textStyle: base),
  );

  static final UrduFontOption harmattan = UrduFontOption(
    id: 'harmattan',
    name: 'Harmattan',
    nameUr: 'حرمتن',
    familyLabel: 'Harmattan',
    isBundled: false,
    script: 'Naskh',
    apply: (base) => GoogleFonts.harmattan(textStyle: base),
  );

  static final UrduFontOption mirza = UrduFontOption(
    id: 'mirza',
    name: 'Mirza',
    nameUr: 'مرزا',
    familyLabel: 'Mirza',
    isBundled: false,
    script: 'Display',
    apply: (base) => GoogleFonts.mirza(textStyle: base),
  );

  static final UrduFontOption katibeh = UrduFontOption(
    id: 'katibeh',
    name: 'Katibeh',
    nameUr: 'کاتبہ',
    familyLabel: 'Katibeh',
    isBundled: false,
    script: 'Display',
    apply: (base) => GoogleFonts.katibeh(textStyle: base),
  );

  /// Every registered Urdu font, in picker order.
  static final List<UrduFontOption> all = [
    jameelKasheeda,
    notoNastaliqUrdu,
    gulzar,
    notoNaskhArabic,
    scheherazadeNew,
    amiri,
    lateef,
    harmattan,
    mirza,
    katibeh,
  ];

  /// User-uploaded fonts (fix #51), rebuilt at runtime by
  /// `UserFontService.syncIntoRegistry()` (lib/services/
  /// user_font_service.dart) from the fonts the user added under
  /// "Apna Font". Empty until that sync runs. This list is the ONLY
  /// mutable part of the registry — the built-in [all] list above is
  /// never touched by user fonts.
  static final List<UrduFontOption> userFonts = <UrduFontOption>[];

  /// Built-ins plus user fonts, in picker order — the list pickers
  /// that support custom fonts should iterate.
  static List<UrduFontOption> get allWithUser =>
      <UrduFontOption>[...all, ...userFonts];

  /// Lookup by [UrduFontOption.id]; built-ins are searched first,
  /// then [userFonts]; unknown ids fall back to the house font
  /// (Kasheeda), matching the app's Urdu default.
  static UrduFontOption byId(String id) {
    for (final font in all) {
      if (font.id == id) return font;
    }
    for (final font in userFonts) {
      if (font.id == id) return font;
    }
    return jameelKasheeda;
  }

  /// Builds a ready [TextStyle] for font [id] at [fontSize] / [color]
  /// (weight defaults to bold — headlines, ribbons and captions in
  /// TJ Pro are bold by house style). This is the one helper pickers,
  /// previews and exporters share.
  static TextStyle styleFor(
    String id, {
    required double fontSize,
    required Color color,
    FontWeight fontWeight = FontWeight.bold,
    double? height,
    List<Shadow>? shadows,
  }) {
    return byId(id).apply(
      TextStyle(
        fontSize: fontSize,
        color: color,
        fontWeight: fontWeight,
        height: height,
        shadows: shadows,
      ),
    );
  }
}

/// v1.5.1 (fixes #51/#52): resolves a saved font id to the
/// font-family name the parity renderer (export) and the live
/// preview should pass for it. The house Kasheeda id resolves to
/// null — callers keep their exact historic behaviour (the parity
/// engine's fontReady Kasheeda path; the preview's own default).
/// Every other id (google_fonts built-ins, #51 user uploads)
/// resolves to its registered family label; the family is live
/// once the option's apply() ran in this process (google_fonts)
/// or the font was FontLoader-registered (user fonts, via
/// UserFontService.loadAll — the export and the News Maker both
/// run it on entry).
String? newsFontFamilyForId(String id) {
  if (id == UrduFonts.jameelKasheeda.id) return null;
  for (final font in UrduFonts.allWithUser) {
    if (font.id == id) return font.familyLabel;
  }
  return null;
}
