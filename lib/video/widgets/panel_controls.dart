/// Shared panel controls of the Video Editor (Master Plan
/// Phase 4 split): small builders used by several tool panels and
/// tool rows. All editor state is reached through
/// [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../services/pro_editor.dart';
import '../editor_stage.dart';
import '../video_editor_controller.dart';

  /// One icon+label choice item — the global UI rule (user order
  /// 22 Nov 2026): every choice inside a tool is an icon above a
  /// label, in a horizontal swipeable row, never bare text. Mirrors
  /// the main tool rail's look (violet when selected).
  Widget iconChoiceItem(
    VideoEditorController host, {
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback? onTap,
    Color? iconColor,
    TextStyle? labelStyle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
            decoration: BoxDecoration(
              color: selected ? TjProTheme.violet : const Color(0xFF232323),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 21, color: iconColor ?? Colors.white),
                const SizedBox(height: 3),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      labelStyle ??
                      const TextStyle(color: Colors.white, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A horizontal scrollable row of [_iconChoiceItem]s — swipe
  /// left/right and more options keep appearing; nothing is
  /// buried in a dropdown or a wrapped stack.
  Widget iconChoiceRail(VideoEditorController host, List<Widget> items) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: items),
    );
  }


/// Layout-transparent wrapper for a panel's child list (verified
/// by a widget probe in Build 4: inside the panel ListView it gives
/// children constraints/size/position identical to direct children).
class PanelColumn extends StatelessWidget {
  final List<Widget> children;
  const PanelColumn({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
}


  /// Section title inside a regrouped tab panel (one-build UI):
  /// violet accent bar + bold label, matching the approved mockups.
class SectionTitle extends StatelessWidget {
  final String title;
  const SectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: TjProTheme.violet,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          // Flexible (v1.5.2, #69 sweep): long section titles
          // overflowed the panel Row on narrow screens.
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


  /// Index of the first widget matching [test], or -1. Used to
  /// split a legacy panel body at a section anchor (the widgets
  /// themselves are preserved exactly — only re-homed, §5).
  int anchorIndex(List<Widget> items, bool Function(Widget) test) {
    for (var i = 0; i < items.length; i++) {
      if (test(items[i])) return i;
    }
    return -1;
  }

  bool isTextStarting(Widget w, String prefix) =>
      w is Text && (w.data ?? '').startsWith(prefix);

  /// Index of the _sectionTitle whose text starts with [part], or
  /// -1 (v1.5.0 — section anchors for the Canvas / Precut splits).
  int sectionAnchor(List<Widget> items, String part) {
    return anchorIndex(items, (w) {
      if (w is Padding && w.child is Row) {
        for (final c in (w.child as Row).children) {
          if (c is Text && (c.data ?? '').startsWith(part)) return true;
        }
      }
      return false;
    });
  }

  /// The ONE grade slider currently picked on Colour › Adjust.
  Widget gradeSliderWidget(VideoEditorController host) {
    switch (host.gradeSlider) {
      case 'Temperature':
        return ProSlider(
          label: 'Temperature',
          value: host.proTemperature,
          min: -100,
          max: 100,
          divisions: 40,
          digits: 0,
          onChanged: (v) => host.update(() => host.proTemperature = v),
        );
      case 'Tint':
        return ProSlider(
          label: 'Tint',
          value: host.proTint,
          min: -100,
          max: 100,
          divisions: 40,
          digits: 0,
          onChanged: (v) => host.update(() => host.proTint = v),
        );
      case 'Saturation':
        return ProSlider(
          label: 'Saturation',
          value: host.proSaturation,
          min: 0,
          max: 2,
          divisions: 40,
          onChanged: (v) => host.update(() => host.proSaturation = v),
        );
      case 'Vibrance':
        return ProSlider(
          label: 'Vibrance',
          value: host.proVibrance,
          min: 0,
          max: 2,
          divisions: 40,
          onChanged: (v) => host.update(() => host.proVibrance = v),
        );
      case 'Contrast':
        return ProSlider(
          label: 'Contrast',
          value: host.proContrast,
          min: 0,
          max: 2,
          divisions: 40,
          onChanged: (v) => host.update(() => host.proContrast = v),
        );
      case 'Shadows':
        return ProSlider(
          label: 'Shadows',
          value: host.proShadows,
          min: -100,
          max: 100,
          divisions: 40,
          digits: 0,
          onChanged: (v) => host.update(() => host.proShadows = v),
        );
      case 'Highlights':
        return ProSlider(
          label: 'Highlights',
          value: host.proHighlights,
          min: -100,
          max: 100,
          divisions: 40,
          digits: 0,
          onChanged: (v) => host.update(() => host.proHighlights = v),
        );
      case 'Brightness':
        return ProSlider(
          label: 'Brightness',
          value: host.proBrightness,
          min: -100,
          max: 100,
          divisions: 40,
          digits: 0,
          onChanged: (v) => host.update(() => host.proBrightness = v),
        );
      // v1.4.0 Adjust extras — one shared slider, values ride
      // _adjustExtraFilter() at export.
      case 'Brilliance':
        return ProSlider(
          label: 'Brilliance',
          value: host.adjBrilliance,
          min: -100,
          max: 100,
          divisions: 40,
          digits: 0,
          onChanged: (v) => host.update(() => host.adjBrilliance = v),
        );
      case 'Sharpen':
        return ProSlider(
          label: 'Sharpen',
          value: host.adjSharpen,
          min: 0,
          max: 100,
          divisions: 20,
          digits: 0,
          onChanged: (v) => host.update(() => host.adjSharpen = v),
        );
      case 'Clarity':
        return ProSlider(
          label: 'Clarity',
          value: host.adjClarity,
          min: 0,
          max: 100,
          divisions: 20,
          digits: 0,
          onChanged: (v) => host.update(() => host.adjClarity = v),
        );
      case 'Whites':
        return ProSlider(
          label: 'Whites',
          value: host.adjWhites,
          min: -100,
          max: 100,
          divisions: 40,
          digits: 0,
          onChanged: (v) => host.update(() => host.adjWhites = v),
        );
      case 'Blacks':
        return ProSlider(
          label: 'Blacks',
          value: host.adjBlacks,
          min: -100,
          max: 100,
          divisions: 40,
          digits: 0,
          onChanged: (v) => host.update(() => host.adjBlacks = v),
        );
      case 'Hue':
        return ProSlider(
          label: 'Hue (deg)',
          value: host.adjHue,
          min: -180,
          max: 180,
          divisions: 72,
          digits: 0,
          onChanged: (v) => host.update(() => host.adjHue = v),
        );
      case 'Fade':
        return ProSlider(
          label: 'Fade',
          value: host.adjFade,
          min: 0,
          max: 100,
          divisions: 20,
          digits: 0,
          onChanged: (v) => host.update(() => host.adjFade = v),
        );
      case 'Vignette':
        return ProSlider(
          label: 'Vignette',
          value: host.adjVignette,
          min: 0,
          max: 100,
          divisions: 20,
          digits: 0,
          onChanged: (v) => host.update(() => host.adjVignette = v),
        );
      case 'Grain':
        return ProSlider(
          label: 'Grain',
          value: host.adjGrain,
          min: 0,
          max: 100,
          divisions: 20,
          digits: 0,
          onChanged: (v) => host.update(() => host.adjGrain = v),
        );
      default:
        return ProSlider(
          label: 'Exposure',
          value: host.proExposure,
          min: -100,
          max: 100,
          divisions: 40,
          digits: 0,
          onChanged: (v) => host.update(() => host.proExposure = v),
        );
    }
  }

class ProSlider extends StatelessWidget {
  const ProSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.digits = 2,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;
  final int digits;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label), Text(value.toStringAsFixed(digits))],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// §6.10 — the custom speed-ramp curve: three plateaus (start /
/// middle / end thirds) drawn as a step graph. Build 3: each
/// plateau carries a drag HANDLE at its centre (the geometry is
/// [SpeedRampMath], shared with the panel's drag handler, so the
/// point under the finger is the point that moves).
class RampCurvePainter extends CustomPainter {
  const RampCurvePainter(this.start, this.mid, this.end);

  final double start;
  final double mid;
  final double end;

  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 4),
      Offset(size.width, size.height - 4),
      axis,
    );
    double y(double speed) => SpeedRampMath.yForSpeed(speed, size.height);
    final path = Path()
      ..moveTo(0, y(start))
      ..lineTo(size.width / 3, y(start))
      ..lineTo(size.width / 3, y(mid))
      ..lineTo(size.width * 2 / 3, y(mid))
      ..lineTo(size.width * 2 / 3, y(end))
      ..lineTo(size.width, y(end));
    canvas.drawPath(
      path,
      Paint()
        ..color = TjProTheme.gold
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    // Drag handles: one per plateau, at its centre.
    final speeds = [start, mid, end];
    for (var i = 0; i < 3; i++) {
      final c = Offset(SpeedRampMath.centreX(i, size.width), y(speeds[i]));
      canvas.drawCircle(c, 7, Paint()..color = TjProTheme.gold);
      canvas.drawCircle(
        c,
        7,
        Paint()
          ..color = Colors.black54
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
      canvas.drawCircle(c, 2.5, Paint()..color = Colors.black87);
    }
  }

  @override
  bool shouldRepaint(RampCurvePainter old) =>
      old.start != start || old.mid != mid || old.end != end;
}

/// §5A — the keyframe easing curve graph (the motion the overlay
/// will follow from the Start to the End keyframe).
class EasingCurvePainter extends CustomPainter {
  const EasingCurvePainter(this.easing);

