/// Build 9 (v1.7.0, fix-list point #5) — REMOTE KILL-SWITCH gates.
///
/// The switches themselves live in the remote config
/// (`tj-pro.json` on nigraantv.xyz — see [RemoteConfig] for the
/// key documentation). This file is the one place features ask
/// "am I killed?" and the one polite notice they show instead of
/// running. Design rules (from the point-#5 research):
///
/// - DEFAULT IS ALWAYS "RUN": a missing key, a failed fetch or
///   an old cached config can never brick a feature — only the
///   literal boolean `true` in a fetched config arms a switch.
/// - A killed feature NEVER crashes and NEVER half-runs: the
///   gate is checked before any work (and before any coin
///   charge), and the user sees [killedMessage] instead.
/// - The gate reads [RemoteConfigService.instance] by default so
///   a config refresh arms/disarms a switch without a restart.
library;

import 'package:flutter/material.dart';

import 'remote_config_service.dart';

/// The features a remote kill switch can stop. Each maps to one
/// `kill_*` key in tj-pro.json (documented on [RemoteConfig]).
enum KillableFeature {
  /// `kill_video_export` — Video Editor export + News export.
  videoExport,

  /// `kill_photo_ai` — Photo Editor AI tools + Video Editor
  /// on-device ML tools (background remover, motion tracking).
  photoAi,

  /// `kill_ai_captions` — AI caption generation (Whisper +
  /// Urdu (AI)) in the Video Editor.
  aiCaptions,

  /// `kill_store` — the Online Store screen.
  store,

  /// `kill_motion` — the Motion Graphics Studio (Build M1).
  motion,
}

class FeatureGate {
  FeatureGate._();

  /// The polite line a killed feature shows (Roman Urdu, the
  /// app's user-facing language).
  static const String killedMessage =
      'Ye feature abhi band hai — jald wapas aaye ga.';

  /// True when [feature] is killed in [config] (defaults to the
  /// live shared config). Pure function of the config — the
  /// editors and screens call this before doing any work.
  static bool isKilled(
    KillableFeature feature, {
    RemoteConfig? config,
  }) {
    final RemoteConfig cfg = config ?? RemoteConfigService.instance.config;
    switch (feature) {
      case KillableFeature.videoExport:
        return cfg.killVideoExport;
      case KillableFeature.photoAi:
        return cfg.killPhotoAi;
      case KillableFeature.aiCaptions:
        return cfg.killAiCaptions;
      case KillableFeature.store:
        return cfg.killStore;
      case KillableFeature.motion:
        return cfg.killMotion;
    }
  }
}

/// Full-area polite state for a killed feature (used by the
/// Online Store screen, whose whole body is the feature).
/// Follows the app's professional pattern: deep dark surface,
/// one small monochrome icon, one line of text.
class KilledFeatureNotice extends StatelessWidget {
  const KilledFeatureNotice({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.pause_circle_outline,
              size: 40,
              color: Colors.white54,
            ),
            const SizedBox(height: 12),
            Text(
              message ?? FeatureGate.killedMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
