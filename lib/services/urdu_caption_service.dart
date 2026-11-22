/// Urdu auto captions — Shruti Urdu via sherpa-onnx (v1.4.0).
///
/// Runs the Udgam Labs Shruti Urdu recognizer (Moonshine-type,
/// Apache-2.0) from the downloadable `shruti_ur` sherpa-onnx pack —
/// the exact pack verified in the tool-test battery
/// (tool-tests/01-captions/run_test.py, V140-TOOL-TESTS.md #1:
/// Urdu decode RTF 0.256, meaning fully preserved; verdict PARTIAL
/// because the model emits no punctuation and splits some compound
/// words — captions from here are a strong draft, not a transcript
/// guarantee).
///
/// Pipeline: extract a 16 kHz mono WAV from the source with
/// [FfmpegService], split it into 15-second windows, decode each
/// window with an [OfflineRecognizer] built from the pack's
/// Moonshine config (preprocess / encode / uncached_decode /
/// cached_decode + tokens.txt — the same four model files the
/// battery's `OfflineRecognizer.from_moonshine` call used), and
/// return one [UrduCaption] per non-empty window with its time span.
///
/// FAIL-SOFT: a missing pack, an ffmpeg failure, a recognizer error
/// or an unreadable file all return an EMPTY list — never a throw,
/// never a partial fake result.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'ffmpeg_service.dart';
import 'model_pack_service.dart';

/// One caption line with its window's time span in the source.
class UrduCaption {
  const UrduCaption({
    required this.start,
    required this.end,
    required this.text,
  });

  final Duration start;
  final Duration end;
  final String text;
}

class UrduCaptionService {
  UrduCaptionService._();

  /// Shared instance (the contract API).
  static final UrduCaptionService instance = UrduCaptionService._();

  /// Recognizer sample rate (the Moonshine pack is 16 kHz only).
  static const int sampleRate = 16000;

  /// Decode window length in seconds (contract: 15 s windows).
  static const int windowSeconds = 15;

  static bool _bindingsTried = false;

