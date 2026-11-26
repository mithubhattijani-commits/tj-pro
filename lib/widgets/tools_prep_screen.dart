import 'dart:async';

import 'package:flutter/material.dart';

import '../services/first_run_prep_service.dart';

/// v1.17.0 (G5, Point #37d): the one-time "Preparing your
/// tools" screen. Shown from Home on the first launch where
/// [FirstRunPrepService.isComplete] is false: every AI model
/// and asset downloads ONCE here, with progress, so no tool
/// ever waits on a download mid-use.
///
/// The user can leave with "Later" — the run keeps going in
/// the background, and whatever is missing is simply prepared
/// again on the next launch (readiness is verified on disk,
/// never assumed). Failures are listed by name at the end;
/// the owning tools keep their own honest at-use errors.
class ToolsPrepScreen extends StatefulWidget {
  const ToolsPrepScreen({super.key, required this.kasheedaUrl});

  final String kasheedaUrl;

  @override
  State<ToolsPrepScreen> createState() => _ToolsPrepScreenState();
}

class _ToolsPrepScreenState extends State<ToolsPrepScreen> {
  PrepProgress? _progress;
  bool _running = true;
  List<String> _failed = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    if (mounted) {
      setState(() {
        _running = true;
        _failed = const [];
      });
    }
    final failed = await FirstRunPrepService.run(
      kasheedaUrl: widget.kasheedaUrl,
      onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _failed = failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalMb = FirstRunPrepService.items().fold<int>(
          0,
          (a, i) => a + i.weightBytes,
        ) ~/
        (1024 * 1024);
    final pct = ((_progress?.overall ?? 0) * 100).round();
    return Scaffold(
      appBar: AppBar(title: const Text('Preparing your tools')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'One-time setup',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Jaani Studio is downloading the AI models and assets its '
              'tools need (about $totalMb MB). This happens only '
              'once — afterwards every tool opens instantly, with '
              'no waiting in the middle of your work. Wi-Fi is '
              'recommended.',
              style: const TextStyle(fontSize: 13.5, height: 1.45),
            ),
            const SizedBox(height: 28),
            if (_running) ...[
              LinearProgressIndicator(value: _progress?.overall ?? 0),
              const SizedBox(height: 12),
              Text(
                _progress == null
                    ? 'Starting…'
                    : '${_progress!.label} — $pct%',
                style: const TextStyle(fontSize: 13),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Later — continue in background'),
              ),
            ] else if (_failed.isEmpty) ...[
              const Icon(Icons.check_circle, size: 52, color: Colors.green),
              const SizedBox(height: 12),
              const Text(
                'All tools are ready.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Start using Jaani Studio'),
              ),
            ] else ...[
              const Text(
                'Some downloads did not finish (usually the '
                'internet). These tools will simply download '
                'their model when first opened, or you can retry '
                'now:',
                style: TextStyle(fontSize: 13.5, height: 1.45),
              ),
              const SizedBox(height: 12),
              for (final f in _failed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 16,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(f)),
                    ],
                  ),
                ),
              const Spacer(),
              FilledButton(
                onPressed: () => unawaited(_start()),
                child: const Text('Retry'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Continue anyway'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
