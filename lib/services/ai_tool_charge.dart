/// Build 9 (v1.7.0, fix-list point #6B) — AI TOOL COIN CHARGE.
///
/// The big AI tools charge PER USE:
/// - AI Caption Generator — Video Editor "Generate Captions"
///   (Whisper, on-device).
/// - AI auto captions — Video Editor "Urdu (AI)" captions
///   (Sherpa-ONNX, on-device).
/// - Photo AI tools — Photo Editor AI operations and the Video
///   Editor's on-device ML tools (background remover, motion
///   tracking).
///
/// Point #20 (2026-11-25): the price is no longer the single
/// `ai_tool_price_coins` value — each tool resolves its own key
/// through [PricingService] (tj-pro.json `prices` object), so
/// the owner can reprice, free, Pro-gate or ad-gate any of them
/// WITHOUT a new build:
/// - [AiToolCharge.reasonCaptionGenerator] -> `price_ve_caption_generator`
/// - [AiToolCharge.reasonAutoCaptions] -> `price_ve_auto_captions`
/// - [AiToolCharge.reasonPhotoAi] -> `price_photo_ai`
/// A key ABSENT from `prices` falls back to the legacy
/// `ai_tool_price_coins` price (default 25), so behaviour is
/// unchanged until the owner sets the keys.
///
/// Kinds: coins -> the confirm dialog below + the EXISTING coin
/// flow ([CoinService.spendAmount] -> the `tjpro-spend-coins`
/// Edge Function) with the tool's stable ledger reason; free ->
/// runs at once; "pro" -> Pro users pass, others see a Pro
/// notice; "ad" -> one rewarded ad unlocks the use. Admins are
/// waived before any of this (CoinService's own rule). When the
/// balance is short the caller shows the existing earn path
/// (rewarded ads in the Earn tab) — see [insufficientMessage].
///
/// The kill switch is the caller's first check (FeatureGate):
/// a killed tool never reaches this charge.
library;

import 'package:flutter/material.dart';

import 'coin_service.dart';
import 'pricing_service.dart';
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

  /// The PricingService key a ledger [reason] resolves through.
  static String priceKeyForReason(String reason) {
    switch (reason) {
      case reasonCaptionGenerator:
        return PricingService.keyVeCaptionGenerator;
      case reasonAutoCaptions:
        return PricingService.keyVeAutoCaptions;
      case reasonPhotoAi:
      default:
        return PricingService.keyPhotoAi;
    }
  }

  /// The resolved spec for [reason]: the `prices` key when set,
  /// else the legacy `ai_tool_price_coins` price as coins.
  static PriceSpec specForReason(String reason) =>
      PricingService.specOr(
        priceKeyForReason(reason),
        fallbackCoins: RemoteConfigService.instance.config.aiToolPriceCoins,
      );

  /// The current per-use coin price for [reason] (0 when the
  /// tool is currently free / Pro-gated / ad-gated).
  static int priceCoinsForReason(String reason) {
    final PriceSpec s = specForReason(reason);
    return s.kind == PriceKind.coins ? s.coins : 0;
  }

  /// Legacy getter (pre-#20 callers/tests): the shared AI-tool
  /// price from `ai_tool_price_coins`, default 25.
  static int priceCoins() =>
      RemoteConfigService.instance.config.aiToolPriceCoins;

  /// The existing earn-path message for a short balance — the
  /// same wording the editors already used before this build.
  static const String insufficientMessage =
      'Coins kam hain — Earn tab mein rewarded ads dekh kar '
      'coins kamayein, phir dobara try karein.';

  /// Resolves the tool's price kind and runs the matching gate:
  /// confirm-dialog + coin charge for a coin price, a Pro
  /// notice for a Pro-only tool, a rewarded ad for an ad-gated
  /// tool, and an immediate pass for a free one. Admins skip
  /// everything and get [AiChargeOutcome.ok] at once — the same
  /// behaviour the editors had before this build.
  static Future<AiChargeOutcome> chargeWithConfirm(
    BuildContext context, {
    required String toolLabel,
    required String reason,
  }) async {
    if (CoinService.instance.isAdminNow) return AiChargeOutcome.ok;
    final PriceSpec spec = specForReason(reason);
    switch (spec.kind) {
      case PriceKind.free:
        return AiChargeOutcome.ok;
      case PriceKind.pro:
        if (PricingService.passesPro) return AiChargeOutcome.ok;
        if (!context.mounted) return AiChargeOutcome.cancelled;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(toolLabel),
            content: const Text(
              'Ye tool sirf Pro users ke liye hai. Pro lene ke '
              'liye Pro screen par payment details maujood hain.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Theek hai'),
              ),
            ],
          ),
        );
        return AiChargeOutcome.cancelled;
      case PriceKind.ad:
        if (!context.mounted) return AiChargeOutcome.cancelled;
        final bool? go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(toolLabel),
            content: const Text(
              'Is istemal ke liye aik rewarded ad dekhein — ad '
              'mukammal dekhne par tool khul jayega.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Later'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Ad Dekhein'),
              ),
            ],
          ),
        );
        if (go != true) return AiChargeOutcome.cancelled;
        final bool watched = await PricingService.watchUnlockAd();
        if (watched) return AiChargeOutcome.ok;
        if (!context.mounted) return AiChargeOutcome.cancelled;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(toolLabel),
            content: const Text(
              'Ad mukammal nahi hua — tool nahi khula. Dobara '
              'try karein.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Theek hai'),
              ),
            ],
          ),
        );
        return AiChargeOutcome.cancelled;
      case PriceKind.coins:
        return _chargeCoinsWithConfirm(
          context,
          toolLabel: toolLabel,
          reason: reason,
          price: spec.coins,
        );
    }
  }

  /// The original Build 9 flow, unchanged: confirm dialog
  /// (price + balance), then the server-ledger spend.
  static Future<AiChargeOutcome> _chargeCoinsWithConfirm(
    BuildContext context, {
    required String toolLabel,
    required String reason,
    required int price,
  }) async {
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
