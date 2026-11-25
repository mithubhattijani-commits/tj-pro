/// Build 13 (v1.10.0) — unit tests for the pure pieces:
/// the caption script aligner (point #16), the update reason
/// texts (point #18), the cube geometry + JSON round-trips
/// (point #19), the ducking command compatibility (point 5),
/// and the Logo Parts model + save-state + split (point 6).
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/live/parity_template.dart';
import 'package:tj_pro/news/breaking_templates.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/karaoke_sync.dart';
import 'package:tj_pro/news/news_analysis.dart';
import 'package:tj_pro/news/logo_parts.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/news/script_aligner.dart';
import 'package:tj_pro/services/ffmpeg_service.dart';
import 'package:tj_pro/services/logo_cube.dart';
import 'package:tj_pro/services/logo_loop_service.dart';
import 'package:tj_pro/services/update_service.dart';

void main() {
  group('point 1 — script aligner normalisation', () {
    test('arabic letter folds', () {
      expect(ScriptAligner.normalizeWord('يوم'), 'یوم');
      expect(ScriptAligner.normalizeWord('كتاب'), 'کتاب');
    });

    test('diacritics and punctuation stripped', () {
      expect(ScriptAligner.normalizeWord('مُحَمَّدٌ'), 'محمد');
      expect(ScriptAligner.normalizeWord('ختم۔'), 'ختم');
      expect(ScriptAligner.normalizeWord('(خبر)'), 'خبر');
    });

    test('arabic-indic digits fold to ascii', () {
      expect(ScriptAligner.normalizeWord('١٢٣'), '123');
      expect(ScriptAligner.normalizeWord('۴۵۶'), '456');
    });

    test('similarity: identical 1, disjoint low', () {
      expect(ScriptAligner.similarity('abc', 'abc'), 1.0);
      expect(ScriptAligner.similarity('abc', 'xyz'), lessThan(0.45));
      expect(ScriptAligner.similarity('', 'abc'), 0.0);
    });
  });

  group('point 1 — DP alignment', () {
    List<AlignedToken> tokens(List<String> words) {
      var t = 0.0;
      return [
        for (final w in words)
          AlignedToken(
            text: w,
            startSec: t,
            endSec: t += 0.4,
          ),
      ];
    }

    test('clean script aligns fully, monotonic', () {
      final script = ['پاکستان', 'میں', 'نئے', 'صوبے', 'بنیں', 'گے'];
      final a = ScriptAligner.align(
        scriptWords: script,
        tokens: tokens(script),
        durationSec: 2.4,
      );
      expect(a.matchRate, 1.0);
      expect(a.matchRate, greaterThanOrEqualTo(kAlignAcceptRate));
      for (var i = 1; i < a.words.length; i++) {
        expect(
          a.words[i].startSec,
          greaterThanOrEqualTo(a.words[i - 1].startSec),
        );
      }
    });

    test('noisy transcript still aligns above the accept line', () {
      final script = 'پاکستان میں نئے صوبوں کی تجویز پر بحث جاری ہے'.split(' ');
      // Whisper-tiny-style phonetic noise on ~half the words.
      final heard = [
        'پاکستان',
        'میں',
        'نئے',
        'صوبو',
        'کی',
        'تجویز',
        'پر',
        'بحث',
        'جاری',
        'ہے',
      ];
      final a = ScriptAligner.align(
        scriptWords: script,
        tokens: tokens(heard),
        durationSec: 4,
      );
      expect(a.matchRate, greaterThanOrEqualTo(kAlignAcceptRate));
      expect(a.matchedCount, greaterThanOrEqualTo(7));
    });

    test('unrelated transcript is rejected', () {
      final a = ScriptAligner.align(
        scriptWords: ['a', 'b', 'c', 'd', 'e', 'f'],
        tokens: tokens(['x', 'y', 'z', 'w', 'v', 'u']),
        durationSec: 2.4,
      );
      expect(a.matchRate, lessThan(kAlignAcceptRate));
    });

    test('unmatched words are filled between anchors', () {
      final script = ['ایک', 'دو', 'تین', 'چار'];
      // Anchors with a real time gap: ایک at 0–0.4, چار at 1.2–1.6.
      final heard = [
        const AlignedToken(text: 'ایک', startSec: 0, endSec: 0.4),
        const AlignedToken(text: 'چار', startSec: 1.2, endSec: 1.6),
      ];
      final a = ScriptAligner.align(
        scriptWords: script,
        tokens: heard,
        durationSec: 1.6,
      );
      // دو/تین filled proportionally inside the (0.4, 1.2) gap.
      expect(a.words[1].startSec, greaterThan(a.words[0].startSec));
      expect(a.words[2].startSec, lessThan(a.words[3].startSec));
      expect(a.words[1].matched, isFalse);
    });
  });

  group('point 1 — karaoke resync with aligned timings', () {
    test('regroups flat words into the existing lines', () {
      final lines = [
        SubtitleLine(text: 'پہلی لائن یہاں', startSec: 0, endSec: 2),
        SubtitleLine(text: 'دوسری لائن', startSec: 2, endSec: 4),
      ];
      final aligned = [
        const AlignedScriptWord(
          word: 'پہلی',
          startSec: 0.1,
          endSec: 0.5,
          matched: true,
        ),
        const AlignedScriptWord(
          word: 'لائن',
          startSec: 0.6,
          endSec: 1.0,
          matched: true,
        ),
        const AlignedScriptWord(
          word: 'یہاں',
          startSec: 1.1,
          endSec: 1.5,
          matched: true,
        ),
        const AlignedScriptWord(
          word: 'دوسری',
          startSec: 2.0,
          endSec: 2.4,
          matched: true,
        ),
        const AlignedScriptWord(
          word: 'لائن',
          startSec: 2.5,
          endSec: 2.9,
          matched: true,
        ),
      ];
      final out = resyncWithAlignedTimings(lines, aligned, 4);
      expect(out.length, 2);
      expect(out[0].startSec, 0.1);
      expect(out[0].endSec, 1.5);
      expect(out[1].startSec, 2.0);
      expect(out[0].text, 'پہلی لائن یہاں');
    });

    test('word-count disagreement returns empty (caller keeps old)', () {
      final lines = [
        SubtitleLine(text: 'ایک دو', startSec: 0, endSec: 2),
      ];
      final out = resyncWithAlignedTimings(
        lines,
        const [
          AlignedScriptWord(
            word: 'ایک',
            startSec: 0,
            endSec: 1,
            matched: true,
          ),
        ],
        2,
      );
      expect(out, isEmpty);
    });
  });

  group('point 1 — NewsProject timing fields', () {
    test('round-trip through JSON', () {
      final p = NewsProject.create()
        ..captionTimingSource = 'whisper'
        ..captionAlignedHash = 'abc123'
        ..musicDucking = false
        ..tickerSpeed = 1.75
        ..tickerLoop = false;
      final back = NewsProject.fromJson(p.toJson());
      expect(back.captionTimingSource, 'whisper');
      expect(back.captionAlignedHash, 'abc123');
      expect(back.musicDucking, isFalse);
      expect(back.tickerSpeed, 1.75);
      expect(back.tickerLoop, isFalse);
    });

    test('absent keys give historic defaults', () {
      final p = NewsProject.fromJson({'id': 'x', 'presetId': 'y'});
      expect(p.captionTimingSource, 'estimate');
      expect(p.captionAlignedHash, '');
      expect(p.musicDucking, isTrue);
      expect(p.tickerSpeed, 1.0);
      expect(p.tickerLoop, isTrue);
    });

    test('staleness flips when the script changes after aligning', () {
      final p = NewsProject.create()
        ..tehreer = 'اصل خبر یہ ہے'
        ..subtitles = [
          SubtitleLine(text: 'اصل خبر یہ ہے', startSec: 0, endSec: 3),
        ];
      p.captionTimingSource = 'whisper';
      p.captionAlignedHash = p.captionTimingFingerprint;
      expect(p.captionTimingsStale, isFalse);
      p.tehreer = 'بدلی ہوئی خبر';
      expect(p.captionTimingsStale, isTrue);
    });
  });

  group('point 2 — reason texts', () {
    test('paused reasons', () {
      expect(UpdateService.pausedReasonText(1), contains('dobara'));
      expect(UpdateService.pausedReasonText(2), contains('network'));
      expect(UpdateService.pausedReasonText(3), contains('Wi-Fi'));
      expect(UpdateService.pausedReasonText(-1), contains('ruki'));
    });

    test('failed reasons', () {
      expect(UpdateService.failedReasonText(1006), contains('jagah'));
      expect(UpdateService.failedReasonText(1009), contains('file'));
      expect(UpdateService.failedReasonText(404), contains('404'));
      expect(UpdateService.failedReasonText(-1), contains('fail'));
    });

    test('watchdog is five minutes', () {
      expect(UpdateService.pausedWatchdog, const Duration(minutes: 5));
    });
  });

  group('point 3 — cube geometry + JSON', () {
    test('tilt 0 culls the top face; tilt sign picks the cap', () {
      bool faceVisible(double tilt, int face) => logoCubeFaces(
            angleY: 0,
            center: const Offset(100, 100),
            size: 100,
            textureWidth: 100,
            textureHeight: 100,
            tiltX: tilt,
          ).any((f) => f.face == face);
      expect(faceVisible(0, kCubeFaceTop), isFalse);
      expect(faceVisible(0.85, kCubeFaceTop), isTrue);
      expect(faceVisible(-0.85, kCubeFaceBottom), isTrue);
      expect(faceVisible(0.85, kCubeFaceBottom), isFalse);
      expect(faceVisible(0, kCubeFaceFront), isTrue);
    });

    test('direction: ccw negates the angle', () {
      expect(
        logoCubeAngleFor(0.25, clockwise: false),
        -logoCubeAngleFor(0.25, clockwise: true),
      );
    });

    test('variant key changes with every setting', () {
      final base = logoCubeVariantKey(
        facePaths: const {},
        speedSec: 6,
        clockwise: true,
        tiltX: 0,
        pedestal: false,
      );
      expect(
        logoCubeVariantKey(
          facePaths: const {},
          speedSec: 4,
          clockwise: true,
          tiltX: 0,
          pedestal: false,
        ),
        isNot(base),
      );
      expect(
        logoCubeVariantKey(
          facePaths: const {},
          speedSec: 6,
          clockwise: true,
          tiltX: 0.85,
          pedestal: false,
        ),
        isNot(base),
      );
      expect(
        logoCubeVariantKey(
          facePaths: const {'front': '/x.png'},
          speedSec: 6,
          clockwise: true,
          tiltX: 0,
          pedestal: false,
        ),
        isNot(base),
      );
    });

    test('preset cube fields round-trip; absent = Samne defaults', () {
      final p = ChannelPreset.nigraanTv()
        ..logoCubeTilt = 0.85
        ..logoCubeSpeedSec = 4
        ..logoCubeDirection = 'ccw'
        ..logoCubePedestal = true
        ..logoCubeFacePaths = {'front': '/a.png'};
      final back = ChannelPreset.fromJson(p.toJson());
      expect(back.logoCubeTilt, 0.85);
      expect(back.logoCubeSpeedSec, 4);
      expect(back.logoCubeDirection, 'ccw');
      expect(back.logoCubePedestal, isTrue);
      expect(back.logoCubeFacePaths['front'], '/a.png');

      final plain = ChannelPreset.fromJson({'id': 'z', 'name': 'Z'});
      expect(plain.logoCubeTilt, 0.0);
      expect(plain.logoCubeSpeedSec, 6.0);
      expect(plain.logoCubeDirection, 'cw');
      expect(plain.logoCubePedestal, isFalse);
    });

    test('breaking template carries the cube fields both ways', () {
      final preset = ChannelPreset.nigraanTv()
        ..logoCubeTilt = -0.85
        ..logoCubeSpeedSec = 3;
      final t = BreakingTemplate.fromPreset(preset);
      expect(t.logoCubeTilt, -0.85);
      expect(t.logoCubeSpeedSec, 3);
      final back = ChannelPreset.nigraanTv();
      t.applyToPreset(back);
      expect(back.logoCubeTilt, -0.85);
      final roundTrip = BreakingTemplate.fromJson(t.toJson());
      expect(roundTrip.logoCubeTilt, -0.85);
    });

    test('ticker speed factor multiplies the parity scroll speed', () {
      final g1 = ParityGeometry(1080, 1920);
      final g2 = ParityGeometry(1080, 1920, tickerSpeedFactor: 2);
      expect(g2.scrollSpeed, g1.scrollSpeed * 2);
    });

    test('project ticker speed multiplies the breaking template', () {
      final project = NewsProject.create()..tickerSpeed = 1.5;
      final preset = ChannelPreset.nigraanTv();
      final before = BreakingTemplate.fromPreset(preset).speed;
      final t = BreakingTemplate.fromProject(project, preset);
      expect(t.speed, closeTo(before * 1.5, 0.001));
    });
  });

  group('point 5 — ducking command compatibility', () {
    test('default call reproduces the historic graph exactly', () {
      final cmd = FfmpegService.musicDuckCommand(
        input: 'in.mp4',
        musicPath: 'm.mp3',
        output: 'out.mp4',
        hasClipAudio: true,
        musicVolume: 0.5,
      );
      expect(cmd, contains('[1:a]volume=0.50[bedraw];'));
      expect(cmd, contains('sidechaincompress'));
      expect(cmd, isNot(contains('afade')));
    });

    test('NS call adds the bed fades', () {
      final cmd = FfmpegService.musicDuckCommand(
        input: 'in.mp4',
        musicPath: 'm.mp3',
        output: 'out.mp4',
        hasClipAudio: true,
        musicVolume: 0.12,
        fadeInSec: 0.8,
        fadeOutSec: 1.5,
        durationSec: 30,
      );
      expect(cmd, contains('afade=t=in:st=0:d=0.80'));
      expect(cmd, contains('afade=t=out:st=28.50:d=1.50'));
    });
  });

  group('point 6 — logo parts model', () {
    test('speed snaps to loop divisors', () {
      expect(snapLogoPartSpeed(5), 4); // tie 4/6 -> the lower wins
      expect(snapLogoPartSpeed(5.5), 6);
      expect(snapLogoPartSpeed(2.4), 2);
      expect(snapLogoPartSpeed(20), 12);
      expect(LogoPart(
        id: 'a',
        name: 'A',
        sourcePath: '/x.png',
        box: const LogoBox(x: 0, y: 0, w: 0.5, h: 0.5),
        speedSec: 5,
      ).speedSec, 4);
    });

    test('parts JSON round-trip (element model: box + source)', () {
      final parts = [
        LogoPart(
          id: 'p0',
          name: 'Part 1',
          sourcePath: '/logo.png',
          box: const LogoBox(x: 0.1, y: 0.2, w: 0.3, h: 0.5),
          rotate: false,
          direction: 'ccw',
          speedSec: 4,
        ),
      ];
      final back = decodeLogoParts(encodeLogoParts(parts));
      expect(back.length, 1);
      expect(back.single.rotate, isFalse);
      expect(back.single.direction, 'ccw');
      expect(back.single.speedSec, 4);
      expect(back.single.box, parts.single.box);
      // Pivot = the box's centre, always.
      expect(back.single.centreX, 0.25);
      expect(back.single.centreY, 0.45);
      expect(decodeLogoParts(''), isEmpty);
      expect(decodeLogoParts('not json'), isEmpty);
    });

    test('old slice-model save loads as NO parts (no crash)', () {
      // The old payload: per-part PNG paths + centroids, no
      // box, no shared source — it cannot map to elements.
      final old = decodeLogoParts(
        '[{"id":"a","name":"A","imagePath":"/a.png","rotate":true,'
        '"direction":"cw","speedSec":6,"centreX":0.5,"centreY":0.5}]',
      );
      expect(old, isEmpty);
    });

    test('save state: never / active / expired at exactly 7 days', () {
      const day = Duration.millisecondsPerDay;
      final t0 = 100 * day;
      expect(logoPartsSaveState(0, t0), LogoPartsSaveState.never);
      expect(logoPartsSaveState(t0, t0 + 6 * day), LogoPartsSaveState.active);
      expect(
        logoPartsSaveState(t0, t0 + 7 * day),
        LogoPartsSaveState.expired,
      );
      expect(logoPartsSaveDaysLeft(t0, t0), 7);
      expect(logoPartsSaveDaysLeft(t0, t0 + 6 * day + 1), 1);
      expect(logoPartsSaveDaysLeft(t0, t0 + 7 * day), 0);
    });

    test('preset parts save fields round-trip; working list does not', () {
      final p = ChannelPreset.nigraanTv()
        ..logoPartsSavedJson = '[{"id":"a"}]'
        ..logoPartsSavedAtMs = 12345;
      final back = ChannelPreset.fromJson(p.toJson());
      expect(back.logoPartsSavedJson, '[{"id":"a"}]');
      expect(back.logoPartsSavedAtMs, 12345);
      expect(back.logoParts, isEmpty); // transient, never serialised
    });

    test('propose: synthetic logo yields element boxes, not slices', () {
      // 60x40: green bg, a red block left, a blue band right —
      // two separate design elements → two proposed boxes.
      const w = 60, h = 40;
      final rgba = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final o = (y * w + x) * 4;
          rgba[o + 3] = 255;
          if (x < 25) {
            rgba[o] = 220; // red block
          } else if (x > 35) {
            rgba[o + 2] = 220; // blue band
          } else {
            rgba[o + 1] = 177; // green gap (background colour)
          }
        }
      }
      // Border is red/blue at the edges — paint a green frame so
      // the border sampler sees the true background.
      for (var x = 0; x < w; x++) {
        for (final y in [0, h - 1]) {
          final o = (y * w + x) * 4;
          rgba[o] = 0;
          rgba[o + 1] = 177;
          rgba[o + 2] = 0;
        }
      }
      for (var y = 0; y < h; y++) {
        for (final x in [0, w - 1]) {
          final o = (y * w + x) * 4;
          rgba[o] = 0;
          rgba[o + 1] = 177;
          rgba[o + 2] = 0;
        }
      }
      final boxes = proposeLogoBoxes(rgba: rgba, width: w, height: h);
      expect(boxes.length, greaterThanOrEqualTo(2));
      // The boxes sit on the two elements (left / right).
      expect(boxes.any((b) => b.centreX < 0.45), isTrue);
      expect(boxes.any((b) => b.centreX > 0.55), isTrue);
    });
  });

  group('point 6 — green screen commands', () {
    test('parts (pre-greened frames) command', () {
      final cmd = FfmpegService.logoGreenScreenCommand(
        framesDir: '/d/frames',
        output: '/d/out.mp4',
        durationSec: 12,
      );
      expect(cmd, contains('frame_%02d.png'));
      expect(cmd, contains('-t 12.00'));
      expect(cmd, contains('yuv420p'));
    });

    test('cube composite command overlays on green', () {
      final cmd = FfmpegService.logoGreenCompositeCommand(
        framesDir: '/d/frames',
        output: '/d/out.mp4',
        durationSec: 6,
      );
      expect(cmd, contains('color=c=0x00B140'));
      expect(cmd, contains('overlay=0:0'));
    });
  });
}
