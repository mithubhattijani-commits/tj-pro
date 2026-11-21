/// TTS Studio service (Phase 5, ported from Magic Box's
/// `lib/services/tts_service.dart` + `lib/screens/tts_screen.dart`,
/// v1.0.13 — adapted to TJ Pro):
///
///   - Voices are named Aoede / Charon (TJ Pro's names), NOT
///     "Billo"/"Jaani". Asad / Uzma keep their own names (they are
///     the Edge voices' real names). The 4 gated Gemini voices
///     (Kore / Fenrir / Puck / Zephyr) are offered under their API
///     names — the proxy's ALLOWED_VOICES already includes them, so
///     no Worker change is needed.
///   - NO coin economy: generation costs nothing in coins. The
///     shared cap is TJ Pro's 5 proxy requests/day per user (same
///     counter as the News Maker voiceover — see
///     `GeminiVoiceService`), admins exempt. Cache-first: the same
///     text + voice + lang + controls costs 0 new requests.
///   - NO `POST /transcribe` anywhere (TJ Pro's on-device Whisper
///     replaces it).
///   - Edge `/edge-tts` needs NO client token: the token lives
///     server-side in the Worker (`EDGE_TRUSTED_CLIENT_TOKEN` —
///     verified in `tts-proxy/worker.js`). The app posts plain
///     `{text, voice}` like Magic Box does.
///   - Gemini → Edge fallback (T4) and Edge → Gemini fallback (T5)
///     are ported together, never one alone: Edge fails
///     deterministically on some short texts (e.g. a lone
///     "Assalam-o-Alaikum" → 502 Microsoft-side), and the Gemini
///     fallback is what saves it.
///
/// Chunking: Gemini ≤2000 chars (TJ Pro's voiceover chunk size —
/// Magic Box used 1500, TJ Pro's 2000 is fine per `magic-box-port.md`
/// §6B), Edge ≤550 chars (proxy limit is 600; 550 leaves margin).
/// Speed/pause controls apply to Gemini WAV only; Edge MP3 ignores
/// them (the screen disables the controls for Edge voices).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'gemini_voice_service.dart';
import 'mp3_utils.dart';
import 'tts_processing.dart';
import 'wav_utils.dart';

/// TTS engine behind a studio voice.
enum StudioTtsEngine { gemini, edge }

/// One TTS Studio voice. `label` is the name shown in the UI —
/// API names for Gemini voices (Aoede/Charon/Kore/…), real names
/// for Edge voices (Asad/Uzma). No nicknames.
class StudioVoice {
  const StudioVoice({
    required this.id,
    required this.label,
    required this.gender,
    required this.engine,
    required this.apiName,
  });

  final String id;
  final String label;

  /// 'Female' or 'Male'.
  final String gender;
  final StudioTtsEngine engine;

  /// Voice name sent to the proxy.
  final String apiName;

  /// Max chars per proxy request for this voice's engine.
  int get maxChars =>
      engine == StudioTtsEngine.gemini ? TtsStudioService.geminiMaxChars : TtsStudioService.edgeMaxChars;

  static const StudioVoice aoede = StudioVoice(
    id: 'aoede',
    label: 'Aoede',
    gender: 'Female',
    engine: StudioTtsEngine.gemini,
    apiName: 'Aoede',
  );
  static const StudioVoice charon = StudioVoice(
    id: 'charon',
    label: 'Charon',
    gender: 'Male',
    engine: StudioTtsEngine.gemini,
    apiName: 'Charon',
  );
  static const StudioVoice asad = StudioVoice(
    id: 'asad',
    label: 'Asad',
    gender: 'Male',
    engine: StudioTtsEngine.edge,
    apiName: 'ur-PK-AsadNeural',
  );
  static const StudioVoice uzma = StudioVoice(
    id: 'uzma',
    label: 'Uzma',
    gender: 'Female',
    engine: StudioTtsEngine.edge,
    apiName: 'ur-PK-UzmaNeural',
  );
  static const StudioVoice kore = StudioVoice(
    id: 'kore',
    label: 'Kore',
    gender: 'Female',
    engine: StudioTtsEngine.gemini,
    apiName: 'Kore',
  );
  static const StudioVoice fenrir = StudioVoice(
    id: 'fenrir',
    label: 'Fenrir',
    gender: 'Male',
    engine: StudioTtsEngine.gemini,
    apiName: 'Fenrir',
  );
  static const StudioVoice puck = StudioVoice(
    id: 'puck',
    label: 'Puck',
    gender: 'Male',
    engine: StudioTtsEngine.gemini,
    apiName: 'Puck',
  );
  static const StudioVoice zephyr = StudioVoice(
    id: 'zephyr',
    label: 'Zephyr',
    gender: 'Female',
    engine: StudioTtsEngine.gemini,
    apiName: 'Zephyr',
  );

