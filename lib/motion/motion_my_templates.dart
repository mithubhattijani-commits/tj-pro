/// MOTION GRAPHICS STUDIO — My Templates store (Build M2,
/// v1.14.0).
///
/// The Editor's Save writes here: the edited scene as JSON plus
/// the image files the user attached to image layers (their
/// paths — the files themselves stay where the picker put them
/// / in the app's documents copy). Stored as ONE JSON list in
/// SharedPreferences; every read/write is fail-soft (a corrupt
/// store reads as empty, never a crash — the zero-effort rule).
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'motion_scene.dart';

/// One saved user template.
class MotionMyTemplate {
  const MotionMyTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.baseTemplateId,
    required this.scene,
    required this.imagePaths,
    required this.savedAtMs,
  });

  final String id;
  final String name;

  /// The seed category it came from (Gallery label reuse).
  final String category;

  /// The seed template id it was forked from (null = unknown).
  final String? baseTemplateId;

  final MotionScene scene;

  /// layer imageKey -> the user's image file path.
  final Map<String, String> imagePaths;

  final int savedAtMs;

  MotionMyTemplate copyWith({
    String? name,
    MotionScene? scene,
    Map<String, String>? imagePaths,
    int? savedAtMs,
  }) {
    return MotionMyTemplate(
      id: id,
      name: name ?? this.name,
      category: category,
      baseTemplateId: baseTemplateId,
      scene: scene ?? this.scene,
      imagePaths: imagePaths ?? this.imagePaths,
      savedAtMs: savedAtMs ?? this.savedAtMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'base': baseTemplateId,
        'scene': scene.toJson(),
        'images': imagePaths,
        'savedAt': savedAtMs,
      };

  static MotionMyTemplate? fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    final rawScene = json['scene'];
    if (id.isEmpty || rawScene is! Map) return null;
    final scene = MotionScene.fromJson(rawScene.cast<String, dynamic>());
    if (scene == null) return null;
    final rawImages = json['images'];
    return MotionMyTemplate(
      id: id,
      name: (json['name'] ?? 'My Template').toString(),
      category: (json['category'] ?? 'titles').toString(),
      baseTemplateId: json['base']?.toString(),
      scene: scene,
      imagePaths: rawImages is Map
          ? rawImages.map((k, v) => MapEntry(k.toString(), v.toString()))
          : const {},
      savedAtMs:
          json['savedAt'] is num ? (json['savedAt'] as num).toInt() : 0,
    );
  }
}

/// The store itself: load / upsert / delete over one
/// SharedPreferences key.
class MotionMyTemplates {
  MotionMyTemplates._();

  static const String storageKey = 'tjpro_motion_my_templates_v1';

  static String newId() =>
      'my-${DateTime.now().millisecondsSinceEpoch}';

  static Future<List<MotionMyTemplate>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => MotionMyTemplate.fromJson(m.cast<String, dynamic>()))
          .whereType<MotionMyTemplate>()
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Insert or replace by id; returns the fresh list (newest
  /// first, matching the Gallery's My Templates order).
  static Future<List<MotionMyTemplate>> save(MotionMyTemplate t) async {
    final items = List<MotionMyTemplate>.from(await load());
    items.removeWhere((e) => e.id == t.id);
    items.insert(0, t);
    await _persist(items);
    return items;
  }

  static Future<List<MotionMyTemplate>> delete(String id) async {
    final items = List<MotionMyTemplate>.from(await load());
    items.removeWhere((e) => e.id == id);
    await _persist(items);
    return items;
  }

  static Future<void> _persist(List<MotionMyTemplate> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        storageKey,
        jsonEncode(items.map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // Saving must never crash the Editor; the caller reports
      // the visible result through its own status line.
    }
  }
}
