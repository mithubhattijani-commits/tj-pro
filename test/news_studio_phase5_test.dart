// Phase 5 unit tests: Magic Box caption + TTS port, karaoke sync,
// burn-in, audio tools, TTS Studio service.
//
// Plain unit tests only (real async, real dart:io where needed — the
// Phase 4 note applies: widget-test pumps never flush dart:io work,
// so persistence is covered here, not in widget tests). No proxy
// calls, no ffmpeg runs, no quota used anywhere here.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/news/caption_editor.dart';
import 'package:tj_pro/news/karaoke_sync.dart';
import 'package:tj_pro/news/news_analysis.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/services/audio_tools_service.dart';
import 'package:tj_pro/services/caption_draft_service.dart';
import 'package:tj_pro/services/caption_service.dart';
import 'package:tj_pro/services/caption_styles.dart';
import 'package:tj_pro/services/gemini_voice_service.dart';
import 'package:tj_pro/services/mp3_utils.dart';
import 'package:tj_pro/services/tts_history_service.dart';
import 'package:tj_pro/services/tts_processing.dart';
import 'package:tj_pro/services/tts_studio_service.dart';
import 'package:tj_pro/services/video_export_service.dart';
import 'package:tj_pro/services/wav_utils.dart';

/// Builds a minimal WAV in memory: 16-bit mono, [sampleRate] Hz,
/// [seconds] long, silence. Same builder as the Phase 4 test file.
Uint8List makeWav({int sampleRate = 24000, double seconds = 3}) {
  final frames = (sampleRate * seconds).round();
  return encodeWav(
    sampleRate: sampleRate,
    channels: 1,
    bitsPerSample: 16,
    pcm: Uint8List(frames * 2),
  );
}

/// Builds [count] valid MP3 frames in memory (MPEG-1 Layer III,
/// 128 kbps, 44.1 kHz, no padding): each frame is 417 bytes and
/// 1152/44100 s long.
Uint8List makeMp3({int frames = 10}) {
  const frameLen = 417; // 144 * 128000 / 44100
  final out = BytesBuilder();
  for (var i = 0; i < frames; i++) {
    final frame = Uint8List(frameLen);
    frame[0] = 0xFF;
    frame[1] = 0xFB; // MPEG-1, Layer III, no CRC
    frame[2] = 0x90; // 128 kbps, 44100 Hz
    frame[3] = 0x00;
    out.add(frame);
  }
  return out.takeBytes();
}

const String tehreer =
    'شیخوپورہ میں پولیس نے بڑی کارروائی کی۔ بھاری مقدار میں شراب برآمد ہوئی۔ ملزم گرفتار ہو گیا۔';

