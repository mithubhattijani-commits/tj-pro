/// TJ Pro — home screen.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'services/hero_banner_cache.dart';
import 'services/referral_service.dart';
import 'services/remote_config_service.dart';
import 'services/unity_ads_service.dart';
import 'services/update_service.dart';

import 'live/live_studio_screen.dart';
import 'news/news_maker_screen.dart';
import 'widgets/banner_ad_widget.dart';
import 'widgets/help_whatsapp_button.dart';
import 'widgets/hero_aspect.dart';
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
      // Build 7 (v1.5.9): diagnostics records carry the app
      // version — read it once here (fail-soft: a package-info
      // failure leaves the version blank, never blocks startup).
      try {
        final info = await PackageInfo.fromPlatform();
        CrashGuard.appVersion = '${info.version} (${info.buildNumber})';
      } catch (_) {
        // Diagnostics simply omit the version.
      }
      // Build 7 (v1.5.9): warm the splash poster's decode BEFORE
      // the first frame, so the SplashGate paints the poster on
      // its very first frame instead of a plain-colour flash.
      await _warmSplashPoster();
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

/// Build 7 (v1.5.9): resolves the splash poster once so its
/// decode sits in the image cache before [runApp]; the
/// SplashGate's own Image then paints synchronously on the first
/// frame. Best-effort: never throws, and never waits longer than
/// 600 ms — a slow decode must not delay startup (the gate's
/// background is the same poster-sampled colour the native
/// splash shows — #030E3F since Build 8 — so even a missed
/// warm-up is a seamless colour-to-poster fade).
/// Build 8 (v1.6.0): also kicks off the remote poster's cache
/// warm (backgrounded, never awaited): the gate shows the
/// cached remote copy when one exists for the config's
/// splash_poster_url, else the bundled canonical poster.
Future<void> _warmSplashPoster() async {
  unawaited(
    HeroBannerCache.instance.warm(
      HeroBannerCache.slotSplash,
      remoteConfigService.config.splashPosterImageUrl,
    ),
  );
  try {
    const ImageProvider provider = AssetImage('assets/splash_poster.png');
    final ImageStream stream =
        provider.resolve(const ImageConfiguration());
    final Completer<void> completer = Completer<void>();
    final ImageStreamListener listener = ImageStreamListener(
      (ImageInfo image, bool synchronousCall) {
        if (!completer.isCompleted) completer.complete();
      },
      onError: (Object error, StackTrace? stack) {
        if (!completer.isCompleted) completer.complete();
      },
    );
    stream.addListener(listener);
    try {
      await completer.future.timeout(
        const Duration(milliseconds: 600),
        onTimeout: () {},
      );
    } finally {
      stream.removeListener(listener);
    }
  } catch (_) {
    // Warming is an optimisation only — the gate loads the
    // poster itself regardless.
  }
}

