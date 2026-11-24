// Smoke test for TJ Pro: home screen shows the CREATE NEW
// entries (Video / Photo / News Studio circles).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tj_pro/main.dart';

/// Points path_provider at a plain path so the News Studio screen's
/// stores load (fail-soft to defaults) in tests. Without a mock, the
/// unhandled platform-channel call never completes in the testWidgets
/// fake-async zone and the screen stays on its spinner.
void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return '/tmp/tj_pro_widget_test';
      }
      return null;
    },
  );
  SharedPreferences.setMockInitialValues({});
  // The workspace's voice recorder creates its platform object
  // on init; unmocked it surfaces as a MissingPluginException
  // once real async time passes.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.llfbandit.record/messages'),
    (MethodCall call) async => null,
  );
  // The Home banner ad is a platform view; in tests its async
  // create call would otherwise surface as a MissingPluginException
  // once real async time passes (runAsync below). A stub view id
  // satisfies the framework (on a phone the ad SDK renders it).
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter/platform_views'),
    (MethodCall call) async {
      if (call.method == 'create') return 1;
      return null;
    },
  );
}

/// The workspace's production load path reads the stores with
/// real dart:io, which only completes when the widget tree is
/// created and driven inside runAsync (the pattern proven in
/// build5_regressions_test.dart). [act] runs inside that real-
/// time window (pump the app, tap the entry), then real time is
/// given for the load to finish before asserting back in the
/// fake-async zone.
Future<void> _openWorkspaceInRealTime(
  WidgetTester tester,
  Future<void> Function() act,
) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(const PhotoVideoEditorApp());
    await tester.pump();
    // Build 6 (v1.5.8): the app now opens on the in-app splash
    // gate (1.8 s of REAL time here) — wait it out before acting
    // on Home.
    await Future<void>.delayed(const Duration(milliseconds: 2000));
    await tester.pump();
    await act();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await tester.pump();
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('Home shows TJ Pro with both editors', (tester) async {
    await tester.pumpWidget(const PhotoVideoEditorApp());
    // Build 6 (v1.5.8): past the in-app splash gate (1.8 s).
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump();

    expect(find.text('TJ Pro'), findsOneWidget);
    // v1.5.6 (Build 4, user reference home): the editors are
    // the reference's three big cards — 'VIDEO EDITOR' /
    // 'PHOTO EDITOR' — which open the project hubs that start
    // the editors. (v1.5.2's CREATE NEW circles were replaced
    // by the user's own home design, copied "same to same".)
    expect(find.text('VIDEO EDITOR'), findsOneWidget);
    expect(find.text('PHOTO EDITOR'), findsOneWidget);
  });

  testWidgets('News Studio card opens the workspace directly',
      (tester) async {
    _mockPathProvider();
    // Build 5 (v1.5.7, user ruling): the gold NEWS STUDIO card
    // opens the News Maker WORKSPACE directly — the old route
    // through the news projects hub / News Studio hub is retired.
    // (The mic icon also appears in the Live Streaming banner —
    // the card's is the first in the tree.)
    await _openWorkspaceInRealTime(tester, () async {
      expect(find.text('NEWS STUDIO'), findsWidgets);
      final cardIcon = find.byIcon(Icons.mic).first;
      await tester.ensureVisible(cardIcon);
      await tester.pump();
      await tester.tap(cardIcon);
      await tester.pump();
    });

    expect(find.byKey(const Key('makerToolLine')), findsOneWidget);
    expect(find.text('News Projects'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom News Studio tab opens the same workspace',
      (tester) async {
    _mockPathProvider();
    await _openWorkspaceInRealTime(tester, () async {
      await tester.tap(find.text('News Studio').last);
      await tester.pump();
    });
    expect(find.byKey(const Key('makerToolLine')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hero is the Nigraan banner image; Join Now is the '
      'Live door', (tester) async {
    _mockPathProvider();
    await tester.pumpWidget(const PhotoVideoEditorApp());
    // Build 6 (v1.5.8): past the in-app splash gate (1.8 s).
    await tester.pump(const Duration(milliseconds: 1900));
    await tester.pump();

    // Build 5 (v1.5.7): slide 1 is the user's banner artwork as
    // an image asset (not a drawn slide, no Watch Live pill).
    final hero = find.byKey(const Key('homeHeroBanner'));
    expect(hero, findsOneWidget);
    final image = tester.widget<Image>(
      find.descendant(of: hero, matching: find.byType(Image)),
    );
    expect(
      (image.image as AssetImage).assetName,
      'assets/hero_nigraan_banner.jpg',
    );
    expect(find.text('Watch Live'), findsNothing);
    // Live Studio's single Home door.
    expect(find.byKey(const Key('homeJoinNowButton')), findsOneWidget);
    // The Watch Ads small button is present (its tap runs the
    // rewarded ad itself — not exercised here: the ad stack has
    // no test implementation).
    expect(find.text('Watch Ads'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
