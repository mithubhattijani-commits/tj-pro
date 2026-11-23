/// Template & Studio options screen (Phase 3, mockup 3; Phase 6:
/// breaking + classic previews render for real, the export works for
/// all three template kinds, and the graphics package controls —
/// category label, interview name plate, PIP — live here).
///
/// The screen where the user picks the template, pastes the ticker
/// text (paste-to-run — the preview ticker scrolls IMMEDIATELY), tunes
/// each ribbon's own settings, sets the lower third + breaking banner,
/// chroma key, and intro/outro. Look: mockup 3
/// (`template-studio-options.png`) — dark navy/black, purple accents.
///
/// Every control is real — nothing here is a dead button:
///   - Template picker, ribbon settings, lower third, breaking banner,
///     chroma toggle/background/sensitivity, intro/outro all persist
///     to the selected channel preset ([ChannelPresetStore]) the moment
///     they change (debounced 500 ms for text fields).
///   - The Export button renders the current template as a 720×1280
///     PNG frame ([renderLiveTemplateImage] — final, breaking and
///     classic branches) and saves it to the gallery. The full reel
///     export (FFmpeg + voice + clips) is Phase 7, in the News Maker
///     / AI News Maker export card.
///   - The visual chroma-key effect IS wired (Phase 7): the toggle +
///     background + sensitivity persist here AND apply in the reel
///     export (`chromaPassCommand` — ProChroma / chromaFilterComplex)
///     and in the video editor when a project opens there. Same for
///     PIP: the toggle + position + size persist now and the video
///     editor composites the inset at export ([pipOverlayFilter]).
///   - Breaking / Classic template variants render for real now
///     (Phase 6) — preview + PNG export. The Templates Library
///     (button below the template picker) holds the full editor.
///
/// RIBBON-CONTENT RULE (user, 20 Nov 2026): the content kind of each
/// ribbon is FIXED — top = current story, middle Urdu = national news,
/// bottom English = international — and is shown as read-only info,
/// never editable.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../app_config.dart';
import '../live/news_template.dart';
import '../services/asset_download_service.dart';
import '../services/remote_config_service.dart';
import 'breaking_templates.dart';
import 'channel_branding_screen.dart';
import 'channel_preset.dart';
import 'templates_library_screen.dart';
import 'widgets/breaking_preview.dart';
import 'widgets/nigraan_final_preview.dart';

/// Template picker ids. All three kinds now render in export as
/// well as in preview: 'nigraanFinal' renders through the Phase 3
/// PNG branch (the nigraanFinal branch of
/// [renderLiveTemplateImage]) and the reel export pins its ticker
/// at the start of the static frame (`tickerAtStart` in
/// ReelExportService); 'breaking' / 'classic' render through the
/// Phase 6 branches in the same renderer.
const String kTemplateFinal = 'nigraanFinal';
const String kTemplateBreaking = 'breaking';
const String kTemplateClassic = 'classic';

class TemplateStudioScreen extends StatefulWidget {
  /// [initialPreset] is a test/deep-link seam: when given, the screen
  /// edits that preset directly instead of loading the selected preset
  /// from the store first. Production always passes null.
  const TemplateStudioScreen({super.key, this.initialPreset});

  final ChannelPreset? initialPreset;

  @override
  State<TemplateStudioScreen> createState() => _TemplateStudioScreenState();
}

class _TemplateStudioScreenState extends State<TemplateStudioScreen> {
  List<ChannelPreset> _presets = [];
  ChannelPreset? _preset;
  String? _selectedId;
  bool _loaded = false;

  final _tickerController = TextEditingController();
  final _topTextController = TextEditingController();
  final _urduTextController = TextEditingController();
  final _englishTextController = TextEditingController();
  final _lowerTitleController = TextEditingController();
  final _lowerSubtitleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _interviewNameController = TextEditingController();
  final _interviewDesignationController = TextEditingController();

  /// Which ribbon's settings panel is expanded ('top' by default,
  /// per mockup 3; null = all collapsed).
  String _expandedRibbon = 'top';
  bool _lowerThirdExpanded = false;

  bool _fontReady = false;

