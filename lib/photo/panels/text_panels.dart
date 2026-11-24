/// Text panels of the Photo Editor (Master Plan Phase 7 split).
///
/// Was a method of `_PhotoEditorScreenState` in
/// photo_editor_screen.dart; now a real widget in its own file.
/// All editor state is reached through [PhotoEditorController] —
/// behaviour unchanged.
library;


import 'package:flutter/material.dart';

import '../photo_editor_controller.dart';
import '../photo_models.dart';
import '../../services/caption_styles.dart';
import '../../services/font_registry.dart';
import '../widgets/panel_helpers.dart';
import '../widgets/photo_widgets.dart';

class TextZone extends StatelessWidget {
  final PhotoEditorController host;
  const TextZone(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Above-bar toolbar: keyboard, STYLE, COLOUR, Aa FONT,
        // alignment, ✓ (requirements #2).
        Row(
          children: [
            IconButton(
              tooltip: 'Keyboard',
              onPressed: () {
                host.update(() => host.textTab = 'type');
                host.textFocus.requestFocus();
              },
              icon: Icon(
                Icons.keyboard,
                color: host.textTab == 'type' ? kPhotoAccentLight : Colors.white,
              ),
            ),
            // Flexible (v1.5.2, #69 sweep): this toolbar Row
            // overflowed narrow screens — the STYLE button
            // shrinks/ellipsizes first.
            Flexible(
              child: TextButton(
                onPressed: () => host.update(() => host.textTab = 'style'),
                child: Text(
                  'STYLE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: host.textTab == 'style' ? kPhotoAccentLight : Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Colour',
              onPressed: () => host.update(() => host.textTab = 'colour'),
              icon: Icon(
                Icons.color_lens,
                color: host.textTab == 'colour' ? kPhotoAccentLight : Colors.white,
              ),
            ),
            TextButton(
              onPressed: () => host.update(() => host.textTab = 'font'),
              child: Text(
                'Aa',
                style: TextStyle(
                  color: host.textTab == 'font' ? kPhotoAccentLight : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Alignment',
              onPressed: () {
                host.update(() {
                  host.textAlign = host.textAlign == TextAlign.left
                      ? TextAlign.center
                      : host.textAlign == TextAlign.center
                      ? TextAlign.right
                      : TextAlign.left;
                });
                host.saveActiveLayer();
              },
              icon: Icon(
                host.textAlign == TextAlign.left
                    ? Icons.format_align_left
                    : host.textAlign == TextAlign.right
                    ? Icons.format_align_right
                    : Icons.format_align_center,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Confirm',
              onPressed: host.closePanel,
              icon: const Icon(Icons.check, color: kPhotoAccentLight),
            ),
          ],
        ),
        Expanded(
          child: switch (host.textTab) {
            'style' => TextStylePanel(host),
            'colour' => TextColourPanel(host),
            'font' => TextFontPanel(host),
            _ => TextTypePanel(host),
          },
        ),
      ],
    );
  }
}

class TextTypePanel extends StatelessWidget {
  final PhotoEditorController host;
  const TextTypePanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    // v1.5.1 (#53): the Type tab's rows (field + Text size + Bold/
    // Italic/Copy + Letter spacing + Line spacing) are ~40px taller
    // than the fixed 272px text zone leaves under the tab header —
    // as a bare Column they painted "BOTTOM OVERFLOWED BY 40
    // PIXELS". Scroll inside the zone instead, the same pattern the
    // Colour tab already uses; no control removed or reordered.
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Layer chips: tap to select the layer being edited.
          if (host.layers.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < host.layers.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text('Text ${i + 1}'),
                        selected: host.activeLayer == i,
                        onSelected: (_) => host.update(() {
                          host.saveActiveLayer();
                          host.loadLayer(i);
                        }),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          // Bottom typing bar — every letter updates the canvas LIVE.
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: host.textCtrl,
                  focusNode: host.textFocus,
                  decoration: const InputDecoration(
                    hintText: 'Yahan likhein — canvas par live ayega',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) {
                    host.update(() => host.text = v);
                    host.saveActiveLayer();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Add text layer',
                onPressed: host.addTextLayer,
                icon: const Icon(Icons.add_circle, color: kPhotoAccentLight),
              ),
              IconButton(
                tooltip: 'Delete this text',
                onPressed: host.activeLayer < 0 ? null : host.deleteActiveLayer,
                icon: const Icon(Icons.delete, color: Colors.redAccent),
              ),
            ],
          ),
          const SizedBox(height: 6),
          PhotoSliderRow(
            label: 'Text size',
            value: host.textSize,
            min: 20,
            max: 110,
            onChanged: (v) {
              host.update(() => host.textSize = v);
              host.saveActiveLayer();
            },
          ),
          Row(
            children: [
              host.photoIconChoiceItem(
                icon: Icons.format_bold,
                label: 'Bold',
                selected: host.textBold,
                onTap: () {
                  host.update(() => host.textBold = !host.textBold);
                  host.saveActiveLayer();
                },
              ),
              host.photoIconChoiceItem(
                icon: Icons.format_italic,
                label: 'Italic',
                selected: host.textItalic,
                onTap: () {
                  host.update(() => host.textItalic = !host.textItalic);
                  host.saveActiveLayer();
                },
              ),
              host.photoIconChoiceItem(
                icon: Icons.copy,
                label: 'Copy',
                selected: false,
                onTap: host.activeLayer < 0 ? null : host.duplicateActiveLayer,
              ),
            ],
          ),
          PhotoSliderRow(
            label: 'Letter spacing',
            value: host.textLetterSpacing,
            min: -2,
            max: 10,
            onChanged: (v) {
              host.update(() => host.textLetterSpacing = v);
              host.saveActiveLayer();
            },
          ),
          PhotoSliderRow(
            label: 'Line spacing',
            value: host.textLineSpacing,
            min: 0.8,
            max: 2.0,
            onChanged: (v) {
              host.update(() => host.textLineSpacing = v);
              host.saveActiveLayer();
            },
          ),
        ],
      ),
    );
  }
}

