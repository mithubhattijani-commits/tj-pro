/// Build 9 (v1.7.0, fix-list point #5) — "REPORT BHEJO" screen.
///
/// The user-facing half of the crash-report system: the user
/// may describe a problem in their own words — or send the
/// report EMPTY; either way the report goes to the Supabase
/// table `tjpro_feedback` with the latest on-device diagnostics
/// attached automatically (see feedback_service.dart).
///
/// Rules honoured here:
/// - The typed text is NEVER lost to a failed send: it stays in
///   the field, a draft is persisted, and the screen says
///   plainly "phir koshish karein".
/// - Entry point: About dialog -> "Report bhejo" (main.dart).
library;

import 'package:flutter/material.dart';

import '../services/crash_guard.dart';
import '../services/feedback_service.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  Future<void> _loadDraft() async {
    final draft = await FeedbackService.loadDraft();
    if (!mounted || draft.isEmpty) return;
    if (_controller.text.isEmpty) {
      _controller.text = draft;
    }
  }

  @override
  void dispose() {
    // Keep an unsent draft for the next visit.
    FeedbackService.saveDraft(_controller.text);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final diagnostics =
        await CrashGuard.loadStoredDiagnostic() ??
            CrashGuard.lastDiagnostic.value ??
            '';
    final ok = await FeedbackService.send(
      message: _controller.text.trim(),
      diagnostics: diagnostics,
    );
    if (!mounted) return;
    if (ok) {
      _controller.clear();
      await FeedbackService.saveDraft('');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report sent — thank you!'),
        ),
      );
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _sending = false;
      _error =
          'Report did not send — it looks like a network issue. Your '
          'written report is safe here; try again.';
    });
    await FeedbackService.saveDraft(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report bhejo')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.bug_report_outlined, size: 20),
                SizedBox(width: 8),
                Text(
                  'Any problem or error?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Write in your own words what happened. You can also send it '
              'empty and send it — along with the report, the app\'s '
              'the latest diagnostics (which screen, what error) will go '
              'by themselves. No private information of yours '
              'does not go.',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('feedbackMessageField'),
              controller: _controller,
              minLines: 4,
              maxLines: 8,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText: 'Write here… (empty is fine too)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ],
            const SizedBox(height: 14),
            ElevatedButton.icon(
              key: const Key('feedbackSendButton'),
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined, size: 18),
              label: Text(_sending ? 'Sending…' : 'Report bhejo'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
