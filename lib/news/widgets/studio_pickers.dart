/// Shared News Studio pickers (v1.5.0, fix #32) — ONE implementation
/// used by both the News Studio home and the News Maker, so the
/// Templates / Ribbons choices can never drift apart (dedupe rule).
///
/// Templates: the built-in designs (Final 3-Ribbon, Classic
/// 2-Ribbon, Breaking, Classic) plus the Online Store's Templates
/// section and the breaking Templates Library.
/// Ribbons: the built-in design variants (Final colours, Classic
/// colours — applied by resetting the preset's ribbon colours to
/// the factory values the design resolver keys off), the deep
/// editor (Template & Studio), and the Online Store's Ribbons
/// category (Drive items appear there automatically).
library;

import 'package:flutter/material.dart';

import '../channel_preset.dart';
import '../store_screen.dart';
import '../template_studio_screen.dart';
import '../templates_library_screen.dart';

/// What the user picked in the Templates sheet.
enum TemplatePick { final3, classic2, breaking, classic, store, library }

/// The ONE display label for a template selection (v1.5.2, fixes
/// #57/#62b/#63b — the coherence rule): derived from BOTH switches
/// that decide the render — the project's template kind AND the
/// preset's Final variant — so a header can never claim
/// 'Final 3-Ribbon' while the Classic 2-Ribbon design is what
/// actually renders. Every surface (Maker header, Template /
/// Ribbons pickers, AI News Maker) derives its label here.
String templateDisplayLabel({
  required String templateKind,
  required bool isFinal3,
  String breakingVariantLabel = '',
}) {
  switch (templateKind) {
    case 'nigraanFinal':
      return isFinal3 ? 'Final 3-Ribbon' : 'Classic 2-Ribbon';
    case 'breaking':
      return breakingVariantLabel.isEmpty
          ? 'Breaking'
          : 'Breaking • $breakingVariantLabel';
    default:
      return 'Classic';
  }
}

/// Whether [pick] is the current template selection.
bool templatePickSelected(
  TemplatePick pick, {
  required String currentKind,
  required bool currentIsFinal3,
}) =>
    switch (pick) {
      TemplatePick.final3 =>
        currentKind == 'nigraanFinal' && currentIsFinal3,
      TemplatePick.classic2 =>
        currentKind == 'nigraanFinal' && !currentIsFinal3,
      TemplatePick.breaking => currentKind == 'breaking',
      TemplatePick.classic => currentKind == 'classic',
      TemplatePick.store => false,
      TemplatePick.library => false,
    };

String templatePickLabel(TemplatePick pick) => switch (pick) {
      TemplatePick.final3 => 'Final 3-Ribbon',
      TemplatePick.classic2 => 'Classic 2-Ribbon',
      TemplatePick.breaking => 'Breaking',
      TemplatePick.classic => 'Classic template',
      TemplatePick.store => 'Online Store',
      TemplatePick.library => 'Templates Library',
    };

/// A mini ribbon-stack preview drawn in the design's REAL
/// colours — the visual half of a picker card (v1.5.2, fixes
/// #62a/#63a: designs are chosen by looking at them, in a line,
/// like the editors' thumbnail rails — never from a text list).
Widget ribbonStackPreview(List<(int, double)> bands) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Container(
      width: 76,
      height: 48,
      color: const Color(0xFF101018),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (final (argb, h) in bands)
            Container(height: h, color: Color(argb)),
        ],
      ),
    ),
  );
}

/// The mini preview for one Templates card.
Widget templatePickPreview(TemplatePick pick) => switch (pick) {
      TemplatePick.final3 => ribbonStackPreview(const [
          (kFinal3TopColor, 9.0),
          (kFinal3UrduColor, 14.0),
          (kFinal3EnglishColor, 10.0),
        ]),
      TemplatePick.classic2 => ribbonStackPreview(const [
          (kFactoryUrduRibbonColor, 13.0),
          (kFactoryEnglishRibbonColor, 13.0),
        ]),
      TemplatePick.breaking => ribbonStackPreview(const [
          (0xFF202028, 12.0),
          (0xFFEF0017, 12.0),
        ]),
      TemplatePick.classic => ribbonStackPreview(const [
          (kFactoryTopRibbonColor, 11.0),
          (kFactoryEnglishRibbonColor, 11.0),
        ]),
      TemplatePick.store => const SizedBox(
          width: 76,
          height: 48,
          child: Icon(Icons.storefront_outlined, color: Colors.white70),
        ),
      TemplatePick.library => const SizedBox(
          width: 76,
          height: 48,
          child: Icon(Icons.dashboard_customize_outlined,
              color: Colors.white70),
        ),
    };

