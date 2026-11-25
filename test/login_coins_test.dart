// Unit tests for the Login + Coins track (News Studio v1).
//
// Pure-logic tests only: no network, no Supabase init, no Unity Ads.
// They pin the §15 coin pricing table, the WhatsApp link derivation,
// the remote-config defaults, and the email validation used by the
// login screen.

import 'package:flutter_test/flutter_test.dart';
import 'package:tj_pro/services/auth_service.dart';
import 'package:tj_pro/services/coin_service.dart';
import 'package:tj_pro/services/remote_config_service.dart';
import 'package:tj_pro/services/supabase_service.dart';
import 'package:tj_pro/widgets/help_whatsapp_button.dart';

void main() {
  group('CoinCosts (§15 pricing table)', () {
    test('earn constants', () {
      // Build 10 (v1.8.0): the per-ad reward dropped to 25
      // (user order 2026-11-25; the server-side
      // tjpro_reward_coins value the claim function pays).
      // The 50/day cap counts ADS, not coins, and the daily
      // free claim is a separate 50 — both unchanged.
      expect(CoinService.rewardPerAd, 25);
      expect(CoinService.dailyFreeCoins, 50);
      // The cap is 50 ads/day (the user's ads spec, also the
      // server-side tjpro_reward_daily_cap) — this expectation
      // still said 20/1000 from the first draft of the plan.
      expect(CoinService.maxRewardedAdsPerDay, 50);
      expect(CoinService.maxAdCoinsPerDay, 1250);
    });

    test('spend costs match the plan', () {
      expect(CoinCosts.costFor(CoinFeature.oneClick), 100);
      expect(CoinCosts.costFor(CoinFeature.voiceover), 50);
      expect(CoinCosts.costFor(CoinFeature.export720p), 50);
      expect(CoinCosts.costFor(CoinFeature.export1080p), 100);
      expect(CoinCosts.costFor(CoinFeature.export4k), 200);
      expect(CoinCosts.costFor(CoinFeature.chromaKey), 50);
      expect(CoinCosts.costFor(CoinFeature.premiumTemplate), 25);
      expect(
        CoinCosts.costFor(CoinFeature.multiPlatformPublish),
        100,
      );
      expect(CoinCosts.costFor(CoinFeature.aiEnhance), 50);
      expect(CoinCosts.costFor(CoinFeature.autoCaptions), 25);
    });

    test('every feature has a reason and a label', () {
      for (final feature in CoinFeature.values) {
        expect(CoinCosts.reasonFor(feature), isNotEmpty);
        expect(CoinCosts.labelFor(feature), isNotEmpty);
      }
    });

    test('spend reasons are distinct', () {
      final reasons =
          CoinFeature.values.map(CoinCosts.reasonFor).toSet();
      expect(reasons.length, CoinFeature.values.length);
    });
  });

  group('SupportContact WhatsApp link', () {
    test('03090808180 -> wa.me/923090808180', () {
      expect(
        SupportContact.waMeUrl('03090808180'),
        'https://wa.me/923090808180',
      );
    });

    test('already-international number is kept', () {
      expect(
        SupportContact.waMeUrl('923090808180'),
        'https://wa.me/923090808180',
      );
    });

    test('spaces and dashes are stripped', () {
      expect(
        SupportContact.waMeUrl('0309-080 8180'),
        'https://wa.me/923090808180',
      );
    });

    test('default number is the support number', () {
      expect(SupportContact.waMeUrl(), 'https://wa.me/923090808180');
    });
  });

  group('RemoteConfig coins/help fields', () {
    test('defaults when the JSON keys are absent', () {
      final config = RemoteConfig.fromJson(<String, dynamic>{});
      expect(config.supportWhatsAppNumber, '03090808180');
      expect(config.rewardedCoinsPlacementId, 'rewarded_coins');
    });

    test('JSON values override the defaults', () {
      final config = RemoteConfig.fromJson(<String, dynamic>{
        'support_whatsapp_number': '03000000000',
        'unity_rewarded_coins_placement_id': 'rewarded_coins_v2',
      });
      expect(config.supportWhatsAppNumber, '03000000000');
      expect(config.rewardedCoinsPlacementId, 'rewarded_coins_v2');
    });

    test('empty JSON strings fall back to defaults', () {
      final config = RemoteConfig.fromJson(<String, dynamic>{
        'support_whatsapp_number': '  ',
        'unity_rewarded_coins_placement_id': '',
      });
      expect(config.supportWhatsAppNumber, '03090808180');
      expect(config.rewardedCoinsPlacementId, 'rewarded_coins');
    });
  });

  group('AuthService.isValidEmail', () {
    test('accepts normal addresses', () {
      expect(AuthService.isValidEmail('mithu@example.com'), isTrue);
      expect(
        AuthService.isValidEmail('  ghulamjillani019@gmail.com  '),
        isTrue,
      );
    });

    test('rejects malformed addresses', () {
      expect(AuthService.isValidEmail(''), isFalse);
      expect(AuthService.isValidEmail('not-an-email'), isFalse);
      expect(AuthService.isValidEmail('a@b'), isFalse);
      expect(AuthService.isValidEmail('a@@b.com'), isFalse);
      expect(AuthService.isValidEmail('a b@c.com'), isFalse);
      expect(AuthService.isValidEmail('@example.com'), isFalse);
    });
  });

  group('Admin emails (display list)', () {
    test('the three admin emails are listed', () {
      expect(
        SupabaseService.adminEmails,
        containsAll(<String>[
          'mithubhattijani@gmail.com',
          'ghulamjillani019@gmail.com',
          'jaanirecords2@gmail.com',
        ]),
      );
      expect(SupabaseService.adminEmails.length, 3);
    });
  });

  group('CoinLedgerEntry parsing', () {
    test('server rows parse (ref_id as reason)', () {
      final entry = CoinLedgerEntry.fromServerJson(<String, dynamic>{
        'amount_coins': 50,
        'type': 'tjpro_reward',
        'ref_id': 'placement:rewarded_coins',
        'created_at': '2026-11-20T10:00:00Z',
      });
      expect(entry, isNotNull);
      expect(entry!.amountCoins, 50);
      expect(entry.isEarn, isTrue);
      expect(entry.reason, 'placement:rewarded_coins');
    });

    test('spend rows are negative and not earn', () {
      final entry = CoinLedgerEntry.fromServerJson(<String, dynamic>{
        'amount_coins': -100,
        'type': 'tjpro_spend',
        'ref_id': 'export_1080p',
        'created_at': '2026-11-20T10:00:00Z',
      });
      expect(entry, isNotNull);
      expect(entry!.isEarn, isFalse);
    });

    test('malformed rows return null', () {
      expect(
        CoinLedgerEntry.fromServerJson(<String, dynamic>{
          'amount_coins': 'fifty',
          'created_at': '2026-11-20T10:00:00Z',
        }),
        isNull,
      );
    });

    test('local JSON round-trips', () {
      final original = CoinLedgerEntry(
        amountCoins: -25,
        type: 'tjpro_spend',
        reason: 'premium_template',
        createdAt: DateTime.utc(2026, 11, 20, 10, 0),
      );
      final parsed = CoinLedgerEntry.fromJson(original.toJson());
      expect(parsed, isNotNull);
      expect(parsed!.amountCoins, -25);
      expect(parsed.reason, 'premium_template');
      expect(parsed.createdAt, original.createdAt);
    });
  });
}
