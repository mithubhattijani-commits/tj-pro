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

/// Shows the Templates picker; returns null when dismissed.
Future<TemplatePick?> showTemplatesPicker(
  BuildContext context, {
  required String currentKind,
  required bool currentIsFinal3,
}) {
  String label(TemplatePick pick) => switch (pick) {
        TemplatePick.final3 => 'Final 3-Ribbon (yellow / red / navy)',
        TemplatePick.classic2 => 'Classic 2-Ribbon',
        TemplatePick.breaking => 'Breaking',
        TemplatePick.classic => 'Classic template',
        TemplatePick.store => 'Online Store — Templates',
        TemplatePick.library => 'Templates Library (breaking)',
      };
  IconData icon(TemplatePick pick) => switch (pick) {
        TemplatePick.final3 => Icons.view_agenda,
        TemplatePick.classic2 => Icons.view_stream,
        TemplatePick.breaking => Icons.flash_on,
        TemplatePick.classic => Icons.web_asset,
        TemplatePick.store => Icons.storefront,
        TemplatePick.library => Icons.dashboard_customize,
      };
  bool selected(TemplatePick pick) => switch (pick) {
        TemplatePick.final3 =>
          currentKind == 'nigraanFinal' && currentIsFinal3,
        TemplatePick.classic2 =>
          currentKind == 'nigraanFinal' && !currentIsFinal3,
        TemplatePick.breaking => currentKind == 'breaking',
        TemplatePick.classic => currentKind == 'classic',
        TemplatePick.store => false,
        TemplatePick.library => false,
      };
  return showModalBottomSheet<TemplatePick>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text(
              'Template chunein',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          for (final pick in TemplatePick.values)
            ListTile(
              leading: Icon(icon(pick)),
              title: Text(label(pick)),
              trailing: selected(pick) ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, pick),
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
        children: [
          const ListTile(
            title: Text(
              'Ribbons chunein',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.view_agenda),
            title: const Text('Final design (yellow / red / navy)'),
            trailing: currentIsFinal3 ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(ctx, RibbonPick.finalDesign),
          ),
          ListTile(
            leading: const Icon(Icons.view_stream),
            title: const Text('Classic design (blue / red)'),
            trailing: !currentIsFinal3 ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(ctx, RibbonPick.classicDesign),
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Apne rang / text / speed'),
            subtitle: const Text(
              'Template & Studio mein har ribbon edit karein',
            ),
            onTap: () => Navigator.pop(ctx, RibbonPick.studio),
          ),
          ListTile(
            leading: const Icon(Icons.storefront),
            title: const Text('Online Store — Ribbons'),
            subtitle: const Text(
              'Store ke ribbon packs — naye packs auto aa jate hain',
            ),
            onTap: () => Navigator.pop(ctx, RibbonPick.store),
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
