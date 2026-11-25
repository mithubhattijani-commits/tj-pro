/// Build 9 (v1.7.0, fix-list point #6B) — AI TOOL COIN CHARGE.
///
/// The big AI tools charge PER USE at the remote-config price
/// (`ai_tool_price_coins` in tj-pro.json, default 25 — see
/// [RemoteConfig.aiToolPriceCoins]):
///
/// - AI Caption Generator — Video Editor "Generate Captions"
///   (Whisper, on-device).
/// - AI auto captions — Video Editor "Urdu (AI)" captions
///   (Sherpa-ONNX, on-device).
/// - Photo AI tools — Photo Editor AI operations and the Video
///   Editor's on-device ML tools (background remover, motion
///   tracking), which previously unlocked once per session for
///   50; they now charge the configured price per use, like the
///   user ordered ("har istemal par 25 coins").
///
/// The charge goes through the EXISTING coin flow
/// ([CoinService.spendAmount] -> the `tjpro-spend-coins` Edge
/// Function), with a stable per-tool ledger reason. Admins are
/// waived by CoinService itself, as everywhere. When the
/// balance is short the caller shows the existing earn path
/// (rewarded ads in the Earn tab) — see [insufficientMessage].
///
/// The kill switch is the caller's first check (FeatureGate):
/// a killed tool never reaches this charge.
library;

import 'package:flutter/material.dart';

import 'coin_service.dart';
import 'remote_config_service.dart';

/// Outcome of one [AiToolCharge.chargeWithConfirm] attempt.
enum AiChargeOutcome {
  /// Coins charged (or waived for an admin) — run the tool.
  ok,

  /// The user tapped "Later" on the confirm dialog.
  cancelled,

  /// Balance too low — show [AiToolCharge.insufficientMessage].
  insufficient,

  /// The spend itself failed (network / server) — show the
  /// error and let the user retry.
  failed,
}

class AiToolCharge {
  AiToolCharge._();

  /// Ledger reasons (stable strings — they appear in the user's
  /// coin history and the server ledger).
  static const String reasonCaptionGenerator = 'ai_caption_generator';
  static const String reasonAutoCaptions = 'ai_auto_captions';
  static const String reasonPhotoAi = 'photo_ai_tool';

  /// The current per-use price (remote config, default 25).
  static int priceCoins() =>
      RemoteConfigService.instance.config.aiToolPriceCoins;

  /// The existing earn-path message for a short balance — the
  /// same wording the editors already used before this build.
  static const String insufficientMessage =
      'Coins kam hain — Earn tab mein rewarded ads dekh kar '
      'coins kamayein, phir dobara try karein.';

  /// Shows the confirm dialog (price + balance) and, on
  /// confirmation, charges the per-use price. Admins skip the
  /// dialog and the charge (CoinService waives them) and get
  /// [AiChargeOutcome.ok] at once — the same behaviour the
  /// editors had before this build.
  static Future<AiChargeOutcome> chargeWithConfirm(
    BuildContext context, {
    required String toolLabel,
    required String reason,
  }) async {
    if (CoinService.instance.isAdminNow) return AiChargeOutcome.ok;
    final int price = priceCoins();
    final int balance = CoinService.instance.balance.value;
    if (!context.mounted) return AiChargeOutcome.cancelled;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(toolLabel),
        content: Text(
          'Ye AI tool har istemal par $price coins ka hai.\n'
          'Aap ka balance: $balance coins.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Chalao — $price coins'),
          ),
        ],
      ),
    );
    if (confirm != true) return AiChargeOutcome.cancelled;
    final CoinSpendResult res = await CoinService.instance.spendAmount(
      price,
      reason: reason,
    );
    if (res.ok) return AiChargeOutcome.ok;
    return res.error == 'insufficient_balance'
        ? AiChargeOutcome.insufficient
        : AiChargeOutcome.failed;
  }
}