  /// Transcribes [audioPath] (audio or video — the audio track is
  /// extracted either way) into Urdu captions. Empty list on any
  /// failure.
  Future<List<UrduCaption>> transcribe(String audioPath) async {
    final List<UrduCaption> captions = <UrduCaption>[];
    Directory? tempDir;
    sherpa.OfflineRecognizer? recognizer;
    try {
      // 1. The pack must be fully on disk first.
      final ModelPackService packs = ModelPackService.instance;
      final File? preprocessor =
          await packs.packFile('shruti_ur', 'preprocess.onnx');
      final File? encoder = await packs.packFile('shruti_ur', 'encode.onnx');
      final File? uncached =
          await packs.packFile('shruti_ur', 'uncached_decode.onnx');
      final File? cached =
          await packs.packFile('shruti_ur', 'cached_decode.onnx');
      final File? tokens = await packs.packFile('shruti_ur', 'tokens.txt');
      if (preprocessor == null ||
          encoder == null ||
          uncached == null ||
          cached == null ||
          tokens == null) {
        return <UrduCaption>[];
      }

      // 2. Extract 16 kHz mono PCM WAV via the app's ffmpeg.
      tempDir = await Directory(
        p.join(
          (await getTemporaryDirectory()).path,
          'urdu_captions_${DateTime.now().millisecondsSinceEpoch}',
        ),
      ).create(recursive: true);
      final String wavPath = p.join(tempDir.path, 'audio_16k.wav');
      final FfmpegResult extract = await FfmpegService.run(
        '-y -i ${FfmpegService.q(audioPath)} -vn -ac 1 -ar $sampleRate '
        '-c:a pcm_s16le -f wav ${FfmpegService.q(wavPath)}',
      );
      if (!extract.ok) return <UrduCaption>[];
      final File wavFile = File(wavPath);
      if (!await wavFile.exists()) return <UrduCaption>[];

      // 3. Read the samples (16-bit PCM mono at 16 kHz).
      final Float32List? samples = _readPcm16Wav(await wavFile.readAsBytes());
      if (samples == null || samples.isEmpty) return <UrduCaption>[];

      // 4. Build the recognizer from the pack (Moonshine config —
      //    identical file roles to the battery's from_moonshine).
      if (!_bindingsTried) {
        _bindingsTried = true;
        try {
          sherpa.initBindings();
        } catch (_) {
          // Android/iOS load the native library via the plugin; a
          // failure here surfaces at recognizer creation instead and
          // is caught by the outer fail-soft handler.
        }
      }
      final sherpa.OfflineRecognizer rec = sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            moonshine: sherpa.OfflineMoonshineModelConfig(
              preprocessor: preprocessor.path,
              encoder: encoder.path,
              uncachedDecoder: uncached.path,
              cachedDecoder: cached.path,
            ),
            tokens: tokens.path,
            numThreads: 2,
          ),
        ),
      );
      recognizer = rec;

      // 5. Decode window by window; keep non-empty windows only.
      final int windowSamples = sampleRate * windowSeconds;
      for (int start = 0; start < samples.length; start += windowSamples) {
        final int end = (start + windowSamples > samples.length)
            ? samples.length
            : start + windowSamples;
        final Float32List chunk =
            Float32List.fromList(samples.sublist(start, end));
        final sherpa.OfflineStream stream = rec.createStream();
        try {
          stream.acceptWaveform(samples: chunk, sampleRate: sampleRate);
          rec.decode(stream);
          final String text = rec.getResult(stream).text.trim();
          if (text.isNotEmpty) {
            captions.add(
              UrduCaption(
                start: Duration(
                  milliseconds: (start * 1000 / sampleRate).round(),
                ),
                end: Duration(
                  milliseconds: (end * 1000 / sampleRate).round(),
                ),
                text: text,
              ),
            );
          }
        } finally {
          stream.free();
        }
      }
      return captions;
    } catch (_) {
      return <UrduCaption>[];
    } finally {
      recognizer?.free();
      if (tempDir != null) {
        try {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        } catch (_) {
          // Temp cleanup is best-effort.
        }
      }
    }
  }

  /// Minimal RIFF/WAVE reader for the ffmpeg-produced file above:
  /// walks the chunks, requires PCM (format 1) 16-bit samples, and
  /// returns them normalized to -1..1 floats. Null on anything else.
  static Float32List? _readPcm16Wav(Uint8List bytes) {
    try {
      if (bytes.length < 44) return null;
      final ByteData bd = ByteData.view(
        bytes.buffer,
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      String tag(int offset) => String.fromCharCodes(
            bytes.sublist(offset, offset + 4),
          );
      if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
      int? channels;
      int? rate;
      int? bits;
      int offset = 12;
      while (offset + 8 <= bytes.length) {
        final String id = tag(offset);
        final int size = bd.getUint32(offset + 4, Endian.little);
        final int body = offset + 8;
        if (id == 'fmt ') {
          final int format = bd.getUint16(body, Endian.little);
          if (format != 1) return null; // PCM only.
          channels = bd.getUint16(body + 2, Endian.little);
          rate = bd.getInt32(body + 4, Endian.little);
          bits = bd.getUint16(body + 14, Endian.little);
        } else if (id == 'data') {
          if (channels == null || rate == null || bits == null) {
            return null;
          }
          if (rate != sampleRate || bits != 16) return null;
          final int frames = size ~/ (2 * channels);
          final Float32List out = Float32List(frames);
          for (int i = 0; i < frames; i++) {
            // Mono was forced at extraction; if a file still carries
            // more channels, channel 0 is the caption source.
            final int s =
                bd.getInt16(body + i * 2 * channels, Endian.little);
            out[i] = s / 32768.0;
          }
          return out;
        }
        offset = body + size + (size.isOdd ? 1 : 0);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
