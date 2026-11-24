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
import 'services/crash_guard.dart';
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
  // Phase 0 crash guard: the whole startup runs inside a guarded
  // zone; errors that escape it land in [CrashGuard.report] (logged
  // + surfaced) instead of taking the app down silently. The
  // framework/platform handlers are installed first thing inside.
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      CrashGuard.install();
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
      // Phase 0 (#34): if a previous session was killed while the
      // system DownloadManager was fetching an update, re-attach to
      // that download so its progress/completion survive the kill.
      // Backgrounded and fail-soft — never blocks startup.
      unawaited(UpdateService.restorePendingDownload());
      runApp(const PhotoVideoEditorApp());
    },
    (Object error, StackTrace stack) =>
        CrashGuard.report(error, stack, source: 'zone'),
  );
}

class PhotoVideoEditorApp extends StatelessWidget {
  const PhotoVideoEditorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      // Phase 0: lets [CrashGuard] surface caught errors as a
      // snackbar from anywhere, no BuildContext needed.
      scaffoldMessengerKey: CrashGuard.messengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: TjProTheme.gold,
          brightness: Brightness.dark,
        ),
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

  /// Build 4 (Home reference): hero carousel state.
  final PageController _heroController = PageController();
  int _heroPage = 0;

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
    _heroController.dispose();
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
      MaterialPageRoute(builder: (_) => ProjectsHubScreen(kind: kind)),
    );
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
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
      // Build 4 (Home, user reference "same to same"): the AppBar
      // is replaced by the reference header (logo + TJ Pro /
      // Creative Studio + Premium pill + avatar), visible on all
      // tabs like the AppBar was.
      body: Column(
        children: [
          ValueListenableBuilder<RemoteConfig>(
            valueListenable: remoteConfigService.notifier,
            builder: (context, cfg, _) => _homeHeader(cfg),
          ),
          const UpdateProgressBar(),
          Expanded(
            child: _tabIndex == 1 && AppConfig.newsStudioEnabled
                ? const NewsStudioScreen()
                : _tabIndex == 2 && AppConfig.newsStudioEnabled
                ? const CoinsScreen()
                : Container(
                    decoration: const BoxDecoration(
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
                    // Eager column in a scroll view (not a lazy
                    // ListView): every section exists in the tree
                    // immediately, like the pre-redesign home whose
                    // cards were all in the first viewport.
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Remote announcement (config-driven,
                          // only when enabled with text).
                          ValueListenableBuilder<RemoteConfig>(
                            valueListenable: remoteConfigService.notifier,
                            builder: (context, cfg, _) {
                              if (!cfg.announcement.show) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _AnnouncementBar(
                                  text: cfg.announcement.text,
                                ),
                              );
                            },
                          ),
                          _heroCarousel(),
                          const SizedBox(height: 14),
                          // Three big cards -> the existing
                          // Projects hubs (the editors' entries).
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (AppConfig.videoEditorEnabled)
                                Expanded(
                                  child: _bigCard(
                                    icon: Icons.play_circle_fill,
                                    title: 'VIDEO EDITOR',
                                    subtitle: 'Edit Like a Pro',
                                    colors: const [
                                      Color(0xFF8E24AA),
                                      Color(0xFF4A148C),
                                    ],
                                    pillColor: const Color(0xFFAB47BC),
                                    onTap: () => _openHub('video'),
                                  ),
                                ),
                              if (AppConfig.videoEditorEnabled &&
                                  AppConfig.photoEditorEnabled)
                                const SizedBox(width: 10),
                              if (AppConfig.photoEditorEnabled)
                                Expanded(
                                  child: _bigCard(
                                    icon: Icons.image,
                                    title: 'PHOTO EDITOR',
                                    subtitle: 'Enhance Your Photos',
                                    colors: const [
                                      Color(0xFF1565C0),
                                      Color(0xFF0D47A1),
                                    ],
                                    pillColor: const Color(0xFF1E88E5),
                                    onTap: () => _openHub('photo'),
                                  ),
                                ),
                              if ((AppConfig.videoEditorEnabled ||
                                      AppConfig.photoEditorEnabled) &&
                                  AppConfig.newsStudioEnabled)
                                const SizedBox(width: 10),
                              if (AppConfig.newsStudioEnabled)
                                Expanded(
                                  child: _bigCard(
                                    icon: Icons.mic,
                                    title: 'NEWS STUDIO',
                                    subtitle: 'Create & Broadcast',
                                    colors: const [
                                      Color(0xFFF9A825),
                                      Color(0xFFE65100),
                                    ],
                                    pillColor: const Color(0xFFFFB300),
                                    onTap: () => _openHub('news'),
                                  ),
                                ),
                            ],
                          ),
                          if (AppConfig.liveStudioEnabled) ...[
                            const SizedBox(height: 14),
                            _liveBanner(),
                          ],
                          const SizedBox(height: 18),
                          // WHAT'S NEW (reference): header + View
                          // All -> Store; four cards.
                          Row(
                            children: [
                              const Icon(
                                Icons.chevron_right,
                                color: Color(0xFFF5C542),
                                size: 20,
                              ),
                              const Expanded(
                                child: Text(
                                  "What's New",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => _open(const StoreScreen()),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'View All',
                                      style: TextStyle(
                                        color: Color(0xFFF5C542),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_forward,
                                      size: 15,
                                      color: Color(0xFFF5C542),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 148,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _whatsNewTile(
                                  asset: 'assets/backgrounds/newsroom.jpg',
                                  title: 'News Templates',
                                  subtitle: 'Professional Layouts',
                                  onTap: () =>
                                      _open(const TemplatesLibraryScreen()),
                                ),
                                const SizedBox(width: 10),
                                _whatsNewTile(
                                  asset: 'assets/backgrounds/studio_desk.jpg',
                                  title: 'Music & Voice',
                                  subtitle: 'Create & Edit Audio',
                                  onTap: () => _open(const TtsStudioScreen()),
                                ),
                                const SizedBox(width: 10),
                                _whatsNewTile(
                                  icon: Icons.auto_awesome,
                                  iconColors: const [
                                    Color(0xFF3949AB),
                                    Color(0xFF00ACC1),
                                  ],
                                  title: 'New Features',
                                  subtitle: 'Explore More',
                                  onTap: () =>
                                      UpdateService.checkManually(context),
                                ),
                                const SizedBox(width: 10),
                                _whatsNewTile(
                                  icon: Icons.photo_library,
                                  iconColors: const [
                                    Color(0xFF6A1B9A),
                                    Color(0xFFAD1457),
                                  ],
                                  title: 'Gallery',
                                  subtitle: 'Premium Collection',
                                  onTap: () => _open(const StoreScreen()),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          const AdvertisingBanner(),
                          const SizedBox(height: 14),
                          // Four small buttons (reference): the
                          // same four destinations the half cards
                          // carried — Watch Ads (with the live
                          // balance), Invite, Updates, About.
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ValueListenableBuilder<int>(
                                  valueListenable: CoinService.instance.balance,
                                  builder: (context, balance, _) =>
                                      _smallButton(
                                        icon: Icons.card_giftcard,
                                        tint: const Color(0xFFE91E63),
                                        title: 'Watch Ads',
                                        subtitle:
                                            'Earn Coins • Balance: $balance',
                                        onTap: () => _open(const CoinsScreen()),
                                      ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _smallButton(
                                  icon: Icons.group,
                                  tint: const Color(0xFF00BFA5),
                                  title: 'Invite',
                                  subtitle: 'Share & Earn',
                                  onTap: () => _open(const ShareEarnScreen()),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _smallButton(
                                  icon: Icons.refresh,
                                  tint: const Color(0xFF2979FF),
                                  title: 'Updates',
                                  subtitle: 'Check for Updates',
                                  onTap: () =>
                                      UpdateService.checkManually(context),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _smallButton(
                                  icon: Icons.info,
                                  tint: const Color(0xFF7C4DFF),
                                  title: 'About',
                                  subtitle: 'TJ Pro & Nigraan TV',
                                  onTap: _showAbout,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Works offline. No account, no uploads — '
                            'everything is processed on your phone. '
                            'Basic editing is free; Premium AI tools unlock '
                            'with coins — earn coins by watching ads in the '
                            'Coins section.',
                            style: TextStyle(color: Colors.white70),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          // Remote Config sponsored ad card (only
                          // when the config enables it).
                          ValueListenableBuilder<RemoteConfig>(
                            valueListenable: remoteConfigService.notifier,
                            builder: (context, cfg, _) {
                              if (!cfg.sponsoredAd.show) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                children: [
                                  _SponsoredAdCard(ad: cfg.sponsoredAd),
                                  const SizedBox(height: 14),
                                ],
                              );
                            },
                          ),
                          const Center(child: BannerAdWidget()),
                          const SizedBox(height: 16),
                          const HelpWhatsAppRow(),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
      // Bottom nav (reference): Home | News Studio | Earn.
      bottomNavigationBar: AppConfig.newsStudioEnabled
          ? BottomNavigationBar(
              currentIndex: _tabIndex,
              onTap: (index) => setState(() => _tabIndex = index),
              backgroundColor: const Color(0xFF0B1026),
              selectedItemColor: const Color(0xFFF5C542),
              unselectedItemColor: Colors.white60,
              items: const [
                BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(
                  icon: Icon(Icons.newspaper),
                  label: 'News Studio',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.monetization_on),
                  label: 'Earn',
                ),
              ],
            )
          : null,
    );
  }

  /// Reference header: TJ Pro play badge (or the remote logo when
  /// one is set), name + taglines, the gold Premium pill (the Pro
  /// screen — the old AppBar crown's destination), and the avatar
  /// (the Account flow — the old AppBar person icon).
  Widget _homeHeader(RemoteConfig cfg) {
    final String title = cfg.displayName.isNotEmpty
        ? cfg.displayName
        : AppConfig.appName;
    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        MediaQuery.of(context).padding.top + 8,
        14,
        10,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1026), Color(0xFF101736)],
        ),
      ),
      child: Row(
        children: [
          if (cfg.logoUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Image.network(
                cfg.logoUrl,
                height: 42,
                errorBuilder: (context, error, stackTrace) =>
                    const _PlayBadge(),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: _PlayBadge(),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.05,
                  ),
                ),
                const Text(
                  'Creative Studio',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFF5C542),
                    height: 1.1,
                  ),
                ),
                const Text(
                  'Create • Edit • Earn',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Colors.white60,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => _open(const ProScreen()),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF3A2A00), Color(0xFF241A00)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFF5C542)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CrownIcon(size: 16),
                  SizedBox(width: 5),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Premium',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFF5C542),
                          height: 1.0,
                        ),
                      ),
                      Text(
                        'Member',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: Color(0xFFF5C542),
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: _accountTap,
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                const CircleAvatar(
                  radius: 17,
                  backgroundColor: Color(0xFF232C4E),
                  child: Icon(Icons.person, size: 19, color: Colors.white70),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0B1026),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Hero carousel: slide 1 = the News Studio banner (Watch Live
  /// -> Live Studio); slide 2 (when a banner is booked/enabled) =
  /// the remote ADMIN house-ad banner with its existing behaviour
  /// (contain fit, never cropped; tap opens its link when set).
  Widget _heroCarousel() {
    return ValueListenableBuilder<RemoteConfig>(
      valueListenable: remoteConfigService.notifier,
      builder: (context, cfg, _) {
        final showAdmin =
            cfg.advertisingBannerEnabled &&
            cfg.advertisingBannerImageUrl.isNotEmpty;
        final slides = <Widget>[
          _newsHeroSlide(),
          if (showAdmin) _adminHeroSlide(cfg),
        ];
        return Column(
          children: [
            SizedBox(
              height: 178,
              child: PageView(
                controller: _heroController,
                onPageChanged: (i) => setState(() => _heroPage = i),
                children: slides,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < slides.length; i++)
                  GestureDetector(
                    onTap: () => _heroController.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    ),
                    child: Container(
                      width: i == _heroPage ? 16 : 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == _heroPage
                            ? const Color(0xFFF5C542)
                            : Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _newsHeroSlide() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D1B4C), Color(0xFF123A7A), Color(0xFF0A1030)],
        ),
        border: Border.all(color: const Color(0x33F5C542)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(const LiveStudioScreen()),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              top: -30,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                    width: 14,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0A1030),
                          border: Border.all(
                            color: const Color(0xFFF5C542),
                            width: 1.6,
                          ),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'نگران',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                height: 1.0,
                              ),
                            ),
                            Text(
                              'TV',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFE53935),
                                height: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD32F2F),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 7, color: Colors.white),
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
                    ],
                  ),
                  const Spacer(),
                  const Text(
                    'GLOBAL & PAKISTAN',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.6,
                      color: Color(0xFFF5C542),
                    ),
                  ),
                  const Text(
                    'NEWS STUDIO',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD32F2F),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_circle_fill,
                          size: 15,
                          color: Colors.white,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Watch Live',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.double_arrow, size: 13, color: Colors.white),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The admin house-ad banner as a carousel slide — the SAME
  /// rendering as the Advertise page: BoxFit.contain on a neutral
  /// letterbox, NEVER cropped; tap opens the banner link when one
  /// is set (no link = no handler, as before).
  Widget _adminHeroSlide(RemoteConfig cfg) {
    final url = cfg.advertisingBannerImageUrl;
    final link = cfg.advertisingBannerLinkUrl.trim();
    return Container(
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onTap: link.isEmpty
            ? null
            : () async {
                final uri = Uri.parse(link);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
        child: url.startsWith('assets/')
            ? Image.asset(
                url,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              )
            : Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
      ),
    );
  }

  /// One of the three big editor cards (reference): glossy
  /// gradient, big icon, title, tagline, gold-toned Open pill.
  Widget _bigCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Color> colors,
    required Color pillColor,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
          child: Column(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: Colors.white, size: 27),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 10.5),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: pillColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Open',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward, size: 13, color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Live Streaming banner (reference): LIVE badge, title,
  /// Join Now pill, Facebook/YouTube Live chips — everything goes
  /// to the existing Live Studio.
  Widget _liveBanner() {
    void openLive() => _open(const LiveStudioScreen());
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF1A237E), Color(0xFF6A1B9A), Color(0xFFAD1457)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: InkWell(
        onTap: openLive,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD32F2F),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, size: 7, color: Colors.white),
                          SizedBox(width: 5),
                          Text(
                            'LIVE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'Live '),
                          TextSpan(
                            text: 'Streaming',
                            style: TextStyle(color: Color(0xFFF5C542)),
                          ),
                        ],
                      ),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Text(
                      'Facebook • YouTube par live dekhain',
                      style: TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                    const SizedBox(height: 9),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD32F2F),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sensors, size: 14, color: Colors.white),
                          SizedBox(width: 6),
                          Text(
                            'Join Now',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward,
                            size: 13,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mic, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 10),
                  _liveChip(Icons.facebook, 'Facebook Live', openLive),
                  const SizedBox(height: 6),
                  _liveChip(Icons.smart_display, 'YouTube Live', openLive),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _liveChip(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }

  /// One What's New tile: image (or gradient + icon) top, title,
  /// subtitle, chevron — the reference card shape.
  Widget _whatsNewTile({
    String? asset,
    IconData? icon,
    List<Color>? iconColors,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      width: 128,
      decoration: BoxDecoration(
        color: const Color(0xFF141B31),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 82,
              width: double.infinity,
              child: asset != null
                  ? Image.asset(asset, fit: BoxFit.cover)
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: iconColors!,
                        ),
                      ),
                      child: Icon(
                        icon,
                        color: Colors.white.withValues(alpha: 0.9),
                        size: 36,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 7, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: Colors.white38,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One of the four small buttons under the Advertising banner
  /// (reference): tinted dark tile, icon, title, subtitle.
  Widget _smallButton({
    required IconData icon,
    required Color tint,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint.withValues(alpha: 0.34), tint.withValues(alpha: 0.13)],
        ),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: tint.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, color: tint, size: 23),
              const SizedBox(height: 6),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                subtitle,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 9,
                  height: 1.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The TJ Pro play badge from the reference header: a glossy
/// gradient squircle with a white play triangle.
class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF7043), Color(0xFFD81B60), Color(0xFF3949AB)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.play_arrow, color: Colors.white, size: 26),
    );
  }
}

