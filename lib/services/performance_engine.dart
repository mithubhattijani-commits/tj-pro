/// Build 10 (v1.8.0) — TJ Core Engine (fix-list point #7, the
/// CHOSEN parts 7A–7E; 7F lives in the editors' recovery code).
///
/// What this is, honestly: a device profiler + an adaptive
/// configuration + a memory-pressure responder. It is NOT a
/// guarantee — no engine can make an app 100% crash-free (the
/// big editors crash too). What it does:
///
/// * 7A — measures the phone once at launch (RAM, CPU cores,
///   storage, Android low-RAM flag) and classifies it into a
///   tier: LOW / MID / HIGH / FLAGSHIP. The tier is shown on
///   the About dialog's Diagnostics block, never as a popup.
/// * 7B — hands every heavy subsystem a [PerformanceConfig]
///   sized for the tier (poster/template preview render cap,
///   store preview decode width, photo-enlarge pixel cap,
///   export chunk size + whether the hardware encoder is
///   worth trying first). Under memory pressure the config
///   steps DOWN one tier; when the pressure passes (checked
///   by re-probing free RAM) it restores.
/// * 7E — on a system memory-pressure signal it evicts the
///   app's recreatable caches: Flutter's decoded-image cache
///   plus the in-memory maps of the hero / store-preview /
///   store-audio caches. Disk copies stay — everything
///   re-warms from disk on demand, nothing the user owns is
///   touched.
///
/// What was deliberately NOT built (fix-list #7 decision):
/// app-side frame/texture buffer pools and a timeline-window
/// rewrite are native-engine patterns that do not map onto
/// Flutter; proxy clips are a separate, larger job.
library;

import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/widgets.dart';

import 'crash_guard.dart';
import 'ffmpeg_service.dart';
import 'hero_banner_cache.dart';
import 'store_audio_preview.dart';
import 'store_preview_cache.dart';

/// Device capability tier (7A). RAM-first classification: the
/// app's heavy work (ffmpeg encodes, image decode, photo
/// pipeline) is memory-bound long before it is CPU-bound.
enum DeviceTier {
  low,
  mid,
  high,
  flagship;

  /// User-facing label (About / Diagnostics).
  String get label => switch (this) {
        DeviceTier.low => 'LOW',
        DeviceTier.mid => 'MID',
        DeviceTier.high => 'HIGH',
        DeviceTier.flagship => 'FLAGSHIP',
      };

  /// One tier down (floor: LOW) — the pressure step-down.
  DeviceTier get steppedDown => switch (this) {
        DeviceTier.flagship => DeviceTier.high,
        DeviceTier.high => DeviceTier.mid,
        DeviceTier.mid => DeviceTier.low,
        DeviceTier.low => DeviceTier.low,
      };
}

/// One launch's measured device facts (7A). Every field is
/// fail-soft: a probe that could not answer leaves null, and
/// [tier] still resolves (see [DeviceProfile.tierFor]).
class DeviceProfile {
  const DeviceProfile({
    this.model,
    this.sdkInt,
    this.ramMb,
    this.availableRamMb,
    this.cpuCores,
    this.freeDiskBytes,
    this.totalDiskBytes,
    this.isLowRamDevice = false,
  });

  final String? model;
  final int? sdkInt;

  /// Total physical RAM in MB (device_info_plus reports MB).
  final int? ramMb;

  /// Free RAM in MB at probe time.
  final int? availableRamMb;

  final int? cpuCores;

  /// Disk sizes in BYTES (device_info_plus reports bytes).
  final int? freeDiskBytes;
  final int? totalDiskBytes;

  /// Android's own low-RAM flag (ActivityManager.isLowRamDevice).
  final bool isLowRamDevice;

  DeviceTier get tier => tierFor(
        ramMb: ramMb,
        cpuCores: cpuCores,
        isLowRamDevice: isLowRamDevice,
      );

