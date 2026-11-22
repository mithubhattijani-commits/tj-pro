/// Tombstone — emptied in v1.2.0 (plan §9 static check).
///
/// This file used to hold the pre-Unity mobile-ads implementation.
/// It has been unreferenced since the one-build (v1.1.0): nothing in
/// the app imports it, and it pointed at an ads package the app no
/// longer depends on — exactly the class of stale reference the §9
/// gate forbids. All ads are Unity Ads now; see
/// `unity_ads_service.dart`. (Premium unlocks are coins only since
/// v1.3.0 — see `coin_service.dart`.)
///
/// The file is kept as a tombstone (no code) because the snapshot
/// push route cannot delete files from the repository.
library;
