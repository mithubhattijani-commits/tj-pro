/// Phase 5 port from Magic Box (`audio-box-ref`,
/// `lib/services/mp3_utils.dart`, v1.0.13) — verbatim, pure Dart.
/// Frame-header parsing only (no decoding): MP3 durations, trim and
/// join for the Audio Trimmer & the TTS Studio (Edge MP3 files).
library;

import 'dart:typed_data';

/// Pure-Dart MP3 frame handling (no packages, no server) for the
/// Audio Trimmer & Joiner.
///
/// Only the frame headers are parsed — no audio is decoded — so trim
/// and join are frame-accurate (±26 ms at 44.1 kHz) and lossless.
/// Supports MPEG-1 / 2 / 2.5, Layer I / II / III. Free-format frames
/// (bitrate index 0) and files with no valid frame are rejected with
/// a clear error. ID3v2 tags at the start are skipped (and preserved
/// on trim); ID3v1/APE junk at the end is ignored.
class Mp3Frame {
  /// Byte offset of the frame header in the file.
  final int offset;

  /// Full frame length in bytes (header + payload).
  final int length;

  /// Frame duration in seconds (samples per frame / sample rate).
  final double durationSeconds;

  /// Start time of this frame in the stream.
  final double startSeconds;

  const Mp3Frame({
    required this.offset,
    required this.length,
    required this.durationSeconds,
    required this.startSeconds,
  });
}

class Mp3Info {
  final List<Mp3Frame> frames;

  /// Byte offset where the first audio frame starts (after ID3v2).
  final int audioStart;

  /// Length of the ID3v2 header, 0 when there is none.
  final int id3v2Length;

  const Mp3Info({
    required this.frames,
    required this.audioStart,
    required this.id3v2Length,
  });

  double get durationSeconds =>
      frames.isEmpty ? 0 : frames.last.startSeconds + frames.last.durationSeconds;

  int get frameCount => frames.length;
}

