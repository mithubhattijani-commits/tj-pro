/// Category templates for News Studio (Phase 8, master prompt §8).
///
/// One REAL template variant per each of the 13 v1 categories
/// (Breaking, Pakistan, International, Political, Sports, Business,
/// Technology, Weather, Crime, Special Reports, Documentary,
/// Interview, News Bulletins) — so no category in the Templates
/// Library is ever an empty list. A category template is a named
/// preset snapshot: which base renderer it uses (Final 3-Ribbon /
/// Classic / one of the four breaking variants), its ribbon colours,
/// its category label and its interview-plate flag. It renders for
/// real: [previewPreset] returns a [ChannelPreset] the existing
/// preview widgets ([NigraanFinalPreview] / [ClassicPreview] /
/// [BreakingTemplatePreview]) and the existing PNG renderers in
/// `lib/live/news_template.dart` ([renderLiveTemplateImage]) already
/// draw — a category template adds NO new renderer, it drives the
/// Phase 6 ones with its own colours + label.
///
/// RIBBON-CONTENT RULE (user, 20 Nov 2026 — binds every phase):
///   TOP ribbon    = CURRENT khabar (us waqt ki story).
///   MIDDLE (Urdu) = NATIONAL NEWS (doosri qomi khabrein — NEVER the
///                     current story).
///   BOTTOM (English) = INTERNATIONAL news.
/// [applyToPreset] changes colours, template kind, variant, label and
/// the interview-plate flag ONLY — it never touches a ribbon's
/// `contentKind` (read-only), and the ribbon texts come from the
/// channel preset / project, never from the template.
///
/// SAVE CUSTOM TEMPLATE: the Templates Library saves the selected
/// category template's current settings under a typed name via
/// [CategoryTemplateStore.saveCustomTemplate]; the saved card appears
/// under its category, is reusable in every project, and is editable
/// (colours / label / kind) + deletable there. Built-ins cannot be
/// deleted (their ids are the category ids, never 'custom_…').
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'channel_preset.dart';
import 'news_project.dart';

/// The 13 v1 category ids (master prompt §8) — same ids as
/// [kTemplateCategories] in `templates_library_screen.dart`.
const List<String> kCategoryTemplateIds = [
  'breaking',
  'pakistan',
  'international',
  'politics',
  'sports',
  'business',
  'technology',
  'weather',
  'crime',
  'special',
  'documentary',
  'interview',
  'bulletins',
];

/// One category template: a base renderer + colours + label.
class CategoryTemplate {
  CategoryTemplate({
    String? id,
    required this.categoryId,
    required this.name,
    this.isCustom = false,
    this.templateKind = 'nigraanFinal',
    this.breakingVariant = 'breakingRedBanner',
    this.topColor = 0xFF01B0FF,
    this.middleColor = 0xFF3D5AFE,
    this.bottomColor = 0xFFEF0017,
    this.tickerColor = 0xFF01B0FF,
    this.categoryLabel = '',
    this.coinCost = 0,
    this.showInterviewPlate = false,
    this.showIntro = true,
    this.showOutro = true,
  }) : id = id ?? categoryId;

  /// Stable id. Built-ins use the category id; saved customs get a
  /// `custom_<millis>` id.
  String id;

  /// Which of the 13 categories this template belongs to.
  String categoryId;

  /// Display name in the Templates Library.
  String name;

  /// True for user-saved custom templates.
  bool isCustom;

  /// Base renderer: 'nigraanFinal' (Final 3-Ribbon) | 'classic' |
  /// 'breaking' (one of the four breaking variants).
  String templateKind;

  /// Breaking variant id, only when [templateKind] is 'breaking'.
  String breakingVariant;

  /// Ribbon colours as ARGB (top ticker / middle Urdu / bottom
  /// English). Changeable per ribbon via the swatch picker.
  int topColor;
  int middleColor;
  int bottomColor;

  /// Top ticker strip colour for the Breaking + Ticker combo variant
  /// (house ticker blue by default).
  int tickerColor;

  /// Category label chip (e.g. 'SPORTS') — the user types it; it is
  /// never invented. Empty = no chip.
  String categoryLabel;

