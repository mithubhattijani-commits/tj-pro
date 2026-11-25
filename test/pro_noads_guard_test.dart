// Fix-list point #10 (2026-11-25) — PRO = NO ADS, central guard.
//
// Covers the app-side fix:
// - UnityAdsService: while ProService.proActive holds, interstitial
//   load / show and the export-ad sequence never reach the Unity
//   plugin (asserted by counting calls on the plugin's method
//   channel). With Pro inactive the same calls flow exactly as
//   before. Rewarded ads are out of scope and untouched.
// - UnityBannerAdWidget: renders nothing while Pro is active,
//   renders the banner slot while free, and reacts live when the
//   Pro state flips.
// - ProService.loadCachedGrant: the cache-only startup step main()
//   runs BEFORE UnityAdsService.init(), so a returning Pro user is
//   recognised before the first interstitial preload.
//
// The Unity plugin (unity_ads_plugin 0.5.0) talks on the method
// channel 'com.rebeloid.unity_ads' (methods init/load/showVideo);
// load/show callbacks arrive on 'com.rebeloid.unity_ads/videoAd_
// <placementId>' (loadComplete / showStart / showComplete) and the
// init callback on the main channel (initComplete). The mock below
// plays the platform side faithfully enough for the service's
// completers to resolve.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tj_pro/app_config.dart';
import 'package:tj_pro/services/pro_service.dart';
import 'package:tj_pro/services/unity_ads_service.dart';
import 'package:tj_pro/widgets/banner_ad_widget.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';

const MethodChannel _mainChannel = MethodChannel('com.rebeloid.unity_ads');
const String _mainChannelName = 'com.rebeloid.unity_ads';

/// Every Dart->platform call the plugin made, in order.
final List<MethodCall> _calls = <MethodCall>[];

/// Delivers a platform->Dart callback the way the real Unity SDK
/// would (through the binary messenger, to the plugin's handler).
Future<void> _platformCallback(
  String channelName,
  String method,
  Object? arguments,
) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        channelName,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (ByteData? _) {},
      );
}

String _placementChannel(String placementId) =>
    'com.rebeloid.unity_ads/videoAd_$placementId';

Future<void> _flush() =>
    Future<void>.delayed(const Duration(milliseconds: 60));

void _setPro({required bool active}) {
  ProService.instance.proUntil = active
      ? DateTime.now().add(const Duration(days: 1))
      : null;
  ProService.instance.isPro.value = active;
}

