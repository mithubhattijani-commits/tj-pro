/// Export-crash hotfix regression tests (audit C1–C7):
/// encode policy, ping-pong cycle wiring, the clipper clamp
/// guard, the export-death watcher, and the CrashGuard
/// mid-frame deferral. Pure-Dart / widget level — no device,
/// no ffmpeg execution.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tj_pro/live/parity_template.dart';
import 'package:tj_pro/news/widgets/template_media_preview.dart';
import 'package:tj_pro/services/crash_guard.dart';
import 'package:tj_pro/services/export_death_watcher.dart';
import 'package:tj_pro/services/ffmpeg_service.dart';
import 'package:tj_pro/services/performance_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FfmpegService.applyEncodePolicy (audit C1/C6)', () {
    const cmd = '-y -i in.mp4 -c:v libx264 -preset veryfast '
        '-crf 23 -c:a aac out.mp4';

    test('default policy is byte-identical (no cap, veryfast)', () {
      expect(
        FfmpegService.applyEncodePolicy(cmd, threads: 0, preset: 'veryfast'),
        cmd,
      );
    });

    test('LOW policy caps threads and steps the preset', () {
      expect(
        FfmpegService.applyEncodePolicy(cmd, threads: 2, preset: 'superfast'),
        '-y -i in.mp4 -c:v libx264 -threads 2 -preset superfast '
        '-crf 23 -c:a aac out.mp4',
      );
    });

    test('HIGH policy caps threads, preset unchanged', () {
      expect(
        FfmpegService.applyEncodePolicy(cmd, threads: 6, preset: 'veryfast'),
        '-y -i in.mp4 -c:v libx264 -threads 6 -preset veryfast '
        '-crf 23 -c:a aac out.mp4',
      );
    });

    test('bitrate variant of the token is rewritten too', () {
      const brCmd = '-y -i in.mp4 -c:v libx264 -preset veryfast '
          '-b:v 5000k -maxrate 7500k out.mp4';
      expect(
        FfmpegService.applyEncodePolicy(brCmd, threads: 4, preset: 'veryfast'),
        '-y -i in.mp4 -c:v libx264 -threads 4 -preset veryfast '
        '-b:v 5000k -maxrate 7500k out.mp4',
      );
    });

    test('commands without the token pass through untouched', () {
      const copyCmd = '-y -i in.mp4 -c:v copy -c:a copy out.mp4';
      expect(
        FfmpegService.applyEncodePolicy(
          copyCmd,
          threads: 2,
          preset: 'superfast',
        ),
        copyCmd,
      );
    });
  });

  group('PerformanceConfig encode policy per tier', () {
    test('thread caps + LOW preset step', () {
      expect(PerformanceConfig.forTier(DeviceTier.low).exportThreads, 2);
      expect(
        PerformanceConfig.forTier(DeviceTier.low).exportPreset,
        'superfast',
      );
      expect(PerformanceConfig.forTier(DeviceTier.mid).exportThreads, 4);
      expect(PerformanceConfig.forTier(DeviceTier.mid).exportPreset, 'veryfast');
      expect(PerformanceConfig.forTier(DeviceTier.high).exportThreads, 6);
      expect(
        PerformanceConfig.forTier(DeviceTier.high).exportPreset,
        'veryfast',
      );
      expect(PerformanceConfig.forTier(DeviceTier.flagship).exportThreads, 8);
    });

    test('engine pushes the live policy into FfmpegService', () {
      PerformanceEngine.debugSetProfileForTest(
        const DeviceProfile(ramMb: 2048, cpuCores: 4),
      );
      expect(PerformanceEngine.instance.tier, DeviceTier.low);
      expect(FfmpegService.encodeThreads, 2);
      expect(FfmpegService.encodePreset, 'superfast');
      PerformanceEngine.resetForTest();
      FfmpegService.encodeThreads = 0;
      FfmpegService.encodePreset = 'veryfast';
    });
  });

  group('safeNotchFrom — the clipper clamp guard', () {
    test('valid inputs behave exactly like the old clamp', () {
      expect(safeNotchFrom(top: 100, bottom: 500, notchTop: 300), 300);
      expect(safeNotchFrom(top: 100, bottom: 500, notchTop: 50), 100);
      expect(safeNotchFrom(top: 100, bottom: 500, notchTop: 600), 500);
    });

    test('inverted range (the crash shape) clamps instead of throwing', () {
      // First layout frame: bottom still 0, top already positive.
      expect(safeNotchFrom(top: 120, bottom: 0, notchTop: 300), 120);
      expect(safeNotchFrom(top: 120, bottom: 0, notchTop: 40), 40);
      expect(safeNotchFrom(top: 120, bottom: 0, notchTop: 0), 0);
    });

    test('degenerate + NaN inputs never throw', () {
      expect(safeNotchFrom(top: 200, bottom: 200, notchTop: 999), 200);
      expect(safeNotchFrom(top: 0, bottom: 0, notchTop: 0), 0);
      expect(safeNotchFrom(top: double.nan, bottom: 100, notchTop: 50), 0);
      expect(safeNotchFrom(top: 0, bottom: 100, notchTop: double.nan), 0);
    });
  });

  group('parity template — ping-pong cycle wiring (audit C3)', () {
    test('cycle input is looped, graph has NO reverse', () {
      final assets = ParityAssets(
        geometry: ParityGeometry(720, 1280),
        ribbons: const [],
        capBar: File('/tmp/capbar.png'),
        capDate: File('/tmp/capdate.png'),
        topRibbon: null,
      );
      final cmd = buildParityTemplateCommand(
        input: '/tmp/in.mp4',
        output: '/tmp/out.mp4',
        assets: assets,
        logoPingPongPath: '/tmp/logo-cycle.mov',
        clockFontFile: null,
        exportStart: DateTime(2026, 11, 25, 12),
      );
      expect(cmd, contains("-stream_loop -1 -i '/tmp/logo-cycle.mov'"));
      expect(cmd, contains('split[logoa][logob]'));
      expect(cmd, isNot(contains('reverse')));
    });
  });

  group('ExportDeathWatcher (audit C4)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      CrashGuard.resetDiagnosticsForTest();
      ExportDeathWatcher.resetForTest();
    });

    tearDown(() {
      ExportDeathWatcher.resetForTest();
    });

    test('window decision: slack before start, anything after', () {
      const start = 1000000000;
      expect(
        ExportDeathWatcher.exitBelongsToExportWindow(
          exportStartedAtMs: start,
          exitTimestampMs: start,
        ),
        isTrue,
      );
      expect(
        ExportDeathWatcher.exitBelongsToExportWindow(
          exportStartedAtMs: start,
          exitTimestampMs: start + 3600000,
        ),
        isTrue,
      );
      expect(
        ExportDeathWatcher.exitBelongsToExportWindow(
          exportStartedAtMs: start,
          exitTimestampMs: start - 4 * 60000,
        ),
        isTrue,
      );
      expect(
        ExportDeathWatcher.exitBelongsToExportWindow(
          exportStartedAtMs: start,
          exitTimestampMs: start - 6 * 60000,
        ),
        isFalse,
      );
    });

    test('reason names', () {
      expect(ExportDeathWatcher.reasonName(3), 'LOW_MEMORY');
      expect(ExportDeathWatcher.reasonName(5), 'CRASH_NATIVE');
      expect(ExportDeathWatcher.reasonName(99), 'REASON_99');
    });

    test('a death inside the window is reported once, marker cleared',
        () async {
      final startedAt = DateTime(2026, 11, 25, 10, 0);
      ExportDeathWatcher.nowFn = () => startedAt;
      await ExportDeathWatcher.markExportStarted();
      ExportDeathWatcher.exitInfoReaderForTest = () async => {
            'reason': 3,
            'timestamp': startedAt.millisecondsSinceEpoch + 120000,
            'description': 'lmkd kill',
          };
      await ExportDeathWatcher.checkOnStartup();
      expect(CrashGuard.recentDiagnostics, hasLength(1));
      expect(CrashGuard.recentDiagnostics.single, contains('LOW_MEMORY'));
      expect(CrashGuard.recentDiagnostics.single, contains('export.exit'));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getInt(ExportDeathWatcher.markerPrefsKey),
        isNull,
      );
      // One-shot: a second check reports nothing new.
      await ExportDeathWatcher.checkOnStartup();
      expect(CrashGuard.recentDiagnostics, hasLength(1));
    });

    test('a death BEFORE the window stays silent', () async {
      final startedAt = DateTime(2026, 11, 25, 10, 0);
      ExportDeathWatcher.nowFn = () => startedAt;
      await ExportDeathWatcher.markExportStarted();
      ExportDeathWatcher.exitInfoReaderForTest = () async => {
            'reason': 3,
            'timestamp': startedAt.millisecondsSinceEpoch - 3600000,
            'description': 'older death',
          };
      await ExportDeathWatcher.checkOnStartup();
      expect(CrashGuard.recentDiagnostics, isEmpty);
    });

    test('no marker, no report', () async {
      ExportDeathWatcher.exitInfoReaderForTest = () async => {
            'reason': 3,
            'timestamp': 1,
            'description': '',
          };
      await ExportDeathWatcher.checkOnStartup();
      expect(CrashGuard.recentDiagnostics, isEmpty);
    });

    test('graceful finish clears the marker — no report', () async {
      ExportDeathWatcher.nowFn = () => DateTime(2026, 11, 25, 10, 0);
      await ExportDeathWatcher.markExportStarted();
      await ExportDeathWatcher.markExportFinished();
      ExportDeathWatcher.exitInfoReaderForTest = () async => {
            'reason': 3,
            'timestamp': DateTime(2026, 11, 25, 10, 1)
                .millisecondsSinceEpoch,
            'description': '',
          };
      await ExportDeathWatcher.checkOnStartup();
      expect(CrashGuard.recentDiagnostics, isEmpty);
    });
  });

  group('CrashGuard mid-frame deferral', () {
    testWidgets('report() during build defers the banner, never throws',
        (tester) async {
      CrashGuard.resetThrottleForTest();
      CrashGuard.resetDiagnosticsForTest();
      var fired = false;
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: CrashGuard.messengerKey,
          home: Builder(
            builder: (context) {
              if (!fired) {
                fired = true;
                // Fires INSIDE the build phase — the exact
                // shape of the clipper paint error. Before the
                // hotfix this threw "Build scheduled during
                // frame" from inside the reporter itself.
                CrashGuard.report(
                  StateError('mid-frame error'),
                  StackTrace.current,
                  source: 'test.frame',
                );
              }
              return const Scaffold(body: Text('home'));
            },
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pump();
      expect(tester.takeException(), isNull);
      // The deferred banner landed after the frame.
      expect(find.textContaining('Kuch ghalat ho gaya'), findsOneWidget);
      // And the error was still RECORDED (recording is never
      // deferred or throttled).
      expect(CrashGuard.lastError.value, contains('mid-frame error'));
    });
  });
}