class AdvertisingBanner extends StatelessWidget {
  const AdvertisingBanner({super.key});

  Future<void> _openWhatsApp() async {
    final Uri uri = Uri.parse(AppConfig.supportWhatsAppLink);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // Build 4 (Home reference): the "For Advertising" banner in
  // the reference's shape — dark blue/gold, megaphone, WhatsApp
  // number (from AppConfig, as before), gold Chat Now pill. The
  // tap is the same WhatsApp flow as before. (The bundled house
  // banner image itself now lives in the hero carousel's admin
  // slide.)
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D2137), Color(0xFF14324F), Color(0xFF7A5A00)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x55F5C542)),
      ),
      child: InkWell(
        onTap: _openWhatsApp,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFFF5C542),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.campaign,
                  color: Colors.black87,
                  size: 24,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'For Advertising',
                      style: TextStyle(
                        color: Color(0xFFFFD76A),
                        fontSize: 16.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Contact Us on WhatsApp:',
                      style: TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                    SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.chat, color: Color(0xFF25D366), size: 15),
                        SizedBox(width: 5),
                        Text(
                          AppConfig.supportWhatsAppNumber,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5C542),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Chat Now',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward, size: 13, color: Colors.black),
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
                ) => const SizedBox.shrink(),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.campaign_outlined, color: TjProTheme.gold),
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
  bool shouldRepaint(_CrownPainter oldDelegate) => oldDelegate.color != color;
}