int _callsFor(String method, {String? placementId}) {
  return _calls.where((MethodCall c) {
    if (c.method != method) return false;
    if (placementId == null) return true;
    final Object? args = c.arguments;
    return args is Map && args['placementId'] == placementId;
  }).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_mainChannel, (MethodCall call) async {
          _calls.add(call);
          switch (call.method) {
            case 'init':
              unawaited(
                Future<void>(
                  () => _platformCallback(
                    _mainChannelName,
                    'initComplete',
                    null,
                  ),
                ),
              );
              return null;
            case 'load':
              final String id =
                  (call.arguments as Map)['placementId'] as String;
              unawaited(
                Future<void>(
                  () => _platformCallback(
                    _placementChannel(id),
                    'loadComplete',
                    <String, dynamic>{'placementId': id},
                  ),
                ),
              );
              return null;
            case 'showVideo':
              final String id =
                  (call.arguments as Map)['placementId'] as String;
              unawaited(
                Future<void>(() async {
                  await _platformCallback(
                    _placementChannel(id),
                    'showStart',
                    <String, dynamic>{'placementId': id},
                  );
                  await _platformCallback(
                    _placementChannel(id),
                    'showComplete',
                    <String, dynamic>{'placementId': id},
                  );
                }),
              );
              return null;
          }
          return null;
        });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_mainChannel, null);
    _setPro(active: false);
  });

  group('ProService.loadCachedGrant (startup-order helper)', () {
    test('a cached future grant is recognised without any network',
        () async {
      // The cache keys are ProService's private constants; they are
      // part of the on-device contract, so the test pins them.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tjpro_pro_until_ms_v1':
            DateTime.now()
                .add(const Duration(days: 7))
                .millisecondsSinceEpoch,
        'tjpro_pro_user_id_v1': '',
      });
      ProService.instance.proUntil = null;
      await ProService.instance.loadCachedGrant();
      expect(ProService.instance.proActive, isTrue);
    });

    test('a cached expired grant stays free', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tjpro_pro_until_ms_v1':
            DateTime.now()
                .subtract(const Duration(days: 1))
                .millisecondsSinceEpoch,
        'tjpro_pro_user_id_v1': '',
      });
      ProService.instance.proUntil = null;
      await ProService.instance.loadCachedGrant();
      expect(ProService.instance.proActive, isFalse);
    });
  });

  group('Pro active from a cold start (SDK never initialised)', () {
    setUp(() {
      _setPro(active: true);
      _calls.clear();
    });

    test('export ads return before even initialising the SDK',
        () async {
      await UnityAdsService.showExportAds(2);
      await _flush();
      expect(_calls, isEmpty);
      expect(UnityAdsService.isInitialized, isFalse);
    });

    test('interstitial load and show never reach the plugin',
        () async {
      expect(await UnityAdsService.loadInterstitialAd(), isFalse);
      expect(await UnityAdsService.showInterstitialAd(), isFalse);
      await _flush();
      expect(_callsFor('load'), 0);
      expect(_callsFor('showVideo'), 0);
    });
  });

  group('Free user — ad flow unchanged', () {
    setUp(() => _setPro(active: false));

    test('SDK initialises and preloads as before', () async {
      await UnityAdsService.init();
      await _flush();
      expect(UnityAdsService.isInitialized, isTrue);
      expect(_callsFor('init'), 1);
    });

    test('interstitial load reaches the plugin and succeeds',
        () async {
      _calls.clear();
      expect(await UnityAdsService.loadInterstitialAd(), isTrue);
      expect(
        _callsFor(
          'load',
          placementId: AppConfig.unityInterstitialPlacementId,
        ),
        1,
      );
    });

    test('interstitial show reaches the plugin and succeeds',
        () async {
      await _flush();
      _calls.clear();
      expect(await UnityAdsService.showInterstitialAd(), isTrue);
      expect(
        _callsFor(
          'showVideo',
          placementId: AppConfig.unityInterstitialPlacementId,
        ),
        1,
      );
    });
  });

  group('Pro granted mid-session — suppression is immediate', () {
    setUp(() async {
      await _flush();
      _setPro(active: true);
      _calls.clear();
    });

    test('load, show and export ads all stop at the guard', () async {
      expect(await UnityAdsService.loadInterstitialAd(), isFalse);
      expect(await UnityAdsService.showInterstitialAd(), isFalse);
      await UnityAdsService.showExportAds(1);
      await _flush();
      expect(_calls, isEmpty);
    });
  });

  group('Pro expired — ads flow again', () {
    test('interstitial load reaches the plugin once more', () async {
      ProService.instance.proUntil =
          DateTime.now().subtract(const Duration(minutes: 5));
      ProService.instance.isPro.value = false;
      _calls.clear();
      expect(await UnityAdsService.loadInterstitialAd(), isTrue);
      expect(
        _callsFor(
          'load',
          placementId: AppConfig.unityInterstitialPlacementId,
        ),
        1,
      );
      _setPro(active: false);
    });
  });

  group('UnityBannerAdWidget (point #10)', () {
    testWidgets('Pro active: the slot renders nothing', (tester) async {
      _setPro(active: true);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BannerAdWidget())),
      );
      expect(find.byType(UnityBannerAd), findsNothing);
    });

    testWidgets('Free: the slot renders the Unity banner',
        (tester) async {
      _setPro(active: false);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BannerAdWidget())),
      );
      expect(find.byType(UnityBannerAd), findsOneWidget);
    });

    testWidgets('Pro granted while visible: banner disappears live',
        (tester) async {
      _setPro(active: false);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BannerAdWidget())),
      );
      expect(find.byType(UnityBannerAd), findsOneWidget);
      // Simulate the refresh that grants Pro mid-session.
      _setPro(active: true);
      await tester.pump();
      expect(find.byType(UnityBannerAd), findsNothing);
      _setPro(active: false);
    });
  });
}