void main() {
  // -----------------------------------------------------------------
  // 1. Caption styles (11 styles, presets, fonts, colours).
  // -----------------------------------------------------------------
  group('Caption styles (Magic Box port)', () {
    test('11 styles, nigraan first = default, green spoken word', () {
      expect(StudioCaptionStyles.all.length, 11);
      final first = StudioCaptionStyles.all.first;
      expect(first.id, 'nigraan');
      expect(first.nameEn, 'Nigraan Karaoke');
      expect(first.animation, CaptionAnimation.karaoke);
      expect(first.highlightColor, StudioCaptionStyles.green);
      expect(first.highlightColor, 0xFF3AEC70);
      expect(first.position, CaptionPosition.bottom);
      expect(StudioCaptionStyles.byId('nigraan'), first);
      // Unknown id falls back to the default, never throws.
      expect(StudioCaptionStyles.byId('nope'), first);
    });

    test('all 11 ids in picker order, last is minimal', () {
      expect(
        StudioCaptionStyles.all.map((s) => s.id).toList(),
        [
          'nigraan',
          'bold_pop',
          'pop_up',
          'karaoke_fill',
          'highlight_box',
          'typewriter',
          'one_word',
          'classic',
          'news_ticker',
          'spotlight',
          'minimal',
        ],
      );
      expect(StudioCaptionStyles.all.last.nameEn, 'Minimal');
    });

    test('highlight choices are the 6 documented colours', () {
      expect(StudioCaptionStyles.highlightChoices, [
        0xFF3AEC70,
        0xFFFFD60A,
        0xFFFFFFFF,
        0xFF00E5FF,
        0xFFEF0017,
        0xFF3D5AFE,
      ]);
    });

    test('3 one-tap presets, Nigraan News = house look', () {
      expect(CaptionPresets.all.length, 3);
      final nigraan = CaptionPresets.nigraanNews;
      expect(nigraan.styleId, 'nigraan');
      expect(nigraan.fontId, 'jameel_kasheeda');
      expect(nigraan.highlightColor, StudioCaptionStyles.green);
      expect(nigraan.position, CaptionPosition.bottom);
      expect(CaptionPresets.byId('tiktok_bold').styleId, 'bold_pop');
      expect(CaptionPresets.byId('clean').styleId, 'classic');
    });

    test('6 fonts, Urdu gets Jameel first, English gets display fonts', () {
      expect(CaptionFonts.all.length, 6);
      expect(CaptionFonts.forLang('ur').first.id, 'jameel_kasheeda');
      expect(CaptionFonts.forLang('ur').length, 2);
      expect(
        CaptionFonts.forLang('en').map((f) => f.id).toList(),
        ['system', 'bebas', 'anton', 'montserrat', 'poppins'],
      );
      expect(CaptionFonts.byId('nope'), CaptionFonts.system);
    });

    test('size scale S/M/L = 0.8/1.0/1.3; ASS colour AABBGGRR', () {
      expect(StudioCaptionStyles.sizeScale(CaptionSize.small), 0.8);
      expect(StudioCaptionStyles.sizeScale(CaptionSize.medium), 1.0);
      expect(StudioCaptionStyles.sizeScale(CaptionSize.large), 1.3);
      // Green #3AEC70, opaque -> &H0070EC3A (AABBGGRR).
      expect(StudioCaptionStyles.assColor(0xFF3AEC70), '&H0070EC3A');
      // 50% white -> alpha 0x80 inverts to 0x7F.
      expect(StudioCaptionStyles.assColor(0x80FFFFFF), '&H7FFFFFFF');
      expect(StudioCaptionStyles.assAlignment(CaptionPosition.top), 8);
      expect(StudioCaptionStyles.assAlignment(CaptionPosition.middle), 5);
      expect(StudioCaptionStyles.assAlignment(CaptionPosition.bottom), 2);
    });

    test('even-split word timing: active word + start/end', () {
      const text = 'one two three four';
      expect(
        StudioCaptionStyles.activeWordIndex(
          start: 0,
          end: 4,
          text: text,
          positionSeconds: 2.5,
        ),
        2,
      );
      expect(
        StudioCaptionStyles.activeWordIndex(
          start: 0,
          end: 4,
          text: text,
          positionSeconds: -1,
        ),
        -1,
      );
      expect(
        StudioCaptionStyles.wordStart(
          start: 0,
          end: 4,
          text: text,
          index: 1,
        ),
        1.0,
      );
      expect(
        StudioCaptionStyles.wordEnd(
          start: 0,
          end: 4,
          text: text,
          index: 1,
        ),
        2.0,
      );
    });
  });

  // -----------------------------------------------------------------
  // 2. WAV utils (pure Dart).
  // -----------------------------------------------------------------
  group('WAV utils', () {
    test('encode -> parse round-trip keeps format + duration', () {
      final bytes = makeWav(seconds: 3);
      final wav = parseWav(bytes)!;
      expect(wav.sampleRate, 24000);
      expect(wav.channels, 1);
      expect(wav.bitsPerSample, 16);
      expect(wav.durationSeconds, closeTo(3.0, 0.001));
      expect(wav.frameCount, 24000 * 3);
    });

    test('garbage bytes return null, never throw', () {
      expect(parseWav(Uint8List.fromList([1, 2, 3, 4])), isNull);
      expect(parseWav(Uint8List(0)), isNull);
    });

    test('resample 2.0x halves the duration (pitch changes too)', () {
      final bytes = makeWav(seconds: 4);
      final fast = resampleWav(bytes, 2.0);
      expect(parseWav(fast)!.durationSeconds, closeTo(2.0, 0.01));
      final slow = resampleWav(bytes, 0.5);
      expect(parseWav(slow)!.durationSeconds, closeTo(8.0, 0.01));
      expect(() => resampleWav(bytes, 0), throwsException);
    });

    test('insertSilence adds exactly the requested silence', () {
      final bytes = makeWav(seconds: 2);
      final withPause = insertSilenceWav(bytes, [1.0], 0.5);
      expect(
        parseWav(withPause)!.durationSeconds,
        closeTo(2.5, 0.01),
      );
      // No boundaries / zero silence = same bytes back.
      expect(insertSilenceWav(bytes, [], 0.5), bytes);
    });

    test('slice + concat round-trip', () {
      final bytes = makeWav(seconds: 4);
      final slice = sliceWav(bytes, 1.0, 3.0);
      expect(parseWav(slice)!.durationSeconds, closeTo(2.0, 0.01));
      final joined = concatWav([slice, slice]);
      expect(parseWav(joined)!.durationSeconds, closeTo(4.0, 0.01));
      expect(
        () => concatWav([
          bytes,
          makeWav(sampleRate: 16000, seconds: 1),
        ]),
        throwsException,
      );
    });
  });

  // -----------------------------------------------------------------
  // 3. MP3 utils (pure Dart).
  // -----------------------------------------------------------------
  group('MP3 utils', () {
    test('synthetic frames parse to the right duration', () {
      final bytes = makeMp3(frames: 10);
      expect(mp3DurationSeconds(bytes), closeTo(10 * 1152 / 44100, 0.01));
      expect(parseMp3(bytes).frameCount, 10);
    });

    test('garbage throws, trim keeps whole frames in range', () {
      expect(
        () => mp3DurationSeconds(Uint8List.fromList([1, 2, 3, 4])),
        throwsException,
      );
      final bytes = makeMp3(frames: 10);
      final total = mp3DurationSeconds(bytes);
      final trimmed = trimMp3(bytes, 0.0, total / 2);
      final trimmedDur = mp3DurationSeconds(trimmed);
      expect(trimmedDur, greaterThan(0));
      expect(trimmedDur, lessThanOrEqualTo(total / 2 + 0.03));
      expect(() => trimMp3(bytes, 5.0, 6.0), throwsException);
    });

    test('concat joins MP3 files', () {
      final joined = concatMp3([makeMp3(frames: 4), makeMp3(frames: 6)]);
      expect(mp3DurationSeconds(joined), closeTo(10 * 1152 / 44100, 0.01));
    });
  });

  // -----------------------------------------------------------------
  // 4. TTS processing (controls, pad, formats).
  // -----------------------------------------------------------------
  group('TTS processing', () {
    test('TtsControls: default, cache suffix, tone presets', () {
      const def = TtsControls();
      expect(def.isDefault, isTrue);
      expect(def.cacheSuffix, '');
      const fast = TtsControls(speed: 1.25, pauseSeconds: 0.5);
      expect(fast.isDefault, isFalse);
      expect(fast.cacheSuffix, '|s1.25|p0.5');
      expect(TtsStudioService.tonePresets['News']!.speed, 1.0);
      expect(TtsStudioService.tonePresets['News']!.pauseSeconds, 0.2);
      expect(TtsStudioService.tonePresets['Story']!.speed, 0.9);
      expect(TtsStudioService.tonePresets['Story']!.pauseSeconds, 0.5);
      expect(TtsStudioService.tonePresets['Ad']!.speed, 1.15);
      expect(TtsStudioService.tonePresets['Ad']!.pauseSeconds, 0.1);
    });

    test('sentence boundaries split on Urdu + Latin punctuation', () {
      expect(sentenceBoundaries('Hello world. How are you? Fine!'), [13, 26]);
      expect(sentenceBoundaries('پہلا جملہ۔ دوسرا جملہ۔'), [11]);
      expect(sentenceBoundaries('No punctuation here'), isEmpty);
    });

    test('applyTtsControls: speed halves duration, pause adds silence', () {
      final bytes = makeWav(seconds: 4);
      final fast = applyTtsControls(
        bytes,
        text: 'one two three four',
        controls: const TtsControls(speed: 2.0),
      );
      expect(parseWav(fast)!.durationSeconds, closeTo(2.0, 0.01));
      final paused = applyTtsControls(
        bytes,
        text: 'First sentence. Second sentence.',
        controls: const TtsControls(pauseSeconds: 0.5),
      );
      expect(
        parseWav(paused)!.durationSeconds,
        closeTo(4.5, 0.05),
      );
      // Default controls return the same bytes.
      final same = applyTtsControls(bytes, text: 'x', controls: const TtsControls());
      expect(same, bytes);
    });

    test('ambient pad generates a parseable WAV of the right length', () {
      final pad = generateAmbientPadWav(durationSeconds: 2.0);
      final wav = parseWav(pad)!;
      expect(wav.durationSeconds, closeTo(2.0, 0.01));
      expect(wav.sampleRate, 24000);
      final mixed = mixWavWithMusic(makeWav(seconds: 2));
      expect(parseWav(mixed)!.durationSeconds, closeTo(2.0, 0.01));
    });

    test('duration/size/duration-label helpers', () {
      expect(audioDurationSeconds(makeWav(seconds: 3), 'wav'), closeTo(3.0, 0.01));
      expect(audioDurationSeconds(makeMp3(frames: 10), 'mp3'), closeTo(10 * 1152 / 44100, 0.01));
      expect(audioDurationSeconds(Uint8List.fromList([1, 2]), 'wav'), 0);
      expect(formatAudioSize(500), '500 B');
      expect(formatAudioSize(2048), '2 KB');
      expect(formatAudioSize(1536 * 1024), '1.5 MB');
      expect(formatDuration(42), '00:42');
      expect(formatDuration(125), '02:05');
    });
  });

  // -----------------------------------------------------------------
  // 5. Karaoke sync (real WAV duration, not the word-count guess).
  // -----------------------------------------------------------------
  group('Karaoke sync', () {
    test('lines span exactly the voiceover duration, contiguous', () {
      final lines = syncSubtitlesToVoiceover(tehreer, 12.0);
      expect(lines.length, greaterThan(1));
      expect(lines.first.startSec, 0.0);
      expect(lines.last.endSec, 12.0);
      for (var i = 0; i < lines.length; i++) {
        expect(lines[i].endSec, greaterThan(lines[i].startSec));
        if (i > 0) expect(lines[i].startSec, lines[i - 1].endSec);
        expect(lines[i].words, isNotEmpty);
        // Words fill the line window exactly.
        expect(lines[i].words.first.startSec, lines[i].startSec);
        expect(lines[i].words.last.endSec, lines[i].endSec);
      }
    });

    test('longer words get longer timings than short ones', () {
      final lines = syncSubtitlesToVoiceover('ا ب', 2.0);
      expect(lines.length, 1);
      final words = lines.first.words;
      expect(words.length, 2);
      // 'ا' is 1 char, 'ب' is 1 char — equal; use a clearer case:
      final lines2 = syncSubtitlesToVoiceover('a verylongword', 3.0);
      final w2 = lines2.first.words;
      expect(w2[1].endSec - w2[1].startSec,
          greaterThan(w2[0].endSec - w2[0].startSec));
    });

    test('empty text / non-positive duration gives no lines', () {
      expect(syncSubtitlesToVoiceover('', 10.0), isEmpty);
      expect(syncSubtitlesToVoiceover(tehreer, 0), isEmpty);
      expect(syncSubtitlesToVoiceover(tehreer, -5), isEmpty);
    });

    test('resync keeps translations and re-times edited text', () {
      final original = syncSubtitlesToVoiceover(tehreer, 12.0);
      final edited = [
        SubtitleLine(
          text: '${original.first.text} نیا لفظ',
          startSec: 0,
          endSec: 1,
          translation: 'Edited line translation',
        ),
        ...original.skip(1),
      ];
      final resynced = resyncExistingLines(edited, 20.0);
      expect(resynced.first.translation, 'Edited line translation');
      expect(resynced.last.endSec, 20.0);
      expect(resynced.first.words, isNotEmpty);
    });

    test('active word + line lookup use real word timings', () {
      final lines = syncSubtitlesToVoiceover(tehreer, 12.0);
      final line = lines.first;
      final midWord = line.words[1];
      final mid = (midWord.startSec + midWord.endSec) / 2;
      expect(activeWordIndexInLine(line, mid), 1);
      expect(activeWordIndexInLine(line, -1), -1);
      expect(subtitleLineAt(lines, 0.0), 0);
      expect(subtitleLineAt(lines, 11.99), lines.length - 1);
      expect(subtitleLineAt(lines, 99.0), -1);
    });
  });

  // -----------------------------------------------------------------
  // 6. Caption exports + styled ASS + SRT parse.
  // -----------------------------------------------------------------
  group('Caption exports', () {
    final segments = [
      CaptionSegment(
        'شیخوپورہ میں پولیس',
        0.0,
        2.0,
        words: const [
          CaptionWord(word: 'شیخوپورہ', start: 0.0, end: 0.8),
          CaptionWord(word: 'میں', start: 0.8, end: 1.1),
          CaptionWord(word: 'پولیس', start: 1.1, end: 2.0),
        ],
        translation: 'Police in Sheikhupura',
      ),
      CaptionSegment('بڑی کارروائی', 2.0, 3.5),
    ];

    test('SRT exact shape + dual language + VTT + TXT', () {
      final srt = CaptionService.buildSrt(segments);
      expect(
        srt,
        '1\n00:00:00,000 --> 00:00:02,000\nشیخوپورہ میں پولیس\n\n'
        '2\n00:00:02,000 --> 00:00:03,500\nبڑی کارروائی\n\n',
      );
      final dual = CaptionService.buildSrt(segments, dualLanguage: true);
      expect(dual, contains('Police in Sheikhupura'));
      final vtt = CaptionService.buildVtt(segments);
      expect(vtt.startsWith('WEBVTT\n\n'), isTrue);
      expect(vtt, contains('00:00:00.000 --> 00:00:02.000'));
      expect(
        CaptionService.buildTxt(segments),
        'شیخوپورہ میں پولیس\nبڑی کارروائی',
      );
      expect(
        CaptionService.buildPlainText(segments, dualLanguage: true),
        contains('Police in Sheikhupura'),
      );
    });

    test('SRT round-trips through parseSrt', () {
      final srt = CaptionService.buildSrt(segments);
      final parsed = CaptionService.parseSrt(srt);
      expect(parsed.length, 2);
      expect(parsed[0].text, 'شیخوپورہ میں پولیس');
      expect(parsed[0].start, 0.0);
      expect(parsed[0].end, 2.0);
      expect(parsed[1].end, 3.5);
      // Malformed input never throws, just skips bad blocks.
      expect(CaptionService.parseSrt('not an srt at all'), isEmpty);
      expect(CaptionService.parseSrt(''), isEmpty);
    });

    test('word timing prefers real timings, falls back to even split', () {
      final withWords = segments[0];
      expect(CaptionService.wordStartOf(withWords, 0), 0.0);
      expect(CaptionService.wordEndOf(withWords, 1), 1.1);
      expect(CaptionService.activeWordIndexOf(withWords, 0.9), 1);
      final noWords = segments[1];
      expect(CaptionService.wordStartOf(noWords, 0), 2.0);
      // Even split over 2 words in a 1.5s window: word 1 ends at 3.5.
      expect(CaptionService.wordEndOf(noWords, 1), 3.5);
      expect(CaptionService.wordEndOf(noWords, 0), closeTo(2.75, 0.01));
      expect(CaptionService.activeWordIndexOf(noWords, 2.2), 0);
    });

    test('styled ASS karaoke uses {\\kf} with REAL word durations', () {
      final style = StudioCaptionStyles.byId('nigraan');
      final ass = CaptionService.buildStyledAss(segments, style);
      expect(ass, contains('PlayResX: 1280'));
      expect(ass, contains('PlayResY: 720'));
      // Real word durations: 0.8s -> kf80, 0.3s -> kf30, 0.9s -> kf90.
      expect(ass, contains('{\\kf80}'));
      expect(ass, contains('{\\kf30}'));
      expect(ass, contains('{\\kf90}'));
      // Highlight = green secondary colour.
      expect(ass, contains(StudioCaptionStyles.assColor(0xFF3AEC70)));
      // One Dialogue for the karaoke line + one for the flash line.
      expect('Dialogue:'.allMatches(ass).length, 2);
    });

    test('styled ASS pop = one Dialogue per word; typewriter cumulative', () {
      final pop = CaptionService.buildStyledAss(
        segments,
        StudioCaptionStyles.byId('bold_pop'),
      );
      // 3 words in line 1 + 2 words in line 2 = 5 Dialogues.
      expect('Dialogue:'.allMatches(pop).length, 5);
      // Pop shows one word at a time — no Dialogue carries a full line.
      expect(pop, isNot(contains('شیخوپورہ میں پولیس')));
      final typewriter = CaptionService.buildStyledAss(
        segments,
        StudioCaptionStyles.byId('typewriter'),
      );
      expect('Dialogue:'.allMatches(typewriter).length, 5);
      // Cumulative: the last dialogue of line 1 shows all 3 words.
      expect(typewriter, contains('شیخوپورہ میں پولیس'));
      final flash = CaptionService.buildStyledAss(
        segments,
        StudioCaptionStyles.byId('classic'),
      );
      expect('Dialogue:'.allMatches(flash).length, 2);
    });

    test('styled ASS dual language + position + size scaling', () {
      final ass = CaptionService.buildStyledAss(
        segments,
        StudioCaptionStyles.byId('nigraan'),
        position: CaptionPosition.top,
        size: CaptionSize.large,
        playResX: 1080,
        playResY: 1920,
        dualLanguage: true,
      );
      expect(ass, contains('PlayResX: 1080'));
      expect(ass, contains('PlayResY: 1920'));
      // Top alignment = 8, and the dual style exists above the main.
      expect(ass, contains('TJProDual'));
      expect(ass, contains(',8,10,10,'));
      // Large (1.3x) on a 1920 canvas: 48 * 1.3 * (1920/720) = 166.
      expect(ass, contains('TJPro,Arial,166,'));
      // Dual font is 70% of the main size.
      expect(ass, contains('TJProDual,Arial,116,'));
    });

    test('styled ASS highlight override + custom font family', () {
      final ass = CaptionService.buildStyledAss(
        segments,
        StudioCaptionStyles.byId('nigraan'),
        highlightColor: 0xFFFFD60A,
        fontFamily: 'JameelNooriNastaleeqKasheeda',
      );
      expect(ass, contains(StudioCaptionStyles.assColor(0xFFFFD60A)));
      expect(ass, contains('JameelNooriNastaleeqKasheeda'));
    });
  });

  // -----------------------------------------------------------------
  // 7. Caption editor ops + undo/redo.
  // -----------------------------------------------------------------
  group('Caption editor', () {
    List<SubtitleLine> seed() => [
          SubtitleLine(text: 'one two three', startSec: 0, endSec: 3),
          SubtitleLine(text: 'four five', startSec: 3, endSec: 5),
        ];

    test('edit keeps window + translation, drops stale word timings', () {
      final editor = CaptionEditor([
        SubtitleLine(
          text: 'one two',
          startSec: 0,
          endSec: 2,
          words: [SubtitleWord(word: 'one', startSec: 0, endSec: 1)],
          translation: 'first line',
        ),
      ]);
      expect(editor.editLine(0, 'one two three'), isTrue);
      expect(editor.lines[0].text, 'one two three');
      expect(editor.lines[0].translation, 'first line');
      expect(editor.lines[0].words, isEmpty);
      expect(editor.editLine(0, '  '), isFalse);
      expect(editor.editLine(9, 'x'), isFalse);
    });

    test('delete + undo + redo round-trip', () {
      final editor = CaptionEditor(seed());
      expect(editor.deleteLine(0), isTrue);
      expect(editor.lines.length, 1);
      expect(editor.canUndo, isTrue);
      expect(editor.undo(), isTrue);
      expect(editor.lines.length, 2);
      expect(editor.canRedo, isTrue);
      expect(editor.redo(), isTrue);
      expect(editor.lines.length, 1);
      expect(editor.undo(), isTrue);
      expect(editor.undo(), isFalse);
    });

    test('split divides text + window proportionally', () {
      final editor = CaptionEditor(seed());
      expect(editor.splitLine(0, 0), isTrue);
      expect(editor.lines.length, 3);
      expect(editor.lines[0].text, 'one');
      expect(editor.lines[1].text, 'two three');
      expect(editor.lines[0].endSec, editor.lines[1].startSec);
      expect(editor.lines[0].endSec, closeTo(0.75, 0.01));
      expect(editor.splitLine(0, 5), isFalse);
    });

    test('merge joins text + window; shift/nudge clamp at 0', () {
      final editor = CaptionEditor(seed());
      expect(editor.mergeWithNext(0), isTrue);
      expect(editor.lines.length, 1);
      expect(editor.lines[0].text, 'one two three four five');
      expect(editor.lines[0].endSec, 5.0);
      expect(editor.mergeWithNext(0), isFalse);

      final editor2 = CaptionEditor(seed());
      editor2.shiftAll(0.5);
      expect(editor2.lines[0].startSec, 0.5);
      editor2.shiftAll(-2.0);
      expect(editor2.lines[0].startSec, 0.0);
      expect(editor2.nudgeLine(1, -10.0), isTrue);
      expect(editor2.lines[1].startSec, 0.0);
      expect(editor2.nudgeLine(9, 1.0), isFalse);
    });

    test('add manual line appends after the last line', () {
      final editor = CaptionEditor(seed());
      expect(editor.addManualLine('new line'), isTrue);
      expect(editor.lines.length, 3);
      expect(editor.lines[2].startSec, 5.0);
      expect(editor.lines[2].endSec, 7.0);
      expect(editor.addManualLine('  '), isFalse);
      expect(editor.setTranslation(2, 'English line'), isTrue);
      expect(editor.lines[2].translation, 'English line');
    });
  });

  // -----------------------------------------------------------------
  // 8. Draft store + history (file-based, temp dir seam).
  // -----------------------------------------------------------------
  group('Caption draft store + TTS history', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('tj_pro_phase5_');
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('draft save/load round-trip, clear removes it', () async {
      final store = CaptionDraftStore(directoryOverride: tmp);
      expect(await store.load('proj_1'), isNull);
      await store.save(
        'proj_1',
        CaptionDraft(
          lines: [
            SubtitleLine(text: 'hello world', startSec: 0, endSec: 2),
          ],
          styleId: 'bold_pop',
          position: CaptionPosition.middle,
          size: CaptionSize.large,
          highlightColor: 0xFFFFD60A,
          fontId: 'bebas',
          dualLanguage: true,
        ),
      );
      final loaded = await store.load('proj_1');
      expect(loaded, isNotNull);
      expect(loaded!.lines.first.text, 'hello world');
      expect(loaded.styleId, 'bold_pop');
      expect(loaded.position, CaptionPosition.middle);
      expect(loaded.size, CaptionSize.large);
      expect(loaded.highlightColor, 0xFFFFD60A);
      expect(loaded.dualLanguage, isTrue);
      await store.clear('proj_1');
      expect(await store.load('proj_1'), isNull);
    });

    test('history record/list/remove/clear + summary line', () async {
      final history = TtsHistoryService(directoryOverride: tmp);
      expect(await history.loadAll(), isEmpty);
      final entry = TtsHistoryEntry(
        id: 'h1',
        text: 'hello',
        voiceId: 'aoede',
        lang: 'ur',
        ext: 'wav',
        filePath: '/tmp/x.wav',
        durationSec: 42,
        sizeBytes: 2048,
        createdAt: DateTime(2026, 11, 21),
      );
      expect(entry.summary, 'WAV • aoede • 00:42 • 2 KB');
      await history.record(entry);
      await history.record(
        entry.copyWithForTest(id: 'h2', createdAt: DateTime(2026, 11, 22)),
      );
      final all = await history.loadAll();
      expect(all.length, 2);
      expect(all.first.id, 'h2'); // newest first
      expect(await history.remove('h1'), isTrue);
      expect(await history.remove('h1'), isFalse);
      await history.clear();
      expect(await history.loadAll(), isEmpty);
    });
  });

  // -----------------------------------------------------------------
  // 9. Burn-in (filter graph builders + drawtext fallback).
  // -----------------------------------------------------------------
  group('Video burn-in', () {
    test('ASS attempt args: scale + subtitles + x264 + audio copy', () {
      final args = VideoExportService.burnInArgs(
        inputPath: '/tmp/in.mp4',
        assPath: '/tmp/caps.ass',
        outputPath: '/tmp/out.mp4',
        quality: VideoExportQuality.p720,
        vertical: true,
      );
      expect(args, contains('-vf'));
      final vf = args[args.indexOf('-vf') + 1];
      expect(vf, 'scale=720:-2,subtitles=/tmp/caps.ass');
      expect(args, contains('libx264'));
      expect(args, contains('23'));
      expect(args, contains('copy'));
      expect(args.last, '/tmp/out.mp4');

      final args1080 = VideoExportService.burnInArgs(
        inputPath: '/tmp/in.mp4',
        assPath: '/tmp/caps.ass',
        outputPath: '/tmp/out.mp4',
        quality: VideoExportQuality.p1080,
        vertical: false,
      );
      expect(args1080[args1080.indexOf('-vf') + 1],
          'scale=-2:1080,subtitles=/tmp/caps.ass');
    });

    test('drawtext fallback parses ASS Dialogues back out', () async {
      final ass = CaptionService.buildStyledAss(
        [
          CaptionSegment('hello world', 1.0, 2.5),
          CaptionSegment('second line', 3.0, 4.0),
        ],
        StudioCaptionStyles.byId('classic'),
      );
      final filter = await VideoExportService.buildDrawtextFilter(
        assContent: ass,
        scale: 'scale=-2:720',
        quality: VideoExportQuality.p720,
        vertical: false,
      );
      expect(filter, isNotNull);
      expect(filter!, startsWith('scale=-2:720,drawtext='));
      expect('drawtext='.allMatches(filter).length, 2);
      expect(filter, contains("between(t,1.0,2.5)"));
      expect(filter, contains("between(t,3.0,4.0)"));
      expect(filter, contains('hello world'));
    });

    test('drawtext fallback returns null when no Dialogues parse', () async {
      final filter = await VideoExportService.buildDrawtextFilter(
        assContent: '[Script Info]\nTitle: empty\n',
        scale: 'scale=-2:720',
        quality: VideoExportQuality.p720,
        vertical: false,
      );
      expect(filter, isNull);
    });

    test('filter-path escaping handles colon + quote', () {
      expect(
        VideoExportService.escapeFilterPath("/tmp/a:b'c.ass"),
        r"/tmp/a\:b\'c.ass",
      );
      expect(VideoExportService.scaleFor(VideoExportQuality.p720, true),
          'scale=720:-2');
      expect(VideoExportService.scaleFor(VideoExportQuality.p1080, false),
          'scale=-2:1080');
    });
  });

  // -----------------------------------------------------------------
  // 10. Audio tools (convert / extract / trim / join builders).
  // -----------------------------------------------------------------
  group('Audio tools', () {
    test('MP3 convert args: codec + bitrate + rate + channels', () {
      final args = AudioToolsService.buildConvertArgs(
        inputPath: '/tmp/in.wav',
        options: const ConvertOptions(format: ConvertFormat.mp3),
        outputPath: '/tmp/out.mp3',
      );
      expect(args, contains('libmp3lame'));
      expect(args, contains('192k'));
      expect(args, contains('44100'));
      expect(args, contains('2'));
      expect(args.last, '/tmp/out.mp3');
    });

    test('WAV convert has no bitrate; loudnorm wins over volume', () {
      final wavArgs = AudioToolsService.buildConvertArgs(
        inputPath: '/tmp/in.mp3',
        options: const ConvertOptions(format: ConvertFormat.wav),
        outputPath: '/tmp/out.wav',
      );
      expect(wavArgs, contains('pcm_s16le'));
      expect(wavArgs, isNot(contains('192k')));
      final normArgs = AudioToolsService.buildConvertArgs(
        inputPath: '/tmp/in.mp3',
        options: const ConvertOptions(volume: 1.5, loudnorm: true),
        outputPath: '/tmp/out.mp3',
      );
      final af = normArgs[normArgs.indexOf('-af') + 1];
      expect(af, contains('loudnorm'));
      expect(af, isNot(contains('volume=')));
      final volArgs = AudioToolsService.buildConvertArgs(
        inputPath: '/tmp/in.mp3',
        options: const ConvertOptions(volume: 1.5),
        outputPath: '/tmp/out.mp3',
      );
      expect(volArgs[volArgs.indexOf('-af') + 1], contains('volume=1.50'));
    });

    test('trim + speed + fade-out anchor on the trimmed duration', () {
      final args = AudioToolsService.buildConvertArgs(
        inputPath: '/tmp/in.mp3',
        options: const ConvertOptions(
          trimStartSec: 2.0,
          trimEndSec: 12.0,
          speed: 1.5,
          fadeOutSec: 1.0,
        ),
        outputPath: '/tmp/out.mp3',
      );
      expect(args, contains('-ss'));
      expect(args, contains('2.00'));
      expect(args, contains('-to'));
      expect(args, contains('12.00'));
      final af = args[args.indexOf('-af') + 1];
      expect(af, contains('atempo=1.50'));
      // Fade-out starts at (12-2) - 1 = 9.00s into the trimmed audio.
      expect(af, contains('afade=t=out:st=9.00:d=1.00'));
    });

    test('extract audio args + output naming', () {
      final args = AudioToolsService.buildExtractAudioArgs(
        videoPath: '/tmp/clip.mp4',
        format: ConvertFormat.mp3,
        outputPath: '/tmp/clip_audio.mp3',
      );
      expect(args, contains('-vn'));
      expect(args, contains('libmp3lame'));
      expect(
        AudioToolsService.outputPathFor('/tmp/voice.wav', ConvertFormat.mp3),
        '/tmp/voice_converted.mp3',
      );
    });

    test('pure-Dart trim/join/duration on WAV + MP3 bytes', () {
      final wav = makeWav(seconds: 4);
      expect(
        AudioToolsService.audioDurationSeconds(wav),
        closeTo(4.0, 0.01),
      );
      final trimmed = AudioToolsService.trimAudio(wav, 1.0, 3.0);
      expect(
        AudioToolsService.audioDurationSeconds(trimmed),
        closeTo(2.0, 0.01),
      );
      final joined = AudioToolsService.joinAudio([trimmed, trimmed]);
      expect(
        AudioToolsService.audioDurationSeconds(joined),
        closeTo(4.0, 0.01),
      );
      final mp3 = makeMp3(frames: 10);
      expect(
        AudioToolsService.audioDurationSeconds(mp3),
        closeTo(10 * 1152 / 44100, 0.01),
      );
      expect(AudioToolsService.audioDurationSeconds(Uint8List(4)), isNull);
      expect(() => AudioToolsService.joinAudio([wav, mp3]), throwsException);
    });
  });

  // -----------------------------------------------------------------
  // 11. TTS Studio service (pure parts: chunking, voices, fallbacks).
  // -----------------------------------------------------------------
  group('TTS Studio service', () {
    test('8 voices: Aoede/Charon + Asad/Uzma + 4 gated, API names', () {
      expect(StudioVoice.all.length, 8);
      expect(StudioVoice.byId('aoede').label, 'Aoede');
      expect(StudioVoice.byId('charon').label, 'Charon');
      expect(StudioVoice.byId('asad').apiName, 'ur-PK-AsadNeural');
      expect(StudioVoice.byId('uzma').apiName, 'ur-PK-UzmaNeural');
      expect(StudioVoice.byId('kore').apiName, 'Kore');
      expect(StudioVoice.byId('fenrir').apiName, 'Fenrir');
      expect(StudioVoice.byId('puck').apiName, 'Puck');
      expect(StudioVoice.byId('zephyr').apiName, 'Zephyr');
      // No "Billo"/"Jaani" labels anywhere.
      expect(
        StudioVoice.all.map((v) => v.label),
        isNot(contains('Billo')),
      );
      expect(
        StudioVoice.all.map((v) => v.label),
        isNot(contains('Jaani')),
      );
    });

    test('fallback mapping is same-gender both ways', () {
      expect(TtsStudioService.edgeFallbackFor(StudioVoice.aoede).id, 'uzma');
      expect(TtsStudioService.edgeFallbackFor(StudioVoice.charon).id, 'asad');
      expect(
        TtsStudioService.geminiFallbackFor(StudioVoice.asad).id,
        'charon',
      );
      expect(
        TtsStudioService.geminiFallbackFor(StudioVoice.uzma).id,
        'aoede',
      );
    });

    test('chunking: short text = 1 chunk; long text splits on sentences', () {
      expect(
        TtsStudioService.chunkText('Short text.', StudioVoice.aoede),
        ['Short text.'],
      );
      expect(TtsStudioService.chunkText('', StudioVoice.aoede), isEmpty);
      final long = List.filled(150, 'یہ ایک لمبا جملہ ہے۔').join(' ');
      final chunks = TtsStudioService.chunkText(long, StudioVoice.aoede);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(2000));
      }
      expect(
        TtsStudioService.estimatedRequests(long, StudioVoice.aoede),
        chunks.length,
      );
      // Edge chunks are smaller (550) than Gemini (2000).
      final edgeChunks = TtsStudioService.chunkText(long, StudioVoice.asad);
      expect(edgeChunks.length, greaterThanOrEqualTo(chunks.length));
      for (final c in edgeChunks) {
        expect(c.length, lessThanOrEqualTo(550));
      }
    });

    test('a single over-long sentence hard-splits on words', () {
      final sentence = List.filled(500, 'word').join(' ');
      final chunks = TtsStudioService.chunkText(sentence, StudioVoice.aoede);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(2000));
      }
      expect(chunks.join(' '), sentence);
    });

    test('sample texts exist for News/Story/Ad', () {
      expect(TtsStudioService.sampleTexts.keys.toSet(), {'News', 'Story', 'Ad'});
      for (final sample in TtsStudioService.sampleTexts.values) {
        expect(sample.trim(), isNotEmpty);
      }
    });
  });

  // -----------------------------------------------------------------
  // 12. Voiceover service basics (chunking + language detect).
  // -----------------------------------------------------------------
  group('GeminiVoiceService basics', () {
    test('chunkText splits on sentences, never mid-sentence', () {
      expect(GeminiVoiceService.chunkText(''), isEmpty);
      final text = 'پہلا جملہ۔ دوسرا جملہ۔ تیسرا جملہ۔';
      expect(GeminiVoiceService.chunkText(text), [text]);
      final long = List.filled(200, 'یہ ایک جملہ ہے۔').join(' ');
      final chunks = GeminiVoiceService.chunkText(long);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(2000));
      }
    });

    test('detectLang: Arabic script -> ur, else en', () {
      expect(GeminiVoiceService.detectLang('یہ خبر ہے'), 'ur');
      expect(GeminiVoiceService.detectLang('This is news'), 'en');
      expect(GeminiVoiceService.detectLang(''), 'en');
    });

    test('admin emails exempt (local check)', () {
      expect(
        GeminiVoiceService.isAdminEmail('mithubhattijani@gmail.com'),
        isTrue,
      );
      expect(
        GeminiVoiceService.isAdminEmail('MITHUBHATTIJANI@GMAIL.COM'),
        isTrue,
      );
      expect(GeminiVoiceService.isAdminEmail('someone@else.com'), isFalse);
      expect(GeminiVoiceService.isAdminEmail(null), isFalse);
    });
  });

  // -----------------------------------------------------------------
  // 13. NewsProject: caption settings + voice controls round-trip.
  // -----------------------------------------------------------------
  group('NewsProject Phase 5 fields', () {
    test('caption settings + voice controls survive JSON', () {
      final project = NewsProject.create()
        ..captionStyleId = 'bold_pop'
        ..captionPosition = CaptionPosition.middle
        ..captionSize = CaptionSize.large
        ..captionHighlight = 0xFFFFD60A
        ..captionFontId = 'bebas'
        ..captionOutline = false
        ..captionShadow = true
        ..captionBackground = true
        ..captionDualLanguage = true
        ..voiceSpeed = 1.25
        ..voicePauseSec = 0.5
        ..voiceMusic = true
        ..subtitles = [
          SubtitleLine(
            text: 'hello',
            startSec: 0,
            endSec: 1,
            words: [SubtitleWord(word: 'hello', startSec: 0, endSec: 1)],
            translation: 'salam',
          ),
        ];
      final restored = NewsProject.fromJson(project.toJson());
      expect(restored.captionStyleId, 'bold_pop');
      expect(restored.captionPosition, CaptionPosition.middle);
      expect(restored.captionSize, CaptionSize.large);
      expect(restored.captionHighlight, 0xFFFFD60A);
      expect(restored.captionFontId, 'bebas');
      expect(restored.captionOutline, isFalse);
      expect(restored.captionShadow, isTrue);
      expect(restored.captionBackground, isTrue);
      expect(restored.captionDualLanguage, isTrue);
      expect(restored.voiceSpeed, 1.25);
      expect(restored.voicePauseSec, 0.5);
      expect(restored.voiceMusic, isTrue);
      expect(restored.subtitles.first.words.first.word, 'hello');
      expect(restored.subtitles.first.translation, 'salam');
    });

    test('old JSON without Phase 5 fields loads defaults', () {
      final restored = NewsProject.fromJson({
        'id': 'old_1',
        'title': 'old',
        'tehreer': 'خبر',
        'voice': 'Aoede',
      });
      expect(restored.captionStyleId, 'nigraan');
      expect(restored.captionPosition, CaptionPosition.bottom);
      expect(restored.captionSize, CaptionSize.medium);
      expect(restored.captionHighlight, isNull);
      expect(restored.voiceSpeed, 1.0);
      expect(restored.voicePauseSec, 0.0);
      expect(restored.voiceMusic, isFalse);
      expect(restored.subtitles, isEmpty);
    });
  });
}

/// Test-only copy helper (the production class has no copyWith).
extension on TtsHistoryEntry {
  TtsHistoryEntry copyWithForTest({
    String? id,
    DateTime? createdAt,
  }) {
    return TtsHistoryEntry(
      id: id ?? this.id,
      text: text,
      voiceId: voiceId,
      lang: lang,
      ext: ext,
      filePath: filePath,
      durationSec: durationSec,
      sizeBytes: sizeBytes,
      createdAt: createdAt ?? this.createdAt,
      fellBackToEdge: fellBackToEdge,
      fellBackToGemini: fellBackToGemini,
    );
  }
}
