/// News project model + JSON store (Phase 4).
///
/// ONE project JSON is shared by the News Maker editor, the One Click
/// AI News Maker and the SEO step — all three screens read and write
/// the same file, so work never has to be re-typed between them:
///
///   tehreer, voice settings, voiceover file path (+ duration),
///   clips, preset/template, ticker text, headline, summary,
///   subtitles, breaking flag, fact-check sources, SEO.
///
/// Stored as plain JSON in the app documents directory
/// (`news_projects/<id>.json`), same pattern as `news_template.json`
/// / `channel_presets.json`. Autosave is the screens' job (debounced);
/// this file only reads/writes.
///
/// [wavDurationSeconds] parses a WAV (RIFF) header to get the audio
/// length without a player — the voiceover preview shows its duration
/// from the file itself.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/caption_styles.dart';
import '../services/export_settings.dart';
import '../services/gemini_voice_service.dart';
import 'channel_preset.dart';
import 'element_override.dart';
import 'news_analysis.dart';

/// A fact-check source the user attached. The app does NOT auto-verify
/// sources — there is no verification call anywhere in this file or in
/// the screens. The card only LISTS what the user attached, so the
/// user can check them before publishing (master prompt §12: never
/// invent facts/quotes/sources; manual fact-check).
class NewsSource {
  NewsSource({required this.kind, required this.value, this.label = ''});

  /// 'url' or 'text'.
  final String kind;
  final String value;
  final String label;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'value': value,
        'label': label,
      };

  static NewsSource fromJson(Map<String, dynamic> json) {
    return NewsSource(
      kind: (json['kind'] as String?) ?? 'text',
      value: (json['value'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
    );
  }
}

/// SEO fields for one project (saved by the SEO step, §12).
class SeoData {
  SeoData({
    this.title = '',
    this.description = '',
    List<String>? hashtags,
    this.keywords = '',
    this.followLine = defaultFollowLine,
  }) : hashtags = hashtags ?? [];

  String title;
  String description;
  List<String> hashtags;
  String keywords;
  String followLine;

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'hashtags': hashtags,
        'keywords': keywords,
        'followLine': followLine,
      };

  static SeoData fromJson(Map<String, dynamic> json) {
    final rawTags = json['hashtags'];
    final tags = <String>[];
    if (rawTags is List) {
      for (final t in rawTags) {
        if (t is String) tags.add(t);
      }
    }
    return SeoData(
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      hashtags: tags,
      keywords: (json['keywords'] as String?) ?? '',
      followLine:
          (json['followLine'] as String?) ?? defaultFollowLine,
    );
  }
}

/// Per-clip trim range (Tools-fix wave, P1-3): the part of one
/// clip FILE the timeline entry actually uses — [startSec] into
/// the file up to [endSec] (null = to the end of the file). A
/// split is two entries pointing at the same file with adjoining
/// trim ranges, so splitting never copies or re-encodes media.
/// Defaults are the FULL range, which is exactly the pre-trim
/// behaviour; old project JSON has no trim data and loads
/// full-range (backward compatible both ways — an old build
/// reading new JSON simply ignores the extra key).
class ClipTrim {
  const ClipTrim({this.startSec = 0, this.endSec});

  /// Seconds into the clip file where this entry starts (>= 0).
  final double startSec;

  /// Seconds into the clip file where this entry ends, or null
  /// for "to the end of the file".
  final double? endSec;

  /// The untouched range.
  static const ClipTrim full = ClipTrim();

  bool get isFullRange => startSec <= 0 && endSec == null;

  /// Length of the used range when the file is [fileDurationSec]
  /// long (0 when the range is empty / the file is unknown).
  double effectiveDuration(double fileDurationSec) {
    final end = endSec ?? fileDurationSec;
    final d = end - startSec;
    return d > 0 ? d : 0;
  }

  ClipTrim copyWith({double? startSec, double? endSec, bool clearEnd = false}) {
    return ClipTrim(
      startSec: startSec ?? this.startSec,
      endSec: clearEnd ? null : (endSec ?? this.endSec),
    );
  }

  Map<String, dynamic> toJson() => {
        'start': startSec,
        if (endSec != null) 'end': endSec,
      };

  static ClipTrim fromJson(Map<String, dynamic> json) {
    var start = (json['start'] as num?)?.toDouble() ?? 0;
    if (start < 0) start = 0;
    var end = (json['end'] as num?)?.toDouble();
    if (end != null && end <= start) end = null;
    return ClipTrim(startSec: start, endSec: end);
  }
}

