/// Channel Branding screen (Phase 8, master prompt §9).
///
/// The dedicated branding section: channel name, logo replace,
/// brand colour, ribbon colours, social handles, watermark
/// (toggle / position / size) and intro/outro defaults — for the
/// selected channel preset. Every control is REAL: edits go into a
/// working copy, "Save branding" persists it via
/// [ChannelPresetStore], and the live preview at the top renders
/// from the working copy, so a change is visible before saving.
///
/// AUTO-APPLY: new projects render from their channel preset, so a
/// saved branding change is what the next project's preview, template
/// PNG and reel export (watermark step + end card) use — there is no
/// separate per-project branding copy to go stale. Social handles
/// are shown only where entered: the preview footer here, the
/// Templates Library card footer and the export end card — an empty
/// handle is never shown as a placeholder.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'breaking_templates.dart';
import 'channel_preset.dart';
import 'watermark.dart';
import 'widgets/breaking_preview.dart';
import 'widgets/nigraan_final_preview.dart';

/// Brand-colour swatches: the 5 house ribbon swatches + purple
/// (the app accent / default brand colour) + black.
const List<int> kBrandSwatches = [
  0xFF7C3AED,
  0xFF01B0FF,
  0xFFD50000,
  0xFF3D5AFE,
  0xFFEF0017,
  0xFF1E88E5,
  0xFF000000,
];

class ChannelBrandingScreen extends StatefulWidget {
  /// Test seams: when given, the screen uses them directly instead
  /// of loading the store first. Production passes nulls.
  const ChannelBrandingScreen({
    super.key,
    this.initialPreset,
    this.initialPresets,
  });

  final ChannelPreset? initialPreset;
  final List<ChannelPreset>? initialPresets;

  @override
  State<ChannelBrandingScreen> createState() =>
      _ChannelBrandingScreenState();
}

class _ChannelBrandingScreenState extends State<ChannelBrandingScreen> {
  List<ChannelPreset> _presets = [];
  ChannelPreset? _preset;
  ChannelPreset? _working;
  bool _loaded = false;

