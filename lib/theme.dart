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

  static ThemeData get dark => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: gold,
          brightness: Brightness.dark,
        ),
      );
}
