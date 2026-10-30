// Smoke test for TJ Pro: home screen shows both editor entries.

import 'package:flutter_test/flutter_test.dart';

import 'package:tj_pro/main.dart';

void main() {
  testWidgets('Home shows TJ Pro with both editors', (tester) async {
    await tester.pumpWidget(const PhotoVideoEditorApp());

    expect(find.text('TJ Pro'), findsOneWidget);
    expect(find.text('Photo Editor'), findsOneWidget);
    expect(find.text('Video Editor'), findsOneWidget);
  });
}