/// One visual picker card (editors' rail pattern): preview on
/// top, label under it, gold border + check when selected.
Widget designCard({
  required Widget preview,
  required String label,
  required bool selected,
  required VoidCallback onTap,
  Key? cardKey,
}) {
  return InkWell(
    key: cardKey,
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      width: 92,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFF181828),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? const Color(0xFFF5C542) : Colors.white24,
          width: selected ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          preview,
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 3),
                const Icon(Icons.check, size: 13, color: Color(0xFFF5C542)),
              ],
            ],
          ),
        ],
      ),
    ),
  );
}

/// The Templates designs as ONE horizontal rail of visual cards
/// (v1.5.2, fix #63a) — used by the Templates sheet AND inline in
/// the Maker's Template panel, so the choice looks and behaves
/// identically everywhere.
Widget templateDesignRail({
  required String currentKind,
  required bool currentIsFinal3,
  required ValueChanged<TemplatePick> onPick,
}) {
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final pick in TemplatePick.values) ...[
          designCard(
            cardKey: Key('templateCard-${pick.name}'),
            preview: templatePickPreview(pick),
            label: templatePickLabel(pick),
            selected: templatePickSelected(
              pick,
              currentKind: currentKind,
              currentIsFinal3: currentIsFinal3,
            ),
            onTap: () => onPick(pick),
          ),
          const SizedBox(width: 8),
        ],
      ],
    ),
  );
}

/// Shows the Templates picker; returns null when dismissed.
Future<TemplatePick?> showTemplatesPicker(
  BuildContext context, {
  required String currentKind,
  required bool currentIsFinal3,
}) {
  return showModalBottomSheet<TemplatePick>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            title: Text(
              'Template chunein',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 16),
            child: templateDesignRail(
              currentKind: currentKind,
              currentIsFinal3: currentIsFinal3,
              onPick: (pick) => Navigator.pop(ctx, pick),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Applies a Templates-sheet pick that is a NAVIGATION (store /
/// library). Returns true when it navigated (the caller then does
/// not treat the pick as a design change).
Future<bool> openTemplatePickDestination(
  BuildContext context,
  TemplatePick pick,
) async {
  switch (pick) {
    case TemplatePick.store:
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const StoreScreen(initialCategory: 'Templates'),
        ),
      );
      return true;
    case TemplatePick.library:
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const TemplatesLibraryScreen(),
        ),
      );
      return true;
    case TemplatePick.final3:
    case TemplatePick.classic2:
    case TemplatePick.breaking:
    case TemplatePick.classic:
      return false;
  }
}

/// What the user picked in the Ribbons sheet.
enum RibbonPick { finalDesign, classicDesign, studio, store }

/// The mini preview for one Ribbons-design card — the design's
/// real ribbon stack.
Widget ribbonPickPreview(RibbonPick pick) => switch (pick) {
      RibbonPick.finalDesign => ribbonStackPreview(const [
          (kFinal3TopColor, 9.0),
          (kFinal3UrduColor, 14.0),
          (kFinal3EnglishColor, 10.0),
        ]),
      RibbonPick.classicDesign => ribbonStackPreview(const [
          (kFactoryUrduRibbonColor, 13.0),
          (kFactoryEnglishRibbonColor, 13.0),
        ]),
      RibbonPick.studio => const SizedBox(
          width: 76,
          height: 48,
          child: Icon(Icons.tune_outlined, color: Colors.white70),
        ),
      RibbonPick.store => const SizedBox(
          width: 76,
          height: 48,
          child: Icon(Icons.storefront_outlined, color: Colors.white70),
        ),
    };

String ribbonPickLabel(RibbonPick pick) => switch (pick) {
      RibbonPick.finalDesign => 'Final design',
      RibbonPick.classicDesign => 'Classic design',
      RibbonPick.studio => 'Apne rang',
      RibbonPick.store => 'Online Store',
    };

