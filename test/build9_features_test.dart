// Build 9 (v1.7.0) — fix-list points #5 + #6 + the proXfade
// whitelist fix.
//
// Point #5: crash auto-report (offline queue + hourly dedupe +
// fail-soft flush), the "Report bhejo" feedback payload, and
// the remote kill-switch config + gates.
// Point #6A: banner booking — price table, per-slot queue
// math, automatic expiry, auto-moderation verdicts (text +
// image).
// Point #6B: the AI-tool price comes from the remote config
// (default 25).
// Whitelist: the five store transitions (zoomin, fadeblack,
// circleclose, fadewhite, vertopen) are valid xfade names and
// reach the generated FFmpeg command instead of falling back
// to 'fade'.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/main.dart';
import 'package:tj_pro/news/banner_booking_screen.dart';
import 'package:tj_pro/news/feedback_screen.dart';
import 'package:tj_pro/services/banner_booking_service.dart';
import 'package:tj_pro/services/banner_moderation.dart';
import 'package:tj_pro/services/crash_guard.dart';
import 'package:tj_pro/services/crash_reporter.dart';
import 'package:tj_pro/services/feature_gate.dart';
import 'package:tj_pro/services/feedback_service.dart';
import 'package:tj_pro/services/pro_editor.dart';
import 'package:tj_pro/services/remote_config_service.dart';

void mockPlatformChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final channel in const [
    'flutter/platform_views',
    'flutter/platform_views_2',
    'com.rebeloid.unity_ads',
  ]) {
    messenger.setMockMethodCallHandler(
      MethodChannel(channel),
      (MethodCall call) async => null,
    );
  }
}

