import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'coin_service.dart';

/// Online Store (TJ Pro v1.2.0, plan §3) — a Drive-backed content
/// store. The user drops a file into a category folder of the public
/// "TJ Pro Store" Drive folder and it appears in the app with no new
/// build and no list editing (zero-effort rule, 21 Nov 2026).
///
/// Listing route: there is NO Drive API key in the app, so listings
/// are read by parsing the public embedded folder view
/// (`drive.google.com/embeddedfolderview?id=<folderId>#grid`), which
/// works for an anyone-with-link folder. When [StoreConfig.driveApiKey]
/// is set later, the Drive API v3 path is tried first instead and the
/// embedded view remains the fallback. Downloads use the standard
/// `uc?export=download` URL via package:http.
///
/// Robustness (acceptance criteria): cache-first — every listing and
/// every owned-item record is cached in SharedPreferences, callers
/// render instantly from cache and refresh in the background, and any
/// network / parse failure degrades to the cache instead of throwing.
/// Files that are zero-byte, still uploading, unparseable, or have an
/// unsupported extension for their category are skipped silently.
/// Every method is failure-isolated: nothing here throws to the UI.
///
/// Purchase flow (deduct-on-success): check the balance through
/// [CoinService] → download to the app documents directory → verify
/// the file is non-empty → ONLY THEN deduct via
/// [CoinService.spendAmount] → mark owned (persisted). Owned items
/// live on-device and are reusable offline forever; pickers read them
/// through [StoreService.ownedItems].
class StoreConfig {
  StoreConfig._();

  /// Root "TJ Pro Store" folder (anyone-with-link Viewer), owned by
  /// the jaanirecords2 Drive account.
  static const String rootFolderId = '1AYTgpyQsL8b6CEASlUl0tnjRV7y5wFrO';

  /// Optional Drive API v3 key. Empty = embedded-view parsing only.
  /// Set this (e.g. from remote config later) to enable the API path;
  /// no code change is needed.
  static const String driveApiKey = '';

  /// The store categories — these are also the exact subfolder
  /// names inside the root folder, and the app sections they feed.
  /// F2 (tools-fix wave 2): 'Transitions' + 'Text Styles' added —
  /// their Drive folders existed since 2026-11-23 but discovery
  /// matched only the names listed here, so anything dropped in
  /// those two folders NEVER surfaced in the Store (no chip, no
  /// listing, no purchase path) — a silent break of the
  /// zero-effort rule. The Library recipe system reads the same
  /// folders separately for editor pickers; this list is what
  /// makes their PLAIN stock files list/buy/download in the
  /// Store like every other category.
  static const List<String> categories = <String>[
    'Animations',
    'Backgrounds',
    'Captions',
    'Effects',
    'Music',
    'Ribbons',
    'Templates',
    'Text Templates',
    'Transitions',
    'Text Styles',
  ];

  /// Price table — the single source for store prices (coins).
  /// A file whose name contains "FREE" (any case) costs 0 instead
  /// (see [StoreService.priceFor]).
  static const Map<String, int> priceTable = <String, int>{
    'Text Templates': 10,
    'Animations': 10,
    'Ribbons': 10,
    'Effects': 10,
    'Captions': 10,
    'Backgrounds': 10,
    'Music': 30,
    'Templates': 50,
    // F2: folder-default prices, matched to the comparable
    // categories — Transitions are short video clips like
    // Animations/Effects (10); Text Styles are text assets like
    // Text Templates (10). "FREE" in a file name still wins (0).
    'Transitions': 10,
    'Text Styles': 10,
  };