  /// Coin cost to use (0 = free, built-in).
  int coinCost;

  /// Interview name plate flag (the Interview category template).
  /// The plate itself renders only once an interviewee name is set
  /// (on the preset / project) — no name is ever invented here.
  bool showInterviewPlate;

  bool showIntro;
  bool showOutro;

  bool get isFree => coinCost == 0;

  /// The single category this template belongs to.
  List<String> get categories => [categoryId];

  String get displayName => name;

  /// The 13 built-in category defaults — one per category, each
  /// with its own colours + label so every category renders
  /// distinctly. Colour discipline (§14 rule 2): breaking stays red,
  /// ticker blue, Urdu blue, English red — the per-category accent
  /// lives on the TOP ribbon / banner only.
  static List<CategoryTemplate> defaults() {
    return [
      CategoryTemplate(
        categoryId: 'breaking',
        name: 'Breaking News',
        templateKind: 'breaking',
        breakingVariant: 'breakingRedBanner',
        topColor: 0xFFD50000,
        middleColor: 0xFF3D5AFE,
        bottomColor: 0xFF000000,
        categoryLabel: 'BREAKING',
      ),
      CategoryTemplate(
        categoryId: 'pakistan',
        name: 'Pakistan News',
        templateKind: 'nigraanFinal',
        topColor: 0xFF01B0FF,
        middleColor: 0xFF3D5AFE,
        bottomColor: 0xFFEF0017,
        categoryLabel: 'PAKISTAN',
      ),
      CategoryTemplate(
        categoryId: 'international',
        name: 'International News',
        templateKind: 'nigraanFinal',
        topColor: 0xFF1565C0,
        middleColor: 0xFF3D5AFE,
        bottomColor: 0xFFEF0017,
        categoryLabel: 'INTERNATIONAL',
      ),
      CategoryTemplate(
        categoryId: 'politics',
        name: 'Political News',
        templateKind: 'nigraanFinal',
        topColor: 0xFF6A1B9A,
        middleColor: 0xFF3D5AFE,
        bottomColor: 0xFFEF0017,
        categoryLabel: 'POLITICS',
      ),
      CategoryTemplate(
        categoryId: 'sports',
        name: 'Sports News',
        templateKind: 'nigraanFinal',
        topColor: 0xFF2E7D32,
        middleColor: 0xFF1565C0,
        bottomColor: 0xFFEF0017,
        categoryLabel: 'SPORTS',
      ),
      CategoryTemplate(
        categoryId: 'business',
        name: 'Business News',
        templateKind: 'nigraanFinal',
        topColor: 0xFFBF8F00,
        middleColor: 0xFF3D5AFE,
        bottomColor: 0xFFEF0017,
        categoryLabel: 'BUSINESS',
      ),
      CategoryTemplate(
        categoryId: 'technology',
        name: 'Technology News',
        templateKind: 'nigraanFinal',
        topColor: 0xFF7C3AED,
        middleColor: 0xFF3D5AFE,
        bottomColor: 0xFFEF0017,
        categoryLabel: 'TECHNOLOGY',
      ),
      CategoryTemplate(
        categoryId: 'weather',
        name: 'Weather Report',
        templateKind: 'nigraanFinal',
        topColor: 0xFF00838F,
        middleColor: 0xFF1565C0,
        bottomColor: 0xFFEF0017,
        categoryLabel: 'WEATHER',
      ),
      CategoryTemplate(
        categoryId: 'crime',
        name: 'Crime Report',
        templateKind: 'breaking',
        breakingVariant: 'breakingRedBanner',
        topColor: 0xFFD50000,
        middleColor: 0xFF3D5AFE,
        bottomColor: 0xFF000000,
        categoryLabel: 'CRIME',
      ),
      CategoryTemplate(
        categoryId: 'special',
        name: 'Special Report',
        templateKind: 'classic',
        topColor: 0xFF01B0FF,
        middleColor: 0xFF3D5AFE,
        bottomColor: 0xFFEF0017,
        categoryLabel: 'SPECIAL REPORT',
      ),
      CategoryTemplate(
        categoryId: 'documentary',
        name: 'Documentary Report',
        templateKind: 'classic',
        topColor: 0xFF455A64,
        middleColor: 0xFF3D5AFE,
        bottomColor: 0xFFEF0017,
        categoryLabel: 'DOCUMENTARY',
      ),
      CategoryTemplate(
        categoryId: 'interview',
        name: 'Interview',
        templateKind: 'classic',
        topColor: 0xFF01B0FF,
        middleColor: 0xFF3D5AFE,
        bottomColor: 0xFFEF0017,
        categoryLabel: 'INTERVIEW',
        showInterviewPlate: true,
      ),
      CategoryTemplate(
        categoryId: 'bulletins',
        name: 'News Bulletin',
        templateKind: 'breaking',
        breakingVariant: 'topHeadlineBar',
        topColor: 0xFFFFFFFF,
        middleColor: 0xFF3D5AFE,
        bottomColor: 0xFF01B0FF,
        categoryLabel: 'BULLETIN',
      ),
    ];
  }

