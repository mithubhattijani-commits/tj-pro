/// Live styled caption preview (Phase 5).
///
/// Renders one [SubtitleLine] the way it will look on screen / in
/// the burn-in: the word being spoken at [positionSec] is drawn in
/// the style's highlight colour (Nigraan green #3AEC70 by default),
/// the rest in the style's text colour.
///
/// Animation behaviour (same as the ASS export):
///   - karaoke: whole line visible, spoken word highlighted (and
///     scaled by the style's `highlightScale`, e.g. Spotlight 1.25x).
///   - pop: only the spoken word is shown, big.
///   - typewriter: words appear one by one and stay.
///   - flash: whole line at once, no word animation.
///
/// The widget is pure presentation: [positionSec] is supplied by the
/// caller (the voiceover player's position, or a scrub slider).
library;

import 'package:flutter/material.dart';

import '../news_analysis.dart';
import '../../services/caption_styles.dart';
import '../karaoke_sync.dart';

class StyledCaptionPreview extends StatelessWidget {
  const StyledCaptionPreview({
    super.key,
    required this.line,
    required this.style,
    required this.positionSec,
    this.highlightColor,
    this.fontFamily,
    this.fontSizePx,
    this.showBackground,
  });

  final SubtitleLine line;
  final StudioCaptionStyle style;

  /// Playback position in seconds (voiceover position, or scrub).
  final double positionSec;

  /// Highlight override (the style control's colour choice).
  final int? highlightColor;

  /// Font family override (the style control's font choice).
  final String? fontFamily;

  /// Base font size in logical px (style default when null).
  final double? fontSizePx;

  /// Force the line background on/off (style default when null).
  final bool? showBackground;

  bool get _isArabic => RegExp(r'[\u0600-\u06FF]').hasMatch(line.text);

  @override
  Widget build(BuildContext context) {
    final active = activeWordIndexInLine(line, positionSec);
    final words = StudioCaptionStyles.wordsOf(line.text);
    if (words.isEmpty) return const SizedBox.shrink();
    final baseSize = (fontSizePx ?? style.fontSizePx);
    final highlight = Color(highlightColor ?? style.highlightColor);
    final textColor = Color(style.textColor);
    String show(String w) => style.uppercase ? w.toUpperCase() : w;

    TextStyle wordStyle(bool isActive) => TextStyle(
          color: isActive ? highlight : textColor,
          fontSize: baseSize * (isActive ? style.highlightScale : 1.0),
          fontWeight: style.bold ? FontWeight.bold : FontWeight.normal,
          fontFamily: fontFamily,
          shadows: style.shadow
              ? const [
                  Shadow(
                    color: Colors.black54,
                    offset: Offset(1, 1),
                    blurRadius: 2,
                  ),
                ]
              : null,
        );

    final List<InlineSpan> spans;
    switch (style.animation) {
      case CaptionAnimation.pop:
        // Only the spoken word is on screen (first word before it
        // starts, last word after it ends).
        final index = active < 0
            ? (positionSec < line.startSec ? 0 : words.length - 1)
            : active;
        spans = [
          TextSpan(text: show(words[index]), style: wordStyle(true)),
        ];
      case CaptionAnimation.typewriter:
        // Words appear one by one and stay.
        final upto = active < 0
            ? (positionSec < line.startSec ? 0 : words.length)
            : active + 1;
        spans = [
          for (var i = 0; i < upto; i++)
            TextSpan(text: '${show(words[i])} ', style: wordStyle(false)),
        ];
      case CaptionAnimation.flash:
        spans = [
          TextSpan(text: show(line.text), style: wordStyle(false)),
        ];
      case CaptionAnimation.karaoke:
        spans = [
          for (var i = 0; i < words.length; i++)
            TextSpan(
              text: '${show(words[i])} ',
              style: wordStyle(i == active),
            ),
        ];
    }

    final useBackground =
        showBackground ?? (style.backgroundColor != 0);
    final bg = useBackground
        ? Color(style.backgroundColor != 0
            ? style.backgroundColor
            : StudioCaptionStyles.black70)
        : null;
    final content = RichText(
      textAlign: TextAlign.center,
      textDirection: _isArabic ? TextDirection.rtl : TextDirection.ltr,
      text: TextSpan(children: spans),
    );
    if (bg == null) return content;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: content,
    );
  }
}