  static const List<StudioVoice> all = [
    aoede,
    charon,
    asad,
    uzma,
    kore,
    fenrir,
    puck,
    zephyr,
  ];

  static StudioVoice byId(String id) =>
      all.firstWhere((v) => v.id == id, orElse: () => aoede);
}

/// Audio for one generated chunk.
class GeneratedAudio {
  const GeneratedAudio({
    required this.bytes,
    required this.ext,
    this.fellBackToEdge = false,
    this.fellBackToGemini = false,
  });

  final Uint8List bytes;

  /// 'wav' (Gemini) or 'mp3' (Edge).
  final String ext;
  final bool fellBackToEdge;
  final bool fellBackToGemini;
}

/// Result of one full TTS Studio generation.
class TtsStudioResult {
  TtsStudioResult({
    required this.bytes,
    required this.ext,
    required this.cached,
    required this.usedDeviceFallback,
    required this.proxyRequests,
    this.fellBackToEdge = false,
    this.fellBackToGemini = false,
    this.controlsIgnored = false,
    this.filePath,
  });

  final Uint8List bytes;
  final String ext;
  final bool cached;
  final bool usedDeviceFallback;
  final int proxyRequests;
  final bool fellBackToEdge;
  final bool fellBackToGemini;

  /// Path of the cached result file (null only when the cache write
  /// failed — the bytes are still valid). Used for history, download
  /// and share.
  final String? filePath;

  /// True when speed/pause were requested for an Edge (MP3) voice —
  /// MP3 cannot be resampled without a decoder, so the controls were
  /// skipped and the audio is unmodified. The screen says so.
  final bool controlsIgnored;

  double get durationSec => audioDurationSeconds(bytes, ext);

  int get sizeBytes => bytes.length;
}

/// Thrown when the 5/day cap cannot cover a generation.
class TtsStudioCapException implements Exception {
  TtsStudioCapException(this.remaining, this.needed);
  final int remaining;
  final int needed;
  @override
  String toString() =>
      'TtsStudioCapException: $needed request(s) chahiye, aaj sirf '
      '$remaining baaki (cap 5/day).';
}

class TtsStudioService {
  TtsStudioService({GeminiVoiceService? voiceService})
      : _voiceService = voiceService ?? GeminiVoiceService();

  static const _base =
      'https://nigraan-tv-tts-proxy.mithubhattijani.workers.dev';

  /// Max chars per Gemini proxy request (same as the voiceover).
  static const geminiMaxChars = 2000;

  /// Max chars per Edge proxy request (proxy limit is 600; 550
  /// leaves margin).
  static const edgeMaxChars = 550;

  static const _cacheDirName = 'tts_studio_cache';
  static const _previewDirName = 'tts_previews';

  /// The cap counter is SHARED with the News Maker voiceover:
  /// one counter, not two (see `magic-box-port.md` §6C).
  final GeminiVoiceService _voiceService;

  Future<int> remainingToday() => _voiceService.remainingToday();

  // ---- Voices / fallbacks ----

  /// Same-gender Edge voice used as the Gemini fallback.
  static StudioVoice edgeFallbackFor(StudioVoice geminiVoice) =>
      geminiVoice.gender == 'Male' ? StudioVoice.asad : StudioVoice.uzma;

  /// Same-gender Gemini voice used when an Edge voice fails.
  static StudioVoice geminiFallbackFor(StudioVoice edgeVoice) =>
      edgeVoice.gender == 'Male' ? StudioVoice.charon : StudioVoice.aoede;

  // ---- Chunking ----

