/// Gemini voiceover for News Studio (v1).
///
/// Turns tehreer (news script) into one voiceover WAV through the Nigraan
/// TTS proxy — the same live endpoint the website TTS tool uses:
///
///   POST https://nigraan-tv-tts-proxy.mithubhattijani.workers.dev/tts
///   JSON {text, voice, lang}  →  {audio: base64, format: "wav"|"pcm24k",
///   mime, model, voice, keyIndex}
///
/// Rules the proxy enforces (verified in tts-proxy/worker.js — break
/// these and the call fails):
///   - text max 2000 chars per request — longer tehreer is chunked here.
///   - NEVER prefix the text with a language label ("in Urdu: …" etc.).
///   - NEVER send `systemInstruction` — the endpoint returns HTTP 400.
///   - `format: "pcm24k"` is raw 16-bit PCM, 24 kHz, mono — converted to
///     WAV with FFmpeg before the concat step. `format: "wav"` is used
///     as-is (detected by the proxy from the RIFF "UklGR" prefix).
///
/// Flow: chunk tehreer into ≤2000-char sentences → one POST per chunk →
/// base64 audio → per-chunk WAV files → ffmpeg-concat into one voiceover
/// WAV. Cache-first: the final WAV is keyed by a hash of
/// (text + voice + lang), so the same tehreer costs 0 new Gemini calls.
/// Voices: Aoede (female, default) / Charon (male). `lang` is auto-
/// detected from the script — `ur` when the text has Arabic-script
/// (Urdu/Arabic/Persian) characters, `en` otherwise.
///
/// TTS CAP — 5 requests/day per user (user decision 20 Nov 2026).
/// The cap counts proxy POSTs (one per chunk), keyed by local date, in a
/// small JSON file in the app documents directory. The three admin
/// emails — mithubhattijani@gmail.com, ghulamjillani019@gmail.com,
/// jaanirecords2@gmail.com — are EXEMPT (no cap, no coins). This local
/// check is a courtesy limit only: a client-side check is trivially
/// bypassed, so SERVER-SIDE enforcement lands with the login/coins
/// track (the proxy must count per authenticated user there). The
/// login track HAS landed (Phase 10): [_isAdmin] now reads the
/// server-fed [AuthService.isAdmin] flag, so a signed-in admin is
/// exempt; guests (no session) are capped like everyone else.
/// When the cap is hit — or the proxy fails — the service falls back to
/// the on-device voice ([FlutterTts], already a dependency): robotic,
/// but the reel still gets a voiceover. Fresh code — NOT copied from the
/// dead `lib/screens/` duplicate (deleted in this same change).
///
/// Gemini TTS free tier is 10 requests/day PER PROJECT, shared across
/// the website TTS tool + Magic Box + every TJ Pro user — that is why
/// the per-user cap + cache-first exist. A ~400-word tehreer is 2,000+
/// chars → 2 requests.
library;

import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'auth_service.dart';
import 'tts_processing.dart';

/// Gemini voices available in News Maker. Aoede is the default.
enum GeminiVoice {
  aoede('Aoede', 'Female'),
  charon('Charon', 'Male');

  const GeminiVoice(this.apiName, this.label);
  final String apiName;
  final String label;
}

/// Result of one voiceover build.
class VoiceoverResult {
  VoiceoverResult({
    required this.file,
    required this.cached,
    required this.usedDeviceFallback,
    required this.proxyRequests,
  });

  /// The final voiceover file (WAV by default, MP3 when
  /// `format: 'mp3'` was requested) in the voice cache directory.
  final File file;

  /// True when the file came from the cache — 0 new Gemini calls.
  final bool cached;

  /// True when the device voice was used (cap hit or proxy failure).
  final bool usedDeviceFallback;

  /// How many proxy POSTs this call made (0 when cached / fallback).
  final int proxyRequests;
}

/// Thrown when neither the proxy nor the device voice could produce audio.
class GeminiVoiceException implements Exception {
  GeminiVoiceException(this.message);
  final String message;
  @override
  String toString() => 'GeminiVoiceException: $message';
}