  /// The tier rules. Thresholds sit BELOW the nominal marketing
  /// sizes because physicalRamSize reports a little less than
  /// the box number (a "6 GB" phone reports ≈5.6 GB):
  ///   LOW      — Android low-RAM flag, or < 3.4 GB
  ///   MID      — < 5.4 GB (the 4 GB class)
  ///   HIGH     — 5.4 GB and up (6 GB / 8 GB classes)
  ///   FLAGSHIP — ≥ 10.5 GB (12 GB class) AND ≥ 8 CPU cores
  /// Unknown RAM resolves to MID — the middle of the road,
  /// never the most aggressive settings on an unmeasured phone.
  static DeviceTier tierFor({
    required int? ramMb,
    required int? cpuCores,
    required bool isLowRamDevice,
  }) {
    if (isLowRamDevice) return DeviceTier.low;
    if (ramMb == null) return DeviceTier.mid;
    if (ramMb < 3400) return DeviceTier.low;
    if (ramMb < 5400) return DeviceTier.mid;
    if (ramMb >= 10500 && (cpuCores ?? 0) >= 8) {
      return DeviceTier.flagship;
    }
    return DeviceTier.high;
  }

  /// One honest line for the About dialog's Diagnostics block:
  /// "Phone: Pixel 7 • RAM 8 GB • Tier: HIGH".
  String get diagnosticsLine {
    final parts = <String>[];
    final m = model;
    if (m != null && m.isNotEmpty) parts.add('Phone: $m');
    final ram = ramMb;
    if (ram != null) {
      parts.add('RAM ${(ram / 1024).toStringAsFixed(ram >= 10240 ? 0 : 1)} GB');
    }
    parts.add('Tier: ${tier.label}');
    return parts.join(' • ');
  }
}

/// The adaptive settings every heavy subsystem reads (7B).
/// Immutable; the engine swaps the whole object when the tier
/// or the pressure state changes, and [PerformanceEngine.config]
/// listeners rebuild/refresh from the new values.
///
/// Before [PerformanceEngine.init] has measured the phone, the
/// engine serves [PerformanceConfig.forTier] of HIGH — which
/// reproduces the app's pre-engine constants exactly (720×1280
/// preview cap, 40 MP enlarge cap), so un-initialised use
/// (widget tests included) behaves as the app always did.
class PerformanceConfig {
  const PerformanceConfig({
    required this.tier,
    required this.previewMaxWidth,
    required this.previewMaxHeight,
    required this.previewThumbCacheWidth,
    required this.photoEnlargeMaxPixels,
    required this.exportChunkSeconds,
    required this.tryHardwareEncoder,
    required this.exportThreads,
    required this.exportPreset,
  });

  final DeviceTier tier;

  /// Cap for poster / template PREVIEW renders (the export
  /// itself always renders at the user's chosen size). Wired
  /// into PosterExportService's bound check.
  final int previewMaxWidth;
  final int previewMaxHeight;

  /// Decode width for store card preview images — the cards
  /// are ~120 dp wide, so decoding a 1200 px preview into them
  /// is pure memory waste on a weak phone. Wired into the
  /// store grid's preview image.
  final int previewThumbCacheWidth;

  /// Output pixel cap for the photo editor's enlarge (7B's
  /// heavy-effect quality knob): weaker phones cap lower so
  /// the operation fits in memory instead of dying mid-way.
  /// HIGH/FLAGSHIP keep the historical ~40 MP cap.
  final int photoEnlargeMaxPixels;

  /// Segment length for the export fallback chain's chunked
  /// attempt (7D): shorter segments = lower peak memory.
  final int exportChunkSeconds;

  /// Whether the export chain tries the MediaCodec hardware
  /// encoder before falling back to software (7D). LOW skips
  /// it: on the weakest phones the attempt costs more time
  /// than it can save.
  final bool tryHardwareEncoder;

  /// Hotfix (export-crash audit C1/C6): the libx264 thread cap
  /// for the MAIN export passes (Video Editor + News Studio).
  /// libx264's default is "every core, each with its own frame
  /// queue" — on a weak phone that queue memory is what gets
  /// the process LMK-killed mid-encode. The cap is pushed into
  /// [FfmpegService] whenever this config changes, so a memory-
  /// pressure step-down lightens the NEXT export stage too.
  final int exportThreads;

  /// Hotfix (audit C1): the libx264 preset for the main export
  /// passes. LOW steps one notch faster than the historical
  /// `veryfast` (to `superfast`): a lighter lookahead/RSS
  /// profile for the phones that die mid-encode. Other tiers
  /// keep `veryfast` exactly.
  final String exportPreset;

