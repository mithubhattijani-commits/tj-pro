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
        }
        if (state == 'success') {
          backgroundProgress.value = null;
          final String uri = (status?['localUri'] as String?) ?? '';
          final String? path = _uriToPath(uri);
          if (path != null) {
            try {
              await _channel.invokeMethod<void>(
                'installApk',
                <String, String>{'path': path},
              );
            } catch (_) {}
          }
          return;
        }
        if (state == 'failed' || state == 'not_found') {
          backgroundProgress.value = null;
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