/// One news project — the shared JSON behind News Maker, AI News
/// Maker and the SEO step.
class NewsProject {
  NewsProject({
    required this.id,
    this.title = '',
    this.tehreer = '',
    this.voice = GeminiVoice.aoede,
    this.studioVoiceId = '',
    this.voiceoverPath,
    this.voiceoverDurationSec,
    List<String>? clipPaths,
    List<ClipTrim>? clipTrims,
    this.pipVideoPath,
    this.presetId = 'nigraan-tv',
    this.templateKind = 'nigraanFinal',
    this.breakingVariant = 'breakingRedBanner',
    this.tickerText = '',
    this.englishTickerText = '',
    this.tickerLabel = 'BREAKING NEWS',
    this.reporterPhotoPath,
    this.reporterName = '',
    this.headlineFontId = 'jameel_kasheeda',
    this.tickerFontId = 'jameel_kasheeda',
    this.reporterFontId = 'jameel_kasheeda',
    this.headlineStyleId = '',
    this.tickerStyleId = '',
    this.transitionId = '',
    this.effectId = '',
    this.tickerDirection,
    this.videoTemplateId = '',
    this.backgroundMusicAsset,
    this.storeMusicPath,
    this.storeMusicName,
    this.voiceMusicEnabled = true,
    this.musicDucking = true,
    this.tickerSpeed = 1.0,
    this.tickerLoop = true,
    this.captionTimingSource = 'estimate',
    this.captionAlignedHash = '',
    this.headline = '',
    this.summary = '',
    List<SubtitleLine>? subtitles,
    this.breaking = false,
    List<NewsSource>? sources,
    SeoData? seo,
    this.captionStyleId = 'nigraan',
    this.captionPosition = CaptionPosition.bottom,
    this.captionSize = CaptionSize.medium,
    this.captionHighlight,
    this.captionFontId = 'jameel_kasheeda',
    this.captionOutline = true,
    this.captionShadow = false,
    this.captionBackground = false,
    this.captionDualLanguage = false,
    Map<String, ElementOverride>? elementOverrides,
    this.voiceSpeed = 1.0,
    this.voicePauseSec = 0.0,
    this.voiceMusic = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : elementOverrides = elementOverrides ?? {},
        clipPaths = clipPaths ?? [],
        clipTrims = normaliseClipTrims(clipPaths ?? [], clipTrims),
        subtitles = subtitles ?? [],
        sources = sources ?? [],
        seo = seo ?? SeoData(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Stable id — also the JSON file name (`<id>.json`).
  String id;

  /// Display title (defaults to the headline when empty).
  String title;

  /// The Urdu news script — the source of headline, summary,
  /// subtitles, topics and the voiceover.
  String tehreer;

  /// Gemini voice for the voiceover (Aoede female / Charon male).
  GeminiVoice voice;

  /// v1.5.0 (#19): the ONE unified voice selection — a
  /// [StudioVoice] id from the shared 8-voice catalogue (6 Gemini +
  /// Asad/Uzma Edge). Empty = derive from [voice] (the pre-v1.5.0
  /// projects). When a Gemini voice is picked, [voice] is kept in
  /// sync so every other reader of the project stays correct.
  String studioVoiceId;

  /// v1.5.0 (#33): per-element MANUAL overrides (move / resize /
  /// hide) for the Final template's elements, keyed by
  /// [NewsElement] id. Empty = the template renders exactly as
  /// finalised. Applied by the preview + the parity export.
  Map<String, ElementOverride> elementOverrides;

  /// Cached voiceover WAV path (from GeminiVoiceService), or null.
  String? voiceoverPath;

  /// Voiceover length in seconds (WAV header — see
  /// [wavDurationSeconds]), or null when no voiceover yet.
  double? voiceoverDurationSec;

  /// Clip file paths (gallery videos), in timeline order.
  List<String> clipPaths;

  /// Per-clip trim ranges (P1-3), PARALLEL to [clipPaths] — entry
  /// i trims clip i. Always the same length as [clipPaths]: the
  /// constructor normalises it, and every clip-list mutation must
  /// go through [setClipPaths] (or set both lists together, as
  /// the Maker's split does) so the two never drift apart.
  List<ClipTrim> clipTrims;

  /// Tools-fix wave (P0-3): the PIP inset's video source — a
  /// video file the user picked in the Template panel's PIP
  /// section. Before this field the PIP switch/position/scale
  /// existed but no source could ever be chosen, so the export
  /// had nothing to composite. Null = no PIP video picked.
  String? pipVideoPath;

  /// Pads/truncates [trims] to exactly one entry per path in
  /// [paths] (full-range where missing) — the invariant keeper
  /// for the parallel [clipTrims] list.
  static List<ClipTrim> normaliseClipTrims(
    List<String> paths,
    List<ClipTrim>? trims,
  ) {
    return List<ClipTrim>.generate(
      paths.length,
      (i) => (trims != null && i < trims.length) ? trims[i] : ClipTrim.full,
    );
  }

  /// Re-attaches trims after a clip-list edit (add / remove /
  /// reorder from the picker, which returns paths only): the
  /// n-th occurrence of a path in [newPaths] inherits the trim of
  /// the n-th occurrence in [oldPaths], so a split's two halves
  /// (same path, different trims) keep their own ranges through
  /// a reorder. Brand-new paths get the full range.
  static List<ClipTrim> reconcileClipTrims({
    required List<String> oldPaths,
    required List<ClipTrim> oldTrims,
    required List<String> newPaths,
  }) {
    int occurrenceIn(List<String> list, int upto, String path) {
      var n = 0;
      for (var i = 0; i < upto && i < list.length; i++) {
        if (list[i] == path) n++;
      }
      return n;
    }

    return List<ClipTrim>.generate(newPaths.length, (i) {
      final path = newPaths[i];
      final want = occurrenceIn(newPaths, i, path);
      var seen = -1;
      for (var j = 0; j < oldPaths.length; j++) {
        if (oldPaths[j] != path) continue;
        seen++;
        if (seen == want) {
          return j < oldTrims.length ? oldTrims[j] : ClipTrim.full;
        }
      }
      return ClipTrim.full;
    });
  }

  /// The ONE way screens replace the clip list: paths and their
  /// trims move together (see [reconcileClipTrims]).
  void setClipPaths(List<String> next) {
    clipTrims = reconcileClipTrims(
      oldPaths: clipPaths,
      oldTrims: clipTrims,
      newPaths: next,
    );
    clipPaths = List<String>.from(next);
  }

  /// Trim of clip [i] (full range when out of bounds).
  ClipTrim trimAt(int i) =>
      (i >= 0 && i < clipTrims.length) ? clipTrims[i] : ClipTrim.full;

  /// Used length of clip [i] when its file is [fileDurationSec]
  /// long (null = duration unknown → the trim's own span when it
  /// has an end, else null).
  double? clipEffectiveDurationAt(int i, double? fileDurationSec) {
    final trim = trimAt(i);
    if (fileDurationSec != null) return trim.effectiveDuration(fileDurationSec);
    if (trim.endSec != null) return trim.endSec! - trim.startSec;
    return null;
  }

  /// Channel preset id this project belongs to.
  String presetId;

  /// Template kind: 'nigraanFinal' (renders now) or 'breaking'
  /// (render branch lands in Phase 6 — stored now, previewed then).
  String templateKind;

  /// Which of the four breaking variants this project uses when
  /// [templateKind] is 'breaking' (a [BreakingVariant] id). Phase 6:
  /// choosing a variant in a project changes its preview + render.
  String breakingVariant;

  /// Top ticker text — paste-to-run, same contract as Phase 3.
  String tickerText;

  /// v1.5.2 (fix #65): the SECOND ticker's text — the English
  /// ticker on the bottom ribbon. Before this field the Ticker
  /// panel exposed only [tickerText], so the English ticker could
  /// not be edited from the Maker at all (its text was whatever
  /// the preset carried). Applied to the effective preset's
  /// english ribbon in preview + export (see effectivePresetFor);
  /// empty = the preset's own English ribbon text stands.
  String englishTickerText;

  /// v1.5.1 (fix #49): the EDITABLE side label of the ticker band
  /// (the chip at the ticker's side — 'BREAKING NEWS' by default).
  /// Rendered as the label chip in the Final 3-Ribbon bottom band
  /// in preview + export. Empty = no chip.
  String tickerLabel;

  /// v1.5.1 (fix #50): the Reporter (numainda) photo — a path in
  /// the app's documents folder (the picked photo, its BG-removed
  /// cutout, or its BG-replaced composite, whichever the user made
  /// last), or null = no reporter block. Rendered opposite the
  /// logo in the Final template (preview + export), positioned by
  /// the [NewsElement.reporter] override.
  String? reporterPhotoPath;

  /// v1.5.1 (fix #50): the reporter's name, rendered as the name
  /// plate under the reporter photo (e.g. 'Reporter: Rai Ghulam
  /// Jillani Bhatti'). Empty = photo without a plate.
  String reporterName;

  /// v1.5.1 (fix #51): font choices for the headline text, the
  /// ticker text and the reporter name plate — [UrduFonts] ids
  /// (built-ins) or `user:<id>` for a user-uploaded font (see
  /// UserFontService). Default = the house Kasheeda font, which is
  /// what every renderer used before these fields existed.
  String headlineFontId;
  String tickerFontId;
  String reporterFontId;

  /// v1.5.1 (fix #52): Library selections — Drive item folder
  /// ids from the Library engine ('' = none). [headlineStyleId] /
  /// [tickerStyleId] reference 'Text Styles' items (their font
  /// ref, when present, wins over the surface's own font choice);
  /// [transitionId] a 'Transitions' xfade item applied between
  /// the media clips in export; [effectId] an 'Effects' item
  /// (overlay or grade) applied to the main media in export.
  String headlineStyleId;
  String tickerStyleId;
  String transitionId;
  String effectId;

  /// Ticker scroll direction OVERRIDE (v1.2.0 §2.2): a
  /// [RibbonDirection] id ('rtl' / 'ltr') set by the video-template
  /// Direction toggle (Left / Right), or null = no override — the
  /// effective direction then defaults by language (Urdu-script
  /// ticker → rtl, English → ltr; see [effectiveTickerDirection]).
  /// The user's override always wins. Backwards-compatible: absent
  /// in old JSON = null.
  String? tickerDirection;

  /// Bundled video intro template applied to this project (v1.2.0
  /// §2.1): a `VideoIntroTemplate` id ('studioBreakingNews' /
  /// 'globeBreakingNews'), or '' = none applied. Optional and
  /// selectable only — never forced.
  String videoTemplateId;

  /// Bundled built-in background music chosen for this project
  /// (v1.2.0 §2.4): a `BuiltInNewsMusic` asset path
  /// (assets/music/news_music_N.mp3, FREE), or null = none.
  String? backgroundMusicAsset;

  /// Build 12 (point #9a): an Online Store audio item (sound
  /// effect / background music) chosen as this project's
  /// background music in the Audio tool — the owned item's
  /// local file path + display name. When set (and the file
  /// exists) it WINS over [backgroundMusicAsset] in the export
  /// music bed; selecting a built-in track clears it.
  String? storeMusicPath;
  String? storeMusicName;

  /// Build 12 (point #14f): the Voice panel's Background
  /// Music toggle — whether the selected background music
  /// (store item or built-in track) is mixed under the
  /// voiceover in the export. Default true = the historic
  /// behaviour (a selected track always bedded). NOT the same
  /// as [voiceMusic], which is the soft pad mixed at
  /// voice-BUILD time by the TTS services.
  bool voiceMusicEnabled;

  /// Build 13 (point 5): Auto Ducking — when the export mixes
  /// the background-music bed under a voiceover, the bed ducks
  /// under the voice via the engine's sidechain compressor
  /// (the same musicDuckCommand the Video Editor uses). OFF =
  /// the fixed-level bed mix (the pre-Build-13 behaviour).
  /// Default true.
  bool musicDucking;

  /// Build 13 (point 3 / #19): project-level ticker speed
  /// multiplier (0.25–3.0, default 1.0 = the designed speed).
  /// Applied to the parity strip speed in export and to the
  /// preview marquees through the effective preset's transient
  /// tickerSpeedFactor — the Ribbons panel's per-ribbon speeds
  /// are a separate, preset-level control and are untouched.
  double tickerSpeed;

  /// Build 13 (point 3 / #19): whether the ticker scrolls in a
  /// seamless loop (default true, the historic behaviour) or
  /// plays a single pass and stops.
  bool tickerLoop;

  /// Build 13 (point 1 / #16): where the subtitle word timings
  /// came from — 'estimate' (karaoke_sync's proportional
  /// estimator over the real voiceover length) or 'whisper'
  /// (real word timings from the word-split transcription,
  /// mapped onto the script by the script aligner). The UI
  /// labels the two honestly; old projects read as 'estimate'.
  String captionTimingSource;

  /// Build 13 (point 1 / #16): the fingerprint of the inputs
  /// the current 'whisper' timings were computed from (script
  /// text + line texts + voiceover path + duration — see
  /// [captionTimingFingerprint]). When the live fingerprint
  /// differs, the timings are STALE and the UI badges them so.
  String captionAlignedHash;

  /// Build 13 (point 1 / #16): djb2 fingerprint of everything
  /// the aligned timings depend on. Any edit to the tehreer, a
  /// subtitle line's text, or the voiceover itself changes it.
  String get captionTimingFingerprint {
    final buf = StringBuffer()
      ..write(tehreer)
      ..write('|')
      ..write(voiceoverPath ?? '')
      ..write('|')
      ..write(voiceoverDurationSec?.toStringAsFixed(2) ?? '');
    for (final line in subtitles) {
      buf
        ..write('|')
        ..write(line.text);
    }
    final s = buf.toString();
    var hash = 5381;
    for (var i = 0; i < s.length; i++) {
      hash = ((hash * 33) ^ s.codeUnitAt(i)) & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }

  /// True when Whisper-aligned timings exist but their inputs
  /// changed afterwards — the badge condition in the UI.
  bool get captionTimingsStale =>
      captionTimingSource == 'whisper' &&
      captionAlignedHash.isNotEmpty &&
      captionAlignedHash != captionTimingFingerprint;

  /// The ticker direction preview + export must use: the user's
  /// [tickerDirection] override when set, otherwise the language
  /// default for the current [tickerText] (Urdu script → rtl,
  /// otherwise ltr).
  RibbonDirection get effectiveTickerDirection {
    if (tickerDirection != null) {
      return RibbonDirection.fromId(tickerDirection);
    }
    return RegExp(r'[\u0600-\u06FF]').hasMatch(tickerText)
        ? RibbonDirection.rtl
        : RibbonDirection.ltr;
  }

  /// Auto headline (extractive, editable) + auto summary.
  String headline;
  String summary;

  /// Subtitle lines (basic split now; precise sync is Phase 5).
  List<SubtitleLine> subtitles;

  /// Breaking flag — on = breaking template + breaking banner.
  bool breaking;

  /// Caption Studio settings (Phase 5): style + controls applied to
  /// [subtitles] in the preview, ASS export and burn-in. Defaults =
  /// the Nigraan Karaoke house look (green spoken word, Kasheeda,
  /// bottom). [captionHighlight] null = the style's own highlight.
  String captionStyleId;
  CaptionPosition captionPosition;
  CaptionSize captionSize;
  int? captionHighlight;
  String captionFontId;
  bool captionOutline;
  bool captionShadow;
  bool captionBackground;
  bool captionDualLanguage;

  /// Voiceover controls (Phase 5): speed 0.5–2.0x (also changes
  /// pitch — the UI says so), pause between sentences in seconds,
  /// generated ambient pad mixed under the voice.
  double voiceSpeed;
  double voicePauseSec;
  bool voiceMusic;

  /// Fact-check sources the user attached (listed, never auto-verified).
  List<NewsSource> sources;

  /// SEO fields (saved by the SEO step).
  SeoData seo;

  DateTime createdAt;
  DateTime updatedAt;

  /// Fresh draft project. [tehreer] seeds headline/summary/topics
  /// lazily — the screens compute them when the user runs analysis,
  /// never here (no invented content at creation time).
  factory NewsProject.create({String presetId = 'nigraan-tv'}) {
    return NewsProject(
      id: 'project_${DateTime.now().millisecondsSinceEpoch}',
      presetId: presetId,
    );
  }

  /// Maximum clips in one project (Phase 9, [ExportLimits]): every
  /// clip becomes a full normalised intermediate MP4, so unbounded
  /// clips blow device temp storage.
  static const int maxClips = 20;

  bool get canAddClip => clipPaths.length < maxClips;

  /// Adds [picked] clip paths (skipping duplicates), capped at
  /// [maxClips]. Returns the new list plus how many picked paths
  /// were dropped by the cap — the picker shows that number instead
  /// of silently dropping clips.
  ({List<String> clips, int droppedByCap}) addClips(
    List<String> picked,
  ) {
    final next = List<String>.from(clipPaths);
    var dropped = 0;
    for (final path in picked) {
      if (next.contains(path)) continue;
      if (next.length >= maxClips) {
        dropped++;
        continue;
      }
      next.add(path);
    }
    return (clips: next, droppedByCap: dropped);
  }

  NewsProject copyWith({
    String? title,
    String? tehreer,
    GeminiVoice? voice,
    String? studioVoiceId,
    String? voiceoverPath,
    double? voiceoverDurationSec,
    List<String>? clipPaths,
    List<ClipTrim>? clipTrims,
    String? pipVideoPath,
    bool clearPipVideo = false,
    String? presetId,
    String? templateKind,
    String? breakingVariant,
    String? tickerText,
    String? englishTickerText,
    String? tickerLabel,
    String? reporterPhotoPath,
    bool clearReporterPhoto = false,
    String? reporterName,
    String? headlineFontId,
    String? tickerFontId,
    String? reporterFontId,
    String? headlineStyleId,
    String? tickerStyleId,
    String? transitionId,
    String? effectId,
    String? tickerDirection,
    String? videoTemplateId,
    String? backgroundMusicAsset,
    String? storeMusicPath,
    String? storeMusicName,
    bool clearStoreMusic = false,
    bool? voiceMusicEnabled,
    bool? musicDucking,
    double? tickerSpeed,
    bool? tickerLoop,
    String? captionTimingSource,
    String? captionAlignedHash,
    String? headline,
    String? summary,
    List<SubtitleLine>? subtitles,
    bool? breaking,
    List<NewsSource>? sources,
    SeoData? seo,
    String? captionStyleId,
    CaptionPosition? captionPosition,
    CaptionSize? captionSize,
    int? captionHighlight,
    String? captionFontId,
    bool? captionOutline,
    bool? captionShadow,
    bool? captionBackground,
    bool? captionDualLanguage,
    Map<String, ElementOverride>? elementOverrides,
    double? voiceSpeed,
    double? voicePauseSec,
    bool? voiceMusic,
  }) {
    return NewsProject(
      id: id,
      title: title ?? this.title,
      tehreer: tehreer ?? this.tehreer,
      voice: voice ?? this.voice,
      studioVoiceId: studioVoiceId ?? this.studioVoiceId,
      voiceoverPath: voiceoverPath ?? this.voiceoverPath,
      voiceoverDurationSec:
          voiceoverDurationSec ?? this.voiceoverDurationSec,
      clipPaths: clipPaths ?? List<String>.from(this.clipPaths),
      clipTrims: clipTrims ??
          (clipPaths == null
              ? List<ClipTrim>.from(this.clipTrims)
              : reconcileClipTrims(
                  oldPaths: this.clipPaths,
                  oldTrims: this.clipTrims,
                  newPaths: clipPaths,
                )),
      pipVideoPath:
          clearPipVideo ? null : (pipVideoPath ?? this.pipVideoPath),
      presetId: presetId ?? this.presetId,
      templateKind: templateKind ?? this.templateKind,
      breakingVariant: breakingVariant ?? this.breakingVariant,
      tickerText: tickerText ?? this.tickerText,
      englishTickerText: englishTickerText ?? this.englishTickerText,
      tickerLabel: tickerLabel ?? this.tickerLabel,
      reporterPhotoPath:
          clearReporterPhoto ? null : (reporterPhotoPath ?? this.reporterPhotoPath),
      reporterName: reporterName ?? this.reporterName,
      headlineFontId: headlineFontId ?? this.headlineFontId,
      tickerFontId: tickerFontId ?? this.tickerFontId,
      reporterFontId: reporterFontId ?? this.reporterFontId,
      headlineStyleId: headlineStyleId ?? this.headlineStyleId,
      tickerStyleId: tickerStyleId ?? this.tickerStyleId,
      transitionId: transitionId ?? this.transitionId,
      effectId: effectId ?? this.effectId,
      tickerDirection: tickerDirection ?? this.tickerDirection,
      videoTemplateId: videoTemplateId ?? this.videoTemplateId,
      backgroundMusicAsset:
          backgroundMusicAsset ?? this.backgroundMusicAsset,
      storeMusicPath:
          clearStoreMusic ? null : (storeMusicPath ?? this.storeMusicPath),
      storeMusicName:
          clearStoreMusic ? null : (storeMusicName ?? this.storeMusicName),
      voiceMusicEnabled: voiceMusicEnabled ?? this.voiceMusicEnabled,
      musicDucking: musicDucking ?? this.musicDucking,
      tickerSpeed: tickerSpeed ?? this.tickerSpeed,
      tickerLoop: tickerLoop ?? this.tickerLoop,
      captionTimingSource: captionTimingSource ?? this.captionTimingSource,
      captionAlignedHash: captionAlignedHash ?? this.captionAlignedHash,
      headline: headline ?? this.headline,
      summary: summary ?? this.summary,
      subtitles: subtitles ?? List<SubtitleLine>.from(this.subtitles),
      breaking: breaking ?? this.breaking,
      sources: sources ?? List<NewsSource>.from(this.sources),
      seo: seo ?? this.seo,
      captionStyleId: captionStyleId ?? this.captionStyleId,
      captionPosition: captionPosition ?? this.captionPosition,
      captionSize: captionSize ?? this.captionSize,
      captionHighlight: captionHighlight ?? this.captionHighlight,
      captionFontId: captionFontId ?? this.captionFontId,
      captionOutline: captionOutline ?? this.captionOutline,
      captionShadow: captionShadow ?? this.captionShadow,
      captionBackground: captionBackground ?? this.captionBackground,
      captionDualLanguage: captionDualLanguage ?? this.captionDualLanguage,
      elementOverrides: elementOverrides ??
          Map<String, ElementOverride>.from(this.elementOverrides),
      voiceSpeed: voiceSpeed ?? this.voiceSpeed,
      voicePauseSec: voicePauseSec ?? this.voicePauseSec,
      voiceMusic: voiceMusic ?? this.voiceMusic,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'tehreer': tehreer,
        'voice': voice.apiName,
        'studioVoiceId': studioVoiceId,
        'elementOverrides': elementOverrides.map(
          (k, v) => MapEntry(k, v.toJson()),
        ),
        'voiceoverPath': voiceoverPath,
        'voiceoverDurationSec': voiceoverDurationSec,
        'clipPaths': clipPaths,
        'clipTrims': clipTrims.map((t) => t.toJson()).toList(),
        'pipVideoPath': pipVideoPath,
        'presetId': presetId,
        'templateKind': templateKind,
        'breakingVariant': breakingVariant,
        'tickerText': tickerText,
        'englishTickerText': englishTickerText,
        'tickerLabel': tickerLabel,
        'reporterPhotoPath': reporterPhotoPath,
        'reporterName': reporterName,
        'headlineFontId': headlineFontId,
        'tickerFontId': tickerFontId,
        'reporterFontId': reporterFontId,
        'headlineStyleId': headlineStyleId,
        'tickerStyleId': tickerStyleId,
        'transitionId': transitionId,
        'effectId': effectId,
        'tickerDirection': tickerDirection,
        'videoTemplateId': videoTemplateId,
        'backgroundMusicAsset': backgroundMusicAsset,
        'storeMusicPath': storeMusicPath,
        'storeMusicName': storeMusicName,
        'voiceMusicEnabled': voiceMusicEnabled,
        'musicDucking': musicDucking,
        'tickerSpeed': tickerSpeed,
        'tickerLoop': tickerLoop,
        'captionTimingSource': captionTimingSource,
        'captionAlignedHash': captionAlignedHash,
        'headline': headline,
        'summary': summary,
        'subtitles': subtitles.map((s) => s.toJson()).toList(),
        'breaking': breaking,
        'sources': sources.map((s) => s.toJson()).toList(),
        'seo': seo.toJson(),
        'captionStyleId': captionStyleId,
        'captionPosition': captionPosition.name,
        'captionSize': captionSize.name,
        'captionHighlight': captionHighlight,
        'captionFontId': captionFontId,
        'captionOutline': captionOutline,
        'captionShadow': captionShadow,
        'captionBackground': captionBackground,
        'captionDualLanguage': captionDualLanguage,
        'voiceSpeed': voiceSpeed,
        'voicePauseSec': voicePauseSec,
        'voiceMusic': voiceMusic,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static NewsProject fromJson(Map<String, dynamic> json) {
    final voiceName = (json['voice'] as String?) ?? 'Aoede';
    final voice = GeminiVoice.values.firstWhere(
      (v) => v.apiName == voiceName,
      orElse: () => GeminiVoice.aoede,
    );
    final rawClips = json['clipPaths'];
    final clips = <String>[];
    if (rawClips is List) {
      for (final c in rawClips) {
        if (c is String) clips.add(c);
      }
    }
    // P1-3: per-clip trims — absent on pre-trim saves (the
    // constructor normalises to full ranges); malformed entries
    // fall back to the full range for that clip only.
    final rawTrims = json['clipTrims'];
    final trims = <ClipTrim>[];
    if (rawTrims is List) {
      for (final t in rawTrims) {
        trims.add(
          t is Map<String, dynamic> ? ClipTrim.fromJson(t) : ClipTrim.full,
        );
      }
    }
    final rawSubs = json['subtitles'];
    final subs = <SubtitleLine>[];
    if (rawSubs is List) {
      for (final s in rawSubs) {
        if (s is Map<String, dynamic>) {
          subs.add(SubtitleLine.fromJson(s));
        }
      }
    }
    final rawSources = json['sources'];
    final srcs = <NewsSource>[];
    if (rawSources is List) {
      for (final s in rawSources) {
        if (s is Map<String, dynamic>) {
          srcs.add(NewsSource.fromJson(s));
        }
      }
    }
    final rawOverrides = json['elementOverrides'];
    final overrides = <String, ElementOverride>{};
    if (rawOverrides is Map<String, dynamic>) {
      for (final e in rawOverrides.entries) {
        if (e.value is Map<String, dynamic>) {
          overrides[e.key] = ElementOverride.fromJson(e.value);
        }
      }
    }
    final rawSeo = json['seo'];
    CaptionPosition captionPositionFrom(String? name) =>
        CaptionPosition.values.firstWhere(
          (v) => v.name == name,
          orElse: () => CaptionPosition.bottom,
        );
    CaptionSize captionSizeFrom(String? name) =>
        CaptionSize.values.firstWhere(
          (v) => v.name == name,
          orElse: () => CaptionSize.medium,
        );
    return NewsProject(
      id: (json['id'] as String?) ?? 'project_unknown',
      title: (json['title'] as String?) ?? '',
      tehreer: (json['tehreer'] as String?) ?? '',
      voice: voice,
      studioVoiceId: (json['studioVoiceId'] as String?) ?? '',
      elementOverrides: overrides,
      voiceoverPath: json['voiceoverPath'] as String?,
      voiceoverDurationSec:
          (json['voiceoverDurationSec'] as num?)?.toDouble(),
      clipPaths: clips,
      clipTrims: trims,
      pipVideoPath: json['pipVideoPath'] as String?,
      presetId: (json['presetId'] as String?) ?? 'nigraan-tv',
      templateKind: (json['templateKind'] as String?) ?? 'nigraanFinal',
      breakingVariant:
          (json['breakingVariant'] as String?) ?? 'breakingRedBanner',
      tickerText: (json['tickerText'] as String?) ?? '',
      englishTickerText: (json['englishTickerText'] as String?) ?? '',
      tickerLabel: (json['tickerLabel'] as String?) ?? 'BREAKING NEWS',
      reporterPhotoPath: json['reporterPhotoPath'] as String?,
      reporterName: (json['reporterName'] as String?) ?? '',
      headlineFontId:
          (json['headlineFontId'] as String?) ?? 'jameel_kasheeda',
      tickerFontId: (json['tickerFontId'] as String?) ?? 'jameel_kasheeda',
      reporterFontId:
          (json['reporterFontId'] as String?) ?? 'jameel_kasheeda',
      headlineStyleId: (json['headlineStyleId'] as String?) ?? '',
      tickerStyleId: (json['tickerStyleId'] as String?) ?? '',
      transitionId: (json['transitionId'] as String?) ?? '',
      effectId: (json['effectId'] as String?) ?? '',
      tickerDirection: json['tickerDirection'] as String?,
      videoTemplateId: (json['videoTemplateId'] as String?) ?? '',
      backgroundMusicAsset: json['backgroundMusicAsset'] as String?,
      storeMusicPath: json['storeMusicPath'] as String?,
      storeMusicName: json['storeMusicName'] as String?,
      // Absent on pre-v1.9.0 saves → ON (the historic behaviour:
      // a selected track always bedded under the voice).
      voiceMusicEnabled: (json['voiceMusicEnabled'] as bool?) ?? true,
      // Build 13: absent on pre-v1.10.0 saves → defaults (ducking
      // ON, designed ticker speed, looping ticker, estimator
      // timings — exactly the historic behaviour).
      musicDucking: (json['musicDucking'] as bool?) ?? true,
      tickerSpeed: (json['tickerSpeed'] as num?)?.toDouble() ?? 1.0,
      tickerLoop: (json['tickerLoop'] as bool?) ?? true,
      captionTimingSource:
          (json['captionTimingSource'] as String?) ?? 'estimate',
      captionAlignedHash: (json['captionAlignedHash'] as String?) ?? '',
      headline: (json['headline'] as String?) ?? '',
      summary: (json['summary'] as String?) ?? '',
      subtitles: subs,
      breaking: (json['breaking'] as bool?) ?? false,
      sources: srcs,
      seo: rawSeo is Map<String, dynamic>
          ? SeoData.fromJson(rawSeo)
          : SeoData(),
      captionStyleId: (json['captionStyleId'] as String?) ?? 'nigraan',
      captionPosition:
          captionPositionFrom(json['captionPosition'] as String?),
      captionSize: captionSizeFrom(json['captionSize'] as String?),
      captionHighlight: (json['captionHighlight'] as num?)?.toInt(),
      captionFontId: (json['captionFontId'] as String?) ?? 'jameel_kasheeda',
      captionOutline: (json['captionOutline'] as bool?) ?? true,
      captionShadow: (json['captionShadow'] as bool?) ?? false,
      captionBackground: (json['captionBackground'] as bool?) ?? false,
      captionDualLanguage: (json['captionDualLanguage'] as bool?) ?? false,
      voiceSpeed: (json['voiceSpeed'] as num?)?.toDouble() ?? 1.0,
      voicePauseSec: (json['voicePauseSec'] as num?)?.toDouble() ?? 0.0,
      voiceMusic: (json['voiceMusic'] as bool?) ?? false,
      createdAt: DateTime.tryParse(
            (json['createdAt'] as String?) ?? '',
          ) ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(
            (json['updatedAt'] as String?) ?? '',
          ) ??
          DateTime.now(),
    );
  }
}

/// JSON store for news projects (same fail-soft pattern as the
/// preset/template stores: a failed save never blocks editing).
class NewsProjectStore {
  static const _dirName = 'news_projects';

  static Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, _dirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Saves [project] (updates its `updatedAt` first). Returns the
  /// saved project.
  static Future<NewsProject> save(NewsProject project) async {
    project.updatedAt = DateTime.now();
    try {
      final dir = await _dir();
      final file = File(p.join(dir.path, '${project.id}.json'));
      await file.writeAsString(jsonEncode(project.toJson()));
    } catch (_) {
      // A failed save must never block editing — the in-memory
      // project keeps working and the next save retries.
    }
    return project;
  }

  static Future<NewsProject?> load(String id) async {
    try {
      final dir = await _dir();
      final file = File(p.join(dir.path, '$id.json'));
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString());
      if (data is Map<String, dynamic>) {
        return NewsProject.fromJson(data);
      }
    } catch (_) {}
    return null;
  }

  /// All saved projects, newest first. Corrupt files are skipped.
  static Future<List<NewsProject>> loadAll() async {
    final projects = <NewsProject>[];
    try {
      final dir = await _dir();
      await for (final entry in dir.list()) {
        if (entry is! File || !entry.path.endsWith('.json')) continue;
        try {
          final data = jsonDecode(await entry.readAsString());
          if (data is Map<String, dynamic>) {
            projects.add(NewsProject.fromJson(data));
          }
        } catch (_) {
          // One corrupt project file must not hide the rest.
        }
      }
    } catch (_) {}
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  /// The most recently saved project, or null when none exists.
  static Future<NewsProject?> loadLatest() async {
    final all = await loadAll();
    return all.isEmpty ? null : all.first;
  }

  static Future<void> delete(String id) async {
    try {
      final dir = await _dir();
      final file = File(p.join(dir.path, '$id.json'));
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

// ---------------------------------------------------------------------------
// WAV duration (RIFF header parse, no player needed).
// ---------------------------------------------------------------------------

int _u32(ByteData data, int offset) =>
    data.getUint32(offset, Endian.little);

String _fourCC(ByteData data, int offset) => String.fromCharCodes(
      data.buffer.asUint8List(offset, 4),
    );

/// Duration of a WAV file in seconds, or null when the file is not a
/// parseable WAV. Reads only the header (first 8 KB) — the `fmt ` chunk
/// gives the byte rate, the `data` chunk gives the size.
double? wavDurationSeconds(File file) {
  try {
    final bytes = file.readAsBytesSync();
    return wavDurationFromBytes(bytes);
  } catch (_) {
    return null;
  }
}

/// Same parse, from bytes (test seam — no file I/O).
double? wavDurationFromBytes(List<int> bytes) {
  try {
    if (bytes.length < 44) return null;
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    if (_fourCC(data, 0) != 'RIFF') return null;
    if (_fourCC(data, 8) != 'WAVE') return null;
    var offset = 12;
    int? byteRate;
    int? dataSize;
    while (offset + 8 <= bytes.length && offset + 8 <= 8192) {
      final chunkId = _fourCC(data, offset);
      final chunkSize = _u32(data, offset + 4);
      final chunkStart = offset + 8;
      if (chunkId == 'fmt ' && chunkSize >= 16) {
        // byteRate sits 8 bytes into the fmt chunk.
        byteRate = _u32(data, chunkStart + 8);
      } else if (chunkId == 'data') {
        dataSize = chunkSize;
        break;
      }
      offset = chunkStart + chunkSize + (chunkSize % 2);
    }
    if (byteRate == null || byteRate <= 0 || dataSize == null) {
      return null;
    }
    return dataSize / byteRate;
  } catch (_) {
    return null;
  }
}
