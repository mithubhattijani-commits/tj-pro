/// TTS Studio history — "My Audio" (Phase 5, ported from Magic
/// Box's `tts_history_service.dart` — adapted: Magic Box stores
/// history in SharedPreferences; TJ Pro stores it as one JSON file
/// in the app documents directory (`tts_history.json`), so no new
/// dependency is needed).
///
/// Every TTS Studio generation is recorded: text, voice, language,
/// format, file path, duration, size, fallbacks used. The file
/// itself lives in the TTS cache dir; deleting a history entry does
/// NOT delete the audio file (the cache evicts on its own), but a
/// history entry whose file is gone shows as unavailable in the UI.
///
/// [directoryOverride] is the test seam: unit tests pass a temp dir.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One recorded TTS generation.
class TtsHistoryEntry {
  TtsHistoryEntry({
    required this.id,
    required this.text,
    required this.voiceId,
    required this.lang,
    required this.ext,
    required this.filePath,
    required this.durationSec,
    required this.sizeBytes,
    required this.createdAt,
    this.fellBackToEdge = false,
    this.fellBackToGemini = false,
  });

  final String id;
  final String text;
  final String voiceId;
  final String lang;

  /// 'wav' or 'mp3'.
  final String ext;
  final String filePath;
  final double durationSec;
  final int sizeBytes;
  final DateTime createdAt;
  final bool fellBackToEdge;
  final bool fellBackToGemini;

  /// One-line summary, as shown in the history list.
  String get summary =>
      '${ext.toUpperCase()} • $voiceId • ${_mmss(durationSec)} • '
      '${_sizeLabel(sizeBytes)}';

  static String _mmss(double seconds) {
    final total = seconds.round();
    return '${(total ~/ 60).toString().padLeft(2, '0')}:'
        '${(total % 60).toString().padLeft(2, '0')}';
  }

  static String _sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'voiceId': voiceId,
        'lang': lang,
        'ext': ext,
        'filePath': filePath,
        'durationSec': durationSec,
        'sizeBytes': sizeBytes,
        'createdAt': createdAt.toIso8601String(),
        'fellBackToEdge': fellBackToEdge,
        'fellBackToGemini': fellBackToGemini,
      };

  static TtsHistoryEntry fromJson(Map<String, dynamic> json) {
    return TtsHistoryEntry(
      id: (json['id'] as String?) ?? '',
      text: (json['text'] as String?) ?? '',
      voiceId: (json['voiceId'] as String?) ?? '',
      lang: (json['lang'] as String?) ?? 'ur',
      ext: (json['ext'] as String?) ?? 'wav',
      filePath: (json['filePath'] as String?) ?? '',
      durationSec: (json['durationSec'] as num?)?.toDouble() ?? 0,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
              DateTime.now(),
      fellBackToEdge: (json['fellBackToEdge'] as bool?) ?? false,
      fellBackToGemini: (json['fellBackToGemini'] as bool?) ?? false,
    );
  }
}

class TtsHistoryService {
  TtsHistoryService({this.directoryOverride});

  /// Test seam — a temp dir instead of the app documents directory.
  final Directory? directoryOverride;

  static const _fileName = 'tts_history.json';

  /// Newest entries first, at most 100 kept.
  static const maxEntries = 100;

  Future<File> _file() async {
    final dir = directoryOverride ??
        await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _fileName));
  }

  Future<List<TtsHistoryEntry>> loadAll() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final data = jsonDecode(await file.readAsString());
      if (data is! List) return [];
      final entries = <TtsHistoryEntry>[];
      for (final e in data) {
        if (e is Map<String, dynamic>) entries.add(TtsHistoryEntry.fromJson(e));
      }
      entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return entries;
    } catch (_) {
      return [];
    }
  }

  /// Records [entry] (newest first, capped at [maxEntries]).
  /// A failed write never throws.
  Future<void> record(TtsHistoryEntry entry) async {
    try {
      final entries = await loadAll();
      entries.insert(0, entry);
      final trimmed = entries.take(maxEntries).toList();
      final file = await _file();
      await file.writeAsString(
        jsonEncode(trimmed.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  /// Removes one entry by id. Returns true when something was removed.
  Future<bool> remove(String id) async {
    try {
      final entries = await loadAll();
      final before = entries.length;
      entries.removeWhere((e) => e.id == id);
      if (entries.length == before) return false;
      final file = await _file();
      await file.writeAsString(
        jsonEncode(entries.map((e) => e.toJson()).toList()),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Clears the whole history. Never throws.
  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
