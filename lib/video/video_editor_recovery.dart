/// Build 10 (v1.8.0) — Video Editor session recovery
/// (fix-list point #7F).
///
/// The News Maker side already autosaved (500 ms debounce →
/// NewsProjectStore) with a recovery card. The VIDEO EDITOR
/// had no autosave at all: kill the app mid-edit and the
/// timeline was gone. This file is the missing half:
///
/// * [VideoEditorSession] — a pure, JSON-safe snapshot of an
///   editing session: every clip's file + editable fields
///   (the same fields [VideoClip.copy] carries) and the
///   editor's panel snapshot map, plus the selected index.
/// * [VideoEditorRecoveryStore] — SharedPreferences
///   persistence for ONE rolling session (the latest work is
///   the draft, CapCut-style), fail-soft in both directions.
///
/// The screen drives it: a periodic save while editing, and
/// on a plain (no project / no initial video) open, an offer
/// to restore when a fresh-enough session with surviving
/// clip files exists. Restoring is always the user's tap —
/// nothing is ever forced over a fresh editor.
library;

import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'editor_models.dart';

class VideoEditorSession {
  const VideoEditorSession({
    required this.clips,
    required this.panel,
    required this.selected,
    required this.savedAtMs,
  });

  /// One map per clip (see [clipToMap]).
  final List<Map<String, Object?>> clips;

  /// The editor's panel snapshot (JSON-safe values only).
  final Map<String, Object?> panel;

  /// Selected clip index at save time.
  final int selected;

  /// Save time, milliseconds since epoch.
  final int savedAtMs;

  /// Sessions older than this are treated as abandoned —
  /// the media they point at is likely gone or irrelevant.
  static const Duration maxAge = Duration(days: 7);

  bool isFresh(DateTime now) {
    final age = now.millisecondsSinceEpoch - savedAtMs;
    return age >= 0 && age <= maxAge.inMilliseconds;
  }

  String encode() => jsonEncode(<String, Object?>{
        'clips': clips,
        'panel': panel,
        'selected': selected,
        'savedAtMs': savedAtMs,
      });

  /// Parses [raw]; null on ANY shape problem (a corrupt
  /// snapshot must fail alone — SafeOps territory — never
  /// take the editor down with it).
  static VideoEditorSession? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final rawClips = decoded['clips'];
      if (rawClips is! List) return null;
      final clips = <Map<String, Object?>>[];
      for (final c in rawClips) {
        if (c is Map) {
          clips.add(Map<String, Object?>.from(c));
        }
      }
      final rawPanel = decoded['panel'];
      final panel = rawPanel is Map
          ? Map<String, Object?>.from(rawPanel)
          : <String, Object?>{};
      final selected = decoded['selected'];
      final savedAt = decoded['savedAtMs'];
      return VideoEditorSession(
        clips: clips,
        panel: panel,
        selected: selected is num ? selected.toInt() : 0,
        savedAtMs: savedAt is num ? savedAt.toInt() : 0,
      );
    } catch (_) {
      return null;
    }
  }

  /// [VideoClip] → its session map: the file path plus every
  /// editable field [VideoClip.copy] preserves.
  static Map<String, Object?> clipToMap(VideoClip clip) =>
      <String, Object?>{
        'path': clip.file.path,
        'durationMs': clip.duration.inMilliseconds,
        'aspect': clip.aspectRatio,
        'trimStart': clip.trimStart,
        'trimEnd': clip.trimEnd,
        'isPhoto': clip.isPhoto,
        'kenBurns': clip.kenBurns,
        'kbZoomIn': clip.kbZoomIn,
        'volume': clip.volume,
        'muted': clip.muted,
        'detachedAudioPath': clip.detachedAudioPath,
        // v1.17.0 G5: a stabilization bake must survive an
        // editor reopen — re-rendering it would defeat the
        // apply-time bake entirely.
        'stabBakedPath': clip.stabBakedPath,
        'stabBakedFor': clip.stabBakedFor,
        'stabBakedLevel': clip.stabBakedLevel,
      };

  /// A session map → [VideoClip]; null when the map lacks a
  /// usable path. File EXISTENCE is the caller's check (the
  /// screen skips clips whose media is gone).
  static VideoClip? clipFromMap(Map<String, Object?> map) {
    final path = map['path'];
    if (path is! String || path.isEmpty) return null;
    final durationMs = map['durationMs'];
    final aspect = map['aspect'];
    final clip = VideoClip(
      File(path),
      Duration(milliseconds: durationMs is num ? durationMs.toInt() : 0),
      aspect is num ? aspect.toDouble() : 1,
    );
    double d(String key, double fallback) {
      final v = map[key];
      return v is num ? v.toDouble() : fallback;
    }

    clip.trimStart = d('trimStart', 0);
    clip.trimEnd = d('trimEnd', -1);
    clip.isPhoto = map['isPhoto'] == true;
    clip.kenBurns = map['kenBurns'] != false;
    clip.kbZoomIn = map['kbZoomIn'] != false;
    clip.volume = d('volume', 1);
    clip.muted = map['muted'] == true;
    final detached = map['detachedAudioPath'];
    clip.detachedAudioPath = detached is String ? detached : null;
    final stabPath = map['stabBakedPath'];
    clip.stabBakedPath = stabPath is String ? stabPath : null;
    final stabFor = map['stabBakedFor'];
    clip.stabBakedFor = stabFor is String ? stabFor : null;
    final stabLevel = map['stabBakedLevel'];
    clip.stabBakedLevel = stabLevel is num ? stabLevel.toInt() : 0;
    return clip;
  }
}

/// SharedPreferences persistence for the one rolling video
/// editor session. Every method is fail-soft: a storage
/// problem loses the draft, never the editing session.
class VideoEditorRecoveryStore {
  VideoEditorRecoveryStore._();

  static const String _key = 'tjpro_video_editor_session_v1';

  static Future<void> save(String encodedSession) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, encodedSession);
    } catch (_) {
      // Draft lost, editing unaffected.
    }
  }

  static Future<String?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Nothing to clear reliably — the next save overwrites.
    }
  }
}
