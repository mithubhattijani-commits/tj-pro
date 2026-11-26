/// "Draft in progress" recovery card (Phase 9, master prompt §14).
///
/// Shown on the News Studio home when the autosaved latest project
/// still has content. Three real actions, no dead buttons:
///   - "Resume" — opens the draft in the News Maker with its
///     actual saved contents (the caller passes the project through).
///   - "Discard" — deletes the draft JSON (caller deletes via
///     `NewsProjectStore.delete`) and hides the card.
///   - "Later" — hides the card for this session only; the draft
///     JSON stays untouched.
///
/// The card itself loads nothing — the screen hands it the already
/// loaded [RecoverableDraft], so it pumps cleanly in widget tests
/// (the News Studio home's FutureBuilder over five chained dart:io
/// reads spins forever in widget tests; this card must never be
/// tested through that screen).
library;

import 'package:flutter/material.dart';

import '../../services/project_recovery.dart';

class DraftRecoveryCard extends StatelessWidget {
  const DraftRecoveryCard({
    super.key,
    required this.draft,
    required this.onResume,
    required this.onDiscard,
    required this.onDismiss,
  });

  final RecoverableDraft draft;
  final VoidCallback onResume;
  final VoidCallback onDiscard;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('draftRecoveryCard'),
      color: const Color(0xFF2A1A4A),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Draft in progress — found from autosave',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              draft.summary,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 4),
            const Text(
              'This draft was autosaved — if you resume, the same '
              'you will get the script, clips and voiceover.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    key: const Key('resumeDraftButton'),
                    onPressed: onResume,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                    ),
                    child: const Text('Resume'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('discardDraftButton'),
                  onPressed: onDiscard,
                  child: const Text('Discard'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  key: const Key('dismissDraftButton'),
                  onPressed: onDismiss,
                  child: const Text('Later'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
