/// Project recovery (Phase 9, master prompt §14: autosave + recovery).
///
/// Autosave itself already exists: News Maker and AI News Maker both
/// debounced-autosave the project JSON on every meaningful edit
/// (500 ms, `NewsProjectStore.save` — see those screens). What was
/// missing was the RECOVERY side: nothing ever offered the autosaved
/// draft back. This file is that side.
///
/// Honest scope: the app cannot tell a crash apart from a clean exit
/// (no crash marker is written), so this does NOT claim "interrupted"
/// detection. What it does, really: on the News Studio home, the
/// most recently autosaved project that still has CONTENT (tehreer,
/// headline, clips or a voiceover) is offered as a "Draft jari hai"
/// card — Resume opens it in the News Maker with its actual saved
/// contents, Discard deletes the JSON, Dismiss hides it for this
/// session only. An empty project (nothing typed yet) is never
/// offered — there is nothing to recover.
///
/// [findRecoverableDraft] is pure over an already-loaded project so
/// it is unit-tested without path_provider; the screen loads the
/// project with `NewsProjectStore.loadLatest()`.
library;

import '../news/news_project.dart';

/// A draft worth offering for restore, with a one-line summary for
/// the card (the draft's ACTUAL contents, not a placeholder).
class RecoverableDraft {
  const RecoverableDraft({
    required this.project,
    required this.summary,
  });

  final NewsProject project;

  /// e.g. "Sheikhupura khabar • 3 clips • voiceover • 2 ghante pehle".
  final String summary;
}

/// True when [project] has anything worth recovering. Null-safe:
/// null means "no project at all".
bool isRecoverableDraft(NewsProject? project) {
  if (project == null) return false;
  return project.tehreer.trim().isNotEmpty ||
      project.headline.trim().isNotEmpty ||
      project.title.trim().isNotEmpty ||
      project.clipPaths.isNotEmpty ||
      project.voiceoverPath != null ||
      project.subtitles.isNotEmpty;
}

/// Builds the recoverable draft for [project], or null when there is
/// nothing to recover. [now] is a test seam (defaults to now).
RecoverableDraft? findRecoverableDraft(
  NewsProject? project, {
  DateTime? now,
}) {
  if (!isRecoverableDraft(project)) return null;
  final p = project!;
  final parts = <String>[];
  final title = p.headline.trim().isNotEmpty
      ? p.headline.trim()
      : (p.title.trim().isNotEmpty ? p.title.trim() : 'Untitled draft');
  parts.add(title);
  if (p.clipPaths.isNotEmpty) {
    parts.add(
      '${p.clipPaths.length} clip${p.clipPaths.length == 1 ? '' : 's'}',
    );
  }
  if (p.voiceoverPath != null) parts.add('voiceover');
  if (p.subtitles.isNotEmpty) {
    parts.add('${p.subtitles.length} subtitles');
  }
  final current = now ?? DateTime.now();
  final age = current.difference(p.updatedAt);
  parts.add(_ageLabel(age));
  return RecoverableDraft(project: p, summary: parts.join(' • '));
}

String _ageLabel(Duration age) {
  if (age.inMinutes < 1) return 'abhi';
  if (age.inMinutes < 60) return '${age.inMinutes} min pehle';
  if (age.inHours < 24) return '${age.inHours} ghante pehle';
  return '${age.inDays} din pehle';
}
