/// Home screen banner ad — Unity Ads (one-build, defect #4).
///
/// This file used to host the AdMob `BannerAdWidget`. AdMob was
/// removed from TJ Pro entirely (the decided ads system is Unity
/// only), and the banner slot is now served by [UnityBannerAdWidget]
/// from the Unity ads service. The widget renders nothing until the
/// banner has actually loaded, so the home screen never shows a
/// broken ad slot.
library;

import 'package:flutter/material.dart';

import '../services/unity_ads_service.dart';

/// Banner slot used by Home (and previously the editor). Kept under
/// the historical name so call sites did not need to change.
class BannerAdWidget extends StatelessWidget {
  const BannerAdWidget({super.key});

  @override
  Widget build(BuildContext context) => const UnityBannerAdWidget();
}
