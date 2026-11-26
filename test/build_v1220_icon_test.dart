// Jaani Studio v1.22.0 — new app icon proofs (user-supplied artwork,
// 26 Nov 2026): the launcher icon set was regenerated from the golden
// "J" artwork in exactly the old structure (legacy full-bleed squares
// + adaptive foregrounds at the old safe-zone geometry), the adaptive
// background colour was re-sampled from the new artwork, and the
// manifest still points at the same @mipmap/ic_launcher.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Jaani Studio launcher icon set', () {
    const sizes = <String, List<int>>{
      // folder: [legacy px, foreground canvas px]
      'mdpi': [48, 108],
      'hdpi': [72, 162],
      'xhdpi': [96, 216],
      'xxhdpi': [144, 324],
      'xxxhdpi': [192, 432],
    };

    test('all density files exist and are non-trivial', () {
      for (final e in sizes.entries) {
        for (final name in ['ic_launcher.png', 'ic_launcher_foreground.png']) {
          final f = File(
            'android/app/src/main/res/mipmap-${e.key}/$name',
          );
          expect(f.existsSync(), isTrue, reason: '${e.key}/$name missing');
          expect(f.lengthSync(), greaterThan(1000),
              reason: '${e.key}/$name suspiciously small');
        }
      }
    });

    test('adaptive background colour re-sampled from the new artwork', () {
      final colors = File(
        'android/app/src/main/res/values/ic_launcher_colors.xml',
      ).readAsStringSync();
      expect(colors, contains('<color name="ic_launcher_background">#231254</color>'));
    });

    test('adaptive icon config + manifest icon reference unchanged', () {
      final adaptive = File(
        'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      ).readAsStringSync();
      expect(adaptive, contains('@color/ic_launcher_background'));
      expect(adaptive, contains('@mipmap/ic_launcher_foreground'));
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    });
  });
}