class GeminiVoiceService {
  static const _ttsUrl =
      'https://nigraan-tv-tts-proxy.mithubhattijani.workers.dev/tts';

  /// Max chars per proxy request (proxy-side limit).
  static const maxChunkChars = 2000;

  /// TTS cap: proxy requests per user per day (user decision 20 Nov 2026).
  static const dailyCap = 5;

  /// Admin emails — exempt from the cap (no cap, no coins).
  static const adminEmails = <String>{
    'mithubhattijani@gmail.com',
    'ghulamjillani019@gmail.com',
    'jaanirecords2@gmail.com',
  };

  static const _cacheDirName = 'gemini_voice_cache';
  static const _usageFileName = 'gemini_voice_usage.json';

  /// Signed-in user email, when the login track lands. Null until then —
  /// with no login, nobody is an admin and the cap applies to everyone.
  /// (Kept as an instance override for tests / manual wiring; in
  /// production [_isAdmin] reads the server-fed flag — see below.)
  String? currentUserEmail;

  /// Admin check — local only. Server-side enforcement lands with the
  /// login/coins track; never rely on this alone for billing.
  static bool isAdminEmail(String? email) {
    if (email == null) return false;
    return adminEmails.contains(email.trim().toLowerCase());
  }

  /// Admin for the TTS cap: the SERVER-fed flag first
  /// ([AuthService.isAdmin], refreshed at startup and on every
  /// sign-in — Phase 10 wiring), falling back to the instance email
  /// override above. Before Phase 10 this read ONLY the instance
  /// field, which production never set — so admins were wrongly
  /// capped at 5/day. The cap itself is local-only (the proxy has
  /// no user identity); the coin bypass, unlike the cap, is enforced
  /// server-side in tjpro-spend-coins.
  bool get _isAdmin =>
      AuthService.isAdmin.value || isAdminEmail(currentUserEmail);