  final KeyframeEasing easing;

  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    canvas.drawRect(
      Rect.fromLTWH(2, 2, size.width - 4, size.height - 4),
      axis..style = PaintingStyle.stroke,
    );
    final w = size.width - 8;
    final h = size.height - 8;
    Offset pt(double x, double y) => Offset(4 + x * w, 4 + (1 - y) * h);
    final path = Path()..moveTo(pt(0, 0).dx, pt(0, 0).dy);
    switch (easing) {
      case KeyframeEasing.linear:
        path.lineTo(pt(1, 1).dx, pt(1, 1).dy);
      case KeyframeEasing.easeIn:
        path.quadraticBezierTo(pt(0.6, 0).dx, pt(0.6, 0).dy, pt(1, 1).dx, pt(1, 1).dy);
      case KeyframeEasing.easeOut:
        path.quadraticBezierTo(pt(0.4, 1).dx, pt(0.4, 1).dy, pt(1, 1).dx, pt(1, 1).dy);
      case KeyframeEasing.easeInOut:
        path.cubicTo(
          pt(0.4, 0).dx, pt(0.4, 0).dy,
          pt(0.6, 1).dx, pt(0.6, 1).dy,
          pt(1, 1).dx, pt(1, 1).dy,
        );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = TjProTheme.gold
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(EasingCurvePainter old) => old.easing != easing;
}

/// One drill-down section of a panel body (v1.15.0 G2, Point
/// #29): the widgets that follow a [SectionTitle], up to the
/// next one. The title itself is NOT in [children] — it becomes
/// the section's chip in the rail.
class PanelSection {
  const PanelSection(this.title, this.children);
  final String title;
  final List<Widget> children;
}

/// Splits a flat panel body into its [SectionTitle] sections
/// (Point #29). A lone [PanelColumn] is unwrapped first. Content
/// before the first title forms a section titled 'Main'. Pure —
/// the tests pin the splitting.
List<PanelSection> splitPanelSections(List<Widget> children) {
  var list = children;
  if (list.length == 1 && list.single is PanelColumn) {
    list = (list.single as PanelColumn).children;
  }
  final sections = <PanelSection>[];
  var current = <Widget>[];
  var title = 'Main';
  var titled = false;
  void flush() {
    if (current.isEmpty) return;
    sections.add(PanelSection(title, List<Widget>.of(current)));
    current = <Widget>[];
  }

  for (final w in list) {
    if (w is SectionTitle) {
      flush();
      title = w.title;
      titled = true;
      continue;
    }
    current.add(w);
  }
  flush();
  if (!titled) {
    return [PanelSection('Main', list)];
  }
  return sections;
}

/// A sensible small icon for a section chip, from its title.
IconData panelSectionIcon(String title) {
  final t = title.toLowerCase();
  if (t.contains('mask')) return Icons.crop_square;
  if (t.contains('blend')) return Icons.contrast;
  if (t.contains('style') || t.contains('font')) return Icons.text_format;
  if (t.contains('position') || t.contains('jagah')) return Icons.open_with;
  if (t.contains('size') || t.contains('scale')) return Icons.aspect_ratio;
  if (t.contains('colour') || t.contains('color') || t.contains('rang')) {
    return Icons.palette;
  }
  if (t.contains('speed') || t.contains('raftaar')) return Icons.speed;
  if (t.contains('ramp')) return Icons.show_chart;
  if (t.contains('audio') || t.contains('music') || t.contains('awaz')) {
    return Icons.music_note;
  }
  if (t.contains('voice')) return Icons.record_voice_over;
  if (t.contains('waveform')) return Icons.graphic_eq;
  if (t.contains('cleanup') || t.contains('clean')) return Icons.cleaning_services;
  if (t.contains('caption')) return Icons.subtitles;
  if (t.contains('urdu')) return Icons.translate;
  if (t.contains('title') && !t.contains('subtitle')) return Icons.title;
  if (t.contains('preset')) return Icons.view_carousel;
  if (t.contains('marker')) return Icons.bookmark;
  if (t.contains('beat')) return Icons.music_note;
  if (t.contains('background') || t.contains('pas-e-manzar')) {
    return Icons.image;
  }
  if (t.contains('key')) return Icons.colorize;
  if (t.contains('trim')) return Icons.content_cut;
  if (t.contains('split')) return Icons.call_split;
  if (t.contains('range')) return Icons.swap_horiz;
  if (t.contains('timeline')) return Icons.timeline;
  if (t.contains('canvas')) return Icons.crop;
  if (t.contains('intro') || t.contains('outro')) return Icons.movie;
  if (t.contains('mode')) return Icons.tune;
  if (t.contains('volume')) return Icons.volume_up;
  if (t.contains('transition')) return Icons.animation;
  if (t.contains('transform')) return Icons.transform;
  if (t.contains('keyframe')) return Icons.diamond;
  if (t.contains('pip') || t.contains('overlay')) {
    return Icons.picture_in_picture_alt;
  }
  if (t.contains('text')) return Icons.text_fields;
  return Icons.tune;
}

/// Point #29 drill-down body (v1.15.0 G2): when a panel body has
/// two or more [SectionTitle] sections, the section names show
/// as chips in ONE line (the same icon-choice rail style as the
/// panel tabs) and only the chosen section's controls show
/// below — the user never scrolls through the whole panel to
/// reach a sub-tool. With fewer than two sections the body is
/// exactly the old [PanelColumn].
class PanelDrillDown extends StatefulWidget {
  final VideoEditorController host;
  final List<Widget> children;

