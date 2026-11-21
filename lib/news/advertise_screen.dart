/// Advertise page — dedicated page for the advertising banner
/// (Phase 10, user order 20 Nov 2026, Magic Box v3 pattern).
///
/// CORRECTED ORDER: the banner lives on THIS dedicated page — NOT
/// two home slots (the earlier "upar + neeche" home note is
/// SUPERSEDED). The page shows:
///
///   - The current banner image with [BoxFit.contain] — any size or
///     aspect ratio auto-fits, fully visible, NEVER cropped
///     (letterbox/padding OK, crop NAHI). The image comes from remote
///     config (`advertising_banner_image_url`, admin-panel controlled)
///     and falls back to the bundled house banner asset; a
///     `assets/...` value loads from the bundle, anything else loads
///     over the network with a graceful fallback on failure.
///   - WhatsApp contact button (booking / help — remote-config number).
///   - "Watch Ads, Earn Coins" button (same flow as the coins
///     section: one Unity rewarded ad on the coins placement → 50
///     coins on full watch, max 20/day). Hidden for admins.
///   - Paid-banner booking: 200 coins / 2 hours (remote-config
///     price/duration). The booking itself goes over WhatsApp to the
///     owner — NO coins are taken in-app for a booking, because the
///     paid flow (verify before live + owner approval in the admin
///     panel + reject = refund) needs the admin-panel/server step,
///     which does not exist yet. Taking coins here with no approval
///     or refund path would be a fake flow. The exact backend step is
///     listed in the Phase 10 release-prep report (parent step).
///   - Report button on the banner (opens WhatsApp with a prefilled
///     report message — real, not a dead button).
///   - ADMIN HOUSE-AD OVERRIDE (v1.2.0): when the Supabase table
///     `tjpro_admin_banner` has an enabled row with an image, that
///     image + link override the remote-config banner (see
///     RemoteConfigService). Tapping the banner opens the override's
///     link (`advertisingBannerLinkUrl`) externally when one is set;
///     when no link is set the tap keeps its original behaviour
///     (no action). Admins (server-fed [AuthService.isAdmin]) also
///     get an "Edit banner" button opening [AdminBannerScreen].
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/coin_service.dart';
import '../services/remote_config_service.dart';
import '../widgets/help_whatsapp_button.dart';
import 'admin_banner_screen.dart';

class AdvertiseScreen extends StatefulWidget {
  const AdvertiseScreen({super.key});

  @override
  State<AdvertiseScreen> createState() => _AdvertiseScreenState();
}

class _AdvertiseScreenState extends State<AdvertiseScreen> {
  final CoinService _coins = CoinService.instance;

  bool _adBusy = false;
  String? _message;

  Future<void> _watchAd() async {
    if (_adBusy) return;
    setState(() {
      _adBusy = true;
      _message = null;
    });
    final result = await _coins.watchRewardedAd();
    if (!mounted) return;
    setState(() {
      _adBusy = false;
      _message = result.ok
          ? '+${result.coins} coins earned!'
          : (result.error ?? 'Could not earn coins. Please try again.');
    });
  }

  /// Opens the banner's link (Supabase admin override /
  /// `advertising_banner_link_url`) in the external browser. Only
  /// wired as a tap handler when a link is actually set — with no
  /// link the banner tap does nothing, exactly as before.
  Future<void> _openBannerLink() async {
    final link =
        RemoteConfigService.instance.config.advertisingBannerLinkUrl
            .trim();
    if (link.isEmpty) return;
    try {
      await launchUrl(
        Uri.parse(link),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the banner link.')),
      );
    }
  }

