/// v1.21.0 — Logo Maker REVEAL integration proofs:
///
/// - The checked Gemini reveal/backdrops file lives in the
///   tree unchanged (its own 21 tests ride along in
///   logo_reveal_gemini_test.dart); here the SECTION wiring
///   is proven: the dock's 5th tab opens the Reveal panel,
///   the style/backdrop chips write the settings, a style
///   change restarts the reveal at that style's duration,
///   and scrubbing parks the animation.
/// - The 3 new settings fields persist through the existing
///   JSON and payloads saved before they existed (v1.20.0
///   and older) load fail-soft as the defaults.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/logo/logo_maker_section.dart';
import 'package:tj_pro/logo/logo_reveal_backdrops.dart';

Future<ui.Image> _makeTestImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(8, 12, 24, 16),
    Paint()..color = const Color(0xFFCC6633),
  );
  canvas.drawRect(
    const Rect.fromLTWH(8, 12, 10, 16),
    Paint()..color = const Color(0xFF3366CC),
  );
  final picture = recorder.endRecording();
  return picture.toImage(40, 40);
}

void main() {
  group('settings — the 3 reveal fields', () {
    test('round-trip preserves revealStyleId/backdropId/backdropGlow', () {
      const settings = LogoMakerSettings(
        revealStyleId: 'shine_sweep',
        backdropId: 'neon_grid',
        backdropGlow: 0.25,
      );
      final restored = LogoMakerSettings.fromJson(settings.toJson());
      expect(restored, settings);
      expect(restored.revealStyleId, 'shine_sweep');
      expect(restored.backdropId, 'neon_grid');
      expect(restored.backdropGlow, 0.25);
    });

    test('an empty revealStyleId (None) survives the round-trip', () {
      const settings = LogoMakerSettings(revealStyleId: '');
      final restored = LogoMakerSettings.fromJson(settings.toJson());
      expect(restored.revealStyleId, '');
      expect(restored, settings);
    });

    test('old JSON without the reveal keys loads as the defaults', () {
      // A v1.20.0-era payload: every pre-v1.21.0 key, none of
      // the new ones. It must decode to EXACTLY the defaults —
      // the export gate (settings == defaults → historic logo)
      // depends on this equality holding.
      final oldJson = const LogoMakerSettings().toJson()
        ..remove('revealStyleId')
        ..remove('backdropId')
        ..remove('backdropGlow');
      final restored = LogoMakerSettings.fromJson(oldJson);
      expect(restored, const LogoMakerSettings());
      expect(restored.revealStyleId, 'fade_zoom');
      expect(restored.backdropId, 'midnight_studio');
      expect(restored.backdropGlow, 0.6);
    });

    test('unknown ids and out-of-range glow fail soft', () {
      final restored = LogoMakerSettings.fromJson(<String, dynamic>{
        'revealStyleId': 'does_not_exist',
        'backdropId': 'does_not_exist',
        'backdropGlow': 7.5,
      });
      expect(restored.revealStyleId, 'fade_zoom');
      expect(restored.backdropId, 'midnight_studio');
      expect(restored.backdropGlow, 1.0);
    });

    test('every style/backdrop id in the lists round-trips', () {
      for (final style in kLogoRevealStyles) {
        final restored = LogoMakerSettings.fromJson(
          LogoMakerSettings(revealStyleId: style.id).toJson(),
        );
        expect(restored.revealStyleId, style.id, reason: style.id);
      }
      for (final backdrop in kLogoBackdrops) {
        final restored = LogoMakerSettings.fromJson(
          LogoMakerSettings(backdropId: backdrop.id).toJson(),
        );
        expect(restored.backdropId, backdrop.id, reason: backdrop.id);
      }
    });
  });

  group('section — Reveal tab', () {
    late ui.Image img;

    setUpAll(() async {
      img = await _makeTestImage();
    });

    void usePhoneSize(WidgetTester tester) {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Widget harness({
      LogoMakerSettings? initial,
      void Function(LogoMakerSettings)? onChanged,
    }) {
      return MaterialApp(
        home: LogoMakerSection(
          logoImage: img,
          initialSettings:
              initial ?? const LogoMakerSettings(spinOn: false),
          onSettingsChanged: onChanged ?? (_) {},
          onSave: (_) {},
          onClose: () {},
        ),
      );
    }

    Future<void> openReveal(WidgetTester tester) async {
      await tester.tap(find.text('Reveal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    /// The chip rows are horizontal ListViews that build
    /// their children lazily — a chip further along the row
    /// only enters the tree once the row is scrolled, exactly
    /// like a user's swipe. [listIndex] 0 = style row,
    /// 1 = backdrop row.
    Future<void> tapChip(
      WidgetTester tester,
      int listIndex,
      String label,
    ) async {
      final list = find.byType(ListView).at(listIndex);
      final target = find.text(label);
      for (var i = 0; i < 12; i++) {
        if (target.evaluate().isNotEmpty) {
          // Built is not enough — the chip must sit FULLY
          // inside the row, or the tap lands on its clipped
          // edge and the GestureDetector never fires.
          final listRect = tester.getRect(list);
          final chipRect = tester.getRect(target);
          if (chipRect.left >= listRect.left &&
              chipRect.right <= listRect.right) {
            break;
          }
        }
        await tester.drag(list, const Offset(-120, 0));
        await tester.pump(const Duration(milliseconds: 60));
      }
      await tester.tap(target);
      await tester.pump();
    }

    testWidgets('the dock carries Reveal between Spin and Save, and '
        'tapping it opens the Reveal panel', (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(harness());
      await tester.pump();

      // Dock order is the enum order: Logo / Style / Spin /
      // Reveal / Save — Reveal sits right of Spin, left of Save.
      final spinPos = tester.getCenter(find.text('Spin'));
      final revealPos = tester.getCenter(find.text('Reveal'));
      final saveLabels = find.text('Save');
      expect(saveLabels, findsWidgets);
      expect(revealPos.dx, greaterThan(spinPos.dx));

      await openReveal(tester);
      expect(find.text('Reveal Style'), findsOneWidget);
      expect(find.text('Backdrop Scene'), findsOneWidget);
      expect(find.text('Backdrop Glow'), findsOneWidget);
      // A style is selected by default, so Play + scrub show.
      expect(find.byKey(const Key('logoMakerRevealPlay')), findsOneWidget);
      expect(find.byKey(const Key('logoMakerRevealScrub')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a backdrop chip writes backdropId to the settings',
        (tester) async {
      usePhoneSize(tester);
      LogoMakerSettings? last;
      await tester.pumpWidget(harness(onChanged: (s) => last = s));
      await tester.pump();
      await openReveal(tester);

      await tapChip(tester, 1, 'Neon Grid');
      expect(last, isNotNull);
      expect(last!.backdropId, 'neon_grid');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a style chip restarts the reveal at that style\'s '
        'duration', (tester) async {
      usePhoneSize(tester);
      LogoMakerSettings? last;
      await tester.pumpWidget(harness(onChanged: (s) => last = s));
      await tester.pump();
      await openReveal(tester);

      // Default style is Fade Zoom — the readout carries its
      // 1200ms duration.
      expect(find.textContaining('1200ms'), findsOneWidget);

      await tapChip(tester, 0, 'Bounce In');
      expect(last, isNotNull);
      expect(last!.revealStyleId, 'bounce_in');
      // The playback readout now carries Bounce In's own
      // duration — the controller restarted on the new style.
      expect(find.textContaining('1100ms'), findsOneWidget);
      expect(find.textContaining('1200ms'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('scrubbing parks the reveal — it does not keep playing',
        (tester) async {
      usePhoneSize(tester);
      await tester.pumpWidget(harness());
      await tester.pump();
      await openReveal(tester);

      // The reveal auto-plays on opening the tab: after
      // 200ms of the 1200ms Fade Zoom it is under way.
      await tester.pump(const Duration(milliseconds: 200));

      final slider = tester.widget<Slider>(
        find.byKey(const Key('logoMakerRevealScrub')),
      );
      slider.onChanged!(0.5);
      await tester.pump();
      expect(find.textContaining('50%'), findsOneWidget);

      // Parked: a long wait later the readout has not moved.
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.textContaining('50%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the None chip clears the style and swaps Play for '
        'the pick-a-style hint', (tester) async {
      usePhoneSize(tester);
      LogoMakerSettings? last;
      await tester.pumpWidget(harness(onChanged: (s) => last = s));
      await tester.pump();
      await openReveal(tester);

      await tester.tap(find.text('None'));
      await tester.pump();
      expect(last, isNotNull);
      expect(last!.revealStyleId, '');
      expect(find.byKey(const Key('logoMakerRevealScrub')), findsNothing);
      expect(
        find.text('Pick a reveal style above to play it here.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
