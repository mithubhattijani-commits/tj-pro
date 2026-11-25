/// AdjustPanel of the Video Editor (Master Plan Phase 4 split).
///
/// Was part of the panels extension on the editor State; now a
/// real widget in its own file. All editor state is reached
/// through [VideoEditorController] — behaviour unchanged.
library;

import 'package:flutter/material.dart';
import '../../services/pro_editor.dart';
import '../adjust_looks.dart';
import '../video_editor_controller.dart';
import '../widgets/panel_controls.dart';

/// AdjustPanel.
class AdjustPanel extends StatelessWidget {
  final VideoEditorController host;
  const AdjustPanel(this.host, {super.key});

  /// v1.4.0 Colour › Adjust (brief: tabs Filters | Adjust — the
  /// tabs live in [_panelTabs]; here: the LUT rail, ONE circular
  /// icon row of adjust items, ONE shared slider, Reset + ✓ (the
  /// panel header's Done is the ✓). 'Auto adjust' is a toggle in
  /// the row (ffmpeg normalize at export). HSL is not offered:
  /// the bundled ffmpeg has no per-hue-range HSL filter, and a
  /// fake slider is worse than none (see _adjustExtraFilter).
  List<Widget> buildChildren(BuildContext context) {
    return [
      const Text('Adjust — ek waqt mein ek slider',
          style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('LUT look'),
      const SizedBox(height: 4),
      iconChoiceRail(host, [
        for (final e in proLuts)
          iconChoiceItem(host, 
            icon: (e['name'] ?? '').isEmpty
                ? Icons.block
                : Icons.photo_filter,
            label: (e['name'] ?? '').isEmpty ? 'None' : e['name']!,
            selected: host.proLut == (e['name'] ?? ''),
            onTap: () => host.update(() => host.proLut = e['name'] ?? ''),
          ),
      ]),
      const SizedBox(height: 8),
      iconChoiceRail(host, [
        iconChoiceItem(host, 
          icon: Icons.auto_fix_high,
          label: 'Auto adjust',
          selected: host.adjAuto,
          onTap: () => host.update(() => host.adjAuto = !host.adjAuto),
        ),
        for (final e in const [
          ('Brightness', Icons.brightness_6),
          ('Contrast', Icons.contrast),
          ('Saturation', Icons.palette),
          ('Brilliance', Icons.lightbulb_outline),
          ('Sharpen', Icons.details),
          ('Clarity', Icons.filter_drama_outlined),
          ('Highlights', Icons.light_mode),
          ('Shadows', Icons.dark_mode),
          ('Whites', Icons.wb_sunny),
          ('Blacks', Icons.nightlight_round),
          ('Temperature', Icons.thermostat),
          ('Tint', Icons.colorize),
          ('Vibrance', Icons.color_lens),
          ('Exposure', Icons.exposure),
          ('Hue', Icons.gradient),
          ('Fade', Icons.waves),
          ('Vignette', Icons.vignette),
          ('Grain', Icons.grain),
        ])
          iconChoiceItem(host, 
            icon: e.$2,
            label: e.$1,
            selected: host.gradeSlider == e.$1,
            onTap: () => host.update(() => host.gradeSlider = e.$1),
          ),
      ]),
      const SizedBox(height: 8),
      gradeSliderWidget(host),
      const SizedBox(height: 4),
      Row(
        children: [
          TextButton.icon(
            onPressed: host.resetGrade,
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Reset'),
          ),
          const Spacer(),
          const Text(
            'Har item per selected clip ke export par lagta hai.',
            style: TextStyle(color: Colors.grey, fontSize: 11),
          ),
        ],
      ),
      const Divider(height: 32),
      MyLooksSection(host),
    ];
  }
  @override
  Widget build(BuildContext context) => PanelColumn(children: buildChildren(context));
}

/// The My Looks name prompt. The TextEditingController lives
/// and dies with THIS State — disposing it from the caller right
/// after showDialog returns races the dialog's exit animation
/// (the field is still building while the route pops), which
/// the v1.13.0 widget test caught as "used after being
/// disposed". Owned here, disposal happens when the route is
/// fully gone.
class _MyLookNameDialog extends StatefulWidget {
  const _MyLookNameDialog();

  @override
  State<_MyLookNameDialog> createState() => _MyLookNameDialogState();
}

class _MyLookNameDialogState extends State<_MyLookNameDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Look save karein'),
      content: TextField(
        key: const Key('myLookNameField'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Look ka naam (misal: Wedding Warm)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('myLookSaveConfirm'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// My Looks (v1.13.0, G5): the Adjust panel's saved-presets
/// section. Save captures the panel's CURRENT settings under a
/// name; tapping a saved Look applies it in one tap; the trash
/// icon deletes it. Looks persist on-device across sessions
/// (see adjust_looks.dart) — this section only reads/writes the
/// store and the host's Adjust controls, nothing else.
class MyLooksSection extends StatefulWidget {
  final VideoEditorController host;
  const MyLooksSection(this.host, {super.key});

  @override
  State<MyLooksSection> createState() => _MyLooksSectionState();
}

class _MyLooksSectionState extends State<MyLooksSection> {
  List<AdjustLook> _looks = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final looks = await AdjustLooksStore.load();
    if (!mounted) return;
    setState(() {
      _looks = looks;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _MyLookNameDialog(),
    );
    if (name == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty || !mounted) return;
    final next = await AdjustLooksStore.add(
      captureAdjustLook(widget.host, trimmed),
    );
    if (!mounted) return;
    setState(() => _looks = next);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Look save ho gaya: $trimmed')),
    );
  }

  void _apply(AdjustLook look) {
    widget.host.update(() => applyAdjustLook(widget.host, look));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Look lag gaya: ${look.name}')),
    );
  }

  Future<void> _delete(AdjustLook look) async {
    final next = await AdjustLooksStore.remove(look.name);
    if (!mounted) return;
    setState(() => _looks = next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'My Looks',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TextButton.icon(
              key: const Key('myLookSaveButton'),
              onPressed: _save,
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: const Text('Save look'),
            ),
          ],
        ),
        if (_loaded && _looks.isEmpty)
          const Text(
            'Abhi koi saved look nahi — settings bana kar Save karein, '
            'phir wo har video par aik tap se lage ga.',
            style: TextStyle(color: Colors.grey, fontSize: 11),
          ),
        for (final look in _looks)
          Row(
            children: [
              Expanded(
                child: InkWell(
                  key: Key('myLookApply_${look.name}'),
                  onTap: () => _apply(look),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(look.name),
                  ),
                ),
              ),
              IconButton(
                key: Key('myLookDelete_${look.name}'),
                tooltip: 'Delete look',
                icon: const Icon(Icons.delete_outline, size: 19),
                onPressed: () => _delete(look),
              ),
            ],
          ),
      ],
    );
  }
}