  /// Embedded mode: the drill sits inside the panel zone's own
  /// scrolling ListView (a single-widget panel's build), so it
  /// must size to its content — rail + the chosen section in one
  /// plain column, the outer list scrolls. Standalone mode (the
  /// zone renders the drill directly in its Expanded) pins the
  /// rail and scrolls only the section body.
  final bool embedded;
  const PanelDrillDown(this.host,
      {super.key, required this.children, this.embedded = false});

  /// Whether [children] would drill (2+ sections).
  static bool appliesTo(List<Widget> children) =>
      splitPanelSections(children).length >= 2;

  @override
  State<PanelDrillDown> createState() => _PanelDrillDownState();
}

class _PanelDrillDownState extends State<PanelDrillDown> {
  int _sel = 0;

  @override
  Widget build(BuildContext context) {
    final sections = splitPanelSections(widget.children);
    if (sections.length < 2) {
      return PanelColumn(children: widget.children);
    }
    final sel = _sel.clamp(0, sections.length - 1);
    final rail = iconChoiceRail(widget.host, [
      for (var i = 0; i < sections.length; i++)
        KeyedSubtree(
          key: Key('panelSection-$i'),
          child: iconChoiceItem(
            widget.host,
            icon: panelSectionIcon(sections[i].title),
            label: sections[i].title,
            selected: i == sel,
            onTap: () => setState(() => _sel = i),
          ),
        ),
    ]);
    if (widget.embedded) {
      return Column(
        key: const Key('panelDrillDown'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          rail,
          const SizedBox(height: 4),
          ...sections[sel].children,
        ],
      );
    }
    return Column(
      key: const Key('panelDrillDown'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        rail,
        Expanded(
          child: ListView(
            key: Key('panelSectionBody-$sel'),
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
            children: sections[sel].children,
          ),
        ),
      ],
    );
  }
}

/// Panel build helper: drill when the body has 2+ sections,
/// the plain column otherwise. Used by the single-widget panels
/// (Split, Trim, Volume, …) whose build used to be a bare
/// [PanelColumn].
Widget panelDrillOrColumn(
        VideoEditorController host, List<Widget> children) =>
    PanelDrillDown.appliesTo(children)
        ? PanelDrillDown(host, embedded: true, children: children)
        : PanelColumn(children: children);
