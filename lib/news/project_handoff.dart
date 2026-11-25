/// News Maker → Video Editor timeline handoff (Phase 7).
///
/// The live video editor (`lib/video/video_editor_screen.dart`) keeps
/// its clips in a private `List<VideoClip>` it fills only from its own
/// gallery picker, so a project cannot be handed over as raw fields —
/// [buildHandoff] resolves a [NewsProject] + its [ChannelPreset] into
/// one plain data object the editor consumes in `initState`:
///
///   - clips: only paths that actually exist on disk (missing files
///     are LISTED in [droppedClipPaths], never silently dropped);
///   - voiceover: the cached WAV path, only when the file exists;
///   - captions: the project's subtitle lines, already on the reel
///     timeline (0-based over the whole reel — the editor must NOT
///     re-offset them, see the flag in the editor);
///   - template: the live-template view of the project (headline,
///     lower third, ticker, logo) for the editor's template pass, plus
///     [templateKind] so the editor renders the nigraanFinal /
///     breaking / classic PNG instead of the live design;
///   - chroma: the persisted preset settings as a [ProChroma] (the
///     sensitivity the Template Studio slider saved) + the background
///     source — a bundled asset path ([chromaBackgroundAsset]) or a
///     gallery file ([ProChroma.backgroundImagePath]); the editor
///     materialises the asset to a file before export;
///   - PIP: the preset's enabled/position/scale + the project's
///     picked inset video ([NewsProject.pipVideoPath], P0-3 —
///     before that field existed the switch had no source at all
///     and the reel export never composited an inset).
///
/// Pure + synchronous (only `File.existsSync` checks) so it is covered
/// by plain unit tests with real temp files.
library;

import 'dart:io';

import '../services/caption_service.dart';
import '../services/fx_pack.dart';
import '../services/pro_editor.dart';
import '../live/news_template.dart';
import 'channel_preset.dart';
import 'news_analysis.dart';
import 'news_project.dart';

/// Everything the video editor needs to open a news project.
class ProjectHandoff {
  ProjectHandoff({
    required this.clipPaths,
    required this.droppedClipPaths,
    required this.voiceoverPath,
    required this.captions,
    required this.template,
    required this.templateKind,
    required this.preset,
    required this.chroma,
    required this.chromaBackgroundAsset,
    required this.pipEnabled,
    required this.pipPosition,
    required this.pipScale,
    required this.cappedClipCount,
    this.clipTrims = const [],
    this.pipVideoPath,
  });

  /// Clip paths that exist on disk, in timeline order.
  final List<String> clipPaths;

  /// Per-clip trim ranges (P1-3), PARALLEL to [clipPaths] — the
  /// trim of the project entry each handed-over clip came from.
  /// May be shorter than [clipPaths] in hand-built handoffs;
  /// [trimAt] falls back to the full range.
  final List<ClipTrim> clipTrims;

  /// Trim of handed-over clip [i] (full range when absent).
  ClipTrim trimAt(int i) =>
      (i >= 0 && i < clipTrims.length) ? clipTrims[i] : ClipTrim.full;

  /// The project's PIP inset video (P0-3), only when the file
  /// exists on disk — null = PIP has no source, and the export
  /// says so in its notes instead of faking an inset.
  final String? pipVideoPath;

  /// Project clip paths whose file is gone — shown to the user, never
  /// silently dropped.
  final List<String> droppedClipPaths;

  /// Cached voiceover WAV path, or null when there is none / it is gone.
  final String? voiceoverPath;

  /// Project subtitles as caption segments, already timeline-relative.
  final List<CaptionSegment> captions;

  /// Live-template view of the project (headline / lower third /
  /// ticker / logo) for the editor's news-template pass.
  final NewsTemplate template;

  /// 'nigraanFinal' | 'breaking' | 'classic' — which PNG renderer the
  /// editor's template pass uses.
  final String templateKind;

  /// The channel preset (may be null when the caller has none).
  final ChannelPreset? preset;

