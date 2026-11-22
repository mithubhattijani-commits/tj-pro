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
    this.presetId = 'nigraan-tv',
    this.templateKind = 'nigraanFinal',
    this.breakingVariant = 'breakingRedBanner',
    this.tickerText = '',
    this.tickerDirection,
    this.videoTemplateId = '',
    this.backgroundMusicAsset,
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
    String? presetId,
    String? templateKind,
    String? breakingVariant,
    String? tickerText,
    String? tickerDirection,
    String? videoTemplateId,
    String? backgroundMusicAsset,
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
      presetId: presetId ?? this.presetId,
      templateKind: templateKind ?? this.templateKind,
      breakingVariant: breakingVariant ?? this.breakingVariant,
      tickerText: tickerText ?? this.tickerText,
      tickerDirection: tickerDirection ?? this.tickerDirection,
      videoTemplateId: videoTemplateId ?? this.videoTemplateId,
      backgroundMusicAsset:
          backgroundMusicAsset ?? this.backgroundMusicAsset,
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
        'presetId': presetId,
        'templateKind': templateKind,
        'breakingVariant': breakingVariant,
        'tickerText': tickerText,
        'tickerDirection': tickerDirection,
        'videoTemplateId': videoTemplateId,
        'backgroundMusicAsset': backgroundMusicAsset,
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
      presetId: (json['presetId'] as String?) ?? 'nigraan-tv',
      templateKind: (json['templateKind'] as String?) ?? 'nigraanFinal',
      breakingVariant:
          (json['breakingVariant'] as String?) ?? 'breakingRedBanner',
      tickerText: (json['tickerText'] as String?) ?? '',
      tickerDirection: json['tickerDirection'] as String?,
      videoTemplateId: (json['videoTemplateId'] as String?) ?? '',
      backgroundMusicAsset: json['backgroundMusicAsset'] as String?,
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
