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
  });

  final UpdatePhase phase;
  final int percent;
  final int bytesDownloaded;
  final int bytesTotal;

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

  /// Restarts a failed/interrupted download cleanly through the
  /// existing [downloadAndInstall] flow. A no-op when no update is
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
  }) {
    final UpdateState prev = updateState.value;
    updateState.value = UpdateState(
      phase: phase,
      percent: percent ?? prev.percent,
      bytesDownloaded: bytesDownloaded ?? prev.bytesDownloaded,
      bytesTotal: bytesTotal ?? prev.bytesTotal,
      update: _activeUpdate ?? prev.update,
      downloadedApkPath: _downloadedApkPath,
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
    // §7 state: this update is now the active one; any APK left over
    // from a previous download no longer counts as ready to install.
    _activeUpdate = update;
    _downloadedApkPath = null;
    _setUpdateState(
      UpdatePhase.available,
      percent: 0,
      bytesDownloaded: 0,
      bytesTotal: 0,
    );

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

    // 4. Poll the system download for progress/completion.
    try {
      for (var i = 0; i < 300; i++) {
        await Future.delayed(const Duration(seconds: 2));
        Map? status;
        try {
          status = await _channel.invokeMethod<Map>(
            'downloadStatus',
            <String, Object>{'downloadId': downloadId},
          );
        } catch (_) {
          continue;
        }
        final String? state = status?['status'] as String?;
        final int downloaded =
            (status?['bytesDownloaded'] as int?) ?? 0;
        final int total = (status?['bytesTotal'] as int?) ?? 0;
        if (total > 0) {
          backgroundProgress.value =
              (downloaded / total).clamp(0.0, 1.0);
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
        if (state == 'success') {
          backgroundProgress.value = null;
          final String uri = (status?['localUri'] as String?) ?? '';
          final String? path = _uriToPath(uri);
          if (path == null) {
            // Downloaded but unusable: quiet failed state with a
            // retry (existing behaviour simply returned silently).
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
          // §7: quiet failed state — retry restarts cleanly via
          // [retryDownload]; no popup is ever shown for this.
          _setUpdateState(UpdatePhase.failed);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Update download nahi ho saka. Internet check kar ke '
                  'dobara koshish karein.',
                ),
              ),
            );
          }
          return;
        }
        // running / pending / paused -> keep polling; the system
        // notification shows live progress meanwhile.
      }
      // Timed out after ~10 minutes of polling.
      backgroundProgress.value = null;
      // §7: NOT a failure — the system download may still be running
      // (its notification shows progress), so the state goes quiet
      // (idle) instead of offering a conflicting retry.
      _setUpdateState(UpdatePhase.idle);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Update download me waqt lag raha hai — notification me '
              'progress dekhte rahen.',
            ),
          ),
        );
      }
    } catch (_) {
      backgroundProgress.value = null;
      _setUpdateState(UpdatePhase.failed);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Update download nahi ho saka. Internet check kar ke '
              'dobara koshish karein.',
            ),
          ),
        );
      }
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
