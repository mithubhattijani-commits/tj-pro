/// TJ Pro — in-app update checker for sideloaded builds.
///
/// The app fetches a small JSON manifest from the website and compares
/// its versionCode with the installed one. When a newer version exists,
/// the user is offered an update; the new APK is downloaded in the
/// BACKGROUND via Android's DownloadManager (a system process — the
/// download survives the app being minimized or killed, shows a
/// persistent progress notification, and auto-resumes) and the system
/// install prompt is fired when ready. A sideloaded app can NEVER install
/// silently — Android always requires the user's install tap, and the
/// UI says so honestly.
///
/// Manifest format (served from the website, published separately):
///   {"versionCode": 3, "versionName": "1.2.0",
///    "url": "https://.../tj-pro.apk", "notes": "What's new"}
///
/// Split-per-ABI releases (Phase 10, Magic Box pattern) add two
/// optional maps; when present, this device's ABI wins, otherwise
/// the universal "versionCode"/"url" are used:
///   {"versionCode": 9, "versionName": "1.0.8",
///    "url": "https://.../tj-pro-arm64-v8a.apk",
///    "urls": {"arm64-v8a": "...", "armeabi-v7a": "...",
///             "x86_64": "..."},
///    "versionCodes": {"arm64-v8a": 2009, "armeabi-v7a": 1009,
///                     "x86_64": 4009}}
/// (Flutter's --split-per-abi scheme: armeabi-v7a = 1000 + base,
/// arm64-v8a = 2000 + base, x86_64 = 4000 + base.)
///
/// The updater is inert until that manifest exists: a missing or
/// unreachable manifest simply means "no update prompt, no error".
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crash_guard.dart';

/// One update entry parsed from the version manifest.
class UpdateInfo {
  const UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.url,
    required this.notes,
  });

  final int versionCode;
  final String versionName;
  final String url;
  final String notes;
}

/// Distinguished outcome of a manual update check (Jaani 31 Oct 2026:
/// "no new version" vs "no internet" vs "update file not found" must
/// show different messages, not one shared message).
enum UpdateCheckResult {
  /// A newer version is available (details in [UpdateCheckOutcome.update]).
  available,

  /// Installed version is already the latest.
  upToDate,

  /// No network connectivity.
  noInternet,

  /// Manifest unreachable (404 / bad response / bad JSON).
  manifestNotFound,
}

/// Combined result of [UpdateService.checkForUpdate]: the distinguished
/// status plus the [UpdateInfo] when a newer version exists.
class UpdateCheckOutcome {
  const UpdateCheckOutcome(this.status, [this.update]);

  final UpdateCheckResult status;
  final UpdateInfo? update;
}

/// Phase of the in-app update flow (plan §7, v1.2.0). Bound by the UI
/// in `lib/widgets/update_ui.dart` via [UpdateService.updateState].
enum UpdatePhase {
  /// Nothing happening: no known update, no download.
  idle,

  /// A newer version is known but no download has started yet.
  available,

  /// The system DownloadManager is downloading the APK in the
  /// background; the app stays fully usable.
  downloading,

  /// The APK is fully downloaded. The system install prompt has
  /// already been fired once (existing behaviour); the UI's Install
  /// button can fire it again with one tap if the user backed out.
  downloaded,

  /// The system install intent is being fired.
  installing,

  /// The download failed or was interrupted. Quiet state: no popup,
  /// the UI offers a retry that restarts the download cleanly.
  failed,
}

/// Immutable snapshot of the update flow for the UI to bind to.
///
/// [percent] is 0–100. [bytesDownloaded] / [bytesTotal] come straight
/// from the DownloadManager status poll in
/// [UpdateService.downloadAndInstall] (the native `downloadStatus`
/// call already returns both numbers) — no new download mechanism
/// and no new native bridge were needed to surface them.
class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.percent = 0,
    this.bytesDownloaded = 0,
    this.bytesTotal = 0,
    this.update,
    this.downloadedApkPath,
    this.statusNote,
  });

  final UpdatePhase phase;
  final int percent;
  final int bytesDownloaded;
  final int bytesTotal;

  /// Build 13 (point #18): an honest, user-readable note about
  /// the download's state — WHY it is paused (network, Wi-Fi
  /// wait, roaming…) or why it failed — from the DownloadManager
  /// reason code the native side now surfaces. Null = nothing
  /// unusual to report.
  final String? statusNote;

  /// The update this state belongs to, when one is known.
  final UpdateInfo? update;

  /// Local path of the fully downloaded APK (phase
  /// [UpdatePhase.downloaded] / [UpdatePhase.installing]).
  final String? downloadedApkPath;

  /// Bytes still to download; 0 when the total is unknown or the
  /// download is complete.
  int get bytesRemaining =>
      bytesTotal > bytesDownloaded ? bytesTotal - bytesDownloaded : 0;

  /// 0.0–1.0 fraction for a [LinearProgressIndicator].
  double get fraction => (percent / 100).clamp(0.0, 1.0);
}

class UpdateService {
  /// Fixed manifest URL. The file itself is published later by the
  /// parent (with the stable APK download link); until then this
  /// checker stays silent.
  static const String manifestUrl =
      'https://nigraantv.xyz/apps/tj-pro-version.json';

  static const String _apkFileName = 'tj-pro-update.apk';

