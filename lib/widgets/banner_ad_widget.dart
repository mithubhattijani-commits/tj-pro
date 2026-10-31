/// Home screen banner ad. Shows nothing at all when the ad fails to
/// load, so the home screen never shows a broken ad slot.
///
/// FIX (30 Oct 2026): the red "Ad with the following id could not be found"
/// error happened because AdWidget was built before the BannerAd finished
/// loading (load() is async). The widget now waits for onAdLoaded before
/// inserting AdWidget into the tree, and hides the slot on any failure.
library;

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../app_config.dart';

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _ad;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    try {
      _ad = BannerAd(
        adUnitId: AppConfig.bannerAdUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
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
    if (!AppConfig.adsEnabled || !AppConfig.bannerAdEnabled) {
      return const SizedBox.shrink();
    }
    final BannerAd? ad = _ad;
    // Only build AdWidget after the ad has actually loaded — building it
    // earlier is what caused "Ad with the following id could not be found".
    if (ad == null || !_isLoaded) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