/// Build 6 (v1.5.8) — in-app splash gate. Build 7 (v1.5.9)
/// hardened — see the notes in [_SplashGateState.initState].
/// Build 8 (v1.6.0) — contain fit + remote poster, see below.
///
/// On the user's Android 12+ phone the system splash showed the
/// poster SMALL and centred: the Android 12+ splash API only
/// allows an icon-sized image, so full-bleed is impossible at OS
/// level. Build 7 therefore makes the native splash icon fully
/// transparent (pubspec flutter_native_splash android_12 image =
/// assets/splash_blank.png): at startup the OS now shows ONLY
/// the plain background colour — no icon anywhere — until this
/// gate paints. Build 8 changes that colour from #040F30 to the
/// canonical poster's own sampled edge colour, #030E3F
/// ([TjProTheme.splashBackground] and the pubspec splash config
/// use the same value), so native -> gate reads as one
/// continuous surface the poster appears on.
///
/// The gate is the app's first screen (and its only cold-start
/// entry: MaterialApp has no routes or deep-link handlers that
/// could bypass it, and the update prompts live behind Home).
/// Build 8 (fix-list point #1): the poster is shown
/// BoxFit.contain — the WHOLE poster is always visible, nothing
/// cropped (cover cropped it on tall phones); the letterbox
/// bands are the gate background, the poster's own sampled edge
/// colour, so they blend with the poster's deep-navy edges. The
/// poster itself comes from [_SplashPosterImage]: the remote
/// config's splash_poster_url (cached on-device, hero-banner
/// pattern) with the bundled canonical poster as the instant
/// first paint and the never-blank fallback — the poster can
/// now change WITHOUT a new build, like the hero banners.
/// The gate stays for [minShow] — or until the first frame is
/// ready, whichever is LATER — and is hard-capped at [maxShow]
/// so the app can never sit on the poster. It then swaps itself
/// for Home in place (no route is pushed, so Back never returns
/// here). No buttons, no tap needed, no extra branding text.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  /// How long the poster stays at minimum.
  static const Duration minShow = Duration(milliseconds: 1800);

  /// Absolute cap — the poster never outlives this.
  static const Duration maxShow = Duration(milliseconds: 2500);

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  bool _showHome = false;
  bool _frameReady = false;
  bool _minElapsed = false;
  Timer? _minTimer;
  Timer? _capTimer;

  @override
  void initState() {
    super.initState();
    // Build 7 (v1.5.9): while the gate is up the poster runs
    // full-bleed UNDER the status bar (immersive); [_swap]
    // restores the normal system UI for Home. The gate is the
    // app's root screen (MaterialApp.home) — there is no route
    // beneath it, so the system Back button exits the app from
    // here; it can never loop back to the poster, and after the
    // one-way swap below the poster never returns (not on
    // resume, not on Back — this State's [_showHome] is never
    // reset).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameReady = true;
      _maybeSwap();
    });
    _minTimer = Timer(SplashGate.minShow, () {
      _minElapsed = true;
      _maybeSwap();
    });
    _capTimer = Timer(SplashGate.maxShow, _swap);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Second layer of the poster warm-up (main() decodes it once
    // before runApp): guarantees the asset is in the image cache
    // even when the startup warm-up was skipped or timed out, so
    // the gate's first frame is the poster, not the plain
    // background colour.
    precacheImage(
      const AssetImage('assets/splash_poster.png'),
      context,
      onError: (Object error, StackTrace? stack) {},
    );
  }

  /// Swap when BOTH the minimum time has passed AND the first
  /// frame is ready (whichever finishes later); the cap timer
  /// calls [_swap] directly at [SplashGate.maxShow].
  void _maybeSwap() {
    if (_frameReady && _minElapsed) _swap();
  }

  void _swap() {
    if (!mounted || _showHome) return;
    _minTimer?.cancel();
    _capTimer?.cancel();
    // Restore the normal system UI (the gate ran immersive).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    setState(() => _showHome = true);
  }

  @override
  void dispose() {
    _minTimer?.cancel();
    _capTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showHome) return const HomeScreen();
    return Scaffold(
      backgroundColor: TjProTheme.splashBackground,
      body: SizedBox.expand(
        child: ValueListenableBuilder<RemoteConfig>(
          valueListenable: remoteConfigService.notifier,
          builder: (context, cfg, _) =>
              _SplashPosterImage(url: cfg.splashPosterImageUrl),
        ),
      ),
    );
  }
}

/// Build 8 (v1.6.0, fix-list point #1): the SplashGate's poster
/// image — the hero banners' proven fallback pattern applied to
/// the splash poster.
///
/// Display order: the on-device cached copy for this exact URL
/// (HeroBannerCache slot [HeroBannerCache.slotSplash]) paints
/// when one exists; otherwise the bundled canonical poster
/// paints instantly while the remote copy downloads in the
/// background (the cache bumps its revision when it lands and
/// this widget swaps to it). Any failure — offline, 404, a
/// broken remote file — simply keeps the bundled poster, so
/// the gate can never render blank or broken. Fit is
/// BoxFit.contain everywhere: the whole poster, never cropped.
class _SplashPosterImage extends StatefulWidget {
  const _SplashPosterImage({required this.url});

  final String url;

  @override
  State<_SplashPosterImage> createState() => _SplashPosterImageState();
}

class _SplashPosterImageState extends State<_SplashPosterImage> {
  File? _file;

