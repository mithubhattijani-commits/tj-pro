// Phase 2 unit tests — pure logic only (no I/O, no platform channels):
// voice chunking/lang/admin rules, ribbon-content rule defaults,
// breaking-template defaults, JSON round-trips, WhatsApp/ad config.

import 'package:flutter_test/flutter_test.dart';

import 'package:tj_pro/app_config.dart';
import 'package:tj_pro/news/breaking_templates.dart';
import 'package:tj_pro/news/channel_preset.dart';
import 'package:tj_pro/services/gemini_voice_service.dart';

void main() {
  group('GeminiVoiceService.chunkText', () {
    test('short text stays one chunk', () {
      final chunks =
          GeminiVoiceService.chunkText('Hello world. Yeh ek test hai.');
      expect(chunks, hasLength(1));
      expect(chunks.first, contains('Hello world.'));
    });

    test('empty text gives no chunks', () {
      expect(GeminiVoiceService.chunkText('  '), isEmpty);
    });

    test('long text splits on sentence boundaries, never over 2000', () {
      final sentence = 'Yeh aik lambi khabar hai. ';
      final text = sentence * 120; // ~3000 chars
      final chunks = GeminiVoiceService.chunkText(text);
      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(2000));
      }
      expect(chunks.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
          text.replaceAll(RegExp(r'\s+'), ' ').trim());
    });

    test('Urdu full stop splits sentences', () {
      final chunks = GeminiVoiceService.chunkText(
        'Pehli khabar yeh hai۔ Doosri khabar woh hai۔',
      );
      expect(chunks, hasLength(1));
      expect(chunks.first, contains('Pehli khabar'));
    });
  });

  group('GeminiVoiceService.detectLang', () {
    test('Urdu script -> ur', () {
      expect(GeminiVoiceService.detectLang('یہ اردو خبر ہے'), 'ur');
    });
    test('English -> en', () {
      expect(GeminiVoiceService.detectLang('Breaking news from Lahore'),
          'en');
    });
  });

  group('GeminiVoiceService admin rule', () {
    test('the three admin emails are exempt', () {
      for (final email in [
        'mithubhattijani@gmail.com',
        'ghulamjillani019@gmail.com',
        'jaanirecords2@gmail.com',
      ]) {
        expect(GeminiVoiceService.isAdminEmail(email), isTrue);
      }
    });
    test('case-insensitive, others not admin', () {
      expect(
        GeminiVoiceService.isAdminEmail('MITHUBHATTIJANI@GMAIL.COM'),
        isTrue,
      );
      expect(GeminiVoiceService.isAdminEmail('someone@gmail.com'), isFalse);
      expect(GeminiVoiceService.isAdminEmail(null), isFalse);
    });
    test('admin remainingToday is unlimited without I/O', () async {
      final service = GeminiVoiceService()
        ..currentUserEmail = 'mithubhattijani@gmail.com';
      // Build 7 (v1.5.9) repair: the unlimited sentinel changed
      // when the Phase 10 server-fed admin flag landed — admins
      // now get -1 (documented on GeminiVoiceService.remaining-
      // Today and handled by every caller), not a huge number.
      expect(await service.remainingToday(), -1);
      expect(await service.usedToday(), 0);
    });
  });

  group('ChannelPreset — ribbon-content rule', () {
    test('Nigraan TV default: colours + content kinds + always rotate', () {
      final preset = ChannelPreset.nigraanTv();
      expect(preset.templateKind, 'nigraanFinal');
      // Build 7 repair: since v1.5.1 (fix #40) the built-in
      // preset's ribbons carry the declared-FINAL design colours
      // (yellow / red / navy), not the old factory scheme — the
      // factory colours survive only as the classic2 fallback in
      // finalDesignRibbonColor.
      expect(preset.tickerColor, kFinal3TopColor);
      expect(preset.urduColor, kFinal3UrduColor);
      expect(preset.englishColor, kFinal3EnglishColor);
      expect(preset.topRibbon.contentKind, RibbonContentKind.current);
      expect(preset.urduRibbon.contentKind, RibbonContentKind.national);
      expect(
        preset.englishRibbon.contentKind,
        RibbonContentKind.international,
      );
      expect(preset.logoRotate, isTrue);
      expect(preset.showTicker, isTrue);
      expect(preset.showUrdu, isTrue);
      expect(preset.showEnglish, isTrue);
    });

    test('RibbonConfig JSON round-trip preserves every field', () {
      final ribbon = RibbonConfig(
        text: 'تازہ ترین خبر',
        color: 0xFF123456,
        speed: 1.5,
        direction: RibbonDirection.ltr,
        fontSize: 22,
        enabled: false,
        contentKind: RibbonContentKind.national,
      );
      final restored = RibbonConfig.fromJson(ribbon.toJson());
      expect(restored.text, ribbon.text);
      expect(restored.color, ribbon.color);
      expect(restored.speed, ribbon.speed);
      expect(restored.direction, ribbon.direction);
      expect(restored.fontSize, ribbon.fontSize);
      expect(restored.enabled, ribbon.enabled);
      expect(restored.contentKind, ribbon.contentKind);
    });

    test('ChannelPreset JSON round-trip preserves ribbons + logoRotate', () {
      final preset = ChannelPreset.nigraanTv()
        ..topRibbon.text = 'Current story ticker'
        ..urduRibbon.text = 'قومی خبریں'
        ..logoPath = '/tmp/logo.png';
      final restored = ChannelPreset.fromJson(preset.toJson());
      expect(restored.topRibbon.text, 'Current story ticker');
      expect(restored.urduRibbon.text, 'قومی خبریں');
      expect(restored.urduRibbon.contentKind, RibbonContentKind.national);
      expect(restored.logoPath, '/tmp/logo.png');
      expect(restored.logoRotate, isTrue);
    });
  });

  group('BreakingTemplate', () {
    test('four v1 defaults with the right coin costs', () {
      final defaults = BreakingTemplate.defaults();
      expect(defaults, hasLength(4));
      expect(defaults[0].variant, BreakingVariant.breakingRedBanner);
      expect(defaults[0].coinCost, 0);
      expect(defaults[0].isFree, isTrue);
      expect(defaults[1].variant, BreakingVariant.latestNews);
      expect(defaults[1].coinCost, 25);
      expect(defaults[2].variant, BreakingVariant.topHeadlineBar);
      expect(defaults[2].coinCost, 25);
      expect(defaults[3].variant, BreakingVariant.breakingTickerCombo);
      expect(defaults[3].coinCost, 25);
    });

    test('combo follows the ribbon-content rule', () {
      final combo = BreakingTemplate.defaults()[3];
      expect(combo.topContentKind, RibbonContentKind.current);
      expect(combo.middleContentKind, RibbonContentKind.national);
      expect(combo.bottomContentKind, RibbonContentKind.international);
      expect(combo.topColor, 0xFFD50000);
      expect(combo.middleColor, 0xFF3D5AFE);
      expect(combo.bottomColor, 0xFFEF0017);
      expect(combo.logoRotate, isTrue);
    });

    test('JSON round-trip preserves custom-template fields', () {
      final template = BreakingTemplate(
        variant: BreakingVariant.latestNews,
        headline: 'Test headline',
        tickerText: 'Test ticker',
        name: 'My Custom',
        isCustom: true,
        id: 'custom_123',
        logoPath: '/tmp/logo.png',
        logoRotate: true,
        showIntro: false,
      );
      final restored = BreakingTemplate.fromJson(template.toJson());
      expect(restored.id, 'custom_123');
      expect(restored.name, 'My Custom');
      expect(restored.isCustom, isTrue);
      expect(restored.displayName, 'My Custom');
      expect(restored.logoPath, '/tmp/logo.png');
      expect(restored.showIntro, isFalse);
    });

    test('built-ins show the variant label as display name', () {
      expect(BreakingTemplate.defaults()[0].displayName,
          'Breaking Red Banner');
    });
  });

  group('AppConfig — WhatsApp help + advertising banner', () {
    test('wa.me link builder converts the local number', () {
      expect(AppConfig.waLinkFor('03090808180'),
          'https://wa.me/923090808180');
      expect(AppConfig.waLinkFor('+92 309 0808180'),
          'https://wa.me/923090808180');
      expect(AppConfig.waLinkFor('923090808180'),
          'https://wa.me/923090808180');
    });
    test('support number + link defaults', () {
      expect(AppConfig.supportWhatsAppNumber, '03090808180');
      expect(
        AppConfig.supportWhatsAppLink,
        'https://wa.me/923090808180',
      );
    });
    test('advertising banner config (200 coins / 2h)', () {
      expect(AppConfig.advertisingBannerEnabled, isTrue);
      expect(AppConfig.advertisingBannerPriceCoins, 200);
      expect(AppConfig.advertisingBannerDurationHours, 2);
    });
    test('on-demand asset URLs are empty until hosted (never fake)', () {
      expect(AppConfig.kasheedaFontUrl, isEmpty);
      expect(AppConfig.nigraanIntroUrl, isEmpty);
    });
    test('News Studio switch defaults on', () {
      expect(AppConfig.newsStudioEnabled, isTrue);
    });
  });
}