class TextStylePanel extends StatelessWidget {
  final PhotoEditorController host;
  const TextStylePanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    final sample = host.styleSample;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final t in const ['SPECIAL', 'CAPTIONS', 'LABEL', 'TITLE'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(t),
                    selected: host.styleTab == t,
                    onSelected: (_) => host.update(() => host.styleTab = t),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.5,
            children: switch (host.styleTab) {
              'CAPTIONS' => [
                for (final s in StudioCaptionStyles.all)
                  host.styleTile(
                    label: s.nameEn,
                    preview: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: s.backgroundColor != 0
                            ? Color(s.backgroundColor)
                            : null,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        sample,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: host.applyFontKey(
                          s.fontId ?? 'default',
                          TextStyle(
                            color: Color(s.textColor),
                            fontSize: 13,
                            fontWeight: s.bold
                                ? FontWeight.bold
                                : FontWeight.normal,
                            shadows: s.shadow
                                ? const [
                                    Shadow(color: Colors.black, blurRadius: 4),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                    onTap: () => host.applyStudioStyle(s),
                  ),
              ],
              'LABEL' => [
                for (final s in StudioCaptionStyles.all.where(
                  (s) => s.backgroundColor != 0 || s.highlightBg != 0,
                ))
                  host.styleTile(
                    label: s.nameEn,
                    preview: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Color(
                          s.backgroundColor != 0
                              ? s.backgroundColor
                              : s.highlightBg,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        sample,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    onTap: () => host.applyStudioStyle(s, label: true),
                  ),
                for (final v in const [
                  ('Message bubble', 0xFF37474F, 0xFFFFFFFF),
                  ('Sticky note', 0xFFFFF176, 0xFF000000),
                  ('Brush note', 0xFFFF7043, 0xFFFFFFFF),
                  ('Paper tape', 0xFFECEFF1, 0xFF000000),
                  ('Pixel bubble', 0xFF3D5AFE, 0xFFFFFFFF),
                ])
                  host.styleTile(
                    label: v.$1,
                    preview: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Color(v.$2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        sample,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(v.$3),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    onTap: () => host.update(() {
                      host.textBg = true;
                      host.textBgColor = Color(v.$2);
                      host.textColor = Color(v.$3);
                      host.textBold = true;
                      host.saveActiveLayer();
                    }),
                  ),
              ],
              'TITLE' => [
                for (final s in StudioCaptionStyles.all.where(
                  (s) => const {
                    'bold_pop',
                    'one_word',
                    'spotlight',
                    'urdu_gulzar_headline',
                    'pop_up',
                  }.contains(s.id),
                ))
                  host.styleTile(
                    label: s.nameEn,
                    preview: Text(
                      sample,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: host.applyFontKey(
                        s.fontId ?? 'default',
                        TextStyle(
                          color: Color(s.highlightColor),
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    onTap: () => host.applyStudioStyle(s),
                  ),
              ],
              _ => [
                for (final t in const [
                  ('classic', 'Classic'),
                  ('neon', 'Neon Lights'),
                  ('breaking', 'Breaking'),
                  ('elegant', 'Elegant'),
                  ('urdu', 'Urdu Gold'),
                  ('script', 'Script Glow'),
                ])
                  host.styleTile(
                    label: t.$2,
                    preview: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: t.$1 == 'breaking' ? Colors.red : null,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        sample,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: host.templatePreviewStyle(t.$1),
                      ),
                    ),
                    onTap: () => host.applyTextTemplate(t.$1),
                  ),
              ],
            },
          ),
        ),
      ],
    );
  }
}

class TextColourPanel extends StatelessWidget {
  final PhotoEditorController host;
  const TextColourPanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final t in const [
                'TEXT',
                'BORDER',
                'SHADOW',
                'GLOW',
                'LABEL',
                'OPACITY',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(t),
                    selected: host.colourTab == t,
                    onSelected: (_) => host.update(() => host.colourTab = t),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: switch (host.colourTab) {
              'BORDER' => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Outline'),
                      const Spacer(),
                      Switch(
                        value: host.textOutline,
                        onChanged: (v) {
                          host.update(() => host.textOutline = v);
                          host.saveActiveLayer();
                        },
                      ),
                    ],
                  ),
                  host.swatchRow(
                    value: host.textOutlineColor,
                    onChanged: (c) {
                      host.update(() {
                        host.textOutlineColor = c;
                        host.textOutline = true;
                      });
                      host.saveActiveLayer();
                    },
                  ),
                  PhotoSliderRow(
                    label: 'Width',
                    value: host.textOutlineWidth,
                    min: 1,
                    max: 8,
                    onChanged: (v) {
                      host.update(() => host.textOutlineWidth = v);
                      host.saveActiveLayer();
                    },
                  ),
                ],
              ),
              'SHADOW' => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Shadow'),
                      const Spacer(),
                      Switch(
                        value: host.textShadow,
                        onChanged: (v) {
                          host.update(() => host.textShadow = v);
                          host.saveActiveLayer();
                        },
                      ),
                    ],
                  ),
                  host.swatchRow(
                    value: host.textShadowColor,
                    onChanged: (c) {
                      host.update(() {
                        host.textShadowColor = c;
                        host.textShadow = true;
                      });
                      host.saveActiveLayer();
                    },
                  ),
                  PhotoSliderRow(
                    label: 'X offset',
                    value: host.shadowDx,
                    min: -20,
                    max: 20,
                    onChanged: (v) {
                      host.update(() => host.shadowDx = v);
                      host.saveActiveLayer();
                    },
                  ),
                  PhotoSliderRow(
                    label: 'Y offset',
                    value: host.shadowDy,
                    min: -20,
                    max: 20,
                    onChanged: (v) {
                      host.update(() => host.shadowDy = v);
                      host.saveActiveLayer();
                    },
                  ),
                  PhotoSliderRow(
                    label: 'Blur',
                    value: host.shadowBlur,
                    min: 0,
                    max: 30,
                    onChanged: (v) {
                      host.update(() => host.shadowBlur = v);
                      host.saveActiveLayer();
                    },
                  ),
                  PhotoSliderRow(
                    label: 'Opacity %',
                    value: host.shadowOpacity * 100,
                    min: 0,
                    max: 100,
                    onChanged: (v) {
                      host.update(() => host.shadowOpacity = v / 100);
                      host.saveActiveLayer();
                    },
                  ),
                ],
              ),
              'GLOW' => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Glow'),
                      const Spacer(),
                      Switch(
                        value: host.textGlow,
                        onChanged: (v) {
                          host.update(() => host.textGlow = v);
                          host.saveActiveLayer();
                        },
                      ),
                    ],
                  ),
                  host.swatchRow(
                    value: host.textGlowColor,
                    onChanged: (c) {
                      host.update(() {
                        host.textGlowColor = c;
                        host.textGlow = true;
                      });
                      host.saveActiveLayer();
                    },
                  ),
                  PhotoSliderRow(
                    label: 'Intensity',
                    value: host.glowBlur,
                    min: 4,
                    max: 40,
                    onChanged: (v) {
                      host.update(() => host.glowBlur = v);
                      host.saveActiveLayer();
                    },
                  ),
                ],
              ),
              'LABEL' => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  host.photoIconChoiceRail([
                    host.photoIconChoiceItem(
                      icon: Icons.block,
                      label: 'None',
                      selected: !host.textBg,
                      onTap: () {
                        host.update(() => host.textBg = false);
                        host.saveActiveLayer();
                      },
                    ),
                    host.photoIconChoiceItem(
                      icon: Icons.bookmark,
                      label: 'Ribbon',
                      selected: host.textBg,
                      onTap: () {
                        host.update(() => host.textBg = true);
                        host.saveActiveLayer();
                      },
                    ),
                  ]),
                  const SizedBox(height: 8),
                  host.swatchRow(
                    value: host.textBgColor,
                    onChanged: (c) {
                      host.update(() {
                        host.textBgColor = c;
                        host.textBg = true;
                      });
                      host.saveActiveLayer();
                    },
                  ),
                ],
              ),
              'OPACITY' => PhotoSliderRow(
                label: 'Opacity %',
                value: host.textOpacity * 100,
                min: 0,
                max: 100,
                onChanged: (v) {
                  host.update(() => host.textOpacity = v / 100);
                  host.saveActiveLayer();
                },
              ),
              _ => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  host.swatchRow(
                    value: host.textColor,
                    onChanged: (c) {
                      host.update(() => host.textColor = c);
                      host.saveActiveLayer();
                    },
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Custom rang (rainbow):',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Slider(
                    value: HSVColor.fromColor(host.textColor).hue,
                    min: 0,
                    max: 360,
                    onChanged: (v) {
                      host.update(() {
                        host.textColor = HSVColor.fromAHSV(1, v, 0.85, 1).toColor();
                      });
                      host.saveActiveLayer();
                    },
                  ),
                ],
              ),
            },
          ),
        ),
      ],
    );
  }
}

