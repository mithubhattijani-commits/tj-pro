// Smoke test for TJ Pro: home screen shows both editor entries.

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
    expect(find.text('Photo Editor'), findsOneWidget);
    expect(find.text('Video Editor'), findsOneWidget);
  });

  testWidgets('News Studio card opens the live studio screen',
      (tester) async {
    _mockPathProvider();
    await tester.pumpWidget(const PhotoVideoEditorApp());

    expect(find.text('News Studio'), findsWidgets);
    final cardTitle = find.text('News Studio').first;
    await tester.ensureVisible(cardTitle);
    await tester.pump();
    await tester.tap(cardTitle);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Navigation landed on the News Studio screen (its AppBar + back
    // button). The screen's data (preset, templates, voice allowance)
    // is verified by the store unit tests — loading it here would need
    // real async the testWidgets fake zone cannot provide.
    expect(find.text('News Studio'), findsWidgets);
    expect(find.byType(BackButton), findsOneWidget);
  });
}
