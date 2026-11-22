/// Local project index for the Projects hub (v1.4.0).
///
/// Every project started from the hub (Video / Photo / News) is
/// recorded here so the hub's MY PROJECTS list can show it again and
/// reopen the section's editor. The index is one JSON list in
/// SharedPreferences under a single key — the same fail-soft pattern
/// as the other local services: any storage problem degrades to an
/// empty list, never a crash, and the editors themselves never read
/// this store (they keep their own session state).
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One hub project entry.
///
/// [kind] is 'photo', 'video' or 'news'. [mediaPath] is the gallery
/// file the project was started from (null for a blank-canvas start);
/// [thumbPath] is an optional thumbnail image path (defaults to
/// [mediaPath] when that is an image).
class ProjectEntry {
  ProjectEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.ratioLabel,
    this.mediaPath,
    this.thumbPath,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String kind;
  final String title;
  final String ratioLabel;
  final String? mediaPath;
  final String? thumbPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProjectEntry copyWith({
    String? title,
    String? ratioLabel,
    String? mediaPath,
    String? thumbPath,
    DateTime? updatedAt,
  }) {
    return ProjectEntry(
      id: id,
      kind: kind,
      title: title ?? this.title,
      ratioLabel: ratioLabel ?? this.ratioLabel,
      mediaPath: mediaPath ?? this.mediaPath,
      thumbPath: thumbPath ?? this.thumbPath,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind,
        'title': title,
        'ratioLabel': ratioLabel,
        'mediaPath': mediaPath,
        'thumbPath': thumbPath,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static ProjectEntry? fromJson(Map<String, dynamic> json) {
    final Object? id = json['id'];
    final Object? kind = json['kind'];
    if (id is! String || id.isEmpty || kind is! String) {
      return null;
    }
    final Object? media = json['mediaPath'];
    final Object? thumb = json['thumbPath'];
    return ProjectEntry(
      id: id,
      kind: kind,
      title: json['title'] is String ? json['title'] as String : 'Project',
      ratioLabel:
          json['ratioLabel'] is String ? json['ratioLabel'] as String : '9:16',
      mediaPath: media is String && media.isNotEmpty ? media : null,
      thumbPath: thumb is String && thumb.isNotEmpty ? thumb : null,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
              DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
              DateTime.now(),
    );
  }
}

/// Singleton store for [ProjectEntry] records, newest activity first.
class ProjectStore {
  ProjectStore._();

  static final ProjectStore instance = ProjectStore._();

  static const String _key = 'tjpro_projects_v1';

  List<ProjectEntry> _entries = <ProjectEntry>[];
  bool _loaded = false;

  /// All entries, most recently updated first.
  List<ProjectEntry> get entries =>
      List<ProjectEntry>.unmodifiable(_entries);

  /// Entries of one kind ('photo' | 'video' | 'news'), newest first.
  List<ProjectEntry> forKind(String kind) =>
      _entries.where((ProjectEntry e) => e.kind == kind).toList();

  /// Loads the persisted index into memory. Fail-soft: any problem
  /// leaves an empty index.
  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_key);
      final List<ProjectEntry> parsed = <ProjectEntry>[];
      if (raw != null && raw.isNotEmpty) {
        final Object? decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final Object? item in decoded) {
            if (item is Map<String, dynamic>) {
              final ProjectEntry? entry = ProjectEntry.fromJson(item);
              if (entry != null) {
                parsed.add(entry);
              }
            }
          }
        }
      }
      parsed.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _entries = parsed;
    } catch (_) {
      _entries = <ProjectEntry>[];
    }
    _loaded = true;
  }

  Future<void> _ensureLoaded() async {
    if (!_loaded) {
      await load();
    }
  }

  Future<void> _save() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(_entries.map((ProjectEntry e) => e.toJson()).toList()),
      );
    } catch (_) {
      // Fail-soft: the in-memory list still serves this session.
    }
  }

  /// Adds [entry] at the top of the index and persists it.
  Future<void> add(ProjectEntry entry) async {
    await _ensureLoaded();
    _entries = <ProjectEntry>[
      entry,
      ..._entries.where((ProjectEntry e) => e.id != entry.id),
    ];
    await _save();
  }

  /// Replaces the entry with the same id (used to bump `updatedAt`
  /// when a project is reopened) and persists the index.
  Future<void> update(ProjectEntry entry) async {
    await _ensureLoaded();
    final int i = _entries.indexWhere((ProjectEntry e) => e.id == entry.id);
    if (i < 0) {
      return;
    }
    _entries[i] = entry;
    _entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _save();
  }

  /// Removes the entry with [id] and persists the index.
  Future<void> delete(String id) async {
    await _ensureLoaded();
    _entries.removeWhere((ProjectEntry e) => e.id == id);
    await _save();
  }
}
