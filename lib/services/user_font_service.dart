/// User-uploaded fonts (fix #51) — the SHARED service behind every
/// "Apna Font" picker in TJ Pro.
///
/// The user picks any `.ttf` / `.otf` file (file_picker, already a
/// dependency); this service validates it, copies it into the app
/// documents directory, registers it at runtime via [FontLoader] —
/// the exact mechanism the Kasheeda house font uses
/// (`AssetDownloadService.loadKasheedaFontFromFile`) — and mirrors it
/// into [UrduFonts.userFonts] so every existing picker / preview /
/// exporter that reads the font registry sees it with no extra
/// wiring.
///
/// Storage layout (all inside the app documents directory):
///
///   user_fonts/
///     user_fonts.json   — registry: [{id, name, family, fileName}]
///     userfont_<id>.ttf — the copied font files
///
/// Failure discipline: [loadAll], [deleteFont] and
/// [syncIntoRegistry] NEVER throw (a broken registry or a missing
/// file must not break app startup or any picker). Only [addFont]
/// throws, and only [UserFontException] with a Roman-Urdu message the
/// UI can show verbatim.
///
/// Registry integration lives HERE, not in `font_registry.dart`:
/// this file imports the registry and converts [UserFont] →
/// [UrduFontOption] via [UserFontService.optionFor]; the registry
/// never imports this service (no import cycle).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'font_registry.dart';

/// One user-uploaded font, as persisted in `user_fonts.json`.
class UserFont {
  const UserFont({
    required this.id,
    required this.name,
    required this.family,
    required this.fileName,
  });

  /// Stable unique id (timestamp + counter at add time).
  final String id;

  /// Display name shown in pickers (picked file's base name, with a
  /// ` (2)` / ` (3)` suffix when the name was already taken).
  final String name;

  /// The FontLoader family this font is registered under
  /// (`UserFont_<sanitized id>` — unique per font, so two uploads of
  /// the same typeface never collide in the engine).
  final String family;

  /// File name (not a path) inside the `user_fonts/` folder.
  final String fileName;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'family': family,
        'fileName': fileName,
      };

  factory UserFont.fromJson(Map<String, dynamic> json) => UserFont(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        family: json['family'] as String? ?? '',
        fileName: json['fileName'] as String? ?? '',
      );
}

/// Thrown by [UserFontService.addFont] only. [message] is
/// user-readable Roman Urdu — the UI shows it as-is.
class UserFontException implements Exception {
  UserFontException(this.message);
  final String message;
  @override
  String toString() => 'UserFontException: $message';
}

/// Singleton service — use [UserFontService.instance].
class UserFontService {
  UserFontService._();

  static final UserFontService instance = UserFontService._();

  static const String _folderName = 'user_fonts';
  static const String _registryFileName = 'user_fonts.json';

  /// In-memory copy of the registry (last [loadAll] / mutation wins).
  List<UserFont> _fonts = <UserFont>[];

  /// Monotonic counter folded into ids / family names so two fonts
  /// added in the same millisecond still get unique names.
  int _counter = 0;

  /// Families already registered with [FontLoader] in this process.
  /// FontLoader has no unregister and re-loading the same family is
  /// wasteful, so [loadAll] skips families already in this set (the
  /// same process-level guard the Kasheeda loader uses).
  final Set<String> _registeredFamilies = <String>{};

  /// The fonts from the last [loadAll] / [addFont] / [deleteFont].
  List<UserFont> get fonts => List<UserFont>.unmodifiable(_fonts);

  // ------------------------------------------------------------------
  // Conversion to the shared registry (kept here — see library doc).
  // ------------------------------------------------------------------

  /// The [UrduFontOption] a picker shows for [font]. Its registry id
  /// is `user:<UserFont.id>`, so saved settings can never collide
  /// with a built-in font id.
  static UrduFontOption optionFor(UserFont font) => UrduFontOption(
        id: 'user:${font.id}',
        name: font.name,
        familyLabel: font.family,
        isBundled: false,
        script: 'Apna Font',
        apply: (base) => base.copyWith(fontFamily: font.family),
      );

