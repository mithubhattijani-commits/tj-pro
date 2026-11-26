/// MOTION GRAPHICS STUDIO — Gallery favourites + recently
/// used (Build M4, v1.26.0; plan §4 M4 item 2).
///
/// Two small local lists, stored exactly like MotionOwnership
/// (SharedPreferences, in-memory cache, fail-soft: any storage
/// error reads as "none", never a crash). Favourites hold
/// built-in template ids; recents hold built-in template ids,
/// most-recent first, capped — both feed the Gallery's
/// category rail chips.
library;

import 'package:shared_preferences/shared_preferences.dart';

/// Heart-marked templates (the Gallery card's heart toggle).
class MotionFavourites {
  MotionFavourites._();

  static const String _key = 'tjpro_motion_favourites_v1';

  static Set<String>? _cache;

  static Future<Set<String>> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key) ?? const <String>[];
      return _cache = list.toSet();
    } catch (_) {
      return _cache = <String>{};
    }
  }

  static Future<bool> isFavourite(String templateId) async =>
      (await load()).contains(templateId);

  /// Flips [templateId]; returns the NEW state (true = now a
  /// favourite). Persisted at once.
  static Future<bool> toggle(String templateId) async {
    final favs = await load();
    final nowFav = !favs.contains(templateId);
    if (nowFav) {
      favs.add(templateId);
    } else {
      favs.remove(templateId);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, favs.toList());
    } catch (_) {
      // The in-memory cache still holds it for this session.
    }
    return nowFav;
  }

  /// Test seam: forget the in-memory cache (storage untouched).
  static void resetCacheForTest() => _cache = null;
}

/// Recently opened templates, most-recent first.
class MotionRecents {
  MotionRecents._();

  static const String _key = 'tjpro_motion_recent_v1';

  /// How many recents the rail chip offers.
  static const int maxItems = 8;

  static List<String>? _cache;

  static Future<List<String>> load() async {
    final cached = _cache;
    if (cached != null) return List<String>.unmodifiable(cached);
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key) ?? const <String>[];
      return List<String>.unmodifiable(_cache = list);
    } catch (_) {
      return List<String>.unmodifiable(_cache = <String>[]);
    }
  }

  /// Moves [templateId] to the front (recording it if new)
  /// and caps the list at [maxItems]. Persisted at once.
  static Future<void> record(String templateId) async {
    final current = List<String>.from(await load());
    current.remove(templateId);
    current.insert(0, templateId);
    final capped = current.take(maxItems).toList();
    _cache = capped;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, capped);
    } catch (_) {
      // The in-memory cache still holds it for this session.
    }
  }

  /// Test seam: forget the in-memory cache (storage untouched).
  static void resetCacheForTest() => _cache = null;
}