  @override
  void initState() {
    super.initState();
    _file = HeroBannerCache.instance
        .cachedFileFor(HeroBannerCache.slotSplash, widget.url);
    HeroBannerCache.instance.revision.addListener(_sync);
    unawaited(
      HeroBannerCache.instance.warm(HeroBannerCache.slotSplash, widget.url),
    );
  }

  @override
  void didUpdateWidget(_SplashPosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _file = HeroBannerCache.instance
          .cachedFileFor(HeroBannerCache.slotSplash, widget.url);
      unawaited(
        HeroBannerCache.instance
            .warm(HeroBannerCache.slotSplash, widget.url),
      );
    }
  }

  @override
  void dispose() {
    HeroBannerCache.instance.revision.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final File? file = HeroBannerCache.instance
        .cachedFileFor(HeroBannerCache.slotSplash, widget.url);
    if (file != _file) setState(() => _file = file);
  }

  @override
  Widget build(BuildContext context) {
    final File? file = _file;
    if (file != null) {
      return Image.file(
        file,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => const Image(
          image: AssetImage('assets/splash_poster.png'),
          fit: BoxFit.contain,
        ),
      );
    }
    return const Image(
      image: AssetImage('assets/splash_poster.png'),
      fit: BoxFit.contain,
    );
  }
}

/// Build 7 (v1.5.9, FIX C): one hero slide's REMOTE image.
///
/// Display order: the on-device cached copy for this exact URL
/// (HeroBannerCache) paints instantly; until a copy is cached
/// the URL streams directly, showing [fallback] while loading;
/// any failure — offline, 404, a broken file — lands on
/// [fallback]. A remote banner can therefore never produce a
/// blank or broken slide. When the cache downloads a fresher
/// copy it bumps its revision and this widget swaps to it.
class _HeroRemoteImage extends StatefulWidget {
  const _HeroRemoteImage({
    required this.slot,
    required this.url,
    required this.fit,
    required this.fallback,
  });

  final String slot;
  final String url;
  final BoxFit fit;
  final Widget fallback;

  @override
  State<_HeroRemoteImage> createState() => _HeroRemoteImageState();
}

class _HeroRemoteImageState extends State<_HeroRemoteImage> {
  File? _file;

  @override
  void initState() {
    super.initState();
    _file = HeroBannerCache.instance.cachedFileFor(widget.slot, widget.url);
    HeroBannerCache.instance.revision.addListener(_sync);
    unawaited(HeroBannerCache.instance.warm(widget.slot, widget.url));
  }

  @override
  void didUpdateWidget(_HeroRemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.slot != widget.slot) {
      _file = HeroBannerCache.instance.cachedFileFor(widget.slot, widget.url);
      unawaited(HeroBannerCache.instance.warm(widget.slot, widget.url));
    }
  }

  @override
  void dispose() {
    HeroBannerCache.instance.revision.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final File? file =
        HeroBannerCache.instance.cachedFileFor(widget.slot, widget.url);
    if (file != _file) setState(() => _file = file);
  }

  @override
  Widget build(BuildContext context) {
    final File? file = _file;
    if (file != null) {
      return Image.file(
        file,
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) => widget.fallback,
      );
    }
    return Image.network(
      widget.url,
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, error, stackTrace) => widget.fallback,
      loadingBuilder: (context, child, loadingProgress) =>
          loadingProgress == null ? child : widget.fallback,
    );
  }
}

/// Build 8 (v1.6.0, fix-list point #2): resolves one hero
/// slide's effective image provider purely to learn its
/// intrinsic aspect, reported via [onAspect]. Renders nothing.
/// Resolution shares the framework image cache with the slide's
/// own Image widget, so it costs no extra download. Failures are
/// silent — the frame simply keeps its current/default height.
class _HeroAspectProbe extends StatefulWidget {
  const _HeroAspectProbe({super.key, required this.provider, required this.onAspect});

  final ImageProvider provider;
  final ValueChanged<double> onAspect;

  @override
  State<_HeroAspectProbe> createState() => _HeroAspectProbeState();
}

