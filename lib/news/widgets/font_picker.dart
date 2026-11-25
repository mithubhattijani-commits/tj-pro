/// Font picker for News Studio text surfaces (v1.5.1, fix #51):
/// a chip wrap over the shared registry — built-ins PLUS the
/// user's own uploaded fonts ([UrduFonts.allWithUser]) — with an
/// "Apna Font lagayen" chip that picks a .ttf/.otf from the phone
/// and registers it through [UserFontService] (copied into app
/// documents, FontLoader-registered, persisted across restarts).
///
/// The service is shared, so the editors' Text tools can mount
/// this same picker in their own steps. Fail-soft by design: an
/// invalid font file surfaces [UserFontException.message] in a
/// SnackBar — never a crash, never a half-registered entry.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/font_registry.dart';
import '../../services/user_font_service.dart';

class NewsFontPicker extends StatelessWidget {
  const NewsFontPicker({
    super.key,
    required this.selectedId,
    required this.onChanged,
  });

  /// The currently selected [UrduFontOption.id] (built-in id or
  /// `user:<id>` for an upload).
  final String selectedId;

  /// Called with the new font id on selection / successful add /
  /// delete-fallback. The caller persists it and rebuilds (the
  /// registry lists are read fresh on every build).
  final ValueChanged<String> onChanged;

  Future<void> _addFont(BuildContext context) async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf'],
    );
    if (picked.isEmpty || picked.first.path == null) return;
    try {
      final font = await UserFontService.instance.addFont(
        File(picked.first.path!),
      );
      await UserFontService.instance.syncIntoRegistry();
      onChanged(UserFontService.optionFor(font).id);
    } on UserFontException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Font add nahi hua: $e')),
        );
      }
    }
  }

  Future<void> _deleteFont(BuildContext context, UrduFontOption option) async {
    final fonts = UserFontService.instance.fonts;
    for (final font in fonts) {
      if (UserFontService.optionFor(font).id == option.id) {
        await UserFontService.instance.deleteFont(font);
        await UserFontService.instance.syncIntoRegistry();
        onChanged(UrduFonts.jameelKasheeda.id);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fonts = UrduFonts.allWithUser;
    // v1.5.2 (fix #60, editors' interface law): ONE horizontal
    // swipeable rail of chips — the same presentation the Video /
    // Photo Editor panels use for every choice row — instead of a
    // multi-row Wrap with uneven rows.
    //
    // Build 12 (point #14e): VISUAL font previews — each chip's
    // label renders the font's own name IN THAT FONT (the Urdu
    // name where the registry carries one, so Kasheeda /
    // Nastaleeq / Naskh chips show their real glyph shapes).
    // The style is built from the option's registered
    // familyLabel DIRECTLY — deliberately NOT
    // UrduFonts.styleFor/apply(): apply() would kick off a
    // runtime download for EVERY Google-font option at panel
    // build (the app only warms the SELECTED fonts — see
    // _warmFont in the Maker). A family the app has already
    // loaded renders in its real face; Kasheeda resolves to
    // the house family the same way.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
        for (final font in fonts) ...[
          ChoiceChip(
            key: Key('fontChoice-${font.id}'),
            label: Text(
              font.nameUr ?? font.name,
              style: TextStyle(
                fontFamily: font.familyLabel,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: selectedId == font.id
                    ? Colors.black
                    : const Color(0xFFC4C9D0),
              ),
            ),
            selected: selectedId == font.id,
            onSelected: (_) => onChanged(font.id),
          ),
          const SizedBox(width: 8),
        ],
        // The selected USER font can be removed again (its file +
        // registry entry go away; surfaces fall back to Kasheeda).
        if (selectedId.startsWith('user:')) ...[
          ActionChip(
            key: const Key('fontDeleteChip'),
            avatar: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Font hatayein'),
            onPressed: () {
              for (final font in fonts) {
                if (font.id == selectedId) {
                  _deleteFont(context, font);
                  break;
                }
              }
            },
          ),
          const SizedBox(width: 8),
        ],
        ActionChip(
          key: const Key('fontAddChip'),
          avatar: const Icon(Icons.add, size: 16),
          label: const Text('Apna Font lagayen'),
          onPressed: () => _addFont(context),
        ),
        ],
      ),
    );
  }
}
