/// Phase 5 port from Magic Box (`audio-box-ref`,
/// `lib/services/tts_processing.dart`, v1.0.13) — verbatim except this
/// header. TTS voice controls applied on-device to generated WAV
/// bytes AFTER the proxy returns them (the proxy accepts only
/// {text, voice, lang} — no rate/pitch/style parameters).
///
/// - Speed (0.5x–2.0x): linear-interpolation resample. Like any
///   resample it also changes the pitch — the UI says so plainly.
///   True pitch-shift at constant tempo needs a phase vocoder, which
///   is NOT in this build.
/// - Pauses: silence inserted at sentence boundaries (even-split by
///   character count over the audio).
/// - Background music: soft ambient pad generated on-device (no
///   bundled file), mixed under the voice.
/// - Format conversion WAV<->MP3 via on-device ffmpeg.
///
/// Applies to Gemini voices only (WAV output). Edge voices return
/// MP3, which cannot be resampled without a decoder — the TTS Studio
/// screen disables the speed/pause controls for Edge voices and says
/// so. No coin/ad code is ported (TJ Pro = 5 requests/day cap).
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'mp3_utils.dart';
import 'wav_utils.dart';

/// TTS voice controls (v1.0.8, free) — applied on-device to the
/// generated WAV bytes, AFTER the proxy returns them.
///
/// The proxy itself accepts only {text, voice, lang} (see
/// tts-proxy/worker.js: no rate/pitch/style parameters, and the Edge
/// SSML hardcodes pitch '+0Hz' / rate '+0%'). So speed and pauses are
/// done here, on the PCM — no server change, no new API.
///
/// - Speed (0.5x–2.0x): linear-interpolation resample. Like any
///   resample it also changes the pitch — the UI says so plainly.
///   True pitch-shift at constant tempo needs a phase vocoder, which
///   is NOT in this build (see the report).
/// - Pauses: silence inserted at sentence boundaries. Boundary times
///   are even-split by character count over the audio (the same
///   even-split convention the caption tools already use honestly).
///
/// Applies to Gemini voices only (WAV output). Edge voices return MP3,
/// which cannot be resampled without a decoder — the TTS screen
/// disables the controls for Edge voices and says so.
class TtsControls {
  /// 1.0 = normal speed. 0.5 = half speed, 2.0 = double speed.
  final double speed;

  /// Silence inserted between sentences, in seconds (0 = off).
  final double pauseSeconds;

  const TtsControls({this.speed = 1.0, this.pauseSeconds = 0.0});

  bool get isDefault =>
      (speed - 1.0).abs() < 0.001 && pauseSeconds <= 0;

  /// Cache-key suffix so a 1.25x file never collides with the 1.0x
  /// file of the same text + voice.
  String get cacheSuffix {
    if (isDefault) return '';
    final s = speed.toStringAsFixed(2);
    final p = pauseSeconds.toStringAsFixed(1);
    return '|s$s|p$p';
  }
}

/// Sentence boundaries (character offsets) in [text], split on
/// sentence-ending punctuation (Latin + Urdu). The final sentence has
/// no trailing boundary.
List<int> sentenceBoundaries(String text) {
  final boundaries = <int>[];
  final pattern = RegExp(r'[.!?؟۔]\s+');
  for (final m in pattern.allMatches(text)) {
    boundaries.add(m.end);
  }
  return boundaries;
}

/// Apply [controls] to Gemini WAV [bytes] for [text]. Returns the
/// processed WAV bytes. No-op (same bytes back) when the controls are
/// default. Throws when the input is not a supported WAV.
Uint8List applyTtsControls(
  Uint8List bytes, {
  required String text,
  required TtsControls controls,
}) {
  if (controls.isDefault) return Uint8List.fromList(bytes);
  var out = bytes;
  if ((controls.speed - 1.0).abs() >= 0.001) {
    out = resampleWav(out, controls.speed);
  }
  if (controls.pauseSeconds > 0) {
    final wav = parseWav(out);
    if (wav == null) throw Exception('Not a supported WAV file.');
    final totalChars = text.length;
    if (totalChars > 0) {
      final duration = wav.durationSeconds;
      final at = <double>[];
      for (final boundary in sentenceBoundaries(text)) {
        at.add(boundary / totalChars * duration);
      }
      out = insertSilenceWav(out, at, controls.pauseSeconds);
    }
  }
  return out;
}