  static PerformanceConfig forTier(DeviceTier tier) => switch (tier) {
        DeviceTier.low => const PerformanceConfig(
            tier: DeviceTier.low,
            previewMaxWidth: 540,
            previewMaxHeight: 960,
            previewThumbCacheWidth: 192,
            photoEnlargeMaxPixels: 16000000,
            exportChunkSeconds: 20,
            tryHardwareEncoder: false,
            exportThreads: 2,
            exportPreset: 'superfast',
          ),
        DeviceTier.mid => const PerformanceConfig(
            tier: DeviceTier.mid,
            previewMaxWidth: 720,
            previewMaxHeight: 1280,
            previewThumbCacheWidth: 288,
            photoEnlargeMaxPixels: 25000000,
            exportChunkSeconds: 30,
            tryHardwareEncoder: true,
            exportThreads: 4,
            exportPreset: 'veryfast',
          ),
        DeviceTier.high => const PerformanceConfig(
            tier: DeviceTier.high,
            previewMaxWidth: 720,
            previewMaxHeight: 1280,
            previewThumbCacheWidth: 384,
            photoEnlargeMaxPixels: 40000000,
            exportChunkSeconds: 30,
            tryHardwareEncoder: true,
            exportThreads: 6,
            exportPreset: 'veryfast',
          ),
        DeviceTier.flagship => const PerformanceConfig(
            tier: DeviceTier.flagship,
            previewMaxWidth: 1080,
            previewMaxHeight: 1920,
            previewThumbCacheWidth: 480,
            photoEnlargeMaxPixels: 40000000,
            exportChunkSeconds: 45,
            tryHardwareEncoder: true,
            exportThreads: 8,
            exportPreset: 'veryfast',
          ),
      };

  /// The config one tier below this one (pressure step-down).
  PerformanceConfig get steppedDown => forTier(tier.steppedDown);
}

/// The engine singleton: profile + live config + the
/// memory-pressure responder (7A/7B/7E).
class PerformanceEngine with WidgetsBindingObserver {
  PerformanceEngine._() {
    // Hotfix (audit C1/C6): keep the ffmpeg encode policy
    // (thread cap + preset) mirrored into FfmpegService, whose
    // run() applies it to every libx264 command. The mirror
    // follows EVERY config swap — tier adoption at init and
    // the memory-pressure step-down alike — so a pressure
    // event mid-export lightens the NEXT stage's encode.
    config.addListener(_pushEncodePolicy);
    _pushEncodePolicy();
  }

  void _pushEncodePolicy() {
    final c = config.value;
    FfmpegService.encodeThreads = c.exportThreads;
    FfmpegService.encodePreset = c.exportPreset;
  }

  static final PerformanceEngine instance = PerformanceEngine._();

  /// Delay before a pressure step-down re-probes free RAM.
  static const Duration pressureRecheckDelay = Duration(seconds: 90);

  /// How many failed rechecks happen before the engine stops
  /// asking and simply stays stepped down for the session.
  static const int maxPressureRechecks = 5;

  /// The live adaptive config. Starts at the HIGH profile
  /// (pre-engine behaviour) until [init] measures the phone.
  final ValueNotifier<PerformanceConfig> config =
      ValueNotifier<PerformanceConfig>(
    PerformanceConfig.forTier(DeviceTier.high),
  );

  /// The measured profile (null until [init] lands, and stays
  /// null when every probe failed — the tier then reads MID).
  DeviceProfile? profile;

  /// True while a memory-pressure step-down is in effect.
  bool underPressure = false;

  /// Pressure events seen this session (Diagnostics fodder).
  int pressureEvents = 0;

  bool _initialized = false;
  Timer? _recheckTimer;
  int _recheckCount = 0;

  /// Test seam: replaces the device_info read (returns the
  /// measured profile, or null when the probe failed).
  static Future<DeviceProfile?> Function()? profileReaderForTest;

  /// Test seam: replaces the free-RAM re-probe used by the
  /// pressure restore check (returns free RAM in MB).
  static Future<int?> Function()? availableRamProbeForTest;

  DeviceTier get tier => profile?.tier ?? config.value.tier;

  /// The config for the measured tier with no pressure applied.
  PerformanceConfig get baseConfig =>
      PerformanceConfig.forTier(profile?.tier ?? DeviceTier.high);

