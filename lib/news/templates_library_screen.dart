/// Templates Library screen (Phase 6, mockup 10; Phase 8: all 13
/// categories populated + save-custom settings summary).
///
/// Categories (the 13 v1 categories from master prompt §8) + template
/// cards with live mini previews + Use + Save as Custom + a ribbon
/// colour picker (5 house swatches per ribbon) on the selected card.
///
/// What is REAL here — nothing is a dead button:
///   - Every card is a live preview of a real template: the 4 breaking
///     variants ([BreakingTemplatePreview]), the Final 3-Ribbon
///     ([NigraanFinalPreview]), Classic ([ClassicPreview]) and one
///     [CategoryTemplate] per each of the 13 categories (Phase 8) —
///     each category card renders through the same Phase 6 previews
///     + PNG renderers with its own colours + label, so no category
///     is ever an empty list.
///   - "Use" REALLY applies the template: breaking variants write
///     their settings into the selected channel preset (variant,
///     colours, texts, lower third, logo, intro/outro, interview
///     plate, PIP) and, when a project was handed in, into that
///     project (template kind + variant + headline + ticker) — both
///     persisted. Final/Classic set the preset's template kind.
///     Category templates apply their kind + variant + colours +
///     label to the preset (+ the project). A saved custom preset
///     card switches the selected preset.
///   - "Save as Custom Template" REALLY saves: the selected card's
///     current settings under the typed name — breaking templates via
///     [BreakingTemplateStore.saveCustomTemplate], Final/Classic via
///     [ChannelPresetStore.saveCustomTemplate], category templates via
///     [CategoryTemplateStore.saveCustomTemplate] — and the new card
///     appears under its category ("My Templates" first in All),
///     reusable in every project. A settings summary above the name
///     field shows exactly what will be saved (ribbons, colours,
///     speed, logo, intro/outro, lower third).
///   - Custom cards have a working Delete button (built-ins cannot
///     be deleted). Saved customs are editable: select the card,
///     edit in the panel, "Use" applies the edits.
///   - The editor panel edits a WORKING COPY: headline, ticker,
///     middle/bottom texts (combo only), category label, per-ribbon
///     colours (5 swatches), speed, direction, font size, ribbon
///     toggles, lower third, interview plate, intro/outro, PIP,
///     logo (gallery picker). Nothing applies until "Use".
///   - Ribbon content kinds are shown as read-only info, never
///     editable (RIBBON-CONTENT RULE: top = current story, middle
///     Urdu = national news, bottom English = international).
///   - Premium templates show their coin cost badge ("25 coins").
///     COINS (Phase 10): "Use" on a priced template spends the cost
///     ([CoinFeature.premiumTemplate], 25 coins) BEFORE applying —
///     insufficient balance aborts with a message and nothing
///     applies. Free templates (cost 0) apply with no spend. Admins
///     are waived server-side. The charge is per Use.
///
/// Split screen, map and sports-score graphics are NOT in this
/// library — they need engines that do not exist in the app yet (see
/// the Phase 6 report); no card pretends otherwise.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/coin_service.dart';
import '../services/pricing_service.dart';

import '../services/asset_download_service.dart';
import 'breaking_templates.dart';
import 'category_templates.dart';
import 'channel_preset.dart';
import 'news_project.dart';
import 'widgets/breaking_preview.dart';
import 'widgets/nigraan_final_preview.dart';

/// The 13 v1 template categories (master prompt §8) + All.
const List<(String, String)> kTemplateCategories = [
  ('all', 'All'),
  ('breaking', 'Breaking News'),
  ('pakistan', 'Pakistan'),
  ('international', 'International'),
  ('politics', 'Politics'),
  ('sports', 'Sports'),
  ('business', 'Business'),
  ('technology', 'Technology'),
  ('weather', 'Weather'),
  ('crime', 'Crime'),
  ('special', 'Special Reports'),
  ('documentary', 'Documentary'),
  ('interview', 'Interview'),
  ('bulletins', 'News Bulletins'),
];

/// Categories of the Final 3-Ribbon template.
const List<String> kFinalTemplateCategories = [
  'pakistan',
  'international',
  'bulletins',
  'politics',
  'special',
];

/// Categories of the Classic template.
const List<String> kClassicTemplateCategories = [
  'bulletins',
  'special',
  'documentary',
  'interview',
  'pakistan',
];

/// The 5 house swatches of the ribbon colour picker (mockup 10):
/// ticker blue, breaking red, Urdu blue, English red, latest blue.
const List<int> kRibbonSwatches = [
  0xFF01B0FF,
  0xFFD50000,
  0xFF3D5AFE,
  0xFFEF0017,
  0xFF1E88E5,
];

/// One card in the library: a breaking template, the Final 3-Ribbon,
/// the Classic template, a category template, or a saved custom
/// channel preset.
class _LibraryItem {
  _LibraryItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.categories,
    this.breaking,
    this.preset,
    this.category,
    this.video,
    this.isCustom = false,
    this.coinCost = 0,
  });

  /// 'breaking' | 'final' | 'classic' | 'category' | 'preset' |
  /// 'videoIntro' (v1.2.0 bundled video intro templates).
  final String id;
  final String name;
  final String kind;
  final List<String> categories;
  final BreakingTemplate? breaking;
  final ChannelPreset? preset;
  final CategoryTemplate? category;
  final VideoIntroTemplate? video;
  final bool isCustom;
  final int coinCost;

  String get subtitle {
    if (kind == 'preset') return 'Custom channel preset';
    if (kind == 'videoIntro') return 'Built-in video intro';
    if (kind == 'category') {
      return isCustom ? 'Custom template' : 'Category template';
    }
    if (isCustom) return 'Custom template';
    return 'Built-in';
  }
}

class TemplatesLibraryScreen extends StatefulWidget {
  /// Test/deep-link seams: when given, the screen uses them directly
  /// instead of loading the stores first. Production passes nulls.
  /// [initialProject] is the project "Use" also applies to.
  const TemplatesLibraryScreen({
    super.key,
    this.initialPreset,
    this.initialProject,
    this.initialTemplates,
    this.initialCategoryTemplates,
  });

  final ChannelPreset? initialPreset;
  final NewsProject? initialProject;
  final List<BreakingTemplate>? initialTemplates;
  final List<CategoryTemplate>? initialCategoryTemplates;

  @override
  State<TemplatesLibraryScreen> createState() =>
      _TemplatesLibraryScreenState();
}

class _TemplatesLibraryScreenState extends State<TemplatesLibraryScreen> {
  List<ChannelPreset> _presets = [];
  ChannelPreset? _preset;
  NewsProject? _project;
  List<BreakingTemplate> _templates = [];
  List<CategoryTemplate> _categoryTemplates = [];
  List<_LibraryItem> _items = [];
  String _category = 'all';
  String? _selectedId;
  bool _loaded = false;
  bool _fontReady = false;

  /// Working copy of the selected breaking template (edited in the
  /// panel, applied on "Use").
  BreakingTemplate? _workingBreaking;

  /// Working copy of the selected preset for Final/Classic cards
  /// (edited in the panel, applied on "Use").
  ChannelPreset? _workingPreset;

