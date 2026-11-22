/// Real FFmpeg reel export for News Studio (Phase 7).
///
/// ONE 720×1280 (or 1080p / 4K) 30 fps reel, composed from the news
/// project in this order:
///
///   clips (normalised + cut-joined)
///     → voiceover mix (clip audio ducked under the Gemini voiceover)
///     → chroma-key pass (preset sensitivity + background)
///     → template overlay (for 'nigraanFinal': the v1.3.0 ANIMATED
///       parity pass — both ribbons scroll, rotating logo + flipping
///       clock capsule, see lib/live/parity_template.dart; other
///       kinds: the 3-ribbon / breaking / classic PNG from
///       `renderLiveTemplateImage`, logo left OUT of the PNG)
///     → rotating-logo overlay (ping-ponged mov, or generated
///       frames) — SKIPPED for 'nigraanFinal' (the parity pass
///       already carries the logo + capsule)
///     → watermark overlay (Phase 8: preset toggle/position/size —
///       skipped entirely when the preset's watermark is off)
///     → intro/outro assembly (10 s intro prepended, 3 s outro card —
///       the branding end card with the channel's real social handles
///       when the preset has any, else the template frame)
///     → karaoke caption burn-in (styled ASS first, drawtext fallback)
///     → gallery save.
///
/// Every step that can be skipped is skipped with a NOTE, never a
/// crash and never a fake claim: a missing intro file means "intro
/// ke baghair export", a missing voiceover means "voiceover ke
/// baghair", a failed caption burn-in means "captions ke baghair" —
/// the notes travel back in [ReelExportResult.notes] and the UI shows
/// them. A step that MUST work (clip normalise/join, template
/// overlay) fails the export with a clear error instead.
///
/// On-device verification limits (honest): actual FFmpeg runs,
/// ExoPlayer playback and the ProRes decoder path need a real device
/// — the VM has none. What IS verified here without a device: every
/// filter graph / command string (unit tests), the PNG renders, and
/// the logo-frame generation.
///
/// What this export deliberately does NOT do (documented, not fake):
/// - Scrolling tickers: SINCE v1.3.0 the 'nigraanFinal' template
///   DOES scroll — both bottom ribbons animate in the export via
///   the parity pass (lib/live/parity_template.dart), matching the
///   real Nigraan videos. The BREAKING / CLASSIC kinds still use
///   one static PNG per export (their ribbons are headline strips,
///   pinned at their start — the export screen says so plainly).
///   Within the parity pass, the OPTIONAL top ribbon (off in the
///   parity preset) is drawn as a still layer — it does not scroll.
/// - No crossfade between clips: the project carries no transition
///   choice, so clips join with a hard cut (the editor's own export
///   has the transition picker for that).
/// - No split screen (EXPLICITLY DEFERRED, Phase 7): split screen
///   needs a SECOND concurrent video track (two clips side by side
///   on the same timeline), but the editor timeline is a single
///   sequential clip list (normalise → concat) with no multi-input
///   track model — there is no second input to composite. PIP works
///   because its inset is one extra picked video overlaid on the
///   finished timeline, not a second timeline track. Split screen
///   stays deferred until the timeline gains a second video track.
/// - No 2K / H.265 (Phase 9 decision): H.265 needs a device codec
///   check (MediaCodec query) that cannot run on this VM and has no
///   test seam yet — the encoder stays libx264 (H.264). The three
///   offered qualities are the three the pipeline is tested for.
///
/// Phase 9 additions (see `lib/services/export_settings.dart`):
/// export settings (quality / fps / bitrate / audio / aspect) are
/// REAL values threaded into every encoding pass; progress is
/// per-stage from the live ffmpeg statistics callback; the result
/// names the failed step; the clip cap (20) is enforced; the
/// pipeline stays file-based/streaming (paths only, no video bytes
/// in Dart memory).
library;

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_config.dart';
import '../live/news_template.dart';
import '../live/parity_template.dart';
import 'asset_download_service.dart';
import 'caption_service.dart';
import 'caption_styles.dart';
import 'export_settings.dart';
import 'ffmpeg_service.dart';
import 'logo_loop_service.dart';
import 'pro_editor.dart';
import 'video_export_service.dart';
import '../news/breaking_templates.dart';
import '../news/channel_preset.dart';
import '../news/element_override.dart';
import '../news/news_project.dart';
import '../news/widgets/template_media_preview.dart' show isPhotoMediaPath;
import '../news/project_handoff.dart';
import '../news/watermark.dart';

/// Result of one reel export.
class ReelExportResult {
  const ReelExportResult({
    required this.success,
    this.outputPath,
    this.error,
    this.notes = const [],
    this.failedStep,
  });

  final bool success;

  /// Gallery-saved MP4 path, when [success] is true.
  final String? outputPath;

  /// Human-readable failure reason, when [success] is false.
  final String? error;

  /// Honest notes about skipped steps ("intro ke baghair export…").
  /// Shown on screen; never hidden.
  final List<String> notes;

  /// Which pipeline step failed, when [success] is false
  /// (Phase 9: 'Clips tayyar karna', 'Clips join karna', 'Gallery
  /// save karna'…). The export screen shows it and offers a retry.
  final String? failedStep;
}

/// Intro asset state, for the export card (never a fake "intro added").
enum IntroAvailability {
  /// Cached on the device — the export will prepend it.
  ready,

  /// Not cached yet, but a download URL IS configured — the card
  /// offers a real download.
  notDownloaded,

  /// No download URL configured at all (not hosted yet) — the export
  /// runs without an intro and says so.
  notHosted,
}

class ReelExportService {
  /// Quality selector used by the export card: 0 = 720p, 1 = 1080p,
  /// 2 = 4K (2160p). Pure — unit-tested.
  static VideoExportQuality qualityFor(int quality) =>
      switch (quality.clamp(0, 2)) {
        1 => VideoExportQuality.p1080,
        2 => VideoExportQuality.p2160,
        _ => VideoExportQuality.p720,
      };

  /// Reel frame size for [quality] (always 9:16 portrait).
  static (int, int) reelDims(int quality) {
    final dims = FfmpegService.exportDims('9:16', quality.clamp(0, 2));
    return dims ?? (720, 1280);
  }

