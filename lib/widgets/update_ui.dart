/// TJ Pro — in-app update UX (plan §7, v1.2.0).
///
/// EXTENDS the existing update system in
/// `lib/services/update_service.dart`; it replaces nothing:
///
/// * [UpdatePopup] / [showUpdatePopupOnce] — the modal shown when an
///   update is available. Its Update button starts the EXISTING
///   background download ([UpdateService.downloadAndInstall]); its
///   Later button snoozes the popup for the rest of the session, and
///   the session guard in [UpdateService] guarantees at most one
///   popup per launch.
/// * [UpdateProgressBar] — a slim bar bound to
///   [UpdateService.updateState] that sits above the home content
///   while the APK downloads in the background (the app stays fully
///   usable). It shows percent + MB downloaded / MB remaining; when
///   the download completes it offers a one-tap Install button that
///   fires the existing install intent, and on failure it shows a
///   quiet Retry (never a popup loop).
library;

import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// Formats a byte count as MB with one decimal, e.g. `12.4 MB`.
String _mb(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

/// Shows the §7 [UpdatePopup] for [update] — at most once per
/// launch, and never after the user tapped Later this session
/// ([UpdateService.canShowUpdatePopup]). Call this from the home
/// screen's post-launch flow instead of (not in addition to) the
/// silent `UpdateService.checkOnLaunch` prompt, so the user never
/// sees two update dialogs for the same launch.
void showUpdatePopupOnce(BuildContext context, UpdateInfo update) {
  if (!UpdateService.canShowUpdatePopup) return;
  UpdateService.markUpdatePopupShown();
  UpdateService.noteUpdateAvailable(update);
  showDialog<void>(
    context: context,
    // Same rule as the existing update dialog (Jaani 3 Nov 2026):
    // the popup must NEVER lock the app — tap-outside dismisses it.
    barrierDismissible: true,
    builder: (dialogContext) => UpdatePopup(
      update: update,
      onLater: () {
        UpdateService.snoozeUpdatePopup();
        Navigator.pop(dialogContext);
      },
      onUpdate: () {
        Navigator.pop(dialogContext);
        // The OUTER context (still mounted after the dialog closes)
        // drives the existing background download + install flow.
        UpdateService.downloadAndInstall(context, update);
      },
    ),
  );
}

/// Modal "update available" dialog (plan §7).
///
/// Pure presentation: [onUpdate] starts the download, [onLater]
/// dismisses + snoozes. Wired for real use by [showUpdatePopupOnce].
class UpdatePopup extends StatelessWidget {
  const UpdatePopup({
    super.key,
    required this.update,
    required this.onUpdate,
    required this.onLater,
  });

  final UpdateInfo update;
  final VoidCallback onUpdate;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.system_update, size: 36),
      title: Text('New version: ${update.versionName}'),
      content: Text(
        [
          if (update.notes.isNotEmpty) update.notes,
          'Tap Update — the download will be in the background and you can '
              'keep using the app. When the download completes, '
              'For install, you will have to tap Install yourself — the app '
              'cannot install by itself.',
        ].join('\n\n'),
      ),
      actions: [
        TextButton(
          onPressed: onLater,
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: onUpdate,
          child: const Text('Update'),
        ),
      ],
    );
  }
}

/// Slim background-download indicator bound to
/// [UpdateService.updateState] (plan §7).
///
/// Mount it once above the home content (see the coordinator wiring
/// note): it renders nothing while idle / merely available, a thin
/// progress strip while downloading, an Install button once the APK
/// is downloaded, and a quiet Retry row after a failed download.
/// It never blocks or covers the app's own UI.
class UpdateProgressBar extends StatelessWidget {
  const UpdateProgressBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateState>(
      valueListenable: UpdateService.updateState,
      builder: (context, state, _) {
        switch (state.phase) {
          case UpdatePhase.idle:
          case UpdatePhase.available:
            return const SizedBox.shrink();
          case UpdatePhase.downloading:
            return _bar(
              context,
              child: Row(
                children: [
                  const Icon(Icons.downloading, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          state.bytesTotal > 0
                              ? 'Update is downloading — '
                                  '${state.percent}%  •  '
                                  '${_mb(state.bytesDownloaded)} / '
                                  '${_mb(state.bytesTotal)}  •  '
                                  '${_mb(state.bytesRemaining)} baqi'
                              : 'Update is downloading — '
                                  '${_mb(state.bytesDownloaded)} '
                                  'downloaded',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: state.bytesTotal > 0
                              ? state.fraction
                              : null,
                          minHeight: 4,
                        ),
                        // Build 13 (point #18): WHY the download
                        // is paused, in the user's words — the
                        // frozen-percent complaint's direct fix.
                        if (state.statusNote != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            state.statusNote!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          case UpdatePhase.downloaded:
            return _bar(
              context,
              child: Row(
                children: [
                  const Icon(Icons.download_done, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Update has downloaded.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () =>
                        UpdateService.installDownloadedApk(),
                    child: const Text('Install'),
                  ),
                ],
              ),
            );
          case UpdatePhase.installing:
            return _bar(
              context,
              child: const Row(
                children: [
                  Icon(Icons.install_mobile, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The installer is opening — there, tap Install '
                      'dabayen.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            );
          case UpdatePhase.failed:
            return _bar(
              context,
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      state.statusNote == null
                          ? 'Update could not download.'
                          : 'Update could not download. '
                              '${state.statusNote}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        UpdateService.retryDownload(context),
                    child: const Text('Retry'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Close',
                    onPressed: () =>
                        UpdateService.dismissFailedState(),
                  ),
                ],
              ),
            );
        }
      },
    );
  }

  /// Shared slim strip: full-width, theme surface, divider on top so
  /// it reads as part of the scaffold rather than a floating card.
  Widget _bar(BuildContext context, {required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: child,
    );
  }
}
