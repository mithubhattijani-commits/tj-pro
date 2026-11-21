/// TJ Pro — home screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

import 'news/coins_screen.dart';
import 'news/login_screen.dart';
import 'photo/photo_editor_screen.dart';
import 'app_config.dart';
import 'services/auth_service.dart';
import 'services/coin_service.dart';
import 'services/premium_gate.dart';
import 'services/remote_config_service.dart';
import 'services/unity_ads_service.dart';
import 'services/update_service.dart';
import 'video/video_editor_screen.dart';
import 'live/live_studio_screen.dart';
import 'news/news_studio_screen.dart';
import 'news/store_screen.dart';
import 'widgets/banner_ad_widget.dart';
import 'widgets/coins_pill.dart';
import 'widgets/help_whatsapp_button.dart';
import 'widgets/update_ui.dart';

/// Shared Remote Config instance: fetched once at startup; the home
/// screen listens to [RemoteConfigService.notifier] so a fresh fetch
/// updates branding, announcements and ads without a restart.
final RemoteConfigService remoteConfigService = RemoteConfigService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ads are Unity-only (one-build, defect #4) — AdMob was removed.
  UnityAdsService.init();
  // Remote Config: returns fast (cache load only); the network refresh
  // is backgrounded and never blocks startup.
  await remoteConfigService.init();
  // Login + Coins (Phase 10): restore the Supabase session (never
  // throws, local-only mode when no anon key was supplied at build
  // time) and load the local coin balance. Both are awaited here so
  // the app-bar coins pill is correct on first paint.
  await AuthService.init();
  await CoinService.instance.load();
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

  /// Bottom-nav tab: 0 = Home, 1 = News Studio. The News Studio tab
  /// and the 4th home card both open [NewsStudioScreen] — one entry
  /// point, so Phase 3/6 only extend that screen, never re-route.
  int _tabIndex = 0;

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
    // Update check (v1.2.0 UX): fetch silently; when a newer version
    // exists, show the once-per-launch update popup (Later snoozes it
    // for the session). The download then runs in the background with
    // the UpdateProgressBar mounted in build(). checkOnLaunch stays
    // available but is NOT also called, or the user gets two dialogs.
    // When the force-update kill-switch is armed, the non-dismissible
    // force dialog handles the update instead of the normal prompt.
    if (!_forceUpdateArmed()) {
      final UpdateInfo? update = await UpdateService.fetchUpdate();
      if (update != null && mounted) {
        showUpdatePopupOnce(context, update);
      }
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
            return AppBar(
              title: Text(title),
              // Coins pill (Phase 10): live balance, hidden for
              // admins; tap opens the Coins screen.
              actions: const [CoinsPill()],
            );
          },
        ),
      ),
      // Update progress bar (v1.2.0): zero-height while idle, so the
      // layout below is unchanged until a background update download
      // is actually running; visible on both tabs.
      body: Column(
        children: [
          const UpdateProgressBar(),
          Expanded(
            child: _tabIndex == 1 && AppConfig.newsStudioEnabled
                ? const NewsStudioScreen()
                : ListView(
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
          // News Studio (Phase 2, v1): AI News Broadcasting Studio —
          // News Maker, channel presets, breaking templates, Gemini
          // voice. Same screen as the bottom-nav tab.
          if (AppConfig.newsStudioEnabled)
            _EntryCard(
              icon: Icons.newspaper,
              title: 'News Studio',
              subtitle:
                  'AI News Broadcasting Studio — News Maker, templates, Gemini voice',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NewsStudioScreen(),
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
          // (The AdMob native ad card that used to sit here was
          // removed with AdMob — Unity has no native format in this
          // setup, defect #4.)
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
          // Login + Coins (Phase 10, News Studio v1): the login tile
          // shows the signed-in email (or Guest) and opens the login
          // screen; the coins tile shows the live balance and opens
          // the Coins screen (Watch Ads, daily claim, history).
          _LoginTile(onAuthChanged: () => setState(() {})),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.monetization_on),
              title: const Text('Coins'),
              subtitle: ValueListenableBuilder<int>(
                valueListenable: CoinService.instance.balance,
                builder: (context, balance, _) => Text(
                  'Balance: $balance coins — Watch Ads se kamayein.',
                ),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 18),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CoinsScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          // Online Store (v1.2.0): Drive-backed store — templates,
          // music, ribbons and more; new stock appears without an app
          // update. Entry is ad-gated inside the Store itself (§3.4);
          // no ad is shown here on Home (§5).
          Card(
            child: ListTile(
              leading: const Icon(Icons.storefront),
              title: const Text('Online Store'),
              subtitle: const Text(
                'Templates, music, ribbons & more — new stock weekly',
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 18),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const StoreScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.support_agent),
              title: const Text('مدد اور سپورٹ'),
              subtitle:
                  Text('Jaani Bhatti — ${AppConfig.supportWhatsAppNumber}'),
              trailing: const Icon(Icons.chat),
              onTap: () async {
                final uri = Uri.parse(AppConfig.supportWhatsAppLink);
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
          const SizedBox(height: 16),
          // "For Help" row (Phase 10): WhatsApp support at the very
          // end of home, number from remote config.
          const HelpWhatsAppRow(),
        ],
      ),
          ),
        ],
      ),
      // Bottom nav: Home + News Studio (Phase 2). Hidden entirely when
      // the News Studio switch is off — then Home is the only screen.
      bottomNavigationBar: AppConfig.newsStudioEnabled
          ? BottomNavigationBar(
              currentIndex: _tabIndex,
              onTap: (index) => setState(() => _tabIndex = index),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.newspaper),
                  label: 'News Studio',
                ),
              ],
            )
          : null,
    );
  }
}