  /// Chroma-key setup from the preset, or null when chroma is off.
  /// `backgroundKind` is always 'image' here: a bundled backdrop and
  /// a gallery pick are both image backgrounds; the bundled one is
  /// resolved to a file by the editor (see [chromaBackgroundAsset]).
  final ProChroma? chroma;

  /// Bundled chroma backdrop asset path (e.g.
  /// `assets/backgrounds/newsroom.jpg`), or null when the background
  /// is a gallery file / chroma is off.
  final String? chromaBackgroundAsset;

  /// PIP from the preset: enabled + inset position + scale.
  final bool pipEnabled;
  final PipPosition pipPosition;
  final double pipScale;

  /// Clips dropped by the Phase 9 cap ([NewsProject.maxClips]) —
  /// reported to the user, never silently dropped. (Missing files
  /// are the separate [droppedClipPaths].)
  final int cappedClipCount;
}

/// Maps project subtitle lines to caption segments (the ASS /
/// burn-in shape). Words are carried over for karaoke sync;
/// [translation] feeds the dual-language line.
List<CaptionSegment> captionSegmentsFromSubtitles(
  List<SubtitleLine> subtitles,
) {
  return subtitles
      .map(
        (s) => CaptionSegment(
          s.text,
          s.startSec,
          s.endSec,
          words: s.words
              .map(
                (w) => CaptionWord(
                  word: w.word,
                  start: w.startSec,
                  end: w.endSec,
                ),
              )
              .toList(),
          translation: s.translation,
        ),
      )
      .toList();
}
/// Never throws for bad input: missing files become [ProjectHandoff.droppedClipPaths]
/// / nulls, and a missing preset degrades to template-only data.
ProjectHandoff buildHandoff({
  required NewsProject project,
  ChannelPreset? preset,
}) {
  final clips = <String>[];
  final clipTrims = <ClipTrim>[];
  final dropped = <String>[];
  // Phase 9 cap: only the first [NewsProject.maxClips] existing
  // clips are handed over; the rest are counted (not silently
  // dropped) so the export can report them.
  var capped = 0;
  for (var i = 0; i < project.clipPaths.length; i++) {
    final path = project.clipPaths[i];
    if (File(path).existsSync()) {
      if (clips.length >= NewsProject.maxClips) {
        capped++;
        continue;
      }
      clips.add(path);
      clipTrims.add(project.trimAt(i));
    } else {
      dropped.add(path);
    }
  }

  // P0-3: the PIP inset's video source rides the handoff too —
  // only when the picked file is actually there.
  final pipPath = project.pipVideoPath;
  final pipVideo =
      (pipPath != null && pipPath.isNotEmpty && File(pipPath).existsSync())
          ? pipPath
          : null;

  String? voiceover;
  final vo = project.voiceoverPath;
  if (vo != null && File(vo).existsSync()) voiceover = vo;

  final captions = captionSegmentsFromSubtitles(project.subtitles);

  final tickerText = project.tickerText.isNotEmpty
      ? project.tickerText
      : (preset?.topRibbon.text ?? '');
  final template = NewsTemplate(
    breakingHeadline: project.headline,
    lowerTitle: preset?.lowerThirdTitle ?? '',
    lowerSubtitle: preset?.lowerThirdSubtitle ?? '',
    tickerText: tickerText,
    logoPath: preset?.logoPath,
    logoRotate: preset?.logoRotate ?? true,
  );

  ProChroma? chroma;
  String? chromaAsset;
  if (preset != null && preset.chromaEnabled) {
    if (preset.chromaBackground == ChromaBackgroundKind.gallery) {
      final bgPath = preset.chromaBackgroundPath;
      chroma = ProChroma(
        color: 'green',
        similarity: preset.chromaSensitivity,
        blend: 0.1,
        backgroundKind: 'image',
        backgroundImagePath:
            bgPath != null && File(bgPath).existsSync() ? bgPath : null,
      );
      // A gallery background whose file is gone: fall back to the
      // solid colour instead of keying onto nothing.
      if (chroma.backgroundImagePath == null) {
        chroma = ProChroma(
          color: 'green',
          similarity: preset.chromaSensitivity,
          blend: 0.1,
          backgroundKind: 'color',
          backgroundColor: '#00FF00',
        );
      }
    } else {
      chromaAsset = preset.chromaBackground.assetPath;
      chroma = ProChroma(
        color: 'green',
        similarity: preset.chromaSensitivity,
        blend: 0.1,
        backgroundKind: 'image',
        // The editor fills the real file path in after materialising
        // [chromaBackgroundAsset]; null here means "asset, not file".
        backgroundImagePath: null,
      );
    }
  }

  var pipPosition = PipPosition.bottomRight;
  if (preset != null) {
    pipPosition = switch (preset.pipPosition) {
      'topLeft' => PipPosition.topLeft,
      'topRight' => PipPosition.topRight,
      'bottomLeft' => PipPosition.bottomLeft,
      _ => PipPosition.bottomRight,
    };
  }

  return ProjectHandoff(
    clipPaths: clips,
    droppedClipPaths: dropped,
    voiceoverPath: voiceover,
    captions: captions,
    template: template,
    templateKind: project.templateKind,
    preset: preset,
    chroma: chroma,
    chromaBackgroundAsset: chromaAsset,
    pipEnabled: preset?.pipEnabled ?? false,
    pipPosition: pipPosition,
    pipScale: (preset?.pipScale ?? 0.3).clamp(0.15, 0.5),
    cappedClipCount: capped,
    clipTrims: clipTrims,
    pipVideoPath: pipVideo,
  );
}