  /// Splits [text] into chunks of at most [voice.maxChars] chars,
  /// breaking on sentence boundaries first, then on words for long
  /// sentences. Pure — unit-tested.
  static List<String> chunkText(String text, StudioVoice voice) {
    final maxChars = voice.maxChars;
    final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return [];
    if (clean.length <= maxChars) return [clean];
    final sentences = clean.split(RegExp(r'(?<=[.!?؟۔])\s+'));
    final chunks = <String>[];
    var current = StringBuffer();
    void flush() {
      final s = current.toString().trim();
      if (s.isNotEmpty) chunks.add(s);
      current = StringBuffer();
    }

    for (final sentence in sentences) {
      if (sentence.length > maxChars) {
        flush();
        final words = sentence.split(' ');
        for (final word in words) {
          if (current.length + word.length + 1 > maxChars) flush();
          if (current.isNotEmpty) current.write(' ');
          current.write(word);
        }
        flush();
      } else {
        if (current.length + sentence.length + 1 > maxChars) flush();
        if (current.isNotEmpty) current.write(' ');
        current.write(sentence);
      }
    }
    flush();
    return chunks;
  }

  /// How many proxy requests a generation of [text] with [voice]
  /// needs (one per chunk). Shown live while typing.
  static int estimatedRequests(String text, StudioVoice voice) =>
      chunkText(text, voice).length;

  // ---- Tone presets (T8) ----

  /// Speed + pause combos: News (1.0x, 0.2s), Story (0.9x, 0.5s),
  /// Ad (1.15x, 0.1s). A manual change becomes a custom tone.
  static const Map<String, TtsControls> tonePresets = {
    'News': TtsControls(speed: 1.0, pauseSeconds: 0.2),
    'Story': TtsControls(speed: 0.9, pauseSeconds: 0.5),
    'Ad': TtsControls(speed: 1.15, pauseSeconds: 0.1),
  };

  // ---- Sample texts (T13) ----

  static const Map<String, String> sampleTexts = {
    'News':
        'شیخوپورہ میں پولیس نے بڑی کارروائی کرتے ہوئے بھاری مقدار میں شراب برآمد کر لی۔ ملزم کو گرفتار کر کے مقدمہ درج کر لیا گیا ہے۔',
    'Story':
        'ایک چھوٹے سے گاؤں میں رہنے والا لڑکا ہر روز صبح سویرے اٹھ کر اپنے خوابوں کی طرف ایک قدم بڑھاتا تھا۔',
    'Ad':
        'ابھی آرڈر کریں اور پائیں شاندار ڈسکاؤنٹ! محدود مدت کی آفر — دیر نہ کریں، آج ہی رابطہ کریں۔',
  };

  // ---- Proxy calls (one chunk, with fallback) ----

  /// Generate audio for ONE chunk, with automatic fallback:
  /// Gemini fails → same-gender free Edge voice; Edge fails →
  /// same-gender Gemini voice. Throws only when BOTH engines fail.
  Future<GeneratedAudio> generateChunkWithFallback(
    String text,
    StudioVoice voice, {
    String lang = 'ur',
    http.Client? client,
  }) async {
    if (voice.engine == StudioTtsEngine.gemini) {
      try {
        return await _generateGemini(text, voice, lang, client: client);
      } catch (_) {
        // Gemini busy / quota / error -> free Edge voice.
        final edgeVoice = edgeFallbackFor(voice);
        final gen = await _generateEdge(text, edgeVoice, client: client);
        return GeneratedAudio(
          bytes: gen.bytes,
          ext: gen.ext,
          fellBackToEdge: true,
        );
      }
    }
    return _generateEdgeWithGeminiFallback(text, voice, lang, client: client);
  }