  /// Opens WhatsApp to the support number with a prefilled message
  /// (booking or report). Real action — the owner approves the banner
  /// there; no coins move in-app for a booking (see file header).
  Future<void> _openWhatsAppBooking({required bool report}) async {
    final config = RemoteConfigService.instance.config;
    final price = config.advertisingBannerPriceCoins;
    final hours = config.advertisingBannerDurationHours;
    final text = report
        ? 'Assalam-o-Alaikum, TJ Pro ke Advertise page par lage banner '
            'ke baare mein report karna hai: '
        : 'Assalam-o-Alaikum, TJ Pro par apna advertising banner '
            'lagwana hai ($price coins / $hours hours). '
            'Banner ki details ye hain: ';
    final uri = Uri.parse(
      '${SupportContact.waMeUrl()}?text=${Uri.encodeComponent(text)}',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Advertise')),
      body: ValueListenableBuilder<RemoteConfig>(
        valueListenable: RemoteConfigService.instance.notifier,
        builder: (context, config, _) {
          final bannerUrl = config.advertisingBannerImageUrl;
          final bannerEnabled = config.advertisingBannerEnabled;
          final bannerLink = config.advertisingBannerLinkUrl.trim();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Advertising banner',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Apna banner yahan lagwayein — TJ Pro ke users dekhenge.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                // The banner itself — BoxFit.contain: any size/aspect
                // auto-fits, fully visible, NEVER cropped. The
                // neutral black12 box behind it is the letterbox for
                // whatever space the fitted image does not fill.
                // Tap: opens the banner link when one is set; with
                // no link set there is no handler (original
                // behaviour — tapping did nothing).
                if (bannerEnabled)
                  GestureDetector(
                    onTap: bannerLink.isEmpty ? null : _openBannerLink,
                    child: Container(
                      height: 220,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: bannerUrl.startsWith('assets/')
                          ? Image.asset(
                              bannerUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Center(
                                child: Text(
                                  'Banner load nahi hua.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            )
                          : Image.network(
                              bannerUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Center(
                                child: Text(
                                  'Banner load nahi hua.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            ),
                    ),
                  )
                else
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Advertising banner abhi band hai.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const Key('advertiseReportButton'),
                    onPressed: () => _openWhatsAppBooking(report: true),
                    icon: const Icon(Icons.flag_outlined, size: 18),
                    label: const Text('Report this banner'),
                  ),
                ),
                // Admin-only: edit the house-ad banner (image + link)
                // in Supabase — shows in the app with no new build.
                // Visibility is driven ONLY by the server-fed
                // [AuthService.isAdmin] flag (fail closed: hidden
                // until the server says admin).
                ValueListenableBuilder<bool>(
                  valueListenable: AuthService.isAdmin,
                  builder: (context, isAdmin, _) {
                    if (!isAdmin) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          key: const Key('advertiseEditBannerButton'),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AdminBannerScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit banner (Admin)'),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                // WhatsApp contact (booking / help).
                const WhatsAppButton(),
                const SizedBox(height: 12),
                // Paid-banner booking — via WhatsApp (see file header:
                // no in-app coin charge for a booking yet).
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Apna banner lagwayein — '
                          '${config.advertisingBannerPriceCoins} coins / '
                          '${config.advertisingBannerDurationHours} hours',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Booking WhatsApp par hoti hai — owner approve '
                          'karne ke baad banner live hoga. Coins booking '
                          'par nahi katte; payment/approval owner se '
                          'WhatsApp par tay hoti hai.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            key: const Key('advertiseBookButton'),
                            onPressed: () =>
                                _openWhatsAppBooking(report: false),
                            icon: const Icon(Icons.campaign_outlined),
                            label: const Text('Book your banner'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Watch Ads — Earn Coins (hidden for admins).
                ValueListenableBuilder<bool>(
                  valueListenable: AuthService.isAdmin,
                  builder: (context, isAdmin, _) {
                    if (isAdmin) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton.icon(
                          key: const Key('advertiseWatchAdsButton'),
                          onPressed: _adBusy ? null : _watchAd,
                          icon: const Icon(Icons.play_circle_fill),
                          label: Text(
                            _adBusy
                                ? 'Loading ad…'
                                : 'Watch Ads, Earn Coins  •  '
                                    '+${CoinService.rewardPerAd} coins',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 6),
                        ValueListenableBuilder<int>(
                          valueListenable: _coins.adsWatchedToday,
                          builder: (context, watched, _) {
                            return Text(
                              'Ads watched today: $watched / '
                              '${CoinService.maxRewardedAdsPerDay} '
                              '(max ${CoinService.maxAdCoinsPerDay} '
                              'coins/day)',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Banner admin panel se control hota hai — owner '
                  'approve kare to hi banner live hota hai.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  'Support: ${config.supportWhatsAppNumber}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