/// Effective preset for a project: a copy of [preset] with the
/// project's own ticker/headline applied to the top ribbon (the
/// ribbon-content rule: top = CURRENT story). The reel export and the
/// template preview both render from this, so the PNG matches what
/// the user sees on screen.
ChannelPreset effectivePresetFor({
  required NewsProject project,
  required ChannelPreset preset,
}) {
  final copy = ChannelPreset.fromJson(preset.toJson());
  final ticker = project.tickerText.trim();
  copy.topRibbon.text =
      ticker.isEmpty ? project.headline.trim() : ticker;
  // v1.5.2 (fix #65): the project's English ticker text drives
  // the bottom ribbon — the same rule the Maker preview applies,
  // so preview and export can never disagree.
  final englishTicker = project.englishTickerText.trim();
  if (englishTicker.isNotEmpty) {
    copy.englishRibbon.text = englishTicker;
  }
  copy.templateKind = project.templateKind;
  // Tools-fix wave (P0-3): the Breaking Banner SWITCH is the
  // preset's own showBreakingBanner — the deep copy above already
  // carries it, and the Maker preview reads that same value. The
  // old line overwrote it with project.breaking (the template
  // KIND flag), which forced the banner off for every non-
  // breaking project and made the Template panel's switch dead
  // in export. The switch now wins, preview == export.
  // P0-3 (ticker direction): the project's direction override
  // steers the export's top ribbon exactly as it steers the
  // Maker preview's top band (and the Breaking template, which
  // already honoured it) — one value, read by both.
  final directionOverride = project.tickerDirection;
  if (directionOverride != null) {
    copy.topRibbon.direction = RibbonDirection.fromId(directionOverride);
  }
  // Build 13 (point #19): the project's ticker speed + loop
  // ride the copy as TRANSIENT fields (never serialised) — the
  // parity geometry reads them from here, so preview (which
  // applies the same rule in the Maker) and export agree.
  copy.tickerSpeedFactor = project.tickerSpeed;
  copy.tickerLoop = project.tickerLoop;
  // Build 13 (point 6): the working logo parts ride the
  // effective preset too (transient — see ChannelPreset).
  copy.logoParts = preset.logoParts;
  copy.logoPartsSourcePath = preset.logoPartsSourcePath;
  return copy;
}
