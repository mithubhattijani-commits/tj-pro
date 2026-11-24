/// Remote Config — server-driven in-app content (v1).
///
/// The app fetches a small JSON from nigraantv.xyz at cold start with
/// an 8-second timeout, caches the last-good JSON in the platform
/// secure store with a timestamp, and re-fetches when the cache is
/// older than 6 hours (or missing).
///
/// Order: network -> cache -> bundled defaults. Never blocks startup,
/// never an infinite spinner, never a crash — on any failure the app
/// just uses what it has. UI listens to [notifier] so a fresh fetch
/// updates the screen without a restart.
///
/// ADVERTISING-BANNER OVERRIDE (v1.2.0): after the config above
/// resolves, the service also tries the Supabase table
/// `tjpro_admin_banner` (single row, id = 1). When that row exists
/// with `enabled = true` and a non-empty `image_url`, it OVERRIDES
/// `advertisingBannerImageUrl` and provides
/// `advertisingBannerLinkUrl` — so an admin can set/change the
/// house-ad banner (image + link) from inside the app with NO new
/// build. Precedence: Supabase override > remote JSON > bundled
/// defaults. Any Supabase failure silently keeps the JSON/default
/// banner. Editor: lib/news/admin_banner_screen.dart.
///
/// NOTE: the reference design uses shared_preferences, but the cache
/// lives in flutter_secure_storage (already a direct dependency, used
/// for Live Studio stream keys) — deliberately, so the remote-config
/// cache never migrates stores. shared_preferences IS a dependency
/// now (Phase 10, coin balance cache) but this cache stays put.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app_config.dart';
import 'crash_guard.dart';
import 'supabase_service.dart';

class AnnouncementConfig {
  const AnnouncementConfig({this.enabled = false, this.text = ''});

  final bool enabled;
  final String text;

  bool get show => enabled && text.trim().isNotEmpty;

  factory AnnouncementConfig.fromJson(Map<String, dynamic> json) {
    return AnnouncementConfig(
      enabled: json['enabled'] == true,
      text: (json['text'] ?? '').toString(),
    );
  }
}

class SponsoredAdConfig {
  const SponsoredAdConfig({
    this.enabled = false,
    this.title = '',
    this.imageUrl = '',
    this.actionUrl = '',
  });

  final bool enabled;
  final String title;
  final String imageUrl;
  final String actionUrl;

  bool get show =>
      enabled && title.trim().isNotEmpty && actionUrl.trim().isNotEmpty;

  factory SponsoredAdConfig.fromJson(Map<String, dynamic> json) {
    return SponsoredAdConfig(
      enabled: json['enabled'] == true,
      title: (json['title'] ?? '').toString(),
      imageUrl: (json['image_url'] ?? '').toString(),
      actionUrl: (json['action_url'] ?? '').toString(),
    );
  }
}

class ForceUpdateConfig {
  const ForceUpdateConfig({this.enabled = false, this.minVersionCode = 0});

  final bool enabled;
  final int minVersionCode;

  factory ForceUpdateConfig.fromJson(Map<String, dynamic> json) {
    final dynamic raw = json['min_version_code'];
    final int code = raw is int ? raw : int.tryParse('$raw') ?? 0;
    return ForceUpdateConfig(
      enabled: json['enabled'] == true,
      minVersionCode: code,
    );
  }
}

class RemoteConfig {
  const RemoteConfig({
    this.displayName = '',
    this.logoUrl = '',
    this.announcement = const AnnouncementConfig(),
    this.sponsoredAd = const SponsoredAdConfig(),
    this.forceUpdate = const ForceUpdateConfig(),
    this.supportWhatsAppNumber = AppConfig.supportWhatsAppNumber,
    this.rewardedCoinsPlacementId =
        AppConfig.unityRewardedCoinsPlacementId,
    this.advertisingBannerEnabled = AppConfig.advertisingBannerEnabled,
    this.advertisingBannerImageUrl =
        AppConfig.advertisingBannerImageUrl,
    this.advertisingBannerLinkUrl = '',
    this.advertisingBannerPriceCoins =
        AppConfig.advertisingBannerPriceCoins,
    this.advertisingBannerDurationHours =
        AppConfig.advertisingBannerDurationHours,
    this.heroBanner1Url = '',
    this.heroBanner1Link = heroBanner1DefaultLink,
    this.heroBanner2Url = '',
    this.heroBanner2Link = '',
    this.kasheedaFontUrl = AppConfig.kasheedaFontUrl,
    this.nigraanIntroUrl = AppConfig.nigraanIntroUrl,
    this.logoMovUrl = AppConfig.logoMovUrl,
    this.easypaisaNumber = AppConfig.proEasypaisaNumber,
    this.easypaisaTitle = AppConfig.proEasypaisaTitle,
    this.ablAccount = AppConfig.proAblAccount,
    this.ablTitle = AppConfig.proAblTitle,
    this.jazzcashNumber = AppConfig.proJazzcashNumber,
  });