  Future<Directory> _cacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _cacheDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Detects the proxy `lang` from the script: `ur` when the text has
  /// Arabic-script characters (Urdu/Arabic/Persian), `en` otherwise.
  static String detectLang(String text) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(text) ? 'ur' : 'en';
  }

  /// 32-bit FNV-1a hash, hex — a stable, dependency-free cache key.
  /// (Dart's String.hashCode is NOT stable across runs, so it cannot key
  /// an on-disk cache.)
  static String _hash(String input) {
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode(input)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String _cacheKey(
    String text,
    GeminiVoice voice,
    String lang, {
    TtsControls controls = const TtsControls(),
    bool backgroundMusic = false,
    String format = 'wav',
  }) =>
      '${voice.apiName.toLowerCase()}_${lang}_${text.length}_${_hash(text)}'
      '${controls.cacheSuffix}${backgroundMusic ? '|music' : ''}|$format';

  // ---- Daily usage counter (local date-keyed JSON) ----

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<Map<String, dynamic>> _readUsage() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final file = File(p.join(docs.path, _usageFileName));
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (data is Map<String, dynamic>) return data;
      }
    } catch (_) {}
    return {};
  }

  Future<int> usedToday() async {
    if (_isAdmin) return 0;
    final usage = await _readUsage();
    return (usage[_todayKey()] as num?)?.toInt() ?? 0;
  }

  /// Proxy requests left today.
  ///
  /// Returns -1 for admins, meaning "unlimited" — callers must
  /// check for -1 and show no cap counter in that case. Everyone
  /// else gets the real remaining count (0–[dailyCap]).
  Future<int> remainingToday() async {
    if (_isAdmin) return -1;
    return (dailyCap - await usedToday()).clamp(0, dailyCap);
  }

  /// Records [count] proxy requests against the shared 5/day cap.
  /// Public so the TTS Studio shares the SAME counter as the News
  /// Maker voiceover (one counter, not two — see
  /// `magic-box-port.md` §6C). Admins are never counted.
  Future<void> recordUsage(int count) => _recordUse(count);

  Future<void> _recordUse(int count) async {
    if (_isAdmin || count <= 0) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final file = File(p.join(docs.path, _usageFileName));
      final usage = await _readUsage();
      final key = _todayKey();
      usage[key] = ((usage[key] as num?)?.toInt() ?? 0) + count;
      await file.writeAsString(jsonEncode(usage));
    } catch (_) {
      // A failed counter write must never block the voiceover itself.
    }
  }

  // ---- Chunking ----

  /// Splits [text] into chunks of at most [maxChunkChars] chars, breaking
  /// only on sentence boundaries (`. ! ? ؟ ۔` and newlines) so no sentence
  /// is ever cut mid-way. A single over-long sentence is hard-split.
  static List<String> chunkText(String text, {int maxChars = maxChunkChars}) {
    final sentences = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      buffer.write(ch);
      if ('.!?؟۔\n'.contains(ch)) {
        final sentence = buffer.toString().trim();
        if (sentence.isNotEmpty) sentences.add(sentence);
        buffer.clear();
      }
    }
    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) sentences.add(tail);

    final chunks = <String>[];
    final current = StringBuffer();
    for (final sentence in sentences) {
      if (sentence.length > maxChars) {
        if (current.isNotEmpty) {
          chunks.add(current.toString().trim());
          current.clear();
        }
        for (var i = 0; i < sentence.length; i += maxChars) {
          final end =
              (i + maxChars < sentence.length) ? i + maxChars : sentence.length;
          chunks.add(sentence.substring(i, end));
        }
        continue;
      }
      if (current.isEmpty) {
        current.write(sentence);
      } else if (current.length + 1 + sentence.length <= maxChars) {
        current.write(' $sentence');
      } else {
        chunks.add(current.toString().trim());
        current.clear();
        current.write(sentence);
      }
    }
    if (current.isNotEmpty) chunks.add(current.toString().trim());
    return chunks.where((c) => c.isNotEmpty).toList();
  }

  // ---- Proxy ----

  /// One proxy POST. Returns the chunk as a WAV file.
  /// Throws on any non-200 status, bad JSON, or missing audio.
  Future<File> _fetchChunk({
    required String text,
    required GeminiVoice voice,
    required String lang,
    required Directory workDir,
    required int index,
  }) async {
    final response = await http
        .post(
          Uri.parse(_ttsUrl),
          headers: {'Content-Type': 'application/json'},
          // NEVER a language label prefix, NEVER systemInstruction —
          // the endpoint returns HTTP 400 for it.
          body: jsonEncode({'text': text, 'voice': voice.apiName, 'lang': lang}),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw GeminiVoiceException(
        'TTS proxy ${response.statusCode}: ${response.body}',
      );
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      throw GeminiVoiceException('TTS proxy: unexpected response shape');
    }
    final audioB64 = (data['audio'] as String?) ?? '';
    if (audioB64.isEmpty) {
      throw GeminiVoiceException('TTS proxy: empty audio in response');
    }
    final bytes = base64Decode(audioB64);
    if (bytes.isEmpty) {
      throw GeminiVoiceException('TTS proxy: empty audio in response');
    }
    final chunkFile = File(p.join(workDir.path, 'chunk_$index.wav'));
    if (data['format'] == 'pcm24k') {
      // Raw 16-bit PCM, 24 kHz, mono — wrap it as WAV before concat.
      final pcmFile = File(p.join(workDir.path, 'chunk_$index.pcm'));
      await pcmFile.writeAsBytes(bytes);
      final session = await FFmpegKit.execute(
        "-f s16le -ar 24000 -ac 1 -i ${FfmpegQuoting.q(pcmFile.path)} "
        "${FfmpegQuoting.q(chunkFile.path)} -y",
      );
      final rc = await session.getReturnCode();
      if ((rc?.getValue() ?? -1) != 0) {
        throw GeminiVoiceException('PCM → WAV conversion failed');
      }
      await pcmFile.delete().catchError((_) => pcmFile);
    } else {
      await chunkFile.writeAsBytes(bytes);
    }
    return chunkFile;
  }

  /// Concatenates [wavFiles] into [output] with the FFmpeg concat
  /// demuxer (re-encoded to pcm_s16le so mixed chunk formats still join).
  Future<void> _concatWavs(List<File> wavFiles, File output) async {
    final dir = output.parent;
    final listFile = File(p.join(dir.path, 'concat.txt'));
    final lines = wavFiles
        .map((f) => "file '${f.path.replaceAll("'", "'\\''")}'")
        .join('\n');
    await listFile.writeAsString(lines);
    final session = await FFmpegKit.execute(
      "-f concat -safe 0 -i ${FfmpegQuoting.q(listFile.path)} "
      "-c:a pcm_s16le ${FfmpegQuoting.q(output.path)} -y",
    );
    final rc = await session.getReturnCode();
    if ((rc?.getValue() ?? -1) != 0) {
      throw GeminiVoiceException('Voiceover concat failed');
    }
    await listFile.delete().catchError((_) => listFile);
  }

  // ---- Device-TTS fallback ----

  /// On-device voice fallback (flutter_tts): synthesizes each chunk to a
  /// file and concats them, same as the proxy path. Returns null when the
  /// device voice cannot produce a file either.
  Future<File?> _deviceFallback({
    required String text,
    required String lang,
    required Directory workDir,
    required File output,
  }) async {
    try {
      final tts = FlutterTts();
      await tts.setLanguage(lang == 'ur' ? 'ur-PK' : 'en-US');
      await tts.setSpeechRate(0.9);
      await tts.setPitch(1.0);
      final chunks = chunkText(text);
      final wavs = <File>[];
      for (var i = 0; i < chunks.length; i++) {
        final chunkFile = File(p.join(workDir.path, 'tts_$i.wav'));
        final result = await tts.synthesizeToFile(chunks[i], chunkFile.path);
        if (result != 1 || !await chunkFile.exists()) {
          return null;
        }
        wavs.add(chunkFile);
      }
      if (wavs.isEmpty) return null;
      if (wavs.length == 1) {
        await wavs.first.copy(output.path);
      } else {
        await _concatWavs(wavs, output);
      }
      return output;
    } catch (_) {
      return null;
    }
  }

  // ---- Public API ----

  /// True when this exact voice request is already cached on disk —
  /// the same key + file [synthesize] checks first, so a `true` here
  /// means the next [synthesize] call costs 0 new proxy calls (and
  /// 0 coins: the Phase 10 coin gate calls this BEFORE spending, so
  /// a cached voiceover is never charged). Never throws: any failure
  /// (e.g. documents dir unavailable) answers false, and the caller
  /// spends normally.
  Future<bool> hasCachedVoice(
    String text, {
    GeminiVoice voice = GeminiVoice.aoede,
    String? lang,
    TtsControls controls = const TtsControls(),
    bool backgroundMusic = false,
    String format = 'wav',
  }) async {
    try {
      final clean = text.trim();
      if (clean.isEmpty) return false;
      final dir = await _cacheDir();
      final key = _cacheKey(
        clean,
        voice,
        lang ?? detectLang(clean),
        controls: controls,
        backgroundMusic: backgroundMusic,
        format: format,
      );
      return await File(p.join(dir.path, '$key.$format')).exists();
    } catch (_) {
      return false;
    }
  }

  /// Builds the voiceover WAV for [text].
  ///
  /// Cache-first: the same text + voice + lang + [controls] +
  /// [backgroundMusic] + [format] returns the cached file with 0 new
  /// proxy calls. Otherwise one proxy POST per chunk (counted
  /// against the 5/day cap). When the cap is hit or the proxy fails,
  /// the device voice is used instead and
  /// [VoiceoverResult.usedDeviceFallback] is true. Throws
  /// [GeminiVoiceException] only when nothing produced audio at all.
  ///
  /// [controls] (speed 0.5–2.0x + pause between sentences, applied
  /// on-device to the WAV — see `tts_processing.dart`; speed also
  /// changes pitch, the UI says so) and [backgroundMusic] (soft
  /// generated pad mixed under the voice) are applied AFTER the
  /// concat, before the file is cached. [format] 'mp3' converts the
  /// final file via on-device ffmpeg (default 'wav').
  Future<VoiceoverResult> synthesize(
    String text, {
    GeminiVoice voice = GeminiVoice.aoede,
    String? lang,
    TtsControls controls = const TtsControls(),
    bool backgroundMusic = false,
    String format = 'wav',
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) {
      throw GeminiVoiceException('Tehreer khaali hai — pehle text likhein.');
    }
    if (format != 'wav' && format != 'mp3') {
      throw GeminiVoiceException('Format sirf wav ya mp3 ho sakta hai.');
    }
    final resolvedLang = lang ?? detectLang(clean);
    final dir = await _cacheDir();
    final key = _cacheKey(
      clean,
      voice,
      resolvedLang,
      controls: controls,
      backgroundMusic: backgroundMusic,
      format: format,
    );
    final cachedFile = File(p.join(dir.path, '$key.$format'));
    if (await cachedFile.exists()) {
      return VoiceoverResult(
        file: cachedFile,
        cached: true,
        usedDeviceFallback: false,
        proxyRequests: 0,
      );
    }

    final chunks = chunkText(clean);
    final workDir = Directory(p.join(dir.path, 'work_$key'));
    if (!await workDir.exists()) await workDir.create(recursive: true);
    // The base voiceover is always built as WAV first; controls /
    // music / format conversion happen after, before caching.
    final baseFile = File(p.join(workDir.path, 'base.wav'));
    try {
      final remaining = await remainingToday();
      File? result;
      var requests = 0;
      // -1 = admin (unlimited) — always allowed; otherwise the
      // remaining count must cover every chunk.
      if (remaining == -1 || remaining >= chunks.length) {
        try {
          final wavs = <File>[];
          for (var i = 0; i < chunks.length; i++) {
            wavs.add(await _fetchChunk(
              text: chunks[i],
              voice: voice,
              lang: resolvedLang,
              workDir: workDir,
              index: i,
            ));
          }
          if (wavs.length == 1) {
            await wavs.first.copy(baseFile.path);
          } else {
            await _concatWavs(wavs, baseFile);
          }
          await _recordUse(chunks.length);
          requests = chunks.length;
          result = baseFile;
        } catch (_) {
          // Proxy failed mid-way: fall through to the device voice.
          result = null;
        }
      }
      result ??= await _deviceFallback(
        text: clean,
        lang: resolvedLang,
        workDir: workDir,
        output: baseFile,
      );
      if (result == null || !await result.exists()) {
        throw GeminiVoiceException(
          'Voiceover nahi ban saka — proxy aur device voice dono fail.',
        );
      }
      // Post-process: speed/pause, music, format — then cache.
      var bytes = await result.readAsBytes();
      if (!controls.isDefault) {
        bytes = applyTtsControls(bytes, text: clean, controls: controls);
      }
      if (backgroundMusic) bytes = mixWavWithMusic(bytes);
      if (format == 'mp3') {
        bytes = await convertAudioBytes(bytes, fromExt: 'wav', toExt: 'mp3');
      }
      await cachedFile.writeAsBytes(bytes);
      return VoiceoverResult(
        file: cachedFile,
        cached: false,
        usedDeviceFallback: requests == 0,
        proxyRequests: requests,
      );
    } finally {
      await workDir.delete(recursive: true).catchError((_) => workDir);
    }
  }

  /// Clears the voice cache (frees disk; next synthesize re-calls).
  Future<void> clearCache() async {
    try {
      final dir = await _cacheDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}

/// Single-quote escaping for FFmpeg command strings (same rule as
/// FfmpegService.q — duplicated here so this service does not depend on
/// the video pipeline).
class FfmpegQuoting {
  static String q(String path) => "'${path.replaceAll("'", "'\\''")}'";
}
