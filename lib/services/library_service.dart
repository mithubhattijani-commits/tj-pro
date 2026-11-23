/// Library engine (v1.5.1, fix #52) — recipe-driven content
/// (Transitions, Text Styles, Effects) read from the SAME public
/// "TJ Pro Store" Drive folder the Online Store uses, so new
/// library content ships with NO new build: drop a correctly
/// shaped item folder into a library category folder and it
/// appears in the News Maker pickers.
///
/// LAYOUT (per category folder — 'Transitions', 'Text Styles',
/// 'Effects' in the store root):
///   `<Category>/<Item Name>/recipe.json`   (required)
///   `<Category>/<Item Name>/<asset files>` (overlay video, …)
///
/// RECIPE FORMAT (minimal, version 1):
/// {
///   "name": "Crossfade",              // display name (required)
///   "category": "Transitions",        // must match its folder
///   "kind": "xfade",                  // see kinds below
///   "params": { ... }                 // kind-specific, below
/// }
/// Kinds + params:
///   Transitions / "xfade":  { "type": "fade", "duration": 0.5,
///                             "easing": "easeInOut" }
///     (type/duration drive ffmpeg's xfade; easing is carried as
///     metadata — xfade has no easing parameter.)
///   Effects / "overlay":    { "asset": "lightleak.mp4",
///                             "blend": "screen", "opacity": 0.55 }
///   Effects / "grade":      { "saturation": 1.15, "contrast": 1.05,
///                             "brightness": 0.02,
///                             "temperature": 0.12, "gamma": 1.0 }
///   Text Styles / "textStyle":
///     { "font": "jameel_kasheeda",        // UrduFonts id or
///                                         // 'user:<id>' (#51)
///       "color": "#F5C542",
///       "labelBackground": "#D50000",
///       "shadow": { "color": "#000000", "blur": 6, "dx": 0, "dy": 2 },
///       "glow":   { "color": "#F5C542", "blur": 12 },
///       "border": { "color": "#000000", "width": 2 },
///       "animationIn": "fade", "animationOut": "fade" }
///
/// Listing route + discipline mirror [StoreService] exactly: the
/// public embedded folder view (no API key in the app),
/// cache-first (SharedPreferences + memory), background refresh,
/// and EVERY failure degrades to cache — an item whose folder,
/// recipe or params do not parse is skipped silently, never
/// thrown at the UI.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'store_service.dart';

/// The library categories — exact subfolder names in the store
/// root. 'Effects' is shared with the Online Store (its stock
/// files stay plain store items; only subfolders carrying a
/// recipe.json are library items).
class LibraryConfig {
  LibraryConfig._();

  static const String transitions = 'Transitions';
  static const String textStyles = 'Text Styles';
  static const String effects = 'Effects';

  static const List<String> categories = <String>[
    transitions,
    textStyles,
    effects,
  ];

  /// Recipe kinds accepted per category — anything else is an
  /// invalid item and is skipped.
  static const Map<String, Set<String>> kindsByCategory =
      <String, Set<String>>{
    transitions: <String>{'xfade'},
    textStyles: <String>{'textStyle'},
    effects: <String>{'overlay', 'grade'},
  };
}

/// A shadow / glow layer of a text style recipe.
class LibraryShadow {
  const LibraryShadow({
    required this.colorArgb,
    required this.blur,
    this.dx = 0,
    this.dy = 0,
  });

  final int colorArgb;
  final double blur;
  final double dx;
  final double dy;

  static LibraryShadow? fromParams(Object? raw) {
    if (raw is! Map) return null;
    final color = parseLibraryColor(raw['color']);
    if (color == null) return null;
    return LibraryShadow(
      colorArgb: color,
      blur: _asDouble(raw['blur'], 0),
      dx: _asDouble(raw['dx'], 0),
      dy: _asDouble(raw['dy'], 0),
    );
  }
}

/// Grading parameters of an Effects 'grade' recipe (also the
/// preview's approximation input — see gradePreviewMatrix in
/// template_media_preview.dart).
class LibraryGrade {
  const LibraryGrade({
    this.saturation = 1,
    this.contrast = 1,
    this.brightness = 0,
    this.temperature = 0,
    this.gamma = 1,
  });

  final double saturation;
  final double contrast;

  /// -1..1 (0 = unchanged), mapped onto eq's -1..1 brightness.
  final double brightness;

  /// -1..1 (negative = cooler, positive = warmer), mapped onto
  /// colorbalance red/blue shifts.
  final double temperature;
  final double gamma;

  bool get isIdentity =>
      saturation == 1 &&
      contrast == 1 &&
      brightness == 0 &&
      temperature == 0 &&
      gamma == 1;