  /// Extensions accepted per category. Anything else is skipped —
  /// this is also what filters out half-uploaded files (Drive shows
  /// them with no / a temporary extension) and stray documents the
  /// user did not mean to publish.
  static const Map<String, Set<String>> allowedExtensions =
      <String, Set<String>>{
    'Templates': <String>{'.mp4', '.mov', '.json'},
    'Text Templates': <String>{'.json', '.png', '.jpg', '.jpeg'},
    'Music': <String>{'.mp3', '.m4a', '.wav', '.ogg'},
    'Animations': <String>{'.mp4', '.json', '.gif', '.png'},
    'Effects': <String>{'.mp4', '.json', '.gif', '.png'},
    'Ribbons': <String>{'.png', '.jpg', '.jpeg', '.json', '.mp4'},
    'Backgrounds': <String>{'.png', '.jpg', '.jpeg', '.json', '.mp4'},
    'Captions': <String>{'.png', '.jpg', '.jpeg', '.json', '.mp4'},
    // F2: Transitions = transition videos (+ recipe .json, the
    // Templates set); Text Styles = style recipes + their
    // preview images (the Text Templates set).
    'Transitions': <String>{'.mp4', '.mov', '.json'},
    'Text Styles': <String>{'.json', '.png', '.jpg', '.jpeg'},
  };

  /// Ledger reason recorded for a store purchase spend.
  static const String spendReason = 'store_purchase';

  /// Download URL for a Drive file id.
  static String downloadUrl(String fileId) =>
      'https://drive.google.com/uc?export=download&id=$fileId';

  /// Public embedded folder view URL for a folder id.
  static String embeddedFolderUrl(String folderId) =>
      'https://drive.google.com/embeddedfolderview?id=$folderId#grid';
}

/// One file listed in a store category folder.
class StoreItem {
  const StoreItem({
    required this.id,
    required this.name,
    required this.category,
    this.sizeBytes,
  });

  /// Drive file id (also the download + ownership key).
  final String id;

  /// File name as it appears in Drive (extension included).
  final String name;

  /// Category (one of [StoreConfig.categories]).
  final String category;

  /// Size in bytes when the listing route reported it (Drive API
  /// only; the embedded view does not expose sizes, so null there).
  final int? sizeBytes;

