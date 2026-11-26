/// Save files to the phone's Download folder (Phase 5).
///
/// Shared by the TTS Studio, Caption Studio, translator and Audio
/// Tools: every export (audio, SRT/VTT/TXT/ASS, captioned video,
/// converted audio) lands in `Download/` with a safe file name and
/// the caller shows the returned path. Throws when the folder cannot
/// be reached or the write fails — callers show the message.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DownloadService {
  /// File-safe version of [fileName] (anything outside
  /// A–Z/a–z/0–9/_/-/. becomes `_`).
  static String safeFileName(String fileName) =>
      fileName.replaceAll(RegExp(r'[^A-Za-z0-9_.\-]'), '_');

  /// The phone's Download directory (created when missing).
  static Future<Directory> downloadsDir() async {
    final extDir = await getExternalStorageDirectory();
    if (extDir == null) {
      throw Exception('Downloads folder not found.');
    }
    final dir = Directory(p.join(extDir.path, 'Download'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Writes [bytes] as [fileName] into Download. Returns the full path.
  static Future<String> saveBytes(String fileName, List<int> bytes) async {
    final dir = await downloadsDir();
    final file = File(p.join(dir.path, safeFileName(fileName)));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Copies [source] into Download as [fileName]. Returns the new path.
  static Future<String> copyFile(File source, String fileName) async {
    final dir = await downloadsDir();
    final dest = File(p.join(dir.path, safeFileName(fileName)));
    await source.copy(dest.path);
    return dest.path;
  }
}