// ---------------------------------------------------------------------
// v1.0.10 — background music + format conversion.
// ---------------------------------------------------------------------

/// Duration of [bytes] in seconds (WAV or MP3). Returns 0 when the
/// bytes cannot be parsed.
double audioDurationSeconds(Uint8List bytes, String ext) {
  try {
    if (ext == 'wav') {
      return parseWav(bytes)?.durationSeconds ?? 0;
    }
    if (ext == 'mp3') return mp3DurationSeconds(bytes);
  } catch (_) {}
  return 0;
}

/// Human file size: "38 KB", "1.0 MB".
String formatAudioSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// "mm:ss" duration label.
String formatDuration(double seconds) {
  final total = seconds.round();
  final m = (total ~/ 60).toString().padLeft(2, '0');
  final s = (total % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// Generate a soft ambient pad as a 16-bit mono WAV — no bundled file,
/// no network download. A quiet major chord (A2 + E3 + A3 + C#4) with
/// a slow tremolo, fading in/out so it never clicks. Peak is ~5% of
/// full scale, so the voice always stays clearly on top.
///
/// The pad is generated at [sampleRate] to match the voice WAV it
/// will be mixed under (Gemini audio is 24 kHz mono 16-bit).
Uint8List generateAmbientPadWav({
  required double durationSeconds,
  int sampleRate = 24000,
}) {
  final frames = (durationSeconds * sampleRate).round().clamp(1, 1 << 28);
  final pcm = Uint8List(frames * 2);
  final d = ByteData.sublistView(pcm);
  // Soft chord, relative amplitudes (sum stays well under 1.0).
  const freqs = [110.0, 164.81, 220.0, 277.18];
  const amps = [0.30, 0.24, 0.18, 0.12];
  const peak = 0.05; // ~5% of full scale — clearly background.
  final fadeFrames = (0.5 * sampleRate).round().clamp(1, frames ~/ 2);
  for (var i = 0; i < frames; i++) {
    final t = i / sampleRate;
    // Slow tremolo (0.1 Hz) so the pad breathes instead of droning.
    final tremolo = 0.85 + 0.15 * math.sin(2 * math.pi * 0.1 * t);
    var v = 0.0;
    for (var k = 0; k < freqs.length; k++) {
      v += amps[k] * math.sin(2 * math.pi * freqs[k] * t);
    }
    var fade = 1.0;
    if (i < fadeFrames) fade = i / fadeFrames;
    if (i >= frames - fadeFrames) {
      fade = (frames - 1 - i) / fadeFrames;
    }
    final sample = (v * peak * tremolo * fade * 32767).round().clamp(
      -32768,
      32767,
    );
    d.setInt16(i * 2, sample, Endian.little);
  }
  return encodeWav(
    sampleRate: sampleRate,
    channels: 1,
    bitsPerSample: 16,
    pcm: pcm,
  );
}

/// Mix the generated ambient pad under a WAV voice track, on-device,
/// sample by sample (clamped so nothing clips). The pad is generated
/// at the voice track's own sample rate, so formats always match.
/// [musicLevel] scales the pad (1.0 = as generated, ~5% peak).
/// Throws when the input is not a supported WAV.
Uint8List mixWavWithMusic(Uint8List voiceBytes, {double musicLevel = 1.0}) {
  final wav = parseWav(voiceBytes);
  if (wav == null) throw Exception('Not a supported WAV file.');
  final padBytes = generateAmbientPadWav(
    durationSeconds: wav.durationSeconds,
    sampleRate: wav.sampleRate,
  );
  final pad = parseWav(padBytes)!;
  final frames = wav.frameCount;
  final outPcm = Uint8List.fromList(wav.pcm);
  final outData = ByteData.sublistView(outPcm);
  final padData = ByteData.sublistView(pad.pcm);
  final padFrames = pad.frameCount;
  for (var i = 0; i < frames; i++) {
    final p = i < padFrames ? i : padFrames - 1;
    // The pad is always 16-bit (see generateAmbientPadWav); scale it
    // to the voice track's bit depth before mixing.
    final padSample = padData.getInt16(p * 2, Endian.little);
    for (var ch = 0; ch < wav.channels; ch++) {
      if (wav.bitsPerSample == 16) {
        final voice = outData.getInt16(
          i * wav.blockAlign + ch * 2,
          Endian.little,
        );
        final mixed = (voice + padSample * musicLevel).round().clamp(
          -32768,
          32767,
        );
        outData.setInt16(i * wav.blockAlign + ch * 2, mixed, Endian.little);
      } else {
        final voice = outPcm[i * wav.blockAlign + ch] - 128;
        final music8 = (padSample / 256).round();
        final mixed = (voice + music8 * musicLevel).round().clamp(
          -128,
          127,
        );
        outPcm[i * wav.blockAlign + ch] = mixed + 128;
      }
    }
  }
  return encodeWav(
    sampleRate: wav.sampleRate,
    channels: wav.channels,
    bitsPerSample: wav.bitsPerSample,
    pcm: outPcm,
  );
}

/// Convert audio bytes between WAV and MP3 with the on-device ffmpeg
/// (ffmpeg_kit_flutter_new, already a dependency for the caption
/// tools). [fromExt]/[toExt] are 'wav' / 'mp3'. Throws when ffmpeg
/// fails — callers fall back to keeping the original format and say so.
Future<Uint8List> convertAudioBytes(
  Uint8List bytes, {
  required String fromExt,
  required String toExt,
}) async {
  if (fromExt == toExt) return Uint8List.fromList(bytes);
  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final inFile = File('${dir.path}/tts_conv_in_$stamp.$fromExt');
  final outFile = File('${dir.path}/tts_conv_out_$stamp.$toExt');
  try {
    await inFile.writeAsBytes(bytes);
    final session = await FFmpegKit.execute(
      '-i "${inFile.path}" -y "${outFile.path}"',
    );
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      throw Exception('Audio conversion failed (ffmpeg rc $rc).');
    }
    if (!await outFile.exists()) {
      throw Exception('Audio conversion produced no file.');
    }
    return await outFile.readAsBytes();
  } finally {
    try {
      if (await inFile.exists()) await inFile.delete();
    } catch (_) {}
    try {
      if (await outFile.exists()) await outFile.delete();
    } catch (_) {}
  }
}

/// Mix the generated ambient pad under an MP3 voice track (Edge
/// voices). MP3 cannot be mixed sample-by-sample without a decoder,
/// so ffmpeg mixes the voice MP3 with a generated pad WAV
/// (amix, voice length wins). Returns MP3 bytes. Throws when ffmpeg
/// fails — callers fall back to the voice without music and say so.
Future<Uint8List> mixMp3WithMusic(Uint8List mp3Bytes) async {
  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final voiceFile = File('${dir.path}/tts_mix_voice_$stamp.mp3');
  final padFile = File('${dir.path}/tts_mix_pad_$stamp.wav');
  final outFile = File('${dir.path}/tts_mix_out_$stamp.mp3');
  try {
    final duration = mp3DurationSeconds(mp3Bytes);
    await voiceFile.writeAsBytes(mp3Bytes);
    await padFile.writeAsBytes(
      generateAmbientPadWav(durationSeconds: duration + 0.5),
    );
    final session = await FFmpegKit.execute(
      '-i "${voiceFile.path}" -i "${padFile.path}" '
      '-filter_complex "[0:a][1:a]amix=inputs=2:duration=first:normalize=0" '
      '-y "${outFile.path}"',
    );
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      throw Exception('Music mix failed (ffmpeg rc $rc).');
    }
    if (!await outFile.exists()) {
      throw Exception('Music mix produced no file.');
    }
    return await outFile.readAsBytes();
  } finally {
    for (final f in [voiceFile, padFile, outFile]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }
}
