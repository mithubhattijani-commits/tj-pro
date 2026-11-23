/// TJ Pro — home screen.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

import 'news/coins_screen.dart';
import 'news/login_screen.dart';
import 'news/pro_screen.dart';
import 'news/share_earn_screen.dart';
import 'news/store_screen.dart';
import 'news/templates_library_screen.dart';
import 'news/tts_studio_screen.dart';

import 'app_config.dart';
import 'projects/projects_hub_screen.dart';
import 'services/auth_service.dart';
import 'services/coin_service.dart';
import 'services/pro_service.dart';
import 'services/referral_service.dart';
import 'services/remote_config_service.dart';
import 'services/unity_ads_service.dart';
import 'services/update_service.dart';

import 'live/live_studio_screen.dart';
import 'news/news_studio_screen.dart';
import 'widgets/banner_ad_widget.dart';
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
  // Pro (v1.4.0): load the Pro entitlement next to the coin balance.
  // Fully fail-soft — no table / offline means free mode.
  await ProService.instance.init();
  // Share & Earn (v1.3.0): referral capture (deep link / clipboard),
  // first-ad hook, and the on-open reward claim. Fully fail-soft and
  // backgrounded — it can never delay or break startup.
  unawaited(ReferralService.instance.init());
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
  /// and the News Studio entries both open [NewsStudioScreen] — one
  /// entry point, so Phase 3/6 only extend that screen, never
  /// re-route.
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

  void _openHub(String kind) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectsHubScreen(kind: kind),
      ),
    );
  }

  void _open(Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  /// Account row tap (v1.5.0 grouped MORE): signed-in → sign-out
  /// confirm; guest → login screen — via the shared top-level
  /// flow helpers below.
  void _accountTap() {
    if (AuthService.isSignedIn) {
      _confirmSignOutFlow(context, () => setState(() {}));
    } else {
      _openLoginFlow(context, () => setState(() {}));
    }
  }

  /// About tap: the old About card's text, as a dialog (the
  /// card itself was part of the de-grouped MORE list).
  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('About'),
        content: const Text(
          'TJ Pro by Nigraan TV — photo & video editor that works '
          'fully offline on your phone. No account, no uploads.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
              actions: [
                // Pro: gold CROWN opens the Pro screen (v1.5.0,
                // #13 — the old workspace_premium rosette read as a
                // medal, not a crown; _CrownIcon draws a real one).
                IconButton(
                  icon: const _CrownIcon(size: 26),
                  tooltip: 'TJ Pro — Go Pro',
                  onPressed: () => _open(const ProScreen()),
                ),
                // v1.5.2 (fix #54, app-wide duplicate sweep): the
                // Coins pill is GONE from the AppBar — it was a
                // second Coins entry point next to the Watch Ads
                // card below (which now carries the live balance
                // itself). ONE entry point per action.
                // Account (its ONE Home entry — it lived only in
                // the deleted MORE list).
                IconButton(
                  icon: const Icon(Icons.person_outline),
                  tooltip: 'Account',
                  onPressed: _accountTap,
                ),
              ],
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
                : Container(
                    decoration: const BoxDecoration(
                      // v1.5.0 (#1/H1): dark news-studio backdrop
                      // (the old cream→pink gradient was the last
                      // non-studio surface on Home).
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF0B1026),
                          Color(0xFF131A33),
                          Color(0xFF1B1035),
                        ],
                      ),
                    ),
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        // Header block (S1): remote logo (when set,
                        // with error-fallback to nothing), the Nigraan
                        // TV presents line, the site pill, the LIVE
                        // NEWS STUDIO line, the bundled heading and the
                        // Remote Config announcement bar (only when
                        // enabled with non-empty text). The remote
                        // display name stays in the AppBar title.
                        ValueListenableBuilder<RemoteConfig>(
                          valueListenable: remoteConfigService.notifier,
                          builder: (
                            BuildContext context,
                            RemoteConfig cfg,
                            Widget? child,
                          ) {
                            return Column(
                              children: <Widget>[
                                if (cfg.logoUrl.isNotEmpty)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 12),
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
                                const Text(
                                  'NIGRAAN TV PRESENTS',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 3,
                                    color: Color(0xFFF5C542),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF232C4E),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Text(
                                    'nigraantv.xyz',
                                    style: TextStyle(
                                      color: Color(0xFFFFE0B2),
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Icon(
                                      Icons.circle,
                                      size: 9,
                                      color: Color(0xFFD32F2F),
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'LIVE NEWS STUDIO',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 2,
                                        color: Color(0xFFFF8A80),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  AppConfig.homeHeading,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                if (cfg.announcement.show)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: _AnnouncementBar(
                                        text: cfg.announcement.text),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        // CREATE NEW (S1): three big circular gradient
                        // buttons; each opens that kind's Projects hub
                        // (projects list + start-from flow), NOT the
                        // editor directly. Direct editor entries stay
                        // reachable in the More section below.
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                'CREATE NEW',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  if (AppConfig.videoEditorEnabled)
                                    Expanded(
                                      child: _CreateCircleButton(
                                        icon: Icons.play_arrow,
                                        label: 'Video',
                                        colors: const [
                                          Color(0xFFF43F5E),
                                          Color(0xFFE11D48),
                                        ],
                                        onTap: () => _openHub('video'),
                                      ),
                                    ),
                                  if (AppConfig.photoEditorEnabled)
                                    Expanded(
                                      child: _CreateCircleButton(
                                        icon: Icons.image,
                                        label: 'Photo',
                                        colors: const [
                                          Color(0xFFFF8A50),
                                          Color(0xFFF4511E),
                                        ],
                                        onTap: () => _openHub('photo'),
                                      ),
                                    ),
                                  if (AppConfig.newsStudioEnabled)
                                    Expanded(
                                      child: _CreateCircleButton(
                                        icon: Icons.newspaper,
                                        label: 'News Studio',
                                        colors: const [
                                          Color(0xFFFFB300),
                                          Color(0xFFFF8F00),
                                        ],
                                        onTap: () => _openHub('news'),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Live Streaming card (S1) -> existing Live
                        // Studio screen.
                        if (AppConfig.liveStudioEnabled)
                          Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFFE53935),
                                  Color(0xFFB71C1C),
                                ],
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: InkWell(
                              onTap: () =>
                                  _open(const LiveStudioScreen()),
                              borderRadius: BorderRadius.circular(18),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: <Widget>[
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                            color: Colors.white70),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Icon(Icons.circle,
                                              size: 8,
                                              color: Colors.white),
                                          SizedBox(width: 5),
                                          Text(
                                            'LIVE',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            'Live Streaming',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            'Facebook · YouTube par live jayein',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withValues(alpha: 0.18),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.sensors,
                                          color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        // Two half cards (S1): Watch Ads / Earn Coins
                        // (same Coins screen the old UI opened) and
                        // Invite / Share & Earn. v1.5.2 (fix #55):
                        // the Watch Ads card carries the LIVE coin
                        // balance in its subtitle — the earning
                        // entry point and the balance in one glance.
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: ValueListenableBuilder<int>(
                                valueListenable:
                                    CoinService.instance.balance,
                                builder: (context, balance, _) =>
                                    _HalfCard(
                                  icon: Icons.monetization_on,
                                  iconColor: const Color(0xFFF59E0B),
                                  title: 'Watch Ads',
                                  subtitle:
                                      'Earn Coins • Balance: $balance',
                                  onTap: () =>
                                      _open(const CoinsScreen()),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _HalfCard(
                                icon: Icons.group_add,
                                iconColor: const Color(0xFF22C55E),
                                title: 'Invite',
                                subtitle: 'Share & Earn',
                                onTap: () =>
                                    _open(const ShareEarnScreen()),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // v1.5.2 (fix #54): the second half-card row
                        // re-homes the two MORE-list destinations
                        // that had no top entry — Check for updates
                        // and About — each exactly once.
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _HalfCard(
                                icon: Icons.system_update,
                                iconColor: const Color(0xFF38BDF8),
                                title: 'Updates',
                                subtitle: 'Check for updates',
                                onTap: () => UpdateService.checkManually(
                                    context),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _HalfCard(
                                icon: Icons.info_outline,
                                iconColor: const Color(0xFFA78BFA),
                                title: 'About',
                                subtitle: 'TJ Pro • Nigraan TV',
                                onTap: _showAbout,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // WHAT'S NEW strip (S1): header + Store link,
                        // then three image cards into existing
                        // destinations.
                        Row(
                          children: <Widget>[
                            const Expanded(
                              child: Text(
                                "WHAT'S NEW",
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                  color: Color(0xFFF5C542),
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _open(const StoreScreen()),
                              child: const Text(
                                'Store >',
                                style: TextStyle(
                                  color: Color(0xFFF5C542),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 170,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: <Widget>[
                              _WhatsNewCard(
                                asset: 'assets/backgrounds/newsroom.jpg',
                                label: 'News Templates',
                                onTap: () => _open(
                                    const TemplatesLibraryScreen()),
                              ),
                              const SizedBox(width: 12),
                              _WhatsNewCard(
                                asset: 'assets/backgrounds/studio_desk.jpg',
                                label: 'Music & Voice',
                                onTap: () =>
                                    _open(const TtsStudioScreen()),
                              ),
                              // v1.5.2 (fix #54): the 'Effects
                              // Packs' card is REMOVED — it opened
                              // the Store, which the 'Store >' link
                              // above already opens (one entry).
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Remote Config sponsored ad card: shown only
                        // when the config enables it. The image hides
                        // gracefully on load failure; the tap opens
                        // the action URL in the external browser.
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
                        // v1.5.2 (fix #54 — the user's explicit
                        // order): the ENTIRE bottom MORE list is
                        // DELETED. Every row in it duplicated a top
                        // entry (Invite, Coins, Pro, the editors,
                        // Live Studio, News Studio, the Store) or
                        // has been re-homed exactly once above:
                        // Account -> the AppBar person icon,
                        // Updates + About -> the second half-card
                        // row, Support -> the HelpWhatsAppRow at
                        // the bottom of this screen. The editors
                        // live behind the CREATE NEW hubs, News
                        // Studio behind its bottom-nav tab, the
                        // Store behind 'Store >', Pro behind the
                        // AppBar crown.
                        const SizedBox(height: 16),
                        const Text(
                          'Works offline. No account, no uploads — '
                          'everything is processed on your phone. '
                          'Basic editing is free; Premium AI tools unlock '
                          'with coins — earn coins by watching ads in the '
                          'Coins section.',
                          style: TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        const AdvertisingBanner(),
                        const SizedBox(height: 16),
                        const Center(child: BannerAdWidget()),
                        const SizedBox(height: 16),
                        // "For Help" row (Phase 10): WhatsApp support
                        // at the very end of home, number from remote
                        // config.
                        const HelpWhatsAppRow(),
                      ],
                    ),
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

/// One big circular gradient button in the CREATE NEW card (S1).
class _CreateCircleButton extends StatelessWidget {
  const _CreateCircleButton({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: colors.last.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 38),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF212121),
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// One of the two white half cards under the Live card (S1).
class _HalfCard extends StatelessWidget {
  const _HalfCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF212121),
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      subtitle,
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 12),
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

/// One image card in the WHAT'S NEW strip (S1).
class _WhatsNewCard extends StatelessWidget {
  const _WhatsNewCard({
    required this.asset,
    required this.label,
    required this.onTap,
  });

  final String asset;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 150,
        height: 170,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Image.asset(asset, fit: BoxFit.cover),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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

/// Shared login flow (Phase 10; extracted in v1.5.0 for the Home
/// grouped Account row — it replaces the old _LoginTile card).
Future<void> _openLoginFlow(
  BuildContext context,
  VoidCallback onAuthChanged,
) async {
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

/// Shared sign-out confirm flow (see [_openLoginFlow]).
Future<void> _confirmSignOutFlow(
  BuildContext context,
  VoidCallback onAuthChanged,
) async {
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


/// A real crown glyph (v1.5.0, #13) — Material has no crown icon,
/// and Icons.workspace_premium reads as a medal/rosette. Three
/// points + band + jewels, drawn in gold.
class _CrownIcon extends StatelessWidget {
  const _CrownIcon({this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: const _CrownPainter(Color(0xFFFFC107)),
    );
  }
}

class _CrownPainter extends CustomPainter {
  const _CrownPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(w * 0.08, h * 0.76)
      ..lineTo(w * 0.03, h * 0.30)
      ..lineTo(w * 0.30, h * 0.52)
      ..lineTo(w * 0.50, h * 0.16)
      ..lineTo(w * 0.70, h * 0.52)
      ..lineTo(w * 0.97, h * 0.30)
      ..lineTo(w * 0.92, h * 0.76)
      ..close();
    canvas.drawPath(path, fill);
    canvas.drawRect(
      Rect.fromLTWH(w * 0.08, h * 0.81, w * 0.84, h * 0.09),
      fill,
    );
    final jewel = Paint()..color = Colors.white.withValues(alpha: 0.9);
    for (final cx in <double>[0.06, 0.50, 0.94]) {
      canvas.drawCircle(Offset(w * cx, h * 0.24), w * 0.05, jewel);
    }
  }

  @override
  bool shouldRepaint(_CrownPainter oldDelegate) =>
      oldDelegate.color != color;
}
