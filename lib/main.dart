/// TJ Pro — home screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

import 'photo/photo_editor_screen.dart';
import 'app_config.dart';
import 'services/ad_service.dart';
import 'services/remote_config_service.dart';
import 'services/unity_ads_service.dart';
import 'services/update_service.dart';
import 'video/video_editor_screen.dart';
import 'live/live_studio_screen.dart';
import 'widgets/banner_ad_widget.dart';
import 'widgets/native_ad_widget.dart';

/// Shared Remote Config instance: fetched once at startup; the home
/// screen listens to [RemoteConfigService.notifier] so a fresh fetch
/// updates branding, announcements and ads without a restart.
final RemoteConfigService remoteConfigService = RemoteConfigService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AdService.init();
  UnityAdsService.init();
  // Remote Config: returns fast (cache load only); the network refresh
  // is backgrounded and never blocks startup.
  await remoteConfigService.init();
  runApp(const PhotoVideoEditorApp());
}

class PhotoVideoEditorApp extends StatelessWidget {
  const PhotoVideoEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: TjProTheme.gold, brightness: Brightness.dark),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Installed build number, loaded once after the first frame.
  int _installedVersionCode = 0;

  /// Last force-update min_version_code already evaluated, so a
  /// re-armed kill-switch (raised min) is honoured on the next
  /// config refresh.
  int _forceUpdateCheckedMin = -1;

  @override
  void initState() {
    super.initState();
    // Post-launch flow: load the installed build number first, then
    // run the ad/update sequencing. Awaiting one method-channel call
    // keeps the force-update armed-check race-free.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_startPostLaunchFlow());
    });
  }

  @override
  void dispose() {
    remoteConfigService.notifier.removeListener(_onRemoteConfigChanged);
    super.dispose();
  }

  Future<void> _startPostLaunchFlow() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      _installedVersionCode = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {
      _installedVersionCode = 0;
    }
    if (!mounted) return;
    // Remote Config force-update kill-switch: evaluated now (cached
    // config) and on every background refresh, so a fresh kill-switch
    // trips without an app restart.
    remoteConfigService.notifier.addListener(_onRemoteConfigChanged);
    _onRemoteConfigChanged();
    // Silent update check: shows a dialog only when a newer version
    // exists; a missing manifest or no network means no prompt at all.
    // Cold-start app open ad first; the update dialog waits for the
    // next launch when an ad was shown, so the two never stack.
    // When the force-update kill-switch is armed, the non-dismissible
    // force dialog handles the update instead of the normal prompt.
    if (!AdService.showAppOpen() && !_forceUpdateArmed()) {
      UpdateService.checkOnLaunch(context);
    }
  }

  /// Synchronous kill-switch check against the cached config and the
  /// installed build number. Used to prefer the non-dismissible force
  /// dialog over the normal update prompt.
  bool _forceUpdateArmed() {
    final ForceUpdateConfig fu = remoteConfigService.config.forceUpdate;
    return fu.enabled &&
        _installedVersionCode > 0 &&
        _installedVersionCode < fu.minVersionCode;
  }

  /// Fires on every config change so a background refresh can trip a
  /// newly armed kill-switch while the app is running.
  void _onRemoteConfigChanged() {
    if (!mounted) return;
    final ForceUpdateConfig fu = remoteConfigService.config.forceUpdate;
    if (!fu.enabled || fu.minVersionCode == _forceUpdateCheckedMin) {
      return;
    }
    if (_installedVersionCode <= 0) {
      // Post-launch flow not finished yet; the explicit call in
      // _startPostLaunchFlow (or the next config change) retries.
      return;
    }
    _forceUpdateCheckedMin = fu.minVersionCode;
    unawaited(_runForceUpdateCheck(fu.minVersionCode));
  }

  /// Force-update path, wired to the existing update flow: the manifest
  /// decides whether a newer APK actually exists; when it does, a
  /// non-dismissible dialog pushes the same background download +
  /// system install-prompt flow. Never throws, never blocks the app.
  Future<void> _runForceUpdateCheck(int minVersionCode) async {
    try {
      final int installed = _installedVersionCode;
      if (installed <= 0 || installed >= minVersionCode) {
        return;
      }
      final UpdateCheckOutcome outcome = await UpdateService.checkForUpdate();
      if (!mounted) {
        return;
      }
      final UpdateInfo? update = outcome.update;
      if (update != null) {
        UpdateService.showForceUpdateDialog(context, update);
      }
      // If the manifest has no newer version, stay fail-soft: a broken
      // or stale manifest must never brick the app.
    } catch (_) {
      // A config problem must never block or crash the app.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ValueListenableBuilder<RemoteConfig>(
          valueListenable: remoteConfigService.notifier,
          builder: (
            BuildContext context,
            RemoteConfig cfg,
            Widget? child,
          ) {
            final String title = cfg.displayName.isNotEmpty
                ? cfg.displayName
                : AppConfig.appName;
            return AppBar(title: Text(title));
          },
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Remote Config header: remote logo (when set, with
          // error-fallback to nothing), the bundled heading, and the
          // announcement bar (only when enabled with non-empty text).
          ValueListenableBuilder<RemoteConfig>(
            valueListenable: remoteConfigService.notifier,
            builder: (
              BuildContext context,
              RemoteConfig cfg,
              Widget? child,
            ) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (cfg.logoUrl.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Image.network(
                        cfg.logoUrl,
                        height: 48,
                        errorBuilder: (
                          BuildContext context,
                          Object error,
                          StackTrace? stackTrace,
                        ) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  Text(
                    AppConfig.homeHeading,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  if (cfg.announcement.show)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child:
                          _AnnouncementBar(text: cfg.announcement.text),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          if (AppConfig.photoEditorEnabled)
            _EntryCard(
              icon: Icons.photo,
            title: 'Photo Editor',
            subtitle:
                'Filters, crop, rotate, brightness, text, AI tools',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PhotoEditorScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          if (AppConfig.videoEditorEnabled)
            _EntryCard(
              icon: Icons.videocam,
            title: 'Video Editor',
            subtitle:
                'Trim, cut & merge, text, music, speed, filters, crossfade',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const VideoEditorScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          if (AppConfig.liveStudioEnabled)
            _EntryCard(
              icon: Icons.live_tv,
              title: 'Live Studio',
              subtitle:
                  'Facebook + YouTube par ek saath live — breaking news templates ke saath',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LiveStudioScreen(),
                  ),
                );
              },
            ),
          const SizedBox(height: 16),
          // Remote Config sponsored ad card: shown only when the config
          // enables it. The image hides gracefully on load failure; the
          // tap opens the action URL in the external browser.
          ValueListenableBuilder<RemoteConfig>(
            valueListenable: remoteConfigService.notifier,
            builder: (
              BuildContext context,
              RemoteConfig cfg,
              Widget? child,
            ) {
              if (!cfg.sponsoredAd.show) {
                return const SizedBox.shrink();
              }
              return Column(
                children: <Widget>[
                  _SponsoredAdCard(ad: cfg.sponsoredAd),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
          const NativeAdWidget(),
          const SizedBox(height: 16),
          const _PremiumUnlockCard(),
          const SizedBox(height: 16),
          const Text(
            'Works offline. No account, no uploads — '
            'everything is processed on your phone. '
            'Basic editing is free; Premium AI tools unlock '
            'with one short ad.',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.system_update),
              title: const Text('Check for updates'),
              subtitle: const Text(
                'Naya version aaye to yahan se update karein.',
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 18),
              onTap: () => UpdateService.checkManually(context),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.support_agent),
              title: const Text('مدد اور سپورٹ'),
              subtitle: const Text('Jaani Bhatti — 03090808180'),
              trailing: const Icon(Icons.chat),
              onTap: () async {
                final uri = Uri.parse('https://wa.me/923090808180');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline),
                      SizedBox(width: 8),
                      Text(
                        'About',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'TJ Pro by Nigraan TV — photo & video editor that '
                    'works fully offline on your phone. No account, no '
                    'uploads.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const AdvertisingBanner(),
          const SizedBox(height: 16),
          const Center(child: BannerAdWidget()),
        ],
      ),
    );
  }
}

/// In-app advertising banner (Jaani, 2 Nov 2026): placed in the About
/// section on the home screen. Tapping opens a WhatsApp chat with
/// Nigraan TV for ad bookings.
class AdvertisingBanner extends StatelessWidget {
  const AdvertisingBanner({super.key});

  static const String _waUrl = 'https://wa.me/923090808180';

  Future<void> _openWhatsApp() async {
    final Uri uri = Uri.parse(_waUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 3,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: _openWhatsApp,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF0F2027),
                Color(0xFF203A43),
                Color(0xFF2C5364),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/jaani_ad_banner.jpg',
                  width: 84,
                  height: 112,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'For Advertising',
                      style: TextStyle(
                        color: Color(0xFFFFD76A),
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Contact Us on WhatsApp:',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.chat,
                            color: Color(0xFF25D366), size: 18),
                        SizedBox(width: 6),
                        Text(
                          '03090808180',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slim announcement bar under the home header, driven by Remote
/// Config. Rendered only when the config enables it with non-empty
/// text (see [AnnouncementConfig.show]).
class _AnnouncementBar extends StatelessWidget {
  const _AnnouncementBar({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x339C7A1F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: TjProTheme.goldDeep),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.campaign, size: 18, color: TjProTheme.gold),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sponsored ad card driven by Remote Config (nigraantv.xyz).
/// Shows only when the config enables it with a title and action URL.
/// The creative hides gracefully when it fails to load; the tap opens
/// the action URL in the external browser. Never auto-opens, never
/// blocks the app.
class _SponsoredAdCard extends StatelessWidget {
  const _SponsoredAdCard({required this.ad});

  final SponsoredAdConfig ad;

  Future<void> _openAd() async {
    final Uri uri = Uri.parse(ad.actionUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: _openAd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (ad.imageUrl.isNotEmpty)
              Image.network(
                ad.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (
                  BuildContext context,
                  Object error,
                  StackTrace? stackTrace,
                ) =>
                    const SizedBox.shrink(),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.campaign_outlined,
                      color: TjProTheme.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      ad.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.open_in_new, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumUnlockCard extends StatefulWidget {
  const _PremiumUnlockCard();

  @override
  State<_PremiumUnlockCard> createState() => _PremiumUnlockCardState();
}

class _PremiumUnlockCardState extends State<_PremiumUnlockCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.aiToolsEnabled) {
      return const SizedBox.shrink();
    }
    if (AdService.isPremiumUnlocked) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.workspace_premium),
          title: Text('Premium AI unlocked'),
          subtitle: Text('All AI tools are available.'),
        ),
      );
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.workspace_premium),
        title: const Text('Premium AI tools'),
        subtitle: const Text(
          'Background remover, blur, beautify and auto-enhance.',
        ),
        trailing: _busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: () async {
                  setState(() => _busy = true);
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await AdService.showRewarded();
                  if (mounted) {
                    setState(() => _busy = false);
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? 'Premium AI unlocked.'
                              : 'No ad was available right now. Try again.',
                        ),
                      ),
                    );
                  }
                },
                child: const Text('Watch ad'),
              ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}


