/// Audio tools — Converter + Trimmer (Phase 5, ported from Magic
/// Box's `audio_convert_service.dart` + `audio_edit_service.dart`,
/// v1.0.13 — adapted: Magic Box's ad gates (1 rewarded ad per
/// convert / unlock ad for batch + video-to-audio) are NOT ported —
/// TJ Pro has no per-feature ad-gate policy decided for the Studio.
/// Batch convert and re-generate mode are NOT ported (batch = the
/// same convert run per file, re-generate = the TTS Studio's job).
/// Everything else is here: formats, bitrate, sample rate, channels,
/// trim, speed, volume, loudnorm normalise, fades, metadata,
/// video-to-audio extraction, trim/join of WAV + MP3 files.
///
/// [buildConvertArgs] is a pure builder (unit-tested); the runners
/// below it are thin ffmpeg calls.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as p;

import 'mp3_utils.dart';
import 'wav_utils.dart';

/// Output format for a conversion.
enum ConvertFormat {
  mp3,
  wav,
  m4a,
  ogg;

  String get ext => name;

  /// ffmpeg audio codec for this format.
  String get codec => switch (this) {
        ConvertFormat.mp3 => 'libmp3lame',
        ConvertFormat.wav => 'pcm_s16le',
        ConvertFormat.m4a => 'aac',
        ConvertFormat.ogg => 'libvorbis',
      };

  /// True for lossy formats (bitrate applies).
  bool get isLossy => this != ConvertFormat.wav;
}

/// All options for one conversion. Defaults = "same quality, just
/// the new container".
class ConvertOptions {
  const ConvertOptions({
    this.format = ConvertFormat.mp3,
    this.bitrateKbps = 192,
    this.sampleRate = 44100,
    this.channels = 2,
    this.trimStartSec,
    this.trimEndSec,
    this.speed = 1.0,
    this.volume = 1.0,
    this.loudnorm = false,
    this.fadeInSec = 0.0,
    this.fadeOutSec = 0.0,
    this.title,
    this.artist,
  });

  final ConvertFormat format;
  final int bitrateKbps;
  final int sampleRate;
  final int channels;

  /// Trim window in seconds (null = keep the whole file).
  final double? trimStartSec;
  final double? trimEndSec;

  /// 0.5–2.0 (atempo; also changes pitch — the UI says so).
  final double speed;

  /// Gain multiplier, up to 2.0. Ignored when [loudnorm] is on
  /// (loudnorm wins over volume gain).
  final double volume;

  /// EBU R128 normalise (single-pass loudnorm).
  final bool loudnorm;
  final double fadeInSec;
  final double fadeOutSec;
  final String? title;
  final String? artist;
}

/// Result of one conversion / extraction run.
class AudioToolsResult {
  const AudioToolsResult({required this.outputPath, required this.bytes});
  final String outputPath;
  final int bytes;
}

class AudioToolsService {
  /// Audio filter chain for [options] (empty = no audio filter).
  /// Order: speed → volume/loudnorm → fades.
  static String audioFilterFor(ConvertOptions options) {
    final parts = <String>[];
    if ((options.speed - 1.0).abs() >= 0.001) {
      parts.add('atempo=${options.speed.toStringAsFixed(2)}');
    }
    if (options.loudnorm) {
      parts.add('loudnorm');
    } else if ((options.volume - 1.0).abs() >= 0.001) {
      parts.add('volume=${options.volume.toStringAsFixed(2)}');
    }
    if (options.fadeInSec > 0) {
      parts.add(
        'afade=t=in:st=0:d=${options.fadeInSec.toStringAsFixed(2)}',
      );
    }
    if (options.fadeOutSec > 0) {
      // Fade-out start needs the duration — the caller appends it
      // when known; without a duration the filter is skipped here
      // (see buildConvertArgs: it uses the trim length when given).
      parts.add('__FADEOUT__');
    }
    return parts.join(',');
  }