  /// Applies this template to a channel preset: template kind +
  /// variant, ribbon colours, category label, interview-plate flag,
  /// intro/outro. The ribbon CONTENT KINDS are deliberately NOT
  /// copied — they are read-only (top = current, middle = national,
  /// bottom = international) and a template must never reassign
  /// them. Ribbon texts are NOT copied either — they come from the
  /// preset / project.
  void applyToPreset(ChannelPreset preset) {
    preset.templateKind = templateKind;
    preset.breakingVariant = breakingVariant;
    preset.breakingTickerColor = tickerColor;
    preset.categoryLabel = categoryLabel;
    preset.topRibbon.color = topColor;
    preset.urduRibbon.color = middleColor;
    preset.englishRibbon.color = bottomColor;
    preset.showInterviewPlate = showInterviewPlate;
    preset.showIntro = showIntro;
    preset.showOutro = showOutro;
  }

  /// Applies this template to a project: template kind + variant.
  /// The rest of the project travels through its channel preset
  /// (see [applyToPreset]).
  void applyToProject(NewsProject project) {
    project.templateKind = templateKind;
    project.breakingVariant = breakingVariant;
    if (templateKind == 'breaking') project.breaking = true;
  }

  /// A copy of [base] with this template applied — the preset the
  /// preview widgets and the PNG renderers draw from. Changing the
  /// template changes this copy, so the preview updates.
  ChannelPreset previewPreset(ChannelPreset base) {
    final copy = ChannelPreset.fromJson(base.toJson());
    applyToPreset(copy);
    return copy;
  }

