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
/// NOTE: the reference design uses shared_preferences, but TJ Pro's
/// pubspec does not declare it (and no new dependency may be added),
/// so the cache lives in flutter_secure_storage, which is already a
/// direct dependency (used for Live Studio stream keys).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  });

  final String displayName;
  final String logoUrl;
  final AnnouncementConfig announcement;
  final SponsoredAdConfig sponsoredAd;
  final ForceUpdateConfig forceUpdate;

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
    );
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

  static const Duration fetchTimeout = Duration(seconds: 8);
  static const Duration refreshInterval = Duration(hours: 6);
  static const String _cacheKey = 'tjpro_remote_config_json_v1';
  static const String _cacheTimeKey = 'tjpro_remote_config_time_v1';

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  final ValueNotifier<RemoteConfig> notifier =
      ValueNotifier<RemoteConfig>(RemoteConfig.defaults);

  RemoteConfig get config => notifier.value;

  /// Call once at startup. Returns fast: it only loads the cached
  /// JSON; the network refresh is backgrounded and never blocks.
  Future<void> init() async {
    await _loadFromCache();
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
          notifier.value = RemoteConfig.fromJson(decoded);
        }
      }
    } catch (_) {
      notifier.value = RemoteConfig.defaults;
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
      notifier.value = parsed;
    } catch (_) {
      // Fail-soft: keep cache/defaults.
    } finally {
      client?.close(force: true);
    }
  }
}
