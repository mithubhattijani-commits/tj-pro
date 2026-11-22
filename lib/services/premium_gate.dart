/// Tombstone — emptied in v1.3.0 (§8, user order 22 Nov 2026).
///
/// This file used to hold the premium gate: watch one rewarded ad and
/// the Premium AI tools unlock for the session. That economy is
/// GONE. Premium tools now unlock with COINS only, charged through
/// `CoinService` / `CoinCosts` (see lib/services/coin_service.dart);
/// rewarded ads exist solely to EARN coins on the Coins screen.
/// The editors' AI guards call `CoinService` directly.
///
/// The file is kept as a tombstone because the snapshot
/// push route cannot delete files from the repository.
///
/// v1.4.0 ADDITION (the only code in this file): the Pro bridge.
/// TJ Pro PRO (lib/services/pro_service.dart) never changes coin
/// prices or the coin gate — it only RAISES caps. A feature that
/// enforces a numeric limit (daily uses, items per project, …)
/// resolves the effective cap through [ProGate.limitFor], which is
/// a straight pass-through to `ProService.limitFor`: Pro active ->
/// the pro cap, otherwise the free cap. Coin spends keep going
/// through `CoinService` exactly as before, Pro or not.
library;

import 'pro_service.dart';

/// Pro-aware limit resolution for gated features (see file header).
class ProGate {
  ProGate._();

  /// True while the signed-in user has an active Pro grant.
  static bool get proActive => ProService.instance.proActive;

  /// The cap to enforce: [proLimit] when Pro is active, else
  /// [freeLimit]. Delegates to [ProService.limitFor] so there is
  /// exactly one place where the Pro rule lives.
  static int limitFor(int freeLimit, int proLimit) =>
      ProService.instance.limitFor(freeLimit, proLimit);
}