  /// Native updater channel ("tj_pro/updater"): background download via
  /// Android DownloadManager, status polling, FileProvider install intent.
  static const MethodChannel _channel = MethodChannel('tj_pro/updater');

  /// SharedPreferences keys for the persisted in-flight update
  /// download (#34 fix design 3): written at enqueue time so a
  /// later launch can re-attach to the system download after the
  /// app was killed mid-download.
  static const String _pendingDownloadIdKey = 'tjpro_pending_dl_id';
  static const String _pendingVersionCodeKey = 'tjpro_pending_dl_code';
  static const String _pendingVersionNameKey = 'tjpro_pending_dl_name';
  static const String _pendingUrlKey = 'tjpro_pending_dl_url';
  static const String _pendingNotesKey = 'tjpro_pending_dl_notes';

  /// DownloadManager reports -1 while the total size is unknown;
  /// the UI state must carry 0 instead (#34 fix design 5) and only
  /// switch to real percent math when a positive total arrives.
  static int clampTotalBytes(int raw) => raw > 0 ? raw : 0;

  /// Build 13 (point #18): how long a download may sit in the
  /// DownloadManager PAUSED state before the user is told, with
  /// the reason, instead of staring at a frozen percent forever.
  static const Duration pausedWatchdog = Duration(minutes: 5);

  /// User-readable text for a DownloadManager PAUSED reason code
  /// (COLUMN_REASON while STATUS_PAUSED): 1 waiting-to-retry,
  /// 2 waiting-for-network, 3 queued-for-Wi-Fi, 4 paused-by-app,
  /// 5 unknown. -1/anything else = the generic line.
  static String pausedReasonText(int reason) {
    switch (reason) {
      case 1:
        return 'server se dobara koshish ka intezar hai';
      case 2:
        return 'network ka intezar hai — internet band ya kamzor hai';
      case 3:
        return 'Wi-Fi ka intezar hai — mobile data par download ruki hai';
      case 4:
        return 'download system ne roki hui hai';
      case 5:
        return 'wajah maloom nahi';
      default:
        return 'download ruki hui hai';
    }
  }

  /// User-readable text for a DownloadManager FAILED reason code
  /// (COLUMN_REASON while STATUS_FAILED): the ERROR_* range
  /// (1000–1009) or a raw HTTP status code.
  static String failedReasonText(int reason) {
    switch (reason) {
      case 1000:
        return 'download fail ho gayi (wajah maloom nahi)';
      case 1001:
        return 'APK file save nahi ho saki (storage masla)';
      case 1002:
      case 1004:
        return 'server se data nahi mila (network/server masla)';
      case 1005:
        return 'server ne bohat zyada redirects bheje';
      case 1006:
        return 'phone mein jagah khatam hai — storage khaali karein';
      case 1007:
        return 'download ki jagah (storage) nahi mili';
      case 1008:
        return 'download wahin se aage nahi badh saki';
      case 1009:
        return 'purani adhoori file ne rok lagayi thi — saaf kar di gayi hai, Retry karein';
      default:
        if (reason >= 400 && reason < 600) {
          return 'server ne jawab diya: HTTP $reason';
        }
        return 'download fail ho gayi';
    }
  }

  /// Build 13 (point #18): the download id a poll loop is
  /// currently attached to (this session), so a second attach —
  /// e.g. the user tapping Update while the launch-restore poll
  /// is already watching the same download — never starts a
  /// duplicate watcher.
  static int? _pollingDownloadId;

  /// Build 13 (point #18): true while a [downloadAndInstall]
  /// flow (reconcile → enqueue → poll) is in flight in this
  /// session. A second tap in that window is answered, not
  /// executed — the pre-Build-13 double-enqueue bug.
  static bool _downloadFlowActive = false;

  /// One status query against the native channel; null when the
  /// channel cannot answer (old build / test host).
  static Future<Map?> _statusOf(int downloadId) async {
    try {
      return await _channel.invokeMethod<Map>(
        'downloadStatus',
        <String, Object>{'downloadId': downloadId},
      );
    } catch (_) {
      return null;
    }
  }

  /// Removes a DownloadManager entry + its (partial) file via
  /// the native removeDownload method. Fail-soft: an old native
  /// side without the method simply leaves the entry, and the
  /// enqueue-time destination hygiene still protects the retry.
  static Future<void> _removeDownload(int downloadId) async {
    try {
      await _channel.invokeMethod<bool>(
        'removeDownload',
        <String, Object>{'downloadId': downloadId},
      );
    } catch (_) {}
  }

  /// Live background-download progress. Null when idle.
  /// Drives the non-blocking progress UI (Jaani, 2 Nov 2026).
  static final ValueNotifier<double?> backgroundProgress =
      ValueNotifier<double?>(null);

  /// Observable update state for the plan-§7 UI (`UpdatePopup` /
  /// `UpdateProgressBar` in `lib/widgets/update_ui.dart`).
  ///
  /// This EXTENDS the existing flow: [backgroundProgress] is still
  /// driven exactly as before, and every transition below is mirrored
  /// into this richer snapshot (phase + percent + byte counts) by
  /// [_setUpdateState]. The byte counts flow from the EXISTING
  /// DownloadManager poll in [downloadAndInstall] — the native
  /// `downloadStatus` result already carries `bytesDownloaded` and
  /// `bytesTotal`, so no new polling bridge was required.
  static final ValueNotifier<UpdateState> updateState =
      ValueNotifier<UpdateState>(const UpdateState());

