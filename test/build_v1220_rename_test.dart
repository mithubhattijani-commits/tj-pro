// Jaani Studio v1.22.0 — app rename proofs (user order, 26 Nov 2026):
// the DISPLAY name changed from "TJ Pro" to "Jaani Studio" everywhere
// the user sees it, while the app's internal identity (package,
// update/config URLs, deep links, pubspec package name) is pinned
// UNCHANGED so existing installs keep updating as the same app.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/app_config.dart';
import 'package:tj_pro/services/referral_service.dart';
import 'package:tj_pro/services/remote_config_service.dart';
import 'package:tj_pro/services/update_service.dart';

void main() {
  group('display name is Jaani Studio', () {
    test('AppConfig.appName (MaterialApp title + Home header)', () {
      expect(AppConfig.appName, 'Jaani Studio');
    });

    test('launcher label in AndroidManifest is Jaani Studio', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:label="Jaani Studio"'));
      expect(manifest, isNot(contains('android:label="TJ Pro"')));
    });

    test('share text leads with the new name', () {
      final svc = ReferralService.instance;
      expect(svc.shareText, startsWith('Jaani Studio — free photo & video editor!'));
    });
  });

  group('internal identity did NOT change (rename guard)', () {
    test('update manifest URL still tj-pro-version.json', () {
      expect(
        UpdateService.manifestUrl,
        'https://nigraantv.xyz/apps/tj-pro-version.json',
      );
    });

    test('remote config URL still tj-pro.json', () {
      expect(
        RemoteConfigService.configUrl,
        'https://nigraantv.xyz/apps/config/tj-pro.json',
      );
    });

    test('referral share base URL still /apps/tj-pro', () {
      expect(ReferralService.shareBaseUrl, 'https://nigraantv.xyz/apps/tj-pro');
    });

    test('Android applicationId still com.tjpro.app', () {
      final gradle =
          File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('applicationId = "com.tjpro.app"'));
    });

    test('deep-link scheme/host in manifest unchanged', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:scheme="tjpro"'));
      expect(manifest, contains('android:pathPrefix="/apps/tj-pro"'));
    });

    test('pubspec package name still tj_pro, version is 1.26.0+45', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('name: tj_pro'));
      expect(pubspec, contains('version: 1.26.0+45'));
      expect(pubspec, contains('description: "Jaani Studio — '));
    });
  });
}
