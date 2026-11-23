/// Master Plan Phase 0 — safety nets, unit level.
///
/// Covers the parts of Phase 0 that are testable without a device:
/// the crash guard's reporting funnel, the update service's byte
/// clamp + pending-download restore (no record / stale record),
/// the FFmpeg session registry's idle behaviour, and the stale
/// temp-file sweep. The native half of #34 (MainActivity.kt) and
/// the on-device poll are covered by the Phase 0 manual test gate
/// in PHASE0-TOOL-TESTS.md — they cannot run in a unit test.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/services/crash_guard.dart';
import 'package:tj_pro/services/ffmpeg_service.dart';
import 'package:tj_pro/services/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CrashGuard (Phase 0)', () {
    test('report logs, remembers and never throws without a UI', () {
      CrashGuard.lastError.value = null;
      CrashGuard.report(
        StateError('phase0 probe'),
        StackTrace.current,
        source: 'test',
      );
      expect(CrashGuard.lastError.value, contains('phase0 probe'));
    });

    test('install is idempotent', () {
      CrashGuard.install();
      CrashGuard.install();
      // Still fully functional after a double install.
      CrashGuard.report(
        StateError('after install'),
        StackTrace.current,
        source: 'test',
      );
      expect(CrashGuard.lastError.value, contains('after install'));
    });
  });

  group('UpdateService #34 helpers (Phase 0)', () {
    test('clampTotalBytes: unknown totals become 0', () {
      expect(UpdateService.clampTotalBytes(-1), 0);
      expect(UpdateService.clampTotalBytes(0), 0);
      expect(UpdateService.clampTotalBytes(253617110), 253617110);
    });

    test('restorePendingDownload with no record is a clean no-op',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await UpdateService.restorePendingDownload();
      expect(
        UpdateService.updateState.value.phase,
        UpdatePhase.idle,
      );
    });

    test(
        'restorePendingDownload with an unanswerable record stays '
        'idle and never throws', () async {
      // A persisted record exists, but the status channel has no
      // handler in the test host (returns null): restore must keep
      // its hands off the state and simply return — on a device the
      // same path keeps the record for the next launch.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tjpro_pending_dl_id': 42,
        'tjpro_pending_dl_code': 0,
        'tjpro_pending_dl_name': 'v0',
        'tjpro_pending_dl_url': 'https://example.invalid/x.apk',
        'tjpro_pending_dl_notes': '',
      });
      await UpdateService.restorePendingDownload();
      expect(
        UpdateService.updateState.value.phase,
        UpdatePhase.idle,
      );
    });
  });

  group('FfmpegService registry (Phase 0)', () {
    test('no sessions are active at rest', () {
      expect(FfmpegService.activeSessionCount, 0);
    });

    test('cancel paths are safe no-ops when idle', () async {
      await FfmpegService.cancelCurrent();
      await FfmpegService.prepareForNewRun();
      expect(FfmpegService.activeSessionCount, 0);
    });

    test('cleanStaleTempFiles deletes only stale prefixed entries',
        () async {
      final dir = await Directory.systemTemp.createTemp('phase0_');
      try {
        final staleFile = File('${dir.path}/reel_export_old.mp4');
        await staleFile.writeAsString('x');
        await staleFile.setLastModified(
          DateTime.now().subtract(const Duration(days: 2)),
        );
        final freshFile = File('${dir.path}/reel_norm_new.mp4');
        await freshFile.writeAsString('x');
        final otherFile = File('${dir.path}/keep_me.txt');
        await otherFile.writeAsString('x');
        await otherFile.setLastModified(
          DateTime.now().subtract(const Duration(days: 2)),
        );
        final freshDir = Directory('${dir.path}/reel_frames_new');
        await freshDir.create();

        await FfmpegService.cleanStaleTempFiles(
          dir,
          prefixes: const ['reel_'],
        );

        expect(await staleFile.exists(), isFalse);
        expect(await freshFile.exists(), isTrue);
        expect(await otherFile.exists(), isTrue);
        expect(await freshDir.exists(), isTrue);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('cleanStaleTempFiles tolerates a missing directory', () async {
      await FfmpegService.cleanStaleTempFiles(
        Directory('${Directory.systemTemp.path}/phase0_missing_zzz'),
        prefixes: const ['reel_'],
      );
    });
  });
}
