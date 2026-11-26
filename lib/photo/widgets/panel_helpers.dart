/// Photo Editor shared panel helpers (Master Plan Phase 7
/// split): the small builders several panels share — panel
/// header, choice rails, action buttons, swatch rows, look
/// thumbnails, the HSL/curve sub-editors and the text-layer
/// helpers. Was a set of methods on `_PhotoEditorScreenState`;
/// now an extension on [PhotoEditorController], so every panel
/// reaches them (and the editor state behind them) through the
/// one contract — behaviour unchanged.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../photo_editor_controller.dart';
import '../photo_models.dart';
import '../../services/font_registry.dart';
import '../../widgets/tool_guide.dart';
import 'photo_widgets.dart';

const _ratioTiles = <(String, int, int)>[
  ('Original', 0, 0),
  ('1:1', 1, 1),
  ('4:5', 4, 5),
  ('9:16', 9, 16),
  ('16:9', 16, 9),
  ('Wallpaper', 9, 19),
  ('3:4', 3, 4),
  ('4:3', 4, 3),
  ('2:3', 2, 3),
  ('3:2', 3, 2),
  ('2.35:1', 47, 20),
  ('2:1', 2, 1),
  ('1:2', 1, 2),
];

extension PhotoPanelHelpers on PhotoEditorController {