/// The Ribbons designs as ONE horizontal rail of visual cards
/// (v1.5.2, fix #62a) — used by the Ribbons sheet AND inline in
/// the Maker's Ribbons panel. A design card reads selected only
/// when the Final template family is the project's kind AND the
/// variant matches — the coherence rule (#62b): the cards can
/// never claim a design the preview is not rendering.
Widget ribbonDesignRail({
  required String currentKind,
  required bool currentIsFinal3,
  required ValueChanged<RibbonPick> onPick,
  bool includeStudio = true,
}) {
  bool selected(RibbonPick pick) => switch (pick) {
        RibbonPick.finalDesign =>
          currentKind == 'nigraanFinal' && currentIsFinal3,
        RibbonPick.classicDesign =>
          currentKind == 'nigraanFinal' && !currentIsFinal3,
        RibbonPick.studio => false,
        RibbonPick.store => false,
      };
  final picks = [
    for (final pick in RibbonPick.values)
      if (includeStudio || pick != RibbonPick.studio) pick,
  ];
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final pick in picks) ...[
          designCard(
            cardKey: Key('ribbonCard-${pick.name}'),
            preview: ribbonPickPreview(pick),
            label: ribbonPickLabel(pick),
            selected: selected(pick),
            onTap: () => onPick(pick),
          ),
          const SizedBox(width: 8),
        ],
      ],
    ),
  );
}

/// Shows the Ribbons picker; returns null when dismissed.
Future<RibbonPick?> showRibbonsPicker(
  BuildContext context, {
  required bool currentIsFinal3,
}) {
  return showModalBottomSheet<RibbonPick>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            title: Text(
              'Ribbons chunein',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 16),
            child: ribbonDesignRail(
              currentKind: 'nigraanFinal',
              currentIsFinal3: currentIsFinal3,
              onPick: (pick) => Navigator.pop(ctx, pick),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Applies a built-in ribbon DESIGN to [preset] in place: the
/// design resolver keys off the factory colour values, so a design
/// pick = factory colours + the design variant. A user's custom
/// colours are replaced ONLY by this explicit design pick (the
/// colour pickers in Template & Studio remain the way to customise
/// afterwards).
void applyRibbonDesign(ChannelPreset preset, {required bool final3}) {
  preset.finalVariant = final3 ? kFinalVariant3 : kFinalVariantClassic2;
  preset.topRibbon = preset.topRibbon.copyWith(color: kFactoryTopRibbonColor);
  preset.urduRibbon =
      preset.urduRibbon.copyWith(color: kFactoryUrduRibbonColor);
  preset.englishRibbon =
      preset.englishRibbon.copyWith(color: kFactoryEnglishRibbonColor);
}

/// Applies a Ribbons-sheet pick: design picks mutate + persist the
/// preset via [persistPreset]; navigation picks open their screen.
/// Returns true when the preset changed (caller reloads).
Future<bool> handleRibbonPick(
  BuildContext context,
  RibbonPick pick, {
  required ChannelPreset preset,
  required Future<void> Function() persistPreset,
}) async {
  switch (pick) {
    case RibbonPick.finalDesign:
      applyRibbonDesign(preset, final3: true);
      await persistPreset();
      return true;
    case RibbonPick.classicDesign:
      applyRibbonDesign(preset, final3: false);
      await persistPreset();
      return true;
    case RibbonPick.studio:
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TemplateStudioScreen()),
      );
      return true;
    case RibbonPick.store:
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const StoreScreen(initialCategory: 'Ribbons'),
        ),
      );
      return false;
  }
}

/// Persists [preset] into the preset store (load-all → replace by
/// id → save-all, keeping the current selection). Fail-soft like
/// every preset save in the app.
Future<void> persistPresetChange(ChannelPreset preset) async {
  try {
    final presets = await ChannelPresetStore.loadAll();
    final selectedId = await ChannelPresetStore.loadSelectedId();
    final index = presets.indexWhere((p) => p.id == preset.id);
    if (index >= 0) {
      presets[index] = preset;
    } else {
      presets.add(preset);
    }
    await ChannelPresetStore.saveAll(presets, selectedId: selectedId);
  } catch (_) {
    // A failed save never blocks the in-memory change.
  }
}
