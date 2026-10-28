/// Home feed native ad card. Shows nothing at all when the ad fails to
/// load, so the home screen never shows a broken ad slot.
library;

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../app_config.dart';

class NativeAdWidget extends StatefulWidget {
  const NativeAdWidget({super.key});

  @override
  State<NativeAdWidget> createState() => _NativeAdWidgetState();
}

class _NativeAdWidgetState extends State<NativeAdWidget> {
  NativeAd? _ad;

  @override
  void initState() {
    super.initState();
    try {
      _ad = NativeAd(
        adUnitId: AppConfig.nativeAdUnitId,
        request: const AdRequest(),
        listener: NativeAdListener(
          onAdFailedToLoad: (ad, _) {
            ad.dispose();
            if (mounted) setState(() => _ad = null);
          },
        ),
        nativeTemplateStyle: NativeTemplateStyle(
          templateType: TemplateType.medium,
        ),
      )..load();
    } catch (_) {
      _ad = null;
    }
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.adsEnabled || !AppConfig.nativeAdEnabled) {
      return const SizedBox.shrink();
    }
    final ad = _ad;
    if (ad == null) return const SizedBox.shrink();
    return SizedBox(
      height: 300,
      child: AdWidget(ad: ad),
    );
  }
}
