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
    // v1.5.2 (fix #54): the editors no longer have their own
    // Home cards — they are the CREATE NEW circles ('Video' /
    // 'Photo'), which open the project hubs that start the
    // editors. The old full-name cards were duplicates.
    expect(find.text('Photo'), findsWidgets);
    expect(find.text('Video'), findsWidgets);
  });

  testWidgets('News Studio circle opens the news projects hub',
      (tester) async {
    _mockPathProvider();
    await tester.pumpWidget(const PhotoVideoEditorApp());

    expect(find.text('News Studio'), findsWidgets);
    // The circle's label sits below its tap area — tap the
    // circle's newspaper icon (the first one; the second is the
    // bottom-nav tab's icon).
    final circleIcon = find.byIcon(Icons.newspaper).first;
    await tester.ensureVisible(circleIcon);
    await tester.pump();
    await tester.tap(circleIcon);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Navigation landed on the pushed News projects hub (its
    // AppBar + back button) — the hub is where News Maker
    // projects start from (v1.5.2: the old direct News Studio
    // card was one of the duplicated Home entries; the bottom
    // nav's News Studio tab is the studio's one Home entry).
    expect(find.text('News Projects'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });
}