  static LibraryGrade fromParams(Map<String, dynamic> params) {
    return LibraryGrade(
      saturation: _asDouble(params['saturation'], 1).clamp(0, 3),
      contrast: _asDouble(params['contrast'], 1).clamp(0, 3),
      brightness: _asDouble(params['brightness'], 0).clamp(-1, 1),
      temperature: _asDouble(params['temperature'], 0).clamp(-1, 1),
      gamma: _asDouble(params['gamma'], 1).clamp(0.1, 3),
    );
  }
}

double _asDouble(Object? raw, double fallback) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw) ?? fallback;
  return fallback;
}

/// The render shadow list (glow first, then the drop shadow)
/// for a text-style [recipe]; empty when the recipe carries
/// neither. Shared by the parity renderer (export) and the
/// preview widgets — material's Shadow IS dart:ui's Shadow.
List<ui.Shadow> libraryStyleShadows(LibraryRecipe recipe) {
  final out = <ui.Shadow>[];
  final glow = recipe.styleGlow;
  if (glow != null && glow.blur > 0) {
    out.add(ui.Shadow(color: ui.Color(glow.colorArgb), blurRadius: glow.blur));
  }
  final shadow = recipe.styleShadow;
  if (shadow != null) {
    out.add(
      ui.Shadow(
        color: ui.Color(shadow.colorArgb),
        blurRadius: shadow.blur,
        offset: ui.Offset(shadow.dx, shadow.dy),
      ),
    );
  }
  return out;
}

/// The ffmpeg filter chain for a 'grade' recipe: eq (saturation /
/// contrast / brightness / gamma) + colorbalance for the
/// temperature shift. Identity parameters are omitted so an
/// all-default grade produces an empty chain (caller skips).
String libraryGradeFilterChain(LibraryGrade g) {
  String n(double v) => v.toStringAsFixed(3);
  final parts = <String>[];
  final eq = <String>[];
  if (g.saturation != 1) eq.add('saturation=${n(g.saturation)}');
  if (g.contrast != 1) eq.add('contrast=${n(g.contrast)}');
  if (g.brightness != 0) eq.add('brightness=${n(g.brightness)}');
  if (g.gamma != 1) eq.add('gamma=${n(g.gamma)}');
  if (eq.isNotEmpty) parts.add('eq=${eq.join(':')}');
  if (g.temperature != 0) {
    final t = n(g.temperature * 0.25);
    final c = n(-g.temperature * 0.25);
    parts.add('colorbalance=rs=$t:bs=$c:rm=$t:bm=$c:rh=$t:bh=$c');
  }
  return parts.join(',');
}

/// Parses a recipe colour: '#RRGGBB' or '#AARRGGBB' (or a raw
/// ARGB int). Null when unparseable.
int? parseLibraryColor(Object? raw) {
  if (raw is int) return raw;
  if (raw is! String) return null;
  var hex = raw.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  return int.tryParse(hex, radix: 16);
}

/// One parsed recipe.json.
class LibraryRecipe {
  const LibraryRecipe({
    required this.name,
    required this.category,
    required this.kind,
    required this.params,
  });

  final String name;
  final String category;
  final String kind;
  final Map<String, dynamic> params;

  // -- Transitions (xfade) --
  String get xfadeType {
    final t = params['type'];
    return (t is String && t.trim().isNotEmpty) ? t.trim() : 'fade';
  }

  double get xfadeDuration =>
      _asDouble(params['duration'], 0.5).clamp(0.1, 3).toDouble();

  // -- Effects (overlay) --
  String? get overlayAsset {
    final a = params['asset'];
    return (a is String && a.trim().isNotEmpty) ? a.trim() : null;
  }

  String get overlayBlend {
    final b = params['blend'];
    return (b is String && b.trim().isNotEmpty) ? b.trim() : 'screen';
  }

  double get overlayOpacity =>
      _asDouble(params['opacity'], 0.55).clamp(0, 1).toDouble();

  // -- Effects (grade) --
  LibraryGrade get grade => LibraryGrade.fromParams(params);

  // -- Text Styles --
  /// Font reference: an UrduFonts id or 'user:<id>' (#51). Null =
  /// the surface's own font choice stays in charge.
  String? get styleFontRef {
    final f = params['font'];
    return (f is String && f.trim().isNotEmpty) ? f.trim() : null;
  }