  Future<GeneratedAudio> _generateGemini(
    String text,
    StudioVoice voice,
    String lang, {
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final res = await httpClient
          .post(
            Uri.parse('$_base/tts'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(
              {'text': text, 'voice': voice.apiName, 'lang': lang},
            ),
          )
          .timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) {
        throw Exception('TTS failed (${res.statusCode}): ${res.body}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final audioB64 = data['audio'] as String?;
      if (audioB64 == null || audioB64.isEmpty) {
        throw Exception('TTS returned no audio');
      }
      final raw = base64Decode(audioB64);
      final format = data['format'] as String? ?? '';
      // Raw PCM (24 kHz) gets a WAV header so normal players can
      // play it; WAV stays as-is.
      if (format == 'pcm24k') {
        return GeneratedAudio(
          bytes: encodeWav(
            sampleRate: 24000,
            channels: 1,
            bitsPerSample: 16,
            pcm: raw,
          ),
          ext: 'wav',
        );
      }
      return GeneratedAudio(bytes: raw, ext: 'wav');
    } finally {
      if (client == null) httpClient.close();
    }
  }

  Future<GeneratedAudio> _generateEdge(
    String text,
    StudioVoice voice, {
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    try {
      final res = await httpClient
          .post(
            Uri.parse('$_base/edge-tts'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text, 'voice': voice.apiName}),
          )
          .timeout(const Duration(seconds: 60));
      if (res.statusCode == 429) {
        throw Exception(
          'Daily Edge limit reached (10 minutes/day). Try a Gemini '
          'voice or come back tomorrow.',
        );
      }
      if (res.statusCode != 200) {
        throw Exception('Edge TTS failed (${res.statusCode}): ${res.body}');
      }
      // A 200 with (near-)empty audio is a failure too — Edge
      // returns an empty body for some short texts instead of an
      // error. Anything under 1 KB cannot be real speech.
      if (res.bodyBytes.length < 1024) {
        throw Exception(
          'Edge TTS returned empty audio (${res.bodyBytes.length} bytes)',
        );
      }
      return GeneratedAudio(bytes: res.bodyBytes, ext: 'mp3');
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// Edge generation with silent Gemini fallback: when Edge fails
  /// the SAME text is retried with the same-gender Gemini voice
  /// (Asad → Charon, Uzma → Aoede). Throws the ORIGINAL Edge error
  /// when Gemini also fails, so the user sees the real reason.
  Future<GeneratedAudio> _generateEdgeWithGeminiFallback(
    String text,
    StudioVoice edgeVoice,
    String lang, {
    http.Client? client,
  }) async {
    try {
      return await _generateEdge(text, edgeVoice, client: client);
    } catch (edgeError) {
      final geminiVoice = geminiFallbackFor(edgeVoice);
      try {
        final gen = await _generateGemini(
          text,
          geminiVoice,
          lang,
          client: client,
        );
        return GeneratedAudio(
          bytes: gen.bytes,
          ext: gen.ext,
          fellBackToGemini: true,
        );
      } catch (_) {
        throw edgeError;
      }
    }
  }

  // ---- Cache ----

  static String _hash(String input) {
    var hash = 0x811c9dc5;
    for (final unit in utf8.encode(input)) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Future<Directory> _cacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _cacheDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _cacheKey(
    String text,
    StudioVoice voice,
    String lang,
    TtsControls controls,
    bool music,
    String format,
  ) =>
      '${voice.id}_$lang${controls.cacheSuffix}'
      '${music ? '|music' : ''}|$format|${text.length}_${_hash(text)}';

  // ---- Full generation ----

  /// Generates [text] with [voice] into ONE audio file.
  ///
  /// Cache-first: the same text + voice + lang + controls + music +
  /// format returns the cached file with 0 new proxy calls.
  /// Otherwise one proxy POST per chunk, counted against the shared
  /// 5/day cap ([TtsStudioCapException] when the cap cannot cover
  /// the chunks — the caller may offer the device voice instead).
  /// [format] is 'wav' or 'mp3' (conversion via on-device ffmpeg).
  /// [music] mixes the generated ambient pad under the voice.
  /// Speed/pause [controls] apply to Gemini WAV only — for Edge
  /// (MP3) they are skipped and [TtsStudioResult.controlsIgnored]
  /// is true.
  Future<TtsStudioResult> generate(
    String text, {
    required StudioVoice voice,
    String? lang,
    TtsControls controls = const TtsControls(),
    bool music = false,
    String format = 'wav',
    http.Client? client,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) throw Exception('Text khaali hai — pehle likhein.');
    if (format != 'wav' && format != 'mp3') {
      throw Exception('Format sirf wav ya mp3 ho sakta hai.');
    }
    final resolvedLang = lang ?? GeminiVoiceService.detectLang(clean);
    final dir = await _cacheDir();
    final key = _cacheKey(clean, voice, resolvedLang, controls, music, format);
    final cachedFile = File(p.join(dir.path, '$key.$format'));
    if (await cachedFile.exists()) {
      final bytes = await cachedFile.readAsBytes();
      if (bytes.isNotEmpty) {
        return TtsStudioResult(
          bytes: bytes,
          ext: format,
          cached: true,
          usedDeviceFallback: false,
          proxyRequests: 0,
          filePath: cachedFile.path,
        );
      }
    }

    final chunks = chunkText(clean, voice);
    final remaining = await _voiceService.remainingToday();
    if (remaining < chunks.length) {
      throw TtsStudioCapException(remaining, chunks.length);
    }

    final parts = <GeneratedAudio>[];
    var fellBackToEdge = false;
    var fellBackToGemini = false;
    for (final chunk in chunks) {
      final gen = await generateChunkWithFallback(
        chunk,
        voice,
        lang: resolvedLang,
        client: client,
      );
      fellBackToEdge = fellBackToEdge || gen.fellBackToEdge;
      fellBackToGemini = fellBackToGemini || gen.fellBackToGemini;
      parts.add(gen);
    }
    await _voiceService.recordUsage(chunks.length);

    final joined = await _joinParts(parts);
    final controlsIgnored =
        !controls.isDefault && joined.ext == 'mp3';
    var outBytes = joined.bytes;
    var outExt = joined.ext;
    if (!controlsIgnored && !controls.isDefault) {
      outBytes = applyTtsControls(
        outBytes,
        text: clean,
        controls: controls,
      );
    }
    if (music) {
      outBytes = outExt == 'wav'
          ? mixWavWithMusic(outBytes)
          : await mixMp3WithMusic(outBytes);
    }
    if (format != outExt) {
      outBytes = await convertAudioBytes(
        outBytes,
        fromExt: outExt,
        toExt: format,
      );
      outExt = format;
    }
    try {
      await cachedFile.writeAsBytes(outBytes);
    } catch (_) {
      // A failed cache write must never block the result itself.
    }
    return TtsStudioResult(
      bytes: outBytes,
      ext: outExt,
      cached: false,
      usedDeviceFallback: false,
      proxyRequests: chunks.length,
      fellBackToEdge: fellBackToEdge,
      fellBackToGemini: fellBackToGemini,
      controlsIgnored: controlsIgnored,
      filePath: cachedFile.path,
    );
  }

  /// Joins per-chunk audio into one file: same-format joins are
  /// pure Dart (WAV concat / MP3 concat); mixed Gemini+Edge parts
  /// go through ffmpeg to WAV first.
  Future<GeneratedAudio> _joinParts(List<GeneratedAudio> parts) async {
    if (parts.isEmpty) throw Exception('Nothing to join.');
    if (parts.length == 1) return parts.first;
    final exts = parts.map((g) => g.ext).toSet();
    if (exts.length == 1) {
      final ext = parts.first.ext;
      final bytes = ext == 'wav'
          ? concatWav(parts.map((g) => g.bytes).toList())
          : concatMp3(parts.map((g) => g.bytes).toList());
      return GeneratedAudio(
        bytes: bytes,
        ext: ext,
        fellBackToEdge: parts.any((g) => g.fellBackToEdge),
        fellBackToGemini: parts.any((g) => g.fellBackToGemini),
      );
    }
    // Mixed formats: normalise every part to WAV via ffmpeg, then join.
    final wavs = <Uint8List>[];
    for (final part in parts) {
      wavs.add(
        part.ext == 'wav'
            ? part.bytes
            : await convertAudioBytes(part.bytes, fromExt: 'mp3', toExt: 'wav'),
      );
    }
    return GeneratedAudio(
      bytes: concatWav(wavs),
      ext: 'wav',
      fellBackToEdge: parts.any((g) => g.fellBackToEdge),
      fellBackToGemini: parts.any((g) => g.fellBackToGemini),
    );
  }

  // ---- Voice preview (T1, free of coins — 1 proxy request, cached) ----

  static const _previewText =
      'Assalam-o-Alaikum, main Nigraan TV se bol raha hoon.';

  /// Plays a short sample in [voice]'s real voice. One short proxy
  /// call per voice per install, cached locally under `tts_previews/`
  /// — it DOES count against the 5/day cap the first time (the
  /// screen says so). Throws [TtsStudioCapException] when the cap
  /// cannot cover even this one request.
  Future<Uint8List> previewVoice(
    StudioVoice voice, {
    http.Client? client,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _cacheDirName, _previewDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(p.join(dir.path, '${voice.id}.wav'));
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) return bytes;
    }
    final remaining = await _voiceService.remainingToday();
    if (remaining < 1) throw TtsStudioCapException(remaining, 1);
    final gen = await generateChunkWithFallback(
      _previewText,
      voice,
      lang: 'ur',
      client: client,
    );
    await _voiceService.recordUsage(1);
    var bytes = gen.bytes;
    if (gen.ext == 'mp3') {
      bytes = await convertAudioBytes(bytes, fromExt: 'mp3', toExt: 'wav');
    }
    try {
      await file.writeAsBytes(bytes);
    } catch (_) {}
    return bytes;
  }

  // ---- Device-voice fallback (cap hit / proxy down) ----

  /// On-device voice fallback (flutter_tts): robotic, but the text
  /// still gets spoken when the proxy or the cap cannot serve it.
  /// Synthesizes per chunk to files and concats them. Returns the
  /// WAV bytes. Throws when the device voice cannot produce audio.
  Future<TtsStudioResult> generateWithDeviceVoice(
    String text, {
    String? lang,
    TtsControls controls = const TtsControls(),
    bool music = false,
    String format = 'wav',
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) throw Exception('Text khaali hai — pehle likhein.');
    final resolvedLang = lang ?? GeminiVoiceService.detectLang(clean);
    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final workDir = Directory(p.join(tmp.path, 'tts_device_$stamp'));
    await workDir.create(recursive: true);
    try {
      final tts = FlutterTts();
      await tts.setLanguage(resolvedLang == 'ur' ? 'ur-PK' : 'en-US');
      await tts.setSpeechRate(0.9);
      await tts.setPitch(1.0);
      final chunks = chunkText(clean, StudioVoice.aoede);
      final wavs = <Uint8List>[];
      for (var i = 0; i < chunks.length; i++) {
        final chunkFile = File(p.join(workDir.path, 'tts_$i.wav'));
        final result = await tts.synthesizeToFile(chunks[i], chunkFile.path);
        if (result != 1 || !await chunkFile.exists()) {
          throw Exception('Device voice se audio nahi ban saka.');
        }
        wavs.add(await chunkFile.readAsBytes());
      }
      if (wavs.isEmpty) throw Exception('Device voice se audio nahi ban saka.');
      var outBytes = wavs.length == 1 ? wavs.first : concatWav(wavs);
      if (!controls.isDefault) {
        outBytes = applyTtsControls(outBytes, text: clean, controls: controls);
      }
      if (music) outBytes = mixWavWithMusic(outBytes);
      var outExt = 'wav';
      if (format == 'mp3') {
        outBytes = await convertAudioBytes(outBytes, fromExt: 'wav', toExt: 'mp3');
        outExt = 'mp3';
      }
      // Persist the device-voice result in the Studio cache dir so
      // history / download / share all have a file to point at.
      String? filePath;
      try {
        final dir = await _cacheDir();
        final file = File(
          p.join(dir.path, 'device_${DateTime.now().millisecondsSinceEpoch}.$outExt'),
        );
        await file.writeAsBytes(outBytes);
        filePath = file.path;
      } catch (_) {}
      return TtsStudioResult(
        bytes: outBytes,
        ext: outExt,
        cached: false,
        usedDeviceFallback: true,
        proxyRequests: 0,
        filePath: filePath,
      );
    } finally {
      await workDir.delete(recursive: true).catchError((_) => workDir);
    }
  }

  /// Clears the Studio cache (frees disk; next generate re-calls).
  Future<void> clearCache() async {
    try {
      final dir = await _cacheDir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}
