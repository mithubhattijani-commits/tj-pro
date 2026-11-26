/// Export settings + performance limits (Phase 9, master prompt §11 + §14).
///
/// [ExportSettings] is the ONE place the export screen's quality / fps /
/// bitrate / audio choices live. The values are REAL — they are passed
/// into the FFmpeg commands in [FfmpegService] (fps filter, `-b:v`,
/// `-b:a`), never just labels on a button. Defaults reproduce the
/// Phase 7 export exactly (30 fps, CRF 23, no explicit bitrate), so
/// existing behaviour and tests are untouched unless the user changes
/// a setting.
///
/// [estimatedSizeBytes] is a real formula, not a guess:
///   size = duration × (video bitrate + audio bitrate) / 8
/// (bits → bytes), plus ~1% container overhead. The bitrate used is
/// the EFFECTIVE one: the explicit bitrate when set, else the
/// per-quality default below (the same numbers the encoder targets).
/// The screen shows the estimate BEFORE the export starts, from the
/// project's known duration (voiceover length, else subtitle end).
///
/// [ExportLimits] is the memory/long-project policy, also real:
///   - max 20 clips per project — every clip is normalised to a full
///     intermediate MP4 in the temp dir, so unbounded clips blow
///     device storage; the clip picker and the handoff both enforce
///     it (extras are reported, never silently dropped).
///   - preview renders are capped at 720×1280 — the template PNG
///     renderer never renders a preview bigger than that, even for a
///     4K export (the export itself renders at full size).
///   - clip probing is LAZY and one-at-a-time: a clip's duration is
///     probed with ffprobe only when its export stage starts, never
///     up front for the whole project.
///   - the export pipeline is FILE-BASED and streaming: FFmpeg reads
///     clip files from disk and writes intermediates to disk. No step
///     loads a whole video file into Dart memory — the commands carry
///     file PATHS only (see the unit test asserting the command
///     strings contain the path and no in-memory bytes). The one
///     exception is the WAV header parse (`wavDurationSeconds`),
///     which reads only the first 8 KB.
///
/// What is NOT here (honest): 2K / H.265. H.265 needs a device codec
/// check (MediaCodec query) that cannot run on this VM and has no
/// test seam yet — the encoder stays libx264 (H.264). 2K is a
/// resolution the UI does not offer for the same reason: the three
/// offered qualities are the three the pipeline is tested for.
library;

/// Hard limits for long projects / memory (Phase 9, §14).
class ExportLimits {
  /// Maximum clips in one project. Reason: each clip becomes a full
  /// normalised intermediate MP4 in the temp dir; past ~20 the temp
  /// storage and the concat list stop being reasonable on a phone.
  static const int maxClipsPerProject = 20;

  /// Preview template renders never exceed this (portrait). The 4K
  /// export still renders its template PNG at full export size —
  /// only the on-screen PREVIEW is capped.
  static const int previewMaxWidth = 720;
  static const int previewMaxHeight = 1280;

  /// Clip durations are probed lazily, one clip at a time, only when
  /// that clip's export stage starts — never for the whole project
  /// up front.
  static const String clipProbePolicy = 'lazy-one-at-a-time';
}

/// One export configuration, chosen on the export screen.
class ExportSettings {
  const ExportSettings({
    this.quality = 0,
    this.fps = 30,
    this.videoBitrateKbps,
    this.audioBitrateKbps,
    this.aspect = '9:16',
  });

  /// 0 = 720p, 1 = 1080p, 2 = 4K (2160p). Same numbering as the
  /// Phase 7 quality selector.
  final int quality;

  /// Frame rate. Only 24 / 30 / 60 are offered — those are the rates
  /// the normalise filter is tested with.
  final int fps;

  /// Explicit video bitrate in kbps, or null = "Auto" (encoder CRF 23
  /// with the per-quality default as the size-estimate basis).
  final int? videoBitrateKbps;

  /// Explicit audio bitrate in kbps, or null = Auto (128 kbps AAC,
  /// the value the normalise pass already encodes at).
  final int? audioBitrateKbps;

  /// '9:16' (reel, default) | '16:9' | '1:1'.
  final String aspect;

