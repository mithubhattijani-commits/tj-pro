/// Caption draft auto-save / restore (Phase 5, ported from Magic
/// Box's `caption_draft_service.dart` — adapted: Magic Box stores
/// drafts in SharedPreferences; TJ Pro stores them as plain JSON in
/// the app documents directory (`caption_drafts/<key>.json`), the
/// same pattern as `news_template.json` / `channel_presets.json`, so
/// no new dependency is needed).
///
/// A draft holds the caption lines + the style settings of one
/// editing session, keyed by the project id (or `'standalone'` for
/// the Caption Studio when no project is open). The Caption Studio
/// saves on every change (debounced) and restores on open; the user
/// can clear it from the export sheet.
///
/// [directoryOverride] is the test seam: unit tests pass a temp dir
/// instead of the real app documents directory.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../news/news_analysis.dart';
import '../services/caption_styles.dart';

/// Everything the Caption Studio needs to restore a session.
class CaptionDraft {
  CaptionDraft({
    required this.lines,
    this.styleId = 'nigraan',
    this.position = CaptionPosition.bottom,
    this.size = CaptionSize.medium,
    this.highlightColor,
    this.fontId = 'jameel_kasheeda',
    this.outline = true,
    this.shadow = false,
    this.background = false,
    this.dualLanguage = false,
  });

  final List<SubtitleLine> lines;
  final String styleId;
  final CaptionPosition position;
  final CaptionSize size;
  final int? highlightColor;
  final String fontId;
  final bool outline;
  final bool shadow;
  final bool background;
  final bool dualLanguage;

  Map<String, dynamic> toJson() => {
        'lines': lines.map((l) => l.toJson()).toList(),
        'styleId': styleId,
        'position': position.name,
        'size': size.name,
        'highlightColor': highlightColor,
        'fontId': fontId,
        'outline': outline,
        'shadow': shadow,
        'background': background,
        'dualLanguage': dualLanguage,
      };

  static CaptionDraft fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'];
    final lines = <SubtitleLine>[];
    if (rawLines is List) {
      for (final l in rawLines) {
        if (l is Map<String, dynamic>) {
          lines.add(SubtitleLine.fromJson(l));
        }
      }
    }
    CaptionPosition positionFrom(String? name) =>
        CaptionPosition.values.firstWhere(
          (v) => v.name == name,
          orElse: () => CaptionPosition.bottom,
        );
    CaptionSize sizeFrom(String? name) => CaptionSize.values.firstWhere(
          (v) => v.name == name,
          orElse: () => CaptionSize.medium,
        );
    return CaptionDraft(
      lines: lines,
      styleId: (json['styleId'] as String?) ?? 'nigraan',
      position: positionFrom(json['position'] as String?),
      size: sizeFrom(json['size'] as String?),
      highlightColor: (json['highlightColor'] as num?)?.toInt(),
      fontId: (json['fontId'] as String?) ?? 'jameel_kasheeda',
      outline: (json['outline'] as bool?) ?? true,
      shadow: (json['shadow'] as bool?) ?? false,
      background: (json['background'] as bool?) ?? false,
      dualLanguage: (json['dualLanguage'] as bool?) ?? false,
    );
  }
}

class CaptionDraftStore {
  CaptionDraftStore({this.directoryOverride});

  /// Test seam — a temp dir instead of the app documents directory.
  final Directory? directoryOverride;

  static const _dirName = 'caption_drafts';

  Future<Directory> _dir() async {
    if (directoryOverride != null) return directoryOverride!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _dirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  File _file(Directory dir, String key) =>
      File(p.join(dir.path, '${_safeKey(key)}.json'));

  static String _safeKey(String key) =>
      key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  /// Saves [draft] under [key]. A failed save never throws (the
  /// in-memory editing keeps working; the next save retries).
  Future<void> save(String key, CaptionDraft draft) async {
    try {
      final dir = await _dir();
      await _file(dir, key).writeAsString(jsonEncode(draft.toJson()));
    } catch (_) {}
  }

  /// Loads the draft for [key], or null when none exists / corrupt.
  Future<CaptionDraft?> load(String key) async {
    try {
      final dir = await _dir();
      final file = _file(dir, key);
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString());
      if (data is Map<String, dynamic>) return CaptionDraft.fromJson(data);
    } catch (_) {}
    return null;
  }

  /// Deletes the draft for [key]. Never throws.
  Future<void> clear(String key) async {
    try {
      final dir = await _dir();
      final file = _file(dir, key);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