BannerBooking booking({
  String id = 'b1',
  int slot = 1,
  String status = BannerBooking.statusApproved,
  required DateTime start,
  required DateTime end,
}) {
  return BannerBooking(
    id: id,
    userId: 'u1',
    slot: slot,
    imageUrl: 'https://example.com/ad.jpg',
    text: '',
    linkUrl: '',
    durationHours: 1,
    priceCoins: 100,
    status: status,
    startsAt: start,
    endsAt: end,
    createdAt: start,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(mockPlatformChannels);

  group('Whitelist fix — proXfade validNames', () {
    test('the five store transitions are valid names', () {
      for (final name in <String>[
        'zoomin',
        'fadeblack',
        'circleclose',
        'fadewhite',
        'vertopen',
      ]) {
        expect(ProTransition.validNames, contains(name), reason: name);
      }
      // 18 previous + 5 new, no duplicates crept in.
      expect(ProTransition.validNames.length, 23);
      expect(
        ProTransition.validNames.toSet().length,
        ProTransition.validNames.length,
      );
    });

    test('proXfadeCommand emits the real transition, not fade', () {
      final cmd = proXfadeCommand(
        inputs: <String>['a.mp4', 'b.mp4'],
        durationsMs: <int>[4000, 4000],
        transition: const ProTransition(name: 'zoomin'),
        hasAudio: false,
        output: 'out.mp4',
      );
      expect(cmd, isNotNull);
      expect(cmd, contains('xfade=transition=zoomin'));
    });

    test('an unknown name still falls back to fade', () {
      final cmd = proXfadeCommand(
        inputs: <String>['a.mp4', 'b.mp4'],
        durationsMs: <int>[4000, 4000],
        transition: const ProTransition(name: 'not_a_transition'),
        hasAudio: false,
        output: 'out.mp4',
      );
      expect(cmd, contains('xfade=transition=fade'));
    });
  });

  group('Point #5/#6B — remote config: kill keys + AI price', () {
    test('defaults: every kill switch OFF, price 25', () {
      const cfg = RemoteConfig();
      expect(cfg.killVideoExport, isFalse);
      expect(cfg.killPhotoAi, isFalse);
      expect(cfg.killAiCaptions, isFalse);
      expect(cfg.killStore, isFalse);
      expect(cfg.aiToolPriceCoins, 25);
    });

    test('absent keys keep the defaults', () {
      final cfg = RemoteConfig.fromJson(<String, dynamic>{});
      expect(cfg.killVideoExport, isFalse);
      expect(cfg.killStore, isFalse);
      expect(cfg.aiToolPriceCoins, 25);
    });

    test('only the literal boolean true arms a switch', () {
      final cfg = RemoteConfig.fromJson(<String, dynamic>{
        'kill_video_export': true,
        'kill_photo_ai': 'true', // string must NOT arm it
        'kill_ai_captions': 1, // number must NOT arm it
        'kill_store': false,
      });
      expect(cfg.killVideoExport, isTrue);
      expect(cfg.killPhotoAi, isFalse);
      expect(cfg.killAiCaptions, isFalse);
      expect(cfg.killStore, isFalse);
    });

    test('ai_tool_price_coins parses int and numeric string', () {
      expect(
        RemoteConfig.fromJson(<String, dynamic>{
          'ai_tool_price_coins': 40,
        }).aiToolPriceCoins,
        40,
      );
      expect(
        RemoteConfig.fromJson(<String, dynamic>{
          'ai_tool_price_coins': '30',
        }).aiToolPriceCoins,
        30,
      );
    });

    test('invalid prices fall back to 25 (never free/absurd)', () {
      for (final bad in <dynamic>[0, -5, 'abc', null, 99999999]) {
        expect(
          RemoteConfig.fromJson(<String, dynamic>{
            'ai_tool_price_coins': bad,
          }).aiToolPriceCoins,
          25,
          reason: '$bad',
        );
      }
    });

    test('withAdvertisingBanner preserves kill keys + price', () {
      final cfg = RemoteConfig.fromJson(<String, dynamic>{
        'kill_store': true,
        'ai_tool_price_coins': 40,
      });
      final overridden =
          cfg.withAdvertisingBanner(imageUrl: 'x.jpg', linkUrl: '');
      expect(overridden.killStore, isTrue);
      expect(overridden.aiToolPriceCoins, 40);
    });

    test('FeatureGate maps each feature to its own switch', () {
      const cfg = RemoteConfig(killPhotoAi: true);
      expect(FeatureGate.isKilled(KillableFeature.photoAi, config: cfg),
          isTrue);
      expect(FeatureGate.isKilled(KillableFeature.store, config: cfg),
          isFalse);
      expect(
          FeatureGate.isKilled(KillableFeature.videoExport, config: cfg),
          isFalse);
      expect(
          FeatureGate.isKilled(KillableFeature.aiCaptions, config: cfg),
          isFalse);
    });
  });

  group('Point #5 — crash reporter queue', () {
    final store = <String, String>{};
    var fixedNow = DateTime(2026, 11, 25, 7, 0);

    setUp(() {
      CrashReporter.resetForTest();
      CrashGuard.resetDiagnosticsForTest();
      store.clear();
      fixedNow = DateTime(2026, 11, 25, 7, 0);
      CrashReporter.nowFn = () => fixedNow;
      CrashReporter.prefsReader = (k) async => store[k];
      CrashReporter.prefsWriter = (k, v) async {
        store[k] = v;
      };
      CrashReporter.deviceInfoOverride =
          () async => (model: 'Test Phone', android: 'Android 14');
    });

    tearDown(() {
      CrashReporter.resetForTest();
    });

    test('enqueue builds a full row and queues it', () async {
      CrashReporter.sendOverride = (_) async => false; // keep queued
      final r = CrashReporter.instance;
      await r.init();
      r.enqueue(Exception('boom'), StackTrace.current, source: 'test');
      expect(r.queuedReports, hasLength(1));
      final row = r.queuedReports.single;
      expect(row['source'], 'test');
      expect(row['error'], contains('boom'));
      expect(row['device_model'], 'Test Phone');
      expect(row['android_version'], 'Android 14');
      expect(row['install_id'], isNotEmpty);
      expect(row['fingerprint'], isNotEmpty);
    });

    test('same fingerprint within an hour is queued only once',
        () async {
      CrashReporter.sendOverride = (_) async => false;
      final r = CrashReporter.instance;
      await r.init();
      r.enqueue(Exception('same'), StackTrace.current, source: 's');
      r.enqueue(Exception('same'), StackTrace.current, source: 's');
      expect(r.queuedReports, hasLength(1));
      // A different error is a different fingerprint.
      r.enqueue(Exception('other'), StackTrace.current, source: 's');
      expect(r.queuedReports, hasLength(2));
      // After the hour, the same error may be reported again.
      fixedNow = fixedNow.add(const Duration(hours: 1, minutes: 1));
      r.enqueue(Exception('same'), StackTrace.current, source: 's');
      expect(r.queuedReports, hasLength(3));
    });

    test('queue is capped at 50, oldest dropped', () async {
      CrashReporter.sendOverride = (_) async => false;
      final r = CrashReporter.instance;
      await r.init();
      for (var i = 0; i < 55; i++) {
        r.enqueue(Exception('e$i'), StackTrace.current, source: 's$i');
      }
      expect(r.queuedReports, hasLength(CrashReporter.maxQueueEntries));
      expect(r.queuedReports.first['error'], contains('e5'));
    });

    test('flush success clears the queue; failure keeps it', () async {
      var accept = false;
      CrashReporter.sendOverride = (_) async => accept;
      final r = CrashReporter.instance;
      await r.init();
      r.enqueue(Exception('x'), StackTrace.current, source: 's');
      await r.flush();
      expect(r.queuedReports, hasLength(1)); // send refused -> kept
      accept = true;
      await r.flush();
      expect(r.queuedReports, isEmpty);
    });

    test('CrashGuard hands recorded errors to the reporter', () async {
      CrashReporter.sendOverride = (_) async => false;
      final r = CrashReporter.instance;
      await r.init();
      CrashGuard.captureHandled(
        Exception('via guard'),
        StackTrace.current,
        source: 'maker.preview',
      );
      expect(r.queuedReports, hasLength(1));
      expect(r.queuedReports.single['source'], 'maker.preview');
    });

    test('long errors and stacks are truncated', () async {
      CrashReporter.sendOverride = (_) async => false;
      final r = CrashReporter.instance;
      await r.init();
      final row = r.buildRow(
        Exception('x' * 5000),
        StackTrace.fromString('y' * 5000),
        source: 's',
        when: fixedNow,
      );
      expect((row['error'] as String).length,
          CrashReporter.maxErrorChars);
      expect((row['stack'] as String).length,
          CrashReporter.maxStackChars);
    });
  });

  group('Point #5 — feedback payload', () {
    test('buildRow carries message + truncated diagnostics', () {
      final row = FeedbackService.buildRow(
        message: 'app hang hua',
        diagnostics: 'd' * 9000,
        when: DateTime(2026, 11, 25),
      );
      expect(row['message'], 'app hang hua');
      expect((row['diagnostics'] as String).length,
          FeedbackService.maxDiagnosticsChars);
      expect(row['created_at'], isNotNull);
    });

    test('send goes through the override and reports its result',
        () async {
      Map<String, dynamic>? seen;
      FeedbackService.sendOverride = (row) async {
        seen = row;
        return true;
      };
      final ok = await FeedbackService.send(
        message: '',
        diagnostics: 'diag',
      );
      expect(ok, isTrue);
      expect(seen?['message'], ''); // empty message still sends
      FeedbackService.sendOverride = null;
    });
  });

  group('Point #6A — moderation', () {
    test('clean text passes', () {
      expect(
        BannerModeration.checkText('Meray Channel Ko Subscribe Karein')
            .verdict,
        ModerationVerdict.pass,
      );
    });

    test('english profanity rejects', () {
      expect(
        BannerModeration.checkText('this is shit').verdict,
        ModerationVerdict.reject,
      );
    });

    test('roman urdu profanity rejects', () {
      expect(
        BannerModeration.checkText('wo bohat harami hai').verdict,
        ModerationVerdict.reject,
      );
    });

    test('urdu script profanity rejects', () {
      expect(
        BannerModeration.checkText('یہ حرامی ہے').verdict,
        ModerationVerdict.reject,
      );
    });

    test('word boundaries: innocent lookalikes pass', () {
      // 'sexy' contains 'sex' but is a different word; the
      // filter matches whole words only.
      expect(
        BannerModeration.checkText('sexy design studio').verdict,
        ModerationVerdict.pass,
      );
    });

    test('borderline category goes to review, never straight live',
        () {
      expect(
        BannerModeration.checkText('best casino offers').verdict,
        ModerationVerdict.review,
      );
    });

    test('link must be http/https', () {
      expect(BannerModeration.checkLink('').verdict,
          ModerationVerdict.pass);
      expect(BannerModeration.checkLink('https://example.com/x').verdict,
          ModerationVerdict.pass);
      expect(BannerModeration.checkLink('ftp://example.com').verdict,
          ModerationVerdict.reject);
      expect(BannerModeration.checkLink('not a link').verdict,
          ModerationVerdict.reject);
    });

    test('image checks: real png passes, fake png rejects, '
        'tiny image reviews', () async {
      final dir = await Directory.systemTemp.createTemp('b9mod');
      try {
        final good = File('${dir.path}/good.png');
        await good.writeAsBytes(
          img.encodePng(img.Image(width: 800, height: 400)),
        );
        expect(
          (await BannerModeration.checkImageFile(good)).verdict,
          ModerationVerdict.pass,
        );

        final fake = File('${dir.path}/fake.png');
        await fake.writeAsString('this is not an image');
        expect(
          (await BannerModeration.checkImageFile(fake)).verdict,
          ModerationVerdict.reject,
        );

        final tiny = File('${dir.path}/tiny.png');
        await tiny.writeAsBytes(
          img.encodePng(img.Image(width: 50, height: 20)),
        );
        expect(
          (await BannerModeration.checkImageFile(tiny)).verdict,
          ModerationVerdict.review,
        );

        final gif = File('${dir.path}/anim.gif');
        await gif.writeAsBytes(
          img.encodePng(img.Image(width: 800, height: 400)),
        );
        expect(
          (await BannerModeration.checkImageFile(gif)).verdict,
          ModerationVerdict.reject,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('Point #6A — booking math', () {
    final now = DateTime(2026, 11, 25, 12, 0);

    test('price table is the user-confirmed 100/200/300', () {
      expect(
        BannerBookingService.durations
            .map((d) => (d.hours, d.coins))
            .toList(),
        <(int, int)>[(1, 100), (2, 200), (4, 300)],
      );
    });

    test('free slot starts now; busy slot queues at its end', () {
      expect(BannerBookingService.computeStart(<BannerBooking>[], 1, now),
          now);
      final running = booking(
        start: now.subtract(const Duration(minutes: 30)),
        end: now.add(const Duration(minutes: 30)),
      );
      expect(
        BannerBookingService.computeStart(<BannerBooking>[running], 1, now),
        running.endsAt,
      );
      // The other slot is independent.
      expect(
        BannerBookingService.computeStart(<BannerBooking>[running], 2, now),
        now,
      );
    });

    test('isActiveAt honours the window edges (automatic expiry)',
        () {
      final b = booking(
        start: now,
        end: now.add(const Duration(hours: 1)),
      );
      expect(b.isActiveAt(now), isTrue);
      expect(b.isActiveAt(now.add(const Duration(minutes: 59))), isTrue);
      expect(b.isActiveAt(now.add(const Duration(hours: 1))), isFalse);
      expect(
        b.isActiveAt(now.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      // A pending_review booking NEVER shows, even in-window.
      final pending = booking(
        status: BannerBooking.statusPendingReview,
        start: now,
        end: now.add(const Duration(hours: 1)),
      );
      expect(pending.isActiveAt(now), isFalse);
    });

    test('activeFrom picks the active booking of the slot only', () {
      final mine = booking(
        id: 'a',
        slot: 2,
        start: now.subtract(const Duration(minutes: 10)),
        end: now.add(const Duration(minutes: 50)),
      );
      expect(
        BannerBookingService.activeFrom(<BannerBooking>[mine], 2, now)?.id,
        'a',
      );
      expect(
        BannerBookingService.activeFrom(<BannerBooking>[mine], 1, now),
        isNull,
      );
    });
  });

  group('Point #5/#6A — widgets', () {
    testWidgets('KilledFeatureNotice shows the polite message',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: KilledFeatureNotice())),
      );
      expect(find.text(FeatureGate.killedMessage), findsOneWidget);
    });

    testWidgets('FeedbackScreen renders field + send button',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.pumpWidget(
        const MaterialApp(home: FeedbackScreen()),
      );
      await tester.pump();
      expect(find.byKey(const Key('feedbackMessageField')), findsOneWidget);
      expect(find.byKey(const Key('feedbackSendButton')), findsOneWidget);
      expect(find.text('Report bhejo'), findsWidgets);
    });

    testWidgets('BannerBookingScreen renders slots, durations, book',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      BannerBookingService.resetForTest();
      await tester.pumpWidget(
        const MaterialApp(home: BannerBookingScreen()),
      );
      await tester.pump();
      expect(find.byKey(const Key('bookingSlot1')), findsOneWidget);
      expect(find.byKey(const Key('bookingSlot2')), findsOneWidget);
      expect(find.byKey(const Key('bookingDuration0')), findsOneWidget);
      expect(find.byKey(const Key('bookingDuration2')), findsOneWidget);
      expect(find.byKey(const Key('bookingSubmitButton')), findsOneWidget);
      BannerBookingService.resetForTest();
    });

    testWidgets('app: Home builds with the booking layer idle',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      BannerBookingService.resetForTest();
      await tester.pumpWidget(const PhotoVideoEditorApp());
      await tester.pump();
      // Past the SplashGate: Home's own hero (owner banner) is
      // up, no booked slide exists, nothing threw.
      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pump();
      expect(find.byKey(const Key('homeHeroBanner')), findsOneWidget);
      expect(find.byKey(const Key('homeHeroBooked1')), findsNothing);
      expect(find.byKey(const Key('homeHeroBooked2')), findsNothing);
      expect(tester.takeException(), isNull);
      BannerBookingService.resetForTest();
    });

    testWidgets('app: an active slot-1 booking takes the hero slot',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      BannerBookingService.resetForTest();
      final now = DateTime.now();
      BannerBookingService.fetchApprovedOverride = () async =>
          <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'bk1',
              'user_id': 'someone',
              'slot': 1,
              'image_url': 'https://example.com/ad.png',
              'ad_text': 'Ad',
              'link_url': '',
              'duration_hours': 1,
              'price_coins': 100,
              'status': 'approved',
              'starts_at':
                  now.subtract(const Duration(minutes: 5)).toIso8601String(),
              'ends_at':
                  now.add(const Duration(minutes: 55)).toIso8601String(),
              'created_at': now.toIso8601String(),
            },
          ];
      await BannerBookingService.instance.refresh();
      await tester.pumpWidget(const PhotoVideoEditorApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1900));
      await tester.pump();
      expect(find.byKey(const Key('homeHeroBooked1')), findsOneWidget);
      expect(tester.takeException(), isNull);
      BannerBookingService.resetForTest();
    });
  });
}