  /// Default video bitrate (kbps) per quality — the standard
  /// YouTube-recommended ladder for H.264: 720p ~2.5 Mbps, 1080p
  /// ~5 Mbps, 4K ~12 Mbps (portrait reels use the same ladder; the
  /// pixel count is what matters, not the orientation).
  static int defaultVideoBitrateKbps(int quality) => switch (quality
      .clamp(0, 2)) {
        1 => 5000,
        2 => 12000,
        _ => 2500,
      };

  /// Default audio bitrate (kbps): 128 AAC stereo.
  static const int defaultAudioBitrateKbps = 128;

  /// Effective video bitrate for the estimate / encoder.
  int get effectiveVideoBitrateKbps =>
      videoBitrateKbps ?? defaultVideoBitrateKbps(quality);

  /// Effective audio bitrate for the estimate / encoder.
  int get effectiveAudioBitrateKbps =>
      audioBitrateKbps ?? defaultAudioBitrateKbps;

  /// Frame size for this quality + aspect (via the same table the
  /// FFmpeg service uses). Null aspect falls back to 9:16.
  (int, int) get dims {
    const table = <String, List<(int, int)>>{
      '9:16': [(720, 1280), (1080, 1920), (2160, 3840)],
      '16:9': [(1280, 720), (1920, 1080), (3840, 2160)],
      '1:1': [(720, 720), (1080, 1080), (2160, 2160)],
    };
    final rows = table[aspect] ?? table['9:16']!;
    return rows[quality.clamp(0, 2)];
  }

  String get qualityLabel => switch (quality.clamp(0, 2)) {
        1 => '1080p',
        2 => '4K',
        _ => '720p',
      };

  /// True when every field is in range. [error] names the first bad
  /// field (shown on the export screen instead of starting a bad
  /// export).
  bool get isValid => error == null;

  String? get error {
    if (quality < 0 || quality > 2) return 'Quality 720p, 1080p ya 4K ho.';
    if (fps != 24 && fps != 30 && fps != 60) {
      return 'FPS 24, 30 ya 60 ho.';
    }
    if (videoBitrateKbps != null &&
        (videoBitrateKbps! < 500 || videoBitrateKbps! > 50000)) {
      return 'Video bitrate must be between 500–50000 kbps.';
    }
    if (audioBitrateKbps != null &&
        (audioBitrateKbps! < 32 || audioBitrateKbps! > 320)) {
      return 'Audio bitrate must be between 32–320 kbps.';
    }
    if (aspect != '9:16' && aspect != '16:9' && aspect != '1:1') {
      return 'Aspect 9:16, 16:9 ya 1:1 ho.';
    }
    return null;
  }

  /// Estimated output size in bytes for a [durationSec]-long video:
  ///   duration × (video + audio bitrate) / 8, +1% container overhead.
  /// Returns null when the duration is unknown (<= 0) — the screen
  /// then says so instead of showing a made-up number.
  int? estimatedSizeBytes(double? durationSec) {
    if (durationSec == null || durationSec <= 0) return null;
    final bitsPerSec =
        (effectiveVideoBitrateKbps + effectiveAudioBitrateKbps) * 1000;
    final bytes = durationSec * bitsPerSec / 8;
    return (bytes * 1.01).round();
  }

  /// Human size label ("19.7 MB", "850 KB"). Null when unknown.
  String? estimatedSizeLabel(double? durationSec) {
    final bytes = estimatedSizeBytes(durationSec);
    if (bytes == null) return null;
    return formatBytes(bytes);
  }

  /// "19.7 MB" / "850 KB" / "320 B" — pure, unit-tested.
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  ExportSettings copyWith({
    int? quality,
    int? fps,
    int? videoBitrateKbps,
    int? audioBitrateKbps,
    String? aspect,
  }) {
    return ExportSettings(
      quality: quality ?? this.quality,
      fps: fps ?? this.fps,
      videoBitrateKbps: videoBitrateKbps ?? this.videoBitrateKbps,
      audioBitrateKbps: audioBitrateKbps ?? this.audioBitrateKbps,
      aspect: aspect ?? this.aspect,
    );
  }
}