  CategoryTemplate copyWith({
    String? id,
    String? categoryId,
    String? name,
    bool? isCustom,
    String? templateKind,
    String? breakingVariant,
    int? topColor,
    int? middleColor,
    int? bottomColor,
    int? tickerColor,
    String? categoryLabel,
    int? coinCost,
    bool? showInterviewPlate,
    bool? showIntro,
    bool? showOutro,
  }) {
    return CategoryTemplate(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      isCustom: isCustom ?? this.isCustom,
      templateKind: templateKind ?? this.templateKind,
      breakingVariant: breakingVariant ?? this.breakingVariant,
      topColor: topColor ?? this.topColor,
      middleColor: middleColor ?? this.middleColor,
      bottomColor: bottomColor ?? this.bottomColor,
      tickerColor: tickerColor ?? this.tickerColor,
      categoryLabel: categoryLabel ?? this.categoryLabel,
      coinCost: coinCost ?? this.coinCost,
      showInterviewPlate: showInterviewPlate ?? this.showInterviewPlate,
      showIntro: showIntro ?? this.showIntro,
      showOutro: showOutro ?? this.showOutro,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'categoryId': categoryId,
        'name': name,
        'isCustom': isCustom,
        'templateKind': templateKind,
        'breakingVariant': breakingVariant,
        'topColor': topColor,
        'middleColor': middleColor,
        'bottomColor': bottomColor,
        'tickerColor': tickerColor,
        'categoryLabel': categoryLabel,
        'coinCost': coinCost,
        'showInterviewPlate': showInterviewPlate,
        'showIntro': showIntro,
        'showOutro': showOutro,
      };

  static CategoryTemplate fromJson(Map<String, dynamic> json) {
    return CategoryTemplate(
      id: (json['id'] as String?) ?? (json['categoryId'] as String? ?? ''),
      categoryId: (json['categoryId'] as String?) ?? '',
      name: (json['name'] as String?) ?? 'Template',
      isCustom: (json['isCustom'] as bool?) ?? false,
      templateKind: (json['templateKind'] as String?) ?? 'nigraanFinal',
      breakingVariant:
          (json['breakingVariant'] as String?) ?? 'breakingRedBanner',
      topColor: (json['topColor'] as int?) ?? 0xFF01B0FF,
      middleColor: (json['middleColor'] as int?) ?? 0xFF3D5AFE,
      bottomColor: (json['bottomColor'] as int?) ?? 0xFFEF0017,
      tickerColor: (json['tickerColor'] as int?) ?? 0xFF01B0FF,
      categoryLabel: (json['categoryLabel'] as String?) ?? '',
      coinCost: (json['coinCost'] as int?) ?? 0,
      showInterviewPlate: (json['showInterviewPlate'] as bool?) ?? false,
      showIntro: (json['showIntro'] as bool?) ?? true,
      showOutro: (json['showOutro'] as bool?) ?? true,
    );
  }
}

/// JSON store for category templates (same pattern as
/// `BreakingTemplateStore`).
///
/// The file holds ONLY user-saved custom templates; the 13 built-in
/// category defaults are regenerated by [CategoryTemplate.defaults]
/// on every load. [loadAll] returns built-ins first, then customs.
class CategoryTemplateStore {
  static const _fileName = 'category_templates.json';

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  /// Loads the saved custom templates only (empty when none saved yet).
  static Future<List<CategoryTemplate>> loadCustom() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map<String, dynamic>) {
          final raw = data['templates'];
          if (raw is List) {
            final templates = <CategoryTemplate>[];
            for (final item in raw) {
              if (item is Map<String, dynamic>) {
                final t = CategoryTemplate.fromJson(item);
                if (t.isCustom) templates.add(t);
              }
            }
            return templates;
          }
        }
      }
    } catch (_) {}
    return [];
  }

  /// Loads all templates: the 13 built-in category defaults + every
  /// user-saved custom template.
  static Future<List<CategoryTemplate>> loadAll() async {
    return [...CategoryTemplate.defaults(), ...await loadCustom()];
  }

  /// Persists the custom templates from [templates] (built-ins are
  /// regenerated, never stored).
  static Future<void> saveAll(List<CategoryTemplate> templates) async {
    try {
      final file = await _file();
      final customs = templates.where((t) => t.isCustom).toList();
      await file.writeAsString(jsonEncode({
        'templates': customs.map((e) => e.toJson()).toList(),
      }));
    } catch (_) {
      // Template persistence is a convenience; a failed save must never
      // block editing or exporting with the in-memory templates.
    }
  }

  /// SAVE CUSTOM TEMPLATE: saves [template]'s current settings —
  /// base kind, variant, ribbon colours, category label, interview
  /// plate, intro/outro — as a NEW named template ([name]) under its
  /// category that shows up in the Templates Library and is reusable
  /// in every project. Returns the saved copy.
  static Future<CategoryTemplate> saveCustomTemplate({
    required String name,
    required CategoryTemplate template,
  }) async {
    final saved = template.copyWith(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Custom Template' : name.trim(),
      isCustom: true,
    );
    final all = await loadAll();
    all.add(saved);
    await saveAll(all);
    return saved;
  }

  /// Deletes a saved custom template by [id]. Built-ins cannot be
  /// deleted (their ids are category ids, never 'custom_…').
  static Future<void> deleteCustomTemplate(String id) async {
    if (!id.startsWith('custom_')) return;
    final customs = await loadCustom();
    customs.removeWhere((t) => t.id == id);
    await saveAll(customs);
  }
}