  /// Runs one FFmpeg command, mapping its live statistics progress
  /// (0..1 within the command) into the stage's [from]..[to] range.
  /// [expectedMs] is the duration this command processes; null means
  /// "no live sub-progress — report the stage end when the command
  /// finishes". The statistics callback inside [FfmpegService.run]
  /// is the real ffmpeg progress stream (time processed / expected
  /// duration) — Phase 9 wires it per stage instead of only
  /// reporting stage fractions.
  static Future<FfmpegResult> _runStage(
    String command,
    double from,
    double to, {
    int? expectedMs,
    void Function(double progress)? onProgress,
  }) async {
    final res = await FfmpegService.run(
      command,
      expectedMs: expectedMs,
      onProgress: expectedMs == null
          ? null
          : (p) => onProgress?.call(from + p * (to - from)),
    );
    onProgress?.call(to);
    return res;
  }

  /// Reel duration estimate in ms for progress mapping + the size
  /// estimate: the voiceover length when known (the reel is cut to
  /// the voiceover), else the last subtitle end, else null (stage
  /// fractions only — never a fabricated duration).
  static int? _estimatedReelMs(NewsProject project) {
    final vo = project.voiceoverDurationSec;
    if (vo != null && vo > 0) return (vo * 1000).round();
    double last = 0;
    for (final s in project.subtitles) {
      if (s.endSec > last) last = s.endSec;
    }
    if (last > 0) return (last * 1000).round();
    return null;
  }

  /// Public seam for the export screen's size estimate: the reel
  /// duration in seconds (voiceover, else subtitles), or null when
  /// unknown.
  static double? estimatedDurationSec(NewsProject project) {
    final ms = _estimatedReelMs(project);
    return ms == null ? null : ms / 1000;
  }

  /// True when [video] has an audio stream (ffprobe). False on any
  /// probe failure — callers then treat the video as silent (the
  /// voiceover becomes the only audio track).
  static Future<bool> probeHasAudio(File video) async {
    try {
      final session = await FFprobeKit.getMediaInformation(video.path);
      final streams = session.getMediaInformation()?.getStreams();
      if (streams == null) return false;
      for (final s in streams) {
        if (s.getType() == 'audio') return true;
      }
    } catch (_) {}
    return false;
  }

  /// Intro state for the export card (cache check only, no download).
  static Future<IntroAvailability> introState({
    AssetDownloadService? assetService,
  }) async {
    final svc = assetService ?? const AssetDownloadService();
    try {
      final cached =
          await svc.cachedFile(AssetDownloadService.introFileName);
      if (cached != null) return IntroAvailability.ready;
    } catch (_) {}
    if (AppConfig.nigraanIntroUrl.trim().isEmpty) {
      return IntroAvailability.notHosted;
    }
    return IntroAvailability.notDownloaded;
  }

  /// The styled ASS for the project's subtitles, using the project's
  /// own caption style + controls (the same builder the Caption
  /// Studio uses — `CaptionService.buildStyledAss`). Null when the
  /// project has no subtitle lines.
  static String? styledAssForProject({
    required NewsProject project,
    required int playResX,
    required int playResY,
  }) {
    if (project.subtitles.isEmpty) return null;
    final segments = captionSegmentsFromSubtitles(project.subtitles);
    return CaptionService.buildStyledAss(
      segments,
      StudioCaptionStyles.byId(project.captionStyleId),
      position: project.captionPosition,
      size: project.captionSize,
      highlightColor: project.captionHighlight,
      fontFamily:
          CaptionFonts.byId(project.captionFontId).family ?? 'Arial',
      playResX: playResX,
      playResY: playResY,
      outline: project.captionOutline,
      shadow: project.captionShadow,
      background: project.captionBackground,
      dualLanguage: project.captionDualLanguage,
    );
  }