  /// The update a download / retry currently belongs to.
  static UpdateInfo? _activeUpdate;

  /// Local path of the last fully downloaded update APK, so the UI's
  /// Install button can re-fire the existing install intent.
  static String? _downloadedApkPath;

  /// Session guards for the §7 popup: at most ONE update popup per
  /// launch, and "Later" snoozes it for the rest of the session.
  static bool _updatePopupShownThisSession = false;
  static bool _updatePopupSnoozedThisSession = false;

  /// True while the §7 update popup may still be shown this session.
  static bool get canShowUpdatePopup =>
      !_updatePopupShownThisSession && !_updatePopupSnoozedThisSession;

  /// Records that the §7 update popup has been shown this session.
  static void markUpdatePopupShown() {
    _updatePopupShownThisSession = true;
  }

  /// "Later" on the §7 popup: no update popup again this session.
  /// (The manual "Check for updates" tile is unaffected.)
  static void snoozeUpdatePopup() {
    _updatePopupSnoozedThisSession = true;
  }

  /// Remembers [update] as the known/active update and, unless a
  /// download is already in flight or finished, moves the state to
  /// [UpdatePhase.available]. Never clobbers an in-flight download.
  static void noteUpdateAvailable(UpdateInfo update) {
    _activeUpdate = update;
    final UpdatePhase phase = updateState.value.phase;
    if (phase == UpdatePhase.idle ||
        phase == UpdatePhase.available ||
        phase == UpdatePhase.failed) {
      _setUpdateState(UpdatePhase.available);
    }
  }

  /// Fires the EXISTING system install intent for the already
  /// downloaded APK (the same `installApk` channel call
  /// [downloadAndInstall] makes on completion). One tap from the
  /// progress bar's Install button; a no-op when nothing has been
  /// downloaded. Afterwards the state returns to
  /// [UpdatePhase.downloaded] so the button can fire the prompt
  /// again if the user backed out of the system installer.
  static Future<void> installDownloadedApk() async {
    final String? path = _downloadedApkPath;
    if (path == null) return;
    _setUpdateState(UpdatePhase.installing);
    try {
      await _channel.invokeMethod<void>(
        'installApk',
        <String, String>{'path': path},
      );
    } catch (_) {}
    _setUpdateState(UpdatePhase.downloaded);
  }

  /// Restarts a failed/interrupted download through
  /// [downloadAndInstall] — which since Build 13 RECONCILES
  /// first: a download the system still holds (running, or even
  /// completed while the UI showed "failed") is re-attached /
  /// surfaced, never duplicated. A no-op when no update is
  /// known. Never shows a popup.
  static Future<void> retryDownload(BuildContext context) async {
    final UpdateInfo? update = _activeUpdate ?? updateState.value.update;
    if (update == null) return;
    _downloadedApkPath = null;
    await downloadAndInstall(context, update);
  }

  /// Dismisses the quiet failed state (progress bar close button).
  static void dismissFailedState() {
    if (updateState.value.phase == UpdatePhase.failed) {
      _setUpdateState(UpdatePhase.idle);
    }
  }

  /// Single write point for [updateState]: preserves the counters
  /// the caller does not pass and stamps the active update + APK
  /// path onto every snapshot.
  static void _setUpdateState(
    UpdatePhase phase, {
    int? percent,
    int? bytesDownloaded,
    int? bytesTotal,
    String? statusNote,
    bool replaceStatusNote = false,
  }) {
    final UpdateState prev = updateState.value;
    updateState.value = UpdateState(
      phase: phase,
      percent: percent ?? prev.percent,
      bytesDownloaded: bytesDownloaded ?? prev.bytesDownloaded,
      bytesTotal: bytesTotal ?? prev.bytesTotal,
      update: _activeUpdate ?? prev.update,
      downloadedApkPath: _downloadedApkPath,
      // Build 13: the note is sticky (a failure keeps the reason
      // it failed with) unless the caller replaces it outright —
      // passing replaceStatusNote with no note clears it.
      statusNote: replaceStatusNote
          ? statusNote
          : (statusNote ?? prev.statusNote),
    );
  }

  /// Quick connectivity probe: resolves the update host. Used by the
  /// manual check to distinguish "no internet" from other failures.
  static Future<bool> _hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('nigraantv.xyz')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// This device's ABI as the manifest's "urls"/"versionCodes" maps
  /// name it (arm64-v8a / armeabi-v7a / x86_64), or null when it is
  /// none of those (e.g. a desktop test run) — the caller then falls
  /// back to the universal "url"/"versionCode".
  static String? currentAbiName() {
    final abi = Abi.current();
    if (abi == Abi.androidArm64) return 'arm64-v8a';
    if (abi == Abi.androidArm) return 'armeabi-v7a';
    if (abi == Abi.androidX64) return 'x86_64';
    return null;
  }

