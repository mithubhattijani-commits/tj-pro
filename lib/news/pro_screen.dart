/// TJ Pro PRO — paid Pro subscription page (v1.4.0, mockup S6).
///
/// Layout follows the approved mockup: gold crown header, three
/// selectable package cards (7 Din Rs 200 / 15 Din Rs 500 /
/// 30 Din Rs 1,000 with BEST VALUE, monthly selected by default),
/// the PRO KE FAYDE checklist, a payment card, and the gold
/// 'Get Pro' CTA.
///
/// Payment is MANUAL (the owner's flow): the user pays the shown
/// Easypaisa / ABL number (both Ghulam Jillani — the numbers come
/// from [RemoteConfigService] so they can change without a rebuild;
/// a JazzCash line appears only when one is configured), then taps
/// the CTA, which opens WhatsApp to the support number with a
/// prefilled message naming the chosen package — the same booking
/// pattern as the Advertise page (lib/news/advertise_screen.dart).
/// The user sends the payment screenshot there and the owner grants
/// Pro server-side in `tjpro_pro` (see ProService / pro-sql.sql).
/// NO payment is taken in-app.
///
/// When [ProService] reports an active grant, the page shows the
/// active state + expiry instead of the purchase pitch.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_config.dart';
import '../theme.dart';
import '../services/pro_service.dart';
import '../services/remote_config_service.dart';
import '../widgets/help_whatsapp_button.dart';

class _ProPackage {
  const _ProPackage({
    required this.days,
    required this.subtitle,
    required this.price,
    required this.perDay,
    this.badge,
  });

  final String days;
  final String subtitle;
  final int price;
  final String perDay;
  final String? badge;
}

class ProScreen extends StatefulWidget {
  const ProScreen({super.key});

  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  static const Color _gold = Color(0xFFE89B0C);
  static const Color _goldDark = Color(0xFF8D6E00);

  static const List<_ProPackage> _packages = <_ProPackage>[
    _ProPackage(
      days: '7 Din',
      subtitle: 'Weekly package',
      price: AppConfig.proWeeklyRs,
      perDay: 'only Rs 29/day',
    ),
    _ProPackage(
      days: '15 Din',
      subtitle: 'Half month package',
      price: AppConfig.proHalfMonthRs,
      perDay: 'only Rs 33/day',
    ),
    _ProPackage(
      days: '30 Din',
      subtitle: 'Monthly package',
      price: AppConfig.proMonthlyRs,
      perDay: 'poora mahina Pro',
      badge: 'BEST VALUE',
    ),
  ];

  /// F1 (tools-fix wave 2): ONLY the benefits the code actually
  /// delivers. The old list promised zyada tool limits, rozana
  /// zyada AI Voice, AI tools par kam coins and naye features
  /// sab se pehle — none of those mechanisms exist anywhere in
  /// the code, and a PAID screen must never promise what the app
  /// does not do. Verified wiring for what IS listed:
  ///   - no ads: UnityAdsService._proNoAds — banner,
  ///     interstitial and export ads all check
  ///     ProService.proActive;
  ///   - Motion Studio PRO templates: motion_access.dart
  ///     returns proIncluded for Pro users;
  ///   - 1080p/4K export: editor_export_controller's double-ad
  ///     quality gate skips Pro users entirely.
  static const List<String> _benefits = <String>[
    'No ads — banner, interstitial and export ads all off',
    'Motion Studio ke PRO templates shamil',
    '1080p / 4K export without the double ad',
  ];

  /// Monthly is the default selection (mockup S6).
  int _selected = 2;

  @override
  void initState() {
    super.initState();
    // Refresh the grant state so an owner-granted Pro shows up here
    // without an app restart. Fail-soft inside ProService.
    unawaited(ProService.instance.init());
  }

  static String _rs(int value) {
    if (value >= 1000) {
      return 'Rs ${value ~/ 1000},'
          '${(value % 1000).toString().padLeft(3, '0')}';
    }
    return 'Rs $value';
  }