  int? get styleColor => parseLibraryColor(params['color']);
  int? get styleLabelBackground =>
      parseLibraryColor(params['labelBackground']);
  LibraryShadow? get styleShadow =>
      LibraryShadow.fromParams(params['shadow']);
  LibraryShadow? get styleGlow => LibraryShadow.fromParams(params['glow']);
  int? get styleBorderColor {
    final b = params['border'];
    if (b is Map) return parseLibraryColor(b['color']);
    return null;
  }

  double get styleBorderWidth {
    final b = params['border'];
    if (b is Map) return _asDouble(b['width'], 0);
    return 0;
  }

  String? get styleAnimationIn {
    final a = params['animationIn'];
    return (a is String && a.trim().isNotEmpty) ? a.trim() : null;
  }

  String? get styleAnimationOut {
    final a = params['animationOut'];
    return (a is String && a.trim().isNotEmpty) ? a.trim() : null;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'category': category,
        'kind': kind,
        'params': params,
      };

  /// Parses + validates a recipe for [expectedCategory]. Null =
  /// invalid (the item is skipped silently).
  static LibraryRecipe? fromJson(
    Object? raw, {
    required String expectedCategory,
  }) {
    try {
      if (raw is! Map) return null;
      final name = raw['name'];
      final kind = raw['kind'];
      if (name is! String || name.trim().isEmpty) return null;
      if (kind is! String) return null;
      final category = raw['category'];
      if (category != null && category != expectedCategory) {
        return null;
      }
      final allowed = LibraryConfig.kindsByCategory[expectedCategory];
      if (allowed == null || !allowed.contains(kind)) return null;
      final paramsRaw = raw['params'];
      final params = <String, dynamic>{};
      if (paramsRaw is Map) {
        paramsRaw.forEach((k, v) {
          if (k is String) params[k] = v;
        });
      }
      return LibraryRecipe(
        name: name.trim(),
        category: expectedCategory,
        kind: kind,
        params: params,
      );
    } catch (_) {
      return null;
    }
  }
}

/// One library item: a Drive subfolder with a valid recipe.
class LibraryItem {
  const LibraryItem({
    required this.folderId,
    required this.folderName,
    required this.category,
    required this.recipe,
    required this.recipeFileId,
    required this.assetIds,
  });

  /// Drive id of the item's folder — the persisted selection id.
  final String folderId;

  /// The item folder's name in Drive.
  final String folderName;

  final String category;
  final LibraryRecipe recipe;

  /// Drive id of the recipe.json this parse came from — the
  /// refresh path reuses a cached parse only while this id and
  /// the asset set are unchanged.
  final String recipeFileId;

  /// Asset file name → Drive file id (recipe.json excluded).
  final Map<String, String> assetIds;

  String get name => recipe.name;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'folderId': folderId,
        'folderName': folderName,
        'category': category,
        'recipe': recipe.toJson(),
        'recipeFileId': recipeFileId,
        'assetIds': assetIds,
      };

  static LibraryItem? fromJson(Object? raw) {
    try {
      if (raw is! Map) return null;
      final folderId = raw['folderId'];
      final folderName = raw['folderName'];
      final category = raw['category'];
      if (folderId is! String || folderId.isEmpty) return null;
      if (folderName is! String || folderName.isEmpty) return null;
      if (category is! String) return null;
      final recipe = LibraryRecipe.fromJson(
        raw['recipe'],
        expectedCategory: category,
      );
      if (recipe == null) return null;
      final recipeFileId = raw['recipeFileId'];
      final assets = <String, String>{};
      final rawAssets = raw['assetIds'];
      if (rawAssets is Map) {
        rawAssets.forEach((k, v) {
          if (k is String && v is String) assets[k] = v;
        });
      }
      return LibraryItem(
        folderId: folderId,
        folderName: folderName,
        category: category,
        recipe: recipe,
        recipeFileId: recipeFileId is String ? recipeFileId : '',
        assetIds: assets,
      );
    } catch (_) {
      return null;
    }
  }
}

/// The library backend: discovery, listings, asset downloads.
/// Cache-first like [StoreService]; nothing here throws to the UI.
class LibraryService {
  LibraryService._();

  static final LibraryService instance = LibraryService._();

  static const String _foldersKey = 'tjpro_library_folders_v1';
  static const String _itemsPrefix = 'tjpro_library_items_v1_';
  static const String _dirName = 'tj_pro_library';

  /// Bumped whenever a listing changes (screens can refresh).
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final Map<String, String> _folderIds = <String, String>{};
  final Map<String, List<LibraryItem>> _itemsCache =
      <String, List<LibraryItem>>{};
  bool _foldersLoaded = false;

  // ----------------------------------------------------------------
  // Listings (cache-first)
  // ----------------------------------------------------------------

