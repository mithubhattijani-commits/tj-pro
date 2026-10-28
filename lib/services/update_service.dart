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

class UpdateService {
  /// Fixed manifest URL. The file itself is published later by the
  /// parent (with the stable APK download link); until then this
  /// checker stays silent.
  static const String manifestUrl =
      'https://nigraantv.xyz/apps/tj-pro-version.json';

  static const String _apkFileName = 'tj-pro-update.apk';

  /// Returns update info only when a NEWER version exists.
  /// Never throws: any failure (no network, missing manifest, bad
  /// JSON, bad version) simply means "no update prompt".
  static Future<UpdateInfo?> fetchUpdate() async {
    HttpClient? client;
    try {
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      final request = await client.getUrl(Uri.parse(manifestUrl));
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != HttpStatus.ok) return null;
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) return null;
      final remoteCode = data['versionCode'];
      final url = data['url'];
      if (remoteCode is! int || url is! String || url.isEmpty) return null;
      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber) ?? 0;
      if (remoteCode <= currentCode) return null;
      return UpdateInfo(
        versionCode: remoteCode,
        versionName: (data['versionName'] as String?) ?? 'v$remoteCode',
        url: url,
        notes: (data['notes'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  /// Silent launch check: shows a dialog only when an update exists.
  /// No prompt and no error popup in every other case.
  static Future<void> checkOnLaunch(BuildContext context) async {
    final update = await fetchUpdate();
    if (update == null || !context.mounted) return;
    showUpdateDialog(context, update);
  }

  /// Manual check: tells the user when nothing newer was found.
  static Future<void> checkManually(BuildContext context) async {
    final update = await fetchUpdate();
    if (!context.mounted) return;
    if (update == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Koi naya version nahi mila. Internet ya update file '
            'na milne par bhi yehi dikhta hai.',
          ),
        ),
      );
      return;
    }
    showUpdateDialog(context, update);
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

  /// Downloads the APK (with a progress dialog) and fires the system
  /// install prompt. Never attempts a silent install.
  static Future<void> downloadAndInstall(
    BuildContext context,
    UpdateInfo update,
  ) async {
    final progress = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (_, value, __) => AlertDialog(
          title: const Text('Update download ho raha hai'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value > 0 ? value : null),
              const SizedBox(height: 12),
              Text(
                value > 0
                    ? '${(value * 100).toStringAsFixed(0)}% complete'
                    : 'Download ho raha hai…',
              ),
            ],
          ),
        ),
      ),
    );
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
          if (total > 0) progress.value = received / total;
        }
        await sink.close();
      } finally {
        client.close(force: true);
      }
      if (context.mounted) Navigator.pop(context);
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
      if (context.mounted) {
        Navigator.pop(context);
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
      progress.dispose();
    }
  }
}