  /// One icon+label choice item inside a panel — the global UI
  /// rule: every choice is an icon above a label in a horizontal
  /// swipeable row, never bare text.
  Widget photoIconChoiceItem({
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
              color: selected ? kPhotoAccent : const Color(0xFF232323),
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

  Widget photoIconChoiceRail(List<Widget> items) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: items),
    );
  }

  /// Panel header: tool name + hold-to-compare chip + ✓ top-right
  /// to confirm/close (universal panel behaviour, requirements #2).
  /// v1.5.0 (#4): the compare chip moved here from its floating
  /// pill on the preview — same press-and-hold behaviour, no
  /// preview clutter.
  Widget photoPanelHeader(String toolKey) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              photoToolDisplayName(toolKey),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Point #21: har tool ki Guide, isi header mein.
          ToolGuideButton(guideId: 'pe.$toolKey', compact: true),
          GestureDetector(
            onTapDown: (_) => update(() => comparing = true),
            onTapUp: (_) => update(() => comparing = false),
            onTapCancel: () => update(() => comparing = false),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: comparing ? kPhotoAccent : Colors.white12,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.compare, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Compare (hold)',
                    style: TextStyle(color: Colors.white, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Confirm',
            onPressed: closePanel,
            icon: const Icon(Icons.check, color: kPhotoAccentLight),
          ),
        ],
      ),
    );
  }

  String photoToolDisplayName(String key) {
    const names = <String, String>{
      'canvas': 'Canvas',
      'filter': 'Filter',
      'adjust': 'Adjust',
      'effect': 'Effect',
      'background': 'Background',
      'portrait': 'Portrait',
      'sticker': 'Sticker',
      'text': 'Text',
      'pip': 'PIP',
      'remove': 'Remove',
      'enhance': 'Enhance',
      'cutout': 'Cutout',
      'doodle': 'Doodle',
      'makeup': 'Makeup',
      'crop': 'Crop',
      'expand': 'Expand',
      'frame': 'Frame',
      'rotate': 'Rotate',
    };
    return names[key] ?? key;
  }

  /// One AI action with its Premium badge ON the button (P3).
  Widget aiAction({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flexible (v1.5.2, #69 sweep): two AI buttons side by
          // side on a narrow screen overflowed the label Row —
          // the text ellipsizes instead.
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: kPhotoAccent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Premium',
              style: TextStyle(color: Colors.white, fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  Widget plainAction({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }

  /// Colour swatch row bound to a colour value.
  Widget swatchRow({
    required Color value,
    required ValueChanged<Color> onChanged,
    List<Color> colors = kPhotoPalette,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: colors.map((c) {
          final selected = value.toARGB32() == c.toARGB32();
          return GestureDetector(
            onTap: () => onChanged(c),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? kPhotoAccentLight : Colors.grey,
                  width: selected ? 3 : 1,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// One filter/LUT thumbnail tile: the look rendered on the
  /// user's own photo, with a violet selected ring.
  Widget lookThumb({
    required String label,
    required bool selected,
    required Uint8List? thumb,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? kPhotoAccent : Colors.white24,
                  width: selected ? 3 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: thumb != null
                    ? Image.memory(thumb, fit: BoxFit.cover)
                    : Container(
                        color: const Color(0xFF2A2A2A),
                        child: const Icon(Icons.image, color: Colors.grey),
                      ),
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 66,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? kPhotoAccentLight : Colors.white70,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Single H/S/L slider row for the HSL editor.
  Widget hslSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              value.toStringAsFixed(1),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget ratioRail({
    required (String, int, int) selected,
    required ValueChanged<(String, int, int)> onSelect,
    bool includeOriginal = true,
  }) {
    return photoIconChoiceRail([
      for (final r in _ratioTiles)
        if (includeOriginal || r.$2 != 0)
          photoIconChoiceItem(
            icon: r.$2 == 0
                ? Icons.crop_original
                : r.$2 > r.$3
                ? Icons.crop_landscape
                : r.$2 == r.$3
                ? Icons.crop_square
                : Icons.crop_portrait,
            label: r.$1,
            selected: selected.$1 == r.$1,
            onTap: () => onSelect(r),
          ),
    ]);
  }

  double adjValue(String key) {
    switch (key) {
      case 'lightness':
        return brightness;
      case 'exposure':
        return exposure;
      case 'contrast':
        return (contrast - 1) * 100;
      case 'warmth':
        return temperature;
      case 'tint':
        return tint;
      case 'saturation':
        return (saturation - 1) * 100;
      case 'fade':
        return fade;
      case 'highlight':
        return highlights;
      case 'shadow':
        return shadows;
      case 'color':
        return vibrance;
      case 'hue':
        return hueShift;
      case 'vignette':
        return vignette;
      case 'sharpen':
        return sharpenDetail;
      case 'grain':
        return grain;
      default:
        return 0;
    }
  }

  void adjSet(String key, double v) {
    switch (key) {
      case 'lightness':
        brightness = v;
      case 'exposure':
        exposure = v;
      case 'contrast':
        contrast = 1 + v / 100;
      case 'warmth':
        temperature = v;
      case 'tint':
        tint = v;
      case 'saturation':
        saturation = 1 + v / 100;
      case 'fade':
        fade = v;
      case 'highlight':
        highlights = v;
      case 'shadow':
        shadows = v;
      case 'color':
        vibrance = v;
      case 'hue':
        hueShift = v;
      case 'vignette':
        vignette = v;
      case 'sharpen':
        sharpenDetail = v;
      case 'grain':
        grain = v;
    }
    schedulePixelPreview();
  }

  (double, double) adjRange(String key) {
    switch (key) {
      case 'fade':
      case 'vignette':
      case 'sharpen':
      case 'grain':
        return (0, 100);
      case 'hue':
        return (-180, 180);
      default:
        return (-100, 100);
    }
  }

  /// Channel curve editor: tap/drag on the graph moves the nearest
  /// control point (or adds one); channels RGB / R / G / B.
  Widget curveEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        photoIconChoiceRail([
          for (final ch in const [
            ('rgb', 'RGB', Icons.show_chart, Colors.white),
            ('r', 'Red', Icons.circle, Colors.red),
            ('g', 'Green', Icons.circle, Colors.green),
            ('b', 'Blue', Icons.circle, Colors.blue),
          ])
            photoIconChoiceItem(
              icon: ch.$3,
              iconColor: ch.$4,
              label: ch.$2,
              selected: curveChannel == ch.$1,
              onTap: () => update(() => curveChannel = ch.$1),
            ),
          photoIconChoiceItem(
            icon: Icons.restart_alt,
            label: 'Reset',
            selected: false,
            onTap: () {
              update(() {
                curvePoints[curveChannel] = [
                  const Offset(0, 0),
                  const Offset(1, 1),
                ];
              });
              schedulePixelPreview();
            },
          ),
        ]),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (ctx, cons) {
            final side = math.min(cons.maxWidth, 190.0);
            return Center(
              child: GestureDetector(
                onPanStart: (d) => curveTouch(d.localPosition, side),
                onPanUpdate: (d) => curveTouch(d.localPosition, side),
                child: CustomPaint(
                  size: Size(side, side),
                  painter: PhotoCurvePainter(
                    points: curvePoints[curveChannel]!,
                    channel: curveChannel,
                  ),
                ),
              ),
            );
          },
        ),
        const Text(
          'Drag on the graph to shape the curve — the preview is live.',
          style: TextStyle(color: Colors.grey, fontSize: 11),
        ),
      ],
    );
  }

  void curveTouch(Offset local, double side) {
    final nx = (local.dx / side).clamp(0.0, 1.0);
    final ny = (1 - local.dy / side).clamp(0.0, 1.0);
    update(() {
      final pts = curvePoints[curveChannel]!;
      // Move the nearest interior point; endpoints only move in Y.
      var best = -1;
      var bestDist = 0.14;
      for (var i = 0; i < pts.length; i++) {
        final d = (pts[i] - Offset(nx, ny)).distance;
        if (d < bestDist) {
          bestDist = d;
          best = i;
        }
      }
      if (best < 0) {
        pts.add(Offset(nx, ny));
      } else if (best == 0) {
        pts[0] = Offset(0, ny);
      } else if (best == pts.length - 1) {
        pts[pts.length - 1] = Offset(1, ny);
      } else {
        pts[best] = Offset(nx, ny);
      }
      pts.sort((a, b) => a.dx.compareTo(b.dx));
    });
    schedulePixelPreview();
  }

  /// The HSL editor (8 colours × H/S/L) — the pre-v1.4.0 panel,
  /// re-homed inside Adjust (and still fully live + Apply).
  Widget hslEditor() {
    final file = workingFile;
    const colorNames = <String>[
      'Red',
      'Orange',
      'Yellow',
      'Green',
      'Cyan',
      'Blue',
      'Purple',
      'Magenta',
    ];
    const colorDots = <Color>[
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.cyan,
      Colors.blue,
      Colors.purple,
      Colors.pink,
    ];
    final adj = hslAdjustments[hslSelectedColor];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('HSL', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton(onPressed: resetHSL, child: const Text('Reset')),
          ],
        ),
        photoIconChoiceRail([
          for (var i = 0; i < 8; i++)
            photoIconChoiceItem(
              icon: Icons.circle,
              iconColor: colorDots[i],
              label: colorNames[i],
              selected: hslSelectedColor == i,
              onTap: () => update(() => hslSelectedColor = i),
            ),
        ]),
        hslSlider(
          label: 'Hue',
          value: adj[0],
          min: -180,
          max: 180,
          onChanged: (v) {
            update(() => hslAdjustments[hslSelectedColor][0] = v);
            schedulePixelPreview();
          },
        ),
        hslSlider(
          label: 'Saturation',
          value: adj[1],
          min: 0,
          max: 2,
          onChanged: (v) {
            update(() => hslAdjustments[hslSelectedColor][1] = v);
            schedulePixelPreview();
          },
        ),
        hslSlider(
          label: 'Lightness',
          value: adj[2],
          min: -100,
          max: 100,
          onChanged: (v) {
            update(() => hslAdjustments[hslSelectedColor][2] = v);
            schedulePixelPreview();
          },
        ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: file == null || busy ? null : applyHSL,
            icon: const Icon(Icons.check),
            label: const Text('Apply HSL'),
          ),
        ),
      ],
    );
  }

  Widget styleTile({
    required String label,
    required Widget preview,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF232323),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            Expanded(child: Center(child: preview)),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  String get styleSample => text.isEmpty
      ? 'Nigraan TV'
      : (text.length > 16 ? text.substring(0, 16) : text);

  Future<void> layerMenu(int index) async {
    final action = await showMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(100, 200, 100, 200),
      items: const [
        PopupMenuItem(value: 'copy', child: Text('Copy')),
        PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (action == null) return;
    update(() {
      saveActiveLayer();
      loadLayer(index);
    });
    if (action == 'copy') {
      duplicateActiveLayer();
    } else if (action == 'delete') {
      deleteActiveLayer();
    } else if (action == 'edit') {
      update(() => textTab = 'type');
      textFocus.requestFocus();
    }
  }

  TextStyle layerStyle(TextLayerData layer, double fontPx, double s) {
    final shadows = <Shadow>[];
    if (layer.glow) {
      shadows.add(
        Shadow(
          color: Color(layer.glowArgb).withValues(alpha: 0.9),
          blurRadius: layer.glowBlur * s,
        ),
      );
    }
    if (layer.shadow) {
      shadows.add(
        Shadow(
          color: Color(layer.shadowArgb),
          offset: Offset(layer.shadowDx * s, layer.shadowDy * s),
          blurRadius: layer.shadowBlur * s,
        ),
      );
    }
    final base = TextStyle(
      color: Color(layer.colorArgb).withValues(alpha: layer.opacity),
      fontSize: fontPx,
      height: layer.lineSpacing,
      fontWeight: layer.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: layer.italic ? FontStyle.italic : FontStyle.normal,
      letterSpacing: layer.letterSpacing * s,
      shadows: shadows,
    );
    return applyFontKey(layer.font, base);
  }

  Widget overlayControls() {
    if (activeOverlay < 0 || activeOverlay >= overlays.length) {
      return const Text(
        'Select an overlay — drag on the preview to set the position '
        'badlein.',
        style: TextStyle(color: Colors.grey, fontSize: 12),
      );
    }
    final o = overlays[activeOverlay];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PhotoSliderRow(
          label: 'Size',
          value: o.scaleFrac * 100,
          min: 8,
          max: 120,
          onChanged: (v) => update(() => o.scaleFrac = v / 100),
        ),
        PhotoSliderRow(
          label: 'Rotate',
          value: o.rotation,
          min: -180,
          max: 180,
          onChanged: (v) => update(() => o.rotation = v),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => update(() {
              overlays.removeAt(activeOverlay);
              activeOverlay = -1;
            }),
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            label: const Text('Delete overlay'),
          ),
        ),
      ],
    );
  }

  TextStyle templatePreviewStyle(String key) {
    switch (key) {
      case 'neon':
        return applyFontKey(
          'bebas',
          const TextStyle(
            color: Colors.cyanAccent,
            fontSize: 17,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.cyan, blurRadius: 12)],
          ),
        );
      case 'breaking':
        return applyFontKey(
          'roboto',
          const TextStyle(
            color: Colors.yellow,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        );
      case 'elegant':
        return applyFontKey(
          'merriweather',
          const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontStyle: FontStyle.italic,
          ),
        );
      case 'urdu':
        return applyFontKey(
          'noto_nastaliq_urdu',
          const TextStyle(color: Color(0xFFFFD54F), fontSize: 15),
        );
      case 'script':
        return applyFontKey(
          'dancing',
          const TextStyle(
            color: Colors.pinkAccent,
            fontSize: 17,
            shadows: [Shadow(color: Colors.pink, blurRadius: 10)],
          ),
        );
      default: // classic
        return const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
        );
    }
  }

  Offset toPreviewLocal(Offset global) {
    final rb = previewKey2.currentContext?.findRenderObject();
    if (rb is RenderBox) return rb.globalToLocal(global);
    return Offset.zero;
  }

  /// Apply a font key to a base style: font_registry entries render
  /// through their own apply(); the Latin/legacy keys go through
  /// google_fonts getters (the pre-v1.4.0 behaviour).
  TextStyle applyFontKey(String key, TextStyle base) {
    if (UrduFonts.all.any((f) => f.id == key)) {
      return UrduFonts.byId(key).apply(base);
    }
    try {
      switch (key) {
        case 'nastaliq':
          return GoogleFonts.notoNastaliqUrdu(textStyle: base);
        case 'naskh':
          return GoogleFonts.notoNaskhArabic(textStyle: base);
        case 'kufi':
          return GoogleFonts.notoKufiArabic(textStyle: base);
        case 'gulzar':
          return GoogleFonts.gulzar(textStyle: base);
        case 'roboto':
          return GoogleFonts.roboto(textStyle: base);
        case 'merriweather':
          return GoogleFonts.merriweather(textStyle: base);
        case 'dancing':
          return GoogleFonts.dancingScript(textStyle: base);
        case 'bebas':
          return GoogleFonts.bebasNeue(textStyle: base);
        case 'pacifico':
          return GoogleFonts.pacifico(textStyle: base);
        default:
          return base;
      }
    } catch (_) {
      return base; // offline or font not cached yet
    }
  }

}