  final String displayName;
  final String logoUrl;
  final AnnouncementConfig announcement;
  final SponsoredAdConfig sponsoredAd;
  final ForceUpdateConfig forceUpdate;

  /// WhatsApp help number (display form, e.g. '03090808180').
  /// JSON key `support_whatsapp_number` in tj-pro.json; falls back to
  /// [AppConfig.supportWhatsAppNumber] when absent.
  final String supportWhatsAppNumber;

  /// Unity rewarded placement that pays coins (News Studio earning).
  /// JSON key `unity_rewarded_coins_placement_id` in tj-pro.json;
  /// falls back to [AppConfig.unityRewardedCoinsPlacementId].
  final String rewardedCoinsPlacementId;

  /// Advertise page (dedicated page, NOT home slots) — admin-panel
  /// controlled via tj-pro.json. Keys: `advertising_banner_enabled` /
  /// `advertising_banner_image_url` /
  /// `advertising_banner_price_coins` /
  /// `advertising_banner_duration_hours`. All fall back to the
  /// [AppConfig] defaults when absent.
  final bool advertisingBannerEnabled;
  final String advertisingBannerImageUrl;

  /// Where tapping the Advertise-page banner goes. Empty (the
  /// default) means "unset": the banner tap then keeps its original
  /// behaviour (no action). JSON key `advertising_banner_link_url`
  /// in tj-pro.json may set it, and the Supabase admin banner
  /// override (see [RemoteConfigService]) replaces it when active.
  final String advertisingBannerLinkUrl;
  final int advertisingBannerPriceCoins;
  final int advertisingBannerDurationHours;

  // --- Build 7 (v1.5.9, FIX C): Home hero banners, remote ------
  // Both hero carousel slides are changeable WITHOUT a new build
  // via tj-pro.json. The keys are purely additive: old app
  // versions ignore them, and this version keeps today's
  // behaviour when they are absent or empty.

  /// Hero slide 1 (the user's Nigraan TV banner) remote image.
  /// JSON key `hero_banner_1_url`. Empty (the default) = the
  /// bundled `assets/hero_nigraan_banner.jpg`, exactly as before;
  /// non-empty = that remote image, cached on-device by
  /// HeroBannerCache with the bundled asset as the never-blank
  /// fallback. Cover fit, unchanged.
  final String heroBanner1Url;

  /// Hero slide 1 tap target. JSON key `hero_banner_1_link`.
  /// Defaults to the Nigraan TV website — the slide's original
  /// behaviour.
  final String heroBanner1Link;

  /// Hero slide 2 (the admin house-ad banner) remote image.
  /// JSON key `hero_banner_2_url`. When non-empty it OVERRIDES
  /// the older advertising-banner chain FOR THE HERO SLIDE (see
  /// [heroBanner2ImageUrl]); when empty, the existing chain —
  /// Supabase override > `advertising_banner_image_url` >
  /// bundled default — decides, exactly as before. The
  /// Advertise page is untouched either way.
  final String heroBanner2Url;

  /// Hero slide 2 tap target. JSON key `hero_banner_2_link`.
  /// When non-empty it overrides [advertisingBannerLinkUrl] for
  /// the hero slide; empty = the advertising link (which itself
  /// defaults to "unset" = no tap handler, as today).
  final String heroBanner2Link;

  /// Default tap target of hero slide 1 (the website).
  static const String heroBanner1DefaultLink = 'https://nigraantv.xyz';

  /// Effective slide-1 image URL; empty = bundled asset.
  String get heroBanner1ImageUrl => heroBanner1Url.trim();

  /// Effective slide-1 tap target (never empty).
  String get heroBanner1TapUrl {
    final String link = heroBanner1Link.trim();
    return link.isEmpty ? heroBanner1DefaultLink : link;
  }

  /// Effective slide-2 image: the hero-2 override when set,
  /// else the existing advertising-banner chain.
  String get heroBanner2ImageUrl {
    final String url = heroBanner2Url.trim();
    return url.isNotEmpty ? url : advertisingBannerImageUrl;
  }

  /// Effective slide-2 tap target: the hero-2 override when
  /// set, else the advertising link.
  String get heroBanner2TapUrl {
    final String link = heroBanner2Link.trim();
    return link.isNotEmpty ? link : advertisingBannerLinkUrl;
  }

