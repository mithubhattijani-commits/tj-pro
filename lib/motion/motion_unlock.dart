/// MOTION GRAPHICS STUDIO — unlock flows (Build M1, v1.11.0).
///
/// The Gallery's one-time unlocks, built entirely on the app's
/// existing money machinery (the [AiToolCharge] discipline):
///
///   - the kill switch is checked FIRST — a killed Motion never
///     charges anyone for anything;
///   - COINS: a confirm dialog (price + live balance), then
///     [CoinService.spendAmount] with the stable ledger reason
///     `motion_template_unlock`; ownership is recorded ONLY
///     after the spend succeeds. Admins are waived by
///     CoinService itself and simply take ownership.
///   - AD: the pricing system's unlock ad
///     ([PricingService.watchUnlockAd]) — one rewarded ad on
///     the standard placement, watched to completion, which
///     deliberately does NOT credit earn coins (earning is
///     CoinService.watchRewardedAd's separate path, exactly as
///     the central pricing design separates them).
///   - PRO-ONLY: no purchase path exists and none is faked —
///     the dialog explains and offers the real Pro screen.
library;

import 'package:flutter/material.dart';

import '../news/pro_screen.dart';
import '../services/coin_service.dart';
import '../services/feature_gate.dart';
import '../services/pricing_service.dart';
import 'motion_access.dart';
import 'motion_templates.dart';

/// Outcome of one unlock attempt.
enum MotionUnlockOutcome {
  /// Unlocked (or admin-waived) — ownership recorded.
  ok,

  /// The user backed out of the dialog.
  cancelled,

  /// Coin balance too low — show the earn path message.
  insufficient,

  /// The spend / ad itself failed — retry is safe.
  failed,

  /// Pro-only template and the user is not Pro.
  proOnly,

  /// Motion is kill-switched — nothing was charged.
  killed,
}

class MotionUnlock {
  MotionUnlock._();

  /// Ledger reason for template unlock spends (stable — it
  /// appears in the user's coin history).
  static const String reasonTemplateUnlock = 'motion_template_unlock';

  /// Runs the right unlock flow for [access] (a locked verdict
  /// from [MotionAccessResolver]) and records ownership on
  /// success. Returns the outcome; the caller refreshes its UI
  /// on [MotionUnlockOutcome.ok].
  static Future<MotionUnlockOutcome> unlock(
    BuildContext context, {
    required MotionTemplate template,
    required MotionAccess access,
  }) async {
    // The gate comes before ANY charge (Build 9 discipline).
    if (FeatureGate.isKilled(KillableFeature.motion)) {
      return MotionUnlockOutcome.killed;
    }
    switch (access.kind) {
      case MotionAccessKind.lockedCoins:
        return _unlockWithCoins(context, template, access.coins);
      case MotionAccessKind.lockedAd:
        return _unlockWithAd(context, template);
      case MotionAccessKind.lockedProOnly:
        return _proOnly(context, template);
      case MotionAccessKind.free:
      case MotionAccessKind.proIncluded:
      case MotionAccessKind.owned:
        return MotionUnlockOutcome.ok;
    }
  }

  static Future<MotionUnlockOutcome> _unlockWithCoins(
    BuildContext context,
    MotionTemplate template,
    int price,
  ) async {
    // Admins are waived by CoinService everywhere; for a
    // one-time purchase that means: take ownership, no dialog.
    if (CoinService.instance.isAdminNow) {
      await MotionOwnership.markOwned(template.id);
      return MotionUnlockOutcome.ok;
    }
    final int balance = CoinService.instance.balance.value;
    if (!context.mounted) return MotionUnlockOutcome.cancelled;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(template.name),
        content: Text(
          'Ye design aik dafa ke $price coins mein hamesha ke '
          'liye unlock ho jayega.\n'
          'Aap ka balance: $balance coins.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Unlock — $price coins'),
          ),
        ],
      ),
    );
    if (confirm != true) return MotionUnlockOutcome.cancelled;
    final CoinSpendResult res = await CoinService.instance.spendAmount(
      price,
      reason: reasonTemplateUnlock,
    );
    if (!res.ok) {
      return res.error == 'insufficient_balance'
          ? MotionUnlockOutcome.insufficient
          : MotionUnlockOutcome.failed;
    }
    await MotionOwnership.markOwned(template.id);
    return MotionUnlockOutcome.ok;
  }

  static Future<MotionUnlockOutcome> _unlockWithAd(
    BuildContext context,
    MotionTemplate template,
  ) async {
    if (!context.mounted) return MotionUnlockOutcome.cancelled;
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(template.name),
        content: const Text(
          'Aik rewarded ad dekhen — ye design hamesha ke liye '
          'unlock ho jayega.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ad dekhen'),
          ),
        ],
      ),
    );
    if (confirm != true) return MotionUnlockOutcome.cancelled;
    final bool watched = await PricingService.watchUnlockAd();
    if (!watched) return MotionUnlockOutcome.failed;
    await MotionOwnership.markOwned(template.id);
    return MotionUnlockOutcome.ok;
  }

  static Future<MotionUnlockOutcome> _proOnly(
    BuildContext context,
    MotionTemplate template,
  ) async {
    if (!context.mounted) return MotionUnlockOutcome.cancelled;
    final bool? seePro = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(template.name),
        content: const Text(
          'Ye design sirf Pro members ke liye hai — coins se '
          'nahi khulta. Pro ki tafseel dekhen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Band karein'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Pro dekhen'),
          ),
        ],
      ),
    );
    if (seePro == true && context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProScreen()),
      );
    }
    return MotionUnlockOutcome.proOnly;
  }
}
