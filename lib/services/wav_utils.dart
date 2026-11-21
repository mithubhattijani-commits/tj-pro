/// Phase 5 port from Magic Box (`audio-box-ref`,
/// `lib/services/wav_utils.dart`, v1.0.13) — verbatim, pure Dart.
/// Used by the TTS voice controls (speed / pauses) and the Audio
/// Trimmer & Joiner. No Magic Box coin/ad code lives in this file.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// Pure-Dart WAV handling (no packages, no server) — shared by the
/// Audio Trimmer & Joiner and the TTS voice controls (speed / pauses).
///
/// Supports PCM WAV (format 1): 8-bit unsigned and 16-bit signed
/// samples, any sample rate, mono or stereo. Chunks may appear in any
/// order (fmt/data/fact/LIST…); odd-sized chunks are skipped with
/// their pad byte, like a real RIFF reader.
class WavData {
  final int sampleRate;
  final int channels;
  final int bitsPerSample;

  /// Raw PCM sample bytes (the data chunk, without its header).
  final Uint8List pcm;

  const WavData({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.pcm,
  });

  int get bytesPerSample => bitsPerSample ~/ 8;
  int get blockAlign => channels * bytesPerSample;

  /// Whole frames (one sample per channel).
  int get frameCount => blockAlign > 0 ? pcm.length ~/ blockAlign : 0;

  double get durationSeconds =>
      sampleRate > 0 ? frameCount / sampleRate : 0;

  /// Format key used when joining: files must match exactly, because
  /// no resampling is done on join.
  String get formatKey => '$sampleRate|$channels|$bitsPerSample';
}

/// Parse a WAV file's bytes. Returns null when the bytes are not a
/// supported PCM WAV (wrong magic, non-PCM format, truncated header).
WavData? parseWav(Uint8List bytes) {
  if (bytes.length < 44) return null;
  final d = ByteData.sublistView(bytes);
  if (d.getUint32(0, Endian.little) != 0x46464952) return null; // 'RIFF'
  if (d.getUint32(8, Endian.little) != 0x45564157) return null; // 'WAVE'

  int? format;
  int? channels;
  int? sampleRate;
  int? bitsPerSample;
  int? dataOffset;
  int? dataSize;

  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = d.getUint32(offset, Endian.little);
    final size = d.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (body + size > bytes.length) break;
    if (id == 0x20746d66) {
      // 'fmt '
      if (size < 16) return null;
      format = d.getUint16(body, Endian.little);
      channels = d.getUint16(body + 2, Endian.little);
      sampleRate = d.getUint32(body + 4, Endian.little);
      bitsPerSample = d.getUint16(body + 14, Endian.little);
    } else if (id == 0x61746164) {
      // 'data'
      dataOffset = body;
      dataSize = size;
    }
    // Chunks are word-aligned: odd sizes carry one pad byte.
    offset = body + size + (size % 2);
  }

  if (format != 1 ||
      channels == null ||
      channels <= 0 ||
      sampleRate == null ||
      sampleRate <= 0 ||
      bitsPerSample == null ||
      (bitsPerSample != 8 && bitsPerSample != 16) ||
      dataOffset == null ||
      dataSize == null) {
    return null;
  }
  final pcm = Uint8List.fromList(
    bytes.sublist(dataOffset, dataOffset + dataSize),
  );
  return WavData(
    sampleRate: sampleRate,
    channels: channels,
    bitsPerSample: bitsPerSample,
    pcm: pcm,
  );
}

/// Encode PCM bytes as a 44-byte-header WAV.
Uint8List encodeWav({
  required int sampleRate,
  required int channels,
  required int bitsPerSample,
  required Uint8List pcm,
}) {
  final bytesPerSample = bitsPerSample ~/ 8;
  final blockAlign = channels * bytesPerSample;
  final byteRate = sampleRate * blockAlign;
  final out = Uint8List(44 + pcm.length);
  final d = ByteData.sublistView(out);

  void writeString(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      out[offset + i] = s.codeUnitAt(i);
    }
  }

  writeString(0, 'RIFF');
  d.setUint32(4, 36 + pcm.length, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  d.setUint32(16, 16, Endian.little);
  d.setUint16(20, 1, Endian.little); // PCM
  d.setUint16(22, channels, Endian.little);
  d.setUint32(24, sampleRate, Endian.little);
  d.setUint32(28, byteRate, Endian.little);
  d.setUint16(32, blockAlign, Endian.little);
  d.setUint16(34, bitsPerSample, Endian.little);
  writeString(36, 'data');
  d.setUint32(40, pcm.length, Endian.little);
  out.setRange(44, 44 + pcm.length, pcm);
  return out;
}

/// Read one 16-bit sample (signed) at [frame] / [channel].
int readSample16(WavData wav, int frame, int channel) {
  final offset = frame * wav.blockAlign + channel * 2;
  return ByteData.sublistView(wav.pcm).getInt16(offset, Endian.little);
}

/// Read one 8-bit sample as signed (-128..127).
int readSample8(WavData wav, int frame, int channel) {
  final offset = frame * wav.blockAlign + channel;
  return wav.pcm[offset] - 128;
}

/// Write one 16-bit sample at [frame] / [channel] into [pcm].
void writeSample16(Uint8List pcm, int blockAlign, int frame, int channel,
    int value) {
  final offset = frame * blockAlign + channel * 2;
  ByteData.sublistView(pcm).setInt16(
    offset,
    value.clamp(-32768, 32767),
    Endian.little,
  );
}