  /// Pure ffmpeg argument builder for one conversion. [outputPath]
  /// must already carry the right extension for [options.format].
  /// [inputDurationSec] (when known) lets the fade-out land at the
  /// end of the trimmed audio.
  static List<String> buildConvertArgs({
    required String inputPath,
    required ConvertOptions options,
    required String outputPath,
    double? inputDurationSec,
  }) {
    final args = <String>['-y'];
    if (options.trimStartSec != null && options.trimStartSec! > 0) {
      args.addAll(['-ss', options.trimStartSec!.toStringAsFixed(2)]);
    }
    if (options.trimEndSec != null && options.trimEndSec! > 0) {
      args.addAll(['-to', options.trimEndSec!.toStringAsFixed(2)]);
    }
    args.addAll(['-i', inputPath]);
    var filter = audioFilterFor(options);
    if (filter.contains('__FADEOUT__')) {
      // Fade-out starts (duration - fadeOut) in; without a known
      // duration there is nothing to anchor to, so drop it.
      final total = inputDurationSec ??
          ((options.trimEndSec ?? 0) - (options.trimStartSec ?? 0));
      if (total > options.fadeOutSec) {
        final start = (total - options.fadeOutSec).toStringAsFixed(2);
        filter = filter.replaceAll(
          '__FADEOUT__',
          'afade=t=out:st=$start:d=${options.fadeOutSec.toStringAsFixed(2)}',
        );
      } else {
        filter = filter
            .replaceAll(',__FADEOUT__', '')
            .replaceAll('__FADEOUT__,', '')
            .replaceAll('__FADEOUT__', '');
      }
    }
    if (filter.isNotEmpty) args.addAll(['-af', filter]);
    args.addAll(['-c:a', options.format.codec]);
    if (options.format.isLossy) {
      args.addAll(['-b:a', '${options.bitrateKbps}k']);
    }
    args.addAll(['-ar', '${options.sampleRate}', '-ac', '${options.channels}']);
    if (options.title != null && options.title!.trim().isNotEmpty) {
      args.addAll(['-metadata', 'title=${options.title!.trim()}']);
    }
    if (options.artist != null && options.artist!.trim().isNotEmpty) {
      args.addAll(['-metadata', 'artist=${options.artist!.trim()}']);
    }
    args.add(outputPath);
    return args;
  }

  /// Pure ffmpeg argument builder: extract the audio track of a
  /// video file into [outputPath] (extension picks the codec).
  static List<String> buildExtractAudioArgs({
    required String videoPath,
    required ConvertFormat format,
    required String outputPath,
  }) {
    return [
      '-y',
      '-i',
      videoPath,
      '-vn',
      '-c:a',
      format.codec,
      outputPath,
    ];
  }

  /// Output file name for a conversion: same base name, new ext.
  static String outputPathFor(String inputPath, ConvertFormat format) {
    final dir = p.dirname(inputPath);
    final base = p.basenameWithoutExtension(inputPath);
    return p.join(dir, '${base}_converted.${format.ext}');
  }

  /// Runs a conversion with ffmpeg. Throws on failure (callers show
  /// the message). Returns the output file + size.
  static Future<AudioToolsResult> convertFile({
    required File input,
    required ConvertOptions options,
    String? outputPath,
    double? inputDurationSec,
    void Function(double progress)? onProgress,
  }) async {
    final out = outputPath ?? outputPathFor(input.path, options.format);
    final args = buildConvertArgs(
      inputPath: input.path,
      options: options,
      outputPath: out,
      inputDurationSec: inputDurationSec,
    );
    final session = await FFmpegKit.executeWithArguments(args);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      final logs = await session.getOutput() ?? '';
      final tail = logs.length > 400
          ? logs.substring(logs.length - 400)
          : logs;
      throw Exception('Convert fail ho gaya: $tail');
    }
    final file = File(out);
    if (!await file.exists()) {
      throw Exception('Convert ne koi file nahi banayi.');
    }
    return AudioToolsResult(
      outputPath: out,
      bytes: await file.length(),
    );
  }

  /// Extracts a video's audio track. Throws on failure.
  static Future<AudioToolsResult> extractAudioFromVideo({
    required File video,
    ConvertFormat format = ConvertFormat.mp3,
    String? outputPath,
  }) async {
    final out = outputPath ?? outputPathFor(video.path, format);
    final args = buildExtractAudioArgs(
      videoPath: video.path,
      format: format,
      outputPath: out,
    );
    final session = await FFmpegKit.executeWithArguments(args);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      throw Exception('Audio nikalna fail ho gaya.');
    }
    final file = File(out);
    if (!await file.exists()) {
      throw Exception('Audio file nahi bani.');
    }
    return AudioToolsResult(outputPath: out, bytes: await file.length());
  }

  // ---- Pure-Dart trim / join (no ffmpeg) ----

  /// Duration of WAV or MP3 bytes in seconds, or null when neither
  /// parses.
  static double? audioDurationSeconds(Uint8List bytes) {
    try {
      final wav = parseWav(bytes);
      if (wav != null) return wav.durationSeconds;
    } catch (_) {}
    try {
      return mp3DurationSeconds(bytes);
    } catch (_) {}
    return null;
  }

  /// Trims WAV or MP3 bytes to [startSec]..[endSec] (sample / frame
  /// accurate). Throws when the bytes are neither WAV nor MP3, or
  /// the range selects nothing.
  static Uint8List trimAudio(Uint8List bytes, double startSec, double endSec) {
    try {
      if (parseWav(bytes) != null) return sliceWav(bytes, startSec, endSec);
    } catch (_) {}
    return trimMp3(bytes, startSec, endSec);
  }

  /// Joins audio files end to end. All inputs must share one format
  /// (all WAV with the same sample rate/channels/bits, or all MP3).
  /// Throws otherwise.
  static Uint8List joinAudio(List<Uint8List> files) {
    if (files.isEmpty) throw Exception('Nothing to join.');
    final firstIsWav = parseWav(files.first) != null;
    if (firstIsWav) return concatWav(files);
    return concatMp3(files);
  }
}
