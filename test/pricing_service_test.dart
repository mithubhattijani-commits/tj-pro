// Point #20 (2026-11-25) — CENTRAL REMOTE PRICING.
//
// Covers the pure value semantics of the system:
// - PriceSpec.parse: number / "pro" / "ad" / malformed inputs.
// - PricingService.spec: an absent key is FREE (never locks).
// - PricingService.specOr: a migrated point falls back to its
//   legacy price while its key is absent (behaviour unchanged).
// - PricingService.coinsOr: number-only table resolution.
// - RemoteConfig carries the `prices` object through fromJson
//   and the admin-banner copy, and degrades to an empty map.
// - AiToolCharge maps each ledger reason to its pricing key.

import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/services/ai_tool_charge.dart';
import 'package:tj_pro/services/pricing_service.dart';
import 'package:tj_pro/services/remote_config_service.dart';

RemoteConfig cfg(Map<String, dynamic> prices) =>
    RemoteConfig(prices: prices);

void main() {
  group('PriceSpec.parse', () {
    test('positive int is a coin price', () {
      expect(PriceSpec.parse(25), PriceSpec.coins(25));
      expect(PriceSpec.parse(1), PriceSpec.coins(1));
    });

    test('zero and negative numbers are FREE', () {
      expect(PriceSpec.parse(0), PriceSpec.free);
      expect(PriceSpec.parse(-50), PriceSpec.free);
    });

    test('integral double is a coin price; fractional is FREE', () {
      expect(PriceSpec.parse(40.0), PriceSpec.coins(40));
      expect(PriceSpec.parse(40.5), PriceSpec.free);
      expect(PriceSpec.parse(0.0), PriceSpec.free);
    });

    test('numeric string is a coin price', () {
      expect(PriceSpec.parse('30'), PriceSpec.coins(30));
      expect(PriceSpec.parse(' 15 '), PriceSpec.coins(15));
      expect(PriceSpec.parse('0'), PriceSpec.free);
    });

    test('"pro" and "ad" strings (any case, padded) map to kinds', () {
      expect(PriceSpec.parse('pro'), PriceSpec.proOnly);
      expect(PriceSpec.parse(' PRO '), PriceSpec.proOnly);
      expect(PriceSpec.parse('ad'), PriceSpec.adUnlock);
      expect(PriceSpec.parse('Ad'), PriceSpec.adUnlock);
    });

    test('malformed values are FREE — never a lock, never a price', () {
      expect(PriceSpec.parse(null), PriceSpec.free);
      expect(PriceSpec.parse(true), PriceSpec.free);
      expect(PriceSpec.parse(false), PriceSpec.free);
      expect(PriceSpec.parse('free'), PriceSpec.free);
      expect(PriceSpec.parse('coins please'), PriceSpec.free);
      expect(PriceSpec.parse(''), PriceSpec.free);
      expect(PriceSpec.parse(<int>[25]), PriceSpec.free);
      expect(
        PriceSpec.parse(<String, dynamic>{'coins': 25}),
        PriceSpec.free,
      );
    });

    test('absurd prices clamp to the 10000 guard', () {
      expect(PriceSpec.parse(999999), PriceSpec.coins(10000));
      expect(PriceSpec.parse('123456'), PriceSpec.coins(10000));
    });
  });

  group('PricingService.spec — absent means FREE', () {
    test('missing key in an empty prices map is free', () {
      expect(
        PricingService.spec('price_photo_ai', config: cfg(const {})),
        PriceSpec.free,
      );
    });

    test('missing key beside other keys is free', () {
      expect(
        PricingService.spec(
          'price_ns_chroma',
          config: cfg(const {'price_photo_ai': 25}),
        ),
        PriceSpec.free,
      );
    });

    test('present values resolve by kind', () {
      final config = cfg(const {
        'price_photo_ai': 40,
        'price_ns_voiceover': 'pro',
        'price_ns_one_click': 'ad',
        'price_ns_chroma': 0,
      });
      expect(
        PricingService.spec('price_photo_ai', config: config),
        PriceSpec.coins(40),
      );
      expect(
        PricingService.spec('price_ns_voiceover', config: config),
        PriceSpec.proOnly,
      );
      expect(
        PricingService.spec('price_ns_one_click', config: config),
        PriceSpec.adUnlock,
      );
      expect(
        PricingService.spec('price_ns_chroma', config: config),
        PriceSpec.free,
      );
    });
  });

  group('PricingService.specOr — migration fallback', () {
    test('absent key falls back to the legacy price', () {
      expect(
        PricingService.specOr(
          'price_photo_ai',
          fallbackCoins: 25,
          config: cfg(const {}),
        ),
        PriceSpec.coins(25),
      );
    });

    test('a configured value beats the fallback (incl. 0 = free)', () {
      final config = cfg(const {'price_photo_ai': 0});
      expect(
        PricingService.specOr(
          'price_photo_ai',
          fallbackCoins: 25,
          config: config,
        ),
        PriceSpec.free,
      );
    });

    test('a zero fallback with an absent key is free', () {
      expect(
        PricingService.specOr(
          'anything',
          fallbackCoins: 0,
          config: cfg(const {}),
        ),
        PriceSpec.free,
      );
    });
  });

  group('PricingService.coinsOr — price tables', () {
    test('absent key keeps the fallback', () {
      expect(
        PricingService.coinsOr('price_banner_booking_1h', 100,
            config: cfg(const {})),
        100,
      );
    });

    test('a configured number wins; 0 makes the row free', () {
      final config = cfg(const {
        'price_banner_booking_1h': 150,
        'price_banner_booking_2h': 0,
      });
      expect(
        PricingService.coinsOr('price_banner_booking_1h', 100,
            config: config),
        150,
      );
      expect(
        PricingService.coinsOr('price_banner_booking_2h', 200,
            config: config),
        0,
      );
    });

    test('"pro"/"ad" in a table keep the fallback (never break it)', () {
      final config = cfg(const {'price_banner_booking_4h': 'pro'});
      expect(
        PricingService.coinsOr('price_banner_booking_4h', 300,
            config: config),
        300,
      );
    });
  });

  group('RemoteConfig prices plumbing', () {
    test('fromJson carries the prices object raw', () {
      final config = RemoteConfig.fromJson(const {
        'prices': {'price_photo_ai': 25, 'price_ns_voiceover': 'pro'},
      });
      expect(config.prices['price_photo_ai'], 25);
      expect(config.prices['price_ns_voiceover'], 'pro');
    });

    test('absent or non-map prices degrade to an empty map', () {
      expect(RemoteConfig.fromJson(const {}).prices, isEmpty);
      expect(
        RemoteConfig.fromJson(const {'prices': 'nope'}).prices,
        isEmpty,
      );
      expect(
        RemoteConfig.fromJson(const {'prices': [1, 2]}).prices,
        isEmpty,
      );
    });

    test('the admin-banner copy preserves prices exactly', () {
      final base = cfg(const {'price_photo_ai': 25});
      final copy = base.withAdvertisingBanner(
        imageUrl: 'https://example.com/b.jpg',
        linkUrl: '',
      );
      expect(copy.prices, base.prices);
    });

    test('the shipped defaults reproduce today\'s prices', () {
      // The migration contract: with NO prices object anywhere,
      // every migrated point resolves to the price it charges
      // today (AI tools via the ai_tool_price_coins default).
      final empty = cfg(const {});
      expect(
        PricingService.specOr('price_photo_ai',
            fallbackCoins: RemoteConfig.aiToolPriceDefaultCoins,
            config: empty),
        PriceSpec.coins(25),
      );
      expect(
        PricingService.specOr('price_ns_voiceover',
            fallbackCoins: 50, config: empty),
        PriceSpec.coins(50),
      );
      expect(
        PricingService.specOr('price_ns_one_click',
            fallbackCoins: 100, config: empty),
        PriceSpec.coins(100),
      );
      expect(
        PricingService.specOr('price_ns_chroma',
            fallbackCoins: 50, config: empty),
        PriceSpec.coins(50),
      );
      expect(
        PricingService.specOr('price_logo_parts_save',
            fallbackCoins: 300, config: empty),
        PriceSpec.coins(300),
      );
    });
  });

  group('AiToolCharge key mapping', () {
    test('each ledger reason resolves through its own key', () {
      expect(
        AiToolCharge.priceKeyForReason(AiToolCharge.reasonCaptionGenerator),
        PricingService.keyVeCaptionGenerator,
      );
      expect(
        AiToolCharge.priceKeyForReason(AiToolCharge.reasonAutoCaptions),
        PricingService.keyVeAutoCaptions,
      );
      expect(
        AiToolCharge.priceKeyForReason(AiToolCharge.reasonPhotoAi),
        PricingService.keyPhotoAi,
      );
    });

    test('Motion template keys follow the registered pattern', () {
      expect(
        PricingService.keyMotionTemplate('breaking_intro_01'),
        'motion_price_breaking_intro_01',
      );
    });
  });
}