  /// Display name without the extension.
  String get title {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// Build 8 (v1.6.0, fix-list point #3): the card-facing name —
  /// [title] with the technical markers removed and whitespace
  /// tidied. DISPLAY ONLY: pricing ("FREE" detection), ownership
  /// and downloads always use the raw [name], exactly as before.
  String get displayTitle => cleanDisplayTitle(title);

  static final RegExp _markerPattern = RegExp(
    r'\((?:transparent|landscape|portrait|square)\)',
    caseSensitive: false,
  );

  /// Removes the "(Transparent)" / "(Landscape)" / "(Portrait)" /
  /// "(Square)" markers from a display title. These markers are
  /// never parsed by the app (verified in STORE-PREVIEWS-REPORT)
  /// — they only cluttered the card. Falls back to the raw title
  /// when cleaning would leave nothing.
  static String cleanDisplayTitle(String rawTitle) {
    var cleaned = rawTitle.replaceAll(_markerPattern, '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    // A trailing marker can leave a dangling separator behind
    // ("Caption - X -"): drop it.
    cleaned = cleaned.replaceAll(RegExp(r'[\s\-|]+$'), '').trim();
    return cleaned.isEmpty ? rawTitle.trim() : cleaned;
  }

  /// Lower-case extension including the dot ('' when none).
  String get extension {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot).toLowerCase() : '';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'category': category,
        'size_bytes': sizeBytes,
      };

  static StoreItem? fromJson(Map<String, dynamic> json) {
    try {
      final id = json['id'];
      final name = json['name'];
      final category = json['category'];
      if (id is! String || name is! String || category is! String) {
        return null;
      }
      if (id.isEmpty || name.isEmpty) return null;
      final size = json['size_bytes'];
      return StoreItem(
        id: id,
        name: name,
        category: category,
        sizeBytes: size is int ? size : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// A purchased / free-downloaded item, persisted on-device. The file
/// itself lives under the app documents directory and never expires.
class StoreOwnedItem {
  const StoreOwnedItem({
    required this.id,
    required this.name,
    required this.category,
    required this.localPath,
    required this.pricePaid,
    required this.ownedAt,
  });

  /// Drive file id.
  final String id;

  final String name;
  final String category;

  /// Absolute path of the downloaded file on this device.
  final String localPath;

  /// Coins actually deducted (0 for FREE items and admin waivers).
  final int pricePaid;

  final DateTime ownedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'category': category,
        'local_path': localPath,
        'price_paid': pricePaid,
        'owned_at': ownedAt.toIso8601String(),
      };

  static StoreOwnedItem? fromJson(Map<String, dynamic> json) {
    try {
      final id = json['id'];
      final name = json['name'];
      final category = json['category'];
      final path = json['local_path'];
      final ownedAt = json['owned_at'];
      if (id is! String ||
          name is! String ||
          category is! String ||
          path is! String ||
          ownedAt is! String) {
        return null;
      }
      final price = json['price_paid'];
      return StoreOwnedItem(
        id: id,
        name: name,
        category: category,
        localPath: path,
        pricePaid: price is int ? price : 0,
        ownedAt: DateTime.parse(ownedAt),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Outcome of [StoreService.purchase].
class StorePurchaseResult {
  const StorePurchaseResult({
    required this.ok,
    this.owned,
    this.error,
    this.insufficientBalance = false,
  });

  /// True when the item is now owned (including already-owned).
  final bool ok;

  /// The owned record when [ok] is true.
  final StoreOwnedItem? owned;

  /// Machine-readable failure reason when [ok] is false
  /// (`insufficient_balance`, `download_failed`, `spend_failed`, ...).
  final String? error;

  /// True when the failure is a low balance — the UI offers the
  /// Coins screen in that case.
  final bool insufficientBalance;
}

/// Drive store backend: discovery, listings, downloads, purchases.
class StoreService {
  StoreService._();

  /// Shared instance.
  static final StoreService instance = StoreService._();

  static const String _foldersKey = 'tjpro_store_folders_v1';
  static const String _listingPrefix = 'tjpro_store_listing_v1_';
  static const String _previewsPrefix = 'tjpro_store_previews_v1_';
  static const String _ownedKey = 'tjpro_store_owned_v1';

  /// Local folder (under app documents) that holds owned files,
  /// with one subfolder per category.
  static const String _storeDirName = 'tj_pro_store';

  /// Bumped whenever a listing or the owned set changes, so screens
  /// can refresh without polling.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  DateTime? _lastSuccessfulRefreshAt;

  /// When a live listing last came back successfully (null = never
  /// this launch). Screens compare it around a refresh to tell a
  /// quiet offline failure apart from fresh data.
  DateTime? get lastSuccessfulRefreshAt => _lastSuccessfulRefreshAt;

  final Map<String, String> _folderIds = <String, String>{};
  final Map<String, List<StoreItem>> _listingCache =
      <String, List<StoreItem>>{};

  /// Build 8: per-category preview map (item base name,
  /// lower-cased -> preview Drive file id), filled by
  /// [refreshCategory] and restored from SharedPreferences by
  /// [cachedListing].
  final Map<String, Map<String, String>> _previewCache =
      <String, Map<String, String>>{};
  List<StoreOwnedItem>? _ownedCache;
  bool _foldersLoaded = false;

  // ------------------------------------------------------------------
  // Pricing
  // ------------------------------------------------------------------

  /// Price of [item]: 0 when the file name contains "FREE" (any
  /// case), otherwise the category price from [StoreConfig.priceTable].
  int priceFor(StoreItem item) {
    if (item.name.toUpperCase().contains('FREE')) return 0;
    return StoreConfig.priceTable[item.category] ?? 0;
  }

  /// True when [name]'s extension is allowed in [category].
  bool isSupported(String category, String name) =>
      _isSupportedName(category, name);

  static bool _isSupportedName(String category, String name) {
    final allowed = StoreConfig.allowedExtensions[category];
    if (allowed == null) return false;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return allowed.contains(name.substring(dot).toLowerCase());
  }

  // ------------------------------------------------------------------
  // Preview files (Build 8, v1.6.0, fix-list point #3)
  // ------------------------------------------------------------------

  /// A preview file sits NEXT TO its item in the same Drive
  /// folder, named `<item base name>.preview.jpg` (Option A of
  /// STORE-PREVIEWS-REPORT). It is NEVER a store item itself.
  static bool isPreviewFileName(String name) =>
      name.toLowerCase().contains('.preview.');

  /// Base name of a preview file: 'X.preview.jpg' -> 'X'
  /// (the matching item's [StoreItem.title]).
  static String previewBaseName(String previewName) {
    final int idx = previewName.toLowerCase().indexOf('.preview.');
    return idx > 0 ? previewName.substring(0, idx) : previewName;
  }

  /// Splits raw folder candidates into sellable items and the
  /// preview map (item base name, lower-cased -> preview file
  /// id). Pure and static so the listing rules are unit-testable.
  /// Preview files are separated BEFORE the extension filter on
  /// purpose: a Music preview is a .jpg inside a folder whose
  /// allowed extensions exclude images, and it must still be
  /// found. Zero-byte and unsupported-extension files are
  /// skipped exactly as before; items come out name-sorted,
  /// exactly as before.
  static ({List<StoreItem> items, Map<String, String> previews})
      buildCategoryListing(String category, List<StoreItem> candidates) {
    final items = <StoreItem>[];
    final previews = <String, String>{};
    for (final entry in candidates) {
      if (isPreviewFileName(entry.name)) {
        previews[previewBaseName(entry.name).toLowerCase()] = entry.id;
        continue;
      }
      if (entry.sizeBytes != null && entry.sizeBytes! <= 0) continue;
      if (!_isSupportedName(category, entry.name)) continue;
      items.add(entry);
    }
    items.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return (items: items, previews: previews);
  }

  /// Drive file id of [item]'s preview image, or null when the
  /// item's folder holds none. Synchronous and cache-only — the
  /// store UI reads it while building cards and never waits.
  String? previewIdFor(StoreItem item) {
    final Map<String, String>? map = _previewCache[item.category];
    if (map == null) return null;
    return map[item.title.toLowerCase()];
  }

  // ------------------------------------------------------------------
  // Category folder discovery
  // ------------------------------------------------------------------

  /// Category name → Drive folder id, discovered by listing the root
  /// folder and matching subfolder names. Cached in
  /// SharedPreferences; a failed refresh keeps the cached map.
  Future<Map<String, String>> discoverSubfolders({
    bool forceRefresh = false,
  }) async {
    try {
      if (_foldersLoaded && !forceRefresh && _folderIds.isNotEmpty) {
        return Map<String, String>.unmodifiable(_folderIds);
      }
      if (!_foldersLoaded || forceRefresh) {
        await _loadCachedFolders();
        if (_folderIds.isNotEmpty && !forceRefresh) {
          _foldersLoaded = true;
          // Refresh in the background so a newly added subfolder is
          // picked up next time without blocking this call.
          unawaited(_refreshFolders());
          return Map<String, String>.unmodifiable(_folderIds);
        }
      }
      await _refreshFolders();
      return Map<String, String>.unmodifiable(_folderIds);
    } catch (_) {
      return Map<String, String>.unmodifiable(_folderIds);
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

  /// The store category a Drive subfolder name maps to (exact
  /// name, case-insensitive, trimmed) — null when the folder is
  /// not a store category. Extracted from [_refreshFolders] so
  /// the discovery rule itself is unit-testable (F2: this match
  /// is the exact gate that kept 'Transitions' / 'Text Styles'
  /// invisible — their names simply were not in the list).
  static String? categoryForFolderName(String folderName) {
    final wanted = folderName.trim().toLowerCase();
    for (final category in StoreConfig.categories) {
      if (category.toLowerCase() == wanted) return category;
    }
    return null;
  }

  Future<void> _refreshFolders() async {
    try {
      final entries = await _listFolder(StoreConfig.rootFolderId,
          foldersOnly: true);
      if (entries.isEmpty) return;
      var changed = false;
      for (final entry in entries) {
        // Match by exact category name (case-insensitive, trimmed).
        final category = categoryForFolderName(entry.name);
        if (category != null && _folderIds[category] != entry.id) {
          _folderIds[category] = entry.id;
          changed = true;
        }
      }
      _foldersLoaded = true;
      if (changed) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_foldersKey, jsonEncode(_folderIds));
        revision.value = revision.value + 1;
      }
    } catch (_) {
      // Keep whatever cache we have.
    }
  }

  // ------------------------------------------------------------------
  // Listings (cache-first)
  // ------------------------------------------------------------------

  /// The cached listing for [category] (memory first, then
  /// SharedPreferences). Never touches the network, never throws.
  Future<List<StoreItem>> cachedListing(String category) async {
    try {
      final memory = _listingCache[category];
      if (memory != null) return List<StoreItem>.unmodifiable(memory);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_listingPrefix$category');
      if (raw == null || raw.isEmpty) return const <StoreItem>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <StoreItem>[];
      final items = decoded
          .whereType<Map<String, dynamic>>()
          .map(StoreItem.fromJson)
          .where((e) => e != null)
          .cast<StoreItem>()
          // Defensive (Build 8): a cache written by an older
          // build after preview files reached Drive could hold a
          // preview as an item — never surface one.
          .where((e) => !isPreviewFileName(e.name))
          .toList();
      _listingCache[category] = items;
      await _loadCachedPreviews(category, prefs);
      return List<StoreItem>.unmodifiable(items);
    } catch (_) {
      return const <StoreItem>[];
    }
  }

  /// Restores the persisted preview map for [category] (once per
  /// category per launch). Best-effort like every cache here.
  Future<void> _loadCachedPreviews(
    String category,
    SharedPreferences prefs,
  ) async {
    if (_previewCache.containsKey(category)) return;
    try {
      final raw = prefs.getString('$_previewsPrefix$category');
      if (raw == null || raw.isEmpty) {
        _previewCache[category] = <String, String>{};
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _previewCache[category] = <String, String>{};
        return;
      }
      final map = <String, String>{};
      decoded.forEach((key, value) {
        if (key is String && value is String && value.isNotEmpty) {
          map[key] = value;
        }
      });
      _previewCache[category] = map;
    } catch (_) {
      _previewCache[category] = <String, String>{};
    }
  }

  /// Cache-first listing: returns the cache immediately when one
  /// exists and refreshes it in the background; on a cold cache it
  /// fetches once. Never throws — failures return the cache (possibly
  /// empty) so the UI can show its quiet retry state.
  Future<List<StoreItem>> listCategory(String category) async {
    try {
      final cached = await cachedListing(category);
      if (cached.isNotEmpty) {
        unawaited(refreshCategory(category));
        return cached;
      }
      return await refreshCategory(category);
    } catch (_) {
      return cachedListing(category);
    }
  }

  /// Fetch the live listing for [category], update the cache, and
  /// return it. On any failure the previous cache is returned
  /// unchanged (never an exception, never an empty overwrite).
  Future<List<StoreItem>> refreshCategory(String category) async {
    try {
      final folders = await discoverSubfolders();
      final folderId = folders[category];
      if (folderId == null || folderId.isEmpty) {
        return await cachedListing(category);
      }
      final entries = await _listFolder(folderId, foldersOnly: false);
      if (entries.isEmpty) return await cachedListing(category);
      _lastSuccessfulRefreshAt = DateTime.now();
      // Build 8: one pass splits sellable items from preview
      // files (see [buildCategoryListing]) — previews are never
      // items, and each item learns its preview's file id.
      final listing = buildCategoryListing(
        category,
        entries
            .map((e) => StoreItem(
                  id: e.id,
                  name: e.name,
                  category: category,
                  sizeBytes: e.sizeBytes,
                ))
            .toList(),
      );
      _previewCache[category] = listing.previews;
      final items = listing.items;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          '$_previewsPrefix$category',
          jsonEncode(listing.previews),
        );
        if (items.isNotEmpty) {
          await prefs.setString(
            '$_listingPrefix$category',
            jsonEncode(items.map((e) => e.toJson()).toList()),
          );
        }
      } catch (_) {
        // Cache is best-effort.
      }
      if (items.isEmpty) return await cachedListing(category);
      _listingCache[category] = items;
      revision.value = revision.value + 1;
      return List<StoreItem>.unmodifiable(items);
    } catch (_) {
      return cachedListing(category);
    }
  }

  // ------------------------------------------------------------------
  // Owned items
  // ------------------------------------------------------------------

  /// All owned records (persisted), newest first. Never throws.
  Future<List<StoreOwnedItem>> _loadOwned() async {
    try {
      if (_ownedCache != null) {
        return List<StoreOwnedItem>.unmodifiable(_ownedCache!);
      }
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_ownedKey);
      if (raw == null || raw.isEmpty) {
        _ownedCache = <StoreOwnedItem>[];
        return const <StoreOwnedItem>[];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _ownedCache = <StoreOwnedItem>[];
        return const <StoreOwnedItem>[];
      }
      _ownedCache = decoded
          .whereType<Map<String, dynamic>>()
          .map(StoreOwnedItem.fromJson)
          .where((e) => e != null)
          .cast<StoreOwnedItem>()
          .toList();
      return List<StoreOwnedItem>.unmodifiable(_ownedCache!);
    } catch (_) {
      return const <StoreOwnedItem>[];
    }
  }

  /// Test seam (Build 12): drop the in-memory owned cache so
  /// the next [ownedItems] call re-reads persistence. Widget
  /// tests seed owned items through SharedPreferences after
  /// another screen already loaded the (empty) list.
  void resetOwnedCacheForTest() {
    _ownedCache = null;
  }

  Future<void> _saveOwned() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _ownedKey,
        jsonEncode((_ownedCache ?? <StoreOwnedItem>[])
            .map((e) => e.toJson())
            .toList()),
      );
      revision.value = revision.value + 1;
    } catch (_) {
      // Persistence is best-effort; the in-memory set still works.
    }
  }

  /// Owned items in [category] whose file is still on-device — the
  /// entry point future pickers use to offer store content offline.
  Future<List<StoreOwnedItem>> ownedItems(String category) async {
    try {
      final all = await _loadOwned();
      final result = <StoreOwnedItem>[];
      for (final item in all) {
        if (item.category != category) continue;
        try {
          if (await File(item.localPath).exists()) result.add(item);
        } catch (_) {
          // A record with an unreadable path is skipped, not fatal.
        }
      }
      return result;
    } catch (_) {
      return const <StoreOwnedItem>[];
    }
  }

  /// The owned record for a Drive file id, or null when not owned.
  Future<StoreOwnedItem?> ownedRecord(String fileId) async {
    try {
      final all = await _loadOwned();
      for (final item in all) {
        if (item.id == fileId) return item;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// True when [fileId] is owned and its file is on-device.
  Future<bool> isOwned(String fileId) async {
    final record = await ownedRecord(fileId);
    if (record == null) return false;
    try {
      return await File(record.localPath).exists();
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------------
  // Purchase (deduct-on-success)
  // ------------------------------------------------------------------

  /// Buy (or freely download) [item].
  ///
  /// Order matters: balance check → download → size verify → deduct
  /// → mark owned. A failed download costs nothing; a failed deduct
  /// deletes the downloaded file so nothing is owned unpaid. Admins
  /// (server-confirmed via [CoinService.isAdminNow]) pay nothing, so
  /// no spend is attempted for them at all.
  Future<StorePurchaseResult> purchase(StoreItem item) async {
    try {
      final existing = await ownedRecord(item.id);
      if (existing != null && await File(existing.localPath).exists()) {
        return StorePurchaseResult(ok: true, owned: existing);
      }

      final price = priceFor(item);
      final coins = CoinService.instance;
      await coins.load();
      if (price > 0 && !coins.canAffordAmount(price)) {
        return const StorePurchaseResult(
          ok: false,
          error: 'insufficient_balance',
          insufficientBalance: true,
        );
      }

      // Download first — coins move only after the file is verified.
      final file = await _downloadItem(item);
      if (file == null) {
        return const StorePurchaseResult(
          ok: false,
          error: 'download_failed',
        );
      }

      var paid = 0;
      if (price > 0 && !coins.isAdminNow) {
        final spend = await coins.spendAmount(
          price,
          reason: StoreConfig.spendReason,
          // One stable key per item: a retry after a crash can never
          // double-charge for the same purchase server-side.
          idempotencyKey: 'tjpro_store:${item.id}',
        );
        if (!spend.ok) {
          try {
            await file.delete();
          } catch (_) {}
          return StorePurchaseResult(
            ok: false,
            error: spend.error ?? 'spend_failed',
            insufficientBalance: spend.error == 'insufficient_balance',
          );
        }
        paid = spend.adminFree ? 0 : price;
      }

      final record = StoreOwnedItem(
        id: item.id,
        name: item.name,
        category: item.category,
        localPath: file.path,
        pricePaid: paid,
        ownedAt: DateTime.now(),
      );
      final all = List<StoreOwnedItem>.from(await _loadOwned());
      all.removeWhere((e) => e.id == item.id);
      _ownedCache = <StoreOwnedItem>[record, ...all];
      await _saveOwned();
      return StorePurchaseResult(ok: true, owned: record);
    } catch (_) {
      return const StorePurchaseResult(ok: false, error: 'purchase_failed');
    }
  }

  /// Download [item] into `documents/tj_pro_store/<Category>/` and
  /// return the file, or null when the download failed or produced a
  /// zero-byte file (deleted in that case). Never throws.
  Future<File?> _downloadItem(StoreItem item) async {
    File? partial;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(
          p.join(docs.path, _storeDirName, _safeSegment(item.category)));
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File(p.join(dir.path, _safeFileName(item)));
      partial = file;
      if (await file.exists()) {
        final size = await file.length();
        if (size > 0) return file;
        await file.delete();
      }
      final client = http.Client();
      try {
        final request =
            http.Request('GET', Uri.parse(StoreConfig.downloadUrl(item.id)));
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
      if (!await file.exists()) return null;
      final size = await file.length();
      if (size <= 0) {
        await file.delete();
        return null;
      }
      return file;
    } catch (_) {
      try {
        if (partial != null && await partial.exists()) await partial.delete();
      } catch (_) {}
      return null;
    }
  }

  /// File name on disk: `<fileId>_<original name>` so two Drive files
  /// that share a display name can never overwrite each other.
  String _safeFileName(StoreItem item) {
    final clean = item.name.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').trim();
    return '${item.id}_$clean';
  }

  String _safeSegment(String value) =>
      value.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_').trim();

  // ------------------------------------------------------------------
  // Folder listing routes (API when keyed, embedded view otherwise)
  // ------------------------------------------------------------------

  /// Raw entries of one folder. Tries the Drive API first when a key
  /// is configured, then the embedded view. Empty on any failure.
  Future<List<_DriveEntry>> _listFolder(
    String folderId, {
    required bool foldersOnly,
  }) async {
    if (StoreConfig.driveApiKey.isNotEmpty) {
      final api = await _listFolderViaApi(folderId);
      if (api.isNotEmpty) {
        return foldersOnly
            ? api.where((e) => e.isFolder).toList()
            : api.where((e) => !e.isFolder).toList();
      }
    }
    return _listFolderViaEmbedded(folderId, foldersOnly: foldersOnly);
  }

  Future<List<_DriveEntry>> _listFolderViaApi(String folderId) async {
    try {
      final query = "'$folderId' in parents and trashed = false";
      final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
        'q': query,
        'key': StoreConfig.driveApiKey,
        'fields': 'files(id,name,mimeType,size)',
        'pageSize': '200',
      });
      final response =
          await http.get(uri).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) return const <_DriveEntry>[];
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['files'] is! List) {
        return const <_DriveEntry>[];
      }
      final entries = <_DriveEntry>[];
      for (final raw in decoded['files'] as List) {
        if (raw is! Map) continue;
        final id = raw['id'];
        final name = raw['name'];
        if (id is! String || name is! String) continue;
        if (id.isEmpty || name.isEmpty) continue;
        final sizeRaw = raw['size'];
        entries.add(_DriveEntry(
          id: id,
          name: name,
          isFolder:
              raw['mimeType'] == 'application/vnd.google-apps.folder',
          sizeBytes: sizeRaw is String ? int.tryParse(sizeRaw) : null,
        ));
      }
      return entries;
    } catch (_) {
      return const <_DriveEntry>[];
    }
  }

  /// Parse the public embedded folder view. Entries look like:
  /// `<div class="flip-entry" id="entry-<id>" ...>` followed by a
  /// `<div class="flip-entry-title">name</div>`; folder entries carry
  /// the `flip-entry-folder` marker in their icon block. The parser
  /// is deliberately tolerant: any entry it cannot read is skipped.
  Future<List<_DriveEntry>> _listFolderViaEmbedded(
    String folderId, {
    required bool foldersOnly,
  }) async {
    try {
      final response = await http
          .get(Uri.parse(StoreConfig.embeddedFolderUrl(folderId)))
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) return const <_DriveEntry>[];
      return _parseEmbeddedFolderHtml(response.body,
          foldersOnly: foldersOnly);
    } catch (_) {
      return const <_DriveEntry>[];
    }
  }

  /// Pure parser for the embedded view HTML.
  /// Returns folder entries when [foldersOnly] is true, file entries
  /// otherwise. Never throws.
  static List<_DriveEntry> _parseEmbeddedFolderHtml(
    String html, {
    required bool foldersOnly,
  }) {
    final entries = <_DriveEntry>[];
    try {
      final entryPattern = RegExp(
        r'id="entry-([-\w]+)"([\s\S]*?)flip-entry-title">([^<]+)<',
      );
      for (final match in entryPattern.allMatches(html)) {
        final id = match.group(1) ?? '';
        final middle = match.group(2) ?? '';
        final name = _decodeHtml(match.group(3) ?? '').trim();
        if (id.isEmpty || name.isEmpty) continue;
        // The block between the entry id and its title holds the
        // type icon; only folder entries mention "folder" there.
        final isFolder = middle.contains('folder');
        if (isFolder != foldersOnly) continue;
        entries.add(_DriveEntry(id: id, name: name, isFolder: isFolder));
      }
    } catch (_) {
      return const <_DriveEntry>[];
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
}

/// One raw Drive listing entry (file or folder).
class _DriveEntry {
  const _DriveEntry({
    required this.id,
    required this.name,
    required this.isFolder,
    this.sizeBytes,
  });

  final String id;
  final String name;
  final bool isFolder;
  final int? sizeBytes;
}