  /// True when an effective Kasheeda download URL exists (remote
  /// config or the compile-time fallback) — gates the manual
  /// Download/retry button, which must not key off the compile-time
  /// constant alone (it is empty by design; the real URL is hosted
  /// and arrives via remote config).
  bool _fontUrlAvailable = false;
  String _fontStatus = 'Checking…';
  bool _exporting = false;
  Timer? _saveTimer;
  final _picker = ImagePicker();

  static const _swatches = <int>[
    0xFF01B0FF,
    0xFFD50000,
    0xFF3D5AFE,
    0xFFEF0017,
    0xFF1E88E5,
    0xFF00C853,
    0xFFFFC107,
    0xFFFFFFFF,
    0xFF000000,
  ];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialPreset;
    if (initial != null) {
      _applyPreset([initial], initial);
      _checkFont();
    } else {
      _load();
    }
  }

  /// Installs [preset] as the working preset (controllers + state).
  void _applyPreset(List<ChannelPreset> presets, ChannelPreset preset) {
    _presets = presets;
    _preset = preset;
    _selectedId = preset.id;
    _tickerController.text = preset.topRibbon.text;
    _topTextController.text = preset.topRibbon.text;
    _urduTextController.text = preset.urduRibbon.text;
    _englishTextController.text = preset.englishRibbon.text;
    _lowerTitleController.text = preset.lowerThirdTitle;
    _lowerSubtitleController.text = preset.lowerThirdSubtitle;
    _categoryController.text = preset.categoryLabel;
    _interviewNameController.text = preset.interviewName;
    _interviewDesignationController.text = preset.interviewDesignation;
    _loaded = true;
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
    setState(() => _applyPreset(presets, preset));
    await _checkFont();
  }

  /// The EFFECTIVE Kasheeda font URL: the remote config value
  /// (`kasheeda_font_url` in tj-pro.json, read the same way
  /// CoinService / HelpWhatsAppButton read theirs —
  /// `RemoteConfigService.instance.config`) when non-empty, else
  /// the compile-time [AppConfig.kasheedaFontUrl] fallback. The
  /// compile-time constant is EMPTY by design, so keying the font
  /// state off it alone always reported the hosted font as
  /// unavailable. Fail-soft: any config-load failure falls back to
  /// the [AppConfig] value, so this screen can never crash on it.
  Future<String> _effectiveKasheedaFontUrl() async {
    try {
      await RemoteConfigService.instance.init();
    } catch (_) {
      // Fail-soft: keep whatever config is already resolved.
    }
    final remoteUrl =
        RemoteConfigService.instance.config.kasheedaFontUrl.trim();
    if (remoteUrl.isNotEmpty) return remoteUrl;
    return AppConfig.kasheedaFontUrl.trim();
  }

  /// Kasheeda font state: cached file -> load it via FontLoader and
  /// render Urdu in Kasheeda; no cached file but an effective
  /// download URL -> download + load it right here; no URL at all ->
  /// the renderer + preview use the system fallback font and say so
  /// (never a crash, never a silent wrong font).
  Future<void> _checkFont() async {
    final service = const AssetDownloadService();
    final cached =
        await service.cachedFile(AssetDownloadService.kasheedaFileName);
    if (!mounted) return;
    if (cached != null) {
      try {
        await AssetDownloadService.loadKasheedaFontFromFile(cached);
        if (!mounted) return;
        setState(() {
          _fontReady = true;
          _fontStatus = 'Urdu font (Kasheeda): ready';
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _fontReady = false;
          _fontStatus =
              'Urdu font (Kasheeda): load nahi hua — fallback font use ho raha hai';
        });
      }
      return;
    }
    final url = await _effectiveKasheedaFontUrl();
    if (!mounted) return;
    if (url.isEmpty) {
      setState(() {
        _fontReady = false;
        _fontUrlAvailable = false;
        _fontStatus =
            'Urdu font (Kasheeda): abhi available nahi — fallback font use ho raha hai';
      });
      return;
    }
    setState(() {
      _fontUrlAvailable = true;
      _fontStatus = 'Urdu font (Kasheeda): downloading…';
    });
    try {
      await const AssetDownloadService().loadKasheedaFont(url: url);
      if (!mounted) return;
      setState(() {
        _fontReady = true;
        _fontStatus = 'Urdu font (Kasheeda): ready';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fontReady = false;
        _fontStatus =
            'Urdu font (Kasheeda): download fail — fallback font use ho raha hai';
      });
    }
  }

  Future<void> _downloadFont() async {
    final url = await _effectiveKasheedaFontUrl();
    if (!mounted) return;
    if (url.isEmpty) {
      setState(() {
        _fontUrlAvailable = false;
        _fontStatus =
            'Urdu font (Kasheeda): abhi available nahi — fallback font use ho raha hai';
      });
      return;
    }
    setState(() {
      _fontUrlAvailable = true;
      _fontStatus = 'Urdu font (Kasheeda): downloading…';
    });
    try {
      await const AssetDownloadService().loadKasheedaFont(url: url);
      if (!mounted) return;
      setState(() {
        _fontReady = true;
        _fontStatus = 'Urdu font (Kasheeda): ready';
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _fontStatus = 'Urdu font download fail: $e',
      );
    }
  }

  /// Persists the working preset (debounced so typing does not write
  /// the JSON file on every keystroke).
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      if (_preset == null) return;
      ChannelPresetStore.saveAll(_presets, selectedId: _selectedId);
    });
  }

  Future<void> _saveNow() async {
    _saveTimer?.cancel();
    if (_preset == null) return;
    await ChannelPresetStore.saveAll(_presets, selectedId: _selectedId);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _tickerController.dispose();
    _topTextController.dispose();
    _urduTextController.dispose();
    _englishTextController.dispose();
    _lowerTitleController.dispose();
    _lowerSubtitleController.dispose();
    _categoryController.dispose();
    _interviewNameController.dispose();
    _interviewDesignationController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _pasteTicker() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _showMessage('Clipboard khaali hai — pehle text copy karein.');
      return;
    }
    final preset = _preset;
    if (preset == null) return;
    setState(() {
      preset.topRibbon.text = text;
      _tickerController.text = text;
      _topTextController.text = text;
    });
    _scheduleSave();
  }

  /// Real export of this screen's work: renders the current template
  /// (final, breaking or classic) as a 720×1280 PNG frame and saves
  /// it to the gallery. The full reel export (FFmpeg + voice +
  /// clips) is Phase 7.
  Future<void> _exportTemplateFrame() async {
    final preset = _preset;
    if (preset == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      await _saveNow();
      final dir = await getApplicationDocumentsDirectory();
      final kind = preset.templateKind;
      final file = await renderLiveTemplateImage(
        template: NewsTemplate(),
        tickerPx: 0,
        now: DateTime.now(),
        dir: dir,
        templateKind: kind == kTemplateBreaking
            ? 'breaking'
            : kind == kTemplateClassic
                ? 'classic'
                : kTemplateFinal,
        preset: preset,
        breakingTemplate: kind == kTemplateBreaking
            ? BreakingTemplate.fromPreset(preset)
            : null,
        tickerAtStart: true,
        includeLogo: true,
        fontReady: _fontReady,
        includeIntroMarker: true,
      );
      await Gal.putImage(file.path);
      _showMessage(
        'Template frame gallery mein save ho gaya — video export '
        'Phase 7 mein aayega.',
      );
    } catch (e) {
      _showMessage('Template frame save nahi hua: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
          title: const Text('Template & Studio'),
          backgroundColor: const Color(0xFF080810),
          actions: [
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Settings save karein',
              onPressed: () async {
                await _saveNow();
                _showMessage('Settings save ho gayi hain.');
              },
            ),
          ],
        ),
        body: !_loaded || _preset == null
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(_preset!),
        bottomNavigationBar: _preset == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    onPressed: _exporting ? null : _exportTemplateFrame,
                    icon: _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.upload),
                    label: Text(
                      _exporting
                          ? 'Frame ban raha hai…'
                          : 'Export Reel • 720p',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildBody(ChannelPreset preset) {
    return ListView(
      key: const Key('templateStudioList'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Text(
          '${preset.name} preset',
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 12),
        _sectionTitle('Preview'),
        const SizedBox(height: 8),
        Center(
          child: preset.templateKind == kTemplateFinal
              ? NigraanFinalPreview(
                  preset: preset,
                  fontReady: _fontReady,
                  height: 300,
                )
              : preset.templateKind == kTemplateBreaking
                  ? BreakingTemplatePreview(
                      key: const Key('templateStudioBreakingPreview'),
                      template: BreakingTemplate.fromPreset(preset),
                      preset: preset,
                      fontReady: _fontReady,
                      height: 300,
                    )
                  : ClassicPreview(
                      key: const Key('templateStudioClassicPreview'),
                      preset: preset,
                      fontReady: _fontReady,
                      height: 300,
                    ),
        ),
        const SizedBox(height: 20),
        _sectionTitle('Template'),
        const SizedBox(height: 8),
        Row(
          children: [
            _templateCard(
              preset: preset,
              kind: kTemplateFinal,
              label: 'Final 3-Ribbon',
              colors: const [0xFFFFC800, 0xFF880C03, 0xFF081E46],
            ),
            const SizedBox(width: 8),
            _templateCard(
              preset: preset,
              kind: kTemplateBreaking,
              label: 'Breaking',
              colors: const [0xFFD50000, 0xFFD50000, 0xFF000000],
            ),
            const SizedBox(width: 8),
            _templateCard(
              preset: preset,
              kind: kTemplateClassic,
              label: 'Classic',
              colors: const [0xFF424242, 0xFF616161, 0xFF9E9E9E],
            ),
          ],
        ),
        if (preset.templateKind == kTemplateBreaking) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: BreakingVariant.values.map((variant) {
              final selected = preset.breakingVariant == variant.id;
              return ChoiceChip(
                key: Key('breakingVariant-${variant.id}'),
                label: Text(variant.label),
                selected: selected,
                onSelected: (_) {
                  setState(() => preset.breakingVariant = variant.id);
                  _scheduleSave();
                },
              );
            }).toList(),
          ),
        ],
        if (preset.templateKind == kTemplateFinal) ...[
          const SizedBox(height: 12),
          // Final design variant (22 Nov 2026): the DEFAULT
          // 3-ribbon stack measured from the user's reference
          // frame, or the v1.3.0 Classic 2-Ribbon parity design.
          // Switching re-renders the preview AND the export.
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Final design',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const Key('finalVariant-final3'),
                label: const Text('Final 3-Ribbon'),
                selected: preset.finalVariant == kFinalVariant3,
                onSelected: (_) {
                  setState(() => preset.finalVariant = kFinalVariant3);
                  _scheduleSave();
                },
              ),
              ChoiceChip(
                key: const Key('finalVariant-classic2'),
                label: const Text('Classic 2-Ribbon'),
                selected: preset.finalVariant == kFinalVariantClassic2,
                onSelected: (_) {
                  setState(
                      () => preset.finalVariant = kFinalVariantClassic2);
                  _scheduleSave();
                },
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('templatesLibraryButton'),
            onPressed: () async {
              await _saveNow();
              if (!mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const TemplatesLibraryScreen(),
                ),
              );
              await _load();
            },
            icon: const Icon(Icons.dashboard_customize),
            label: const Text('Templates Library →'),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const Key('channelBrandingButton'),
            onPressed: () async {
              // Fire-and-forget: the save is fail-soft, and navigation
              // must not wait on a disk write (widget-test pumps never
              // flush dart:io, so an await here would also make the
              // navigation untestable).
              unawaited(_saveNow());
              if (!mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ChannelBrandingScreen(initialPreset: _preset),
                ),
              );
              await _load();
            },
            icon: const Icon(Icons.branding_watermark),
            label: const Text('Channel Branding →'),
          ),
        ),
        const SizedBox(height: 20),
        _sectionTitle('Ticker text — paste karein, chal jaye ga'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('tickerField'),
                controller: _tickerController,
                decoration: const InputDecoration(
                  hintText: 'Ticker text yahan paste karein…',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  preset.topRibbon.text = value;
                  _topTextController.text = value;
                  setState(() {});
                  _scheduleSave();
                },
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('pasteButton'),
              onPressed: _pasteTicker,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
              ),
              child: const Text('Paste'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _tickerStripPreview(preset),
        const SizedBox(height: 4),
        const Text(
          'Sirf text chahiye — preview aur export mein aise hi chalega',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              _fontReady ? Icons.check_circle : Icons.warning_amber,
              size: 16,
              color: _fontReady ? Colors.green : Colors.amber,
            ),
            const SizedBox(width: 6),
            Expanded(
              key: const Key('fontStatus'),
              child: Text(
                _fontStatus,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            if (!_fontReady && _fontUrlAvailable)
              TextButton(
                onPressed: _downloadFont,
                child: const Text('Download'),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _sectionTitle('Ribbons — tap karein, settings khul jayein'),
        const SizedBox(height: 8),
        _ribbonCard(
          preset: preset,
          keyId: 'top',
          title: 'Top ticker ribbon',
          kindLabel: 'Current story',
          ribbon: preset.topRibbon,
          textController: _topTextController,
        ),
        _ribbonCard(
          preset: preset,
          keyId: 'middle',
          title: 'Middle Urdu ribbon',
          kindLabel: 'National news',
          ribbon: preset.urduRibbon,
          textController: _urduTextController,
        ),
        _ribbonCard(
          preset: preset,
          keyId: 'bottom',
          title: 'Bottom English ribbon',
          kindLabel: 'International',
          ribbon: preset.englishRibbon,
          textController: _englishTextController,
        ),
        const SizedBox(height: 20),
        _sectionTitle('Lower Third'),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              InkWell(
                key: const Key('lowerThirdHeader'),
                onTap: () => setState(
                  () => _lowerThirdExpanded = !_lowerThirdExpanded,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Lower Third',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              preset.lowerThirdTitle.isEmpty &&
                                      preset.lowerThirdSubtitle.isEmpty
                                  ? 'Reporter name + place'
                                  : '${preset.lowerThirdTitle} • ${preset.lowerThirdSubtitle}',
                              style: const TextStyle(color: Colors.grey),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: preset.showLowerThird,
                        onChanged: (v) {
                          setState(() => preset.showLowerThird = v);
                          _scheduleSave();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              if (_lowerThirdExpanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    children: [
                      TextField(
                        key: const Key('lowerTitleField'),
                        controller: _lowerTitleController,
                        decoration: const InputDecoration(
                          labelText: 'Reporter name',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          preset.lowerThirdTitle = value;
                          setState(() {});
                          _scheduleSave();
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const Key('lowerSubtitleField'),
                        controller: _lowerSubtitleController,
                        decoration: const InputDecoration(
                          labelText: 'Place',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          preset.lowerThirdSubtitle = value;
                          setState(() {});
                          _scheduleSave();
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: SwitchListTile(
            title: const Text('Breaking banner'),
            subtitle: const Text(
              'Middle Urdu ribbon par "بریکنگ نیوز" chip',
            ),
            value: preset.showBreakingBanner,
            onChanged: (v) {
              setState(() => preset.showBreakingBanner = v);
              _scheduleSave();
            },
          ),
        ),
        const SizedBox(height: 20),
        _sectionTitle('Category label'),
        const SizedBox(height: 8),
        TextField(
          key: const Key('categoryLabelField'),
          controller: _categoryController,
          decoration: const InputDecoration(
            labelText: 'Category (e.g. PAKISTAN, SPORTS)',
            hintText: 'Khaali = koi chip nahi',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            preset.categoryLabel = value;
            setState(() {});
            _scheduleSave();
          },
        ),
        const SizedBox(height: 20),
        _sectionTitle('Interview name plate'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Interview plate dikhayein'),
                  subtitle: const Text(
                    'Lower third ke upar — interviewee ka naam + designation',
                  ),
                  value: preset.showInterviewPlate,
                  onChanged: (v) {
                    setState(() => preset.showInterviewPlate = v);
                    _scheduleSave();
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                TextField(
                  key: const Key('interviewNameField'),
                  controller: _interviewNameController,
                  decoration: const InputDecoration(
                    labelText: 'Interviewee name',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    preset.interviewName = value;
                    setState(() {});
                    _scheduleSave();
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('interviewDesignationField'),
                  controller: _interviewDesignationController,
                  decoration: const InputDecoration(
                    labelText: 'Designation',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    preset.interviewDesignation = value;
                    setState(() {});
                    _scheduleSave();
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _sectionTitle('Picture-in-picture'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: const Text('PIP on karein'),
                  subtitle: const Text(
                    'Dusri video chhoti frame mein — position + size neeche',
                  ),
                  value: preset.pipEnabled,
                  onChanged: (v) {
                    setState(() => preset.pipEnabled = v);
                    _scheduleSave();
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                if (preset.pipEnabled) ...[
                  Wrap(
                    spacing: 8,
                    children: ChannelPreset.pipPositionIds.map((id) {
                      final selected = preset.pipPosition == id;
                      return ChoiceChip(
                        key: Key('pipPosition-$id'),
                        label: Text(
                          ChannelPreset.pipPositionLabels[id] ?? id,
                        ),
                        selected: selected,
                        onSelected: (_) {
                          setState(() => preset.pipPosition = id);
                          _scheduleSave();
                        },
                      );
                    }).toList(),
                  ),
                  Row(
                    children: [
                      const Text('Size'),
                      Expanded(
                        child: Slider(
                          key: const Key('pipScaleSlider'),
                          value: preset.pipScale,
                          min: 0.15,
                          max: 0.5,
                          onChanged: (v) {
                            setState(() => preset.pipScale = v);
                            _scheduleSave();
                          },
                        ),
                      ),
                      Text('${(preset.pipScale * 100).toInt()}%'),
                    ],
                  ),
                ],
                const Text(
                  'PIP inset preview mein dikhta hai — visual effect '
                  'export mein Phase 7 mein lagega.',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _sectionTitle('Chroma Key — Green Screen'),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Chroma Key',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Green screen hata ke background badlein',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: preset.chromaEnabled,
                      onChanged: (v) {
                        setState(() => preset.chromaEnabled = v);
                        _scheduleSave();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Background'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ChromaBackgroundKind.values.map((kind) {
                    final selected = preset.chromaBackground == kind;
                    return ChoiceChip(
                      label: Text(kind.label),
                      selected: selected,
                      onSelected: (_) async {
                        if (kind == ChromaBackgroundKind.gallery) {
                          final picked = await _picker.pickImage(
                            source: ImageSource.gallery,
                          );
                          if (picked == null) return;
                          setState(() {
                            preset.chromaBackground = kind;
                            preset.chromaBackgroundPath = picked.path;
                          });
                        } else {
                          setState(() {
                            preset.chromaBackground = kind;
                            preset.chromaBackgroundPath = null;
                          });
                        }
                        _scheduleSave();
                      },
                    );
                  }).toList(),
                ),
                if (preset.chromaBackground ==
                        ChromaBackgroundKind.gallery &&
                    preset.chromaBackgroundPath != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Picked: ${preset.chromaBackgroundPath!.split('/').last}',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Sensitivity'),
                    Expanded(
                      child: Slider(
                        value: preset.chromaSensitivity,
                        min: 0.05,
                        max: 1.0,
                        onChanged: (v) {
                          setState(() => preset.chromaSensitivity = v);
                          _scheduleSave();
                        },
                      ),
                    ),
                    Text(preset.chromaSensitivity.toStringAsFixed(2)),
                  ],
                ),
                const Text(
                  'Visual chroma effect reel export + timeline editor '
                  'mein lagta hai — sensitivity yahan set hoti hai. '
                  'Chroma key wala export 50 coins ka hota hai '
                  '(resolution ke ilawa).',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _sectionTitle('Intro / Outro'),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Intro (10s)'),
                subtitle: const Text('10 second ka channel intro'),
                value: preset.showIntro,
                onChanged: (v) {
                  setState(() => preset.showIntro = v);
                  _scheduleSave();
                },
              ),
              SwitchListTile(
                title: const Text('Outro'),
                subtitle: const Text('3 second ka end card'),
                value: preset.showOutro,
                onChanged: (v) {
                  setState(() => preset.showOutro = v);
                  _scheduleSave();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }

  Widget _templateCard({
    required ChannelPreset preset,
    required String kind,
    required String label,
    required List<int> colors,
  }) {
    final selected = preset.templateKind == kind;
    return Expanded(
      child: InkWell(
        key: Key('templateCard-$kind'),
        onTap: () {
          setState(() => preset.templateKind = kind);
          _scheduleSave();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF181828),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF7C3AED)
                  : Colors.white24,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: colors
                    .map(
                      (c) => Expanded(
                        child: Container(height: 10, color: Color(c)),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (selected)
                    const Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Color(0xFF7C3AED),
                    ),
                  if (selected) const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The live scrolling ticker strip under the paste field (mockup 3):
  /// red "تازہ ترین" chip + the pasted text scrolling at once.
  Widget _tickerStripPreview(ChannelPreset preset) {
    final ribbon = preset.topRibbon;
    final fontSize =
        NigraanFinalLayout.ribbonFontSize(ribbon, 40);
    return Container(
      key: const Key('tickerStripPreview'),
      height: 40,
      decoration: BoxDecoration(
        color: Color(ribbon.color),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Container(
            color: const Color(0xFFD50000),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              NigraanFinalLayout.tickerChipText,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: _fontReady &&
                        RegExp(r'[\u0600-\u06FF]').hasMatch(
                          NigraanFinalLayout.tickerChipText,
                        )
                    ? AssetDownloadService.kasheedaFamily
                    : null,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ScrollingTickerText(
                text: ribbon.text,
                speed: ribbon.speed,
                direction: ribbon.direction,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  fontFamily: _fontReady &&
                          RegExp(r'[\u0600-\u06FF]').hasMatch(ribbon.text)
                      ? AssetDownloadService.kasheedaFamily
                      : null,
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Text(
              '‹‹ scroll',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ribbonCard({
    required ChannelPreset preset,
    required String keyId,
    required String title,
    required String kindLabel,
    required RibbonConfig ribbon,
    required TextEditingController textController,
  }) {
    final expanded = _expandedRibbon == keyId;
    final hex =
        '#${ribbon.color.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          InkWell(
            key: Key('ribbonHeader-$keyId'),
            onTap: () => setState(() {
              _expandedRibbon = expanded ? '' : keyId;
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Color(ribbon.color),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Icon(
                              expanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 18,
                              color: Colors.grey,
                            ),
                          ],
                        ),
                        Text(
                          '$hex • $kindLabel',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: ribbon.enabled,
                    onChanged: (v) {
                      setState(() => ribbon.enabled = v);
                      _scheduleSave();
                    },
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Text'),
                  const SizedBox(height: 4),
                  TextField(
                    key: Key('ribbonText-$keyId'),
                    controller: textController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      ribbon.text = value;
                      // The top ribbon's text mirrors the ticker field
                      // (same text, two fields — paste-to-run stays in
                      // sync both ways).
                      if (keyId == 'top') _tickerController.text = value;
                      setState(() {});
                      _scheduleSave();
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Color'),
                      const SizedBox(width: 12),
                      Text(
                        hex,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _swatches.map((c) {
                      final selected = ribbon.color == c;
                      return InkWell(
                        key: Key('swatch-$keyId-$c'),
                        onTap: () {
                          setState(() => ribbon.color = c);
                          _scheduleSave();
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? Colors.white
                                  : Colors.white24,
                              width: selected ? 3 : 1,
                            ),
                          ),
                          child: selected
                              ? const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Speed'),
                      Expanded(
                        child: Slider(
                          value: ribbon.speed,
                          min: 0.25,
                          max: 2.5,
                          divisions: 45,
                          onChanged: (v) {
                            setState(() => ribbon.speed = v);
                            _scheduleSave();
                          },
                        ),
                      ),
                      Text('${ribbon.speed.toStringAsFixed(1)}×'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text('Direction'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SegmentedButton<RibbonDirection>(
                          segments: const [
                            ButtonSegment(
                              value: RibbonDirection.rtl,
                              label: Text('Right-to-left'),
                              icon: Icon(Icons.arrow_back),
                            ),
                            ButtonSegment(
                              value: RibbonDirection.ltr,
                              label: Text('Left-to-right'),
                              icon: Icon(Icons.arrow_forward),
                            ),
                          ],
                          selected: {ribbon.direction},
                          onSelectionChanged: (selected) {
                            setState(
                              () => ribbon.direction = selected.first,
                            );
                            _scheduleSave();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Size'),
                      const SizedBox(width: 12),
                      IconButton(
                        key: Key('sizeDown-$keyId'),
                        icon: const Icon(Icons.remove),
                        onPressed: () {
                          setState(() {
                            ribbon.fontSize =
                                (ribbon.fontSize - 1).clamp(10, 40).toDouble();
                          });
                          _scheduleSave();
                        },
                      ),
                      Text(
                        ribbon.fontSize.toInt().toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        key: Key('sizeUp-$keyId'),
                        icon: const Icon(Icons.add),
                        onPressed: () {
                          setState(() {
                            ribbon.fontSize =
                                (ribbon.fontSize + 1).clamp(10, 40).toDouble();
                          });
                          _scheduleSave();
                        },
                      ),
                      const Spacer(),
                      Text(
                        'Content: $kindLabel',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