/// In-app advertising banner (Jaani, 2 Nov 2026): placed in the About
/// section on the home screen. Tapping opens a WhatsApp chat with
/// Nigraan TV for ad bookings. Number/link come from AppConfig
/// (supportWhatsAppNumber / supportWhatsAppLink) — never hardcoded.
/// NOTE (user order 20 Nov 2026): the paid-banner flow lives on a
/// DEDICATED "Advertise" page (later phase) — this About-section card
/// is the existing house banner, not the two home slots (superseded).
class AdvertisingBanner extends StatelessWidget {
  const AdvertisingBanner({super.key});

  Future<void> _openWhatsApp() async {
    final Uri uri = Uri.parse(AppConfig.supportWhatsAppLink);
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
                          AppConfig.supportWhatsAppNumber,
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
    if (PremiumGate.isUnlocked) {
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
                  final ok = await PremiumGate.tryUnlockWithAd();
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

/// Login tile (Phase 10): shows the signed-in email (or Guest) and
/// opens [LoginScreen]; when signed in, tapping offers sign-out.
/// Rebuilds on auth-state changes via [AuthService.authStateChanges];
/// the builder reads [AuthService.isSignedIn] directly because a
/// session restored at startup emits no stream event after subscribe.
class _LoginTile extends StatelessWidget {
  const _LoginTile({required this.onAuthChanged});

  final VoidCallback onAuthChanged;

  Future<void> _openLogin(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          onSignedIn: () {
            Navigator.of(context).pop();
            onAuthChanged();
          },
          onContinueAsGuest: () => Navigator.of(context).pop(),
        ),
      ),
    );
    onAuthChanged();
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final email = AuthService.currentEmail ?? '';
    final signOut = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          'Signed in as $email.\nYour coins stay with your account — '
          'sign in again any time to get them back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (signOut == true) {
      await AuthService.signOut();
      onAuthChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: AuthService.authStateChanges,
      builder: (context, snapshot) {
        final signedIn = AuthService.isSignedIn;
        return Card(
          child: ListTile(
            leading: const Icon(Icons.login),
            title: Text(signedIn ? 'Account' : 'Login'),
            subtitle: Text(
              signedIn
                  ? (AuthService.currentEmail ?? 'Signed in')
                  : 'Guest — sign in to save your coins',
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 18),
            onTap: () => signedIn
                ? _confirmSignOut(context)
                : _openLogin(context),
          ),
        );
      },
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


