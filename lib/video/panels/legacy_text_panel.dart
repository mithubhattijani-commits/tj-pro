/// LegacyTextPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController].
library;

import 'package:flutter/material.dart';
import '../../services/font_registry.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// The Video Editor's Text overlay panel.
///
/// v1.17.0 (G3, Point #34b — ROOT CAUSE): until this build this
/// panel was a SectionTitle + ONE bare TextField, and NO font /
/// size / colour / background state existed for the overlay
/// anywhere in the editor — the rich text system the user
/// remembered lives in the Photo Editor and was never wired
/// here. The state now exists on the controller
/// (textFontId / textSizeScale / textColorArgb / textBgPill),
/// the stage renders it (with pinch-to-resize), and the export
/// drawtext honours size / colour / background box. Font
/// honesty: the Kasheeda house font also exports exactly (its
/// TTF is resolved at export); the other registry fonts style
/// the preview, while the export falls back to the system font
/// — google_fonts downloads have no stable file path drawtext
/// could use, and faking it would be worse.
class LegacyTextPanel extends StatefulWidget {
  final VideoEditorController host;
  const LegacyTextPanel(this.host, {super.key});

  @override
  State<LegacyTextPanel> createState() => _LegacyTextPanelState();
}

class _LegacyTextPanelState extends State<LegacyTextPanel> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.host.text,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  VideoEditorController get host => widget.host;

  List<Widget> buildChildren(BuildContext context) {
    return [
      SectionTitle('Text overlay'),
      const SizedBox(height: 8),
      // Text overlay
      TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: 'Text overlay (single line)',
          border: OutlineInputBorder(),
        ),
        onChanged: (v) => host.update(() => host.text = v),
      ),
      const SizedBox(height: 12),
      SectionTitle('Font'),
      const SizedBox(height: 6),
      iconChoiceRail(host, [
        iconChoiceItem(
          host,
          icon: Icons.font_download_outlined,
          label: 'Default',
          selected: host.textFontId.isEmpty,
          onTap: () => host.update(() => host.textFontId = ''),
        ),
        for (final f in UrduFonts.all)
          iconChoiceItem(
            host,
            icon: Icons.text_fields,
            label: f.name,
            selected: host.textFontId == f.id,
            onTap: () => host.update(() => host.textFontId = f.id),
          ),
      ]),
      const SizedBox(height: 4),
      const Text(
        'The Kasheeda font also exports exactly; other fonts '
        'style the preview (the export then uses the system '
        'font).',
        style: TextStyle(color: Colors.grey, fontSize: 11.5),
      ),
      const SizedBox(height: 12),
      SectionTitle('Size'),
      ProSlider(
        label: 'Size',
        value: host.textSizeScale,
        min: 0.4,
        max: 3.0,
        divisions: 26,
        digits: 2,
        onChanged: (v) => host.update(() => host.textSizeScale = v),
      ),
      const Text(
        'Tip: you can also pinch the text on the preview to '
        'resize it.',
        style: TextStyle(color: Colors.grey, fontSize: 11.5),
      ),
      const SizedBox(height: 12),
      SectionTitle('Colour'),
      const SizedBox(height: 6),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final argb in const [
            0xFFFFFFFF,
            0xFF000000,
            0xFFFFD740,
            0xFFFF5252,
            0xFF69F0AE,
            0xFF40C4FF,
            0xFFFFAB40,
            0xFFFF80AB,
          ])
            GestureDetector(
              onTap: () => host.update(() => host.textColorArgb = argb),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Color(argb),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: host.textColorArgb == argb
                        ? Colors.amber
                        : Colors.white38,
                    width: host.textColorArgb == argb ? 2.5 : 1,
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      SectionTitle('Background'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Background pill'),
        subtitle: const Text(
          'A dark box behind the text — on the preview and in '
          'the export.',
          style: TextStyle(fontSize: 11.5),
        ),
        value: host.textBgPill,
        onChanged: (v) => host.update(() => host.textBgPill = v),
      ),
      const Divider(height: 32),
    ];
  }

  @override
  Widget build(BuildContext context) =>
      PanelColumn(children: buildChildren(context));
}