  /// Measures the phone and adopts its tier's config (7A/7B).
  /// Fail-soft throughout: any probe failure leaves the
  /// previous config in place. Also registers the memory-
  /// pressure observer exactly once (7E). Safe to call again —
  /// later calls are no-ops.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // No binding (bare unit tests) — pressure signals simply
      // never arrive; the profiler/config still work.
    }
    final measured = await _readProfile();
    if (measured != null) {
      profile = measured;
      if (!underPressure) {
        config.value = PerformanceConfig.forTier(measured.tier);
      }
    }
  }

  Future<DeviceProfile?> _readProfile() async {
    final override = profileReaderForTest;
    if (override != null) return override();
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return DeviceProfile(
          model: a.model,
          sdkInt: a.version.sdkInt,
          ramMb: a.physicalRamSize,
          availableRamMb: a.availableRamSize,
          cpuCores: Platform.numberOfProcessors,
          freeDiskBytes: a.freeDiskSize,
          totalDiskBytes: a.totalDiskSize,
          isLowRamDevice: a.isLowRamDevice,
        );
      }
      final base = await info.deviceInfo;
      return DeviceProfile(
        model: base.data['model']?.toString(),
        cpuCores: Platform.numberOfProcessors,
      );
    } catch (e, s) {
      CrashGuard.captureHandled(e, s, source: 'engine.profile');
      return null;
    }
  }

  /// Flutter's memory-pressure signal (7E + 7B step-down).
  @override
  void didHaveMemoryPressure() {
    handleMemoryPressure();
  }

  /// One memory-pressure event: step the config down a tier
  /// and evict every recreatable cache. Idempotent while
  /// already stepped down (the eviction still re-runs — the
  /// OS is asking again, so memory is still tight).
  void handleMemoryPressure() {
    pressureEvents += 1;
    evictCaches();
    if (!underPressure) {
      underPressure = true;
      config.value = baseConfig.steppedDown;
      _recheckCount = 0;
      _scheduleRecheck();
    }
  }

  void _scheduleRecheck() {
    _recheckTimer?.cancel();
    _recheckTimer = Timer(pressureRecheckDelay, () {
      unawaited(recheckPressure());
    });
  }

  /// Re-probes free RAM; restores the base config when the
  /// pressure has clearly passed (≥ 768 MB free, or ≥ 30% of
  /// total RAM free). Otherwise re-arms the recheck, up to
  /// [maxPressureRechecks] times. Returns true when restored.
  Future<bool> recheckPressure() async {
    if (!underPressure) return true;
    _recheckCount += 1;
    int? freeMb;
    try {
      final probe = availableRamProbeForTest;
      if (probe != null) {
        freeMb = await probe();
      } else if (Platform.isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        freeMb = a.availableRamSize;
      }
    } catch (_) {
      freeMb = null;
    }
    final total = profile?.ramMb;
    final recovered = freeMb != null &&
        (freeMb >= 768 || (total != null && total > 0 && freeMb >= total * 0.3));
    if (recovered) {
      underPressure = false;
      config.value = baseConfig;
      _recheckTimer?.cancel();
      return true;
    }
    if (_recheckCount < maxPressureRechecks) {
      _scheduleRecheck();
    }
    return false;
  }

  /// 7E: drops every recreatable in-memory cache. Disk copies
  /// are NOT deleted — the caches re-warm from disk on demand.
  /// Never throws (it runs inside an OS pressure callback).
  void evictCaches() {
    try {
      final binding = PaintingBinding.instance;
      binding.imageCache.clear();
      binding.imageCache.clearLiveImages();
    } catch (_) {
      // No painting binding (tests) — nothing decoded to drop.
    }
    StorePreviewCache.instance.evictMemory();
    HeroBannerCache.instance.evictMemory();
    StoreAudioPreviewCache.instance.evictMemory();
  }

  /// The About dialog's engine line: profile + tier, plus the
  /// pressure state while a step-down is active.
  String get diagnosticsLine {
    final p = profile;
    final base = p?.diagnosticsLine ?? 'Tier: ${tier.label}';
    if (underPressure) {
      return '$base • Memory dabao — quality waqt tor par kam hai';
    }
    return base;
  }

  /// Test seam: installs a measured profile without a device.
  static void debugSetProfileForTest(DeviceProfile value) {
    instance.profile = value;
    instance.underPressure = false;
    instance.config.value = PerformanceConfig.forTier(value.tier);
  }

  /// Test seam: back to the un-initialised defaults.
  static void resetForTest() {
    instance.profile = null;
    instance.underPressure = false;
    instance.pressureEvents = 0;
    instance._recheckCount = 0;
    instance._recheckTimer?.cancel();
    instance._recheckTimer = null;
    instance.config.value = PerformanceConfig.forTier(DeviceTier.high);
    profileReaderForTest = null;
    availableRamProbeForTest = null;
  }
}
