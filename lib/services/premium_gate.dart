/// Tombstone — emptied in v1.3.0 (§8, user order 22 Nov 2026).
///
/// This file used to hold the premium gate: watch one rewarded ad and
/// the Premium AI tools unlock for the session. That economy is
/// GONE. Premium tools now unlock with COINS only, charged through
/// `CoinService` / `CoinCosts` (see lib/services/coin_service.dart);
/// rewarded ads exist solely to EARN coins on the Coins screen.
/// The editors' AI guards call `CoinService` directly — nothing
/// imports this file any more.
///
/// The file is kept as a tombstone (no code) because the snapshot
/// push route cannot delete files from the repository.
library;