  /// Copy with ONLY the banner image + link replaced (the Supabase
  /// admin-banner override path). Every other value is preserved
  /// exactly, so the override can never disturb unrelated config.
  RemoteConfig withAdvertisingBanner({
    required String imageUrl,
    required String linkUrl,
  }) {
    return RemoteConfig(
      displayName: displayName,
      logoUrl: logoUrl,
      announcement: announcement,
      sponsoredAd: sponsoredAd,
      forceUpdate: forceUpdate,
      supportWhatsAppNumber: supportWhatsAppNumber,
      rewardedCoinsPlacementId: rewardedCoinsPlacementId,
      advertisingBannerEnabled: advertisingBannerEnabled,
      advertisingBannerImageUrl: imageUrl,
      advertisingBannerLinkUrl: linkUrl,
      advertisingBannerPriceCoins: advertisingBannerPriceCoins,
      advertisingBannerDurationHours: advertisingBannerDurationHours,
      heroBanner1Url: heroBanner1Url,
      heroBanner1Link: heroBanner1Link,
      heroBanner2Url: heroBanner2Url,
      heroBanner2Link: heroBanner2Link,
      kasheedaFontUrl: kasheedaFontUrl,
      nigraanIntroUrl: nigraanIntroUrl,
      logoMovUrl: logoMovUrl,
      easypaisaNumber: easypaisaNumber,
      easypaisaTitle: easypaisaTitle,
      ablAccount: ablAccount,
      ablTitle: ablTitle,
      jazzcashNumber: jazzcashNumber,
    );
  }

  /// On-demand asset URLs (Kasheeda font / Nigraan intro / rotating
  /// logo mov). JSON keys `kasheeda_font_url` / `nigraan_intro_url` /
  /// `logo_mov_url`; empty means "not hosted yet" (same rule as the
  /// [AppConfig] defaults — never a placeholder URL).
  final String kasheedaFontUrl;
  final String nigraanIntroUrl;
  final String logoMovUrl;

  /// TJ Pro PRO payment details (v1.4.0) — shown on the Pro screen
  /// (lib/news/pro_screen.dart) so a user can pay manually and send
  /// the screenshot on WhatsApp. JSON keys `pro_easypaisa_number` /
  /// `pro_easypaisa_title` / `pro_abl_account` / `pro_abl_title` /
  /// `pro_jazzcash_number` in tj-pro.json; every field falls back to
  /// the [AppConfig] Pro defaults when absent, so the numbers can
  /// change without a rebuild. [jazzcashNumber] is EMPTY until
  /// JazzCash is added — the Pro screen shows its JazzCash line only
  /// when this is non-empty.
  final String easypaisaNumber;
  final String easypaisaTitle;
  final String ablAccount;
  final String ablTitle;
  final String jazzcashNumber;

  static const RemoteConfig defaults = RemoteConfig();

