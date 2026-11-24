// Phase 4 (Master Plan): the Video Editor export pipeline, split out
// of video_editor_screen.dart. Behaviour is unchanged: this class
// drives the exact same staged render through the screen's State via
// the VideoEditorController contract.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../app_config.dart';
import '../live/news_template.dart';
import '../news/breaking_templates.dart';
import '../news/project_handoff.dart';
import '../services/asset_download_service.dart';
import '../services/logo_loop_service.dart';
import '../live/parity_template.dart';
import '../services/unity_ads_service.dart';
import '../services/ffmpeg_service.dart';
import '../services/caption_service.dart';
import '../services/pro_editor.dart';
import '../services/fx_pack.dart';
import '../services/pro_vision.dart';
import '../services/pro_service.dart';
import '../services/reel_export_service.dart';
import '../services/video_export_service.dart';
import 'editor_models.dart';
import 'video_editor_controller.dart';

/// Phase 0: thrown inside the export pipeline when the user has
/// cancelled the export; caught by [_VideoEditorScreenState._export]
/// and turned into the "Export cancel kar diya gaya." status.
class ExportCancelled implements Exception {
  const ExportCancelled();
}

class VideoEditorExportController {
  final VideoEditorController host;
  const VideoEditorExportController(this.host);


  Future<void> _exportInner() async {
    try {
      final dir = await host.workDir();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      var out = p.join(dir.path, 'pve_export_$stamp.mp4');
      // v1.4.0: per-clip volume / mute materialisation — every clip
      // whose own gain is off 1.0 or that is muted is replaced by a
      // processed copy (video stream copied, audio gained/silenced)
      // before the main pipeline runs, the same replace-in-place
      // pattern as the reverse / silence passes below. Guarded per
      // clip: a failure keeps that clip's original file.
      for (var i = 0; i < host.clips.length; i++) {
        final c = host.clips[i];
        if (c.isPhoto || (c.volume == 1 && !c.muted)) continue;
        try {
          final proc = p.join(dir.path, 'clipvol_${stamp}_$i.mp4');
          final cmd = c.muted
              ? '-i ${FfmpegService.q(c.file.path)} -c:v copy -an '
                    '-y ${FfmpegService.q(proc)}'
              : '-i ${FfmpegService.q(c.file.path)} -c:v copy '
                    '-af volume=${c.volume.toStringAsFixed(2)} '
                    '-c:a aac -b:a 128k -y ${FfmpegService.q(proc)}';
          final r = await FfmpegService.run(cmd);
          if (r.ok) {
            final nc = VideoClip(File(proc), c.duration, c.aspectRatio);
            nc.trimStart = c.trimStart;
            nc.trimEnd = c.trimEnd;
            nc.volume = c.volume;
            nc.muted = c.muted;
            nc.detachedAudioPath = c.detachedAudioPath;
            host.clips[i] = nc;
          }
        } catch (_) {
          // Keep the original clip — the export must not fail over
          // a per-clip gain.
        }
      }
      host.checkExportCancelled();
      if (host.clips.isNotEmpty) {
        final int idx = host.selected < host.clips.length ? host.selected : 0;
        VideoClip clip = host.clips[idx];
        if (host.fxReverse) {
          final String revOut = p.join(dir.path, 'fx_rev_$stamp.mp4');
          final FfmpegResult r = await FfmpegService.run(
            reverseCommand(input: clip.file.path, output: revOut),
          );
          if (r.ok) {
            final VideoClip nc = VideoClip(
              File(revOut),
              clip.duration,
              clip.aspectRatio,
            );
            nc.trimStart = clip.trimStart;
            nc.trimEnd = clip.trimEnd;
            host.clips[idx] = nc;
          }
        }
        if (host.fxSilenceRemove) {
          final String silOut = p.join(dir.path, 'fx_sil_$stamp.mp4');
          final VideoClip cur = host.clips[idx];
          final FfmpegResult r = await FfmpegService.run(
            silenceRemoveCommand(input: cur.file.path, output: silOut),
          );
          if (r.ok) {
            host.clips[idx] = VideoClip(
              File(silOut),
              cur.duration,
              cur.aspectRatio,
            );
          }
        }
      }
      host.checkExportCancelled();
      host.fontFile ??= FfmpegService.findFontFile();
      final hasText = host.text.trim().isNotEmpty;
      if (hasText && host.fontFile == null) {
        host.setStatus(
          'Note: no system font found, exporting without text overlay.',
        );
      }
      final text = hasText ? host.text : null;

      // Auto captions: ASS subtitles (proper Urdu shaping) or, on the
      // fallback retry, timed drawtext (Latin scripts only).
      String? subsPath;
      String? capFilter;
      var useCaptions = host.captions.isNotEmpty;
      if (useCaptions) {
        final adjusted = host.adjustedCaptions();
        if (adjusted.isEmpty) {
          useCaptions = false;
        } else if (host.captionDrawtextFallback) {
          capFilter = CaptionService.buildDrawtextFilters(
            segments: adjusted,
            fontFile: host.fontFile,
            fontSize: host.clips.first.aspectRatio < 1.0 ? 56 : 40,
          );
          if (capFilter == null) {
            throw Exception(
              'Captions need the subtitles filter for Urdu text, which '
              'this build does not support.',
            );
          }
        } else {
          final assPath = p.join(dir.path, 'captions_$stamp.ass');
          final portrait = host.clips.first.aspectRatio < 1.0;
          await File(assPath).writeAsString(
            CaptionService.buildAss(
              segments: adjusted,
              portrait: portrait,
              style: host.captionStyle,
            ),
          );
          subsPath = assPath;
        }
      }

      // PRO: beat auto-cut (single clip only). Beats were detected on
      // the source file, so segment boundaries are intersected with
      // the clip's trim range, then each segment is trimmed with the
      // existing normalize primitive and concat-joined into one
      // intermediate clip. The normal pipeline then runs on that
      // intermediate as a one-clip export. Multi-clip + beat sync =
      // markers only (no cut).
      var clips = host.clips;
      // v1.3.0 (§6.1): photo clips are materialised to real video
      // segments first (Ken Burns zoom or a static hold), so every
      // later stage sees ordinary video clips.
      var hadPhoto = false;
      if (clips.any((c) => c.isPhoto)) {
        hadPhoto = true;
        final mat = <VideoClip>[];
        for (var i = 0; i < clips.length; i++) {
          final c = clips[i];
          if (!c.isPhoto) {
            mat.add(c);
            continue;
          }
          final portraitP = c.aspectRatio < 1.0;
          final pw = host.fxQuality == 2
              ? (portraitP ? 2160 : 3840)
              : host.fxQuality == 1
              ? (portraitP ? 1080 : 1920)
              : (portraitP ? 720 : 1280);
          final ph = host.fxQuality == 2
              ? (portraitP ? 3840 : 2160)
              : host.fxQuality == 1
              ? (portraitP ? 1920 : 1080)
              : (portraitP ? 1280 : 720);
          final seg = p.join(dir.path, 'photo_${stamp}_$i.mp4');
          host.setStatus('Photo clip ${i + 1} tayyar ho raha hai…');
          final res = await FfmpegService.run(
            FfmpegService.photoClipCommand(
              imagePath: c.file.path,
              output: seg,
              width: pw,
              height: ph,
              durationSec: c.effectiveDuration,
              kenBurns: c.kenBurns,
              zoomIn: c.kbZoomIn,
            ),
          );
          if (!res.ok) {
            throw Exception('Photo clip ${i + 1} failed. ${res.logs}');
          }
          mat.add(VideoClip(File(seg), c.duration, c.aspectRatio));
        }
        clips = mat;
      }
      if (host.beatAutoCut &&
          host.beats.isNotEmpty &&
          host.clips.length == 1 &&
          !hadPhoto) {
        final src = host.clips.first;
        final segments = beatSegments(
          host.beats,
          src.duration.inMilliseconds / 1000,
        );
        final portraitCut = src.aspectRatio < 1.0;
        final cw = portraitCut ? 720 : 1280;
        final ch = portraitCut ? 1280 : 720;
        final cutParts = <String>[];
        var cutTotalMs = 0;
        for (var i = 0; i < segments.length; i++) {
          final seg = segments[i];
          final s = math.min(
            math.max(seg.start, src.trimStart),
            src.effectiveEnd,
          );
          final e = math.min(
            math.max(seg.end, src.trimStart),
            src.effectiveEnd,
          );
          if (e - s < 0.2) continue;
          final part = p.join(dir.path, 'beatcut_${stamp}_$i.mp4');
          host.setStatus('Beat cut ${i + 1}/${segments.length}…');
          final res = await FfmpegService.run(
            FfmpegService.normalizeCommand(
              input: src.file.path,
              trimStart: s,
              trimEnd: e,
              width: cw,
              height: ch,
              output: part,
            ),
          );
          if (!res.ok) {
            throw Exception('Beat cut part ${i + 1} failed. ${res.logs}');
          }
          cutParts.add(part);
          cutTotalMs += ((e - s) * 1000).round();
        }
        if (cutParts.isNotEmpty) {
          final cutList = p.join(dir.path, 'beatcut_$stamp.txt');
          await File(cutList).writeAsString(
            cutParts
                .map((f) => "file '${f.replaceAll("'", "'\\''")}'")
                .join('\n'),
          );
          final cutFile = p.join(dir.path, 'beatcut_$stamp.mp4');
          final cc = FfmpegService.concatCommand(
            listFile: cutList,
            output: cutFile,
          );
          host.setStatus('Beat cuts jor rahe hain…');
          final res = await FfmpegService.run(cc);
          if (!res.ok) throw Exception('Beat cut join failed. ${res.logs}');
          clips = [
            VideoClip(
              File(cutFile),
              Duration(milliseconds: cutTotalMs),
              src.aspectRatio,
            ),
          ];
        }
      }

      // PRO: grading + speed ramp, resolved once for the whole export.
      // The LUT asset file is resolved here; on failure the export
      // continues with sliders only (status note, never a failure).
      String? lutPath;
      if (host.proLut.isNotEmpty) {
        try {
          String? asset;
          for (final e in proLuts) {
            if ((e['name'] ?? '') == host.proLut) asset = e['asset'];
          }
          if (asset != null) {
            final f = await ensureLutFile(asset, dir);
            lutPath = f.path;
          }
        } catch (e) {
          host.setStatus(
            'Note: LUT load nahi hua, baghair LUT ke export ho raha hai.',
          );
        }
      }
      final gradeStr = host.gradeActive
          ? gradeFilter(
              ProGrade(
                lutName: host.proLut,
                temperature: host.proTemperature,
                tint: host.proTint,
                saturation: host.proSaturation,
                vibrance: host.proVibrance,
                contrast: host.proContrast,
                shadows: host.proShadows,
                highlights: host.proHighlights,
                brightness: host.proBrightness,
                exposure: host.proExposure,
              ),
              lutFilePath: lutPath,
            )
          : '';
      final rampPreset = host.rampPreset();
      final exportDurSec = clips.fold<double>(
        0.0,
        (a, c) => a + c.effectiveDuration,
      );
      // v1.3.0 (§6.10): the 'Custom' ramp builds its segments from
      // the three point speeds (start / middle / end thirds).
      final customRamp = host.proRamp == 'Custom' && exportDurSec > 0;
      final hasRamp = rampPreset != null || customRamp;
      final rampSegs = rampPreset != null
          ? rampSegments(rampPreset, exportDurSec)
          : customRamp
          ? <RampSegment>[
              RampSegment(tStart: 0, tEnd: exportDurSec / 3, speed: host.rampStart),
              RampSegment(
                tStart: exportDurSec / 3,
                tEnd: exportDurSec * 2 / 3,
                speed: host.rampMid,
              ),
              RampSegment(
                tStart: exportDurSec * 2 / 3,
                tEnd: exportDurSec,
                speed: host.rampEnd,
              ),
            ]
          : <RampSegment>[];
      final List<String> extraParts = <String>[];
      if (gradeStr.isNotEmpty) extraParts.add(gradeStr);
      // v1.4.0 Adjust extras (sharpen / clarity / whites / blacks /
      // hue / fade / vignette / grain / auto) ride the same chain.
      final adjustExtra = host.adjustExtraFilter();
      if (adjustExtra.isNotEmpty) extraParts.add(adjustExtra);
      if (hasRamp) extraParts.add(rampSetpts(rampSegs));
      final String shakeStr = shakeFilter(host.fxShake);
      if (shakeStr.isNotEmpty) extraParts.add(shakeStr);
      final String? extraVideoFilter = extraParts.isEmpty
          ? null
          : extraParts.join(',');
      // Ramp replaces the fixed speed: the video timing comes from the
      // ramp setpts, and the audio filter from the ramp (music exports
      // keep the music track untouched, so the ramp audio filter only
      // applies when no music is picked).
      final effectiveSpeed = hasRamp ? 1.0 : host.speed;
      // v1.3.0 (§6.8): auto-duck keeps the music OUT of the main
      // pass — a post-pass sidechain-ducks it under the clip audio.
      final duckMusic = host.autoDuck && host.musicPath != null;
      final String? mainMusicPath = duckMusic ? null : host.musicPath;
      final String? rampAudio = (hasRamp && mainMusicPath == null)
          ? rampAudioFilter(rampSegs)
          : null;
      final String voiceStr = voiceFxFilter(host.fxVoice);
      final String fadeStr = audioFadeFilter(
        fadeInSec: host.fxFadeIn,
        fadeOutSec: host.fxFadeOut,
        durationSec: exportDurSec,
      );
      String fxAudioFilter = '';
      if (voiceStr.isNotEmpty) {
        fxAudioFilter = voiceStr;
      }
      if (fadeStr.isNotEmpty) {
        if (fxAudioFilter.isNotEmpty) {
          fxAudioFilter = '$fxAudioFilter,$fadeStr';
        } else {
          fxAudioFilter = fadeStr;
        }
      }
      String? finalAudioFilter;
      final bool isComplex = rampAudio != null && rampAudio.contains('[0:a]');
      if (isComplex) {
        finalAudioFilter = rampAudio;
      } else {
        final List<String> afParts = <String>[];
        // Mute original audio (CapCut/VN-style): silence the clip's own
        // audio at export. Ignored when music is picked — music already
        // replaces the clip audio track.
        if (host.muteOriginal && mainMusicPath == null) {
          afParts.add('volume=0');
        }
        if (effectiveSpeed != 1.0 && mainMusicPath == null) {
          afParts.add('atempo=$effectiveSpeed');
        }
        if (fxAudioFilter.isNotEmpty) {
          afParts.add(fxAudioFilter);
        }
        // Music track gain: with music picked, the output audio stream is
        // the music track, so volume= here adjusts music only.
        if (mainMusicPath != null && host.volumePoints.isNotEmpty) {
          // v1.3.0 (§6.9): music volume keyframes — a piecewise
          // linear gain envelope over the music track.
          afParts.add(
            "volume='${FfmpegService.volumeEnvelopeExpression(host.volumePoints, host.musicVolume)}':eval=frame",
          );
        } else if (mainMusicPath != null && host.musicVolume != 1.0) {
          afParts.add('volume=${host.musicVolume.toStringAsFixed(2)}');
        }
        if (afParts.isNotEmpty) {
          finalAudioFilter = afParts.join(',');
        }
      }

      host.checkExportCancelled();
      double progress = 0;
      void onProgress(double v) {
        if ((v - progress).abs() > 0.05) {
          progress = v;
          host.setStatus('Exporting… ${(v * 100).round()}%');
        }
      }

      if (clips.length == 1) {
        final c = clips.first;
        final cmd = FfmpegService.singleClipCommand(
          input: c.file.path,
          trimStart: c.trimStart,
          trimEnd: c.effectiveEnd,
          speed: effectiveSpeed,
          filterPreset: host.filter,
          // §6.5 blur fill: the main pass keeps the original frame;
          // a post-pass reframes it over its own blurred copy.
          aspect: host.canvasFill == 'blur' ? 'Original' : host.aspect,
          text: text,
          fontFile: host.fontFile,
          subtitlesPath: subsPath,
          captionFilter: capFilter,
          textAtTop: useCaptions,
          musicPath: mainMusicPath,
          extraVideoFilter: extraVideoFilter,
          audioFilter: finalAudioFilter,
          exportQuality: host.fxQuality,
          filterIntensity: host.filterIntensity,
          canvasFill: host.canvasFill == 'color' ? 'color' : 'none',
          fillColor: host.canvasFillColor,
          fps: host.exportFps,
          output: out,
        );
        final totalMs = ((c.effectiveDuration / effectiveSpeed) * 1000).round();
        final res = await FfmpegService.run(
          cmd,
          expectedMs: totalMs,
          onProgress: onProgress,
        );
        if (!res.ok && hasRamp) {
          // PRO ramp fallback (contract in pro_editor.dart): a failed
          // ramp (e.g. a clip with no audio track for the ramp audio
          // chain) must NOT fail the whole export — retry un-ramped.
          host.setStatus(
            'Note: speed ramp fail ho gaya, baghair ramp ke save ho raha hai.',
          );
          final retryCmd = FfmpegService.singleClipCommand(
            input: c.file.path,
            trimStart: c.trimStart,
            trimEnd: c.effectiveEnd,
            speed: effectiveSpeed,
            filterPreset: host.filter,
            aspect: host.canvasFill == 'blur' ? 'Original' : host.aspect,
            text: text,
            fontFile: host.fontFile,
            subtitlesPath: subsPath,
            captionFilter: capFilter,
            textAtTop: useCaptions,
            musicPath: mainMusicPath,
            extraVideoFilter: gradeStr.isEmpty ? null : gradeStr,
            audioFilter: null,
            exportQuality: host.fxQuality,
            filterIntensity: host.filterIntensity,
            canvasFill: host.canvasFill == 'color' ? 'color' : 'none',
            fillColor: host.canvasFillColor,
            fps: host.exportFps,
            output: out,
          );
          final retryRes = await FfmpegService.run(
            retryCmd,
            expectedMs: totalMs,
            onProgress: onProgress,
          );
          if (!retryRes.ok) {
            throw Exception('FFmpeg failed (${res.returnCode}). ${res.logs}');
          }
        } else if (!res.ok) {
          throw Exception('FFmpeg failed (${res.returnCode}). ${res.logs}');
        }
      } else {
        // Step 1: normalize every clip (trim + common size/fps/codec).
        // Orientation comes from the FIRST clip's real aspect ratio.
        final bool portrait = clips.first.aspectRatio < 1.0;
        int w;
        int h;
        if (host.fxQuality == 2) {
          // 2160p 4K (slow): 2026 baseline export; needs more time on
          // low-end phones — the dropdown label says so.
          w = portrait ? 2160 : 3840;
          h = portrait ? 3840 : 2160;
        } else if (host.fxQuality == 1) {
          w = portrait ? 1080 : 1920;
          h = portrait ? 1920 : 1080;
        } else {
          w = portrait ? 720 : 1280;
          h = portrait ? 1280 : 720;
        }
        final normFiles = <String>[];
        final normDurMs = <int>[];
        for (var i = 0; i < clips.length; i++) {
          final c = clips[i];
          final nf = p.join(dir.path, 'norm_${stamp}_$i.mp4');
          final cmd = FfmpegService.normalizeCommand(
            input: c.file.path,
            trimStart: c.trimStart,
            trimEnd: c.effectiveEnd,
            width: w,
            height: h,
            output: nf,
            // §6.5: blur fill frames every clip over its own
            // blurred copy instead of cropping.
            blurFill: host.canvasFill == 'blur',
            // Build 3: normalize at the chosen export frame rate
            // so the join + final pass stay at one rate.
            fps: host.exportFps,
          );
          host.setStatus('Preparing clip ${i + 1}/${clips.length}…');
          final res = await FfmpegService.run(cmd);
          if (!res.ok) {
            throw Exception('Clip ${i + 1} prepare failed. ${res.logs}');
          }
          normFiles.add(nf);
          normDurMs.add((c.effectiveDuration * 1000).round());
        }
        // Step 2: join.
        final merged = p.join(dir.path, 'merged_$stamp.mp4');
        String? joinCmd;
        if (host.crossfade) {
          // PRO: the selected transition + duration replace the fixed
          // fade; the cut-join fallback below is unchanged.
          joinCmd = proXfadeCommand(
            inputs: normFiles,
            durationsMs: normDurMs,
            transition: ProTransition(
              name: host.proTransition,
              durationSec: host.proTransitionDur,
            ),
            hasAudio: true,
            output: merged,
          );
        }
        if (joinCmd != null) {
          host.setStatus('Applying crossfade…');
          final res = await FfmpegService.run(joinCmd);
          if (!res.ok) {
            // Fall back to a hard cut join rather than failing the export.
            host.setStatus('Crossfade failed, falling back to cut join…');
            joinCmd = null;
          }
        }
        if (joinCmd == null) {
          final listFile = p.join(dir.path, 'concat_$stamp.txt');
          final lines = normFiles
              .map((f) => "file '${f.replaceAll("'", "'\\''")}'")
              .join('\n');
          await File(listFile).writeAsString(lines);
          final cc = FfmpegService.concatCommand(
            listFile: listFile,
            output: merged,
          );
          final res = await FfmpegService.run(cc);
          if (!res.ok) throw Exception('Merge failed. ${res.logs}');
        }
        // Step 3: final pass (speed/filter/aspect/text/music).
        final totalMs = ((normDurMs.reduce((a, b) => a + b) / effectiveSpeed))
            .round();
        final fc = FfmpegService.finalPassCommand(
          input: merged,
          fps: host.exportFps,
          speed: effectiveSpeed,
          filterPreset: host.filter,
          // Blur fill already framed the clips in normalize.
          aspect: host.canvasFill == 'blur' ? 'Original' : host.aspect,
          text: text,
          fontFile: host.fontFile,
          subtitlesPath: subsPath,
          captionFilter: capFilter,
          textAtTop: useCaptions,
          musicPath: mainMusicPath,
          extraVideoFilter: extraVideoFilter,
          audioFilter: finalAudioFilter,
          exportQuality: host.fxQuality,
          filterIntensity: host.filterIntensity,
          canvasFill: host.canvasFill == 'color' ? 'color' : 'none',
          fillColor: host.canvasFillColor,
          output: out,
        );
        final res = await FfmpegService.run(
          fc,
          expectedMs: totalMs,
          onProgress: onProgress,
        );
        if (!res.ok && hasRamp) {
          // PRO ramp fallback, same contract as the single-clip branch.
          host.setStatus(
            'Note: speed ramp fail ho gaya, baghair ramp ke save ho raha hai.',
          );
          final retryFc = FfmpegService.finalPassCommand(
            input: merged,
            fps: host.exportFps,
            speed: effectiveSpeed,
            filterPreset: host.filter,
            aspect: host.canvasFill == 'blur' ? 'Original' : host.aspect,
            text: text,
            fontFile: host.fontFile,
            subtitlesPath: subsPath,
            captionFilter: capFilter,
            textAtTop: useCaptions,
            musicPath: mainMusicPath,
            extraVideoFilter: gradeStr.isEmpty ? null : gradeStr,
            audioFilter: null,
            exportQuality: host.fxQuality,
            filterIntensity: host.filterIntensity,
            canvasFill: host.canvasFill == 'color' ? 'color' : 'none',
            fillColor: host.canvasFillColor,
            output: out,
          );
          final retryRes = await FfmpegService.run(
            retryFc,
            expectedMs: totalMs,
            onProgress: onProgress,
          );
          if (!retryRes.ok) {
            throw Exception('Final export failed. ${res.logs}');
          }
        } else if (!res.ok) {
          throw Exception('Final export failed. ${res.logs}');
        }
      }

      // v1.3.0 (§6.5): blur-fill reframe for the SINGLE-clip path
      // (the main pass ran with aspect 'Original'). Guarded like
      // every post-pass.
      host.checkExportCancelled();
      if (clips.length == 1 && host.canvasFill == 'blur' && host.aspect != 'Original') {
        try {
          final dims = FfmpegService.exportDims(host.aspect, host.fxQuality);
          if (dims != null) {
            host.setStatus('Canvas blur fill lag raha hai…');
            final bfOut = p.join(dir.path, 'pve_export_blurfill_$stamp.mp4');
            final res = await FfmpegService.run(
              FfmpegService.blurFillPassCommand(
                input: out,
                output: bfOut,
                width: dims.$1,
                height: dims.$2,
              ),
            );
            if (res.ok) {
              out = bfOut;
            } else {
              host.setStatus(
                'Note: blur fill fail ho gaya, baghair is ke save ho raha hai.',
              );
            }
          }
        } catch (e) {
          host.setStatus(
            'Note: blur fill fail ho gaya ($e), baghair is ke save ho raha hai.',
          );
        }
      }

      // v1.3.0 (§6.8): auto music ducking — the music was kept out
      // of the main pass; here it is sidechain-ducked under the
      // clip's own audio (or becomes the track when there is none).
      host.checkExportCancelled();
      if (duckMusic) {
        try {
          host.setStatus('Music ducking ho raha hai…');
          final hasAudio = await ReelExportService.probeHasAudio(File(out));
          final duckOut = p.join(dir.path, 'pve_export_duck_$stamp.mp4');
          final res = await FfmpegService.run(
            FfmpegService.musicDuckCommand(
              input: out,
              musicPath: host.musicPath!,
              output: duckOut,
              hasClipAudio: hasAudio,
              musicVolume: host.musicVolume,
            ),
          );
          if (res.ok) {
            out = duckOut;
          } else {
            host.setStatus(
              'Note: music ducking fail ho gaya, baghair music ke save ho raha hai.',
            );
          }
        } catch (e) {
          host.setStatus(
            'Note: music ducking fail ho gaya ($e), baghair music ke save ho raha hai.',
          );
        }
      }

      // Timeline handoff (Phase 7): voiceover mix. The project
      // voiceover (Gemini WAV) is mixed over the clip audio, ducked
      // so the voice stays on top; when the video has no audio track
      // the voiceover simply becomes the track. Guarded like the
      // other post-passes: a failure keeps the unmixed export.
      host.checkExportCancelled();
      if (host.projectVoiceoverPath != null &&
          await File(host.projectVoiceoverPath!).exists()) {
        try {
          host.setStatus('Voiceover mix ho raha hai…');
          final hasAudio = await ReelExportService.probeHasAudio(File(out));
          final mixOut = p.join(dir.path, 'pve_export_voicemix_$stamp.mp4');
          final res = await FfmpegService.run(
            FfmpegService.voiceoverMixCommand(
              input: out,
              voiceoverPath: host.projectVoiceoverPath!,
              output: mixOut,
              hasClipAudio: hasAudio,
            ),
          );
          if (res.ok) {
            out = mixOut;
          } else {
            host.setStatus(
              'Note: voiceover mix fail ho gaya, baghair voice ke save ho raha hai.',
            );
          }
        } catch (e) {
          host.setStatus(
            'Note: voiceover mix fail ho gaya ($e), baghair voice ke save ho raha hai.',
          );
        }
      }

      // PRO post-passes, AFTER the main pipeline and BEFORE the news
      // template pass. Each is guarded: on failure the previous output
      // is kept, a status note is written, and the export continues —
      // a pro pass NEVER fails the whole export.
      // (a) Stabilization.
      host.checkExportCancelled();
      if (host.proStabilize) {
        try {
          final stab = p.join(dir.path, 'pve_export_stab_$stamp.mp4');
          var lastPct = -1;
          final res = await runStabilized(
            input: out,
            output: stab,
            workDir: dir,
            // v1.5.0: the Stabilizer panel's level drives the
            // vidstab strength (Standard = the old fixed values).
            shakiness: host.stabLevel == 1 ? 3 : (host.stabLevel == 3 ? 8 : 5),
            smoothing: host.stabLevel == 1 ? 15 : (host.stabLevel == 3 ? 60 : 30),
            expectedMs: (exportDurSec * 1000).round(),
            onProgress: (v) {
              final pct = (v * 100).round();
              if (pct != lastPct) {
                lastPct = pct;
                host.setStatus('Stabilizing… $pct% done, ${100 - pct}% remaining');
              }
            },
            onStep: (s) => host.setStatus(s),
          );
          if (res.ok) {
            out = stab;
            host.setStatus('Stabilized (${res.engine}).');
          } else {
            host.setStatus(
              'Note: stabilization fail ho gaya, baghair is ke save ho raha hai.',
            );
          }
        } catch (e) {
          host.setStatus(
            'Note: stabilization fail ho gaya ($e), baghair is ke save ho raha hai.',
          );
        }
      }
      // (a2) v1.3.0 (§6.7): main-clip transform (scale / position /
      // rotation / opacity over a blurred backdrop).
      host.checkExportCancelled();
      if (host.transformActive) {
        try {
          final size = await VideoExportService.probeVideoSize(File(out));
          if (size != null) {
            host.setStatus('Transform lag raha hai…');
            final tfOut = p.join(dir.path, 'pve_export_transform_$stamp.mp4');
            final res = await FfmpegService.run(
              FfmpegService.transformPassCommand(
                input: out,
                output: tfOut,
                width: size.width,
                height: size.height,
                scale: host.tfScale,
                posX: host.tfX,
                posY: host.tfY,
                rotationDeg: host.tfRot,
                opacity: host.tfOpacity,
              ),
            );
            if (res.ok) {
              out = tfOut;
            } else {
              host.setStatus(
                'Note: transform fail ho gaya, baghair is ke save ho raha hai.',
              );
            }
          }
        } catch (e) {
          host.setStatus(
            'Note: transform fail ho gaya ($e), baghair is ke save ho raha hai.',
          );
        }
      }
      // (b) Chromakey OR video BG remover — mutually exclusive; if
      // both are on, the BG remover wins (status note).
      final useBgRemover = host.proBgRemove;
      host.checkExportCancelled();
      if (useBgRemover && host.proChroma) {
        host.setStatus(
          'Note: BG remover aur chromakey dono on hain — BG remover use ho raha hai.',
        );
      }
      if (useBgRemover) {
        // v1.4.0: MODNet HQ path FIRST — the exported video's
        // frames get MODNet mattes (OnnxImageService) composited
        // over the chosen background. Any failure falls through to
        // the long-standing ML Kit selfie-segmentation path below,
        // so Remove BG never regresses.
        var modnetDone = false;
        try {
          host.setStatus('Video background (MODNet HQ) hata rahe hain…');
          var lastPct = -1;
          final modnetOut = await VideoExportService.modnetRemoveBackground(
            input: out,
            backgroundKind: host.proBgKind,
            backgroundColor: host.proBgColor,
            backgroundImagePath: host.proBgKind == 'image' ? host.proBgImage : null,
            workDir: dir,
            onProgress: (v) {
              final pct = (v * 100).round();
              if (pct != lastPct) {
                lastPct = pct;
                host.setStatus(
                  'MODNet BG remover… $pct% done, ${100 - pct}% remaining',
                );
              }
            },
            onStep: (s) => host.setStatus(s),
          );
          out = modnetOut;
          modnetDone = true;
          host.setStatus('Video background removed (MODNet HQ).');
        } catch (e) {
          host.setStatus(
            'Note: MODNet BG fail ($e) — ML Kit wala tareeqa use ho raha hai.',
          );
        }
        if (!modnetDone) {
          try {
            host.setStatus(
              'Video background hata rahe hain… (lambi clips par minutes lag sakte hain)',
            );
            var lastPct = -1;
            final bgOut = await removeVideoBackground(
              input: out,
              backgroundKind: host.proBgKind,
              backgroundColor: host.proBgColor,
              backgroundImagePath: host.proBgKind == 'image' ? host.proBgImage : null,
              workDir: dir,
              onProgress: (v) {
                final pct = (v * 100).round();
                if (pct != lastPct) {
                  lastPct = pct;
                  host.setStatus(
                    'Video BG remover… $pct% done, ${100 - pct}% remaining',
                  );
                }
              },
              onStep: (s) => host.setStatus(s),
            );
            out = bgOut;
            host.setStatus('Video background removed.');
          } catch (e) {
            host.setStatus(
              'Note: video BG remover fail ho gaya ($e), pichli video save ho rahi hai.',
            );
          }
        }
      } else if (host.proChroma) {
        try {
          host.setStatus('Chromakey laga rahe hain…');
          final chromaOut = p.join(dir.path, 'pve_export_chroma_$stamp.mp4');
          final c = ProChroma(
            color: host.proChromaColor,
            similarity: host.proChromaSimilarity,
            blend: host.proChromaBlend,
            spill: host.proChromaSpill,
            edge: host.proChromaEdge,
            backgroundKind: host.proChromaBgKind,
            backgroundColor: host.proChromaBgColor,
            backgroundImagePath: host.proChromaBgKind == 'image'
                ? host.proChromaBgImage
                : null,
          );
          // ONE builder for the chroma graph (shared with the reel
          // export) — the Template Studio sensitivity + background and
          // the editor's own chroma controls apply through it.
          final cmd = chromaPassCommand(input: out, c: c, output: chromaOut);
          final res = await FfmpegService.run(cmd);
          if (res.ok) {
            out = chromaOut;
          } else {
            host.setStatus(
              'Note: chromakey fail ho gaya, baghair is ke save ho raha hai.',
            );
          }
        } catch (e) {
          host.setStatus(
            'Note: chromakey fail ho gaya ($e), baghair is ke save ho raha hai.',
          );
        }
      }
      // (b2) Build 3 (Phase 3): MAIN-clip mask — the mask model
      // (shape / feather / invert) applied to the main video
      // itself, composited over black (the stage backdrop). Runs
      // after the main picture is final (stabilize / transform /
      // BG passes) and BEFORE the title + PIP passes, so overlays
      // stay unmasked — the stage preview's exact layer order.
      // Guarded like every post-pass.
      host.checkExportCancelled();
      if (host.mainMask != 'none') {
        try {
          host.setStatus('Main mask lag raha hai…');
          final size = await VideoExportService.probeVideoSize(File(out));
          final maskPath = size == null
              ? null
              : await host.renderMainMaskPng(
                  dir: dir,
                  stamp: stamp,
                  width: size.width,
                  height: size.height,
                );
          if (size != null && maskPath != null) {
            final mmOut = p.join(dir.path, 'pve_export_mainmask_$stamp.mp4');
            final res = await FfmpegService.run(
              mainClipMaskCommand(
                input: out,
                maskPng: maskPath,
                width: size.width,
                height: size.height,
                output: mmOut,
              ),
            );
            if (res.ok) {
              out = mmOut;
            } else {
              host.setStatus(
                'Note: main mask fail ho gaya, baghair mask ke save ho raha hai.',
              );
            }
          } else {
            host.setStatus(
              'Note: main mask ke liye size/PNG nahi mila — baghair mask ke save ho raha hai.',
            );
          }
        } catch (e) {
          host.setStatus(
            'Note: main mask fail ho gaya ($e), baghair mask ke save ho raha hai.',
          );
        }
      }
      // (c) ONE combined animated-overlay pass (motion title/sticker +
      // keyframed overlay + tracked sticker). Skipped entirely when
      // none of them are set.
      host.checkExportCancelled();
      if (host.proTitle.trim().isNotEmpty ||
          host.proSticker.trim().isNotEmpty ||
          (host.trackPoints.isNotEmpty && host.trackSticker.trim().isNotEmpty)) {
        try {
          host.setStatus('Motion titles laga rahe hain…');
          final ovOut = p.join(dir.path, 'pve_export_overlay_$stamp.mp4');
          final cmd = await host.buildOverlayCommand(
            dir: dir,
            stamp: stamp,
            input: out,
            output: ovOut,
            durationSec: exportDurSec,
          );
          if (cmd != null) {
            final res = await FfmpegService.run(cmd);
            if (res.ok) {
              out = ovOut;
            } else {
              host.setStatus(
                'Note: motion title pass fail ho gaya, baghair is ke save ho raha hai.',
              );
            }
          }
        } catch (e) {
          host.setStatus(
            'Note: motion title pass fail ho gaya ($e), baghair is ke save ho raha hai.',
          );
        }
      }

      // PIP (Phase 7): the inset IS composited for real in the export
      // ([pipOverlayFilter]) at the preset's position/scale when
      // opened via timeline handoff. SPLIT SCREEN stays deferred:
      // it needs a second concurrent video track, but this timeline
      // is a single sequential clip list — there is no second input
      // to composite (see the reel export header for the full reason).
      host.checkExportCancelled();
      if (host.fxPip && host.fxPipVideo.isNotEmpty) {
        final String pipOut = p.join(dir.path, 'pve_export_pip_$stamp.mp4');
        // PIP position/scale: the long-standing defaults, or the
        // channel preset's settings when opened via timeline handoff
        // (Phase 7) — the inset is composited for real, never a
        // preview-only effect.
        // v1.3.0 (§6.11): opacity + circle mask. Completion fix
        // (user order 22 Nov 2026): blend modes + the full mask set
        // (shapes / linear / radial, feather, invert) via the
        // masked-blend chain in [_pipSnippetAdvanced]. The untouched
        // default (Normal + no mask + full opacity) still takes the
        // original stock snippet, byte-for-byte.
        final bool pipStock =
            host.pipBlend == 'normal' && host.pipMask == 'none' && host.pipOpacity >= 1;
        // Build 3 (Phase 3): PIP keyframes take their own graph
        // (position + opacity lerps, mask composed in). Blend
        // modes are not part of the keyframed graph in v1 — with
        // a blend chosen, the static advanced graph below runs
        // instead and the user is told.
        final bool pipKeyframed = host.pipKeyframes && host.pipBlend == 'normal';
        if (host.pipKeyframes && host.pipBlend != 'normal') {
          host.setStatus(
            'Note: PIP keyframes blend mode ke sath nahi chalte — '
            'blend wala static PIP lag raha hai.',
          );
        }
        String snippet;
        String? pipMaskPath;
        if (pipKeyframed) {
          final baseSize = await VideoExportService.probeVideoSize(File(out));
          final pipSize = await VideoExportService.probeVideoSize(
            File(host.fxPipVideo),
          );
          if (baseSize == null || pipSize == null) {
            host.setStatus(
              'Note: PIP keyframes ke liye size nahi mila — '
              'simple PIP lag raha hai.',
            );
            snippet = pipOverlayFilter(
              pipLabel: '[1:v]',
              position: host.pipPosition,
              pipScale: host.pipScale,
              margin: 24,
              outLabel: '[vout]',
            );
          } else {
            if (host.pipMask != 'none') {
              pipMaskPath = await host.renderPipMaskPng(
                dir: dir,
                stamp: stamp,
                width: pipSize.width,
                height: pipSize.height,
              );
            }
            // Same box math as _pipSnippetAdvanced (even dims,
            // clamped to the base).
            final s = host.pipScale.clamp(0.15, 0.5);
            var pw = ((pipSize.width * s) / 2).floor() * 2;
            var ph = ((pipSize.height * s) / 2).floor() * 2;
            if (pw > baseSize.width) pw = baseSize.width - (baseSize.width % 2);
            if (ph > baseSize.height) {
              ph = baseSize.height - (baseSize.height % 2);
            }
            if (pw < 2) pw = 2;
            if (ph < 2) ph = 2;
            snippet = keyframedPipFilter(
              baseLabel: '[0:v]',
              pipLabel: '[1:v]',
              track: KeyframeTrack(
                start: ProKeyframe(
                  timeSec: 0,
                  xNorm: host.pkStartX,
                  yNorm: host.pkStartY,
                  opacity: host.pkStartOpacity,
                ),
                end: ProKeyframe(
                  timeSec: exportDurSec,
                  xNorm: host.pkEndX,
                  yNorm: host.pkEndY,
                  opacity: host.pkEndOpacity,
                ),
              ),
              videoW: baseSize.width,
              videoH: baseSize.height,
              pipW: pw,
              pipH: ph,
              outLabel: '[vout]',
              easing: host.pkEasing,
              hasMask: pipMaskPath != null,
            );
          }
        } else if (pipStock) {
          snippet = pipOverlayFilter(
            pipLabel: '[1:v]',
            position: host.pipPosition,
            pipScale: host.pipScale,
            margin: 24,
            outLabel: '[vout]',
          );
        } else {
          final baseSize = await VideoExportService.probeVideoSize(File(out));
          final pipSize = await VideoExportService.probeVideoSize(
            File(host.fxPipVideo),
          );
          if (baseSize == null || pipSize == null) {
            // Guarded fallback (FX-pass contract): without probed
            // geometry the advanced graph cannot be built, so the
            // stock composite runs and the user is told.
            host.setStatus(
              'Note: PIP blend/mask ke liye size nahi mila — '
              'simple PIP lag raha hai.',
            );
            snippet = pipOverlayFilter(
              pipLabel: '[1:v]',
              position: host.pipPosition,
              pipScale: host.pipScale,
              margin: 24,
              outLabel: '[vout]',
            );
          } else {
            if (host.pipMask != 'none') {
              pipMaskPath = await host.renderPipMaskPng(
                dir: dir,
                stamp: stamp,
                width: pipSize.width,
                height: pipSize.height,
              );
            }
            snippet = host.pipSnippetAdvanced(
              base: baseSize,
              pip: pipSize,
              hasMask: pipMaskPath != null,
            );
          }
        }
        final StringBuffer pb = StringBuffer();
        pb.write('-y -i ');
        pb.write(FfmpegService.q(out));
        pb.write(' -i ');
        pb.write(FfmpegService.q(host.fxPipVideo));
        if (pipMaskPath != null) {
          // Build 3 termination fix: the mask PNG goes in as a
          // SINGLE frame, never looped — the alpha chain's
          // framesync filters (blend / alphamerge) repeat its last
          // frame for the whole inset, and a looped input never
          // reaches EOF, so blend would generate frames forever
          // (the main-mask render test hung 97 min on exactly
          // this). See mainClipMaskCommand's header note.
          pb.write(' -i ');
          pb.write(FfmpegService.q(pipMaskPath));
        }
        pb.write(' -filter_complex "');
        pb.write(snippet);
        pb.write('" -map "[vout]" -map 0:a? -c:v libx264 -preset veryfast ');
        pb.write('-crf 23 -c:a copy -movflags +faststart ');
        pb.write(FfmpegService.q(pipOut));
        final FfmpegResult pr = await FfmpegService.run(pb.toString());
        if (pr.ok) {
          out = pipOut;
        }
      } else if (host.fxPip) {
        // PIP on but no inset video picked: the pass is skipped and
        // the user is told — never a fake PIP claim.
        host.setStatus(
          'Note: PIP video nahi chuna — PIP ke baghair save ho raha hai.',
        );
      }

      // v2 news template + logo second pass (before gallery save).
      // The template frame is rendered by the same dart:ui renderer
      // the live view uses, so Urdu shaping stays correct. If the
      // pass fails, the clean export is saved instead of failing.
      //
      // v1.3.0 (§9): a 'nigraanFinal' HANDOFF project takes the
      // ANIMATED parity pass instead (both ribbons scroll, rotating
      // logo + flipping clock capsule — parity_template.dart), with
      // the Kasheeda font gate: no font, no template (a loud status,
      // never a fallback-font lookalike). The plain editor's live
      // design keeps the static pass; its ticker/clock note in the
      // News panel was updated accordingly.
      host.checkExportCancelled();
      if (host.newsEnabled) {
        var parityDone = false;
        if (host.projectTemplateKind == 'nigraanFinal' &&
            host.handoffProject != null &&
            host.handoffPreset != null) {
          final svc = const AssetDownloadService();
          final fontReady = await svc.ensureKasheedaFontReady(
            url: AppConfig.kasheedaFontUrl,
          );
          if (!fontReady) {
            host.setStatus(
              'Kasheeda font nahi mila — Final template nahi laga, '
              'saaf video save ho rahi hai.',
            );
          } else {
            try {
              host.setStatus('Final template (animated) lag raha hai…');
              final size = await VideoExportService.probeVideoSize(File(out));
              if (size != null) {
                final effPreset = effectivePresetFor(
                  project: host.handoffProject!,
                  preset: host.handoffPreset!,
                );
                final assets = await renderParityAssets(
                  preset: effPreset,
                  dir: dir,
                  width: size.width,
                  height: size.height,
                  now: DateTime.now(),
                  fontReady: fontReady,
                );
                String? movPath;
                String? framesDir;
                String? stillPath;
                final mov = await svc.cachedLogoMov();
                if (mov != null) {
                  movPath = mov.path;
                } else if (host.news.logoPath != null &&
                    await File(host.news.logoPath!).exists()) {
                  // Logo parity (user spec 22 Nov 2026): a user-imported
                  // logo ROTATES in 3D exactly like the channel logo —
                  // generate its loop frames the same way the reel
                  // export does; the still is only a fallback.
                  try {
                    final key = logoLoopCacheKey(
                      logoFile: File(host.news.logoPath!),
                    );
                    final dirFrames = Directory(
                      p.join(dir.path, 'logo_loop_$key'),
                    );
                    await LogoLoopService.generateFrames(
                      logoFile: File(host.news.logoPath!),
                      outDir: dirFrames,
                    );
                    framesDir = dirFrames.path;
                  } catch (_) {
                    stillPath = host.news.logoPath;
                  }
                }
                // final3 default logo (demo v4): the user's
                // green-screen rotating-cube video — only when no
                // user logo was picked (a picked logo keeps its
                // generated-frames behaviour). Missing bundle →
                // null → the existing path (fail soft).
                String? gsPath;
                if (effPreset.finalIs3Ribbon &&
                    framesDir == null &&
                    stillPath == null) {
                  final gs = await svc.ensureLogoGsFile();
                  gsPath = gs?.path;
                }
                String? clockFont;
                final dejaVu = await svc.ensureDejaVuFile();
                clockFont = dejaVu?.path ?? FfmpegService.findFontFile();
                final parityOut = p.join(
                  dir.path,
                  'pve_export_parity_$stamp.mp4',
                );
                final cmd = buildParityTemplateCommand(
                  input: out,
                  output: parityOut,
                  assets: assets,
                  logoGsPath: gsPath,
                  logoMovPath: movPath,
                  logoFramesDir: framesDir,
                  logoStillPng: stillPath,
                  clockFontFile: clockFont,
                  exportStart: DateTime.now(),
                  videoBitrateKbps: null,
                );
                final res = await FfmpegService.run(cmd);
                if (res.ok) {
                  out = parityOut;
                  parityDone = true;
                } else {
                  host.setStatus(
                    'Note: animated template fail ho gaya, static '
                    'template se try ho raha hai.',
                  );
                }
              }
            } catch (e) {
              host.setStatus(
                'Note: animated template fail ho gaya ($e), static '
                'template se try ho raha hai.',
              );
            }
          }
        }
        if (!parityDone) {
          final useNews =
              host.news.breakingHeadline.trim().isNotEmpty ||
              host.news.lowerTitle.trim().isNotEmpty ||
              host.news.lowerSubtitle.trim().isNotEmpty ||
              host.news.tickerText.trim().isNotEmpty;
          String? templatePng;
          if (useNews) {
            host.setStatus('News template laga rahe hain…');
            // Timeline handoff (Phase 7): render the PROJECT's template
            // kind (nigraanFinal / breaking / classic) from its preset
            // instead of the live design, with the logo left out of the
            // PNG (the static logo comes from the overlay pass below,
            // as before). The plain editor keeps the live render.
            final tplFile = await renderLiveTemplateImage(
              template: host.news,
              tickerPx: 0,
              tickerAtStart: true,
              now: DateTime.now(),
              dir: dir,
              templateKind: host.projectTemplateKind ?? 'live',
              preset: host.handoffPreset,
              breakingTemplate:
                  host.projectTemplateKind == 'breaking' &&
                      host.handoffProject != null &&
                      host.handoffPreset != null
                  ? BreakingTemplate.fromProject(
                      host.handoffProject!,
                      host.handoffPreset!,
                    )
                  : null,
              includeLogo: host.handoffPreset == null,
              includeIntroMarker: host.handoffPreset == null,
            );
            templatePng = tplFile.path;
          }
          String? logoPath;
          final pickedLogo = host.news.logoPath;
          if (pickedLogo != null && await File(pickedLogo).exists()) {
            logoPath = pickedLogo;
          }
          final templated = p.join(dir.path, 'pve_export_templated_$stamp.mp4');
          final overlayCmd = FfmpegService.overlayPassCommand(
            input: out,
            templatePngPath: templatePng,
            logoPath: logoPath,
            logoPosition: host.news.logoPosition.name,
            output: templated,
          );
          if (overlayCmd != null) {
            final res = await FfmpegService.run(overlayCmd);
            if (!res.ok) {
              host.setStatus(
                'Note: news template pass fail ho gaya, saaf video save ho rahi hai.',
              );
            } else {
              out = templated;
            }
          }
        }
      }

      // v1.3.0 (§6.1): intro / outro attach slots — the picked
      // videos are normalised to the export's own dims and joined
      // with the concat demuxer (intro first, outro last). Guarded:
      // a failed attach keeps the unattached export.
      if (host.introClipPath != null || host.outroClipPath != null) {
        try {
          final size = await VideoExportService.probeVideoSize(File(out));
          if (size != null) {
            final segments = <String>[];
            Future<String?> attach(String path, String tag) async {
              final hasAudio = await ReelExportService.probeHasAudio(
                File(path),
              );
              final norm = p.join(dir.path, 'attach_${tag}_$stamp.mp4');
              final res = await FfmpegService.run(
                FfmpegService.normalizeWithAudioCommand(
                  input: path,
                  trimStart: 0,
                  trimEnd: 3600,
                  width: size.width,
                  height: size.height,
                  output: norm,
                  addSilentAudio: !hasAudio,
                ),
              );
              return res.ok ? norm : null;
            }

            if (host.introClipPath != null) {
              final n = await attach(host.introClipPath!, 'intro');
              if (n != null) segments.add(n);
            }
            segments.add(out);
            if (host.outroClipPath != null) {
              final n = await attach(host.outroClipPath!, 'outro');
              if (n != null) segments.add(n);
            }
            if (segments.length > 1) {
              host.setStatus('Intro/outro jor rahe hain…');
              final listFile = p.join(dir.path, 'attach_$stamp.txt');
              await File(listFile).writeAsString(
                segments
                    .map((f) => "file '${f.replaceAll("'", "'\\''")}'")
                    .join('\n'),
              );
              final joined = p.join(dir.path, 'pve_export_joined_$stamp.mp4');
              final res = await FfmpegService.run(
                FfmpegService.concatCommand(listFile: listFile, output: joined),
              );
              if (res.ok) {
                out = joined;
              } else {
                host.setStatus(
                  'Note: intro/outro attach fail ho gaya, baghair is ke save ho raha hai.',
                );
              }
            }
          }
        } catch (e) {
          host.setStatus(
            'Note: intro/outro attach fail ho gaya ($e), baghair is ke save ho raha hai.',
          );
        }
      }

      host.checkExportCancelled();
      if (!await Gal.hasAccess()) {
        if (!await Gal.requestAccess()) {
          throw Exception('Gallery access was denied.');
        }
      }
      await Gal.putVideo(out);
      host.setStatus('Saved to gallery: ${p.basename(out)}');
      UnityAdsService.showInterstitialAd();
      final exportCtx = host.context;
      if (exportCtx.mounted) {
        // Build 3 (Phase 3, PRO-SPEC point 22): the saved video
        // can be shared straight from the completion snackbar.
        ScaffoldMessenger.of(exportCtx).showSnackBar(
          SnackBar(
            content: const Text('Video saved to gallery.'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Share',
              onPressed: () => unawaited(
                SharePlus.instance.share(
                  ShareParams(files: [XFile(out)]),
                ),
              ),
            ),
          ),
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> export() async {
    if (host.clips.isEmpty) {
      host.setStatus('Add at least one video first.');
      return;
    }
    if (host.busy) return;
    // Export settings live at the export step now (one-build):
    // the user confirms quality + frame rate here, CapCut-style,
    // before the render starts. v1.3.0: when the AppBar pill
    // already set them, the dialog is skipped. Build 3: the
    // dialog now carries the frame rate too (24/30/60).
    if (!host.qualityPicked) {
      final ok = await host.pickExportSettings();
      if (ok != true || !host.mounted) return;
    }
    final quality = host.fxQuality;
    // v1.4.0 PRO: 1080p / 4K exports carry the double-ad gate for
    // free users (two back-to-back interstitials before the render
    // starts — the ad service's own 120 s interval may suppress
    // the second when one was just shown). Pro subscribers
    // (ProService.proActive) skip the gate entirely.
    if (quality >= 1 && !ProService.instance.proActive) {
      host.setStatus('Ads chal rahe hain — phir export shuru hoga…');
      await UnityAdsService.showInterstitialAd();
      await UnityAdsService.showInterstitialAd();
      if (!host.mounted) return;
    }
    host.update(() {
      host.busy = true;
      host.exporting = true;
      host.exportCancelRequested = false;
      host.status = 'Exporting…';
    });
    try {
      // Phase 0 pre-run discipline: no zombie ffmpeg session from
      // an earlier abandoned run competes with this export.
      await FfmpegService.prepareForNewRun();
      host.captionDrawtextFallback = false;
      await _exportInner();
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final subFail =
          msg.contains('subtitle') ||
          msg.contains('no such filter') ||
          msg.contains('libass');
      if (host.exportCancelRequested || e is ExportCancelled) {
        // Phase 0: a user cancel is not a failure.
        host.setStatus('Export cancel kar diya gaya.');
      } else if (host.captions.isNotEmpty &&
          subFail &&
          !CaptionService.containsArabicInSegments(host.captions)) {
        host.setStatus('Subtitles filter failed, retrying with text captions…');
        host.captionDrawtextFallback = true;
        try {
          await _exportInner();
        } catch (e2) {
          if (host.exportCancelRequested || e2 is ExportCancelled) {
            host.setStatus('Export cancel kar diya gaya.');
          } else {
            host.setStatus('Export failed: $e2');
          }
        }
      } else {
        host.setStatus('Export failed: $e');
      }
    } finally {
      // Phase 0 sweep: this finally was an UNGUARDED setState —
      // leaving the screen mid-export made it throw on completion.
      if (host.mounted) {
        host.update(() {
          host.busy = false;
          host.exporting = false;
        });
      }
    }
  }
}