  final _picker = ImagePicker();
  final _nameController = TextEditingController();
  final _facebookController = TextEditingController();
  final _youtubeController = TextEditingController();
  final _tiktokController = TextEditingController();
  final _instagramController = TextEditingController();
  final _xController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialPreset != null || widget.initialPresets != null) {
      _presets = widget.initialPresets ??
          (widget.initialPreset == null
              ? [ChannelPreset.nigraanTv()]
              : [widget.initialPreset!]);
      _preset = widget.initialPreset ?? _presets.first;
      _working = ChannelPreset.fromJson(_preset!.toJson());
      _syncControllers(_working!);
      _loaded = true;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final presets = await ChannelPresetStore.loadAll();
    final selectedId = await ChannelPresetStore.loadSelectedId();
    final preset = selectedId == null
        ? presets.first
        : presets.firstWhere(
            (p) => p.id == selectedId,
            orElse: () => presets.first,
          );
    if (!mounted) return;
    setState(() {
      _presets = presets;
      _preset = preset;
      _working = ChannelPreset.fromJson(preset.toJson());
      _syncControllers(_working!);
      _loaded = true;
    });
  }

  void _syncControllers(ChannelPreset p) {
    _nameController.text = p.name;
    _facebookController.text = p.socialFacebook;
    _youtubeController.text = p.socialYoutube;
    _tiktokController.text = p.socialTiktok;
    _instagramController.text = p.socialInstagram;
    _xController.text = p.socialX;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _facebookController.dispose();
    _youtubeController.dispose();
    _tiktokController.dispose();
    _instagramController.dispose();
    _xController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Persists the working copy into the presets list (in place, same
  /// id — a preset's identity never changes when its branding is
  /// edited). The state update + confirmation happen synchronously;
  /// the JSON write is fire-and-forget (fail-soft, like every other
  /// store here — a failed write never blocks editing, and the next
  /// save retries).
  void _save() {
    final preset = _preset;
    final working = _working;
    if (preset == null || working == null) return;
    final index = _presets.indexWhere((p) => p.id == preset.id);
    if (index >= 0) _presets[index] = working;
    unawaited(
      ChannelPresetStore.saveAll(_presets, selectedId: preset.id),
    );
    setState(() => _preset = working);
    _showMessage(
      'Branding save ho gayi — naye projects par lagoo hogi.',
    );
  }

  /// Switches the edited channel (saving the current working copy
  /// first, so no edit is lost by switching).
  void _switchPreset(ChannelPreset next) {
    if (_preset?.id == next.id) return;
    _save();
    if (!mounted) return;
    setState(() {
      _preset = next;
      _working = ChannelPreset.fromJson(next.toJson());
      _syncControllers(_working!);
    });
  }

  Future<void> _pickLogo() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() => _working?.logoPath = picked.path);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF7C3AED),
          secondary: Color(0xFF7C3AED),
        ),
        scaffoldBackgroundColor: const Color(0xFF080810),
        cardColor: const Color(0xFF181828),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Channel Branding'),
          backgroundColor: const Color(0xFF080810),
        ),
        body: !_loaded || _preset == null || _working == null
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(_working!),
      ),
    );
  }

  Widget _buildBody(ChannelPreset working) {
    final handles = endCardLines(working);
    return ListView(
      key: const Key('channelBrandingList'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        if (_presets.length > 1) ...[
          const Text(
            'Channel',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _presets.map((p) {
              return ChoiceChip(
                key: Key('brandingPreset-${p.id}'),
                label: Text(p.name),
                selected: p.id == _preset!.id,
                onSelected: (_) => _switchPreset(p),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
        const Text(
          'Live preview — branding yahan se naye projects par lagoo hoti hai',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Center(
          child: working.templateKind == 'breaking'
              ? BreakingTemplatePreview(
                  template: BreakingTemplate.fromPreset(working),
                  preset: working,
                  height: 220,
                )
              : working.templateKind == 'classic'
                  ? ClassicPreview(preset: working, height: 220)
                  : NigraanFinalPreview(preset: working, height: 220),
        ),
        const SizedBox(height: 20),
        const Text(
          'Channel name',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('brandingNameField'),
          controller: _nameController,
          decoration: const InputDecoration(
            hintText: 'Channel ka naam…',
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => working.name = v),
        ),
        const SizedBox(height: 20),
        const Text(
          'Logo',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                working.logoPath == null
                    ? 'Logo: default (3D rotate on)'
                    : 'Logo: ${working.logoPath!.split('/').last} (3D rotate on)',
                style: const TextStyle(color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              key: const Key('brandingLogoButton'),
              onPressed: _pickLogo,
              child: const Text('Logo badlein'),
            ),
            if (working.logoPath != null) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                key: const Key('brandingLogoClearButton'),
                onPressed: () => setState(() => working.logoPath = null),
                child: const Text('Default'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Brand colour',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _swatchRow(
          'Brand',
          working.brandColor,
          (c) => setState(() => working.brandColor = c),
          keyPrefix: 'brandingBrandColor',
        ),
        const SizedBox(height: 12),
        const Text(
          'Ribbon colours',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _swatchRow(
          'Top ticker',
          working.topRibbon.color,
          (c) => setState(() => working.topRibbon.color = c),
          keyPrefix: 'brandingRibbonColor-top',
        ),
        _swatchRow(
          'Middle Urdu',
          working.urduRibbon.color,
          (c) => setState(() => working.urduRibbon.color = c),
          keyPrefix: 'brandingRibbonColor-middle',
        ),
        _swatchRow(
          'Bottom English',
          working.englishRibbon.color,
          (c) => setState(() => working.englishRibbon.color = c),
          keyPrefix: 'brandingRibbonColor-bottom',
        ),
        const Text(
          'Ribbon content fixed hai — top = current story, middle '
          'Urdu = national news, bottom English = international.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 20),
        const Text(
          'Social handles',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Khaali handle kahin nahi dikhega — sirf bhare hue handles '
          'preview footer aur export end card par aate hain.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        _handleField(
          key: const Key('brandingHandle-facebook'),
          label: 'Facebook',
          controller: _facebookController,
          onChanged: (v) => setState(() => working.socialFacebook = v),
        ),
        const SizedBox(height: 8),
        _handleField(
          key: const Key('brandingHandle-youtube'),
          label: 'YouTube',
          controller: _youtubeController,
          onChanged: (v) => setState(() => working.socialYoutube = v),
        ),
        const SizedBox(height: 8),
        _handleField(
          key: const Key('brandingHandle-tiktok'),
          label: 'TikTok',
          controller: _tiktokController,
          onChanged: (v) => setState(() => working.socialTiktok = v),
        ),
        const SizedBox(height: 8),
        _handleField(
          key: const Key('brandingHandle-instagram'),
          label: 'Instagram',
          controller: _instagramController,
          onChanged: (v) => setState(() => working.socialInstagram = v),
        ),
        const SizedBox(height: 8),
        _handleField(
          key: const Key('brandingHandle-x'),
          label: 'X (Twitter)',
          controller: _xController,
          onChanged: (v) => setState(() => working.socialX = v),
        ),
        const SizedBox(height: 12),
        Card(
          key: const Key('brandingHandlesPreview'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'End card par ye dikhega:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (handles.length <= 1)
                  const Text(
                    'Koi handle nahi — end card par sirf channel ka '
                    'naam dikhega.',
                    style: TextStyle(color: Colors.grey),
                  )
                else
                  ...handles.map((line) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(line),
                      )),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Watermark — exported reels par',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Channel mark (logo, ya brand colour par initial) export '
          'mein corner par lagta hai.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        SwitchListTile(
          key: const Key('brandingWatermarkSwitch'),
          title: const Text('Watermark on karein'),
          value: working.watermarkEnabled,
          onChanged: (v) =>
              setState(() => working.watermarkEnabled = v),
          contentPadding: EdgeInsets.zero,
        ),
        if (working.watermarkEnabled) ...[
          const Text('Position'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ChannelPreset.watermarkPositionIds.map((id) {
              return ChoiceChip(
                key: Key('brandingWatermarkPosition-$id'),
                label: Text(
                  ChannelPreset.watermarkPositionLabels[id] ?? id,
                ),
                selected: working.watermarkPosition == id,
                onSelected: (_) =>
                    setState(() => working.watermarkPosition = id),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Size'),
              Expanded(
                child: Slider(
                  key: const Key('brandingWatermarkSizeSlider'),
                  value: working.watermarkSize.clamp(0.05, 0.30),
                  min: 0.05,
                  max: 0.30,
                  onChanged: (v) =>
                      setState(() => working.watermarkSize = v),
                ),
              ),
              Text(
                '${(working.watermarkSize * 100).toInt()}%',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          'Intro / Outro defaults',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SwitchListTile(
          key: const Key('brandingIntroSwitch'),
          title: const Text('Intro (10s)'),
          value: working.showIntro,
          onChanged: (v) => setState(() => working.showIntro = v),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          key: const Key('brandingOutroSwitch'),
          title: const Text('Outro (3s end card)'),
          value: working.showOutro,
          onChanged: (v) => setState(() => working.showOutro = v),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('brandingSaveButton'),
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Save branding'),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Save karne par ye branding naye projects, template '
          'previews aur reel exports par lagoo ho jati hai.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _handleField({
    required Key key,
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) {
    return TextField(
      key: key,
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      onChanged: (v) {
        onChanged(v);
        setState(() {});
      },
    );
  }

  /// One swatch row: label + hex + tappable colour circles.
  Widget _swatchRow(
    String label,
    int current,
    void Function(int) set, {
    required String keyPrefix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label),
              const SizedBox(width: 12),
              Text(
                '#${current.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kBrandSwatches.map((c) {
              final selected = current == c;
              return InkWell(
                key: Key('$keyPrefix-$c'),
                onTap: () => set(c),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.white : Colors.white24,
                      width: selected ? 3 : 1,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