  factory RemoteConfig.fromJson(Map<String, dynamic> json) {
    return RemoteConfig(
      displayName: (json['display_name'] ?? '').toString(),
      logoUrl: (json['logo_url'] ?? '').toString(),
      announcement: AnnouncementConfig.fromJson(
        _stringMap(json['announcement']),
      ),
      sponsoredAd: SponsoredAdConfig.fromJson(
        _stringMap(json['sponsored_ad']),
      ),
      forceUpdate: ForceUpdateConfig.fromJson(
        _stringMap(json['force_update']),
      ),
      supportWhatsAppNumber: _nonEmptyString(
        json['support_whatsapp_number'],
        AppConfig.supportWhatsAppNumber,
      ),
      rewardedCoinsPlacementId: _nonEmptyString(
        json['unity_rewarded_coins_placement_id'],
        AppConfig.unityRewardedCoinsPlacementId,
      ),
      advertisingBannerEnabled:
          json['advertising_banner_enabled'] is bool
              ? json['advertising_banner_enabled'] as bool
              : AppConfig.advertisingBannerEnabled,
      advertisingBannerImageUrl: _nonEmptyString(
        json['advertising_banner_image_url'],
        AppConfig.advertisingBannerImageUrl,
      ),
      // Unlike the image URL there is no bundled fallback for the
      // link: absent/empty in JSON simply means "unset".
      advertisingBannerLinkUrl:
          (json['advertising_banner_link_url'] ?? '').toString().trim(),
      advertisingBannerPriceCoins: _nonEmptyInt(
        json['advertising_banner_price_coins'],
        AppConfig.advertisingBannerPriceCoins,
      ),
      advertisingBannerDurationHours: _nonEmptyInt(
        json['advertising_banner_duration_hours'],
        AppConfig.advertisingBannerDurationHours,
      ),
      // FIX C hero keys: absent/empty keeps today's behaviour
      // (slide 1 = bundled asset + website tap; slide 2 = the
      // advertising chain).
      heroBanner1Url: (json['hero_banner_1_url'] ?? '').toString().trim(),
      heroBanner1Link: _nonEmptyString(
        json['hero_banner_1_link'],
        heroBanner1DefaultLink,
      ),
      heroBanner2Url: (json['hero_banner_2_url'] ?? '').toString().trim(),
      heroBanner2Link:
          (json['hero_banner_2_link'] ?? '').toString().trim(),
      kasheedaFontUrl: _nonEmptyString(
        json['kasheeda_font_url'],
        AppConfig.kasheedaFontUrl,
      ),
      nigraanIntroUrl: _nonEmptyString(
        json['nigraan_intro_url'],
        AppConfig.nigraanIntroUrl,
      ),
      logoMovUrl: _nonEmptyString(
        json['logo_mov_url'],
        AppConfig.logoMovUrl,
      ),
      easypaisaNumber: _nonEmptyString(
        json['pro_easypaisa_number'],
        AppConfig.proEasypaisaNumber,
      ),
      easypaisaTitle: _nonEmptyString(
        json['pro_easypaisa_title'],
        AppConfig.proEasypaisaTitle,
      ),
      ablAccount: _nonEmptyString(
        json['pro_abl_account'],
        AppConfig.proAblAccount,
      ),
      ablTitle: _nonEmptyString(
        json['pro_abl_title'],
        AppConfig.proAblTitle,
      ),
      // No bundled JazzCash number exists yet: absent/empty in JSON
      // simply stays empty (JazzCash not offered).
      jazzcashNumber:
          (json['pro_jazzcash_number'] ?? AppConfig.proJazzcashNumber)
              .toString()
              .trim(),
    );
  }

  static String _nonEmptyString(dynamic value, String fallback) {
    final String text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  static int _nonEmptyInt(dynamic value, int fallback) {
    if (value is int && value > 0) return value;
    final parsed = int.tryParse('${value ?? ''}');
    return parsed != null && parsed > 0 ? parsed : fallback;
  }

  static Map<String, dynamic> _stringMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return <String, dynamic>{};
  }
}

class RemoteConfigService {
  /// TJ Pro remote-config endpoint (live on nigraantv.xyz).
  static const String configUrl =
      'https://nigraantv.xyz/apps/config/tj-pro.json';

  /// Shared instance for services that need remote config without
  /// going through main.dart's own instance (e.g. CoinService for the
  /// rewarded-coins placement ID, the login screen for the WhatsApp
  /// help number). Both instances read the same cache + URL, so their
  /// values converge; call [init] before relying on fresh values.
  static final RemoteConfigService instance = RemoteConfigService();

  static const Duration fetchTimeout = Duration(seconds: 8);
  static const Duration refreshInterval = Duration(hours: 6);
  static const String _cacheKey = 'tjpro_remote_config_json_v1';
  static const String _cacheTimeKey = 'tjpro_remote_config_time_v1';

  /// Supabase single-row table holding the ADMIN house-ad banner
  /// override (see lib/news/admin_banner_screen.dart for the one-time
  /// CREATE TABLE + RLS SQL the owner runs in the SQL editor).
  static const String adminBannerTable = 'tjpro_admin_banner';

  /// The one config row in [adminBannerTable].
  static const int adminBannerRowId = 1;

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  final ValueNotifier<RemoteConfig> notifier =
      ValueNotifier<RemoteConfig>(RemoteConfig.defaults);

  RemoteConfig get config => notifier.value;

  /// Last config resolved from cache / network / bundled defaults,
  /// WITHOUT the Supabase admin-banner override. The override is
  /// always applied on top of this in [_publish], so a later refresh
  /// can never lose it and clearing it restores these values exactly.
  RemoteConfig _baseConfig = RemoteConfig.defaults;

  /// Active Supabase banner override (null = no override). Set only
  /// when the `tjpro_admin_banner` row exists with `enabled == true`
  /// and a non-empty `image_url`.
  String? _adminBannerImageUrl;
  String _adminBannerLinkUrl = '';

  /// Publish [base] as the current config, with the active Supabase
  /// admin-banner override (if any) applied on top. Precedence:
  /// Supabase override > remote JSON (network/cache) > bundled
  /// [AppConfig] defaults.
  void _publish(RemoteConfig base) {
    _baseConfig = base;
    final String? image = _adminBannerImageUrl;
    notifier.value = image == null
        ? base
        : base.withAdvertisingBanner(
            imageUrl: image,
            linkUrl: _adminBannerLinkUrl,
          );
  }