  /// Parses the version manifest into an [UpdateInfo], honouring the
  /// per-ABI maps when present (Magic Box pattern, split-per-ABI
  /// releases): `versionCodes` {arm64-v8a, armeabi-v7a, x86_64} and
  /// `urls` {…} (per-ABI APK links). Missing maps, an unknown ABI,
  /// or a missing per-ABI entry all fall back to the universal
  /// "versionCode"/"url". Returns null when the manifest has no
  /// usable version + URL. Pure — unit-tested; [abiNameOverride] is
  /// the test seam (production passes nothing and the real
  /// [currentAbiName] is used).
  static UpdateInfo? updateInfoFromManifest(
    Map<String, dynamic> data, {
    String? abiNameOverride,
  }) {
    final abiName = abiNameOverride ?? currentAbiName();
    int? remoteCode;
    if (abiName != null) {
      final codes = data['versionCodes'];
      if (codes is Map) {
        final code = codes[abiName];
        if (code is int) remoteCode = code;
      }
    }
    remoteCode ??= data['versionCode'] is int
        ? data['versionCode'] as int
        : null;
    String? url;
    if (abiName != null) {
      final urls = data['urls'];
      if (urls is Map) {
        final abiUrl = urls[abiName];
        if (abiUrl is String && abiUrl.isNotEmpty) url = abiUrl;
      }
    }
    url ??= data['url'] is String ? data['url'] as String : null;
    if (remoteCode == null || url == null || url.isEmpty) return null;
    return UpdateInfo(
      versionCode: remoteCode,
      versionName: (data['versionName'] as String?) ?? 'v$remoteCode',
      url: url,
      notes: (data['notes'] as String?) ?? '',
    );
  }