  // ------------------------------------------------------------------
  // Storage helpers.
  // ------------------------------------------------------------------

  Future<Directory> _storageDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _folderName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Parses `user_fonts.json`; fail-soft — any problem reads as an
  /// empty registry.
  Future<List<UserFont>> _readEntries() async {
    try {
      final dir = await _storageDir();
      final file = File(p.join(dir.path, _registryFileName));
      if (!await file.exists()) return <UserFont>[];
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return <UserFont>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <UserFont>[];
      final entries = <UserFont>[];
      for (final item in decoded) {
        try {
          if (item is Map<String, dynamic>) {
            entries.add(UserFont.fromJson(item));
          }
        } catch (_) {
          // One malformed entry must not lose the rest.
        }
      }
      return entries;
    } catch (_) {
      return <UserFont>[];
    }
  }

  Future<void> _writeEntries(List<UserFont> entries) async {
    final dir = await _storageDir();
    final file = File(p.join(dir.path, _registryFileName));
    final payload =
        jsonEncode(entries.map((f) => f.toJson()).toList(growable: false));
    await file.writeAsString(payload, flush: true);
  }

  // ------------------------------------------------------------------
  // FontLoader registration (same mechanism as the Kasheeda loader).
  // ------------------------------------------------------------------

  Future<void> _registerFont(String family, File file) async {
    if (_registeredFamilies.contains(family)) return;
    final bytes = await file.readAsBytes();
    final loader = FontLoader(family);
    loader.addFont(
      Future<ByteData>.value(
        ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
    await loader.load();
    _registeredFamilies.add(family);
  }

  // ------------------------------------------------------------------
  // Public API.
  // ------------------------------------------------------------------

  /// Reads the registry and registers every font whose file still
  /// exists. Entries whose file is gone (or whose font fails to
  /// register) are dropped and the registry is re-saved without them.
  /// NEVER throws — returns whatever loaded.
  Future<List<UserFont>> loadAll() async {
    try {
      final dir = await _storageDir();
      final entries = await _readEntries();
      final loaded = <UserFont>[];
      var droppedAny = false;
      for (final font in entries) {
        try {
          final file = File(p.join(dir.path, font.fileName));
          if (!await file.exists()) {
            droppedAny = true;
            continue;
          }
          await _registerFont(font.family, file);
          loaded.add(font);
        } catch (_) {
          droppedAny = true;
        }
      }
      _fonts = loaded;
      if (droppedAny) {
        try {
          await _writeEntries(loaded);
        } catch (_) {
          // Re-save is best-effort; the in-memory list is already right.
        }
      }
      return List<UserFont>.of(loaded);
    } catch (_) {
      return List<UserFont>.of(_fonts);
    }
  }

  /// Validates [picked], copies it into storage, registers it and
  /// persists it. Throws [UserFontException] (Roman-Urdu message) when
  /// the file is not a real `.ttf` / `.otf` font or the engine refuses
  /// to load it.
  Future<UserFont> addFont(File picked) async {
    // 1) Extension gate (case-insensitive).
    final ext = p.extension(picked.path).toLowerCase();
    if (ext != '.ttf' && ext != '.otf') {
      throw UserFontException(
        'Ye file sahi font nahi hai — .ttf ya .otf chunein.',
      );
    }

    // 2) Content gate: read the bytes once (they are reused for the
    //    copy below) and check the sfnt magic — a renamed non-font
    //    file must not reach FontLoader or storage.
    final Uint8List bytes;
    try {
      bytes = await picked.readAsBytes();
    } catch (_) {
      throw UserFontException(
        'Ye file sahi font nahi hai — .ttf ya .otf chunein.',
      );
    }
    if (!_hasSfntMagic(bytes)) {
      throw UserFontException(
        'Ye file sahi font nahi hai — .ttf ya .otf chunein.',
      );
    }

    // 3) Identity: unique id / family / stored file name, and a
    //    display name deduplicated with ` (2)`, ` (3)`, …
    final existing = await _readEntries();
    var displayName = p.basenameWithoutExtension(picked.path).trim();
    if (displayName.isEmpty) displayName = 'Apna Font';
    final takenNames = existing.map((f) => f.name).toSet();
    if (takenNames.contains(displayName)) {
      var suffix = 2;
      while (takenNames.contains('$displayName ($suffix)')) {
        suffix++;
      }
      displayName = '$displayName ($suffix)';
    }
    _counter++;
    final rawId =
        '${DateTime.now().millisecondsSinceEpoch}_$_counter';
    final id = rawId.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    final family = 'UserFont_$id';
    final storedFileName = 'userfont_$id$ext';

    // 4) Copy into storage, THEN register — if the engine refuses the
    //    font, the copy is deleted again so storage never keeps a
    //    font the pickers cannot render.
    final dir = await _storageDir();
    final dest = File(p.join(dir.path, storedFileName));
    await dest.writeAsBytes(bytes, flush: true);
    try {
      await _registerFont(family, dest);
    } catch (_) {
      try {
        await dest.delete();
      } catch (_) {
        // Best-effort cleanup; the exception below is what matters.
      }
      throw UserFontException(
        'Font load nahi ho saka — file kharab lagti hai.',
      );
    }

    // 5) Persist and return.
    final font = UserFont(
      id: id,
      name: displayName,
      family: family,
      fileName: storedFileName,
    );
    _fonts = <UserFont>[...existing, font];
    await _writeEntries(_fonts);
    return font;
  }

  /// Removes [font]'s file and registry entry, and drops it from
  /// [UrduFonts.userFonts] when present. Fail-soft — never throws.
  /// (FontLoader itself has no unregister API, so the family stays
  /// registered in the engine until the process restarts; it simply
  /// disappears from every picker and from [UrduFonts.byId].)
  Future<void> deleteFont(UserFont font) async {
    try {
      final dir = await _storageDir();
      final entries = await _readEntries();
      entries.removeWhere((f) => f.id == font.id);
      _fonts = entries;
      try {
        await _writeEntries(entries);
      } catch (_) {
        // Registry re-save is best-effort.
      }
      UrduFonts.userFonts.removeWhere((o) => o.id == 'user:${font.id}');
      final file = File(p.join(dir.path, font.fileName));
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // A stuck file is harmless — its registry entry is gone.
      }
    } catch (_) {
      // Fail-soft by contract.
    }
  }

  /// Loads every stored font and rebuilds [UrduFonts.userFonts] from
  /// them, so pickers that iterate [UrduFonts.allWithUser] (or look up
  /// `user:…` ids via [UrduFonts.byId]) see the current set. Call once
  /// at startup and after each add / delete. Never throws.
  Future<void> syncIntoRegistry() async {
    final loaded = await loadAll();
    UrduFonts.userFonts
      ..clear()
      ..addAll(loaded.map(optionFor));
  }

  // ------------------------------------------------------------------
  // Validation.
  // ------------------------------------------------------------------

  /// sfnt magic check — the first 4 bytes of every real TTF / OTF /
  /// TTC font are one of: `0x00010000` (TrueType outlines), `OTTO`
  /// (CFF / OpenType), `true` (legacy Apple TrueType) or `ttcf`
  /// (TrueType Collection).
  static bool _hasSfntMagic(Uint8List bytes) {
    if (bytes.length < 4) return false;
    if (bytes[0] == 0x00 &&
        bytes[1] == 0x01 &&
        bytes[2] == 0x00 &&
        bytes[3] == 0x00) {
      return true;
    }
    final tag = String.fromCharCodes(bytes.sublist(0, 4));
    return tag == 'OTTO' || tag == 'true' || tag == 'ttcf';
  }
}