  /// The cached items for [category] (memory, then prefs). Never
  /// touches the network, never throws.
  Future<List<LibraryItem>> cachedItems(String category) async {
    try {
      final memory = _itemsCache[category];
      if (memory != null) return List<LibraryItem>.unmodifiable(memory);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_itemsPrefix$category');
      if (raw == null || raw.isEmpty) return const <LibraryItem>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <LibraryItem>[];
      final items = decoded
          .map(LibraryItem.fromJson)
          .where((e) => e != null)
          .cast<LibraryItem>()
          .toList();
      _itemsCache[category] = items;
      return List<LibraryItem>.unmodifiable(items);
    } catch (_) {
      return const <LibraryItem>[];
    }
  }

  /// Cache-first listing: cache immediately when present (with a
  /// background refresh), a live fetch on a cold cache. Failures
  /// return the cache (possibly empty).
  Future<List<LibraryItem>> listItems(String category) async {
    try {
      final cached = await cachedItems(category);
      if (cached.isNotEmpty) {
        unawaited(refreshItems(category));
        return cached;
      }
      return await refreshItems(category);
    } catch (_) {
      return await cachedItems(category);
    }
  }

  /// Live listing: discover the category folder, read its item
  /// subfolders, fetch + validate each recipe.json. Invalid or
  /// incomplete items are skipped silently. On any failure the
  /// previous cache is returned unchanged.
  Future<List<LibraryItem>> refreshItems(String category) async {
    try {
      final folderId = await _categoryFolderId(category);
      if (folderId == null) return await cachedItems(category);
      final subfolders = await _listFolder(folderId, foldersOnly: true);
      if (subfolders.isEmpty) return await cachedItems(category);
      final items = <LibraryItem>[];
      for (final sub in subfolders) {
        final item = await _loadItem(category, sub);
        if (item != null) items.add(item);
      }
      items.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      _itemsCache[category] = items;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          '$_itemsPrefix$category',
          jsonEncode(items.map((e) => e.toJson()).toList()),
        );
      } catch (_) {
        // Cache is best-effort.
      }
      revision.value = revision.value + 1;
      return List<LibraryItem>.unmodifiable(items);
    } catch (_) {
      return cachedItems(category);
    }
  }

  /// One item by its folder id (from the cache-first listing).
  Future<LibraryItem?> itemById(String category, String folderId) async {
    if (folderId.isEmpty) return null;
    final items = await listItems(category);
    for (final item in items) {
      if (item.folderId == folderId) return item;
    }
    return null;
  }

  /// Reads one item folder: finds recipe.json, downloads +
  /// validates it, and records the asset files. A cached item is
  /// reused when its recipe.json file id is unchanged (no
  /// re-download of the recipe on every refresh).
  Future<LibraryItem?> _loadItem(
    String category,
    _LibEntry folder,
  ) async {
    try {
      final files = await _listFolder(folder.id, foldersOnly: false);
      if (files.isEmpty) return null;
      _LibEntry? recipeEntry;
      final assets = <String, String>{};
      for (final f in files) {
        if (f.name.trim().toLowerCase() == 'recipe.json') {
          recipeEntry = f;
        } else {
          assets[f.name] = f.id;
        }
      }
      if (recipeEntry == null) return null;
      // Reuse the cached parse while the recipe file and the
      // asset set are unchanged (no re-download per refresh).
      final cached = await cachedItems(category);
      for (final c in cached) {
        if (c.folderId == folder.id &&
            c.recipeFileId == recipeEntry.id &&
            c.assetIds.length == assets.length &&
            assets.entries.every((e) => c.assetIds[e.key] == e.value)) {
          return c;
        }
      }
      final recipeJson = await _downloadJson(recipeEntry.id);
      final recipe = LibraryRecipe.fromJson(
        recipeJson,
        expectedCategory: category,
      );
      if (recipe == null) return null;
      return LibraryItem(
        folderId: folder.id,
        folderName: folder.name,
        category: category,
        recipe: recipe,
        recipeFileId: recipeEntry.id,
        assetIds: assets,
      );
    } catch (_) {
      return null;
    }
  }

  // ----------------------------------------------------------------
  // Assets
  // ----------------------------------------------------------------

  /// Ensures one of [item]'s asset files is on-device (downloaded
  /// into documents/tj_pro_library/<Category>/<folderId>/).
  /// Returns the file, or null on any failure. Never throws.
  Future<File?> ensureAsset(LibraryItem item, String fileName) async {
    try {
      final fileId = item.assetIds[fileName];
      if (fileId == null || fileId.isEmpty) return null;
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(
        p.join(
          docs.path,
          _dirName,
          _safeSegment(item.category),
          _safeSegment(item.folderId),
        ),
      );
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File(p.join(dir.path, _safeSegment(fileName)));
      if (await file.exists() && await file.length() > 0) return file;
      final client = http.Client();
      try {
        final request = http.Request(
          'GET',
          Uri.parse(StoreConfig.downloadUrl(fileId)),
        );
        final response =
            await client.send(request).timeout(const Duration(minutes: 5));
        if (response.statusCode != 200) return null;
        final sink = file.openWrite();
        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
          }
        } finally {
          await sink.close();
        }
      } finally {
        client.close();
      }
      if (!await file.exists() || await file.length() <= 0) {
        try {
          await file.delete();
        } catch (_) {}
        return null;
      }
      return file;
    } catch (_) {
      return null;
    }
  }

  String _safeSegment(String value) =>
      value.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').trim();

  // ----------------------------------------------------------------
  // Category folder discovery (root listing, name match)
  // ----------------------------------------------------------------

  Future<String?> _categoryFolderId(String category) async {
    try {
      if (!_foldersLoaded) {
        await _loadCachedFolders();
        _foldersLoaded = true;
      }
      final known = _folderIds[category];
      if (known != null && known.isNotEmpty) {
        // Refresh in the background so a newly created category
        // folder is picked up without blocking.
        unawaited(_refreshFolders());
        return known;
      }
      await _refreshFolders();
      final id = _folderIds[category];
      return (id == null || id.isEmpty) ? null : id;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadCachedFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_foldersKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((key, value) {
        if (key is String && value is String && value.isNotEmpty) {
          _folderIds[key] = value;
        }
      });
    } catch (_) {
      // Cache is best-effort.
    }
  }

  Future<void> _refreshFolders() async {
    try {
      final entries = await _listFolder(
        StoreConfig.rootFolderId,
        foldersOnly: true,
      );
      if (entries.isEmpty) return;
      var changed = false;
      for (final entry in entries) {
        for (final category in LibraryConfig.categories) {
          if (entry.name.trim().toLowerCase() == category.toLowerCase() &&
              _folderIds[category] != entry.id) {
            _folderIds[category] = entry.id;
            changed = true;
          }
        }
      }
      if (changed) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_foldersKey, jsonEncode(_folderIds));
      }
    } catch (_) {
      // Keep whatever cache we have.
    }
  }

  // ----------------------------------------------------------------
  // Drive listing (the StoreService route: embedded folder view)
  // ----------------------------------------------------------------

  Future<List<_LibEntry>> _listFolder(
    String folderId, {
    required bool foldersOnly,
  }) async {
    try {
      final response = await http
          .get(Uri.parse(StoreConfig.embeddedFolderUrl(folderId)))
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) return const <_LibEntry>[];
      return _parseEmbeddedFolderHtml(response.body,
          foldersOnly: foldersOnly);
    } catch (_) {
      return const <_LibEntry>[];
    }
  }

  /// The same tolerant parser discipline as StoreService's:
  /// entries are `id="entry-<id>"` blocks ending at a
  /// `flip-entry-title">name<`; folder entries mention "folder"
  /// in their icon block. Anything unreadable is skipped.
  static List<_LibEntry> _parseEmbeddedFolderHtml(
    String html, {
    required bool foldersOnly,
  }) {
    final entries = <_LibEntry>[];
    try {
      final entryPattern = RegExp(
        r'id="entry-([-\w]+)"([\s\S]*?)flip-entry-title">([^<]+)<',
      );
      for (final match in entryPattern.allMatches(html)) {
        final id = match.group(1) ?? '';
        final middle = match.group(2) ?? '';
        final name = _decodeHtml(match.group(3) ?? '').trim();
        if (id.isEmpty || name.isEmpty) continue;
        final isFolder = middle.contains('folder');
        if (isFolder != foldersOnly) continue;
        entries.add(_LibEntry(id: id, name: name, isFolder: isFolder));
      }
    } catch (_) {
      return const <_LibEntry>[];
    }
    return entries;
  }

  static String _decodeHtml(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }

  /// Downloads + parses a small JSON file from Drive. Null on any
  /// failure (network, status, parse).
  Future<Object?> _downloadJson(String fileId) async {
    try {
      final response = await http
          .get(Uri.parse(StoreConfig.downloadUrl(fileId)))
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) return null;
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      return null;
    }
  }
}

/// One raw Drive listing entry (file or folder).
class _LibEntry {
  const _LibEntry({
    required this.id,
    required this.name,
    required this.isFolder,
  });

  final String id;
  final String name;
  final bool isFolder;
}