  /// Exports [project] with [preset] as one reel. See the file header
  /// for the pipeline. [onProgress] fires 0..1; [onStep] reports the
  /// current stage in the UI status line. [workDirOverride] is a test
  /// seam (a temp dir); production passes none.
  ///
  /// Phase 9 — [settings] carries the export screen's REAL choices
  /// (quality / fps / bitrate / audio / aspect). When null, [quality]
  /// builds the Phase 7 defaults (30 fps, CRF 23, 9:16). Progress is
  /// PER-STAGE and live: each FFmpeg run reports its real statistics
  /// progress (time processed / expected duration) mapped into that
  /// stage's range — the statistics callback is the hook that
  /// already existed in [FfmpegService.run]; what Phase 9 adds is
  /// wiring it per stage with a real expected duration (the clip's
  /// probed duration for normalise, the reel's estimated duration
  /// otherwise). When a duration cannot be probed (ffprobe fails),
  /// that stage reports only its start/end fractions — never a
  /// fabricated smooth bar.
  static Future<ReelExportResult> exportReel({
    required NewsProject project,
    required ChannelPreset preset,
    int quality = 0,
    ExportSettings? settings,
    void Function(double progress)? onProgress,
    void Function(String step)? onStep,
    Directory? workDirOverride,
    AssetDownloadService? assetService,
    // Phase 9 — cancellation: the export screen sets this when the
    // user taps Cancel. Checked between stages (and before each
    // clip); the in-flight ffmpeg pass is cancelled separately via
    // `FfmpegService.cancel()`.
    bool Function()? isCancelled,
  }) async {
    final notes = <String>[];
    final effectiveSettings =
        settings ?? ExportSettings(quality: quality);
    void step(String s, double p) {
      onStep?.call(s);
      onProgress?.call(p);
    }

    /// Non-null when the user cancelled (checked between stages).
    ReelExportResult? cancelledResult() {
      if (isCancelled?.call() != true) return null;
      return ReelExportResult(
        success: false,
        error: 'Export cancel kar diya gaya.',
        failedStep: 'Export (cancel)',
        notes: notes,
      );
    }

    // Runs one FFmpeg command, mapping its live statistics progress
    // (0..1 within the command) into the stage's [from]..[to]
    // range. See [_runStage].
    Future<FfmpegResult> runStage(
      String command,
      double from,
      double to, {
      int? expectedMs,
    }) =>
        _runStage(
          command,
          from,
          to,
          expectedMs: expectedMs,
          onProgress: onProgress,
        );

    // Validate BEFORE touching path_provider, so a bad project fails
    // cleanly even in a plain unit test.
    final handoff = buildHandoff(project: project, preset: preset);
    if (handoff.clipPaths.isEmpty) {
      return ReelExportResult(
        success: false,
        error: 'Koi clip nahi — pehle clips add karein.',
        failedStep: 'Clips tayyar karna',
        notes: handoff.droppedClipPaths.isEmpty
            ? const []
            : [
                '${handoff.droppedClipPaths.length} clip file(s) nahi mili.',
              ],
      );
    }
    if (handoff.droppedClipPaths.isNotEmpty) {
      notes.add(
        '${handoff.droppedClipPaths.length} clip file(s) nahi mili — '
        'un ke baghair export ho raha hai.',
      );
    }
    if (handoff.cappedClipCount > 0) {
      notes.add(
        '${handoff.cappedClipCount} clip(s) 20-clip limit se zyada '
        'thi — pehle 20 export ho rahe hain.',
      );
    }
    final cancelledBeforeStart = cancelledResult();
    if (cancelledBeforeStart != null) return cancelledBeforeStart;

    try {
      final (w, h) = effectiveSettings.dims;
      final q = qualityFor(effectiveSettings.quality);
      final dir = workDirOverride ?? await _workDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      var out = p.join(dir.path, 'reel_export_$stamp.mp4');

      // Reel duration estimate for progress mapping: the voiceover
      // length when known (the reel is cut to the voiceover), else
      // the last subtitle end, else null (stage fractions only).
      final reelMs = _estimatedReelMs(project);

      // Kasheeda for the template renderer. v1.3.0 (§9 criterion
      // 7): the font ships BUNDLED with the app (cache → bundle →
      // download URL, in that order). For the Final template a
      // missing font FAILS the export loudly — the real template's
      // Urdu IS Kasheeda, and a silent system-font fallback would
      // ship a lookalike. Other kinds keep the best-effort path.
      final fontReady =
          await (assetService ?? const AssetDownloadService())
              .ensureKasheedaFontReady(url: AppConfig.kasheedaFontUrl);
      if (!fontReady && project.templateKind == 'nigraanFinal') {
        return ReelExportResult(
          success: false,
          error: 'Kasheeda font nahi mila — Final template ki Urdu '
              'usi font mein render hoti hai, is liye export roka '
              'gaya. (Font app ke saath bundled hai; assets check '
              'karein.)',
          failedStep: 'Template font',
          notes: notes,
        );
      }

      // --- 1. Normalise + join clips (export fps + dims). ---
      step('Clips tayyar ho rahe hain…', 0.05);
      final normFiles = <String>[];
      final totalClips = handoff.clipPaths.length;
      for (var i = 0; i < totalClips; i++) {
        final cancelledClip = cancelledResult();
        if (cancelledClip != null) return cancelledClip;
        final nf = p.join(dir.path, 'reel_norm_${stamp}_$i.mp4');
        // Lazy probe: this clip's duration only, right before its
        // own stage — never for the whole project up front.
        final clipSize =
            await VideoExportService.probeVideoSize(
          File(handoff.clipPaths[i]),
        );
        final clipDuration = clipSize?.durationSeconds;
        final clipMs =
            clipDuration == null ? null : (clipDuration * 1000).round();
        final stageFrom = 0.05 + 0.20 * i / totalClips;
        final stageTo = 0.05 + 0.20 * (i + 1) / totalClips;
        // v1.5.0 (#32): a PHOTO in the clip list becomes a real 5s
        // Ken Burns segment via photoClipCommand — normalizeCommand
        // on a still image would produce a one-frame file and break
        // the concat. Videos keep the normalize path unchanged.
        final isPhoto = isPhotoMediaPath(handoff.clipPaths[i]);
        final res = await runStage(
          isPhoto
              ? FfmpegService.photoClipCommand(
                  imagePath: handoff.clipPaths[i],
                  output: nf,
                  width: w,
                  height: h,
                  durationSec: 5,
                  kenBurns: true,
                )
              : FfmpegService.normalizeCommand(
                  input: handoff.clipPaths[i],
                  trimStart: 0,
                  // No trim range on a project clip: the full clip is
                  // used. `-to 3600` is a generous cap — FFmpeg stops
                  // at EOF.
                  trimEnd: 3600,
                  width: w,
                  height: h,
                  output: nf,
                  fps: effectiveSettings.fps,
                  videoBitrateKbps: effectiveSettings.videoBitrateKbps,
                  audioBitrateKbps: effectiveSettings.audioBitrateKbps,
                ),
          stageFrom,
          stageTo,
          expectedMs: isPhoto ? 5000 : clipMs,
        );
        if (!res.ok) {
          return ReelExportResult(
            success: false,
            error: 'Clip ${i + 1} tayyar nahi hua. ${res.logs}',
            failedStep: 'Clips tayyar karna',
            notes: notes,
          );
        }
        normFiles.add(nf);
      }
      if (normFiles.length == 1) {
        out = normFiles.first;
      } else {
        final listFile = p.join(dir.path, 'reel_concat_$stamp.txt');
        await File(listFile).writeAsString(
          normFiles
              .map((f) => "file '${f.replaceAll("'", "'\\''")}'")
              .join('\n'),
        );
        final merged = p.join(dir.path, 'reel_merged_$stamp.mp4');
        final res = await runStage(
          FfmpegService.concatCommand(listFile: listFile, output: merged),
          0.25,
          0.30,
          expectedMs: reelMs,
        );
        if (!res.ok) {
          return ReelExportResult(
            success: false,
            error: 'Clips join nahi hue. ${res.logs}',
            failedStep: 'Clips join karna',
            notes: notes,
          );
        }
        out = merged;
      }
      step('Clips join ho gaye.', 0.30);

      {
        final c = cancelledResult();
        if (c != null) return c;
      }
      // --- 2. Voiceover mix (ducked under the voice). ---
      final voiceover = handoff.voiceoverPath;
      if (voiceover != null) {
        step('Voiceover mix ho raha hai…', 0.35);
        final hasAudio = await probeHasAudio(File(out));
        final mixOut = p.join(dir.path, 'reel_voicemix_$stamp.mp4');
        final res = await runStage(
          FfmpegService.voiceoverMixCommand(
            input: out,
            voiceoverPath: voiceover,
            output: mixOut,
            hasClipAudio: hasAudio,
            audioBitrateKbps: effectiveSettings.audioBitrateKbps,
          ),
          0.35,
          0.45,
          expectedMs: reelMs,
        );
        if (res.ok) {
          out = mixOut;
        } else {
          notes.add(
            'Voiceover mix fail ho gaya — clip audio ke saath export '
            'ho raha hai.',
          );
        }
      } else {
        notes.add('Voiceover nahi bani — baghair voice ke export ho raha hai.');
      }
      step('Voiceover done.', 0.45);

      {
        final c = cancelledResult();
        if (c != null) return c;
      }
      // --- 2b. Background music bed (v1.2.0, built-in news music). ---
      // The picked built-in track (project.backgroundMusicAsset) loops
      // quietly under whatever audio the reel already has. Any failure
      // is a NOTE — the export continues without the bed, never fails.
      final musicTrack =
          BuiltInNewsMusic.fromAsset(project.backgroundMusicAsset);
      if (musicTrack != null) {
        step('Background music mix ho raha hai…', 0.46);
        final musicFile = await _extractAsset(
          musicTrack.assetPath,
          dir,
          'reel_music_$stamp.mp3',
        );
        if (musicFile == null) {
          notes.add(
            'Background music file nahi mila — baghair music ke export '
            'ho raha hai.',
          );
        } else {
          final hasAudio = await probeHasAudio(File(out));
          final bedOut = p.join(dir.path, 'reel_musicmix_$stamp.mp4');
          final res = await runStage(
            FfmpegService.musicBedCommand(
              input: out,
              musicPath: musicFile.path,
              output: bedOut,
              hasClipAudio: hasAudio,
              // v1.3.0 (§9 criterion 10): the Final template's bed
              // sits at the reference level 0.12 with 0.8 s / 1.5 s
              // fades; other kinds keep the v1.2.0 level.
              musicVolume:
                  project.templateKind == 'nigraanFinal' ? 0.12 : 0.18,
              fadeInSec: project.templateKind == 'nigraanFinal' ? 0.8 : 0,
              fadeOutSec: project.templateKind == 'nigraanFinal' ? 1.5 : 0,
              durationSec:
                  project.templateKind == 'nigraanFinal' && reelMs != null
                      ? reelMs / 1000
                      : null,
              audioBitrateKbps: effectiveSettings.audioBitrateKbps,
            ),
            0.46,
            0.48,
            expectedMs: reelMs,
          );
          if (res.ok) {
            out = bedOut;
          } else {
            notes.add(
              'Background music mix nahi hua — baghair music ke export '
              'ho raha hai.',
            );
          }
        }
        step('Background music done.', 0.48);
      }

      {
        final c = cancelledResult();
        if (c != null) return c;
      }
      // --- 3. Chroma key (preset sensitivity + background). ---
      final chroma = handoff.chroma;
      if (chroma != null) {
        step('Chroma key lag raha hai…', 0.48);
        var chromaForExport = chroma;
        if (handoff.chromaBackgroundAsset != null) {
          try {
            final bgFile = await ensureLutFile(
              handoff.chromaBackgroundAsset!,
              dir,
            );
            chromaForExport = ProChroma(
              color: chroma.color,
              similarity: chroma.similarity,
              blend: chroma.blend,
              backgroundKind: 'image',
              backgroundImagePath: bgFile.path,
            );
          } catch (_) {
            notes.add(
              'Chroma background load nahi hua — solid background ke '
              'saath key ho raha hai.',
            );
            chromaForExport = ProChroma(
              color: chroma.color,
              similarity: chroma.similarity,
              blend: chroma.blend,
              backgroundKind: 'color',
              backgroundColor: '#00FF00',
            );
          }
        }
        final chromaOut = p.join(dir.path, 'reel_chroma_$stamp.mp4');
        final res = await runStage(
          chromaPassCommand(
            input: out,
            c: chromaForExport,
            output: chromaOut,
          ),
          0.48,
          0.55,
          expectedMs: reelMs,
        );
        if (res.ok) {
          out = chromaOut;
        } else {
          notes.add(
            'Chroma key fail ho gaya — baghair chroma ke export ho '
            'raha hai.',
          );
        }
      }
      step('Chroma done.', 0.55);

      {
        final c = cancelledResult();
        if (c != null) return c;
      }
      // --- 3b. Manual MEDIA element adjustment (v1.5.0 #33):
      // the composited main video is scaled / shifted onto the
      // template's dark background colour, or covered entirely
      // when the user removed it — BEFORE the template furniture
      // is drawn over it, exactly like the preview's media layer.
      final mediaOv =
          overrideFor(project.elementOverrides, NewsElement.media);
      if (!mediaOv.isIdentity) {
        step('Media adjust ho raha hai…', 0.56);
        final mediaOut = p.join(dir.path, 'reel_media_$stamp.mp4');
        final String mediaCmd;
        if (mediaOv.hidden) {
          mediaCmd = '-y -i ${FfmpegService.q(out)} '
              '-filter_complex "[0:v]drawbox=x=0:y=0:w=iw:h=ih:'
              'color=0x101018:t=fill[vout]" '
              '-map "[vout]" -map 0:a? '
              '-c:v libx264 -preset veryfast -crf 23 -c:a copy '
              '-movflags +faststart ${FfmpegService.q(mediaOut)}';
        } else {
          final sw = (w * mediaOv.scale).round();
          final sh = (h * mediaOv.scale).round();
          final mx = ((w - sw) / 2 + mediaOv.dx * w).round();
          final my = ((h - sh) / 2 + mediaOv.dy * h).round();
          mediaCmd = '-y -i ${FfmpegService.q(out)} '
              '-f lavfi -i color=c=0x101018:s=${w}x$h:r=30 '
              '-filter_complex "[0:v]scale=$sw:$sh[m];'
              '[1:v][m]overlay=$mx:$my:shortest=1[vout]" '
              '-map "[vout]" -map 0:a? '
              '-c:v libx264 -preset veryfast -crf 23 -c:a copy '
              '-movflags +faststart ${FfmpegService.q(mediaOut)}';
        }
        final res = await runStage(
          mediaCmd,
          0.56,
          0.58,
          expectedMs: reelMs,
        );
        if (res.ok) {
          out = mediaOut;
        } else {
          notes.add(
            'Media adjustment nahi laga — default size/position '
            'ke saath export ho raha hai.',
          );
        }
      }

      // --- 4. Template overlay (logo left OUT of the PNG). ---
      // nigraanFinal still-frame contract: every other still caller
      // of renderLiveTemplateImage (Template Studio frame export,
      // poster export, video-editor template pass) passes
      // tickerAtStart: true, because this is ONE static PNG
      // (tickerPx: 0). In _renderNigraanFinalImage the non-pinned
      // RTL branch starts the top ticker at x = width and both loop
      // copies land outside the strip's clip rect, so with the top
      // ribbon's default RTL direction the pasted ticker text would
      // be INVISIBLE in the exported reel (strip + chip only).
      // Pinning the ticker at its start makes the Final 3-Ribbon
      // frame render in export exactly as it does in those stills.
      // Scoped to 'nigraanFinal' ONLY: the breaking / classic call
      // arguments are unchanged, so their frames render exactly as
      // they do today.
      step('Template lag raha hai…', 0.58);
      final effective = effectivePresetFor(project: project, preset: preset);
      final templatePng = await renderLiveTemplateImage(
        template: NewsTemplate(),
        tickerPx: 0,
        now: DateTime.now(),
        dir: dir,
        width: w,
        height: h,
        templateKind: project.templateKind,
        preset: effective,
        breakingTemplate: project.templateKind == 'breaking'
            ? BreakingTemplate.fromProject(project, effective)
            : null,
        tickerAtStart: project.templateKind == 'nigraanFinal',
        includeLogo: false,
        fontReady: fontReady,
        includeIntroMarker: false,
      );
      // v1.3.0 (§9): for 'nigraanFinal' the ANIMATED parity pass
      // replaces the static PNG overlay AND the separate logo step
      // — both ribbons scroll, the logo rotates bottom-right and
      // the capsule clock ticks/flips, exactly like the real
      // Nigraan videos. A failed parity pass falls back to the
      // static overlay below with a note (never a silent swap).
      var parityApplied = false;
      if (project.templateKind == 'nigraanFinal') {
        final parityOut = await _applyParityTemplate(
          input: out,
          dir: dir,
          stamp: stamp,
          preset: effective,
          width: w,
          height: h,
          fontReady: fontReady,
          assetService: assetService,
          notes: notes,
          settings: effectiveSettings,
          reelMs: reelMs,
          onProgress: onProgress,
          overrides: project.elementOverrides,
        );
        if (parityOut != null) {
          out = parityOut;
          parityApplied = true;
        } else {
          notes.add(
            'Animated Final template nahi laga — static template ke '
            'saath export ho raha hai.',
          );
          if (project.elementOverrides.isNotEmpty) {
            notes.add(
              'Manual element adjustments (Elements panel) sirf '
              'animated template pass mein lagte hain — is static '
              'export mein default layout aaya hai.',
            );
          }
        }
      }
      if (!parityApplied) {
        final templated = p.join(dir.path, 'reel_templated_$stamp.mp4');
        final overlayCmd = FfmpegService.overlayPassCommand(
          input: out,
          templatePngPath: templatePng.path,
          output: templated,
          videoBitrateKbps: effectiveSettings.videoBitrateKbps,
        );
        if (overlayCmd == null) {
          notes.add('Template overlay skip hua (koi overlay nahi bana).');
        } else {
          final res = await runStage(
            overlayCmd,
            0.58,
            0.68,
            expectedMs: reelMs,
          );
          if (res.ok) {
            out = templated;
          } else {
            notes.add(
              'Template overlay fail ho gaya — saaf video export ho '
              'rahi hai.',
            );
          }
        }
      }
      step('Template done.', 0.68);

      {
        final c = cancelledResult();
        if (c != null) return c;
      }
      // --- 5. Rotating logo overlay (inside the parity pass for
      // 'nigraanFinal' — skipped there, the logo + capsule are
      // already burned in at the reference position). ---
      if (!parityApplied) {
        step('Logo lag raha hai…', 0.70);
        final logoDone = await _overlayRotatingLogo(
          input: out,
          dir: dir,
          stamp: stamp,
          preset: preset,
          width: w,
          height: h,
          topRibbonEnabled: effective.topRibbon.enabled,
          assetService: assetService,
          notes: notes,
          settings: effectiveSettings,
          reelMs: reelMs,
          onProgress: onProgress,
        );
        if (logoDone != null) out = logoDone;
      }
      step('Logo done.', 0.78);

      {
        final c = cancelledResult();
        if (c != null) return c;
      }
      // --- 5b. Watermark overlay (Phase 8). ---
      step('Watermark lag raha hai…', 0.78);
      final watermarkDone = await _overlayWatermark(
        input: out,
        dir: dir,
        stamp: stamp,
        preset: preset,
        width: w,
        height: h,
        notes: notes,
        settings: effectiveSettings,
        reelMs: reelMs,
        onProgress: onProgress,
        overrides: project.elementOverrides,
      );
      if (watermarkDone != null) out = watermarkDone;
      step('Watermark done.', 0.80);

      {
        final c = cancelledResult();
        if (c != null) return c;
      }
      // --- 6. Intro / outro assembly. ---
      step('Intro/outro jor rahe hain…', 0.80);
      // Built-in video intro template (v1.2.0): when the project has
      // one applied, extract its bundled MP4 so the assembly can
      // prepend it as the first segment. Missing/failed = note only.
      String? videoIntroPath;
      final vtpl = VideoIntroTemplate.fromId(project.videoTemplateId);
      if (vtpl != null) {
        final f = await _extractAsset(
          vtpl.assetPath,
          dir,
          'reel_vtpl_$stamp.mp4',
        );
        if (f != null) {
          videoIntroPath = f.path;
        } else {
          notes.add(
            'Video intro template file nahi mila — intro ke baghair '
            'export ho raha hai.',
          );
        }
      }
      final assembled = await _assembleIntroOutro(
        main: out,
        dir: dir,
        stamp: stamp,
        preset: preset,
        templatePng: templatePng,
        width: w,
        height: h,
        assetService: assetService,
        notes: notes,
        settings: effectiveSettings,
        reelMs: reelMs,
        onProgress: onProgress,
        videoIntroPath: videoIntroPath,
      );
      if (assembled != null) out = assembled;
      step('Intro/outro done.', 0.86);

      {
        final c = cancelledResult();
        if (c != null) return c;
      }
      // --- 7. Karaoke caption burn-in (ASS first, drawtext fallback). ---
      final ass = styledAssForProject(
        project: project,
        playResX: w,
        playResY: h,
      );
      if (ass != null) {
        step('Captions burn ho rahe hain…', 0.88);
        final burned = await _burnInCaptions(
          input: out,
          assContent: ass,
          dir: dir,
          stamp: stamp,
          quality: q,
          notes: notes,
          settings: effectiveSettings,
          reelMs: reelMs,
          onProgress: onProgress,
        );
        if (burned != null) out = burned;
      }
      step('Captions done.', 0.96);

      {
        final c = cancelledResult();
        if (c != null) return c;
      }
      // --- 8. Gallery save. ---
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) {
          return ReelExportResult(
            success: false,
            error: 'Gallery access denied — video save nahi hui.',
            failedStep: 'Gallery save karna',
            notes: notes,
          );
        }
      }
      await Gal.putVideo(out);
      step('Gallery mein save ho gaya.', 1.0);
      return ReelExportResult(
        success: true,
        outputPath: out,
        notes: notes,
      );
    } catch (e) {
      return ReelExportResult(
        success: false,
        error: 'Export fail ho gaya: $e',
        failedStep: 'Export',
        notes: notes,
      );
    }
  }

  static Future<Directory> _workDir() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory(p.join(tmp.path, 'reel_export'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Extracts a bundled asset to a real file in [dir] (FFmpeg needs
  /// file paths, not asset keys). Returns null on any failure — the
  /// caller notes it and continues; never throws (v1.2.0).
  static Future<File?> _extractAsset(
    String assetPath,
    Directory dir,
    String name,
  ) async {
    try {
      final data = await rootBundle.load(assetPath);
      final f = File(p.join(dir.path, name));
      await f.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      return f;
    } catch (_) {
      return null;
    }
  }

  /// Step 5 — rotating logo overlay. Returns the new output path, or
  /// null when the logo pass was skipped (a note explains why).
  /// Source order (rotation-decision.md): user logo → generated
  /// frames; default logo → cached mov (ping-pong) when downloaded,
  /// else generated frames from the default initial tile.
  /// Step 4 (v1.3.0, 'nigraanFinal' only) — the ANIMATED parity
  /// template pass: renders the parity layers (lib/live/
  /// parity_template.dart) and burns them in with ONE ffmpeg pass —
  /// both ribbons scroll, the logo rotates bottom-right, the
  /// capsule clock ticks with seconds and flips to the Urdu date.
  /// Logo source order: the cached alpha .mov → generated rotating
  /// frames from the picked logo → the picked logo as a still.
  /// Returns the new output path, or null on failure (the caller
  /// falls back to the static overlay with a note).
  static Future<String?> _applyParityTemplate({
    required String input,
    required Directory dir,
    required int stamp,
    required ChannelPreset preset,
    required int width,
    required int height,
    required bool fontReady,
    AssetDownloadService? assetService,
    required List<String> notes,
    ExportSettings settings = const ExportSettings(),
    int? reelMs,
    void Function(double progress)? onProgress,
    Map<String, ElementOverride> overrides = const {},
  }) async {
    try {
      final assets = await renderParityAssets(
        preset: preset,
        dir: dir,
        width: width,
        height: height,
        now: DateTime.now(),
        fontReady: fontReady,
        overrides: overrides,
      );
      final svc = assetService ?? const AssetDownloadService();
      String? movPath;
      String? framesDir;
      String? stillPath;
      // v1.5.0 (#33): a logo the user removed is never resolved —
      // all four sources stay null and the command skips the logo
      // stack (the capsule still renders, unless also removed).
      final logoHidden =
          overrideFor(overrides, NewsElement.logo).hidden;
      final mov = logoHidden ? null : await svc.cachedLogoMov();
      if (mov != null) {
        movPath = mov.path;
      } else if (!logoHidden && preset.logoPath != null &&
          await File(preset.logoPath!).exists()) {
        try {
          final key = logoLoopCacheKey(logoFile: File(preset.logoPath!));
          final dirFrames = Directory(p.join(dir.path, 'logo_loop_$key'));
          await LogoLoopService.generateFrames(
            logoFile: File(preset.logoPath!),
            outDir: dirFrames,
          );
          framesDir = dirFrames.path;
        } catch (_) {
          stillPath = preset.logoPath;
        }
      }
      // final3 default logo (demo v4): the user's green-screen
      // rotating-cube video — only when no user logo was picked
      // (a picked logo keeps its generated-frames behaviour).
      // Missing bundle → null → the existing path (fail soft).
      String? gsPath;
      if (!logoHidden &&
          preset.finalIs3Ribbon &&
          framesDir == null &&
          stillPath == null) {
        final gs = await svc.ensureLogoGsFile();
        gsPath = gs?.path;
      }
      // Clock font: bundled DejaVu → a system font → none (the
      // capsule then shows only its date face; a note says so).
      String? clockFont;
      final dejaVu = await svc.ensureDejaVuFile();
      clockFont = dejaVu?.path ?? FfmpegService.findFontFile();
      if (clockFont == null) {
        notes.add(
          'Clock font nahi mila — capsule mein sirf date nazar '
          'aayegi.',
        );
      }
      final parityOut = p.join(dir.path, 'reel_parity_$stamp.mp4');
      final cmd = buildParityTemplateCommand(
        input: input,
        output: parityOut,
        assets: assets,
        logoGsPath: gsPath,
        logoMovPath: movPath,
        logoFramesDir: framesDir,
        logoStillPng: stillPath,
        clockFontFile: clockFont,
        exportStart: DateTime.now(),
        videoBitrateKbps: settings.videoBitrateKbps,
      );
      final res = await _runStage(
        cmd,
        0.58,
        0.76,
        expectedMs: reelMs,
        onProgress: onProgress,
      );
      if (res.ok) return parityOut;
      notes.add('Animated template pass fail ho gaya. ${res.logs}');
      return null;
    } catch (e) {
      notes.add('Animated template pass fail ho gaya ($e).');
      return null;
    }
  }

  static Future<String?> _overlayRotatingLogo({
    required String input,
    required Directory dir,
    required int stamp,
    required ChannelPreset preset,
    required int width,
    required int height,
    required bool topRibbonEnabled,
    AssetDownloadService? assetService,
    required List<String> notes,
    ExportSettings settings = const ExportSettings(),
    int? reelMs,
    void Function(double progress)? onProgress,
  }) async {
    final logoOut = p.join(dir.path, 'reel_logo_$stamp.mp4');
    try {
      final userLogo = preset.logoPath;
      if (userLogo != null && await File(userLogo).exists()) {
        final key = logoLoopCacheKey(logoFile: File(userLogo));
        final framesDir = Directory(p.join(dir.path, 'logo_loop_$key'));
        await LogoLoopService.generateFrames(
          logoFile: File(userLogo),
          outDir: framesDir,
        );
        final cmd = FfmpegService.logoLoopOverlayCommand(
          input: input,
          output: logoOut,
          width: width,
          height: height,
          topRibbonEnabled: topRibbonEnabled,
          framesDir: framesDir.path,
          videoBitrateKbps: settings.videoBitrateKbps,
        );
        final res = await _runStage(
          cmd,
          0.70,
          0.78,
          expectedMs: reelMs,
          onProgress: onProgress,
        );
        if (res.ok) return logoOut;
        notes.add('Logo overlay fail ho gaya — baghair logo ke export.');
        return null;
      }
      // Default logo: the pre-rendered mov when it is on the device.
      final svc = assetService ?? const AssetDownloadService();
      final mov = await svc.cachedLogoMov();
      if (mov != null) {
        final cmd = FfmpegService.logoLoopOverlayCommand(
          input: input,
          output: logoOut,
          width: width,
          height: height,
          topRibbonEnabled: topRibbonEnabled,
          movPath: mov.path,
          videoBitrateKbps: settings.videoBitrateKbps,
        );
        final res = await _runStage(
          cmd,
          0.70,
          0.78,
          expectedMs: reelMs,
          onProgress: onProgress,
        );
        if (res.ok) return logoOut;
        notes.add(
          'Rotating logo (mov) fail ho gaya — generated loop se try '
          'ho raha hai.',
        );
      } else {
        notes.add(
          'Rotating logo mov abhi download nahi hua — generated '
          'rotating logo use ho raha hai.',
        );
      }
      final initial = preset.name.trim().isEmpty
          ? 'N'
          : preset.name.trim()[0].toUpperCase();
      final key = logoLoopCacheKey(initial: initial);
      final framesDir = Directory(p.join(dir.path, 'logo_loop_$key'));
      await LogoLoopService.generateFrames(outDir: framesDir, initial: initial);
      final cmd = FfmpegService.logoLoopOverlayCommand(
        input: input,
        output: logoOut,
        width: width,
        height: height,
        topRibbonEnabled: topRibbonEnabled,
        framesDir: framesDir.path,
        videoBitrateKbps: settings.videoBitrateKbps,
      );
      final res = await _runStage(
        cmd,
        0.70,
        0.78,
        expectedMs: reelMs,
        onProgress: onProgress,
      );
      if (res.ok) return logoOut;
      notes.add('Logo overlay fail ho gaya — baghair logo ke export.');
      return null;
    } catch (e) {
      notes.add('Logo overlay fail ho gaya ($e) — baghair logo ke export.');
      return null;
    }
  }

  /// Step 5b — watermark overlay (Phase 8). Returns the new output
  /// path, or null when the watermark is off (the normal case for a
  /// preset with the toggle off — no note) or the pass failed (a
  /// note explains it; the export continues without a watermark).
  static Future<String?> _overlayWatermark({
    required String input,
    required Directory dir,
    required int stamp,
    required ChannelPreset preset,
    required int width,
    required int height,
    required List<String> notes,
    ExportSettings settings = const ExportSettings(),
    int? reelMs,
    void Function(double progress)? onProgress,
    Map<String, ElementOverride> overrides = const {},
  }) async {
    if (!preset.watermarkEnabled) return null;
    // v1.5.0 (#33): a watermark the user removed in the Elements
    // panel is skipped exactly like the preset toggle being off.
    final wmOv = overrideFor(overrides, NewsElement.overlay);
    if (wmOv.hidden) return null;
    final wmOut = p.join(dir.path, 'reel_watermark_$stamp.mp4');
    try {
      final wmPng = await renderWatermarkImage(
        preset: preset,
        dir: dir,
        width: width,
        height: height,
      );
      // #33 move/resize: the watermark PNG is a full-frame layer —
      // scale it, re-pad it onto a transparent canvas and crop
      // the frame window at the shifted origin. Failure keeps the
      // designed PNG (with a note), never blocks the export.
      var wmPath = wmPng.path;
      if (!wmOv.isIdentity) {
        final tw = (width * wmOv.scale).round();
        final th = (height * wmOv.scale).round();
        final canvasW = tw > width ? tw : width;
        final canvasH = th > height ? th : height;
        final padX = (canvasW - tw) ~/ 2;
        final padY = (canvasH - th) ~/ 2;
        final cropX =
            (padX - (wmOv.dx * width).round()).clamp(0, canvasW - width);
        final cropY =
            (padY - (wmOv.dy * height).round()).clamp(0, canvasH - height);
        final moved = p.join(dir.path, 'watermark_moved_$stamp.png');
        final movedRes = await FfmpegService.run(
          '-y -i ${FfmpegService.q(wmPng.path)} '
          '-vf "format=rgba,scale=$tw:$th,'
          'pad=$canvasW:$canvasH:$padX:$padY:color=0x00000000,'
          'crop=$width:$height:$cropX:$cropY" '
          '${FfmpegService.q(moved)}',
        );
        if (movedRes.ok) {
          wmPath = moved;
        } else {
          notes.add(
            'Watermark ki manual position/size nahi lagi — '
            'designed position ke saath export ho raha hai.',
          );
        }
      }
      final res = await _runStage(
        FfmpegService.watermarkOverlayCommand(
          input: input,
          watermarkPngPath: wmPath,
          output: wmOut,
          videoBitrateKbps: settings.videoBitrateKbps,
        ),
        0.78,
        0.80,
        expectedMs: reelMs,
        onProgress: onProgress,
      );
      if (res.ok) return wmOut;
      notes.add(
        'Watermark lag nahi saka — baghair watermark ke export ho '
        'raha hai.',
      );
      return null;
    } catch (e) {
      notes.add(
        'Watermark lag nahi saka ($e) — baghair watermark ke export '
        'ho raha hai.',
      );
      return null;
    }
  }

  /// Step 6 — intro/outro assembly. Returns the assembled path, or
  /// null when there is nothing to assemble (both off / intro
  /// unavailable). The intro is prepended only when its file is on
  /// the device; a missing intro is a NOTE, never a crash and never
  /// a fake "intro added". The outro is a 3 s end card — the branding
  /// end card (channel name + real social handles) when the preset
  /// has handles, else the template PNG as before.
  static Future<String?> _assembleIntroOutro({
    required String main,
    required Directory dir,
    required int stamp,
    required ChannelPreset preset,
    required File templatePng,
    required int width,
    required int height,
    AssetDownloadService? assetService,
    required List<String> notes,
    ExportSettings settings = const ExportSettings(),
    int? reelMs,
    void Function(double progress)? onProgress,
    String? videoIntroPath,
  }) async {
    final segments = <String>[];

    // Built-in video intro template segment (v1.2.0) — always FIRST
    // when the project has one applied. Normalized like the channel
    // intro; a failed normalize is a note, never a crash.
    final vtplPath = videoIntroPath;
    if (vtplPath != null) {
      final hasAudio = await probeHasAudio(File(vtplPath));
      final vtplNorm = p.join(dir.path, 'reel_vtpl_norm_$stamp.mp4');
      final res = await _runStage(
        FfmpegService.normalizeWithAudioCommand(
          input: vtplPath,
          trimStart: 0,
          trimEnd: 30,
          width: width,
          height: height,
          output: vtplNorm,
          addSilentAudio: !hasAudio,
          fps: settings.fps,
          videoBitrateKbps: settings.videoBitrateKbps,
          audioBitrateKbps: settings.audioBitrateKbps,
        ),
        0.80,
        0.82,
        expectedMs: 17000,
        onProgress: onProgress,
      );
      if (res.ok) {
        segments.add(vtplNorm);
      } else {
        notes.add(
          'Video intro template tayyar nahi hua — intro ke baghair '
          'export ho raha hai.',
        );
      }
    }

    if (preset.showIntro) {
      final svc = assetService ?? const AssetDownloadService();
      File? intro;
      try {
        // v1.3.0 (§9.9): the intro ships BUNDLED with the app —
        // cache → bundle first, the (currently unconfigured)
        // download URL only as a last resort.
        intro = await svc.ensureIntroFile();
        intro ??= await svc.getIntroVideo(
          url: AppConfig.nigraanIntroUrl,
        );
      } catch (e) {
        intro = null;
        notes.add(
          'Intro download nahi hua ($e) — intro ke baghair export '
          'ho raha hai.',
        );
      }
      if (intro != null) {
        final hasAudio = await probeHasAudio(intro);
        final introNorm = p.join(dir.path, 'reel_intro_$stamp.mp4');
        final res = await _runStage(
          FfmpegService.normalizeWithAudioCommand(
            input: intro.path,
            trimStart: 0,
            trimEnd: 10,
            width: width,
            height: height,
            output: introNorm,
            addSilentAudio: !hasAudio,
            // v1.3.0 (§9.9): the Final template's intro is
            // normalised with BLURRED FILL (the reference
            // treatment), never centre-cropped.
            blurFill: preset.templateKind == 'nigraanFinal',
            fps: settings.fps,
            videoBitrateKbps: settings.videoBitrateKbps,
            audioBitrateKbps: settings.audioBitrateKbps,
          ),
          0.80,
          0.83,
          expectedMs: 10000,
          onProgress: onProgress,
        );
        if (res.ok) {
          segments.add(introNorm);
        } else {
          notes.add(
            'Intro tayyar nahi hua — intro ke baghair export ho raha hai.',
          );
        }
      }
    } else {
      notes.add('Intro off hai — intro ke baghair export ho raha hai.');
    }

    segments.add(main);

    if (preset.showOutro) {
      // Branding end card (Phase 8) when the channel has real social
      // handles — name + handles, never placeholders; otherwise the
      // template frame as before. A failed end-card render falls
      // back to the template frame with a note.
      var outroImage = templatePng;
      if (preset.hasSocialHandles) {
        try {
          outroImage = await renderBrandingEndCardImage(
            preset: preset,
            dir: dir,
            width: width,
            height: height,
          );
        } catch (_) {
          notes.add(
            'End card nahi bana — template frame outro ke tor par '
            'use ho raha hai.',
          );
        }
      }
      final outroSeg = p.join(dir.path, 'reel_outro_$stamp.mp4');
      final res = await _runStage(
        FfmpegService.stillSegmentCommand(
          imagePath: outroImage.path,
          durationSec: 3,
          width: width,
          height: height,
          output: outroSeg,
          fps: settings.fps,
          videoBitrateKbps: settings.videoBitrateKbps,
          audioBitrateKbps: settings.audioBitrateKbps,
        ),
        0.83,
        0.86,
        expectedMs: 3000,
        onProgress: onProgress,
      );
      if (res.ok) {
        segments.add(outroSeg);
      } else {
        notes.add(
          'Outro card nahi bana — outro ke baghair export ho raha hai.',
        );
      }
    }

    if (segments.length == 1) return null;
    final listFile = p.join(dir.path, 'reel_assemble_$stamp.txt');
    await File(listFile).writeAsString(
      segments
          .map((f) => "file '${f.replaceAll("'", "'\\''")}'")
          .join('\n'),
    );
    final assembled = p.join(dir.path, 'reel_assembled_$stamp.mp4');
    final res = await _runStage(
      FfmpegService.concatCommand(listFile: listFile, output: assembled),
      0.86,
      0.88,
      expectedMs: reelMs,
      onProgress: onProgress,
    );
    if (!res.ok) {
      notes.add(
        'Intro/outro join fail ho gaya — main video export ho rahi hai.',
      );
      return null;
    }
    return assembled;
  }

  /// Step 7 — caption burn-in: styled ASS first (full karaoke style),
  /// drawtext fallback second (Latin scripts only — drawtext cannot
  /// shape Urdu). Returns the burned path, or null when both attempts
  /// fail (a note explains it; the export continues without captions).
  static Future<String?> _burnInCaptions({
    required String input,
    required String assContent,
    required Directory dir,
    required int stamp,
    required VideoExportQuality quality,
    required List<String> notes,
    ExportSettings settings = const ExportSettings(),
    int? reelMs,
    void Function(double progress)? onProgress,
  }) async {
    final burned = p.join(
      dir.path,
      'reel_captioned_$stamp.mp4',
    );
    final assFile = File(p.join(dir.path, 'reel_captions_$stamp.ass'));
    await assFile.writeAsString(assContent);
    final scale = VideoExportService.scaleFor(quality, true);
    // Phase 9 — the export screen's real fps/bitrate: fps in the
    // filter chain, an explicit video bitrate replaces CRF 23, an
    // explicit audio bitrate re-encodes audio instead of `-c:a copy`.
    final videoArgs = settings.videoBitrateKbps == null
        ? '-c:v libx264 -preset veryfast -crf 23'
        : '-c:v libx264 -preset veryfast '
            '-b:v ${settings.videoBitrateKbps}k '
            '-maxrate ${(settings.videoBitrateKbps! * 3 / 2).round()}k '
            '-bufsize ${settings.videoBitrateKbps! * 2}k';
    final audioArgs = settings.audioBitrateKbps == null
        ? '-c:a copy'
        : '-c:a aac -b:a ${settings.audioBitrateKbps}k';
    final assCmd =
        '-y -i ${FfmpegService.q(input)} '
        '-vf "$scale,fps=${settings.fps},subtitles=${VideoExportService.escapeFilterPath(assFile.path)}" '
        '$videoArgs $audioArgs '
        '-movflags +faststart ${FfmpegService.q(burned)}';
    var res = await _runStage(
      assCmd,
      0.88,
      0.96,
      expectedMs: reelMs,
      onProgress: onProgress,
    );
    if (res.ok) return burned;
    final drawtext = await VideoExportService.buildDrawtextFilter(
      assContent: assContent,
      scale: scale,
      quality: quality,
      vertical: true,
    );
    if (drawtext != null) {
      final dtCmd =
          '-y -i ${FfmpegService.q(input)} '
          '-vf "$drawtext" '
          '$videoArgs $audioArgs '
          '-movflags +faststart ${FfmpegService.q(burned)}';
      res = await _runStage(
        dtCmd,
        0.88,
        0.96,
        expectedMs: reelMs,
        onProgress: onProgress,
      );
      if (res.ok) {
        notes.add(
          'Styled captions fail hue — plain captions burn hue hain.',
        );
        return burned;
      }
    }
    notes.add(
      'Captions burn nahi hue — baghair captions ke export ho raha hai.',
    );
    return null;
  }
}