/// Font panel (Aa): a VERTICAL list — every font name rendered
/// IN its own typeface (font_registry + the Latin google_fonts).
class TextFontPanel extends StatelessWidget {
  final PhotoEditorController host;
  const TextFontPanel(this.host, {super.key});

  @override
  Widget build(BuildContext context) {
    final entries = <(String, String)>[
      ('default', 'Default'),
      ('roboto', 'Roboto'),
      ('merriweather', 'Merriweather'),
      ('dancing', 'Dancing Script'),
      ('bebas', 'Bebas Neue'),
      ('pacifico', 'Pacifico'),
      ('kufi', 'Noto Kufi Arabic'),
      for (final f in UrduFonts.all) (f.id, f.name),
    ];
    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (ctx, i) {
        final e = entries[i];
        final selected = host.textFont == e.$1;
        return ListTile(
          dense: true,
          title: Text(
            e.$2,
            style: host.applyFontKey(
              e.$1,
              TextStyle(
                fontSize: 18,
                color: selected ? kPhotoAccentLight : Colors.white,
              ),
            ),
          ),
          trailing: selected
              ? const Icon(Icons.check, color: kPhotoAccentLight)
              : null,
          onTap: () {
            host.update(() => host.textFont = e.$1);
            host.saveActiveLayer();
          },
        );
      },
    );
  }
}