  /// Working copy of the selected category template (edited in the
  /// panel, applied on "Use").
  CategoryTemplate? _workingCategory;

  /// Selected bundled video intro template (v1.2.0) + its editor
  /// state: ticker direction (Left/Right toggle; [_videoDirectionAuto]
  /// = follow the language default until the user toggles) and the
  /// chosen built-in music asset (null = none). Headline/ticker live
  /// in [_headlineController] / [_tickerController]; everything is
  /// written to the project (+ preset top ribbon) on "Use".
  VideoIntroTemplate? _workingVideo;
  RibbonDirection _videoDirection = RibbonDirection.rtl;
  bool _videoDirectionAuto = true;
  String? _videoMusicAsset;

  final _picker = ImagePicker();
  final _saveNameController = TextEditingController();

  // Editor controllers, rebuilt on every selection change.
  final _headlineController = TextEditingController();
  final _tickerController = TextEditingController();
  final _middleTextController = TextEditingController();
  final _bottomTextController = TextEditingController();
  final _categoryController = TextEditingController();
  final _lowerTitleController = TextEditingController();
  final _lowerSubtitleController = TextEditingController();
  final _interviewNameController = TextEditingController();
  final _interviewDesignationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _project = widget.initialProject;
    if (widget.initialPreset != null ||
        widget.initialTemplates != null ||
        widget.initialCategoryTemplates != null) {
      _presets = widget.initialPreset == null
          ? [ChannelPreset.nigraanTv()]
          : [widget.initialPreset!];
      _preset = widget.initialPreset ?? ChannelPreset.nigraanTv();
      _templates = widget.initialTemplates ?? BreakingTemplate.defaults();
      _categoryTemplates = widget.initialCategoryTemplates ??
          CategoryTemplate.defaults();
      _buildItems();
      _selectInitial();
      _loaded = true;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    final presets = await ChannelPresetStore.loadAll();
    final selectedId = await ChannelPresetStore.loadSelectedId();
    final templates = await BreakingTemplateStore.loadAll();
    final categoryTemplates = await CategoryTemplateStore.loadAll();
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
      _templates = templates;
      _categoryTemplates = categoryTemplates;
      _buildItems();
      _selectInitial();
      _loaded = true;
    });
    await _checkFont();
  }

  /// Kasheeda for the library previews: load it when cached,
  /// otherwise the previews render Urdu in the fallback font (never
  /// a crash).
  Future<void> _checkFont() async {
    try {
      final cached = await const AssetDownloadService()
          .cachedFile(AssetDownloadService.kasheedaFileName);
      if (cached != null) {
        await AssetDownloadService.loadKasheedaFontFromFile(cached);
        if (!mounted) return;
        setState(() => _fontReady = true);
      }
    } catch (_) {}
  }

  void _buildItems() {
    final items = <_LibraryItem>[];
    for (final t in _templates) {
      items.add(
        _LibraryItem(
          id: t.id,
          name: t.displayName,
          kind: 'breaking',
          categories: t.categories,
          breaking: t,
          isCustom: t.isCustom,
          coinCost: t.coinCost,
        ),
      );
    }
    // v1.2.0: the two bundled VIDEO intro templates — optional,
    // FREE, one-tap apply (kind 'videoIntro'; see breaking_templates
    // .dart for why they are not BreakingVariant values).
    for (final v in VideoIntroTemplate.defaults()) {
      items.add(
        _LibraryItem(
          id: 'video_${v.id}',
          name: v.displayName,
          kind: 'videoIntro',
          categories: v.categories,
          video: v,
          coinCost: v.coinCost,
        ),
      );
    }
    // One card per category (Phase 8): every one of the 13
    // categories has a real, rendering template — built-ins from
    // CategoryTemplate.defaults() + user-saved customs.
    for (final c in _categoryTemplates) {
      items.add(
        _LibraryItem(
          id: 'category_${c.id}',
          name: c.displayName,
          kind: 'category',
          categories: c.categories,
          category: c,
          isCustom: c.isCustom,
          coinCost: c.coinCost,
        ),
      );
    }
    items.add(
      _LibraryItem(
        id: 'final',
        name: 'Final 3-Ribbon',
        kind: 'final',
        categories: kFinalTemplateCategories,
        coinCost: 0,
      ),
    );
    items.add(
      _LibraryItem(
        id: 'classic',
        name: 'Classic',
        kind: 'classic',
        categories: kClassicTemplateCategories,
        coinCost: 0,
      ),
    );
    for (final p in _presets) {
      if (!p.id.startsWith('custom_')) continue;
      items.add(
        _LibraryItem(
          id: 'preset_${p.id}',
          name: p.name,
          kind: 'preset',
          categories: p.templateKind == 'breaking'
              ? BreakingTemplate.categoriesFor(
                  BreakingVariant.fromId(p.breakingVariant),
                )
              : p.templateKind == 'classic'
                  ? kClassicTemplateCategories
                  : kFinalTemplateCategories,
          preset: p,
          isCustom: true,
          coinCost: 0,
        ),
      );
    }
    _items = items;
  }

  /// Selects the card matching the current preset (breaking variant /
  /// classic / final), or the first card.
  void _selectInitial() {
    final preset = _preset;
    if (preset == null || _items.isEmpty) return;
    String? want;
    if (preset.templateKind == 'breaking') {
      want = preset.breakingVariant;
    } else if (preset.templateKind == 'classic') {
      want = 'classic';
    } else {
      want = 'final';
    }
    final match = _items.where((i) => i.id == want).toList();
    _select(match.isEmpty ? _items.first : match.first);
  }

  void _select(_LibraryItem item) {
    _selectedId = item.id;
    if (item.kind == 'videoIntro' && item.video != null) {
      _workingVideo = item.video;
      _workingCategory = null;
      _workingBreaking = null;
      _workingPreset = null;
      final project = _project;
      _headlineController.text = project?.headline ?? '';
      _tickerController.text =
          (project != null && project.tickerText.isNotEmpty)
              ? project.tickerText
              : (_preset?.topRibbon.text ?? '');
      _videoDirectionAuto = project?.tickerDirection == null;
      _videoDirection = project?.tickerDirection != null
          ? RibbonDirection.fromId(project!.tickerDirection)
          : defaultTickerDirectionForText(_tickerController.text);
      _videoMusicAsset = project?.backgroundMusicAsset;
      return;
    }
    _workingVideo = null;
    if (item.kind == 'category' && item.category != null) {
      _workingCategory = item.category!.copyWith();
      _workingBreaking = null;
      _workingPreset = null;
      _categoryController.text = _workingCategory!.categoryLabel;
      return;
    }
    _workingCategory = null;
    if (item.kind == 'breaking' && item.breaking != null) {
      _workingBreaking = item.breaking!.copyWith();
      _workingPreset = null;
      _syncBreakingControllers(_workingBreaking!);
    } else {
      _workingBreaking = null;
      final base = item.preset ?? _preset ?? ChannelPreset.nigraanTv();
      _workingPreset = ChannelPreset.fromJson(base.toJson());
      _syncPresetControllers(_workingPreset!);
    }
  }

  void _syncBreakingControllers(BreakingTemplate t) {
    _headlineController.text = t.headline;
    _tickerController.text = t.tickerText;
    _middleTextController.text = t.middleText;
    _bottomTextController.text = t.bottomText;
    _categoryController.text = t.categoryLabel;
    _lowerTitleController.text = t.lowerThirdTitle;
    _lowerSubtitleController.text = t.lowerThirdSubtitle;
    _interviewNameController.text = t.interviewName;
    _interviewDesignationController.text = t.interviewDesignation;
  }

  void _syncPresetControllers(ChannelPreset p) {
    _headlineController.text = '';
    _tickerController.text = p.topRibbon.text;
    _middleTextController.text = p.urduRibbon.text;
    _bottomTextController.text = p.englishRibbon.text;
    _categoryController.text = p.categoryLabel;
    _lowerTitleController.text = p.lowerThirdTitle;
    _lowerSubtitleController.text = p.lowerThirdSubtitle;
    _interviewNameController.text = p.interviewName;
    _interviewDesignationController.text = p.interviewDesignation;
  }

  @override
  void dispose() {
    _saveNameController.dispose();
    _headlineController.dispose();
    _tickerController.dispose();
    _middleTextController.dispose();
    _bottomTextController.dispose();
    _categoryController.dispose();
    _lowerTitleController.dispose();
    _lowerSubtitleController.dispose();
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

  List<_LibraryItem> get _visibleItems {
    final customs =
        _items.where((i) => i.isCustom).toList(growable: false);
    final builtins =
        _items.where((i) => !i.isCustom).toList(growable: false);
    if (_category == 'all') return [...customs, ...builtins];
    return _items.where((i) => i.categories.contains(_category)).toList();
  }

  Future<void> _reload() async {
    final presets = await ChannelPresetStore.loadAll();
    final selectedId = await ChannelPresetStore.loadSelectedId();
    final templates = await BreakingTemplateStore.loadAll();
    final categoryTemplates = await CategoryTemplateStore.loadAll();
    if (!mounted) return;
    setState(() {
      _presets = presets;
      _preset = selectedId == null
          ? presets.first
          : presets.firstWhere(
              (p) => p.id == selectedId,
              orElse: () => presets.first,
            );
      _templates = templates;
      _categoryTemplates = categoryTemplates;
      _buildItems();
      final selected = _selectedId;
      final match =
          selected == null ? null : _items.where((i) => i.id == selected).toList();
      if (match != null && match.isNotEmpty) {
        _select(match.first);
      } else {
        _selectInitial();
      }
    });
  }

  /// Point #20: an item's EFFECTIVE price — its own coinCost
  /// resolved through the remote key `price_ns_premium_template`
  /// (a configured number replaces the item price, 0 makes
  /// priced items free, an absent key keeps the item price).
  /// The card badge and the charge in [_useSelected] both read
  /// this, so they can never disagree. Free items stay free.
  static int _effectiveCost(_LibraryItem item) => item.coinCost > 0
      ? PricingService.coinsOr(
          PricingService.keyNsPremiumTemplate,
          item.coinCost,
        )
      : 0;

  /// "Use" — applies the working template to the selected channel
  /// preset (+ the handed-in project) and persists both. The state
  /// update + confirmation happen synchronously; the JSON writes are
  /// fire-and-forget (fail-soft, like every other store here).
  ///
  /// COINS (Phase 10): when the selected card is priced
  /// ([_LibraryItem.coinCost] > 0 — the 3 premium breaking variants
  /// at 25 coins), the spend lands BEFORE anything applies; on
  /// insufficient balance the template is NOT applied. Free cards
  /// skip the spend entirely, so the pre-coins behaviour is
  /// unchanged for them.
  Future<void> _useSelected() async {
    final preset = _preset;
    if (preset == null) return;
    // Point #20: the charge is the item's EFFECTIVE price
    // (see _effectiveCost) — the same number the card badge
    // shows, so badge and charge can never disagree.
    final cost =
        _selectedItem == null ? 0 : _effectiveCost(_selectedItem!);
    if (cost > 0) {
      // spendAmount (not spend(premiumTemplate)) so the charge
      // always equals the badge on the card — today every priced
      // template is 25, the standard premium price.
      final spendResult = await CoinService.instance.spendAmount(
        cost,
        reason: CoinCosts.reasonFor(CoinFeature.premiumTemplate),
      );
      if (!spendResult.ok) {
        _showMessage(
          'Coins kam hain — is template ke liye $cost coins chahiye. '
          'Watch Ads se kamayein.',
        );
        return;
      }
    }
    final working = _workingBreaking;
    final workingPreset = _workingPreset;
    final workingCategory = _workingCategory;
    final workingVideo = _workingVideo;
    if (workingVideo != null) {
      // v1.2.0 video intro: headline + ticker + direction + music
      // persist PER PROJECT; the ticker + direction also sync into
      // the preset's top ribbon, so the existing breaking export
      // path (BreakingTemplate.fromProject → PNG overlay) renders
      // the same headline + ticker + direction on the reel.
      final project = _project;
      if (project != null) {
        project.videoTemplateId = workingVideo.id;
        project.headline = _headlineController.text;
        project.tickerText = _tickerController.text;
        project.tickerDirection = _videoDirection.id;
        project.backgroundMusicAsset = _videoMusicAsset;
        unawaited(NewsProjectStore.save(project));
      }
      preset.topRibbon.text = _tickerController.text;
      preset.topRibbon.direction = _videoDirection;
      unawaited(
        ChannelPresetStore.saveAll(_presets, selectedId: preset.id),
      );
      _showMessage(
        'Video intro apply ho gaya — ${workingVideo.displayName}.',
      );
      setState(() {});
      return;
    }
    if (workingCategory != null) {
      workingCategory.applyToPreset(preset);
      final project = _project;
      if (project != null) {
        workingCategory.applyToProject(project);
        unawaited(NewsProjectStore.save(project));
      }
      unawaited(
        ChannelPresetStore.saveAll(_presets, selectedId: preset.id),
      );
      _showMessage('Template apply ho gaya — ${workingCategory.displayName}.');
      setState(() {});
      return;
    }
    if (working != null) {
      working.applyToPreset(preset);
      final project = _project;
      if (project != null) {
        working.applyToProject(project);
        unawaited(NewsProjectStore.save(project));
      }
      unawaited(
        ChannelPresetStore.saveAll(_presets, selectedId: preset.id),
      );
      _showMessage('Template apply ho gaya — ${working.displayName}.');
    } else if (workingPreset != null) {
      final selected = _selectedItem;
      if (selected != null && selected.kind == 'preset' && selected.preset != null) {
        // A saved custom preset: switch the selected preset to it.
        unawaited(ChannelPresetStore.saveAll(
          _presets,
          selectedId: selected.preset!.id,
        ));
        final project = _project;
        if (project != null) {
          project.presetId = selected.preset!.id;
          unawaited(NewsProjectStore.save(project));
        }
        setState(() => _preset = selected.preset);
        _showMessage('Preset apply ho gaya — ${selected.preset!.name}.');
      } else {
        // Final / Classic: copy the edited settings back onto the
        // working preset and set its template kind.
        _applyWorkingPreset(preset, workingPreset);
        preset.templateKind =
            selected?.kind == 'classic' ? 'classic' : 'nigraanFinal';
        // The reel export renders by the PROJECT's templateKind
        // (ReelExportService passes project.templateKind to
        // renderLiveTemplateImage, and effectivePresetFor copies it
        // onto the preset), so a project handed into this screen
        // must follow the preset's new kind — otherwise a project
        // created as 'breaking' would keep exporting the breaking
        // frame after the user switched it to the Final 3-Ribbon
        // template here. (The breaking / category branches above
        // already sync the project via applyToProject.)
        final project = _project;
        if (project != null &&
            project.templateKind != preset.templateKind) {
          project.templateKind = preset.templateKind;
          unawaited(NewsProjectStore.save(project));
        }
        unawaited(
          ChannelPresetStore.saveAll(_presets, selectedId: preset.id),
        );
        _showMessage(
          'Template apply ho gaya — ${selected?.name ?? 'Final 3-Ribbon'}.',
        );
      }
    }
    setState(() {});
  }

  _LibraryItem? get _selectedItem {
    final id = _selectedId;
    if (id == null) return null;
    final match = _items.where((i) => i.id == id).toList();
    return match.isEmpty ? null : match.first;
  }

  /// Copies every editable field from [source] onto [target] except
  /// id + name (the preset's identity never changes when a template
  /// is applied to it).
  void _applyWorkingPreset(ChannelPreset target, ChannelPreset source) {
    target.logoPath = source.logoPath;
    target.logoRotate = source.logoRotate;
    target.logoMediaKind = source.logoMediaKind;
    target.logoVideoPath = source.logoVideoPath;
    target.logoVideoKeyColor = source.logoVideoKeyColor;
    target.logoKeyedFramesDir = source.logoKeyedFramesDir;
    target.logoVideoStillPath = source.logoVideoStillPath;
    target.topRibbon = source.topRibbon.copyWith();
    target.urduRibbon = source.urduRibbon.copyWith();
    target.englishRibbon = source.englishRibbon.copyWith();
    target.breakingVariant = source.breakingVariant;
    target.breakingTickerColor = source.breakingTickerColor;
    target.categoryLabel = source.categoryLabel;
    target.showIntro = source.showIntro;
    target.showOutro = source.showOutro;
    target.lowerThirdTitle = source.lowerThirdTitle;
    target.lowerThirdSubtitle = source.lowerThirdSubtitle;
    target.showLowerThird = source.showLowerThird;
    target.showBreakingBanner = source.showBreakingBanner;
    target.interviewName = source.interviewName;
    target.interviewDesignation = source.interviewDesignation;
    target.showInterviewPlate = source.showInterviewPlate;
    target.pipEnabled = source.pipEnabled;
    target.pipPosition = source.pipPosition;
    target.pipScale = source.pipScale;
    target.chromaEnabled = source.chromaEnabled;
    target.chromaBackground = source.chromaBackground;
    target.chromaBackgroundPath = source.chromaBackgroundPath;
    target.chromaSensitivity = source.chromaSensitivity;
  }

  Future<void> _saveCustom() async {
    final name = _saveNameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Pehle template ka naam likhein.');
      return;
    }
    final working = _workingBreaking;
    final workingPreset = _workingPreset;
    final workingCategory = _workingCategory;
    if (_workingVideo != null) {
      // Built-in video intros are not saved as customs — their
      // headline/ticker/direction/music settings save per project
      // via "Use template".
      _showMessage(
        'Video intro built-in hai — settings "Use template" se '
        'project mein save hoti hain.',
      );
      return;
    }
    if (workingCategory != null) {
      final saved = await CategoryTemplateStore.saveCustomTemplate(
        name: name,
        template: workingCategory,
      );
      if (!mounted) return;
      _saveNameController.clear();
      await _reload();
      if (!mounted) return;
      setState(() => _select(
        _items.firstWhere(
          (i) => i.id == 'category_${saved.id}',
          orElse: () => _items.first,
        ),
      ));
      _showMessage('Custom template save ho gaya — "$name".');
    } else if (working != null) {
      final saved = await BreakingTemplateStore.saveCustomTemplate(
        name: name,
        template: working,
      );
      if (!mounted) return;
      _saveNameController.clear();
      await _reload();
      if (!mounted) return;
      setState(() => _select(
        _items.firstWhere((i) => i.id == saved.id, orElse: () => _items.first),
      ));
      _showMessage('Custom template save ho gaya — "$name".');
    } else if (workingPreset != null) {
      final saved = await ChannelPresetStore.saveCustomTemplate(
        name: name,
        preset: workingPreset,
      );
      if (!mounted) return;
      _saveNameController.clear();
      await _reload();
      if (!mounted) return;
      setState(() => _select(
        _items.firstWhere(
          (i) => i.id == 'preset_${saved.id}',
          orElse: () => _items.first,
        ),
      ));
      _showMessage('Custom template save ho gaya — "$name".');
    }
  }

  Future<void> _deleteCustom(_LibraryItem item) async {
    if (!item.isCustom) return;
    if (item.kind == 'breaking') {
      await BreakingTemplateStore.deleteCustomTemplate(item.id);
    } else if (item.kind == 'category' && item.category != null) {
      await CategoryTemplateStore.deleteCustomTemplate(item.category!.id);
    } else if (item.kind == 'preset' && item.preset != null) {
      await ChannelPresetStore.deletePreset(item.preset!.id);
    }
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    _showMessage('Custom template delete ho gaya.');
  }

  Future<void> _pickLogo() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() {
      _workingBreaking?.logoPath = picked.path;
      final wp = _workingPreset;
      if (wp != null) wp.logoPath = picked.path;
    });
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
          title: const Text('Templates Library'),
          backgroundColor: const Color(0xFF080810),
        ),
        body: !_loaded || _preset == null
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    final visible = _visibleItems;
    final selected = _selectedItem;
    return ListView(
      key: const Key('templatesLibraryList'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        const Text(
          'Categories',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView(
            key: const Key('templateCategoryRow'),
            scrollDirection: Axis.horizontal,
            children: kTemplateCategories.map((c) {
              final isSelected = _category == c.$1;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  key: Key('categoryChip-${c.$1}'),
                  label: Text(c.$2),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _category = c.$1),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        if (visible.isEmpty)
          Card(
            key: const Key('emptyCategory'),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Is category mein abhi koi template nahi — neeche '
                '"Save as Custom Template" se apna template banayein.',
              ),
            ),
          )
        else
          ...visible.map(_templateCard),
        if (selected != null) ...[
          const SizedBox(height: 20),
          const Text(
            'Edit template',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _editorPanel(selected),
          const SizedBox(height: 12),
          Card(
            key: const Key('saveCustomSummary'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Save hoga — settings summary',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _settingsSummaryText(),
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('saveCustomNameField'),
                controller: _saveNameController,
                decoration: const InputDecoration(
                  hintText: 'Custom template ka naam…',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('saveCustomButton'),
              onPressed: _saveCustom,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
              ),
              child: const Text('Save as Custom Template'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Save karta hai: ribbons, colours, speed, direction, size, '
          'logo, intro/outro, lower third, interview plate, PIP — '
          'har project mein reuse ho sakta hai.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 16),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Split screen, map aur sports-score graphics is library '
              'mein nahi hain — un ke liye app mein abhi koi engine '
              'nahi hai (Phase 7). Weather aur Sports ke templates '
              'upar hain — un ke graphics engine abhi nahi hain.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }

  Widget _templateCard(_LibraryItem item) {
    final selected = item.id == _selectedId;
    final preset = _preset!;
    final breaking = item.kind == 'breaking'
        ? (selected ? _workingBreaking ?? item.breaking : item.breaking)
        : null;
    final category = item.kind == 'category'
        ? (selected ? _workingCategory ?? item.category : item.category)
        : null;
    final video = item.kind == 'videoIntro' ? item.video : null;
    final cardPreset = item.kind == 'preset'
        ? item.preset!
        : (selected && _workingPreset != null ? _workingPreset! : preset);
    return Card(
      key: Key('templateCard-${item.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? const Color(0xFF7C3AED) : Colors.white24,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        key: Key('templateCardTap-${item.id}'),
        onTap: () => setState(() => _select(item)),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_circle,
                      color: Color(0xFF7C3AED),
                      size: 20,
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _effectiveCost(item) == 0
                        ? 'FREE'
                        : '${_effectiveCost(item)} coins',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (item.isCustom) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      key: Key('deleteCustom-${item.id}'),
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: 'Custom template delete karein',
                      onPressed: () => _deleteCustom(item),
                    ),
                  ],
                ],
              ),
              Text(
                item.subtitle,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Center(
                child: SizedBox(
                  height: 200,
                  child: _miniPreview(
                    item,
                    breaking,
                    cardPreset,
                    category,
                    video,
                  ),
                ),
              ),
              // Channel handles footer (Phase 8): the selected
              // channel's real handles, shown on every card. No
              // handle = no chip — never a placeholder.
              if (preset.socialHandles.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  key: const Key('templateCardHandles'),
                  spacing: 6,
                  runSpacing: 6,
                  children: preset.socialHandleLines().map((line) {
                    return Chip(
                      label: Text(
                        line,
                        style: const TextStyle(fontSize: 11),
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: Key('useTemplate-${item.id}'),
                  onPressed: () {
                    if (!selected) setState(() => _select(item));
                    _useSelected();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                  ),
                  child: const Text('Use template'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniPreview(
    _LibraryItem item,
    BreakingTemplate? breaking,
    ChannelPreset cardPreset, [
    CategoryTemplate? category,
    VideoIntroTemplate? video,
  ]) {
    // v1.2.0 video intro cards: the real intro video + the live
    // headline / ticker / direction from the editor panel (when
    // selected) — the same trio the export renders.
    if (item.kind == 'videoIntro' && video != null) {
      final isSelected = item.id == _selectedId;
      return VideoIntroPreview(
        template: video,
        headline: isSelected ? _headlineController.text : '',
        tickerText: isSelected ? _tickerController.text : '',
        direction: isSelected
            ? _videoDirection
            : defaultTickerDirectionForText(_tickerController.text),
        fontReady: _fontReady,
        height: 200,
      );
    }
    // Category cards render through the same Phase 6 previews +
    // PNG renderers with the category's own colours + label.
    if (item.kind == 'category' && category != null) {
      final previewPreset = category.previewPreset(cardPreset);
      if (category.templateKind == 'breaking') {
        return BreakingTemplatePreview(
          template: BreakingTemplate.fromPreset(previewPreset),
          preset: previewPreset,
          fontReady: _fontReady,
          height: 200,
        );
      }
      if (category.templateKind == 'classic') {
        return ClassicPreview(
          preset: previewPreset,
          fontReady: _fontReady,
          height: 200,
        );
      }
      return NigraanFinalPreview(
        preset: previewPreset,
        fontReady: _fontReady,
        height: 200,
      );
    }
    if (item.kind == 'breaking' && breaking != null) {
      return BreakingTemplatePreview(
        template: breaking,
        preset: cardPreset,
        fontReady: _fontReady,
        height: 200,
      );
    }
    if (item.kind == 'classic') {
      return ClassicPreview(
        preset: cardPreset,
        fontReady: _fontReady,
        height: 200,
      );
    }
    if (item.kind == 'preset' && item.preset != null) {
      final p = item.preset!;
      if (p.templateKind == 'breaking') {
        return BreakingTemplatePreview(
          template: BreakingTemplate.fromPreset(p),
          preset: p,
          fontReady: _fontReady,
          height: 200,
        );
      }
      if (p.templateKind == 'classic') {
        return ClassicPreview(
          preset: p,
          fontReady: _fontReady,
          height: 200,
        );
      }
    }
    return NigraanFinalPreview(
      preset: cardPreset,
      fontReady: _fontReady,
      height: 200,
    );
  }

  /// The editor panel for the selected card. Breaking templates edit
  /// the working [BreakingTemplate]; Final/Classic/preset cards edit
  /// the working [ChannelPreset] copy; category cards edit the
  /// working [CategoryTemplate] copy.
  Widget _editorPanel(_LibraryItem item) {
    final video = _workingVideo;
    if (video != null) return _videoEditorPanel(item, video);
    final category = _workingCategory;
    if (category != null) return _categoryEditorPanel(item, category);
    final breaking = _workingBreaking;
    final workingPreset = _workingPreset;
    // The logo path is nullable on BOTH models — read it once with
    // null-aware access. (A `breaking?.logoPath ?? workingPreset!`
    // chain NPEs when a breaking card with no custom logo is
    // selected, because workingPreset is null then.)
    final logoPath = breaking?.logoPath ?? workingPreset?.logoPath;
    final isCombo = breaking?.variant == BreakingVariant.breakingTickerCombo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Editing: ${item.name}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (breaking != null) ...[
              _textField(
                key: const Key('editHeadlineField'),
                label: 'Headline',
                controller: _headlineController,
                onChanged: (v) => breaking.headline = v,
              ),
              const SizedBox(height: 12),
              _textField(
                key: const Key('editTickerField'),
                label: 'Ticker text',
                controller: _tickerController,
                onChanged: (v) => breaking.tickerText = v,
              ),
              if (isCombo) ...[
                const SizedBox(height: 12),
                _textField(
                  key: const Key('editMiddleTextField'),
                  label: 'Middle Urdu ribbon — national news',
                  controller: _middleTextController,
                  onChanged: (v) => breaking.middleText = v,
                ),
                const SizedBox(height: 12),
                _textField(
                  key: const Key('editBottomTextField'),
                  label: 'Bottom English ribbon — international',
                  controller: _bottomTextController,
                  onChanged: (v) => breaking.bottomText = v,
                ),
              ],
            ] else ...[
              _textField(
                key: const Key('editTickerField'),
                label: 'Top ticker text — current story',
                controller: _tickerController,
                onChanged: (v) => workingPreset!.topRibbon.text = v,
              ),
              const SizedBox(height: 12),
              _textField(
                key: const Key('editMiddleTextField'),
                label: 'Middle Urdu ribbon — national news',
                controller: _middleTextController,
                onChanged: (v) => workingPreset!.urduRibbon.text = v,
              ),
              const SizedBox(height: 12),
              _textField(
                key: const Key('editBottomTextField'),
                label: 'Bottom English ribbon — international',
                controller: _bottomTextController,
                onChanged: (v) => workingPreset!.englishRibbon.text = v,
              ),
            ],
            const SizedBox(height: 12),
            _textField(
              key: const Key('editCategoryField'),
              label: 'Category label (e.g. PAKISTAN)',
              controller: _categoryController,
              onChanged: (v) {
                if (breaking != null) {
                  breaking.categoryLabel = v;
                } else {
                  workingPreset!.categoryLabel = v;
                }
              },
            ),
            const SizedBox(height: 4),
            const Text(
              'Ribbon content fixed hai — top = current story, middle '
              'Urdu = national news, bottom English = international. '
              'Content kind kabhi change nahi hota.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Text(
              'Ribbon colours',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._colorRows(breaking, workingPreset),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Speed'),
                Expanded(
                  child: Slider(
                    key: const Key('editSpeedSlider'),
                    value: breaking?.speed ?? workingPreset!.topRibbon.speed,
                    min: 0.25,
                    max: 2.5,
                    divisions: 45,
                    onChanged: (v) {
                      setState(() {
                        if (breaking != null) {
                          breaking.speed = v;
                        } else {
                          workingPreset!.topRibbon.speed = v;
                        }
                      });
                    },
                  ),
                ),
                Text(
                  '${(breaking?.speed ?? workingPreset!.topRibbon.speed).toStringAsFixed(1)}×',
                ),
              ],
            ),
            Row(
              children: [
                const Text('Direction'),
                const SizedBox(width: 12),
                Expanded(
                  child: SegmentedButton<RibbonDirection>(
                    key: const Key('editDirectionButton'),
                    segments: const [
                      ButtonSegment(
                        value: RibbonDirection.rtl,
                        label: Text('Right-to-left'),
                      ),
                      ButtonSegment(
                        value: RibbonDirection.ltr,
                        label: Text('Left-to-right'),
                      ),
                    ],
                    selected: {
                      breaking?.direction ??
                          workingPreset!.topRibbon.direction,
                    },
                    onSelectionChanged: (selected) {
                      setState(() {
                        if (breaking != null) {
                          breaking.direction = selected.first;
                        } else {
                          workingPreset!.topRibbon.direction =
                              selected.first;
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Font size'),
                const SizedBox(width: 12),
                IconButton(
                  key: const Key('editSizeDown'),
                  icon: const Icon(Icons.remove),
                  onPressed: () {
                    setState(() {
                      if (breaking != null) {
                        breaking.fontSize =
                            (breaking.fontSize - 1).clamp(10, 40).toDouble();
                      } else {
                        workingPreset!.topRibbon.fontSize =
                            (workingPreset.topRibbon.fontSize - 1)
                                .clamp(10, 40)
                                .toDouble();
                      }
                    });
                  },
                ),
                Text(
                  (breaking?.fontSize ?? workingPreset!.topRibbon.fontSize)
                      .toInt()
                      .toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  key: const Key('editSizeUp'),
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    setState(() {
                      if (breaking != null) {
                        breaking.fontSize =
                            (breaking.fontSize + 1).clamp(10, 40).toDouble();
                      } else {
                        workingPreset!.topRibbon.fontSize =
                            (workingPreset.topRibbon.fontSize + 1)
                                .clamp(10, 40)
                                .toDouble();
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (breaking != null) ...[
              if (isCombo) ...[
                _switchRow(
                  'Top ticker ribbon',
                  breaking.showTop,
                  (v) => setState(() => breaking.showTop = v),
                ),
                _switchRow(
                  'Middle Urdu ribbon',
                  breaking.showMiddle,
                  (v) => setState(() => breaking.showMiddle = v),
                ),
                _switchRow(
                  'Bottom English ribbon',
                  breaking.showBottom,
                  (v) => setState(() => breaking.showBottom = v),
                ),
              ] else
                _switchRow(
                  'Ticker strip',
                  breaking.showRibbons,
                  (v) => setState(() => breaking.showRibbons = v),
                ),
            ] else ...[
              _switchRow(
                'Top ticker ribbon',
                workingPreset!.topRibbon.enabled,
                (v) => setState(() => workingPreset.topRibbon.enabled = v),
              ),
              _switchRow(
                'Middle Urdu ribbon',
                workingPreset.urduRibbon.enabled,
                (v) => setState(() => workingPreset.urduRibbon.enabled = v),
              ),
              _switchRow(
                'Bottom English ribbon',
                workingPreset.englishRibbon.enabled,
                (v) => setState(
                  () => workingPreset.englishRibbon.enabled = v,
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Lower Third',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _textField(
              key: const Key('editLowerTitleField'),
              label: 'Reporter name',
              controller: _lowerTitleController,
              onChanged: (v) {
                if (breaking != null) {
                  breaking.lowerThirdTitle = v;
                } else {
                  workingPreset!.lowerThirdTitle = v;
                }
              },
            ),
            const SizedBox(height: 8),
            _textField(
              key: const Key('editLowerSubtitleField'),
              label: 'Place',
              controller: _lowerSubtitleController,
              onChanged: (v) {
                if (breaking != null) {
                  breaking.lowerThirdSubtitle = v;
                } else {
                  workingPreset!.lowerThirdSubtitle = v;
                }
              },
            ),
            _switchRow(
              'Lower third dikhayein',
              breaking?.showLowerThird ?? workingPreset!.showLowerThird,
              (v) => setState(() {
                if (breaking != null) {
                  breaking.showLowerThird = v;
                } else {
                  workingPreset!.showLowerThird = v;
                }
              }),
            ),
            const SizedBox(height: 16),
            const Text(
              'Interview name plate',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _textField(
              key: const Key('editInterviewNameField'),
              label: 'Interviewee name',
              controller: _interviewNameController,
              onChanged: (v) {
                if (breaking != null) {
                  breaking.interviewName = v;
                } else {
                  workingPreset!.interviewName = v;
                }
              },
            ),
            const SizedBox(height: 8),
            _textField(
              key: const Key('editInterviewDesignationField'),
              label: 'Designation',
              controller: _interviewDesignationController,
              onChanged: (v) {
                if (breaking != null) {
                  breaking.interviewDesignation = v;
                } else {
                  workingPreset!.interviewDesignation = v;
                }
              },
            ),
            _switchRow(
              'Interview plate dikhayein',
              breaking?.showInterviewPlate ??
                  workingPreset!.showInterviewPlate,
              (v) => setState(() {
                if (breaking != null) {
                  breaking.showInterviewPlate = v;
                } else {
                  workingPreset!.showInterviewPlate = v;
                }
              }),
            ),
            const SizedBox(height: 16),
            const Text(
              'Logo',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    logoPath == null
                        ? 'Logo: default (3D rotate on)'
                        : 'Logo: ${logoPath.split('/').last} (3D rotate on)',
                    style: const TextStyle(color: Colors.grey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('editLogoButton'),
                  onPressed: _pickLogo,
                  child: const Text('Logo badlein'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _switchRow(
              'Intro (10s)',
              breaking?.showIntro ?? workingPreset!.showIntro,
              (v) => setState(() {
                if (breaking != null) {
                  breaking.showIntro = v;
                } else {
                  workingPreset!.showIntro = v;
                }
              }),
            ),
            _switchRow(
              'Outro (3s)',
              breaking?.showOutro ?? workingPreset!.showOutro,
              (v) => setState(() {
                if (breaking != null) {
                  breaking.showOutro = v;
                } else {
                  workingPreset!.showOutro = v;
                }
              }),
            ),
            const SizedBox(height: 16),
            const Text(
              'Picture-in-picture',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'PIP inset preview mein dikhta hai — visual effect '
              'export mein Phase 7 mein lagega.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            _switchRow(
              'PIP on karein',
              breaking?.pipEnabled ?? workingPreset!.pipEnabled,
              (v) => setState(() {
                if (breaking != null) {
                  breaking.pipEnabled = v;
                } else {
                  workingPreset!.pipEnabled = v;
                }
              }),
            ),
            if (breaking?.pipEnabled ?? workingPreset!.pipEnabled) ...[
              Wrap(
                spacing: 8,
                children: ChannelPreset.pipPositionIds.map((id) {
                  final selected =
                      (breaking?.pipPosition ??
                          workingPreset!.pipPosition) ==
                      id;
                  return ChoiceChip(
                    key: Key('editPipPosition-$id'),
                    label: Text(
                      ChannelPreset.pipPositionLabels[id] ?? id,
                    ),
                    selected: selected,
                    onSelected: (_) => setState(() {
                      if (breaking != null) {
                        breaking.pipPosition = id;
                      } else {
                        workingPreset!.pipPosition = id;
                      }
                    }),
                  );
                }).toList(),
              ),
              Row(
                children: [
                  const Text('Size'),
                  Expanded(
                    child: Slider(
                      key: const Key('editPipScaleSlider'),
                      value: breaking?.pipScale ?? workingPreset!.pipScale,
                      min: 0.15,
                      max: 0.5,
                      onChanged: (v) => setState(() {
                        if (breaking != null) {
                          breaking.pipScale = v;
                        } else {
                          workingPreset!.pipScale = v;
                        }
                      }),
                    ),
                  ),
                  Text(
                    '${((breaking?.pipScale ?? workingPreset!.pipScale) * 100).toInt()}%',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Editor panel for a VIDEO intro card (v1.2.0 §2.2): two plain
  /// text boxes — Headline (renders in the template's headline
  /// zone) and Ticker (scrolls on the bottom ribbon band) — plus
  /// the ticker DIRECTION toggle (Left / Right) next to the ticker
  /// box, and the built-in music picker (FREE). Direction defaults
  /// by language (Urdu → Left/RTL, English → Right/LTR) until the
  /// user toggles; the toggle always wins. Everything applies on
  /// "Use template" and persists per project.
  Widget _videoEditorPanel(_LibraryItem item, VideoIntroTemplate video) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Editing: ${item.name}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              video.description,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _textField(
              key: const Key('videoHeadlineField'),
              label: 'Headline',
              controller: _headlineController,
              onChanged: (v) {},
            ),
            const SizedBox(height: 12),
            _textField(
              key: const Key('videoTickerField'),
              label: 'Ticker text',
              controller: _tickerController,
              onChanged: (v) {
                if (_videoDirectionAuto) {
                  _videoDirection = defaultTickerDirectionForText(v);
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Ticker direction'),
                const SizedBox(width: 12),
                Expanded(
                  child: SegmentedButton<RibbonDirection>(
                    key: const Key('videoTickerDirectionButton'),
                    segments: const [
                      ButtonSegment(
                        value: RibbonDirection.rtl,
                        label: Text('Left'),
                        icon: Icon(Icons.arrow_back),
                      ),
                      ButtonSegment(
                        value: RibbonDirection.ltr,
                        label: Text('Right'),
                        icon: Icon(Icons.arrow_forward),
                      ),
                    ],
                    selected: {_videoDirection},
                    onSelectionChanged: (selected) {
                      setState(() {
                        _videoDirectionAuto = false;
                        _videoDirection = selected.first;
                      });
                    },
                  ),
                ),
                TextButton(
                  key: const Key('videoTickerDirectionAuto'),
                  onPressed: () {
                    setState(() {
                      _videoDirectionAuto = true;
                      _videoDirection = defaultTickerDirectionForText(
                        _tickerController.text,
                      );
                    });
                  },
                  child: const Text('Auto'),
                ),
              ],
            ),
            const Text(
              'Default: Urdu ticker Left ki taraf, English Right ki '
              'taraf chalta hai — toggle dabane se aap ki choice '
              'hamesha jeetti hai.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Text(
              'Background music — built-in (FREE)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('videoMusic-none'),
                  label: const Text('No music'),
                  selected: _videoMusicAsset == null,
                  onSelected: (_) =>
                      setState(() => _videoMusicAsset = null),
                ),
                ...BuiltInNewsMusic.defaults().map((music) {
                  return ChoiceChip(
                    key: Key('videoMusic-${music.id}'),
                    label: Text('${music.label} • FREE'),
                    selected: _videoMusicAsset == music.assetPath,
                    onSelected: (_) => setState(
                      () => _videoMusicAsset = music.assetPath,
                    ),
                  );
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Editor panel for a category card: category label, base kind
  /// (Final / Breaking / Classic), breaking variant when breaking,
  /// per-ribbon colours, interview plate, intro/outro. Ribbon texts
  /// are NOT edited here — they come from the channel preset /
  /// project (the RIBBON-CONTENT RULE: texts are per-story, the
  /// template only sets kind + colours + label).
  Widget _categoryEditorPanel(_LibraryItem item, CategoryTemplate category) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Editing: ${item.name}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _textField(
              key: const Key('editCategoryField'),
              label: 'Category label (e.g. SPORTS)',
              controller: _categoryController,
              onChanged: (v) {
                category.categoryLabel = v;
                setState(() {});
              },
            ),
            const SizedBox(height: 4),
            const Text(
              'Ribbon content fixed hai — top = current story, middle '
              'Urdu = national news, bottom English = international. '
              'Ribbon texts channel preset / project se aate hain.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Text(
              'Base template',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ('nigraanFinal', 'Final 3-Ribbon'),
                ('breaking', 'Breaking'),
                ('classic', 'Classic'),
              ].map((kind) {
                return ChoiceChip(
                  key: Key('editCategoryKind-${kind.$1}'),
                  label: Text(kind.$2),
                  selected: category.templateKind == kind.$1,
                  onSelected: (_) =>
                      setState(() => category.templateKind = kind.$1),
                );
              }).toList(),
            ),
            if (category.templateKind == 'breaking') ...[
              const SizedBox(height: 12),
              const Text(
                'Breaking variant',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: BreakingVariant.values.map((variant) {
                  return ChoiceChip(
                    key: Key('editCategoryVariant-${variant.id}'),
                    label: Text(variant.label),
                    selected: category.breakingVariant == variant.id,
                    onSelected: (_) => setState(
                      () => category.breakingVariant = variant.id,
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Ribbon colours',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _colorRow('Top ticker', () => category.topColor,
                (c) => category.topColor = c),
            _colorRow('Middle Urdu', () => category.middleColor,
                (c) => category.middleColor = c),
            _colorRow('Bottom English', () => category.bottomColor,
                (c) => category.bottomColor = c),
            const SizedBox(height: 12),
            _switchRow(
              'Interview name plate',
              category.showInterviewPlate,
              (v) => setState(() => category.showInterviewPlate = v),
            ),
            _switchRow(
              'Intro (10s)',
              category.showIntro,
              (v) => setState(() => category.showIntro = v),
            ),
            _switchRow(
              'Outro (3s)',
              category.showOutro,
              (v) => setState(() => category.showOutro = v),
            ),
          ],
        ),
      ),
    );
  }

  /// Settings summary for the "Save as Custom Template" row: exactly
  /// what will be saved from the selected card's working copy
  /// (ribbons, colours, speed, logo, intro/outro, lower third).
  String _settingsSummaryText() {
    String hex(int c) =>
        '#${c.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
    final video = _workingVideo;
    if (video != null) {
      final music = BuiltInNewsMusic.fromAsset(_videoMusicAsset);
      return 'Video intro: ${video.displayName} (FREE) • '
          'Headline: ${_headlineController.text.isEmpty ? '(none)' : _headlineController.text} • '
          'Ticker: ${_tickerController.text.isEmpty ? '(none)' : _tickerController.text} • '
          'Direction: ${_videoDirection == RibbonDirection.rtl ? 'Left' : 'Right'}${_videoDirectionAuto ? ' (auto)' : ''} • '
          'Music: ${music == null ? 'none' : '${music.label} (FREE)'}';
    }
    final category = _workingCategory;
    if (category != null) {
      final kind = category.templateKind == 'breaking'
          ? 'Breaking • ${BreakingVariant.fromId(category.breakingVariant).label}'
          : category.templateKind == 'classic'
              ? 'Classic'
              : 'Final 3-Ribbon';
      return 'Kind: $kind • Label: ${category.categoryLabel.isEmpty ? '(none)' : category.categoryLabel} • '
          'Colours: Top ${hex(category.topColor)}, Middle ${hex(category.middleColor)}, Bottom ${hex(category.bottomColor)} • '
          'Interview plate: ${category.showInterviewPlate ? 'on' : 'off'} • '
          'Intro: ${category.showIntro ? 'on' : 'off'} • Outro: ${category.showOutro ? 'on' : 'off'}';
    }
    final breaking = _workingBreaking;
    if (breaking != null) {
      return 'Headline: ${breaking.headline.isEmpty ? '(none)' : breaking.headline} • '
          'Ticker: ${breaking.tickerText.isEmpty ? '(none)' : breaking.tickerText} • '
          'Colours: Top ${hex(breaking.topColor)}, Middle ${hex(breaking.middleColor)}, Bottom ${hex(breaking.bottomColor)} • '
          'Speed: ${breaking.speed.toStringAsFixed(1)}× • Direction: ${breaking.direction.id} • '
          'Font size: ${breaking.fontSize.toInt()} • '
          'Logo: ${breaking.logoPath == null ? 'default' : breaking.logoPath!.split('/').last} • '
          'Intro: ${breaking.showIntro ? 'on' : 'off'} • Outro: ${breaking.showOutro ? 'on' : 'off'} • '
          'Lower third: ${breaking.lowerThirdTitle.isEmpty ? '(none)' : breaking.lowerThirdTitle}';
    }
    final wp = _workingPreset;
    if (wp != null) {
      return 'Ribbons: Top ${hex(wp.topRibbon.color)} (${wp.topRibbon.enabled ? 'on' : 'off'}), '
          'Middle ${hex(wp.urduRibbon.color)} (${wp.urduRibbon.enabled ? 'on' : 'off'}), '
          'Bottom ${hex(wp.englishRibbon.color)} (${wp.englishRibbon.enabled ? 'on' : 'off'}) • '
          'Speed: ${wp.topRibbon.speed.toStringAsFixed(1)}× • Direction: ${wp.topRibbon.direction.id} • '
          'Font size: ${wp.topRibbon.fontSize.toInt()} • '
          'Logo: ${wp.logoPath == null ? 'default' : wp.logoPath!.split('/').last} • '
          'Intro: ${wp.showIntro ? 'on' : 'off'} • Outro: ${wp.showOutro ? 'on' : 'off'} • '
          'Lower third: ${wp.lowerThirdTitle.isEmpty ? '(none)' : wp.lowerThirdTitle}';
    }
    return '';
  }

  /// One colour row: label + 5 swatches. [get]/[set] read and write
  /// the colour on the working template/preset.
  Widget _colorRow(
    String label,
    int Function() get,
    void Function(int) set,
  ) {
    final current = get();
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
            children: kRibbonSwatches.map((c) {
              final selected = current == c;
              return InkWell(
                key: Key('swatch-$label-$c'),
                onTap: () => setState(() => set(c)),
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

  /// The editable colour rows for the selected card — only the
  /// colours the variant actually has (no fake rows: a variant
  /// without a middle ribbon has no middle colour row).
  List<Widget> _colorRows(
    BreakingTemplate? breaking,
    ChannelPreset? workingPreset,
  ) {
    if (breaking != null) {
      switch (breaking.variant) {
        case BreakingVariant.breakingRedBanner:
          return [
            _colorRow('Banner', () => breaking.topColor,
                (c) => breaking.topColor = c),
            _colorRow('Ticker strip', () => breaking.bottomColor,
                (c) => breaking.bottomColor = c),
          ];
        case BreakingVariant.latestNews:
          return [
            _colorRow('Top bar', () => breaking.topColor,
                (c) => breaking.topColor = c),
            _colorRow('Ticker strip', () => breaking.bottomColor,
                (c) => breaking.bottomColor = c),
          ];
        case BreakingVariant.topHeadlineBar:
          return [
            _colorRow('Headline bar', () => breaking.topColor,
                (c) => breaking.topColor = c),
            _colorRow('Ticker strip', () => breaking.bottomColor,
                (c) => breaking.bottomColor = c),
          ];
        case BreakingVariant.breakingTickerCombo:
          return [
            _colorRow('Banner', () => breaking.topColor,
                (c) => breaking.topColor = c),
            _colorRow('Top ticker', () => breaking.tickerColor,
                (c) => breaking.tickerColor = c),
            _colorRow('Middle Urdu', () => breaking.middleColor,
                (c) => breaking.middleColor = c),
            _colorRow('Bottom English', () => breaking.bottomColor,
                (c) => breaking.bottomColor = c),
          ];
      }
    }
    final wp = workingPreset!;
    return [
      _colorRow('Top ticker', () => wp.topRibbon.color,
          (c) => wp.topRibbon.color = c),
      _colorRow('Middle Urdu', () => wp.urduRibbon.color,
          (c) => wp.urduRibbon.color = c),
      _colorRow('Bottom English', () => wp.englishRibbon.color,
          (c) => wp.englishRibbon.color = c),
    ];
  }

  Widget _textField({
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

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(label),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }
}
