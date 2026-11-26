/// Live trending suggestions for the SEO step (Phase 4, §13).
///
///   POST https://nigraan-tv-tts-proxy.mithubhattijani.workers.dev/trends-suggest
///   JSON {text, lang}  →  {suggestedHashtags, suggestedKeywords,
///   sources, checkedAt}
///
/// STATUS (verified 20 Nov 2026 ~23:59 PKT): the endpoint does NOT
/// exist yet — the Worker answers 404
/// (`{"error":"Use POST /tts, POST /edge-tts or POST /transcribe"}`).
/// A separate agent is building it. Until it lands, this service
/// returns [TrendsResult.unavailable] and the SEO screen degrades
/// gracefully to manual entry with a clear "suggestions unavailable —
/// manually likhein" state.
///
/// STANDING RULE (§13): suggestions are NEVER invented. Only tags
/// that actually appear in the live trend lists (Google Trends + X)
/// may be suggested. An empty suggestion is correct; an invented one
/// is a bug. This client enforces nothing about the content — it
/// trusts the endpoint's contract and shows the returned source
/// labels (Google Trends / X) next to each suggestion.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// One suggestion batch from the trends endpoint.
class TrendsSuggestion {
  TrendsSuggestion({
    required this.hashtags,
    required this.keywords,
    required this.sources,
    this.checkedAt,
  });

  /// Suggested hashtags (with leading `#`), live-trend matched only.
  final List<String> hashtags;

  /// Suggested keywords (plain phrases, no `#`).
  final List<String> keywords;

  /// Where each suggestion was verified, e.g. ['Google Trends', 'X'].
  final List<String> sources;

  /// When the Worker last checked the trend lists (ISO string).
  final String? checkedAt;

  static TrendsSuggestion fromJson(Map<String, dynamic> json) {
    List<String> strings(dynamic raw) {
      final out = <String>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is String && item.trim().isNotEmpty) {
            out.add(item.trim());
          }
        }
      }
      return out;
    }

    return TrendsSuggestion(
      hashtags: strings(json['suggestedHashtags']),
      keywords: strings(json['suggestedKeywords']),
      sources: strings(json['sources']),
      checkedAt: json['checkedAt'] as String?,
    );
  }
}

/// Result of one suggestion fetch.
class TrendsResult {
  TrendsResult.available(this.suggestion)
      : available = true,
        reason = null;

  TrendsResult.unavailable(this.reason)
      : available = false,
        suggestion = null;

  /// True when the endpoint answered with suggestions (possibly an
  /// empty list — empty is correct when nothing trends for the topic).
  final bool available;

  /// User-facing reason when [available] is false (e.g. endpoint
  /// 404, no network). Never a made-up suggestion.
  final String? reason;

  final TrendsSuggestion? suggestion;
}

class TrendsService {
  static const trendsUrl =
      'https://nigraan-tv-tts-proxy.mithubhattijani.workers.dev/trends-suggest';

  /// Fetches live suggestions for [text] (`lang` 'ur'/'en'). Any
  /// failure — 404, other status, timeout, no network — returns
  /// [TrendsResult.unavailable]; the caller shows manual entry.
  /// [client] is a test seam (pass a MockClient in tests).
  static Future<TrendsResult> fetchSuggestions({
    required String text,
    required String lang,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    final owned = client == null;
    try {
      final response = await httpClient
          .post(
            Uri.parse(trendsUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'text': text, 'lang': lang}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 404) {
        return TrendsResult.unavailable(
          'The Trends endpoint is not live yet — write manually',
        );
      }
      if (response.statusCode != 200) {
        return TrendsResult.unavailable(
          'Suggestions could not be fetched (server ${response.statusCode}) — '
          'write manually',
        );
      }
      final data = jsonDecode(response.body);
      if (data is! Map<String, dynamic>) {
        return TrendsResult.unavailable(
          'The suggestions response was not understood — write manually',
        );
      }
      return TrendsResult.available(TrendsSuggestion.fromJson(data));
    } catch (_) {
      return TrendsResult.unavailable(
        'Suggestions could not be fetched (network) — write manually',
      );
    } finally {
      if (owned) httpClient.close();
    }
  }
}
