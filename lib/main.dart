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
import 'news/pro_screen.dart';
import 'news/share_earn_screen.dart';
import 'news/store_screen.dart';
import 'news/templates_library_screen.dart';
import 'news/tts_studio_screen.dart';
import 'photo/photo_editor_screen.dart';
import 'app_config.dart';
import 'projects/projects_hub_screen.dart';
import 'services/auth_service.dart';
import 'services/coin_service.dart';
import 'services/pro_service.dart';
import 'services/referral_service.dart';
import 'services/remote_config_service.dart';
import 'services/unity_ads_service.dart';
import 'services/update_service.dart';
import 'video/video_editor_screen.dart';
import 'live/live_studio_screen.dart';
import 'news/news_studio_screen.dart';
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
                // Pro (v1.4.0): gold crown opens the Pro screen.
                IconButton(
                  icon: const Icon(
                    Icons.workspace_premium,
                    color: Color(0xFFFFC107),
                  ),
                  tooltip: 'TJ Pro — Go Pro',
                  onPressed: () => _open(const ProScreen()),
                ),
                // Coins pill (Phase 10): live balance, hidden for
                // admins; tap opens the Coins screen.
                const CoinsPill(),
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
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFFDEBD2),
                          Color(0xFFFBD9C2),
                          Color(0xFFF6A8B8),
                          Color(0xFFF15A8C),
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
                                    color: Color(0xFF7C4A2D),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4E342E),
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
                                        color: Color(0xFF8E2434),
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
                                    color: Color(0xFF3E2723),
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
                        // Invite / Share & Earn.
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _HalfCard(
                                icon: Icons.monetization_on,
                                iconColor: const Color(0xFFF59E0B),
                                title: 'Watch Ads',
                                subtitle: 'Earn Coins',
                                onTap: () =>
                                    _open(const CoinsScreen()),
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
                                  color: Color(0xFF5D2E1F),
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _open(const StoreScreen()),
                              child: const Text(
                                'Store >',
                                style: TextStyle(
                                  color: Color(0xFF5D2E1F),
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
                              const SizedBox(width: 12),
                              _WhatsNewCard(
                                asset: 'assets/jaani_ad_banner.jpg',
                                label: 'Effects Packs',
                                onTap: () =>
                                    _open(const StoreScreen()),
                              ),
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
                        // MORE: every destination the old home body
                        // carried stays reachable here — nothing was
                        // removed, only reorganised.
                        const Text(
                          'MORE',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: Color(0xFF5D2E1F),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (AppConfig.newsStudioEnabled)
                          _EntryCard(
                            icon: Icons.newspaper,
                            title: 'News Studio',
                            subtitle:
                                'AI News Broadcasting Studio — News Maker, templates, Gemini voice',
                            onTap: () =>
                                _open(const NewsStudioScreen()),
                          ),
                        const SizedBox(height: 12),
                        if (AppConfig.photoEditorEnabled)
                          _EntryCard(
                            icon: Icons.photo,
                            title: 'Photo Editor',
                            subtitle:
                                'Filters, crop, rotate, brightness, text, AI tools',
                            onTap: () =>
                                _open(const PhotoEditorScreen()),
                          ),
                        const SizedBox(height: 12),
                        if (AppConfig.videoEditorEnabled)
                          _EntryCard(
                            icon: Icons.videocam,
                            title: 'Video Editor',
                            subtitle:
                                'Trim, cut & merge, text, music, speed, filters, crossfade',
                            onTap: () =>
                                _open(const VideoEditorScreen()),
                          ),
                        const SizedBox(height: 12),
                        if (AppConfig.liveStudioEnabled)
                          _EntryCard(
                            icon: Icons.live_tv,
                            title: 'Live Studio',
                            subtitle:
                                'Facebook + YouTube par ek saath live — breaking news templates ke saath',
                            onTap: () =>
                                _open(const LiveStudioScreen()),
                          ),
                        const SizedBox(height: 16),
                        // (The AdMob native ad card that used to sit
                        // here was removed with AdMob — Unity has no
                        // native format in this setup, defect #4.)
                        // (v1.3.0 §8: the Premium-unlock card that sat
                        // here is REMOVED by user order. Premium AI
                        // tools unlock with coins only; coins are
                        // earned by watching ads in the Coins section.)
                        const Text(
                          'Works offline. No account, no uploads — '
                          'everything is processed on your phone. '
                          'Basic editing is free; Premium AI tools unlock '
                          'with coins — earn coins by watching ads in the '
                          'Coins section.',
                          style: TextStyle(color: Color(0xFF4E342E)),
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
                            trailing: const Icon(Icons.arrow_forward_ios,
                                size: 18),
                            onTap: () =>
                                UpdateService.checkManually(context),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Login + Coins (Phase 10, News Studio v1): the
                        // login tile shows the signed-in email (or
                        // Guest) and opens the login screen; the coins
                        // tile shows the live balance and opens the
                        // Coins screen (Watch Ads, daily claim,
                        // history).
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
                            trailing: const Icon(Icons.arrow_forward_ios,
                                size: 18),
                            onTap: () => _open(const CoinsScreen()),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Share & Earn (v1.3.0): the referral entry —
                        // its own tidy card (NOT a revival of the
                        // removed ad-unlock card). Opens the Share &
                        // Earn screen: my code + link, Share button,
                        // joined/earned stats, reward claim.
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.group_add),
                            title: const Text('Share & Earn'),
                            subtitle: const Text(
                              'Apna link share karein — har naye user par 100 coins.',
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios,
                                size: 18),
                            onTap: () => _open(const ShareEarnScreen()),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Online Store (v1.2.0): Drive-backed store —
                        // templates, music, ribbons and more; new stock
                        // appears without an app update. Entry is
                        // ad-gated inside the Store itself (§3.4); no
                        // ad is shown here on Home (§5).
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.storefront),
                            title: const Text('Online Store'),
                            subtitle: const Text(
                              'Templates, music, ribbons & more — new stock weekly',
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios,
                                size: 18),
                            onTap: () => _open(const StoreScreen()),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.support_agent),
                            title: const Text('مدد اور سپورٹ'),
                            subtitle: Text(
                                'Jaani Bhatti — ${AppConfig.supportWhatsAppNumber}'),
                            trailing: const Icon(Icons.chat),
                            onTap: () async {
                              final uri =
                                  Uri.parse(AppConfig.supportWhatsAppLink);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri,
                                    mode: LaunchMode.externalApplication);
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
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold),
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