  /// Apply (or clear) the admin-banner override locally and
  /// re-publish at once. Called by the admin banner editor after a
  /// successful Supabase save, so the Advertise page reflects the new
  /// banner without an app restart. Same rule as the server read:
  /// only an enabled override with a non-empty image takes over;
  /// anything else clears the override and the remote-JSON/default
  /// banner comes back.
  void applyAdminBannerOverride({
    required bool enabled,
    required String imageUrl,
    required String linkUrl,
  }) {
    final String image = imageUrl.trim();
    if (enabled && image.isNotEmpty) {
      _adminBannerImageUrl = image;
      _adminBannerLinkUrl = linkUrl.trim();
    } else {
      _adminBannerImageUrl = null;
      _adminBannerLinkUrl = '';
    }
    _publish(_baseConfig);
  }

  /// Best-effort Supabase read of the admin banner override. Runs
  /// after the remote-JSON config resolves (cache load + every
  /// network refresh). ANY failure — Supabase not initialized, table
  /// missing, offline, RLS denial, timeout — silently keeps the
  /// existing remote-JSON/default values: no crash and no behaviour
  /// change for anyone. When the read succeeds, a missing / disabled
  /// / imageless row clears the override (Supabase is authoritative
  /// when reachable); an enabled row with a non-empty image sets it.
  Future<void> _fetchAdminBannerOverride() async {
    try {
      if (!SupabaseService.isInitialized) return;
      final Map<String, dynamic>? row = await SupabaseService.client
          .from(adminBannerTable)
          .select('image_url, link_url, enabled')
          .eq('id', adminBannerRowId)
          .maybeSingle()
          .timeout(fetchTimeout);
      if (row == null) {
        applyAdminBannerOverride(
          enabled: false,
          imageUrl: '',
          linkUrl: '',
        );
        return;
      }
      applyAdminBannerOverride(
        enabled: row['enabled'] == true,
        imageUrl: (row['image_url'] ?? '').toString(),
        linkUrl: (row['link_url'] ?? '').toString(),
      );
    } catch (e, s) {
      // Fail-soft: keep the remote-JSON/default banner exactly
      // as-is. Build 7: recorded with its boundary tag.
      CrashGuard.captureHandled(e, s, source: 'home.banner');
    }
  }

  /// Call once at startup. Returns fast: it only loads the cached
  /// JSON; the network refresh is backgrounded and never blocks.
  Future<void> init() async {
    await _loadFromCache();
    // The cached/default config has resolved — now let the Supabase
    // admin banner override (if any) take over the banner fields.
    unawaited(_fetchAdminBannerOverride());
    final String? tsRaw = await _readKey(_cacheTimeKey);
    final int ts = int.tryParse(tsRaw ?? '') ?? 0;
    final int age = DateTime.now().millisecondsSinceEpoch - ts;
    if (ts == 0 || age > refreshInterval.inMilliseconds) {
      unawaited(_refresh());
    }
  }

  Future<String?> _readKey(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadFromCache() async {
    try {
      final String? raw = await _storage.read(key: _cacheKey);
      if (raw != null && raw.isNotEmpty) {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _publish(RemoteConfig.fromJson(decoded));
        }
      }
    } catch (e, s) {
      // Build 7: recorded with its boundary tag (no banner).
      CrashGuard.captureHandled(e, s, source: 'home.config');
      _publish(RemoteConfig.defaults);
    }
  }

  Future<void> _refresh() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = fetchTimeout;
      final HttpClientRequest request =
          await client.getUrl(Uri.parse(configUrl));
      final HttpClientResponse response =
          await request.close().timeout(fetchTimeout);
      if (response.statusCode != HttpStatus.ok) {
        return;
      }
      final String body = await response.transform(utf8.decoder).join();
      final dynamic decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      final RemoteConfig parsed = RemoteConfig.fromJson(decoded);
      await _storage.write(key: _cacheKey, value: body);
      await _storage.write(
        key: _cacheTimeKey,
        value: DateTime.now().millisecondsSinceEpoch.toString(),
      );
      _publish(parsed);
      // The fresh remote-JSON config has resolved — re-check the
      // Supabase admin banner override on top of it.
      await _fetchAdminBannerOverride();
    } catch (e, s) {
      // Fail-soft: keep cache/defaults. Build 7: recorded with
      // its boundary tag (no banner).
      CrashGuard.captureHandled(e, s, source: 'home.config');
    } finally {
      client?.close(force: true);
    }
  }
}