class _HeroAspectProbeState extends State<_HeroAspectProbe> {
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_HeroAspectProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) _resolve();
  }

  void _resolve() {
    _detach();
    final ImageStream stream =
        widget.provider.resolve(const ImageConfiguration());
    final ImageStreamListener listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        final double? aspect = heroAspectFromSize(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        if (aspect == null) return;
        // A cache hit completes the stream SYNCHRONOUSLY —
        // possibly during the build phase, where the parent's
        // setState would throw. Always report after the frame.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onAspect(aspect);
        });
      },
      onError: (Object error, StackTrace? stack) {
        // Silent: no aspect reported, the frame keeps its
        // current height and the slide's own fallback shows.
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _detach() {
    final ImageStream? stream = _stream;
    final ImageStreamListener? listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
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
      // Build 7 (v1.5.9, Phase 8): the app theme IS the design
      // system's dark theme — the identical ThemeData that used
      // to be written inline here, now owned by theme.dart.
      theme: TjProTheme.dark,
      // Build 7 (v1.5.9): diagnostics records name the current
      // route/screen — this observer keeps CrashGuard's route
      // label current. It observes only; it changes nothing.
      navigatorObservers: [CrashGuard.routeObserver],
      // Build 6 (v1.5.8): the app opens on the in-app splash
      // gate (full-screen poster), which swaps itself for Home.
      home: const SplashGate(),
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

  /// Bottom-nav tab: 0 = Home, 1 = News Studio, 2 = Earn. Build 5
  /// (v1.5.7): the News Studio tab AND the Home NEWS STUDIO card
  /// both open the News Maker WORKSPACE directly — the old News
  /// Studio hub screen is retired, so there is exactly one News
  /// Studio home and it is the workspace itself.
  int _tabIndex = 0;

  /// Build 5 (v1.5.7): Home's Watch Ads button runs the rewarded
  /// ad itself (decision: it must not merely open the Coins
  /// screen) — this flag is its in-flight guard, mirroring the
  /// Coins screen's own.
  bool _homeAdBusy = false;

  /// Build 4 (Home reference): hero carousel state.
  final PageController _heroController = PageController();
  int _heroPage = 0;

  /// Build 8 (v1.6.0, fix-list point #2): intrinsic aspect
  /// (width / height) of each hero slide's effective image, by
  /// slide index, reported by the slides' aspect probes. The
  /// carousel frame follows the ACTIVE slide's aspect so a
  /// banner is never cropped; an index with no entry yet keeps
  /// the historical default frame height.
  final Map<int, double> _heroAspects = <int, double>{};

  void _reportHeroAspect(int index, double aspect) {
    if (!mounted) return;
    final double? known = _heroAspects[index];
    if (known != null && (known - aspect).abs() < 0.005) return;
    setState(() => _heroAspects[index] = aspect);
  }

  /// The image provider slide 1 is effectively showing (remote
  /// cached copy, remote stream, or the bundled artwork) — the
  /// aspect probe resolves THIS so the frame matches the image
  /// actually on screen.
  ImageProvider _heroProvider1(RemoteConfig cfg) {
    final String url = cfg.heroBanner1ImageUrl;
    if (url.isEmpty) {
      return const AssetImage('assets/hero_nigraan_banner.jpg');
    }
    final File? file =
        HeroBannerCache.instance.cachedFileFor(HeroBannerCache.slot1, url);
    return file != null ? FileImage(file) : NetworkImage(url);
  }

  /// Same for slide 2 (the admin banner chain).
  ImageProvider _heroProvider2(RemoteConfig cfg) {
    final String url = cfg.heroBanner2ImageUrl;
    if (url.startsWith('assets/')) return AssetImage(url);
    final File? file =
        HeroBannerCache.instance.cachedFileFor(HeroBannerCache.slot2, url);
    return file != null ? FileImage(file) : NetworkImage(url);
  }

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
    remoteConfigService.notifier.removeListener(_warmHeroBanners);
    _heroController.dispose();
    super.dispose();
  }

  /// Build 7 (v1.5.9, FIX C): keeps the on-device hero-banner
  /// cache warm for the CURRENT config — called once at launch
  /// and on every remote-config change. Cached copies paint
  /// instantly; fresh copies swap in when downloaded.
  void _warmHeroBanners() {
    final RemoteConfig cfg = remoteConfigService.config;
    unawaited(
      HeroBannerCache.instance
          .warm(HeroBannerCache.slot1, cfg.heroBanner1ImageUrl),
    );
    unawaited(
      HeroBannerCache.instance
          .warm(HeroBannerCache.slot2, cfg.heroBanner2ImageUrl),
    );
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
    remoteConfigService.notifier.addListener(_warmHeroBanners);
    _warmHeroBanners();
    _onRemoteConfigChanged();
    // Update check (v1.2.0 UX): fetch silently; when a newer version
    // exists, show the once-per-launch update popup (Later snoozes it
    // for the session). The download then runs in the background with
    // the UpdateProgressBar mounted in build(). checkOnLaunch stays
    // available but is NOT also called, or the user gets two dialogs.
    // When the force-update kill-switch is armed, the non-dismissible
    // force dialog handles the update instead of the normal prompt.
    // Build 6 (v1.5.8, error-banner audit): this flow runs
    // unawaited from a post-frame callback. fetchUpdate() is
    // fail-soft inside, but the popup call sat outside any
    // guard — a popup-time failure became an unhandled async
    // error on the Home screen. Fail-soft end to end.
    try {
      if (!_forceUpdateArmed()) {
        final UpdateInfo? update = await UpdateService.fetchUpdate();
        if (update != null && mounted) {
          showUpdatePopupOnce(context, update);
        }
      }
    } catch (e, s) {
      // The update prompt is a nicety — never an error path.
      // Build 7: recorded with its boundary tag (no banner).
      CrashGuard.captureHandled(e, s, source: 'home.update');
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

  /// Build 5 (v1.5.7, user ruling): Home's Watch Ads button
  /// performs the rewarded-ad action itself — the Coins screen's
  /// own flow ([CoinService.watchRewardedAd]) with the outcome
  /// reported here. It is NOT a door to the Coins screen; Coins
  /// ka ghar is the bottom Earn tab only.
  Future<void> _watchAdFromHome() async {
    if (_homeAdBusy) return;
    setState(() => _homeAdBusy = true);
    final result = await CoinService.instance.watchRewardedAd();
    if (!mounted) return;
    setState(() => _homeAdBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.ok
              ? '+${result.coins} coins earned!'
              : (result.error ??
                  'Could not earn coins. Please try again.'),
        ),
      ),
    );
  }

  /// Build 5 (v1.5.7): the What's New "New Features" tile — a
  /// genuine what's-new list for this release (it previously
  /// duplicated the Updates small button's update check).
  void _showWhatsNew() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("What's New — v1.5.7"),
        content: const Text(
          '• Naya TJ Pro icon aur Nigraan TV splash screen\n'
          '• News Studio ab seedha professional workspace khulta '
          'hai — saare tools aik hi screen par, koi hub nahi\n'
          '• Template & Studio ke saare tools (PIP, Chroma, '
          'Interview plate, Category, Intro/Outro) ab News Maker '
          'ke Template panel mein hain\n'
          '• Home ka bara banner Nigraan TV ka apna banner hai — '
          'tap karne par nigraantv.xyz khulti hai\n'
          '• Live Studio ka aik hi darwaza: Live Streaming banner '
          'ka Join Now\n'
          '• "Kuch ghalat ho gaya" banner bar bar aane ka masla '
          'theek kar diya gaya',
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

  /// About tap: the old About card's text, as a dialog (the
  /// card itself was part of the de-grouped MORE list).
  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('About'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TJ Pro by Nigraan TV — photo & video editor that works '
                'fully offline on your phone. No account, no uploads.',
              ),
              const SizedBox(height: 16),
              // Build 6 (v1.5.8): persistent diagnostics —
              // read back from SharedPreferences so a phone-only
              // failure can be inspected instead of guessed at.
              // Build 7 (v1.5.9): the text now holds the LAST
              // FIVE recorded errors (newest first), each with
              // its boundary tag, the app version and the screen
              // it fired on. Read-only; the Copy button puts it
              // on the clipboard.
              const Text(
                'Diagnostics — aakhri khata',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              FutureBuilder<String?>(
                future: CrashGuard.loadStoredDiagnostic(),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Text('Load ho raha hai…');
                  }
                  final text = snap.data;
                  if (text == null || text.isEmpty) {
                    return const Text(
                      'Abhi tak koi khata record nahi hui.',
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        text,
                        style: const TextStyle(fontSize: 11),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: text),
                          ),
                          icon: const Icon(Icons.copy, size: 14),
                          label: const Text('Copy'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
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
                ? const NewsMakerScreen()
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
                                    // Build 5 (v1.5.7): straight
                                    // into the workspace — no hub.
                                    onTap: () =>
                                        _open(const NewsMakerScreen()),
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
                                  // Build 5 (v1.5.7): a genuine
                                  // what's-new tile — it no longer
                                  // duplicates the Updates button's
                                  // update check (audit A14).
                                  onTap: _showWhatsNew,
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
                                  // Build 5 (v1.5.7): the Store's
                                  // Backgrounds gallery — "View
                                  // All" above is the one all-store
                                  // door (audit A15).
                                  onTap: () => _open(
                                    const StoreScreen(
                                      initialCategory: 'Backgrounds',
                                    ),
                                  ),
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
                                        subtitle: _homeAdBusy
                                            ? 'Loading ad…'
                                            : 'Earn Coins • Balance: $balance',
                                        // Build 5 (v1.5.7, user
                                        // ruling): the button RUNS
                                        // the rewarded ad itself —
                                        // Coins ka ghar is only the
                                        // bottom Earn tab now.
                                        onTap: _homeAdBusy
                                            ? null
                                            : () => unawaited(
                                                  _watchAdFromHome(),
                                                ),
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

  /// Hero carousel: slide 1 = the user's own Nigraan TV banner
  /// IMAGE (Build 5, v1.5.7 — his artwork, not a drawn design;
  /// tap opens the Nigraan TV website); slide 2 (when a banner
  /// is booked/enabled) = the remote ADMIN house-ad banner with
  /// its existing behaviour (contain fit, never cropped; tap
  /// opens its link when set).
  ///
  /// Build 8 (v1.6.0, fix-list point #2): the frame ADAPTS to
  /// the active slide's image aspect (probed from the image
  /// actually being shown) instead of the old fixed 178dp, so
  /// slide 1 is never cropped whatever banner is served. The
  /// math lives in widgets/hero_aspect.dart: aspect clamped to
  /// 1.15:1..2.65:1, height capped at 45% of the screen, and
  /// the historical 178dp until a slide's aspect is known. The
  /// height change on a slide swipe animates subtly (220 ms).
  /// Auto-scroll, dots and tap behaviour are unchanged.
  Widget _heroCarousel() {
    return ValueListenableBuilder<RemoteConfig>(
      valueListenable: remoteConfigService.notifier,
      builder: (context, cfg, _) {
        // Build 7 (v1.5.9, FIX C): slide 2 shows when its
        // EFFECTIVE image exists and either the advertising
        // banner is enabled (today's rule) or a hero-2 override
        // is set in the remote config.
        final showAdmin = cfg.heroBanner2ImageUrl.isNotEmpty &&
            (cfg.advertisingBannerEnabled ||
                cfg.heroBanner2Url.trim().isNotEmpty);
        final slides = <Widget>[
          _newsHeroSlide(cfg),
          if (showAdmin) _adminHeroSlide(cfg),
        ];
        // Rebuild when the banner cache lands a fresh copy: the
        // effective providers (and their aspects) can change.
        return ValueListenableBuilder<int>(
          valueListenable: HeroBannerCache.instance.revision,
          builder: (context, _, _) {
            final providers = <ImageProvider>[
              _heroProvider1(cfg),
              if (showAdmin) _heroProvider2(cfg),
            ];
            return LayoutBuilder(
              builder: (context, constraints) {
                final double maxHeight =
                    MediaQuery.sizeOf(context).height *
                        heroMaxHeightFraction;
                final int active =
                    _heroPage < slides.length ? _heroPage : 0;
                final double height = heroFrameHeight(
                  width: constraints.maxWidth,
                  aspect: _heroAspects[active],
                  maxHeight: maxHeight,
                );
                return Column(
                  children: [
                    // Invisible probes: each resolves its slide's
                    // effective image and reports its aspect.
                    for (var i = 0; i < providers.length; i++)
                      _HeroAspectProbe(
                        key: ValueKey<String>('heroAspectProbe$i'),
                        provider: providers[i],
                        onAspect: (a) => _reportHeroAspect(i, a),
                      ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      height: height,
                      child: PageView(
                        controller: _heroController,
                        onPageChanged: (i) =>
                            setState(() => _heroPage = i),
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
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 3),
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
          },
        );
      },
    );
  }

  /// Slide 1 (Build 5, v1.5.7, user ruling): the user's OWN
  /// Nigraan TV banner as an IMAGE — the artwork cropped from his
  /// home reference, shown cover-fit exactly as sent. It is a
  /// banner, not a button: no drawn replacement, no Watch Live
  /// pill of our own (the artwork carries its own). The tap opens
  /// his website, nigraantv.xyz — Live Studio's Home door is the
  /// Live Streaming banner's Join Now, nowhere else.
  Widget _newsHeroSlide(RemoteConfig cfg) {
    // Build 7 (v1.5.9, FIX C): when the remote config sets a
    // hero-1 image, the slide shows it (cached on-device, cover
    // fit as always); the bundled artwork remains both the
    // no-config default and the never-blank fallback. The tap
    // opens the config's hero-1 link (default: the website).
    final String remoteUrl = cfg.heroBanner1ImageUrl;
    return Container(
      key: const Key('homeHeroBanner'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33F5C542)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openExternal(cfg.heroBanner1TapUrl),
        child: remoteUrl.isEmpty
            ? Image.asset(
                'assets/hero_nigraan_banner.jpg',
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              )
            : _HeroRemoteImage(
                slot: HeroBannerCache.slot1,
                url: remoteUrl,
                fit: BoxFit.cover,
                fallback: Image.asset(
                  'assets/hero_nigraan_banner.jpg',
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
      ),
    );
  }

  /// Opens [url] in the external browser (the hero slides' tap
  /// targets come from the remote config; slide 1's default is
  /// the Nigraan TV website, as it always was).
  Future<void> _openExternal(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// The admin house-ad banner as a carousel slide — the SAME
  /// rendering as the Advertise page: BoxFit.contain on a neutral
  /// letterbox, NEVER cropped; tap opens the banner link when one
  /// is set (no link = no handler, as before).
  Widget _adminHeroSlide(RemoteConfig cfg) {
    // Build 7 (v1.5.9, FIX C): the EFFECTIVE slide-2 image/link
    // (hero-2 remote-config override when set, else the existing
    // advertising chain — see RemoteConfig.heroBanner2ImageUrl).
    // Remote images go through the on-device cache; the bundled
    // house banner is the never-blank fallback. Fit stays
    // BoxFit.contain — the admin banner is NEVER cropped.
    final url = cfg.heroBanner2ImageUrl;
    final link = cfg.heroBanner2TapUrl.trim();
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
            : _HeroRemoteImage(
                slot: HeroBannerCache.slot2,
                url: url,
                fit: BoxFit.contain,
                fallback: Image.asset(
                  AppConfig.advertisingBannerImageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
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
  /// Join Now pill, Facebook/YouTube Live chips. Build 5
  /// (v1.5.7, user ruling): Join Now is Live Studio's ONLY door
  /// on Home — the banner body and the platform chips are
  /// display-only now (they were three extra copies of the same
  /// door on one card).
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
                    InkWell(
                      key: const Key('homeJoinNowButton'),
                      onTap: openLive,
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
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
                  _liveChip(Icons.facebook, 'Facebook Live'),
                  const SizedBox(height: 6),
                  _liveChip(Icons.smart_display, 'YouTube Live'),
                ],
              ),
            ],
          ),
        ),
    );
  }

  /// One platform chip on the Live Streaming banner — display
  /// only since Build 5 (Join Now is the banner's single door).
  Widget _liveChip(IconData icon, String label) {
    return Container(
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
    // Nullable since Build 5: the Watch Ads button disables
    // itself while its ad is in flight.
    required VoidCallback? onTap,
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
