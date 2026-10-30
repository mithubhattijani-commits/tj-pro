/// Stream-key storage for Live Studio.
///
/// Keys are kept ONLY in the platform secure store (Keychain/Keystore)
/// on the user's own phone. They are never written to a file, never
/// logged, never printed, and never sent anywhere except inside the
/// RTMP URL the streaming plugin opens to Facebook/YouTube. The UI
/// only ever shows "connected / not set" — no part of a key is ever
/// displayed, not even the last characters.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StreamKeyStore {
  static const _fbKey = 'tj_fb_stream_key';
  static const _ytKey = 'tj_yt_stream_key';

  static const _storage = FlutterSecureStorage();

  static Future<void> saveFacebook(String key) async {
    final value = key.trim();
    if (value.isEmpty) {
      await _storage.delete(key: _fbKey);
    } else {
      await _storage.write(key: _fbKey, value: value);
    }
  }

  static Future<void> saveYouTube(String key) async {
    final value = key.trim();
    if (value.isEmpty) {
      await _storage.delete(key: _ytKey);
    } else {
      await _storage.write(key: _ytKey, value: value);
    }
  }

  /// Returns the saved keys. Callers must treat these as secrets: use
  /// them ONLY to build the RTMP URL passed to the streamer, and never
  /// log, display, or persist them anywhere else.
  static Future<({String? facebook, String? youtube})> load() async {
    final fb = await _storage.read(key: _fbKey);
    final yt = await _storage.read(key: _ytKey);
    return (
      facebook: (fb == null || fb.isEmpty) ? null : fb,
      youtube: (yt == null || yt.isEmpty) ? null : yt,
    );
  }

  static Future<bool> get hasFacebook async =>
      (await _storage.read(key: _fbKey))?.isNotEmpty == true;

  static Future<bool> get hasYouTube async =>
      (await _storage.read(key: _ytKey))?.isNotEmpty == true;

  /// Facebook Live RTMP ingest (RTMPS). The key is appended, never shown.
  static String facebookRtmpUrl(String key) =>
      'rtmps://live-api-s.facebook.com:443/rtmp/$key';

  /// YouTube Live RTMP ingest.
  static String youTubeRtmpUrl(String key) =>
      'rtmp://a.rtmp.youtube.com/live2/$key';
}