const List<List<int>> _bitratesMpeg1 = [
  // Layer I, II, III (kbps) by bitrate index 1..14.
  [32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
  [32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
  [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
];

const List<List<int>> _bitratesMpeg2 = [
  [32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
  [8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
  [8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
];

const List<List<int>> _sampleRates = [
  [44100, 48000, 32000], // MPEG-1
  [22050, 24000, 16000], // MPEG-2
  [11025, 12000, 8000], // MPEG-2.5
];

/// Parse one frame header at [offset]. Returns the frame, or null
/// when the bytes there are not a valid frame header.
Mp3Frame? _parseFrameHeader(Uint8List bytes, int offset, double startSeconds) {
  if (offset + 4 > bytes.length) return null;
  if (bytes[offset] != 0xFF || (bytes[offset + 1] & 0xE0) != 0xE0) {
    return null;
  }
  final b1 = bytes[offset + 1];
  final b2 = bytes[offset + 2];
  final versionBits = (b1 >> 3) & 0x03;
  final layerBits = (b1 >> 1) & 0x03;
  final bitrateIndex = (b2 >> 4) & 0x0F;
  final sampleRateIndex = (b2 >> 2) & 0x03;
  final padding = (b2 >> 1) & 0x01;
  // 01 = reserved version, 00 = reserved layer, 0/15 = bad/free bitrate,
  // 3 = reserved sample rate.
  if (versionBits == 1 || layerBits == 0) return null;
  if (bitrateIndex == 0 || bitrateIndex == 15) return null;
  if (sampleRateIndex == 3) return null;

  final versionRow = versionBits == 3
      ? 0
      : versionBits == 2
          ? 1
          : 2;
  final layerRow = layerBits == 3
      ? 0
      : layerBits == 2
          ? 1
          : 2;
  final bitrates =
      versionBits == 3 ? _bitratesMpeg1 : _bitratesMpeg2;
  final bitrateKbps = bitrates[layerRow][bitrateIndex - 1];
  final sampleRate = _sampleRates[versionRow][sampleRateIndex];
  // Samples per frame and frame-length coefficient, by layer
  // (layerBits: 3 = Layer I, 2 = Layer II, 1 = Layer III):
  // Layer I = 384 samples, coeff 12; Layer II = 1152, coeff 144;
  // Layer III = 1152 / coeff 144 on MPEG-1, 576 / coeff 72 on
  // MPEG-2/2.5. (Layer I and III must not be swapped — that makes
  // every MP3 duration 3x too short.)
  final isMpeg1 = versionBits == 3;
  final samplesPerFrame = layerBits == 3
      ? 384
      : layerBits == 2
          ? 1152
          : (isMpeg1 ? 1152 : 576);
  final slotsPerFrame = layerBits == 3
      ? 12
      : layerBits == 2
          ? 144
          : (isMpeg1 ? 144 : 72);
  final length =
      (slotsPerFrame * bitrateKbps * 1000 ~/ sampleRate) + padding;
  if (length <= 0 || offset + length > bytes.length) return null;
  return Mp3Frame(
    offset: offset,
    length: length,
    durationSeconds: samplesPerFrame / sampleRate,
    startSeconds: startSeconds,
  );
}

/// Length of the ID3v2 tag at the start (0 when there is none).
int _id3v2Length(Uint8List bytes) {
  if (bytes.length < 10) return 0;
  if (bytes[0] != 0x49 || bytes[1] != 0x44 || bytes[2] != 0x33) {
    return 0; // 'ID3'
  }
  final size = ((bytes[6] & 0x7F) << 21) |
      ((bytes[7] & 0x7F) << 14) |
      ((bytes[8] & 0x7F) << 7) |
      (bytes[9] & 0x7F);
  final total = 10 + size;
  return total <= bytes.length ? total : 0;
}

/// Parse all frames. Throws when no valid frame is found (not an MP3,
/// or free-format which cannot be measured).
Mp3Info parseMp3(Uint8List bytes) {
  final id3 = _id3v2Length(bytes);
  final frames = <Mp3Frame>[];
  var offset = id3;
  var time = 0.0;
  while (offset + 4 <= bytes.length) {
    final frame = _parseFrameHeader(bytes, offset, time);
    if (frame == null) {
      // Skip one byte of junk and look for the next sync.
      offset++;
      continue;
    }
    frames.add(frame);
    time += frame.durationSeconds;
    offset += frame.length;
  }
  if (frames.isEmpty) {
    throw Exception('No MP3 audio frames found in this file.');
  }
  return Mp3Info(frames: frames, audioStart: id3, id3v2Length: id3);
}

/// Duration of an MP3 file's bytes (frame scan). Throws on invalid data.
double mp3DurationSeconds(Uint8List bytes) => parseMp3(bytes).durationSeconds;

/// Frame-accurate trim: keeps whole frames that lie inside
/// [startSec]..[endSec]. The ID3v2 header (when present) is kept.
/// Throws when the range selects no frames.
Uint8List trimMp3(Uint8List bytes, double startSec, double endSec) {
  final info = parseMp3(bytes);
  final out = BytesBuilder();
  if (info.id3v2Length > 0) {
    out.add(bytes.sublist(0, info.id3v2Length));
  }
  var kept = 0;
  for (final frame in info.frames) {
    final frameEnd = frame.startSeconds + frame.durationSeconds;
    if (frame.startSeconds >= startSec && frameEnd <= endSec + 0.001) {
      out.add(bytes.sublist(frame.offset, frame.offset + frame.length));
      kept++;
    }
  }
  if (kept == 0) {
    throw Exception('Nothing to keep in that range — pick a wider range.');
  }
  return out.takeBytes();
}

/// Join MP3 files end to end. MP3 frames are self-contained, so plain
/// concatenation plays correctly. The first file's ID3v2 tag is kept;
/// later files' ID3v2 tags are dropped.
Uint8List concatMp3(List<Uint8List> files) {
  if (files.isEmpty) throw Exception('Nothing to join.');
  final out = BytesBuilder();
  for (var i = 0; i < files.length; i++) {
    final info = parseMp3(files[i]);
    if (i == 0) {
      out.add(files[i]);
    } else {
      out.add(files[i].sublist(info.audioStart));
    }
  }
  return out.takeBytes();
}