/// Slice [startSec]..[endSec] out of a WAV file's bytes (sample
/// accurate). Throws when the input is not a supported WAV.
Uint8List sliceWav(Uint8List wavBytes, double startSec, double endSec) {
  final wav = parseWav(wavBytes);
  if (wav == null) throw Exception('Not a supported WAV file.');
  final startFrame = (startSec * wav.sampleRate)
      .round()
      .clamp(0, wav.frameCount);
  final endFrame =
      (endSec * wav.sampleRate).round().clamp(startFrame, wav.frameCount);
  final pcm = Uint8List.fromList(
    wav.pcm.sublist(
      startFrame * wav.blockAlign,
      endFrame * wav.blockAlign,
    ),
  );
  return encodeWav(
    sampleRate: wav.sampleRate,
    channels: wav.channels,
    bitsPerSample: wav.bitsPerSample,
    pcm: pcm,
  );
}

/// Concatenate WAV files end to end. All inputs must share the exact
/// format (sample rate / channels / bits) — no resampling is done.
/// Throws otherwise.
Uint8List concatWav(List<Uint8List> wavBytesList) {
  if (wavBytesList.isEmpty) throw Exception('Nothing to join.');
  final first = parseWav(wavBytesList.first);
  if (first == null) throw Exception('Not a supported WAV file.');
  final pcm = BytesBuilder();
  for (final bytes in wavBytesList) {
    final wav = parseWav(bytes);
    if (wav == null) throw Exception('Not a supported WAV file.');
    if (wav.formatKey != first.formatKey) {
      throw Exception(
        'WAV files must have the same sample rate, channels and bit '
        'depth to join (${wav.formatKey} vs ${first.formatKey}).',
      );
    }
    pcm.add(wav.pcm);
  }
  return encodeWav(
    sampleRate: first.sampleRate,
    channels: first.channels,
    bitsPerSample: first.bitsPerSample,
    pcm: pcm.takeBytes(),
  );
}

/// Change playback speed by resampling ([speed] > 1 = faster and
/// shorter, < 1 = slower and longer). Linear interpolation per
/// channel. Note: like any resample, speed also changes the pitch —
/// the UI says so plainly. Only 8/16-bit PCM.
Uint8List resampleWav(Uint8List wavBytes, double speed) {
  if (speed <= 0) throw Exception('Speed must be above 0.');
  if ((speed - 1.0).abs() < 0.001) return Uint8List.fromList(wavBytes);
  final wav = parseWav(wavBytes);
  if (wav == null) throw Exception('Not a supported WAV file.');
  final inFrames = wav.frameCount;
  final outFrames = (inFrames / speed).round().clamp(1, 1 << 28);
  final outPcm = Uint8List(outFrames * wav.blockAlign);
  for (var i = 0; i < outFrames; i++) {
    final pos = i * speed;
    final i0 = pos.floor().clamp(0, inFrames - 1);
    final i1 = math.min(i0 + 1, inFrames - 1);
    final frac = pos - i0;
    for (var ch = 0; ch < wav.channels; ch++) {
      int s0;
      int s1;
      if (wav.bitsPerSample == 16) {
        s0 = readSample16(wav, i0, ch);
        s1 = readSample16(wav, i1, ch);
      } else {
        s0 = readSample8(wav, i0, ch);
        s1 = readSample8(wav, i1, ch);
      }
      final v = (s0 + (s1 - s0) * frac).round();
      if (wav.bitsPerSample == 16) {
        writeSample16(outPcm, wav.blockAlign, i, ch, v);
      } else {
        outPcm[i * wav.blockAlign + ch] =
            (v + 128).clamp(0, 255);
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

/// Insert [silenceSeconds] of silence at each of [atSeconds] (times on
/// the ORIGINAL timeline, ascending). Used by the TTS pause control:
/// a short breath between sentences. Times past the end are ignored.
Uint8List insertSilenceWav(
  Uint8List wavBytes,
  List<double> atSeconds,
  double silenceSeconds,
) {
  if (silenceSeconds <= 0 || atSeconds.isEmpty) {
    return Uint8List.fromList(wavBytes);
  }
  final wav = parseWav(wavBytes);
  if (wav == null) throw Exception('Not a supported WAV file.');
  final silenceFrames = (silenceSeconds * wav.sampleRate).round();
  if (silenceFrames <= 0) return Uint8List.fromList(wavBytes);
  final sorted = List.of(atSeconds)..sort();
  final out = BytesBuilder();
  var cursorFrame = 0;
  for (final t in sorted) {
    final frame = (t * wav.sampleRate).round().clamp(0, wav.frameCount);
    if (frame <= cursorFrame) continue;
    out.add(wav.pcm.sublist(
      cursorFrame * wav.blockAlign,
      frame * wav.blockAlign,
    ));
    out.add(Uint8List(silenceFrames * wav.blockAlign));
    cursorFrame = frame;
  }
  out.add(wav.pcm.sublist(cursorFrame * wav.blockAlign));
  return encodeWav(
    sampleRate: wav.sampleRate,
    channels: wav.channels,
    bitsPerSample: wav.bitsPerSample,
    pcm: out.takeBytes(),
  );
}
