/// Build v1.18.0 — Motion-style reskin proofs.
///
/// The reskin is SKIN ONLY: these tests pin (a) the new Motion
/// theme values the whole app now wears, (b) the HOME GUARD —
/// the palette inputs Home reads are byte-identical to before,
/// so Home renders exactly as it did, (c) the new reusable
/// Motion chrome components actually work (button taps fire,
/// chips fire, cards render their children), and (d) a real
/// screen (Online Store) still renders its controls under the
/// new skin with the new scaffold colour.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tj_pro/news/store_screen.dart';
import 'package:tj_pro/theme.dart';
import 'package:tj_pro/widgets/motion_chrome.dart';

void main() {
  group('v1.18.0 — Motion theme values', () {
    test('dark theme wears the Motion navy/glass skin', () {
      final theme = TjProTheme.dark;
      expect(theme.scaffoldBackgroundColor, TjProTheme.motionBgBottom);
      expect(theme.scaffoldBackgroundColor, const Color(0xFF04060F));
      expect(theme.colorScheme.primary, TjProTheme.motionBlue);
      expect(theme.colorScheme.secondary, TjProTheme.motionCyan);
      expect(theme.dialogTheme.backgroundColor, const Color(0xFF0B1327));
      expect(theme.bottomSheetTheme.backgroundColor,
          const Color(0xFF0A1128));
      expect(theme.sliderTheme.activeTrackColor, TjProTheme.motionBlue);
      expect(theme.chipTheme.selectedColor, TjProTheme.motionBlue);
      expect(theme.progressIndicatorTheme.color, TjProTheme.motionCyan);
      expect(theme.appBarTheme.backgroundColor, TjProTheme.motionBgTop);
    });

    test('mockup gradient + glass values are the CSS values', () {
      expect(
        TjProTheme.motionGradient.colors,
        const <Color>[
          Color(0xFF7B2FFF),
          Color(0xFF2F7BFF),
          Color(0xFF00C6FF),
        ],
      );
      expect(
        TjProTheme.motionCyanGradient.colors,
        const <Color>[Color(0xFF00C6FF), Color(0xFF0072FF)],
      );
      final glass = TjProTheme.motionGlass();
      final gradient = glass.gradient! as LinearGradient;
      expect(
        gradient.colors,
        const <Color>[Color(0x6B284696), Color(0xB8090E22)],
      );
      // No backdrop blur anywhere in the skin: the decoration is
      // a plain gradient + border + shadow (BackdropFilter is a
      // widget, and none is used by the chrome components).
      expect(glass.border, isNotNull);
    });

    test('surface tokens moved into the Motion navy family', () {
      expect(TjProTheme.surfaceNavy, const Color(0xFF060A1C));
      expect(TjProTheme.background, const Color(0xFF060A1C));
      expect(TjProTheme.panelSurface, const Color(0xFF0C1428));
      expect(TjProTheme.surfaceDeep, const Color(0xFF04060F));
    });
  });

  group('v1.18.0 — HOME GUARD (Home palette inputs unchanged)', () {
    test('gold family + splash values are byte-identical', () {
      expect(TjProTheme.gold, const Color(0xFFFFD76A));
      expect(TjProTheme.goldDeep, const Color(0xFF9C7A1F));
      expect(TjProTheme.goldBright, const Color(0xFFFFE08A));
      expect(TjProTheme.homeGold, const Color(0xFFF5C542));
      expect(TjProTheme.splashBackground, const Color(0xFF030E3F));
    });
  });

  group('v1.18.0 — Motion chrome components work', () {
    testWidgets('MotionGradientButton renders and fires on tap',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: TjProTheme.dark,
          home: Scaffold(
            body: MotionGradientButton(
              onPressed: () => taps++,
              child: const Text('Export'),
            ),
          ),
        ),
      );
      expect(find.text('Export'), findsOneWidget);
      await tester.tap(find.text('Export'));
      expect(taps, 1);
    });

    testWidgets('MotionGlassCard / DockBar / Background render children',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TjProTheme.dark,
          home: MotionBackground(
            child: Column(
              children: const [
                MotionGlassCard(child: Text('glass child')),
                MotionDockBar(child: Text('dock child')),
              ],
            ),
          ),
        ),
      );
      expect(find.text('glass child'), findsOneWidget);
      expect(find.text('dock child'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('MotionChip fires and selected chip is gradient-filled',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: TjProTheme.dark,
          home: Scaffold(
            body: Row(
              children: [
                MotionChip(
                  label: 'Effects',
                  selected: true,
                  onTap: () => taps++,
                ),
                MotionChip(
                  label: 'Music',
                  selected: false,
                  onTap: () => taps++,
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Effects'), findsOneWidget);
      expect(find.text('Music'), findsOneWidget);
      // The selected chip's container carries the gradient.
      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .toList();
      final hasGradient = containers.any((c) {
        final d = c.decoration;
        return d is BoxDecoration && d.gradient != null;
      });
      expect(hasGradient, isTrue);
      await tester.tap(find.text('Music'));
      expect(taps, 1);
    });
  });

  group('v1.18.0 — Store screen under the new skin', () {
    testWidgets('renders title, category chips and the navy scaffold',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TjProTheme.dark,
          home: const StoreScreen(),
        ),
      );
      await tester.pump();
      expect(find.text('Online Store'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsWidgets);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, TjProTheme.surfaceNavy);
      expect(scaffold.backgroundColor, const Color(0xFF060A1C));
      expect(tester.takeException(), isNull);
      // Flush the store entry gate's background timers.
      await tester.pump(const Duration(seconds: 12));
      await tester.pump();
    });
  });
}
