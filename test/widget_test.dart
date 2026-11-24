// Smoke test for TJ Pro: home screen shows the CREATE NEW
// entries (Video / Photo / News Studio circles).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
}

void main() {
  testWidgets('Home shows TJ Pro with both editors', (tester) async {
    await tester.pumpWidget(const PhotoVideoEditorApp());

    expect(find.text('TJ Pro'), findsOneWidget);
    // v1.5.6 (Build 4, user reference home): the editors are
    // the reference's three big cards — 'VIDEO EDITOR' /
    // 'PHOTO EDITOR' — which open the project hubs that start
    // the editors. (v1.5.2's CREATE NEW circles were replaced
    // by the user's own home design, copied "same to same".)
    expect(find.text('VIDEO EDITOR'), findsOneWidget);
    expect(find.text('PHOTO EDITOR'), findsOneWidget);
  });

  testWidgets('News Studio circle opens the news projects hub',
      (tester) async {
    _mockPathProvider();
    await tester.pumpWidget(const PhotoVideoEditorApp());

    expect(find.text('NEWS STUDIO'), findsWidgets);
    // v1.5.6 (Build 4): the entry is now the reference's gold
    // NEWS STUDIO big card — tap its mic icon. The destination
    // is unchanged: the news projects hub.
    final cardIcon = find.byIcon(Icons.mic).first;
    await tester.ensureVisible(cardIcon);
    await tester.pump();
    await tester.tap(cardIcon);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Navigation landed on the pushed News projects hub (its
    // AppBar + back button) — the hub is where News Maker
    // projects start from. (v1.5.6: the reference home's big
    // NEWS STUDIO card is the entry, wired to the same hub the
    // v1.5.2 circle opened.)
    expect(find.text('News Projects'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });
}
