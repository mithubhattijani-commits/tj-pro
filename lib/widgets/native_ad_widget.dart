/// Home feed native ad card. Shows nothing at all when the ad fails to
/// load, so the home screen never shows a broken ad slot.
///
/// FIX (30 Oct 2026): same root cause as the banner widget — AdWidget was
/// built before the NativeAd finished loading (load() is async), which
/// caused "Ad with the following id could not be found". The widget now
/// waits for onAdLoaded before inserting AdWidget into the tree.
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
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    try {
      _ad = NativeAd(
        adUnitId: AppConfig.nativeAdUnitId,
        request: const AdRequest(),
        listener: NativeAdListener(
          onAdLoaded: (Ad ad) {
            if (mounted) {
              setState(() {
                _isLoaded = true;
              });
            }
          },
          onAdFailedToLoad: (Ad ad, LoadAdError _) {
            ad.dispose();
            if (mounted) {
              setState(() {
                _ad = null;
                _isLoaded = false;
              });
            }
          },
        ),
        nativeTemplateStyle: NativeTemplateStyle(
          templateType: TemplateType.medium,
        ),
      )..load();
    } catch (_) {
      _ad = null;
      _isLoaded = false;
    }
  }

  @override
  void dispose() {
    _ad?.dispose();
    _ad = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.adsEnabled || !AppConfig.nativeAdEnabled) {
      return const SizedBox.shrink();
    }
    final NativeAd? ad = _ad;
    // Only build AdWidget after the ad has actually loaded.
    if (ad == null || !_isLoaded) return const SizedBox.shrink();
    return SizedBox(
      height: 300,
      child: AdWidget(ad: ad),
    );
  }
}