  /// CTA: opens WhatsApp (support number, remote-config) with a
  /// prefilled Pro request naming the selected package — the
  /// Advertise page's booking pattern. The user attaches the
  /// payment screenshot in that chat.
  Future<void> _getPro() async {
    final _ProPackage pkg = _packages[_selected];
    final String text = 'Assalam-o-Alaikum, I want TJ Pro PRO '
        '— ${pkg.days} (${_rs(pkg.price)}). I have made the payment, '
        'I am sending the screenshot.';
    final Uri uri = Uri.parse(
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

  Widget _packageCard(int index) {
    final _ProPackage pkg = _packages[index];
    final bool selected = index == _selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: selected
                ? TjProTheme.motionPanelRaised
                : TjProTheme.motionPanel,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _selected = index),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selected ? _gold : TjProTheme.motionBorder,
                    width: selected ? 1.6 : 1,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    // Radio circle.
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected ? _gold : Colors.white38,
                          width: 2,
                        ),
                      ),
                      child: selected
                          ? Center(
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _gold,
                                ),
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pkg.days,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pkg.subtitle,
                            style: const TextStyle(
                              color: TjProTheme.motionTextSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _rs(pkg.price),
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          pkg.perDay,
                          style: const TextStyle(
                            color: TjProTheme.motionTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (pkg.badge != null)
            Positioned(
              top: -10,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _gold,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  pkg.badge!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _paymentRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14)),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // v1.18.0 (Motion reskin): the old light-cream page (an
      // older era's design) joins the app-wide navy/glass skin;
      // gold stays as Pro's own accent (crown, selection, CTA).
      backgroundColor: TjProTheme.motionBgBottom,
      body: SafeArea(
        child: ValueListenableBuilder<RemoteConfig>(
          valueListenable: RemoteConfigService.instance.notifier,
          builder: (context, config, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  // Gold crown header.
                  Center(
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            Color(0xFFFFD54F),
                            Color(0xFFFFA000),
                          ],
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Color(0x55FFA000),
                            blurRadius: 24,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.workspace_premium,
                        size: 44,
                        color: _goldDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text.rich(
                    TextSpan(
                      children: <TextSpan>[
                        TextSpan(
                          text: 'TJ Pro ',
                          style: TextStyle(color: Colors.white),
                        ),
                        TextSpan(
                          text: 'PRO',
                          style: TextStyle(color: _gold),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Everything — with higher limits, without interruption',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: TjProTheme.motionTextSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 22),
                  // Active state (when Pro is already granted).
                  ValueListenableBuilder<bool>(
                    valueListenable: ProService.instance.isPro,
                    builder: (context, isPro, _) {
                      final DateTime? until =
                          ProService.instance.proUntil;
                      if (!isPro || until == null) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0E2A18),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF2E7D32),
                            ),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'Your Pro is ACTIVE',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF81C784),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Expiry: ${until.day}/${until.month}/'
                                '${until.year}',
                                style: const TextStyle(
                                  color: Color(0xFF81C784),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  // Package cards.
                  for (int i = 0; i < _packages.length; i++)
                    _packageCard(i),
                  const SizedBox(height: 6),
                  // PRO KE FAYDE checklist.
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: TjProTheme.motionPanel,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: TjProTheme.motionBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PRO KE FAYDE',
                          style: TextStyle(
                            color: _gold,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final String benefit in _benefits)
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFFFFF3D6),
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    size: 15,
                                    color: _gold,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    benefit,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Payment card (numbers from remote config).
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: TjProTheme.motionPanel,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: TjProTheme.motionBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Payment — Easypaisa / Bank',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _paymentRow(
                          'Easypaisa — ${config.easypaisaTitle}',
                          config.easypaisaNumber,
                        ),
                        _paymentRow(
                          'ABL Bank — ${config.ablTitle}',
                          config.ablAccount,
                        ),
                        if (config.jazzcashNumber.isNotEmpty)
                          _paymentRow('JazzCash', config.jazzcashNumber),
                        const SizedBox(height: 10),
                        const Text(
                          'Send the screenshot after payment — your '
                          'Pro will be activated immediately.',
                          style: TextStyle(
                            color: TjProTheme.motionTextSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // CTA.
                  Material(
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _getPro,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: <Color>[
                              Color(0xFFFFC107),
                              Color(0xFFFF9800),
                            ],
                          ),
                        ),
                        child: const Text(
                          'Get Pro',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The admin can also gift Pro to a user',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: TjProTheme.motionTextSecondary, fontSize: 12),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