  /// Manual-check entry point with distinguished failure modes.
  /// Returns the status plus [UpdateInfo] when a newer version exists.
  /// Never throws.
  static Future<UpdateCheckOutcome> checkForUpdate() async {
    if (!await _hasInternetConnection()) {
      return const UpdateCheckOutcome(UpdateCheckResult.noInternet);
    }
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(Uri.parse(manifestUrl));
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != HttpStatus.ok) {
        return const UpdateCheckOutcome(UpdateCheckResult.manifestNotFound);
      }
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) {
        return const UpdateCheckOutcome(UpdateCheckResult.manifestNotFound);
      }
      final info = updateInfoFromManifest(data);
      if (info == null) {
        return const UpdateCheckOutcome(UpdateCheckResult.manifestNotFound);
      }
      final packageInfo = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(packageInfo.buildNumber) ?? 0;
      if (info.versionCode <= currentCode) {
        return const UpdateCheckOutcome(UpdateCheckResult.upToDate);
      }
      return UpdateCheckOutcome(UpdateCheckResult.available, info);
    } on SocketException {
      return const UpdateCheckOutcome(UpdateCheckResult.noInternet);
    } catch (_) {
      return const UpdateCheckOutcome(UpdateCheckResult.manifestNotFound);
    } finally {
      client?.close(force: true);
    }
  }

  /// Returns update info only when a NEWER version exists.
  /// Never throws: any failure (no network, missing manifest, bad
  /// JSON, bad version) simply means "no update prompt".
  /// Used by the silent launch check.
  static Future<UpdateInfo?> fetchUpdate() async {
    final outcome = await checkForUpdate();
    return outcome.update;
  }

  /// Silent launch check: shows a dialog only when an update exists.
  /// No prompt and no error popup in every other case.
  static Future<void> checkOnLaunch(BuildContext context) async {
    final update = await fetchUpdate();
    if (update == null || !context.mounted) return;
    showUpdateDialog(context, update);
  }

  /// Manual check: shows a specific message for each outcome —
  /// up-to-date vs no internet vs update file not found (Jaani 31 Oct
  /// 2026: these must NOT share one message).
  static Future<void> checkManually(BuildContext context) async {
    final outcome = await checkForUpdate();
    if (!context.mounted) return;
    switch (outcome.status) {
      case UpdateCheckResult.available:
        if (outcome.update != null) {
          showUpdateDialog(context, outcome.update!);
        }
        break;
      case UpdateCheckResult.upToDate:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Aap ka app up to date hai.'),
          ),
        );
        break;
      case UpdateCheckResult.noInternet:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Internet connection nahi hai — check karne ke liye '
              'internet on karein.',
            ),
          ),
        );
        break;
      case UpdateCheckResult.manifestNotFound:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Update file nahi mili — baad me koshish karein.'),
          ),
        );
        break;
    }
  }

  static void showUpdateDialog(BuildContext context, UpdateInfo update) {
    noteUpdateAvailable(update);
    showDialog<void>(
      context: context,
      // Jaani 3 Nov 2026: the update dialog must NEVER lock the app —
      // tapping outside dismisses it; the download runs in background.
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: Text('Naya version: ${update.versionName}'),
        content: Text(
          [
            if (update.notes.isNotEmpty) update.notes,
            'Install ke liye aap ko khud Install dabana hoga — '
                'app khud-ba-khud install nahi ho sakti.',
          ].join('\n\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              downloadAndInstall(context, update);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  /// Force-update dialog for the Remote Config kill-switch.
  /// Non-dismissible: no "Later" button, no tap-outside dismiss, and
  /// the Android back button is blocked. The Update button runs the
  /// SAME background download + system install-prompt flow as the
  /// normal update dialog.
  static void showForceUpdateDialog(BuildContext context, UpdateInfo update) {
    noteUpdateAvailable(update);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Update zaroori hai'),
            content: Text(
              update.notes.isNotEmpty
                  ? update.notes
                  : 'Is version ko mazeed istemal karne ke liye naya '
                      'version install karna zaroori hai. Update dabayen '
                      '— download background me hogi, aur install ke '
                      'liye aap ko khud Install dabana hoga.',
            ),
            actions: <Widget>[
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  downloadAndInstall(context, update);
                },
                child: const Text('Update karein'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Downloads the APK in the BACKGROUND and fires the system install
  /// prompt when ready. Never attempts a silent install.
  ///
  /// Jaani's order (2 Nov 2026): tapping "Update" must NOT lock the app
  /// behind a modal progress dialog. The user keeps using the app while
  /// the download runs; the install prompt appears only when ready.
  ///
  /// Jaani's order (3 Nov 2026): the download itself goes through
  /// Android's DownloadManager — a system process — so it keeps going
  /// even if the app is minimized or killed, shows a persistent system
  /// notification with progress, and auto-resumes after interruptions.
  /// We poll the download status, drive [backgroundProgress], and fire
  /// the install intent on success.
  static Future<void> downloadAndInstall(
    BuildContext context,
    UpdateInfo update,
  ) async {
    // Build 13 (point #18): a second tap while a flow is already
    // in flight is ANSWERED, never executed — the pre-Build-13
    // code enqueued a second DownloadManager download here,
    // overwrote the pending record and orphaned the first
    // download (the user's "double download" report).
    if (_downloadFlowActive) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Update download pehle se chal rahi hai — usi ko '
              'aage badhne dein.',
            ),
          ),
        );
      }
      return;
    }
    _downloadFlowActive = true;
    try {
      await _downloadAndInstallFlow(context, update);
    } finally {
      _downloadFlowActive = false;
    }
  }

  /// The download flow proper (see [downloadAndInstall] for the
  /// in-flight guard that wraps it).
  static Future<void> _downloadAndInstallFlow(
    BuildContext context,
    UpdateInfo update,
  ) async {
    // §7 state: this update is now the active one; any APK left over
    // from a previous download no longer counts as ready to install.
    _activeUpdate = update;
    _downloadedApkPath = null;
    _setUpdateState(
      UpdatePhase.available,
      percent: 0,
      bytesDownloaded: 0,
      bytesTotal: 0,
      replaceStatusNote: true,
    );

    // Build 13 (point #18): ENQUEUE-TIME RECONCILIATION — before
    // any new enqueue, look at the download a previous tap /
    // session left behind:
    //   same version, still running/pending/paused -> attach the
    //     poll to THAT download (no second enqueue);
    //   same version, already successful -> surface Install for
    //     the APK already on disk;
    //   same version failed/not_found, or another version's
    //     leftover -> remove the entry + its file, drop the
    //     record, and only then fall through to ONE fresh enqueue.
    if (await _reconcilePendingDownload(context, update)) return;

    // 1. The system installer needs the "install unknown apps" grant.
    bool canInstall = false;
    try {
      canInstall =
          await _channel.invokeMethod<bool>('canInstallPackages') ?? false;
    } catch (_) {
      canInstall = false;
    }
    if (!canInstall) {
      try {
        await _channel.invokeMethod<void>('openInstallSettings');
      } catch (_) {}
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pehle Settings me TJ Pro ke liye "Install unknown apps" '
              'allow karein, phir dobara Update dabayen.',
            ),
          ),
        );
      }
      return;
    }

    // 2. Hand the download to the system DownloadManager.
    int? downloadId;
    try {
      downloadId = await _channel.invokeMethod<int>(
        'downloadApk',
        <String, String>{'url': update.url, 'fileName': _apkFileName},
      );
    } catch (_) {
      downloadId = null;
    }
    if (downloadId == null) {
      backgroundProgress.value = null;
      // §7: quiet failed state — the progress bar offers a retry,
      // no popup loop (the existing snackbar below still shows).
      _setUpdateState(UpdatePhase.failed);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Update download shuru nahi ho saki. Internet check kar '
              'ke dobara koshish karein.',
            ),
          ),
        );
      }
      return;
    }

    // 3. Tell the user, return immediately — no modal, no lock.
    backgroundProgress.value = 0;
    _setUpdateState(
      UpdatePhase.downloading,
      percent: 0,
      bytesDownloaded: 0,
      bytesTotal: 0,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Update background me download ho rahi hai — aap app '
            'istemal karte rahen.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }

    // 4. Persist the pending download (#34 fix design 3), then poll
    // it to a terminal state. The persisted record lets a later
    // launch re-attach if this process dies mid-download.
    await _persistPendingDownload(update, downloadId);
    await _pollDownload(
      downloadId: downloadId,
      showMessage: (String message) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      },
    );
  }

  /// Build 13 (point #18): enqueue-time reconciliation — see
  /// the call site in [_downloadAndInstallFlow]. Returns true
  /// when the existing download fully handles this tap (attached
  /// poll or Install surfaced); false when the caller should
  /// proceed to exactly ONE fresh enqueue (any stale entry has
  /// already been removed at that point).
  static Future<bool> _reconcilePendingDownload(
    BuildContext context,
    UpdateInfo update,
  ) async {
    int? pendingId;
    var pendingCode = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      pendingId = prefs.getInt(_pendingDownloadIdKey);
      pendingCode = prefs.getInt(_pendingVersionCodeKey) ?? 0;
    } catch (_) {
      return false;
    }
    if (pendingId == null) return false;
    final status = await _statusOf(pendingId);
    if (status == null) {
      // The channel cannot answer (degraded native side): fall
      // through to the fresh enqueue — the native destination
      // hygiene keeps the fixed file name from failing it.
      return false;
    }
    final state = status['status'] as String?;
    if (pendingCode != update.versionCode) {
      // Another version's leftover: remove it so it can never
      // block or confuse this update, then enqueue fresh.
      await _removeDownload(pendingId);
      await _clearPendingDownload();
      return false;
    }
    if (state == 'running' || state == 'pending' || state == 'paused') {
      final downloaded = (status['bytesDownloaded'] as int?) ?? 0;
      final total = clampTotalBytes((status['bytesTotal'] as int?) ?? 0);
      backgroundProgress.value =
          total > 0 ? (downloaded / total).clamp(0.0, 1.0) : 0;
      _setUpdateState(
        UpdatePhase.downloading,
        percent: total > 0
            ? ((downloaded / total) * 100).round().clamp(0, 100)
            : 0,
        bytesDownloaded: downloaded,
        bytesTotal: total,
        statusNote: state == 'paused'
            ? 'Download ruki hui hai — '
                '${pausedReasonText((status['reason'] as int?) ?? -1)}.'
            : null,
        replaceStatusNote: true,
      );
      if (_pollingDownloadId == pendingId) {
        // A poll (the launch-restore one) is already watching
        // this exact download — attaching a second watcher would
        // double-fire the install intent on success.
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Update download pehle se chal rahi hai — usi ko '
                'aage badhne dein.',
              ),
            ),
          );
        }
        return true;
      }
      await _pollDownload(
        downloadId: pendingId,
        showMessage: (String message) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message)),
            );
          }
        },
      );
      return true;
    }
    if (state == 'success') {
      final uri = (status['localUri'] as String?) ?? '';
      final path = _uriToPath(uri);
      if (path != null && File(path).existsSync()) {
        _downloadedApkPath = path;
        final downloaded = (status['bytesDownloaded'] as int?) ?? 0;
        final total = clampTotalBytes((status['bytesTotal'] as int?) ?? 0);
        _setUpdateState(
          UpdatePhase.downloaded,
          percent: 100,
          bytesDownloaded: total > 0 ? total : downloaded,
          bytesTotal: total,
          replaceStatusNote: true,
        );
        await _clearPendingDownload();
        try {
          await _channel.invokeMethod<void>(
            'installApk',
            <String, String>{'path': path},
          );
        } catch (_) {}
        return true;
      }
      // Marked successful but the file is gone — clean up and
      // let the caller enqueue fresh.
      await _removeDownload(pendingId);
      await _clearPendingDownload();
      return false;
    }
    // failed / not_found / unrecognised: remove the entry + its
    // partial file, drop the record, enqueue exactly once.
    await _removeDownload(pendingId);
    await _clearPendingDownload();
    return false;
  }

  /// Persists the in-flight system download (#34 fix design 3) so
  /// [restorePendingDownload] can re-attach after an app kill.
  /// Fail-soft: the live poll in this session is unaffected if the
  /// write fails.
  static Future<void> _persistPendingDownload(
    UpdateInfo update,
    int downloadId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_pendingDownloadIdKey, downloadId);
      await prefs.setInt(_pendingVersionCodeKey, update.versionCode);
      await prefs.setString(_pendingVersionNameKey, update.versionName);
      await prefs.setString(_pendingUrlKey, update.url);
      await prefs.setString(_pendingNotesKey, update.notes);
    } catch (_) {}
  }

  /// Drops the persisted pending-download record (terminal state
  /// reached, or the record proved stale).
  static Future<void> _clearPendingDownload([
    SharedPreferences? prefs,
  ]) async {
    try {
      final p = prefs ?? await SharedPreferences.getInstance();
      await p.remove(_pendingDownloadIdKey);
      await p.remove(_pendingVersionCodeKey);
      await p.remove(_pendingVersionNameKey);
      await p.remove(_pendingUrlKey);
      await p.remove(_pendingNotesKey);
    } catch (_) {}
  }

  /// Polls the system DownloadManager for [downloadId] until the
  /// download reaches a terminal state, driving [backgroundProgress]
  /// and [updateState] exactly as the pre-Phase-0 inline loop did —
  /// with the #34 fix design applied:
  ///
  /// - Channel errors are NOT swallowed silently: the first one is
  ///   logged, and after 5 in a row the quiet failed state surfaces
  ///   (Retry) instead of a fake frozen download.
  /// - No ~10-minute cap: polling runs until success / failed /
  ///   not_found, with a generous 6-hour safety cap; on cap expiry
  ///   the phase STAYS downloading (the system notification remains
  ///   the progress source and the persisted record lets the next
  ///   launch re-attach) rather than dropping to idle.
  /// - A raw total of -1 (DownloadManager "unknown") is clamped to
  ///   0 in state via [clampTotalBytes], so the UI shows
  ///   downloaded-MB + an indeterminate bar until the real total
  ///   arrives.
  ///
  /// [showMessage] is optional: the launch-restore path passes
  /// none, so its messages are skipped while state updates still
  /// land. The caller wraps it in its own mounted check.
  static Future<void> _pollDownload({
    required int downloadId,
    void Function(String message)? showMessage,
  }) async {
    // 2 s interval; 10800 polls ≈ 6 h safety cap.
    const int maxPolls = 10800;
    var consecutiveChannelFailures = 0;
    // Build 13 (point #18): paused tracking for the watchdog —
    // when the download entered PAUSED and whether the user has
    // already been told (with the reason) about this pause.
    DateTime? pausedSince;
    var pausedWatchdogFired = false;
    _pollingDownloadId = downloadId;
    try {
      for (var i = 0; i < maxPolls; i++) {
        await Future.delayed(const Duration(seconds: 2));
        Map? status;
        try {
          status = await _channel.invokeMethod<Map>(
            'downloadStatus',
            <String, Object>{'downloadId': downloadId},
          );
          consecutiveChannelFailures = 0;
        } catch (e) {
          consecutiveChannelFailures++;
          if (consecutiveChannelFailures == 1) {
            // #34 fix design 2: the first failure is VISIBLE in
            // the log instead of being swallowed like the old
            // loop did on every single poll.
            debugPrint('[TJPro][update] downloadStatus poll failed: $e');
          }
          if (consecutiveChannelFailures >= 5) {
            // The status channel itself is broken — surface the
            // quiet failed state. Build 13: the persisted record
            // is KEPT and Retry now RECONCILES first (see
            // downloadAndInstall) — if the system download is in
            // fact still running, Retry re-attaches to it instead
            // of enqueueing a second copy (the pre-Build-13
            // double-download path).
            backgroundProgress.value = null;
            _setUpdateState(
              UpdatePhase.failed,
              statusNote: 'Download ki halat nahi mil rahi thi — '
                  'Retry dabayein, pehle halat check hogi.',
              replaceStatusNote: true,
            );
            return;
          }
          continue;
        }
        final String? state = status?['status'] as String?;
        final int downloaded = (status?['bytesDownloaded'] as int?) ?? 0;
        final int total = clampTotalBytes(
          (status?['bytesTotal'] as int?) ?? 0,
        );
        if (total > 0) {
          backgroundProgress.value = (downloaded / total).clamp(0.0, 1.0);
          // §7: surface the poll's real byte counts to the UI state.
          _setUpdateState(
            UpdatePhase.downloading,
            percent: ((downloaded / total) * 100).round().clamp(0, 100),
            bytesDownloaded: downloaded,
            bytesTotal: total,
          );
        } else {
          // Total not known yet: keep the byte count, stay
          // indeterminate (percent unchanged).
          _setUpdateState(
            UpdatePhase.downloading,
            bytesDownloaded: downloaded,
            bytesTotal: total,
          );
        }
        // Build 13 (point #18): PAUSED is no longer invisible.
        // The reason (from COLUMN_REASON) goes into the state
        // note at once, and a download paused for the whole
        // watchdog window earns ONE explanatory message — the
        // pre-Build-13 poll just kept looping while the percent
        // sat frozen at 4/5/10/40%.
        if (state == 'paused') {
          final reason = (status?['reason'] as int?) ?? -1;
          final since = pausedSince ??= DateTime.now();
          _setUpdateState(
            UpdatePhase.downloading,
            statusNote: 'Download ruki hui hai — '
                '${pausedReasonText(reason)}.',
          );
          if (!pausedWatchdogFired &&
              DateTime.now().difference(since) >= pausedWatchdog) {
            pausedWatchdogFired = true;
            showMessage?.call(
              'Update download kaafi der se ruki hai — '
              '${pausedReasonText(reason)}. Internet / Wi-Fi check '
              'karein; masla hal hote hi download khud aage badhegi.',
            );
          }
        } else if (state == 'running' || state == 'pending') {
          if (pausedSince != null) {
            pausedSince = null;
            pausedWatchdogFired = false;
            _setUpdateState(
              UpdatePhase.downloading,
              replaceStatusNote: true,
            );
          }
        }
        if (state == 'success') {
          backgroundProgress.value = null;
          final String uri = (status?['localUri'] as String?) ?? '';
          final String? path = _uriToPath(uri);
          if (path == null) {
            // Downloaded but unusable: quiet failed state with a
            // retry (existing behaviour simply returned silently).
            await _clearPendingDownload();
            _setUpdateState(UpdatePhase.failed);
            return;
          }
          // §7: remember the APK and mark it downloaded BEFORE the
          // install intent fires, so the progress bar's Install
          // button can re-fire the same intent with one tap if the
          // user backs out of the system installer.
          _downloadedApkPath = path;
          _setUpdateState(
            UpdatePhase.downloaded,
            percent: 100,
            bytesDownloaded: total > 0 ? total : downloaded,
            bytesTotal: total,
          );
          await _clearPendingDownload();
          try {
            await _channel.invokeMethod<void>(
              'installApk',
              <String, String>{'path': path},
            );
          } catch (_) {}
          return;
        }
        if (state == 'failed' || state == 'not_found') {
          backgroundProgress.value = null;
          // Build 13 (point #18): surface the DownloadManager
          // reason (logged through CrashGuard so it lands in the
          // diagnostics), remove the dead entry + its partial
          // file so nothing poisons the retry, and let Retry
          // reconcile-then-enqueue exactly once.
          final reason = (status?['reason'] as int?) ?? -1;
          final reasonText = state == 'failed'
              ? failedReasonText(reason)
              : 'download system mein nahi mili';
          if (state == 'failed') {
            CrashGuard.report(
              Exception(
                'Update download failed (reason $reason: $reasonText)',
              ),
              StackTrace.current,
              source: 'update-download',
            );
          }
          await _removeDownload(downloadId);
          await _clearPendingDownload();
          _setUpdateState(
            UpdatePhase.failed,
            statusNote: 'Wajah: $reasonText.',
            replaceStatusNote: true,
          );
          showMessage?.call(
            'Update download nahi ho saka — $reasonText. '
            'Retry dabayein.',
          );
          return;
        }
        // running / pending / paused -> keep polling; the system
        // notification shows live progress meanwhile.
      }
      // Safety cap reached (~6 h): NOT a failure and NOT idle —
      // the download may still be running natively. The phase
      // stays downloading and the persisted record stays, so the
      // next launch re-attaches via [restorePendingDownload].
      backgroundProgress.value = null;
    } catch (_) {
      backgroundProgress.value = null;
      _setUpdateState(UpdatePhase.failed);
      showMessage?.call(
        'Update download nahi ho saka. Internet check kar ke '
        'dobara koshish karein.',
      );
    } finally {
      if (_pollingDownloadId == downloadId) _pollingDownloadId = null;
    }
  }

  /// Phase 0 (#34 fix design 3): re-attach to a system download a
  /// previous session left behind. Called once from `main()`,
  /// backgrounded; fully fail-soft — any problem simply means the
  /// normal launch flow proceeds untouched.
  ///
  /// - The record's version is already installed -> the hop
  ///   finished while we were gone; drop the record.
  /// - Still running / pending / paused -> restore the downloading
  ///   state (with the last known byte counts) and resume polling.
  /// - Already successful -> surface the downloaded state so the
  ///   banner offers Install for the APK on disk.
  /// - Failed / not_found -> drop the stale record quietly.
  /// - Channel unreachable or an unrecognised status -> KEEP the
  ///   record; the next launch tries again rather than orphaning
  ///   a possibly-live download.
  static Future<void> restorePendingDownload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final int? downloadId = prefs.getInt(_pendingDownloadIdKey);
      if (downloadId == null) return;
      final int code = prefs.getInt(_pendingVersionCodeKey) ?? 0;
      if (code > 0) {
        final packageInfo = await PackageInfo.fromPlatform();
        final int installed = int.tryParse(packageInfo.buildNumber) ?? 0;
        if (installed >= code) {
          await _clearPendingDownload(prefs);
          return;
        }
      }
      Map? status;
      try {
        status = await _channel.invokeMethod<Map>(
          'downloadStatus',
          <String, Object>{'downloadId': downloadId},
        );
      } catch (_) {
        return;
      }
      final String? state = status?['status'] as String?;
      final int downloaded = (status?['bytesDownloaded'] as int?) ?? 0;
      final int total = clampTotalBytes(
        (status?['bytesTotal'] as int?) ?? 0,
      );
      final update = UpdateInfo(
        versionCode: code,
        versionName: prefs.getString(_pendingVersionNameKey) ?? 'v$code',
        url: prefs.getString(_pendingUrlKey) ?? '',
        notes: prefs.getString(_pendingNotesKey) ?? '',
      );
      if (state == 'running' || state == 'pending' || state == 'paused') {
        _activeUpdate = update;
        _downloadedApkPath = null;
        backgroundProgress.value =
            total > 0 ? (downloaded / total).clamp(0.0, 1.0) : 0;
        _setUpdateState(
          UpdatePhase.downloading,
          percent: total > 0
              ? ((downloaded / total) * 100).round().clamp(0, 100)
              : 0,
          bytesDownloaded: downloaded,
          bytesTotal: total,
          // Build 13: a re-attached PAUSED download explains
          // itself immediately instead of looking frozen.
          statusNote: state == 'paused'
              ? 'Download ruki hui hai — '
                  '${pausedReasonText((status?['reason'] as int?) ?? -1)}.'
              : null,
          replaceStatusNote: true,
        );
        await _pollDownload(downloadId: downloadId);
      } else if (state == 'success') {
        final String uri = (status?['localUri'] as String?) ?? '';
        final String? path = _uriToPath(uri);
        if (path == null) {
          await _clearPendingDownload(prefs);
          return;
        }
        _activeUpdate = update;
        _downloadedApkPath = path;
        _setUpdateState(
          UpdatePhase.downloaded,
          percent: 100,
          bytesDownloaded: total > 0 ? total : downloaded,
          bytesTotal: total,
        );
        await _clearPendingDownload(prefs);
      } else if (state == 'failed' || state == 'not_found') {
        await _clearPendingDownload(prefs);
      }
    } catch (_) {
      // Restore is best-effort by design — never break startup.
    }
  }

  /// Convert a DownloadManager local URI (file://) to a path usable by
  /// the install intent. We always download into the app's external
  /// files dir, so this is a file:// URI.
  static String? _uriToPath(String uri) {
    if (uri.isEmpty) return null;
    if (uri.startsWith('file://')) {
      return Uri.parse(uri).toFilePath();
    }
    return null;
  }
}
