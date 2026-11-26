// Phase 10 unit + widget tests: login/coins merge wiring — the
// export quality → coin mapping, the new RemoteConfig keys
// (advertising + on-demand asset URLs), the local-only coin ledger
// (load + daily claim + spend, no Supabase in tests), the
// hasCachedVoice cache check, and widget smoke tests for the new
// Advertise page, the CoinsPill and the LoginScreen.
//
// The coin gate is real: the paid-feature screens spend BEFORE they
// run, so the older Phase 4 / Phase 9 widget tests seed
// `CoinService.instance.balance` first (see those files).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tj_pro/news/advertise_screen.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/news/coins_screen.dart';
import 'package:tj_pro/news/export_screen.dart';
import 'package:tj_pro/news/login_screen.dart';
import 'package:tj_pro/news/news_project.dart';
import 'package:tj_pro/services/auth_service.dart';
import 'package:tj_pro/services/coin_service.dart';
import 'package:tj_pro/services/gemini_voice_service.dart';
import 'package:tj_pro/services/remote_config_service.dart';
import 'package:tj_pro/services/update_service.dart';
import 'package:tj_pro/widgets/coins_pill.dart';

/// Points path_provider at a plain path so the voice cache lookup
/// runs real dart:io (no cached file → false) without a device.
void _mockPathProvider() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return '/tmp/tj_pro_phase10_test';
      }
      return null;
    },
  );
}

/// Mocks flutter_secure_storage reads so RemoteConfigService.init()
/// finds a FRESH cached config and never attempts a real network
/// refresh inside tests.
void _mockSecureStorageFreshCache() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (MethodCall call) async {
      if (call.method == 'read') {
        final args = call.arguments;
        final key = args is Map ? args['key']?.toString() : null;
        if (key == 'tjpro_remote_config_json_v1') return '{}';
        if (key == 'tjpro_remote_config_time_v1') {
          return DateTime.now().millisecondsSinceEpoch.toString();
        }
      }
      return null;
    },
  );
}

