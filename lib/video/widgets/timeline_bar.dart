/// Timeline bar of the Video Editor (Master Plan Phase 4 split).
///
/// Was `_timelineBar` + helpers inside the panels extension on the
/// editor State; now a real widget in its own file. All editor state
/// is reached through [VideoEditorController] — behaviour unchanged.
library;

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../theme.dart';
import '../editor_models.dart';
import '../editor_stage.dart';
import '../video_editor_controller.dart';

/// The editor's timeline: contextual hint, ruler + clip lanes with
/// the centred playhead, and the transport-adjacent zoom controls.
class TimelineBar extends StatelessWidget {
  final VideoEditorController host;
  const TimelineBar(this.host, {super.key});

  /// v1.5.0 TIMELINE (mockups V1/V2, replacing _timelineSection +
  /// _timelineCard): contextual yellow hint → the centred-playhead
  /// strip (fixed red + column at left with Mute under it, ruler
  /// labels every 2s, REAL filmstrip thumbnails, gold selection,
  /// trim handles on the selected block, transition badges on the
  /// boundaries, long-press swap) → PIP lane → audio lane → text
  /// lane → times row (current centred / total right — BOTH from
  /// the one TimelineClock model, #5/#30).
  @override
  Widget build(BuildContext context) {
    final total = host.totalDurationSec;
    // Phase 2: kick off the music waveform render (cached; the
    // audio lane paints it as its background when it lands).
    final mp = host.musicPath;
    if (mp != null && !host.musicWaveCache.containsKey(mp)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (host.mounted) unawaited(host.ensureMusicWave(mp));
      });
    }
    final wavePath = mp == null ? null : host.musicWaveCache[mp];
    return Container(
      color: TjProTheme.surfaceDeep,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  host.elementRow && host.fxPip
                      ? 'PIP element selected — use Switch to return to the main track.'
                      : host.clipRow && host.clips.isNotEmpty
                          ? 'Long press to swap'
                          : 'Select one track to edit.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFFFD60A),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // v1.14.0 T1 (A20): TIMELINE snap quick toggle —
              // tap = on/off, long-press = strength cycles
              // (Halki → Normal → Mazboot). The full settings
              // (switch + strength chips) also live in the Trim
              // panel's Timeline section.
              InkWell(
                key: const Key('tlSnapToggle'),
                onTap: () => host.update(() {
                  host.tlSnapOn = !host.tlSnapOn;
                  host.setStatus(host.tlSnapOn
                      ? 'Snap ON — the playhead and trim handles '
                          'boundary/beat/marker par chipkenge.'
                      : 'Snap OFF — the playhead and trim are completely '
                          'will move freely.');
                }),
                onLongPress: () => host.update(() {
                  host.tlSnapStrength = (host.tlSnapStrength + 1) % 3;
                  host.tlSnapOn = true;
                  host.setStatus(
                    'Snap ki taqat: ${host.tlSnapStrength == 0 ? 'Light' : host.tlSnapStrength == 2 ? 'Mazboot' : 'Normal'}.',
                  );
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.anchor,
                        size: 13,
                        color: host.tlSnapOn
                            ? TjProTheme.gold
                            : Colors.white38,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        host.tlSnapOn
                            ? (host.tlSnapStrength == 0
                                ? 'Snap·H'
                                : host.tlSnapStrength == 2
                                    ? 'Snap·M'
                                    : 'Snap')
                            : 'Snap',
                        style: TextStyle(
                          color: host.tlSnapOn
                              ? TjProTheme.gold
                              : Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // v1.14.0 T1 (A14): timecode readout toggle.
              InkWell(
                key: const Key('tlTcToggle'),
                onTap: () => host.update(() {
                  host.timecodeOn = !host.timecodeOn;
                  host.setStatus(host.timecodeOn
                      ? 'Timecode ON — time in H:MM:SS:FF '
                          'dikhe ga.'
                      : 'Timecode OFF — time will show in m:ss.');
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    'TC',
                    style: TextStyle(
                      color: host.timecodeOn
                          ? TjProTheme.gold
                          : Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              // v1.14.0 T3 (A4): multi-select mode toggle.
              InkWell(
                key: const Key('tlMultiToggle'),
                onTap: () => host.update(() {
                  host.multiMode = !host.multiMode;
                  if (!host.multiMode) host.clearMultiSelect();
                  host.setStatus(host.multiMode
                      ? 'Multi-select ON — tap clips to '
                          'choose many clips.'
                      : 'Multi-select OFF.');
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.checklist,
                        size: 14,
                        color: host.multiMode
                            ? TjProTheme.gold
                            : Colors.white38,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'Multi',
                        style: TextStyle(
                          color: host.multiMode
                              ? TjProTheme.gold
                              : Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Main-track lock (Phase 2): while locked, the
              // timeline's trim handles and reorder are disabled
              // (selection, playback and the panels still work).
              InkWell(
                onTap: () =>
                    host.update(() => host.mainTrackLocked = !host.mainTrackLocked),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        host.mainTrackLocked ? Icons.lock : Icons.lock_open,
                        size: 14,
                        color: host.mainTrackLocked
                            ? TjProTheme.gold
                            : Colors.white54,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Video lock',
                        style: TextStyle(
                          color: host.mainTrackLocked
                              ? TjProTheme.gold
                              : Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // v1.14.0 T3 (A4): the multi-select action bar —
          // shown only in multi mode. Batch delete / duplicate /
          // move run on every ticked clip in ONE history step.
          if (host.multiMode)
            Container(
              key: const Key('tlMultiBar'),
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF22303C),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Text(
                    '${host.multiSelect.length} select',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    key: const Key('tlMultiMoveLeft'),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Move back',
                    onPressed: host.multiSelect.isEmpty
                        ? null
                        : () => host.moveMultiSelected(-1),
                    icon: const Icon(Icons.arrow_back,
                        size: 17, color: Colors.white),
                  ),
                  IconButton(
                    key: const Key('tlMultiMoveRight'),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Move forward',
                    onPressed: host.multiSelect.isEmpty
                        ? null
                        : () => host.moveMultiSelected(1),
                    icon: const Icon(Icons.arrow_forward,
                        size: 17, color: Colors.white),
                  ),
                  IconButton(
                    key: const Key('tlMultiDuplicate'),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Duplicate',
                    onPressed: host.multiSelect.isEmpty
                        ? null
                        : host.duplicateMultiSelected,
                    icon: const Icon(Icons.copy,
                        size: 17, color: Colors.white),
                  ),
                  IconButton(
                    key: const Key('tlMultiDelete'),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Delete',
                    onPressed: host.multiSelect.isEmpty
                        ? null
                        : () => unawaited(host.deleteMultiSelected()),
                    icon: const Icon(Icons.delete_outline,
                        size: 17, color: Colors.redAccent),
                  ),
                  IconButton(
                    key: const Key('tlMultiClear'),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Clear selection',
                    onPressed: host.clearMultiSelect,
                    icon: const Icon(Icons.clear,
                        size: 17, color: Colors.white70),
                  ),
                ],
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              // v1.15.0 G1: halfPad MUST equal the centre line's
              // x (TimelineMath.stripLineX) — the old
              // `maxWidth/2 - 52` was 26px short, so Split (and
              // every centre-based action) landed ~0.65s early.
              final halfPad =
                  TimelineMath.stripHalfPad(constraints.maxWidth);
              final contentW = halfPad * 2 + total * host.tlPxPerSec;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fixed left column: red + (add) and, under it,
                  // the selected clip's Mute toggle (InShot's
                  // "Mute Clip" label zone).
                  SizedBox(
                    width: 52,
                    child: Column(
                      children: [
                        Material(
                          color: const Color(0xFFE53935),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: host.busy ? null : () => showAddMediaSheet(host),
                            child: const SizedBox(
                              width: 38,
                              height: 38,
                              child: Icon(
                                Icons.add,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Timeline zoom (Phase 2): − / + scale the
                        // strip around the playhead centre.
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            InkWell(
                              onTap: () => host.tlZoomBy(1 / 1.4),
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(
                                  Icons.remove,
                                  size: 15,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => host.tlZoomBy(1.4),
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(
                                  Icons.add,
                                  size: 15,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // v1.14.0 T1 (A13): zoom-to-fit — the
                        // whole project in one screen.
                        InkWell(
                          key: const Key('tlZoomFit'),
                          onTap: total > 0
                              ? () => host.tlZoomToFit(
                                    constraints.maxWidth - 52,
                                  )
                              : null,
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(
                              Icons.fit_screen,
                              size: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (host.clips.isNotEmpty)
                          InkWell(
                            onTap: () {
                              final clip = host.clips[host.selected];
                              host.update(() => clip.muted = !clip.muted);
                              unawaited(
                                host.controller?.setVolume(
                                      clip.muted ? 0 : clip.volume,
                                    ) ??
                                    Future<void>.value(),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 2,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    host.clips[host.selected].muted
                                        ? Icons.volume_off
                                        : Icons.volume_up,
                                    size: 14,
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(width: 2),
                                  const Text(
                                    'Mute',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            // Build 4 player fix: jumpTo() (playback
                            // follow + zoom) dispatches its own scroll
                            // notifications — they are not user scrubs
                            // and must not touch the player.
                            if (host.tlProgrammaticScroll) return false;
                            if (n is ScrollStartNotification) {
                              host.tlUserScrolling = true;
                            } else if (n is ScrollUpdateNotification) {
                              // Live scrub (Phase 2): the preview
                              // follows the drag (paused only,
                              // debounced in _scheduleScrubSeek).
                              host.scheduleScrubSeek();
                            } else if (n is ScrollEndNotification) {
                              host.tlUserScrolling = false;
                              // Build 4 player fix: while playing, the
                              // strip FOLLOWS the player — a ScrollEnd
                              // here must not seek (the seek-fight loop
                              // that pinned playback at 0:00 on v1.5.5).
                              if (!TimelineMath.scrubSeekOnScrollEnd(
                                isPlaying: host.clock.isPlaying,
                                programmaticScroll:
                                    host.tlProgrammaticScroll,
                              )) {
                                return false;
                              }
                              var centreSec =
                                  host.tlScroll.offset / host.tlPxPerSec;
                              // Snap the resting playhead to a
                              // clip boundary when it lands close
                              // (Phase 2), with a light tick.
                              // A1 (v1.12): beats + manual markers
                              // are snap targets too. v1.14 T1
                              // (A20): the threshold is the user's
                              // snap setting — 0 = snap OFF, no
                              // snapping at all.
                              final snapThresh =
                                  host.tlSnapThreshold(false);
                              if (snapThresh > 0) {
                                final snapped = TimelineMath.snapSec(
                                  centreSec,
                                  [
                                    ...TimelineMath.boundaries(
                                      host.effectiveDurations,
                                    ),
                                    ...host.timelineBeats,
                                    ...host.markers,
                                  ],
                                  snapThresh,
                                );
                                if (snapped != centreSec) {
                                  centreSec = snapped;
                                  HapticFeedback.selectionClick();
                                }
                              }
                              unawaited(host.seekToGlobalSec(centreSec));
                            }
                            return false;
                          },
                          child: _PinchZoomStrip(
                            host: host,
                            child: SingleChildScrollView(
                            controller: host.tlScroll,
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: contentW,
                              height: 74,
                              child: Stack(
                                children: [
                                  // v1.14 T3 (A5): the marked
                                  // range — a gold wash over the
                                  // strip between In and Out,
                                  // with edge lines. Drawn under
                                  // the blocks so the filmstrips
                                  // stay readable.
                                  if (host.rangeIn != null &&
                                      host.rangeOut != null &&
                                      host.rangeOut! > host.rangeIn!)
                                    Positioned(
                                      key: const Key('tlRangeBand'),
                                      left: halfPad +
                                          host.rangeIn! * host.tlPxPerSec,
                                      width: (host.rangeOut! -
                                              host.rangeIn!) *
                                          host.tlPxPerSec,
                                      top: 11,
                                      bottom: 0,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: TjProTheme.gold
                                              .withValues(alpha: 0.13),
                                          border: const Border(
                                            left: BorderSide(
                                              color: TjProTheme.gold,
                                              width: 1.5,
                                            ),
                                            right: BorderSide(
                                              color: TjProTheme.gold,
                                              width: 1.5,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  // Ruler labels — v1.14 T1
                                  // (A14): the step adapts to the
                                  // zoom (the old fixed 2 s was
                                  // unreadable zoomed out and
                                  // sparse zoomed in).
                                  for (var s = 0.0;
                                      s <= total + 0.001;
                                      s += TimelineMath.rulerStepSec(
                                        host.tlPxPerSec,
                                      ))
                                    Positioned(
                                      left: halfPad + s * host.tlPxPerSec - 8,
                                      top: 0,
                                      child: Text(
                                        _rulerLabel(
                                          s,
                                          TimelineMath.rulerStepSec(
                                            host.tlPxPerSec,
                                          ),
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ),
                                  // A1 (v1.12): beat ticks in the
                                  // ruler band — the detected beats,
                                  // mapped onto the timeline by
                                  // host.timelineBeats (music = 0
                                  // offset; a clip's beats shift by
                                  // its start + trim).
                                  for (final t in host.timelineBeats)
                                    Positioned(
                                      left: halfPad +
                                          t * host.tlPxPerSec -
                                          0.75,
                                      top: 2,
                                      child: Container(
                                        width: 1.5,
                                        height: 9,
                                        color: Colors.white38,
                                      ),
                                    ),
                                  // A1 (v1.12): manual markers —
                                  // a gold flag on the ruler and a
                                  // thin gold line down the strip.
                                  for (final t in host.markers) ...[
                                    Positioned(
                                      left: halfPad +
                                          t * host.tlPxPerSec -
                                          0.75,
                                      top: 11,
                                      bottom: 0,
                                      child: Container(
                                        width: 1.5,
                                        color: TjProTheme.gold
                                            .withValues(alpha: 0.55),
                                      ),
                                    ),
                                    Positioned(
                                      left: halfPad +
                                          t * host.tlPxPerSec -
                                          4,
                                      top: 0,
                                      child: Icon(
                                        Icons.bookmark,
                                        size: 9,
                                        color: TjProTheme.gold,
                                      ),
                                    ),
                                  ],
                                  // Clip blocks.
                                  for (var i = 0;
                                      i < host.clips.length;
                                      i++)
                                    _timelineClipBlock(
                                      i,
                                      left: halfPad +
                                          host.clipStartSec(i) * host.tlPxPerSec,
                                    ),
                                  // Transition badges.
                                  for (var i = 1;
                                      i < host.clips.length;
                                      i++)
                                    Positioned(
                                      left: halfPad +
                                          host.clipStartSec(i) * host.tlPxPerSec -
                                          11,
                                      top: 26,
                                      child: GestureDetector(
                                        onTap: () =>
                                            host.openTool('transitions'),
                                        child: Container(
                                          width: 22,
                                          height: 22,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius:
                                                BorderRadius.circular(5),
                                          ),
                                          child: Icon(
                                            host.crossfade
                                                ? Icons.swap_horiz
                                                : Icons.add,
                                            size: 14,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            ),
                          ),
                        ),
                        // FIXED centre playhead.
                        Positioned(
                          left: TimelineMath.stripLineX(
                              constraints.maxWidth),
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: 2,
                            color: const Color(0xFFFFD60A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          if (host.fxPip) ...[
            const SizedBox(height: 4),
            _laneRow(
              laneKey: 'pip',
              icon: Icons.picture_in_picture_alt,
              label: 'PIP',
              // v1.16.0 G3 (A3): the PIP lane lock — while locked
              // the window cannot be dragged and the PIP timing
              // controls are disabled (accidental-change guard).
              laneAction: InkWell(
                key: const Key('pipLaneLock'),
                onTap: () => host.update(
                    () => host.pipLaneLocked = !host.pipLaneLocked),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    host.pipLaneLocked ? Icons.lock : Icons.lock_open,
                    size: 13,
                    color: host.pipLaneLocked
                        ? TjProTheme.gold
                        : Colors.white54,
                  ),
                ),
              ),
              child: LayoutBuilder(
              builder: (context, laneConstraints) {
                // v1.16.0 G2 (Motion M3): the PIP lane shows the
                // inset's WINDOW as a segment of the timeline —
                // drag it sideways to move the window (length
                // preserved); trim it in the PIP panel. A full
                // window renders exactly like the old full bar.
                final total = host.totalDurationSec;
                final laneW = laneConstraints.maxWidth;
                final pxPerSec =
                    (total > 0 && laneW > 0) ? laneW / total : 0.0;
                final w = total > 0
                    ? TimelineMath.pipWindowClamp(
                        start: host.pipStartSec,
                        end: host.pipEndSec,
                        totalDur: total,
                      )
                    : (start: 0.0, end: 0.0);
                final segLeft = w.start * pxPerSec;
                final segWidth = total > 0
                    ? (w.end - w.start) * pxPerSec
                    : laneW;
                return GestureDetector(
                  onTap: () => host.update(() {
                    host.elementRow = true;
                    host.clipRow = false;
                    host.activeTool = null;
                  }),
                  onHorizontalDragUpdate: pxPerSec > 0 && !host.pipLaneLocked
                      ? (d) {
                          final moved = TimelineMath.pipWindowDragged(
                            start: w.start,
                            end: w.end,
                            deltaSec: d.delta.dx / pxPerSec,
                            totalDur: total,
                          );
                          host.update(() {
                            host.pipStartSec = moved.start;
                            host.pipEndSec = moved.end;
                          });
                        }
                      : null,
                  child: Stack(
                    children: [
                      Container(
                        height: 22,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2226),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Positioned(
                        left: segLeft,
                        width: segWidth <= 0 ? laneW : segWidth,
                        child: Container(
                          key: const Key('pipWindowSeg'),
                          height: 22,
                          decoration: BoxDecoration(
                            color: host.elementRow
                                ? const Color(0xFF6A4C00)
                                : const Color(0xFF263238),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          alignment: Alignment.centerLeft,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.picture_in_picture_alt,
                                size: 13,
                                color: Colors.white70,
                              ),
                              SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'PIP element',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            ),
          ],
          const SizedBox(height: 4),
          // Audio lane.
          _laneRow(
            laneKey: 'audio',
            icon: Icons.music_note,
            label: 'Audio',
            // v1.16.0 G3 (A3): the audio lane mute — REAL: the
            // export drops the music entirely while muted.
            laneAction: InkWell(
              key: const Key('audioLaneMute'),
              onTap: () =>
                  host.update(() => host.musicMuted = !host.musicMuted),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  host.musicMuted ? Icons.volume_off : Icons.volume_up,
                  size: 13,
                  color: host.musicMuted
                      ? Colors.redAccent
                      : Colors.white54,
                ),
              ),
            ),
            child: InkWell(
            onTap: () => host.openToolTab('audio', 'music'),
            child: Container(
              height: 22,
              decoration: BoxDecoration(
                color: host.musicPath != null
                    ? const Color(0xFF37474F)
                    : const Color(0xFF222222),
                borderRadius: BorderRadius.circular(4),
                // Phase 2: the music file's waveform as the lane
                // background (plain lane until it renders).
                image: (wavePath != null && wavePath.isNotEmpty)
                    ? DecorationImage(
                        image: FileImage(File(wavePath)),
                        fit: BoxFit.fill,
                        opacity: 0.5,
                      )
                    : null,
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.music_note,
                    size: 13,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      host.musicPath != null
                          ? p.basename(host.musicPath!)
                          : '+ Add audio',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
          const SizedBox(height: 4),
          // Text lane.
          _laneRow(
            laneKey: 'text',
            icon: Icons.text_fields,
            label: 'Text',
            child: InkWell(
            onTap: () => host.openTool('text'),
            child: Container(
              height: 22,
              decoration: BoxDecoration(
                color: host.text.trim().isNotEmpty
                    ? const Color(0xFF37474F)
                    : const Color(0xFF222222),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.text_fields,
                    size: 13,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      host.text.trim().isNotEmpty
                          ? host.text.trim()
                          : host.captions.isNotEmpty
                              ? '${host.captions.length} captions'
                              : '+ Add text',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
          // v1.16.0 G4 (A18): the captions lane — every caption
          // as a strip at its timeline span (the export's own
          // mapping, TimelineMath.captionStripSpans). Tapping a
          // strip seeks to it and opens the editor on it. Shown
          // only when captions exist.
          if (host.captions.isNotEmpty) ...[
            const SizedBox(height: 4),
            _laneRow(
              laneKey: 'captions',
              icon: Icons.closed_caption,
              label: 'CC',
              child: LayoutBuilder(
                builder: (context, c) {
                  final total = host.totalDurationSec;
                  final spans = TimelineMath.captionStripSpans(
                    segments: [
                      for (final s in host.captions)
                        (start: s.start, end: s.end),
                    ],
                    timelineRelative: host.captionsTimelineRelative,
                    selectedClipStart: host.clips.isEmpty
                        ? 0
                        : host.clipStartSec(host.selected),
                    totalDur: total,
                  );
                  return Stack(
                    children: [
                      Container(
                        height: 22,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      for (var i = 0; i < spans.length; i++)
                        Positioned(
                          left: total > 0
                              ? (spans[i].start / total * c.maxWidth)
                                  .clamp(0.0, c.maxWidth - 10)
                              : 0,
                          width: total > 0
                              ? ((spans[i].end - spans[i].start) /
                                      total *
                                      c.maxWidth)
                                  .clamp(10.0, c.maxWidth)
                              : c.maxWidth,
                          child: GestureDetector(
                            onTap: () =>
                                unawaited(host.editCaptionAt(i)),
                            child: Container(
                              key: Key('captionStrip-$i'),
                              height: 22,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4A3F00),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: TjProTheme.gold
                                        .withValues(alpha: 0.5)),
                              ),
                              alignment: Alignment.centerLeft,
                              child: Text(
                                host.captions[i].text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
          // Build 3 (Phase 3): the Keyframes lane — ◆ points at
          // each active track's keyframe times (gold = title /
          // sticker track, cyan = PIP track; both tracks span the
          // whole timeline in v1, so the points sit at the two
          // ends, top row = title, bottom row = PIP). Shown only
          // while a keyframe track is on; tapping opens the
          // Animation panel.
          if ((host.proKeyframes &&
                  (host.proTitle.trim().isNotEmpty ||
                      host.proSticker.trim().isNotEmpty)) ||
              (host.pipKeyframes && host.fxPip)) ...[
            const SizedBox(height: 4),
            _laneRow(
              laneKey: 'keyframes',
              icon: Icons.animation,
              label: 'Keys',
              child: InkWell(
                onTap: () => host.openToolTab('overlay', 'keyframes'),
                child: Container(
                  height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xFF222222),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      Widget diamond(double frac, double top, Color color) =>
                          Positioned(
                            left: (frac * c.maxWidth).clamp(
                              0.0,
                              c.maxWidth - 10,
                            ),
                            top: top,
                            child: Transform.rotate(
                              angle: 0.7853981633974483,
                              child: Container(
                                width: 9,
                                height: 9,
                                color: color,
                              ),
                            ),
                          );
                      final titleTrack = host.proKeyframes &&
                          (host.proTitle.trim().isNotEmpty ||
                              host.proSticker.trim().isNotEmpty);
                      final pipTrack = host.pipKeyframes && host.fxPip;
                      return Stack(
                        children: [
                          if (titleTrack) ...[
                            diamond(0, 2, TjProTheme.gold),
                            diamond(1, 2, TjProTheme.gold),
                          ],
                          if (pipTrack) ...[
                            diamond(0, 11, Colors.cyanAccent),
                            diamond(1, 11, Colors.cyanAccent),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 4),
          // Times row — current centred, total right, both from
          // the ONE clock/model (#5).
          // v1.15.0 G1.6: the CENTRE label shows the second that
          // is actually under the fixed centre line (strip scroll
          // offset / pxPerSec) — the old label showed the preview
          // CLOCK position while claiming to be the centred one,
          // so the user could not verify where a Split would land.
          // It now also rebuilds on scroll, not just on the clock.
          AnimatedBuilder(
            animation: Listenable.merge([host.clock, host.tlScroll]),
            builder: (context, _) {
              String fmtT(double sec) {
                // v1.14 T1 (A14): timecode mode shows
                // H:MM:SS:FF at the export fps.
                if (host.timecodeOn) {
                  return TimelineMath.formatTimecode(sec, host.exportFps);
                }
                final m = sec ~/ 60;
                final s = (sec % 60).floor().toString().padLeft(2, '0');
                return '$m:$s';
              }

              final centreSec = host.tlScroll.hasClients &&
                      host.tlPxPerSec > 0
                  ? (host.tlScroll.offset / host.tlPxPerSec)
                      .clamp(0.0, total)
                      .toDouble()
                  : host.globalPositionSec;

              return SizedBox(
                height: 16,
                child: Stack(
                  children: [
                    Center(
                      child: Text(
                        fmtT(centreSec),
                        key: const Key('tlTimeCentre'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        fmtT(total),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Formal track header (Phase 2): every lane gets the same
  /// 52-wide label cell (icon + name + show/hide eye) aligned with
  /// the strip's fixed column, turning the summary lanes into
  /// named tracks. Hiding collapses the lane to a slim strip; the
  /// lane's content and taps return when it is shown again.
  Widget _laneRow({
    required String laneKey,
    required IconData icon,
    required String label,
    required Widget child,
    // v1.16.0 G3 (A3): an optional REAL lane control (audio
    // mute / PIP lock) shown before the row's eye toggle.
    Widget? laneAction,
  }) {
    final hidden = host.laneHidden.contains(laneKey);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 52,
          child: Row(
            children: [
              Icon(icon, size: 12, color: Colors.white54),
              const SizedBox(width: 2),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 9,
                  ),
                ),
              ),
              ?laneAction,
              InkWell(
                onTap: () => host.update(() {
                  if (hidden) {
                    host.laneHidden.remove(laneKey);
                  } else {
                    host.laneHidden.add(laneKey);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    hidden ? Icons.visibility_off : Icons.visibility,
                    size: 13,
                    color: Colors.white54,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: hidden
              ? Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B1B1B),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '$label hidden',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 9,
                    ),
                  ),
                )
              : child,
        ),
      ],
    );
  }

  /// One filmstrip block on the new timeline: real thumbnails
  /// (photo clips show themselves), gold border when selected,
  /// trim handles on the selected block, tap = select + preview,
  /// long-press = the swap sheet ("Long press to swap").
  /// v1.16.0 G4 (A16): the clip block's waveform strip — kicks
  /// off the (cached, once-only) render and paints the PNG when
  /// it exists. No audio stream / still rendering = no strip.
  Widget _clipWaveOverlay(VideoClip clip) {
    host.ensureClipWave(clip);
    final path = host.clipWaveCache[host.clipWaveKey(clip)];
    if (path == null || path.isEmpty) return const SizedBox.shrink();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 15,
      child: Opacity(
        opacity: clip.muted || clip.disabled ? 0.3 : 0.75,
        child: Image.file(
          File(path),
          fit: BoxFit.fill,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _timelineClipBlock(int i, {required double left}) {
    final clip = host.clips[i];
    final w = clip.effectiveDuration * host.tlPxPerSec;
    final selected = i == host.selected;
    final inMulti = host.multiSelect.contains(i);
    final thumbs = host.thumbCache[host.thumbKey(clip)];
    // v1.14 T2 (A7): in Slip mode the SELECTED block's body
    // drag slips its window — the long-press reorder stands
    // down for that block so the drag is unambiguous.
    final slipBlock = host.trimMode == 'slip' &&
        selected &&
        !host.mainTrackLocked &&
        !clip.isPhoto;
    return Positioned(
      // Keyed by the clip OBJECT so a drag-reorder moves the
      // block's element (and its live gesture) with the clip.
      key: ObjectKey(clip),
      left: left,
      top: 14,
      width: w,
      height: 56,
      child: GestureDetector(
        onTap: () {
          // v1.14 T3 (A4): in multi mode a tap TICKS the clip
          // instead of selecting it alone.
          if (host.multiMode) {
            host.toggleMultiSelect(i);
            return;
          }
          host.update(() {
            host.selected = i;
            host.clipRow = true;
            host.elementRow = false;
          });
          unawaited(host.loadPreview());
        },
        // Long press: drag = live reorder (Phase 2); a stationary
        // press still opens the swap sheet (the original path).
        // Locked track: no reorder at all.
        onLongPressStart: host.mainTrackLocked || slipBlock
            ? null
            : (_) => host.onClipDragStart(i),
        onLongPressMoveUpdate:
            host.mainTrackLocked || slipBlock ? null : host.onClipDragMove,
        onLongPressEnd: host.mainTrackLocked || slipBlock
            ? null
            : (_) => host.onClipDragEnd(i),
        // v1.14 T2 (A7): Slip — drag the selected block to slide
        // the used window inside its file (position + length
        // unchanged). The math is TimelineMath.slipEdit, applied
        // incrementally like the trim handles.
        onHorizontalDragUpdate: slipBlock
            ? (d) {
                final res = TimelineMath.slipEdit(
                  trimStart: clip.trimStart,
                  effEnd: clip.effectiveEnd,
                  full: clip.duration.inMilliseconds / 1000,
                  delta: d.delta.dx / host.tlPxPerSec,
                );
                if (res != null) {
                  host.update(() {
                    clip.trimStart = res.start;
                    clip.trimEnd = res.end;
                  });
                }
              }
            : null,
        onHorizontalDragEnd: slipBlock
            ? (_) {
                host.pushHistory();
                unawaited(host.loadPreview());
              }
            : null,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: selected
                  ? TjProTheme.gold
                  : inMulti
                      ? Colors.cyanAccent
                      : Colors.white24,
              width: selected || inMulti ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(4),
            color: const Color(0xFF2A2A2A),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned.fill(
                child: thumbs == null || thumbs.isEmpty
                    ? const Center(
                        child: Icon(
                          Icons.movie,
                          color: Colors.white38,
                          size: 18,
                        ),
                      )
                    : Row(
                        children: [
                          for (var k = 0; k < 24; k++)
                            Expanded(
                              child: Image.file(
                                File(thumbs[k % thumbs.length]),
                                fit: BoxFit.cover,
                                height: 56,
                                errorBuilder: (_, _, _) =>
                                    const ColoredBox(
                                  color: Color(0xFF2A2A2A),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              // v1.16.0 G4 (A16): the clip's real audio
              // waveform along the block's bottom (trimmed
              // range; rendered once, cached — see
              // host.ensureClipWave).
              if (!clip.isPhoto) _clipWaveOverlay(clip),
              if (clip.isPhoto)
                const Positioned(
                  left: 3,
                  top: 3,
                  child: Icon(
                    Icons.photo,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              // v1.16.0 G3 (C3): the colour label strip.
              if (clip.colorLabel > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Container(
                    key: Key('tlClipLabel-$i'),
                    height: 4,
                    color: Color(TimelineMath.clipLabelArgb[
                        TimelineMath.clipLabelClamp(clip.colorLabel)]),
                  ),
                ),
              // v1.16.0 G3 (A23): a disabled clip is veiled —
              // its space stays, its picture is gone (the same
              // in the preview and the export).
              if (clip.disabled)
                Positioned.fill(
                  child: Container(
                    key: Key('tlClipDisabled-$i'),
                    color: Colors.black.withValues(alpha: 0.62),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.white38),
                      ),
                      child: const Text(
                        'OFF',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              // v1.16.0 G3 (A22): state badges from the clip's
              // REAL state (TimelineMath.clipBadgeKeys) — mute,
              // changed volume, trimmed, audio unlinked.
              if (TimelineMath.clipBadgeKeys(
                    isPhoto: clip.isPhoto,
                    muted: clip.muted,
                    volume: clip.volume,
                    trimStart: clip.trimStart,
                    trimEnd: clip.trimEnd,
                    hasDetachedAudio: clip.detachedAudioPath != null,
                    disabled: clip.disabled,
                  )
                  .any((b) => b != 'photo' && b != 'off'))
                Positioned(
                  left: 3,
                  bottom: 3,
                  child: Row(
                    key: Key('tlClipBadges-$i'),
                    children: [
                      for (final b in TimelineMath.clipBadgeKeys(
                        isPhoto: clip.isPhoto,
                        muted: clip.muted,
                        volume: clip.volume,
                        trimStart: clip.trimStart,
                        trimEnd: clip.trimEnd,
                        hasDetachedAudio:
                            clip.detachedAudioPath != null,
                        disabled: clip.disabled,
                      ))
                        if (b != 'photo' && b != 'off')
                          Container(
                            margin: const EdgeInsets.only(right: 2),
                            padding: const EdgeInsets.all(1.5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(2.5),
                            ),
                            child: Icon(
                              switch (b) {
                                'mute' => Icons.volume_off,
                                'vol' => Icons.volume_up,
                                'trim' => Icons.content_cut,
                                _ => Icons.link_off,
                              },
                              size: 9,
                              color: Colors.white,
                            ),
                          ),
                    ],
                  ),
                ),
              // v1.14 T3 (A4): the multi-select tick.
              if (inMulti)
                Positioned(
                  right: 3,
                  top: 3,
                  child: Container(
                    key: Key('tlMultiTick-$i'),
                    decoration: const BoxDecoration(
                      color: Colors.cyanAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 12,
                      color: Colors.black,
                    ),
                  ),
                ),
              if (selected && !host.mainTrackLocked) ...[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: 14,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) {
                      // v1.14 T2 (A6): in Roll mode this handle
                      // moves the boundary WITH the previous
                      // clip (TimelineMath.rollEdit) — the pair's
                      // total length never changes.
                      if (host.trimMode == 'roll') {
                        if (i <= 0) return;
                        final a = host.clips[i - 1];
                        final res = TimelineMath.rollEdit(
                          aTrimStart: a.trimStart,
                          aEffEnd: a.effectiveEnd,
                          aFull: a.duration.inMilliseconds / 1000,
                          bTrimStart: clip.trimStart,
                          bEffEnd: clip.effectiveEnd,
                          delta: d.delta.dx / host.tlPxPerSec,
                        );
                        if (res != null) {
                          host.update(() {
                            a.trimEnd = res.aEnd;
                            clip.trimStart = res.bStart;
                          });
                        }
                        return;
                      }
                      host.update(() {
                        var v = (clip.trimStart +
                                d.delta.dx / host.tlPxPerSec)
                            .clamp(0, clip.effectiveEnd - 0.3)
                            .toDouble();
                        // Snap to the clip's true start (Phase 2),
                        // one haptic tick per engagement.
                        // A1 (v1.12): beats + markers inside this
                        // clip are targets too, converted to the
                        // handle's file-second domain. v1.14 T1
                        // (A20): the threshold is the user's snap
                        // setting — 0 = no snapping at all.
                        final thresh = host.tlSnapThreshold(true);
                        if (thresh > 0) {
                          final snapped = TimelineMath.snapSec(
                            v,
                            [
                              0.0,
                              ...TimelineMath.trimSnapFilePoints(
                                clipStart: host.clipStartSec(i),
                                trimStart: clip.trimStart,
                                effectiveDuration: clip.effectiveDuration,
                                timelinePoints: [
                                  ...host.timelineBeats,
                                  ...host.markers,
                                ],
                              ),
                            ],
                            thresh,
                          );
                          if (snapped != v) {
                            if (!host.trimSnapped) {
                              host.trimSnapped = true;
                              HapticFeedback.selectionClick();
                            }
                            v = snapped;
                          } else {
                            host.trimSnapped = false;
                          }
                        }
                        clip.trimStart = v;
                      });
                    },
                    onHorizontalDragEnd: (_) {
                      host.trimSnapped = false;
                      host.pushHistory();
                      if (host.trimMode == 'roll') {
                        if (i <= 0) {
                          host.setStatus('Before the first clip, no '
                              'no boundary — roll is not possible.');
                        } else {
                          unawaited(host.loadPreview());
                        }
                      }
                    },
                    child: Container(
                      color: TjProTheme.gold.withValues(alpha: 0.85),
                      child: Icon(
                        host.trimMode == 'roll'
                            ? Icons.swap_horiz
                            : Icons.chevron_left,
                        size: 12,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 14,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) {
                      // v1.14 T2 (A6): in Roll mode this handle
                      // moves the boundary WITH the next clip.
                      if (host.trimMode == 'roll') {
                        if (i >= host.clips.length - 1) return;
                        final b = host.clips[i + 1];
                        final res = TimelineMath.rollEdit(
                          aTrimStart: clip.trimStart,
                          aEffEnd: clip.effectiveEnd,
                          aFull: clip.duration.inMilliseconds / 1000,
                          bTrimStart: b.trimStart,
                          bEffEnd: b.effectiveEnd,
                          delta: d.delta.dx / host.tlPxPerSec,
                        );
                        if (res != null) {
                          host.update(() {
                            clip.trimEnd = res.aEnd;
                            b.trimStart = res.bStart;
                          });
                        }
                        return;
                      }
                      host.update(() {
                        final full = clip.duration.inMilliseconds / 1000;
                        var v = (clip.effectiveEnd +
                                d.delta.dx / host.tlPxPerSec)
                            .clamp(clip.trimStart + 0.3, full);
                        // Snap to the clip's true end (Phase 2).
                        // A1 (v1.12): beats + markers inside this
                        // clip are targets too (file-second domain).
                        // v1.14 T1 (A20): the threshold is the
                        // user's snap setting — 0 = no snapping.
                        final thresh = host.tlSnapThreshold(true);
                        if (thresh > 0) {
                          final snapped = TimelineMath.snapSec(
                            v,
                            [
                              full,
                              ...TimelineMath.trimSnapFilePoints(
                                clipStart: host.clipStartSec(i),
                                trimStart: clip.trimStart,
                                effectiveDuration: clip.effectiveDuration,
                                timelinePoints: [
                                  ...host.timelineBeats,
                                  ...host.markers,
                                ],
                              ),
                            ],
                            thresh,
                          );
                          if (snapped != v) {
                            if (!host.trimSnapped) {
                              host.trimSnapped = true;
                              HapticFeedback.selectionClick();
                            }
                            v = snapped;
                          } else {
                            host.trimSnapped = false;
                          }
                        }
                        clip.trimEnd = v;
                      });
                    },
                    onHorizontalDragEnd: (_) {
                      host.trimSnapped = false;
                      host.pushHistory();
                      if (host.trimMode == 'roll') {
                        if (i >= host.clips.length - 1) {
                          host.setStatus('After the last clip, no '
                              'no boundary — roll is not possible.');
                        } else {
                          unawaited(host.loadPreview());
                        }
                      }
                    },
                    child: Container(
                      color: TjProTheme.gold.withValues(alpha: 0.85),
                      child: Icon(
                        host.trimMode == 'roll'
                            ? Icons.swap_horiz
                            : Icons.chevron_right,
                        size: 12,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

  /// v1.14 T1 (A14): one ruler label for second [s] at the
  /// adaptive [step] — sub-second steps keep a decimal, minute
  /// steps switch to m:ss so long timelines stay readable.
  String _rulerLabel(double s, double step) {
    if (step >= 60) {
      final m = s ~/ 60;
      final ss = (s % 60).round().toString().padLeft(2, '0');
      return '$m:$ss';
    }
    if (step < 1) return '${s.toStringAsFixed(1)}s';
    return '${s.toInt()}s';
  }

  /// The add-media sheet behind the timeline's red + button.
  void showAddMediaSheet(VideoEditorController host) {
    showModalBottomSheet<void>(
      context: host.context,
      backgroundColor: TjProTheme.motionPanel,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.videocam, color: Colors.white),
              title: const Text(
                'Add video',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                unawaited(host.addClip());
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo, color: Colors.white),
              title: const Text(
                'Add photo',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetCtx).pop();
                unawaited(host.addPhotoClip());
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Long-press on a clip block: swap it with a neighbour
  /// ("Long press to swap" — the reorder path of the new
  /// timeline).
  void showSwapSheet(VideoEditorController host, int i) {
    showModalBottomSheet<void>(
      context: host.context,
      backgroundColor: TjProTheme.motionPanel,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (i > 0)
              ListTile(
                leading:
                    const Icon(Icons.arrow_back, color: Colors.white),
                title: const Text(
                  'Swap with the previous clip',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  swapClips(host, i, i - 1);
                },
              ),
            if (i < host.clips.length - 1)
              ListTile(
                leading:
                    const Icon(Icons.arrow_forward, color: Colors.white),
                title: const Text(
                  'Swap with the next clip',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(sheetCtx).pop();
                  swapClips(host, i, i + 1);
                },
              ),
          ],
        ),
      ),
    );
  }

  void swapClips(VideoEditorController host, int a, int b) {
    host.pushHistory();
    host.update(() {
      final tmp = host.clips[a];
      host.clips[a] = host.clips[b];
      host.clips[b] = tmp;
      host.selected = b;
    });
    unawaited(host.loadPreview());
  }

/// v1.14.0 T1 (A13): pinch-to-zoom over the timeline strip.
///
/// A [Listener] — NOT a GestureDetector — tracks raw pointers,
/// so it never enters the gesture arena: the strip's scroll,
/// the blocks' taps and the long-press reorder keep exactly
/// their old behaviour. When a SECOND pointer lands, the
/// pointer distance becomes the zoom: the host captures its
/// base px-per-second (tlPinchStart) and every move reports
/// the distance ratio (tlPinchUpdate), which the host turns
/// into a centre-anchored zoom — the same anchor the −/+
/// buttons have always used.
class _PinchZoomStrip extends StatefulWidget {
  const _PinchZoomStrip({required this.host, required this.child});

  final VideoEditorController host;
  final Widget child;

  @override
  State<_PinchZoomStrip> createState() => _PinchZoomStripState();
}

class _PinchZoomStripState extends State<_PinchZoomStrip> {
  final Map<int, Offset> _pointers = {};
  double? _baseDistance;

  double get _distance {
    final pts = _pointers.values.toList();
    if (pts.length < 2) return 0;
    return (pts[0] - pts[1]).distance;
  }

  void _onDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      _baseDistance = _distance;
      widget.host.tlPinchStart();
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    final base = _baseDistance;
    if (_pointers.length == 2 && base != null && base > 0) {
      widget.host.tlPinchUpdate(_distance / base);
    }
  }

  void _onUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.length < 2) _baseDistance = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      child: widget.child,
    );
  }
}
