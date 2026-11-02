/// TJ Pro — in-app update checker for sideloaded builds.
///
/// The app fetches a small JSON manifest from the website and compares
/// its versionCode with the installed one. When a newer version exists,
/// the user is offered an update; the new APK is downloaded and the
/// system install prompt is fired. A sideloaded app can NEVER install
/// silently — Android always requires the user's install tap, and the
/// UI says so honestly.
///
/// Manifest format (served from the website, published separately):
///   {"versionCode": 3, "versionName": "1.2.0",
///    "url": "https://.../tj-pro.apk", "notes": "What's new"}
///
/// The updater is inert until that manifest exists: a missing or
/// unreachable manifest simply means "no update prompt, no error".
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

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
      final remoteCode = data['versionCode'];
      final url = data['url'];
      if (remoteCode is! int || url is! String || url.isEmpty) {
        return const UpdateCheckOutcome(UpdateCheckResult.manifestNotFound);
      }
      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber) ?? 0;
      if (remoteCode <= currentCode) {
        return const UpdateCheckOutcome(UpdateCheckResult.upToDate);
      }
      return UpdateCheckOutcome(
        UpdateCheckResult.available,
        UpdateInfo(
          versionCode: remoteCode,
          versionName: (data['versionName'] as String?) ?? 'v$remoteCode',
          url: url,
          notes: (data['notes'] as String?) ?? '',
        ),
      );
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
  static Future<void> downloadAndInstall(
    BuildContext context,
    UpdateInfo update,
  ) async {
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
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$_apkFileName');
      if (await file.exists()) await file.delete();
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30);
      try {
        final request = await client.getUrl(Uri.parse(update.url));
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('Download failed: ${response.statusCode}');
        }
        final total = response.contentLength;
        var received = 0;
        final sink = file.openWrite();
        await for (final chunk in response) {
          received += chunk.length;
          sink.add(chunk);
          if (total > 0) backgroundProgress.value = received / total;
        }
        await sink.close();
      } finally {
        client.close(force: true);
      }
      backgroundProgress.value = null;
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Install prompt nahi khula. Settings me TJ Pro ke liye '
              '"Install unknown apps" allow karein, phir dobara Update '
              'dabayen.',
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
    } finally {
      backgroundProgress.value = null;
    }
  }
}