void main() {
  group('coinFeatureForQuality (export pricing)', () {
    test('0 = 720p / 50 coins', () {
      expect(coinFeatureForQuality(0), CoinFeature.export720p);
      expect(CoinCosts.costFor(coinFeatureForQuality(0)), 50);
    });

    test('1 = 1080p / 100 coins', () {
      expect(coinFeatureForQuality(1), CoinFeature.export1080p);
      expect(CoinCosts.costFor(coinFeatureForQuality(1)), 100);
    });

    test('2 = 4K / 200 coins', () {
      expect(coinFeatureForQuality(2), CoinFeature.export4k);
      expect(CoinCosts.costFor(coinFeatureForQuality(2)), 200);
    });

    test('out-of-range quality falls back to 720p', () {
      expect(coinFeatureForQuality(99), CoinFeature.export720p);
      expect(coinFeatureForQuality(-1), CoinFeature.export720p);
    });
  });

  group('RemoteConfig advertising + asset keys', () {
    test('defaults when the JSON keys are absent', () {
      final config = RemoteConfig.fromJson(<String, dynamic>{});
      expect(config.advertisingBannerEnabled, isTrue);
      expect(
        config.advertisingBannerImageUrl,
        'assets/jaani_ad_banner.jpg',
      );
      expect(config.advertisingBannerPriceCoins, 200);
      expect(config.advertisingBannerDurationHours, 2);
      expect(config.kasheedaFontUrl, isEmpty);
      expect(config.nigraanIntroUrl, isEmpty);
      expect(config.logoMovUrl, isEmpty);
    });

    test('JSON values override the defaults', () {
      final config = RemoteConfig.fromJson(<String, dynamic>{
        'advertising_banner_enabled': false,
        'advertising_banner_image_url':
            'https://example.com/banner.png',
        'advertising_banner_price_coins': 500,
        'advertising_banner_duration_hours': 6,
        'kasheeda_font_url': 'https://example.com/kasheeda.ttf',
        'nigraan_intro_url': 'https://example.com/intro.mp4',
        'logo_mov_url': 'https://example.com/logo.mov',
      });
      expect(config.advertisingBannerEnabled, isFalse);
      expect(
        config.advertisingBannerImageUrl,
        'https://example.com/banner.png',
      );
      expect(config.advertisingBannerPriceCoins, 500);
      expect(config.advertisingBannerDurationHours, 6);
      expect(config.kasheedaFontUrl, 'https://example.com/kasheeda.ttf');
      expect(config.nigraanIntroUrl, 'https://example.com/intro.mp4');
      expect(config.logoMovUrl, 'https://example.com/logo.mov');
    });

    test('empty strings and bad ints fall back to defaults', () {
      final config = RemoteConfig.fromJson(<String, dynamic>{
        'advertising_banner_image_url': '   ',
        'advertising_banner_price_coins': 0,
        'advertising_banner_duration_hours': 'not-a-number',
        'kasheeda_font_url': '',
      });
      expect(
        config.advertisingBannerImageUrl,
        'assets/jaani_ad_banner.jpg',
      );
      expect(config.advertisingBannerPriceCoins, 200);
      expect(config.advertisingBannerDurationHours, 2);
      expect(config.kasheedaFontUrl, isEmpty);
    });
  });

  group('CoinService load + daily claim (local-only)', () {
    test('load reads the mocked balance; daily claim once per day',
        () async {
      _mockSecureStorageFreshCache();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tjpro_balance': 500,
      });
      await CoinService.instance.load();
      expect(CoinService.instance.balance.value, 500);

      expect(await CoinService.instance.claimDaily(), isTrue);
      expect(CoinService.instance.balance.value, 550);
      // Second claim the same day is refused — the mocked prefs
      // now hold today's claim date.
      expect(await CoinService.instance.claimDaily(), isFalse);
      expect(CoinService.instance.balance.value, 550);
    });
  });

  group('CoinService local-only spend', () {
    test('spend debits and reports the new balance', () async {
      CoinService.instance.balance.value = 1000;
      final result =
          await CoinService.instance.spend(CoinFeature.export1080p);
      expect(result.ok, isTrue);
      expect(result.balance, 900);
      expect(CoinService.instance.balance.value, 900);
    });

    test('spend refuses when the balance is too low', () async {
      CoinService.instance.balance.value = 30;
      final result =
          await CoinService.instance.spend(CoinFeature.export720p);
      expect(result.ok, isFalse);
      expect(result.error, 'insufficient_balance');
      expect(CoinService.instance.balance.value, 30);
    });

    test('canAfford follows the balance', () {
      CoinService.instance.balance.value = 100;
      expect(
        CoinService.instance.canAfford(CoinFeature.oneClick),
        isTrue,
      );
      expect(
        CoinService.instance.canAfford(CoinFeature.export4k),
        isFalse,
      );
    });

    test('spendAmount charges the exact amount given', () async {
      CoinService.instance.balance.value = 1000;
      final result = await CoinService.instance.spendAmount(
        25,
        reason: CoinCosts.reasonFor(CoinFeature.premiumTemplate),
      );
      expect(result.ok, isTrue);
      expect(CoinService.instance.balance.value, 975);
    });
  });

  group('GeminiVoiceService.hasCachedVoice', () {
    test('returns false (no throw) when nothing is cached', () async {
      _mockPathProvider();
      final cached = await GeminiVoiceService().hasCachedVoice(
        'شیخوپورہ میں پولیس نے بڑی کارروائی کی۔',
        voice: GeminiVoice.aoede,
      );
      expect(cached, isFalse);
    });

    test('server-fed admin flag exempts the 5/day cap', () async {
      // Phase 10 wiring: before it, _isAdmin read ONLY the
      // instance currentUserEmail, which production never set —
      // admins were wrongly capped. The flag is server-fed
      // (tjpro-is-admin); reset it so later tests see non-admin.
      AuthService.isAdmin.value = true;
      addTearDown(() => AuthService.isAdmin.value = false);
      // Build 7 (v1.5.9) repair: the unlimited sentinel is -1
      // (see GeminiVoiceService.remainingToday), not a huge
      // number — the expectation predates that change.
      expect(await GeminiVoiceService().remainingToday(), -1);
      expect(await GeminiVoiceService().usedToday(), 0);
    });
  });

  group('AdvertiseScreen widget', () {
    testWidgets('banner (BoxFit.contain) + WhatsApp + Watch Ads',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AdvertiseScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Advertise'), findsOneWidget);
      expect(find.text('Advertising banner'), findsOneWidget);
      // The banner image never crops: BoxFit.contain.
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.contain);
      expect(find.byKey(const Key('advertiseBookButton')), findsOneWidget);
      expect(
        find.byKey(const Key('advertiseReportButton')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('advertiseWatchAdsButton')),
        findsOneWidget,
      );
      expect(find.textContaining('Watch Ads, Earn Coins'), findsOneWidget);
      // Build 9 (v1.7.0, point #6A): the booking card no longer
      // shows the old single remote-config price (200 coins /
      // 2 hours via WhatsApp) — booking is in-app now with the
      // user-confirmed 100/200/300 table for 1/2/4 hours.
      expect(
        find.textContaining('100 coins / 1 hour, 200 / 2 hours'),
        findsOneWidget,
      );
    });
  });

  group('CoinsPill widget', () {
    testWidgets('shows the live balance and opens Coins on tap',
        (tester) async {
      AuthService.isAdmin.value = false;
      CoinService.instance.balance.value = 250;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: const [CoinsPill()]),
            body: const Text('home'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('coinsPill')), findsOneWidget);
      expect(find.byKey(const Key('coinsPillBalance')), findsOneWidget);
      expect(find.text('250'), findsOneWidget);

      await tester.tap(find.byKey(const Key('coinsPill')));
      await tester.pumpAndSettle();
      expect(find.text('Your balance'), findsOneWidget);
    });

    testWidgets('hidden for admins', (tester) async {
      AuthService.isAdmin.value = true;
      addTearDown(() => AuthService.isAdmin.value = false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: const [CoinsPill()]),
            body: const Text('home'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('coinsPill')), findsNothing);
    });
  });

  group('LoginScreen widget', () {
    testWidgets('Google + email + coins cards + For Help row',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            onSignedIn: () {},
            onContinueAsGuest: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Coins kaise kamayein'), findsOneWidget);
      // Build 7 repair: the "Admins — sab kuch free" card was
      // REMOVED from the app on the user's order (no admin notes
      // anywhere) — pin its absence instead of its presence.
      expect(find.text('Admins — sab kuch free, no coins, no ads'),
          findsNothing);
      expect(find.text('Continue as guest'), findsOneWidget);
      expect(
        find.text(
          'For Help — need any guideline? Message us on WhatsApp',
        ),
        findsOneWidget,
      );
      expect(find.text('03090808180'), findsOneWidget);
    });
  });

  group('CoinsScreen widget', () {
    testWidgets('balance card + Watch Ads + prices list',
        (tester) async {
      AuthService.isAdmin.value = false;
      CoinService.instance.balance.value = 250;
      await tester.pumpWidget(
        const MaterialApp(home: CoinsScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your balance'), findsOneWidget);
      expect(find.text('250'), findsOneWidget);
      expect(find.textContaining('Watch Ads, Earn Coins'), findsOneWidget);
      expect(find.text('Prices'), findsOneWidget);
      expect(find.text('One Click AI News Maker'), findsOneWidget);
      expect(find.text('Export 1080p'), findsOneWidget);
    });
  });

  group('UpdateService.updateInfoFromManifest (per-ABI)', () {
    const manifest = <String, dynamic>{
      'versionCode': 9,
      'versionName': '1.0.8',
      'url': 'https://example.com/tj-pro-arm64.apk',
      'urls': <String, dynamic>{
        'arm64-v8a': 'https://example.com/tj-pro-arm64.apk',
        'armeabi-v7a': 'https://example.com/tj-pro-armv7.apk',
        'x86_64': 'https://example.com/tj-pro-x86_64.apk',
      },
      'versionCodes': <String, dynamic>{
        'arm64-v8a': 2009,
        'armeabi-v7a': 1009,
        'x86_64': 4009,
      },
      'notes': 'News Studio v1',
    };

    test('arm64 picks 2009 + its own URL', () {
      final info = UpdateService.updateInfoFromManifest(
        manifest,
        abiNameOverride: 'arm64-v8a',
      );
      expect(info, isNotNull);
      expect(info!.versionCode, 2009);
      expect(info.url, 'https://example.com/tj-pro-arm64.apk');
      expect(info.versionName, '1.0.8');
    });

    test('armeabi-v7a picks 1009 + its own URL', () {
      final info = UpdateService.updateInfoFromManifest(
        manifest,
        abiNameOverride: 'armeabi-v7a',
      );
      expect(info, isNotNull);
      expect(info!.versionCode, 1009);
      expect(info.url, 'https://example.com/tj-pro-armv7.apk');
    });

    test('x86_64 picks 4009 + its own URL', () {
      final info = UpdateService.updateInfoFromManifest(
        manifest,
        abiNameOverride: 'x86_64',
      );
      expect(info, isNotNull);
      expect(info!.versionCode, 4009);
      expect(info.url, 'https://example.com/tj-pro-x86_64.apk');
    });

    test('unknown ABI falls back to the universal code + URL', () {
      final info = UpdateService.updateInfoFromManifest(
        manifest,
        abiNameOverride: 'mips',
      );
      expect(info, isNotNull);
      expect(info!.versionCode, 9);
      expect(info.url, 'https://example.com/tj-pro-arm64.apk');
    });

    test('manifest without per-ABI maps uses the universal entries',
        () {
      final info = UpdateService.updateInfoFromManifest(
        const <String, dynamic>{
          'versionCode': 8,
          'versionName': '1.0.7',
          'url': 'https://example.com/tj-pro.apk',
        },
        abiNameOverride: 'arm64-v8a',
      );
      expect(info, isNotNull);
      expect(info!.versionCode, 8);
      expect(info.url, 'https://example.com/tj-pro.apk');
    });

    test('missing URL (and no per-ABI URL) returns null', () {
      expect(
        UpdateService.updateInfoFromManifest(
          const <String, dynamic>{'versionCode': 9},
          abiNameOverride: 'arm64-v8a',
        ),
        isNull,
      );
    });

    test('real ABI on this VM is not an Android ABI → fallback', () {
      // On the VM Abi.current() is linux-x64, so currentAbiName()
      // is null and the universal entries win. The per-ABI branch
      // itself is the proven Magic Box pattern, verified on device
      // after the build (see the release-prep report).
      expect(UpdateService.currentAbiName(), isNull);
      final info = UpdateService.updateInfoFromManifest(manifest);
      expect(info, isNotNull);
      expect(info!.versionCode, 9);
    });
  });

  group('ExportScreen coin label', () {
    // Build 7 (v1.5.9) repair: resolution pricing was abolished
    // on the user's order (v1.2.0 — 720p/1080p/4K are FREE, ads
    // play alongside the export). The only remaining charge on
    // this button is chroma key (50). The old expectations
    // (50 for 720p, 100 with chroma) pin the abolished prices.
    testWidgets('button shows Free at 720p; chroma adds 50',
        (tester) async {
      final project = NewsProject(
        id: 'screen-coins',
        voiceoverDurationSec: 42,
        templateKind: 'nigraanFinal',
      );
      final preset = ChannelPreset.nigraanTv();
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(project: project, preset: preset),
        ),
      );
      await tester.pump();
      expect(find.text('Export • 720p • Free'), findsOneWidget);

      final chromaPreset = ChannelPreset.nigraanTv()
        ..chromaEnabled = true;
      await tester.pumpWidget(
        MaterialApp(
          home: ExportScreen(project: project, preset: chromaPreset),
        ),
      );
      await tester.pump();
      expect(find.text('Export • 720p • 50 coins'), findsOneWidget);
    });
  });
}
